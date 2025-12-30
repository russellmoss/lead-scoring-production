-- ============================================================================
-- PRODUCTION SCORING: V4 Feature Engineering for Live Leads
-- ============================================================================
-- 
-- PURPOSE: Generate features for V4 model scoring on current leads
-- 
-- USAGE:
--   - Run daily to score new leads
--   - Refresh when new leads are added or advisor data is updated
--   - Features are PIT-compliant (use only data available at CURRENT_DATE)
-- 
-- DEPLOYMENT:
--   - This SQL prepares features
--   - Python model (lead_scorer_v4.py) generates predictions
--   - Scores are written back to BigQuery/Salesforce
-- 
-- HYBRID STRATEGY:
--   - V3 Rules: Primary prioritization (T1, T2, T3, T4, Standard)
--   - V4 Score: Deprioritization filter (skip bottom 20%)
--   - Combined: V3 tier + V4 percentile = final priority
-- ============================================================================

-- ============================================================================
-- VIEW: Production Features for Scoring
-- ============================================================================
-- This view calculates features for all leads that need scoring
-- ============================================================================

CREATE OR REPLACE VIEW `savvy-gtm-analytics.ml_features.v4_production_features` AS

WITH 
-- ============================================================================
-- BASE: Get leads that need scoring
-- ============================================================================
base AS (
    SELECT 
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as advisor_crd,
        CURRENT_DATE() as prediction_date,  -- Use current date as "contact date" for scoring
        l.LeadSource,
        l.Email,
        l.LinkedIn_Profile_Apollo__c as linkedin_url,
        -- Group lead source for filtering
        CASE 
            WHEN l.LeadSource LIKE '%Provided%' OR l.LeadSource LIKE '%List%' THEN 'Provided List'
            WHEN l.LeadSource LIKE '%LinkedIn%' THEN 'LinkedIn'
            ELSE 'Other'
        END as lead_source_grouped
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.FA_CRD__c IS NOT NULL
      AND l.stage_entered_contacting__c IS NOT NULL
      -- Only score leads that are contacted but not yet converted
      AND l.Stage_Entered_Call_Scheduled__c IS NULL
      -- Exclude Savvy employees
      AND (l.Company IS NULL OR UPPER(l.Company) NOT LIKE '%SAVVY%')
),

-- ============================================================================
-- FEATURE GROUP 1: TENURE FEATURES (from employment history)
-- ============================================================================
-- Same logic as phase_2_feature_engineering.sql
-- ============================================================================
history_firm AS (
    SELECT 
        b.lead_id,
        b.prediction_date,
        b.advisor_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_date,
        DATE_DIFF(b.prediction_date, eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) as tenure_months
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
        AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= b.prediction_date
        AND (eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
             OR eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= b.prediction_date)
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY b.lead_id 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
),

current_snapshot AS (
    SELECT 
        b.lead_id,
        b.prediction_date,
        b.advisor_crd,
        c.LATEST_REGISTERED_EMPLOYMENT_COMPANY_CRD_ID as firm_crd,
        c.LATEST_REGISTERED_EMPLOYMENT_COMPANY as firm_name,
        c.LATEST_REGISTERED_EMPLOYMENT_START_DATE as firm_start_date,
        CASE 
            WHEN c.LATEST_REGISTERED_EMPLOYMENT_START_DATE <= b.prediction_date 
            THEN DATE_DIFF(b.prediction_date, c.LATEST_REGISTERED_EMPLOYMENT_START_DATE, MONTH)
            ELSE NULL
        END as tenure_months
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON b.advisor_crd = c.RIA_CONTACT_CRD_ID
    WHERE c.LATEST_REGISTERED_EMPLOYMENT_START_DATE IS NOT NULL
      AND c.LATEST_REGISTERED_EMPLOYMENT_START_DATE <= b.prediction_date
),

current_firm AS (
    SELECT 
        COALESCE(hf.lead_id, cs.lead_id) as lead_id,
        COALESCE(hf.prediction_date, cs.prediction_date) as prediction_date,
        COALESCE(hf.advisor_crd, cs.advisor_crd) as advisor_crd,
        COALESCE(hf.firm_crd, cs.firm_crd) as firm_crd,
        COALESCE(hf.firm_name, cs.firm_name) as firm_name,
        COALESCE(hf.firm_start_date, cs.firm_start_date) as firm_start_date,
        COALESCE(hf.tenure_months, cs.tenure_months) as tenure_months
    FROM history_firm hf
    FULL OUTER JOIN current_snapshot cs
        ON hf.lead_id = cs.lead_id
    WHERE COALESCE(hf.lead_id, cs.lead_id) IS NOT NULL
),

industry_tenure AS (
    SELECT
        cf.lead_id,
        cf.prediction_date,
        cf.firm_start_date,
        COALESCE((
            SELECT SUM(
                DATE_DIFF(
                    COALESCE(eh2.PREVIOUS_REGISTRATION_COMPANY_END_DATE, cf.prediction_date),
                    eh2.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                    MONTH
                )
            )
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh2
            WHERE eh2.RIA_CONTACT_CRD_ID = cf.advisor_crd
                AND eh2.PREVIOUS_REGISTRATION_COMPANY_START_DATE < cf.firm_start_date
                AND (eh2.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL
                     OR eh2.PREVIOUS_REGISTRATION_COMPANY_END_DATE <= cf.prediction_date)
        ), 0) as industry_tenure_months
    FROM current_firm cf
    WHERE cf.firm_start_date IS NOT NULL
),

-- ============================================================================
-- FEATURE GROUP 2: MOBILITY FEATURES
-- ============================================================================
mobility AS (
    SELECT 
        b.lead_id,
        b.prediction_date,
        COUNT(DISTINCT CASE 
            WHEN eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE > DATE_SUB(b.prediction_date, INTERVAL 3 YEAR)
                AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= b.prediction_date
            THEN eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID
        END) as mobility_3yr
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
    GROUP BY b.lead_id, b.prediction_date
),

-- ============================================================================
-- FEATURE GROUP 3: FIRM STABILITY
-- ============================================================================
firm_stability AS (
    SELECT
        cf.lead_id,
        cf.firm_crd,
        cf.prediction_date,
        COALESCE((
            SELECT COUNT(DISTINCT eh_d.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_d
            WHERE eh_d.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
              AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(cf.prediction_date, INTERVAL 12 MONTH)
              AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE < cf.prediction_date
              AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
        ), 0) as firm_departures_12mo,
        COALESCE((
            SELECT COUNT(DISTINCT eh_a.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_a
            WHERE eh_a.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
              AND eh_a.PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(cf.prediction_date, INTERVAL 12 MONTH)
              AND eh_a.PREVIOUS_REGISTRATION_COMPANY_START_DATE < cf.prediction_date
        ), 0) as firm_arrivals_12mo,
        COALESCE((
            SELECT COUNT(DISTINCT eh_current.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_current
            WHERE eh_current.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
              AND eh_current.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= cf.prediction_date
              AND (eh_current.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL OR eh_current.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= cf.prediction_date)
        ), 0) as firm_rep_count_at_contact
    FROM current_firm cf
    WHERE cf.firm_crd IS NOT NULL
),

-- ============================================================================
-- FEATURE GROUP 4: WIREHOUSE & BROKER PROTOCOL
-- ============================================================================
wirehouse AS (
    SELECT
        cf.lead_id,
        CASE
            WHEN UPPER(cf.firm_name) LIKE '%MERRILL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%MORGAN STANLEY%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%UBS%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%WELLS FARGO%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%EDWARD JONES%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%RAYMOND JAMES%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%AMERIPRISE%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%LPL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%NORTHWESTERN MUTUAL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%STIFEL%' THEN 1
            ELSE 0
        END as is_wirehouse
    FROM current_firm cf
),

broker_protocol AS (
    SELECT
        cf.lead_id,
        CASE WHEN bp.firm_crd_id IS NOT NULL THEN 1 ELSE 0 END as is_broker_protocol
    FROM current_firm cf
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.broker_protocol_members` bp
        ON cf.firm_crd = bp.firm_crd_id
    QUALIFY ROW_NUMBER() OVER(PARTITION BY cf.lead_id ORDER BY bp.firm_crd_id) = 1
),

-- ============================================================================
-- FEATURE GROUP 5: EXPERIENCE
-- ============================================================================
experience AS (
    SELECT
        b.lead_id,
        COALESCE(it.industry_tenure_months, c.INDUSTRY_TENURE_MONTHS, 0) / 12.0 as experience_years,
        CASE WHEN COALESCE(it.industry_tenure_months, c.INDUSTRY_TENURE_MONTHS) IS NULL THEN 1 ELSE 0 END as is_experience_missing
    FROM base b
    LEFT JOIN industry_tenure it ON b.lead_id = it.lead_id
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON b.advisor_crd = c.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- FEATURE GROUP 6: DATA QUALITY FLAGS
-- ============================================================================
data_quality AS (
    SELECT
        b.lead_id,
        CASE WHEN b.Email IS NOT NULL THEN 1 ELSE 0 END as has_email,
        CASE WHEN b.linkedin_url IS NOT NULL THEN 1 ELSE 0 END as has_linkedin,
        CASE WHEN b.advisor_crd IS NOT NULL THEN 1 ELSE 0 END as has_fintrx_match,
        CASE WHEN cf.firm_crd IS NOT NULL THEN 1 ELSE 0 END as has_employment_history
    FROM base b
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id
),

-- ============================================================================
-- COMBINE ALL FEATURES (matching training feature set)
-- ============================================================================
all_features AS (
    SELECT
        -- Base columns
        b.lead_id,
        b.advisor_crd,
        b.prediction_date,
        b.lead_source_grouped,

        -- Firm at contact
        cf.firm_crd,
        cf.firm_name,

        -- GROUP 1: TENURE FEATURES
        COALESCE(cf.tenure_months, 0) as tenure_months,
        CASE
            WHEN cf.tenure_months IS NULL THEN 'Unknown'
            WHEN cf.tenure_months < 12 THEN '0-12'
            WHEN cf.tenure_months < 24 THEN '12-24'
            WHEN cf.tenure_months < 48 THEN '24-48'
            WHEN cf.tenure_months < 120 THEN '48-120'
            ELSE '120+'
        END as tenure_bucket,

        -- Industry tenure
        COALESCE(it.industry_tenure_months, 0) as industry_tenure_months,
        e.experience_years,
        CASE
            WHEN e.experience_years < 5 THEN '0-5'
            WHEN e.experience_years < 10 THEN '5-10'
            WHEN e.experience_years < 15 THEN '10-15'
            WHEN e.experience_years < 20 THEN '15-20'
            ELSE '20+'
        END as experience_bucket,
        e.is_experience_missing,

        -- GROUP 2: MOBILITY FEATURES
        COALESCE(m.mobility_3yr, 0) as mobility_3yr,
        CASE
            WHEN COALESCE(m.mobility_3yr, 0) = 0 THEN 'Stable'
            WHEN COALESCE(m.mobility_3yr, 0) = 1 THEN 'Low_Mobility'
            ELSE 'High_Mobility'
        END as mobility_tier,

        -- GROUP 3: FIRM STABILITY FEATURES
        fs.firm_rep_count_at_contact,
        COALESCE(fs.firm_departures_12mo, 0) as firm_departures_12mo,
        COALESCE(fs.firm_arrivals_12mo, 0) as firm_arrivals_12mo,
        COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) as firm_net_change_12mo,
        CASE
            WHEN cf.firm_crd IS NULL THEN 'Unknown'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < -10 THEN 'Heavy_Bleeding'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < 0 THEN 'Light_Bleeding'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) = 0 THEN 'Stable'
            ELSE 'Growing'
        END as firm_stability_tier,
        CASE WHEN cf.firm_crd IS NULL THEN 0 ELSE 1 END as has_firm_data,

        -- GROUP 4: WIREHOUSE & BROKER PROTOCOL
        COALESCE(w.is_wirehouse, 0) as is_wirehouse,
        COALESCE(bp.is_broker_protocol, 0) as is_broker_protocol,

        -- GROUP 5: DATA QUALITY FLAGS
        dq.has_email,
        dq.has_linkedin,
        dq.has_fintrx_match,
        dq.has_employment_history,

        -- ============================================================================
        -- INTERACTION FEATURES
        -- ============================================================================
        CASE
            WHEN COALESCE(m.mobility_3yr, 0) >= 2
                AND (COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0)) < -10
            THEN 1 ELSE 0
        END as mobility_x_heavy_bleeding,

        CASE
            WHEN COALESCE(cf.tenure_months, 9999) < 24 AND COALESCE(m.mobility_3yr, 0) >= 2
            THEN 1 ELSE 0
        END as short_tenure_x_high_mobility,

        -- Metadata
        CURRENT_TIMESTAMP() as feature_extraction_timestamp

    FROM base b
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id
    LEFT JOIN industry_tenure it ON b.lead_id = it.lead_id
    LEFT JOIN mobility m ON b.lead_id = m.lead_id
    LEFT JOIN firm_stability fs ON b.lead_id = fs.lead_id
    LEFT JOIN wirehouse w ON b.lead_id = w.lead_id
    LEFT JOIN broker_protocol bp ON b.lead_id = bp.lead_id
    LEFT JOIN experience e ON b.lead_id = e.lead_id
    LEFT JOIN data_quality dq ON b.lead_id = dq.lead_id
)

SELECT * FROM all_features;

-- ============================================================================
-- TABLE: Daily Scores (for caching and Salesforce sync)
-- ============================================================================
-- This table stores the latest scores for each lead
-- Refresh daily or when new leads are added
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_daily_scores` AS

SELECT
    pf.lead_id,
    pf.advisor_crd,
    pf.prediction_date,
    -- All features (for model inference)
    pf.tenure_bucket,
    pf.experience_bucket,
    pf.is_experience_missing,
    pf.mobility_tier,
    pf.firm_rep_count_at_contact,
    pf.firm_net_change_12mo,
    pf.firm_stability_tier,
    pf.has_firm_data,
    pf.is_wirehouse,
    pf.is_broker_protocol,
    pf.has_email,
    pf.has_linkedin,
    pf.mobility_x_heavy_bleeding,
    pf.short_tenure_x_high_mobility,
    -- Metadata
    CURRENT_TIMESTAMP() as scored_at,
    'v4.0.0' as model_version
FROM `savvy-gtm-analytics.ml_features.v4_production_features` pf;

-- ============================================================================
-- USAGE NOTES
-- ============================================================================
--
-- REFRESH SCHEDULE:
--   - Run daily (recommended: 6 AM EST)
--   - Refresh when new leads are added
--   - Refresh when advisor data is updated in FINTRX
--
-- TRIGGERS FOR RESCORE:
--   - New lead enters "Contacting" stage
--   - Advisor changes firms (employment history updated)
--   - Firm stability data refreshed (monthly)
--
-- DATA FRESHNESS:
--   - FINTRX data: Updated daily
--   - Employment history: Real-time (backfilled)
--   - Firm stability: Calculated from employment history (real-time)
--
-- PYTHON SCORING:
--   1. Query this table/view for leads needing scores
--   2. Use lead_scorer_v4.py to generate predictions
--   3. Write scores back to BigQuery/Salesforce
--   4. Calculate percentile (1-100) for deprioritization
--
-- SALESFORCE FIELDS:
--   - V4_Score__c: Raw prediction (0-1)
--   - V4_Score_Percentile__c: Percentile rank (1-100)
--   - V4_Deprioritize__c: TRUE if bottom 20% (percentile <= 20)
--
-- ============================================================================

