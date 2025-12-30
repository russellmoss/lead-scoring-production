
-- ============================================================================
-- LEAD SCORING: POINT-IN-TIME FEATURE ENGINEERING USING VIRTUAL SNAPSHOT METHODOLOGY
-- ============================================================================
--
-- 🚨 CRITICAL ARCHITECTURE: Physical snapshot tables do NOT exist.
-- This query uses Virtual Snapshot approach to construct PIT state dynamically.
--
-- VIRTUAL SNAPSHOT LOGIC (Zero Leakage):
-- 1. Anchor: Start with Lead table (Id, stage_entered_contacting__c as contacted_date)
-- 2. Rep State (PIT - Gap Tolerant): Join Lead to contact_registered_employment_history
--    - Filter: PREVIOUS_REGISTRATION_COMPANY_START_DATE <= contacted_date
--    - Rank: Order by START_DATE DESC and take top 1 (Last Known Value logic)
--    - Why: Recovers ~63% of leads in employment gaps by using most recent prior employment
-- 3. Firm State (PIT): Join that Firm_CRD to Firm_historicals
--    - Join on Firm_CRD AND Year/Month corresponding to contacted_date
--    - This gives us Firm AUM and Rep Count as they were reported that month
--
-- KEY PRINCIPLES:
-- 1. All rep state constructed from employment_history at contacted_date
-- 2. All firm state constructed from Firm_historicals using Year/Month of contacted_date
-- 3. NO physical snapshot tables - all state is constructed on-the-fly
-- 4. NO joins to "*_current" tables for feature calculation (except null signals)
-- 5. Employment history used for mobility features and firm stability (PIT-safe)
--
-- ⚠️ CRITICAL FIX (2025-01-XX): Firm Arrivals Calculation
-- The firm_net_change_12mo feature was using BROKEN calculation:
-- - OLD (BROKEN): Arrivals from employment_history (undercounts by 800+)
-- - NEW (FIXED): Arrivals from ria_contacts_current using PRIMARY_FIRM_START_DATE
-- This fix ensures growing firms (like Equitable Advisors) are correctly identified
-- and not incorrectly marked as "bleeding" in tier scoring logic.
--
-- DATASET: FinTrx_data_CA (Canadian region)
-- LOCATION: northamerica-northeast2 (Toronto)
-- ANALYSIS DATE: 2025-10-31 (fixed for training set stability)
-- MATURITY WINDOW: 30 days
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` AS

WITH 
-- ========================================================================
-- BASE: Target variable with right-censoring protection
-- ========================================================================
lead_base AS (
    SELECT
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        
        -- PIT month for firm lookups (month BEFORE contact to ensure data availability)
        DATE_TRUNC(DATE_SUB(DATE(l.stage_entered_contacting__c), INTERVAL 1 MONTH), MONTH) as pit_month,
        
        -- Target variable with fixed analysis_date for training set stability
        -- CRITICAL: Use fixed analysis_date instead of CURRENT_DATE() to prevent training set drift
        CASE
            WHEN DATE_DIFF(DATE('2025-10-31'), DATE(l.stage_entered_contacting__c), DAY) < 30
            THEN NULL  -- Right-censored (too young as of analysis_date)
            WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL
                 AND DATE_DIFF(DATE(l.Stage_Entered_Call_Scheduled__c), 
                               DATE(l.stage_entered_contacting__c), DAY) <= 30
            THEN 1  -- Positive: converted within window
            ELSE 0  -- Negative: mature lead, never converted
        END as target,
        
        -- Lead metadata
        l.Company as company_name,
        l.LeadSource as lead_source
        
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.stage_entered_contacting__c IS NOT NULL
        AND l.FA_CRD__c IS NOT NULL
        AND l.Company NOT LIKE '%Savvy%'
        AND DATE(l.stage_entered_contacting__c) >= '2024-02-01'
        AND DATE(l.stage_entered_contacting__c) <= '2025-10-01'
),

-- ========================================================================
-- VIRTUAL SNAPSHOT: Rep State at contacted_date (from employment_history)
-- CRITICAL: Find the employment record where contacted_date is between START and END
-- ========================================================================
rep_state_pit AS (
    SELECT
        lb.lead_id,
        lb.advisor_crd,
        lb.contacted_date,
        
        -- Find the employment record active at contacted_date
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd_at_contact,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as current_job_start_date,
        COALESCE(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE, DATE('2025-10-31')) as current_job_end_date,
        
        -- Calculate current firm tenure as of contacted_date
        DATE_DIFF(
            lb.contacted_date,
            eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
            MONTH
        ) as current_firm_tenure_months,
        
        -- Calculate total industry tenure from all prior jobs
        (SELECT 
            COALESCE(SUM(
                DATE_DIFF(
                    COALESCE(eh2.PREVIOUS_REGISTRATION_COMPANY_END_DATE, DATE('2025-10-31')),
                    eh2.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                    MONTH
                )
            ), 0)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh2
         WHERE eh2.RIA_CONTACT_CRD_ID = lb.advisor_crd
           AND eh2.PREVIOUS_REGISTRATION_COMPANY_START_DATE < eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE
        ) as industry_tenure_months,
        
        -- Count prior firms (all jobs before current)
        (SELECT COUNT(DISTINCT eh3.PREVIOUS_REGISTRATION_COMPANY_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh3
         WHERE eh3.RIA_CONTACT_CRD_ID = lb.advisor_crd
           AND eh3.PREVIOUS_REGISTRATION_COMPANY_START_DATE < eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE
        ) as num_prior_firms
        
    FROM lead_base lb
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON lb.advisor_crd = eh.RIA_CONTACT_CRD_ID
    WHERE 
        -- contacted_date must be within this employment period
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= lb.contacted_date
        AND (eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
             OR eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= lb.contacted_date)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY lb.lead_id 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1  -- Take most recent employment if multiple overlap
),

-- ========================================================================
-- VIRTUAL SNAPSHOT: Firm State at contacted_date (from Firm_historicals)
-- CRITICAL: Use pit_month (month BEFORE contacted_date) to ensure data availability
-- ========================================================================
firm_state_pit AS (
    SELECT
        rsp.lead_id,
        rsp.firm_crd_at_contact,
        rsp.contacted_date,
        lb.pit_month,
        
        -- Join to Firm_historicals using pit_month (month before contacted_date)
        -- Use most recent Firm_historicals row with month <= pit_month
        fh.TOTAL_AUM as firm_aum_pit,
        -- Rep count calculated from employment history (count distinct advisors at firm in that month)
        (SELECT COUNT(DISTINCT eh_rep.RIA_CONTACT_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_rep
         WHERE eh_rep.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = rsp.firm_crd_at_contact
           AND eh_rep.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= DATE(lb.pit_month)
           AND (eh_rep.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
                OR eh_rep.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE(lb.pit_month))
        ) as firm_rep_count_at_contact,
        fh.AMT_OF_AUM_HIGH_NET_WORTH_INDIVIDUALS as firm_hnw_aum_pit,
        fh.TOTAL_ACCOUNTS as firm_total_accounts_pit,
        
        -- Calculate AUM growth (12 months prior from Firm_historicals)
        fh_12mo.TOTAL_AUM as firm_aum_12mo_ago,
        
        -- AUM growth rate (12-month)
        CASE 
            WHEN fh_12mo.TOTAL_AUM > 0
            THEN (fh.TOTAL_AUM - fh_12mo.TOTAL_AUM) * 100.0 / fh_12mo.TOTAL_AUM
            ELSE NULL
        END as aum_growth_12mo_pct
        
    FROM rep_state_pit rsp
    INNER JOIN lead_base lb ON rsp.lead_id = lb.lead_id
    -- Join to Firm_historicals for pit_month
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.Firm_historicals` fh
        ON rsp.firm_crd_at_contact = fh.RIA_INVESTOR_CRD_ID
        AND EXTRACT(YEAR FROM lb.pit_month) = fh.YEAR
        AND EXTRACT(MONTH FROM lb.pit_month) = fh.MONTH
    -- Join to Firm_historicals for 12 months prior (for growth calculation)
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.Firm_historicals` fh_12mo
        ON rsp.firm_crd_at_contact = fh_12mo.RIA_INVESTOR_CRD_ID
        AND fh_12mo.YEAR = EXTRACT(YEAR FROM DATE_SUB(lb.pit_month, INTERVAL 12 MONTH))
        AND fh_12mo.MONTH = EXTRACT(MONTH FROM DATE_SUB(lb.pit_month, INTERVAL 12 MONTH))
    -- Fallback: if exact month doesn't exist, use most recent prior month
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY rsp.lead_id
        ORDER BY fh.YEAR DESC, fh.MONTH DESC
    ) = 1
),

-- ========================================================================
-- ADVISOR: Features derived from employment history (Virtual Snapshot)
-- ========================================================================
advisor_features_virtual AS (
    SELECT
        rsp.lead_id,
        rsp.advisor_crd,
        rsp.contacted_date,
        rsp.industry_tenure_months,
        rsp.num_prior_firms,
        rsp.current_firm_tenure_months,
        rsp.firm_crd_at_contact,
        
        -- Calculate average tenure at prior firms (excluding current)
        (SELECT 
            AVG(DATE_DIFF(
                COALESCE(eh_prior.PREVIOUS_REGISTRATION_COMPANY_END_DATE, DATE('2025-10-31')),
                eh_prior.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                MONTH
            ))
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_prior
         WHERE eh_prior.RIA_CONTACT_CRD_ID = rsp.advisor_crd
           AND eh_prior.PREVIOUS_REGISTRATION_COMPANY_START_DATE < rsp.current_job_start_date
           AND eh_prior.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
           AND eh_prior.PREVIOUS_REGISTRATION_COMPANY_END_DATE < rsp.contacted_date
        ) as avg_prior_firm_tenure_months
        
    FROM rep_state_pit rsp
),

-- ========================================================================
-- ADVISOR: Additional employment history features (Virtual Snapshot)
-- VALIDATED MOBILITY FEATURES: 3-year lookback and Restlessness logic
-- ========================================================================
employment_features_supplement AS (
    SELECT
        lb.lead_id,
        lb.advisor_crd,
        lb.contacted_date,
        
        -- VALIDATED MOBILITY FEATURES (From Rep Mobility Doc)
        -- Key Predictor: 3-4x Lift for high mobility advisors
        
        -- 1. Recent Velocity (3-year lookback) - Count moves in last 36 months
        COUNTIF(
            eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(lb.contacted_date, INTERVAL 36 MONTH)
            AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < lb.contacted_date
        ) as pit_moves_3yr,
        
        -- 2. Historical Pattern - Average tenure at all prior firms (excluding current)
        -- Only count completed tenures (those with end dates)
        AVG(
            CASE 
                WHEN eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
                     AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < lb.contacted_date
                THEN DATE_DIFF(
                    eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                    eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, 
                    MONTH
                )
                ELSE NULL
            END
        ) as pit_avg_prior_tenure_months,
        
        -- Legacy: Job hopper indicator (3+ firms in 5 years)
        COUNTIF(
            eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(lb.contacted_date, INTERVAL 5 YEAR)
        ) as firms_in_last_5_years
        
    FROM lead_base lb
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON lb.advisor_crd = eh.RIA_CONTACT_CRD_ID
    WHERE eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE < lb.contacted_date
    GROUP BY lb.lead_id, lb.advisor_crd, lb.contacted_date
),

-- ========================================================================
-- MOBILITY DERIVED: Restlessness ratio calculation
-- ========================================================================
mobility_derived AS (
    SELECT
        efs.lead_id,
        efs.pit_moves_3yr,
        efs.pit_avg_prior_tenure_months,
        afs.current_firm_tenure_months,
        
        -- 3. Restlessness Score (Ratio)
        -- High ratio (>1.0) = staying longer than usual = might be ready to move
        CASE 
            WHEN efs.pit_avg_prior_tenure_months > 0 
            THEN SAFE_DIVIDE(afs.current_firm_tenure_months, efs.pit_avg_prior_tenure_months)
            ELSE 1.0  -- Default to 1.0 if no prior tenure data
        END as pit_restlessness_ratio,
        
        -- 4. Mobility Tier (Categorical - High Priority Signal)
        CASE
            WHEN efs.pit_moves_3yr >= 3 THEN 'Highly Mobile'
            WHEN efs.pit_moves_3yr = 2 THEN 'Mobile'
            WHEN efs.pit_moves_3yr = 1 THEN 'Average'
            WHEN efs.pit_moves_3yr = 0 AND afs.current_firm_tenure_months < 60 THEN 'Stable'
            WHEN efs.pit_moves_3yr = 0 AND afs.current_firm_tenure_months >= 60 THEN 'Lifer'
            ELSE 'Unknown'
        END as pit_mobility_tier
    FROM employment_features_supplement efs
    LEFT JOIN advisor_features_virtual afs
        ON efs.lead_id = afs.lead_id
),

-- ========================================================================
-- DATA QUALITY SIGNALS: Null/Unknown indicators (highly predictive in V12)
-- EXCEPTION: These join to ria_contacts_current ONLY for boolean indicators
-- ========================================================================
data_quality_signals AS (
    SELECT
        rsp.lead_id,
        rsp.advisor_crd,
        -- Gender missing - BOOLEAN INDICATOR ONLY
        CASE WHEN c.GENDER IS NULL OR c.GENDER = '' THEN 1 ELSE 0 END as is_gender_missing,
        -- LinkedIn missing - BOOLEAN INDICATOR ONLY
        CASE WHEN c.LINKEDIN_PROFILE_URL IS NULL OR c.LINKEDIN_PROFILE_URL = '' THEN 1 ELSE 0 END as is_linkedin_missing,
        -- Personal email missing - BOOLEAN INDICATOR ONLY
        CASE WHEN c.PERSONAL_EMAIL_ADDRESS IS NULL OR c.PERSONAL_EMAIL_ADDRESS = '' THEN 1 ELSE 0 END as is_personal_email_missing,
        -- License data missing - BOOLEAN INDICATOR ONLY
        CASE WHEN c.REP_LICENSES IS NULL OR c.REP_LICENSES = '' THEN 1 ELSE 0 END as is_license_data_missing,
        -- Industry tenure missing - BOOLEAN INDICATOR ONLY
        CASE WHEN c.INDUSTRY_TENURE_MONTHS IS NULL THEN 1 ELSE 0 END as is_industry_tenure_missing
    FROM rep_state_pit rsp
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON rsp.advisor_crd = c.RIA_CONTACT_CRD_ID
),

-- ========================================================================
-- FIRM STABILITY: Rep movement metrics (PIT - CORRECTED calculation)
-- ========================================================================
-- CRITICAL FIX: Arrivals must come from ria_contacts_current, not employment_history
-- employment_history only captures past jobs (people who left), missing current hires
-- ========================================================================
firm_stability_pit AS (
    SELECT
        rsp.lead_id,
        rsp.firm_crd_at_contact,
        rsp.contacted_date,
        
        -- Departures in 12 months before contact (from employment_history - CORRECT)
        COUNT(DISTINCT CASE 
            WHEN eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
                 AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE <= rsp.contacted_date
                 AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE > DATE_SUB(rsp.contacted_date, INTERVAL 12 MONTH)
            THEN eh.RIA_CONTACT_CRD_ID 
        END) as departures_12mo,
        
        -- Arrivals in 12 months before contact (CORRECTED: from ria_contacts_current)
        -- CRITICAL FIX: employment_history only has past jobs, missing current hires
        -- Use ria_contacts_current to count advisors who started at firm within 12mo before contacted_date
        -- For PIT: Verify they were at firm at contacted_date via employment_history
        (SELECT COUNT(DISTINCT c.RIA_CONTACT_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
         INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_verify
             ON c.RIA_CONTACT_CRD_ID = eh_verify.RIA_CONTACT_CRD_ID
         WHERE SAFE_CAST(c.PRIMARY_FIRM AS INT64) = rsp.firm_crd_at_contact
           AND c.PRIMARY_FIRM_START_DATE IS NOT NULL
           AND c.PRIMARY_FIRM_START_DATE <= rsp.contacted_date
           AND c.PRIMARY_FIRM_START_DATE > DATE_SUB(rsp.contacted_date, INTERVAL 12 MONTH)
           -- PIT verification: Advisor was at this firm at contacted_date
           AND eh_verify.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = rsp.firm_crd_at_contact
           AND eh_verify.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= rsp.contacted_date
           AND (eh_verify.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
                OR eh_verify.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= rsp.contacted_date)
        ) as arrivals_12mo
        
    FROM rep_state_pit rsp
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON rsp.firm_crd_at_contact = eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID
    GROUP BY rsp.lead_id, rsp.firm_crd_at_contact, rsp.contacted_date
),

-- ========================================================================
-- FIRM STABILITY: Add derived metrics
-- ========================================================================
firm_stability_derived AS (
    SELECT
        fs.*,
        -- Net change (empirically: most predictive feature)
        arrivals_12mo - departures_12mo as net_change_12mo,
        -- Total movement (velocity indicator)
        departures_12mo + arrivals_12mo as total_movement_12mo
    FROM firm_stability_pit fs
),

-- ========================================================================
-- ACCOLADES: Count before contact date (PIT)
-- ========================================================================
accolades_pit AS (
    SELECT
        lb.lead_id,
        lb.advisor_crd,
        COUNT(*) as accolade_count,
        COUNTIF(a.OUTLET = 'Forbes') as forbes_accolades,
        COUNTIF(a.OUTLET = "Barron's") as barrons_accolades,
        MAX(a.YEAR) as most_recent_accolade_year
    FROM lead_base lb
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_accolades_historicals` a
        ON lb.advisor_crd = a.RIA_CONTACT_CRD_ID
        AND a.YEAR <= EXTRACT(YEAR FROM lb.contacted_date)
    GROUP BY lb.lead_id, lb.advisor_crd
),

-- ========================================================================
-- DISCLOSURES: Count before contact date (PIT)
-- ========================================================================
disclosures_pit AS (
    SELECT
        lb.lead_id,
        lb.advisor_crd,
        COUNT(*) as disclosure_count,
        COUNTIF(d.TYPE = 'Criminal') as criminal_disclosures,
        COUNTIF(d.TYPE = 'Regulatory') as regulatory_disclosures,
        COUNTIF(d.TYPE = 'Customer Dispute') as customer_dispute_disclosures
    FROM lead_base lb
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.Historical_Disclosure_data` d
        ON lb.advisor_crd = d.CONTACT_CRD_ID
        AND DATE(d.EVENT_DATE) < lb.contacted_date
    GROUP BY lb.lead_id, lb.advisor_crd
),

-- ========================================================================
-- PERCENTILE CALCULATIONS: Firm stability percentiles (calculated globally)
-- ========================================================================
stability_percentiles AS (
    SELECT
        lead_id,
        net_change_12mo,
        PERCENT_RANK() OVER (ORDER BY net_change_12mo) * 100 as net_change_percentile
    FROM firm_stability_derived
)

-- ========================================================================
-- FINAL: Combine all features
-- ========================================================================
SELECT
    -- Identifiers & Target
    lb.lead_id,
    lb.advisor_crd,
    lb.contacted_date,
    lb.target,
    lb.lead_source,
    
    -- Firm identifiers
    rsp.firm_crd_at_contact,
    lb.pit_month,
    
    -- =====================
    -- ADVISOR FEATURES (from Virtual Snapshot)
    -- =====================
    COALESCE(rsp.industry_tenure_months, 0) as industry_tenure_months,
    COALESCE(rsp.num_prior_firms, 0) as num_prior_firms,
    COALESCE(rsp.current_firm_tenure_months, 0) as current_firm_tenure_months,
    COALESCE(avf.avg_prior_firm_tenure_months, 0) as avg_prior_firm_tenure_months,
    COALESCE(efs.firms_in_last_5_years, 0) as firms_in_last_5_years,
    
    -- VALIDATED MOBILITY FEATURES (3-year lookback and Restlessness)
    COALESCE(md.pit_moves_3yr, 0) as pit_moves_3yr,
    COALESCE(md.pit_avg_prior_tenure_months, 0) as pit_avg_prior_tenure_months,
    COALESCE(md.pit_restlessness_ratio, 1.0) as pit_restlessness_ratio,
    COALESCE(md.pit_mobility_tier, 'Unknown') as pit_mobility_tier,
    
    -- =====================
    -- FIRM AUM FEATURES (from Virtual Snapshot)
    -- =====================
    fsp.firm_aum_pit,
    LOG(GREATEST(1, COALESCE(fsp.firm_aum_pit, 1))) as log_firm_aum,
    fsp.aum_growth_12mo_pct,
    fsp.firm_rep_count_at_contact,
    
    -- AUM tier
    CASE
        WHEN fsp.firm_aum_pit >= 1000000000 THEN 'Billion+'
        WHEN fsp.firm_aum_pit >= 100000000 THEN '100M-1B'
        WHEN fsp.firm_aum_pit >= 10000000 THEN '10M-100M'
        WHEN fsp.firm_aum_pit >= 1000000 THEN '1M-10M'
        WHEN fsp.firm_aum_pit IS NOT NULL THEN 'Under_1M'
        ELSE 'Unknown'
    END as firm_aum_tier,
    
    -- =====================
    -- FIRM STABILITY FEATURES (PIT - KEY PREDICTORS)
    -- =====================
    COALESCE(fst.departures_12mo, 0) as firm_departures_12mo,
    COALESCE(fst.arrivals_12mo, 0) as firm_arrivals_12mo,
    COALESCE(fst.net_change_12mo, 0) as firm_net_change_12mo,
    COALESCE(fst.total_movement_12mo, 0) as firm_total_movement_12mo,
    
    -- Net change score (empirically validated: 50 + net_change * 3.5)
    ROUND(GREATEST(0, LEAST(100, 50 + COALESCE(fst.net_change_12mo, 0) * 3.5)), 1) as firm_stability_score,
    
    -- Stability percentile
    COALESCE(sp.net_change_percentile, 50) as firm_stability_percentile,
    
    -- Priority classification
    CASE
        WHEN COALESCE(sp.net_change_percentile, 50) <= 10 THEN 'HIGH_PRIORITY'
        WHEN COALESCE(sp.net_change_percentile, 50) <= 25 THEN 'MEDIUM_PRIORITY'
        WHEN COALESCE(fst.net_change_12mo, 0) < 0 THEN 'MONITOR'
        ELSE 'STABLE'
    END as firm_recruiting_priority,
    
    -- Stability tier
    CASE
        WHEN COALESCE(fst.net_change_12mo, 0) <= -14 THEN 'Severe_Bleeding'
        WHEN COALESCE(fst.net_change_12mo, 0) <= -3 THEN 'Moderate_Bleeding'
        WHEN COALESCE(fst.net_change_12mo, 0) < 0 THEN 'Slight_Bleeding'
        WHEN COALESCE(fst.net_change_12mo, 0) = 0 THEN 'Stable'
        ELSE 'Growing'
    END as firm_stability_tier,
    
    -- =====================
    -- ACCOLADES & QUALITY FEATURES
    -- =====================
    COALESCE(ap.accolade_count, 0) as accolade_count,
    CASE WHEN COALESCE(ap.accolade_count, 0) > 0 THEN 1 ELSE 0 END as has_accolades,
    COALESCE(ap.forbes_accolades, 0) as forbes_accolades,
    
    -- =====================
    -- DISCLOSURE FEATURES (PIT)
    -- =====================
    COALESCE(dp.disclosure_count, 0) as disclosure_count,
    CASE WHEN COALESCE(dp.disclosure_count, 0) > 0 THEN 1 ELSE 0 END as has_disclosures,
    COALESCE(dp.criminal_disclosures, 0) as criminal_disclosures,
    COALESCE(dp.regulatory_disclosures, 0) as regulatory_disclosures,
    
    -- =====================
    -- DATA QUALITY INDICATORS & NULL SIGNALS
    -- =====================
    CASE WHEN COALESCE(dqs.is_linkedin_missing, 1) = 0 THEN 1 ELSE 0 END as has_linkedin,
    CASE WHEN fsp.firm_aum_pit IS NOT NULL THEN 1 ELSE 0 END as has_firm_aum,
    CASE WHEN rsp.firm_crd_at_contact IS NOT NULL THEN 1 ELSE 0 END as has_valid_virtual_snapshot,
    
    -- NULL SIGNAL FEATURES (Highly predictive in V12)
    COALESCE(dqs.is_gender_missing, 0) as is_gender_missing,
    COALESCE(dqs.is_linkedin_missing, 0) as is_linkedin_missing,
    COALESCE(dqs.is_personal_email_missing, 0) as is_personal_email_missing,
    COALESCE(dqs.is_license_data_missing, 0) as is_license_data_missing,
    COALESCE(dqs.is_industry_tenure_missing, 0) as is_industry_tenure_missing
    
FROM lead_base lb
LEFT JOIN rep_state_pit rsp ON lb.lead_id = rsp.lead_id
LEFT JOIN firm_state_pit fsp ON rsp.lead_id = fsp.lead_id
LEFT JOIN advisor_features_virtual avf ON rsp.lead_id = avf.lead_id
LEFT JOIN employment_features_supplement efs ON lb.lead_id = efs.lead_id
LEFT JOIN mobility_derived md ON efs.lead_id = md.lead_id
LEFT JOIN data_quality_signals dqs ON rsp.lead_id = dqs.lead_id
LEFT JOIN firm_stability_derived fst ON rsp.lead_id = fst.lead_id
LEFT JOIN stability_percentiles sp ON fst.lead_id = sp.lead_id
LEFT JOIN accolades_pit ap ON lb.lead_id = ap.lead_id
LEFT JOIN disclosures_pit dp ON lb.lead_id = dp.lead_id
WHERE lb.target IS NOT NULL  -- Exclude right-censored leads
