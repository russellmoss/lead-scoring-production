-- ============================================================================
-- LEAD LIST GENERATION QUERY - VERSION 3.3.0
-- ============================================================================
-- 
-- Version: V3.3.0_12302025_BLEEDING_SIGNAL_REFINEMENT
-- Author: Lead Scoring Team
-- Date: December 30, 2025
--
-- CHANGES FROM V3.2.4:
-- 1. REMOVED TIER_5_HEAVY_BLEEDER (converted at 3.27%, below baseline)
-- 2. Implemented inferred departures (60-90 days fresher signal)
-- 3. Tightened TIER_3 threshold from -10/-1 to -15/-3
-- 4. Added bleeding_velocity field (ACCELERATING/STEADY/DECELERATING)
-- 5. Added TIER_3A_ACCELERATING_BLEEDER for optimal timing
--
-- KEY INSIGHT:
-- Heavy bleeding firms have already lost their best advisors.
-- Moderate bleeding with accelerating velocity catches advisors
-- in the "should I go?" decision phase.
--
-- VALIDATION DATA:
-- | Bleeding Category | Conversion | Lift |
-- |-------------------|------------|------|
-- | MODERATE_BLEEDING | 5.43%      | 1.42x|
-- | HEAVY_BLEEDING    | 3.27%      | 0.86x| <- REMOVED
-- | BASELINE          | 3.82%      | 1.0x |
--
-- USAGE:
-- 1. Replace {TABLE_NAME} with your desired output table name (e.g., 'february_2026_lead_list')
-- 2. Adjust {LEAD_LIMIT} to desired number of leads (default: 2400)
-- 3. Adjust {RECYCLABLE_DAYS} for re-engagement threshold (default: 180)
-- 4. Execute in BigQuery
-- 
-- FEATURES:
-- - New prospects (not in Salesforce)
-- - Recyclable leads (180+ days no contact, not DNC)
-- - V3.3.0 tier scoring with bleeding velocity detection
-- - Firm diversity cap (max 50 leads per firm)
-- - Priority ranking by tier and conversion potential
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.{TABLE_NAME}` AS

WITH 
-- ============================================================================
-- A. EXCLUSIONS (Wirehouses)
-- ============================================================================
excluded_firms AS (
    SELECT firm_pattern FROM UNNEST([
        '%J.P. MORGAN%', '%MORGAN STANLEY%', '%MERRILL%', '%WELLS FARGO%', 
        '%UBS %', '%UBS,%', '%EDWARD JONES%', '%AMERIPRISE%', 
        '%NORTHWESTERN MUTUAL%', '%PRUDENTIAL%', '%RAYMOND JAMES%',
        '%FIDELITY%', '%SCHWAB%', '%VANGUARD%', '%GOLDMAN SACHS%', '%CITIGROUP%',
        '%LPL FINANCIAL%', '%COMMONWEALTH%', '%CETERA%', '%CAMBRIDGE%',
        '%OSAIC%', '%PRIMERICA%',
        '%STATE FARM%', '%ALLSTATE%', '%NEW YORK LIFE%', '%NYLIFE%',
        '%TRANSAMERICA%', '%FARM BUREAU%', '%NATIONWIDE%',
        '%LINCOLN FINANCIAL%', '%MASS MUTUAL%', '%MASSMUTUAL%'
    ]) as firm_pattern
),

-- ============================================================================
-- B. EXISTING SALESFORCE CRDs
-- ============================================================================
salesforce_crds AS (
    SELECT DISTINCT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE FA_CRD__c IS NOT NULL AND IsDeleted = false
),

-- ============================================================================
-- C. RECYCLABLE LEADS ({RECYCLABLE_DAYS}+ days no contact)
-- ============================================================================
lead_task_activity AS (
    SELECT 
        t.WhoId as lead_id,
        MAX(GREATEST(
            COALESCE(DATE(t.ActivityDate), DATE('1900-01-01')),
            COALESCE(DATE(t.CompletedDateTime), DATE('1900-01-01')),
            COALESCE(DATE(t.CreatedDate), DATE('1900-01-01'))
        )) as last_activity_date
    FROM `savvy-gtm-analytics.SavvyGTMData.Task` t
    WHERE t.IsDeleted = false AND t.WhoId IS NOT NULL
      AND (t.Type IN ('Outgoing SMS', 'Incoming SMS')
           OR UPPER(t.Subject) LIKE '%SMS%' OR UPPER(t.Subject) LIKE '%TEXT%'
           OR t.TaskSubtype = 'Call' OR t.Type = 'Call'
           OR UPPER(t.Subject) LIKE '%CALL%' OR t.CallType IS NOT NULL)
    GROUP BY t.WhoId
),

recyclable_lead_ids AS (
    SELECT l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN lead_task_activity la ON l.Id = la.lead_id
    WHERE l.IsDeleted = false AND l.FA_CRD__c IS NOT NULL
      AND (la.last_activity_date IS NULL OR DATE_DIFF(CURRENT_DATE(), la.last_activity_date, DAY) > {RECYCLABLE_DAYS})
      AND (l.DoNotCall IS NULL OR l.DoNotCall = false)
      AND l.Status NOT IN ('Closed', 'Converted', 'Dead', 'Unqualified', 'Disqualified', 
                           'Do Not Contact', 'Not Qualified', 'Bad Data', 'Duplicate')
),

-- ============================================================================
-- D. ADVISOR EMPLOYMENT HISTORY (For mobility metrics)
-- ============================================================================
advisor_moves AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID) as total_firms,
        COUNT(DISTINCT CASE 
            WHEN PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 YEAR)
            THEN PREVIOUS_REGISTRATION_COMPANY_CRD_ID END) as moves_3yr,
        MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE) as career_start_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    GROUP BY RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- E. FIRM HEADCOUNT (from ria_contacts_current)
-- ============================================================================
firm_headcount AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_reps
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY PRIMARY_FIRM
),

-- ============================================================================
-- F. FIRM DEPARTURES (12 months) - INFERRED from START_DATE at new firm
-- V3.3 UPDATE: Use PRIMARY_FIRM_START_DATE to infer departures 60-90 days faster
-- When advisor starts at Firm B, we infer they departed Firm A on same date
-- ============================================================================
firm_departures AS (
    SELECT
        SAFE_CAST(prior_employer.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT prior_employer.RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN (
        SELECT
            eh.RIA_CONTACT_CRD_ID,
            eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID,
            eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
            ROW_NUMBER() OVER (
                PARTITION BY eh.RIA_CONTACT_CRD_ID 
                ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
            ) as rn
        FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
    ) prior_employer
        ON c.RIA_CONTACT_CRD_ID = prior_employer.RIA_CONTACT_CRD_ID
        AND prior_employer.rn = 1
        -- Ensure we're looking at a DIFFERENT firm (not current employer)
        AND SAFE_CAST(prior_employer.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != SAFE_CAST(c.PRIMARY_FIRM AS INT64)
    WHERE c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND c.PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

-- ============================================================================
-- F2. FIRM DEPARTURES - 90 DAY WINDOWS FOR VELOCITY CALCULATION
-- V3.3 UPDATE: Detect ACCELERATING bleeding (firms entering bleeding phase)
-- ============================================================================
firm_departures_velocity AS (
    SELECT
        SAFE_CAST(prior_employer.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        -- Recent 90 days
        COUNT(DISTINCT CASE 
            WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN c.RIA_CONTACT_CRD_ID 
        END) as departures_90d,
        -- Prior 90 days (91-180 days ago)
        COUNT(DISTINCT CASE 
            WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
                 AND c.PRIMARY_FIRM_START_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN c.RIA_CONTACT_CRD_ID 
        END) as departures_prior_90d
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN (
        SELECT
            eh.RIA_CONTACT_CRD_ID,
            eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID,
            eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
            ROW_NUMBER() OVER (
                PARTITION BY eh.RIA_CONTACT_CRD_ID 
                ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
            ) as rn
        FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
    ) prior_employer
        ON c.RIA_CONTACT_CRD_ID = prior_employer.RIA_CONTACT_CRD_ID
        AND prior_employer.rn = 1
        AND SAFE_CAST(prior_employer.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != SAFE_CAST(c.PRIMARY_FIRM AS INT64)
    WHERE c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
      AND c.PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

-- ============================================================================
-- G. FIRM ARRIVALS (12 months) - from ria_contacts_current
-- ============================================================================
firm_arrivals AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

-- ============================================================================
-- H. COMBINED FIRM METRICS
-- ============================================================================
firm_metrics AS (
    SELECT
        h.firm_crd,
        h.current_reps as firm_rep_count,
        COALESCE(d.departures_12mo, 0) as departures_12mo,
        COALESCE(a.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(a.arrivals_12mo, 0) - COALESCE(d.departures_12mo, 0) as firm_net_change_12mo,
        CASE WHEN h.current_reps > 0 
             THEN COALESCE(d.departures_12mo, 0) * 100.0 / h.current_reps 
             ELSE 0 END as turnover_pct,
        -- V3.3: Bleeding velocity fields
        COALESCE(dv.departures_90d, 0) as departures_90d,
        COALESCE(dv.departures_prior_90d, 0) as departures_prior_90d,
        -- Velocity classification
        CASE 
            WHEN COALESCE(dv.departures_prior_90d, 0) = 0 
                 AND COALESCE(dv.departures_90d, 0) >= 3 
            THEN 'ACCELERATING'
            WHEN COALESCE(dv.departures_90d, 0) > COALESCE(dv.departures_prior_90d, 0) * 1.5 
            THEN 'ACCELERATING'
            WHEN COALESCE(dv.departures_90d, 0) < COALESCE(dv.departures_prior_90d, 0) * 0.5 
            THEN 'DECELERATING'
            ELSE 'STEADY'
        END as bleeding_velocity
    FROM firm_headcount h
    LEFT JOIN firm_departures d ON h.firm_crd = d.firm_crd
    LEFT JOIN firm_departures_velocity dv ON h.firm_crd = dv.firm_crd  -- V3.3: Add velocity join
    LEFT JOIN firm_arrivals a ON h.firm_crd = a.firm_crd
    WHERE h.current_reps >= 20  -- Minimum viable firm size
),

-- ============================================================================
-- I. BASE PROSPECT DATA
-- ============================================================================
base_prospects AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        c.CONTACT_FIRST_NAME as first_name,
        c.CONTACT_LAST_NAME as last_name,
        c.PRIMARY_FIRM_NAME as firm_name,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
        c.EMAIL as email,
        COALESCE(c.MOBILE_PHONE_NUMBER, c.OFFICE_PHONE_NUMBER) as phone,
        c.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        c.PRIMARY_FIRM_EMPLOYEE_COUNT as firm_employee_count,
        DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, MONTH) as tenure_months,
        DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, YEAR) as tenure_years,
        CASE WHEN sf.crd IS NULL THEN 'NEW_PROSPECT' ELSE 'IN_SALESFORCE' END as prospect_type,
        sf.lead_id as existing_lead_id
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN salesforce_crds sf ON c.RIA_CONTACT_CRD_ID = sf.crd
    WHERE c.CONTACT_FIRST_NAME IS NOT NULL AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM_START_DATE IS NOT NULL AND c.PRIMARY_FIRM_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern)
),

-- ============================================================================
-- J. ENRICH WITH ADVISOR HISTORY, FIRM METRICS, AND CERTIFICATIONS
-- ============================================================================
enriched_prospects AS (
    SELECT 
        bp.*,
        COALESCE(am.total_firms, 1) as total_firms,
        COALESCE(am.total_firms, 1) - 1 as num_prior_firms,
        COALESCE(am.moves_3yr, 0) as moves_3yr,
        DATE_DIFF(CURRENT_DATE(), am.career_start_date, YEAR) as industry_tenure_years,
        DATE_DIFF(CURRENT_DATE(), am.career_start_date, MONTH) as industry_tenure_months,
        
        COALESCE(fm.firm_rep_count, bp.firm_employee_count, 1) as firm_rep_count,
        COALESCE(fm.arrivals_12mo, 0) as firm_arrivals_12mo,
        COALESCE(fm.departures_12mo, 0) as firm_departures_12mo,
        COALESCE(fm.firm_net_change_12mo, 0) as firm_net_change_12mo,
        COALESCE(fm.turnover_pct, 0) as firm_turnover_pct,
        -- V3.3: Bleeding velocity fields
        fm.departures_90d,
        fm.departures_prior_90d,
        fm.bleeding_velocity,
        
        CASE WHEN EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(bp.firm_name) LIKE ef.firm_pattern) THEN 1 ELSE 0 END as is_wirehouse,
        
        -- Certification and license detection from FINTRX (V3.2.1)
        CASE WHEN c.CONTACT_BIO LIKE '%CFP%' 
             OR c.CONTACT_BIO LIKE '%Certified Financial Planner%'
             OR c.TITLE_NAME LIKE '%CFP%'
             THEN 1 ELSE 0 END as has_cfp,
        
        CASE WHEN c.REP_LICENSES LIKE '%Series 65%' 
             AND c.REP_LICENSES NOT LIKE '%Series 7%' 
             THEN 1 ELSE 0 END as has_series_65_only,
        
        CASE WHEN c.REP_LICENSES LIKE '%Series 7%' 
             THEN 1 ELSE 0 END as has_series_7,
        
        CASE WHEN c.CONTACT_BIO LIKE '%CFA%' 
             OR c.CONTACT_BIO LIKE '%Chartered Financial Analyst%'
             OR c.TITLE_NAME LIKE '%CFA%'
             THEN 1 ELSE 0 END as has_cfa
        
    FROM base_prospects bp
    LEFT JOIN advisor_moves am ON bp.crd = am.crd
    LEFT JOIN firm_metrics fm ON bp.firm_crd = fm.firm_crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c ON bp.crd = c.RIA_CONTACT_CRD_ID
    WHERE COALESCE(fm.turnover_pct, 0) < 100
),

-- ============================================================================
-- K. APPLY V3.2.1 TIER LOGIC (with certifications)
-- ============================================================================
scored_prospects AS (
    SELECT 
        ep.*,
        
        -- Score tier (V3.2.1 - includes certification tiers)
        CASE 
            -- Tier 1A: CFP at bleeding firm
            WHEN (tenure_years BETWEEN 1 AND 4
                  AND industry_tenure_years >= 5
                  AND firm_net_change_12mo < 0
                  AND has_cfp = 1
                  AND is_wirehouse = 0) THEN 'TIER_1A_PRIME_MOVER_CFP'
            -- Tier 1B: Series 65 only + Tier 1 criteria
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            -- Standard Tier 1 (no certification boost)
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 'TIER_1_PRIME_MOVER'
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 'TIER_2_PROVEN_MOVER'
            -- V3.3 NEW: TIER_3A - Accelerating Bleeding (highest value moderate bleeder)
            -- Firms that just started bleeding are in the "what's happening?" phase
            -- Advisors are most receptive during this uncertainty window
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND bleeding_velocity = 'ACCELERATING'
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 'TIER_3A_ACCELERATING_BLEEDER'
            -- V3.3 UPDATE: Tightened threshold (-15 to -3) and added velocity boost
            -- Analysis: Moderate bleeding (5.43%) outperforms heavy bleeding (3.27%)
            -- Sweet spot is 3-15 departures, preferably with accelerating velocity
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 'TIER_3_MODERATE_BLEEDER'
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 'TIER_4_EXPERIENCED_MOVER'
            -- V3.3 UPDATE: TIER_5_HEAVY_BLEEDER REMOVED
            -- Analysis showed heavy bleeding firms (16+ departures) convert at 3.27%
            -- This is BELOW the 3.82% baseline, so this tier was counterproductive
            -- Advisors at heavily bleeding firms now fall to STANDARD tier
            ELSE 'STANDARD'
        END as score_tier,
        
        -- Priority rank (V3.2.1 - certification tiers have highest priority)
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4
                  AND industry_tenure_years >= 5
                  AND firm_net_change_12mo < 0
                  AND has_cfp = 1
                  AND is_wirehouse = 0) THEN 1
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 2
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 3
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 4
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND bleeding_velocity = 'ACCELERATING'
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 5
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 6
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 7
            ELSE 8
        END as priority_rank,
        
        -- Expected conversion rate (V3.2.1 - updated rates)
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4
                  AND industry_tenure_years >= 5
                  AND firm_net_change_12mo < 0
                  AND has_cfp = 1
                  AND is_wirehouse = 0) THEN 0.1644
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 0.1648
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 0.1321
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 0.0859
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND bleeding_velocity = 'ACCELERATING'
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 0.0600
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 0.0543
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 0.1154
            ELSE 0.0382
        END as expected_conversion_rate,
        
        -- Score narrative (V3.2.1 - includes certification information)
        CASE 
            -- Tier 1A: CFP at bleeding firm
            WHEN (tenure_years BETWEEN 1 AND 4
                  AND industry_tenure_years >= 5
                  AND firm_net_change_12mo < 0
                  AND has_cfp = 1
                  AND is_wirehouse = 0) THEN
                CONCAT(
                    first_name, ' is a CFP holder (Certified Financial Planner) at ', firm_name, 
                    ', which has lost ', CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors (net) in the past year. ',
                    'CFP designation indicates book ownership and client relationships, making this advisor highly portable. ',
                    'With ', CAST(tenure_years AS STRING), ' years at the firm and ', CAST(industry_tenure_years AS STRING), 
                    ' years of experience, this is an ULTRA-PRIORITY lead. ',
                    'Tier 1A: Prime Mover + CFP with 16.44% expected conversion (4.30x baseline).'
                )
            -- Tier 1B: Series 65 only (pure RIA)
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN
                CONCAT(
                    first_name, ' is a fee-only RIA advisor (Series 65 only, no Series 7) at ', firm_name, 
                    ', meeting Prime Mover criteria. ',
                    'Pure RIA advisors have no broker-dealer ties, making transitions easier. ',
                    CASE 
                        WHEN firm_net_change_12mo < 0 THEN CONCAT('The firm has lost ', CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors (net) in the past year. ')
                        WHEN firm_rep_count <= 10 THEN CONCAT('The firm is very small with only ', CAST(firm_rep_count AS STRING), ' advisors. ')
                        ELSE ''
                    END,
                    'With ', CAST(tenure_years AS STRING), ' years at the firm and ', CAST(industry_tenure_years AS STRING), 
                    ' years of experience, this is a HIGH-PRIORITY lead. ',
                    'Tier 1B: Prime Mover (Pure RIA) with 16.48% expected conversion (4.31x baseline).'
                )
            -- Standard Tier 1 paths
            WHEN (tenure_years BETWEEN 1 AND 3
                  AND industry_tenure_years BETWEEN 5 AND 15
                  AND firm_net_change_12mo < 0
                  AND firm_rep_count <= 50
                  AND is_wirehouse = 0) THEN
                CONCAT(
                    first_name, ' has been at ', firm_name, ' for ', CAST(tenure_years AS STRING), ' years',
                    ' and has ', CAST(industry_tenure_years AS STRING), ' years of industry experience. ',
                    'The firm has lost ', CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors (net) in the past year',
                    ' and has only ', CAST(firm_rep_count AS STRING), ' reps remaining. ',
                    'This combination of mid-career experience at a small, bleeding firm makes them a Prime Mover ',
                    'with 13.21% expected conversion (3.46x baseline).'
                )
            WHEN (tenure_years BETWEEN 1 AND 3
                  AND firm_rep_count <= 10
                  AND is_wirehouse = 0) THEN
                CONCAT(
                    first_name, ' works at ', firm_name, ', a micro-firm with only ', CAST(firm_rep_count AS STRING), ' advisors, ',
                    'and joined ', CAST(tenure_years AS STRING), ' years ago. ',
                    'Advisors at very small firms are typically entrepreneurial, own their book outright, ',
                    'and have no restrictive covenants - making them highly receptive to new opportunities. ',
                    'Prime Mover tier with 13.21% expected conversion (3.46x baseline).'
                )
            WHEN (tenure_years BETWEEN 1 AND 4
                  AND industry_tenure_years BETWEEN 5 AND 15
                  AND firm_net_change_12mo < 0
                  AND is_wirehouse = 0) THEN
                CONCAT(
                    first_name, ' is a ', CAST(industry_tenure_years AS STRING), '-year industry veteran ',
                    'who joined ', firm_name, ' ', CAST(tenure_years AS STRING), ' years ago. ',
                    'The firm has lost ', CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors (net) in the past 12 months. ',
                    'Watching colleagues leave often triggers a should-I-go-too mindset. ',
                    'Prime Mover with 13.21% expected conversion (3.46x baseline).'
                )
            WHEN (num_prior_firms >= 3
                  AND industry_tenure_years >= 5) THEN
                CONCAT(
                    first_name, ' has worked at ', CAST(num_prior_firms + 1 AS STRING), ' different firms over a ',
                    CAST(industry_tenure_years AS STRING), '-year career, currently at ', firm_name, '. ',
                    'This history of mobility demonstrates a willingness to change when the right opportunity appears. ',
                    'Proven Mover tier with 8.59% expected conversion (2.25x baseline).'
                )
            -- V3.3 NEW: TIER_3A - Accelerating Bleeding
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND bleeding_velocity = 'ACCELERATING'
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN
                CONCAT(
                    'The firm ', firm_name, ' has recently started experiencing advisor departures ',
                    '(net change: ', CAST(firm_net_change_12mo AS STRING), ', accelerating in last 90 days). ',
                    'This is the optimal window - ', first_name, ' is watching colleagues leave and evaluating options. ',
                    'Accelerating Bleeder tier - prioritize outreach. ',
                    'Expected conversion ~6% (estimated 1.57x baseline).'
                )
            -- V3.3 UPDATE: Tightened threshold (-15 to -3) and added velocity boost
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN
                CONCAT(
                    'The firm ', firm_name, ' has experienced moderate advisor departures ',
                    '(net change: ', CAST(firm_net_change_12mo AS STRING), ') in the past year. ',
                    CASE WHEN bleeding_velocity = 'ACCELERATING' 
                         THEN 'Bleeding is accelerating - advisors are actively evaluating options. '
                         ELSE '' 
                    END,
                    first_name, ', with ', CAST(industry_tenure_years AS STRING), ' years of experience, is likely having conversations ',
                    'with departing colleagues and hearing about opportunities elsewhere. ',
                    'Moderate Bleeder tier with 5.43% expected conversion (1.42x baseline).'
                )
            WHEN (industry_tenure_years >= 20
                  AND tenure_years BETWEEN 1 AND 4) THEN
                CONCAT(
                    first_name, ' is a ', CAST(industry_tenure_years AS STRING), '-year industry veteran ',
                    'who made a move to ', firm_name, ' just ', CAST(tenure_years AS STRING), ' years ago. ',
                    'A 20+ year veteran who recently changed firms has proven they are not stuck ',
                    'and will move for the right opportunity. ',
                    'Experienced Mover tier with 11.54% expected conversion (3.02x baseline).'
                )
            ELSE
                CONCAT(
                    first_name, ' at ', firm_name, ' does not currently meet priority tier criteria. ',
                    'Profile: ', CAST(tenure_years AS STRING), ' years at current firm, ',
                    CAST(COALESCE(industry_tenure_years, 0) AS STRING), ' years in industry, ',
                    'firm net change: ', CAST(COALESCE(firm_net_change_12mo, 0) AS STRING), '. ',
                    CASE WHEN has_cfp = 1 THEN 'Has CFP certification. ' ELSE '' END,
                    CASE WHEN has_series_65_only = 1 THEN 'Fee-only RIA (Series 65 only). ' ELSE '' END,
                    'Standard tier with 3.82% baseline conversion.'
                )
        END as score_narrative
        
    FROM enriched_prospects ep
),

-- ============================================================================
-- L. FILTER AND RANK
-- ============================================================================
ranked_prospects AS (
    SELECT 
        sp.*,
        CASE 
            WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 1
            WHEN sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids) THEN 2
            ELSE 99
        END as source_priority,
        (CASE WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 0 
              WHEN sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids) THEN 1000
              ELSE 9999 END)
        + (sp.priority_rank * 100)
        + (CASE WHEN sp.firm_net_change_12mo < 0 THEN ABS(sp.firm_net_change_12mo) ELSE 0 END * -1)
        as sort_score,
        ROW_NUMBER() OVER (
            PARTITION BY sp.firm_crd 
            ORDER BY 
                CASE WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 0 ELSE 1 END,
                sp.priority_rank,
                sp.crd
        ) as rank_within_firm
    FROM scored_prospects sp
    WHERE sp.prospect_type = 'NEW_PROSPECT'
       OR sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids)
),

-- ============================================================================
-- M. APPLY FIRM DIVERSITY CAP
-- ============================================================================
diversity_filtered AS (
    SELECT * FROM ranked_prospects
    WHERE rank_within_firm <= 50 AND source_priority < 99
)

-- ============================================================================
-- N. FINAL OUTPUT
-- ============================================================================
SELECT 
    crd as advisor_crd,
    existing_lead_id as salesforce_lead_id,
    first_name,
    last_name,
    email,
    phone,
    firm_name,
    firm_crd,
    firm_rep_count,
    firm_net_change_12mo,
    firm_arrivals_12mo,
    firm_departures_12mo,
    ROUND(firm_turnover_pct, 1) as firm_turnover_pct,
    tenure_months,
    tenure_years,
    industry_tenure_years,
    num_prior_firms,
    moves_3yr,
    score_tier,
    priority_rank,
    expected_conversion_rate,
    ROUND(expected_conversion_rate * 100, 2) as expected_rate_pct,
    score_narrative,
    -- Certification flags (for reference)
    has_cfp,
    has_series_65_only,
    has_series_7,
    has_cfa,
    prospect_type,
    CASE 
        WHEN prospect_type = 'NEW_PROSPECT' THEN 'New - Not in Salesforce'
        ELSE CONCAT('Recyclable - ', CAST({RECYCLABLE_DAYS} AS STRING), '+ days no contact')
    END as lead_source_description,
    ROW_NUMBER() OVER (ORDER BY sort_score, crd) as list_rank,
    CURRENT_TIMESTAMP() as generated_at

FROM diversity_filtered
ORDER BY sort_score, crd
LIMIT {LEAD_LIMIT};

