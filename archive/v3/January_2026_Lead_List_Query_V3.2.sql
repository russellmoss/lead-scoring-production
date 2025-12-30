-- ============================================================================
-- JANUARY 2026 LEAD LIST GENERATOR (V3.3.0 - BLEEDING SIGNAL REFINEMENT)
-- Model: V3.3.0_12302025_BLEEDING_SIGNAL_REFINEMENT
-- 
-- TIER LOGIC: Uses same tier assignment logic as deployed model (ml_features.lead_scores_v3)
-- - Tier logic is calculated inline to match deployed model V3.2.3
-- - All prospects must have PRODUCING_ADVISOR = TRUE (filtered in base_prospects)
-- - FINTRX title and PRODUCING_ADVISOR columns added to output for verification
-- 
-- BUG FIXES APPLIED:
-- 1. Firm rep count: Now uses ria_contacts_current (was using employment_history)
-- 2. Firm arrivals: Now uses ria_contacts_current (was using employment_history)
--    - employment_history only has PAST jobs (4 records with NULL end_date)
--    - ria_contacts_current has CURRENT advisors with accurate start dates
-- 3. Collapsed firms: Excludes firms with <20 reps or >100% turnover
-- 
-- UPDATES:
-- 4. Added LinkedIn profile URLs from FINTRX (LINKEDIN_PROFILE_URL field)
--    - Coverage: ~60-70% of contacts have LinkedIn URLs
--    - Source: ria_contacts_current.LINKEDIN_PROFILE_URL
-- 
-- V3.3 CHANGES:
-- 1. REMOVED TIER_5_HEAVY_BLEEDER (converted at 3.27%, below 3.82% baseline)
-- 2. Implemented inferred departures (60-90 days fresher signal)
-- 3. Tightened TIER_3 threshold from -10/-1 to -15/-3
-- 4. Added bleeding_velocity field (ACCELERATING/STEADY/DECELERATING)
-- 5. Added TIER_3A_ACCELERATING_BLEEDER for optimal timing
--
-- TIER QUOTA SYSTEM (Stratified Sampling):
-- 5. EXCLUDES STANDARD tier leads (only priority tiers with proven lift)
-- 6. Implements tier quotas to ensure diversity and sustainability:
--    - TIER_1A_PRIME_MOVER_CFP: 50 leads (ultra-rare, increased to maximize)
--    - TIER_1B_PRIME_MOVER_SERIES65: 60 leads (rare, increased to maximize)
--    - TIER_1_PRIME_MOVER: 300 leads (strong performers, increased to maximize)
--    - TIER_2_PROVEN_MOVER: 1,500 leads (largest tier, aggressive quota)
--    - TIER_3A_ACCELERATING_BLEEDER: 100 leads (NEW - high value moderate bleeder)
--    - TIER_3_MODERATE_BLEEDER: 300 leads (moderate volume, increased)
--    - TIER_4_EXPERIENCED_MOVER: 300 leads (good performers, increased)
--    TOTAL: ~3,010 priority tier leads (capped at 2,400 via LIMIT)
--    Note: TIER_5 removed - those leads now fall to STANDARD (excluded from list)
-- 
-- USAGE:
-- 1. Replace table name in CREATE OR REPLACE TABLE statement if needed
-- 2. Lead limit is 2,400 (tier quotas ensure diversity, STANDARD tier excluded)
-- 3. Adjust tier quotas in Section O if needed (e.g., increase Tier 1A from 25 to 30)
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.january_2026_lead_list` AS

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
        '%LINCOLN FINANCIAL%', '%MASS MUTUAL%', '%MASSMUTUAL%',
        -- V3.2.4: Insurance firm exclusions
        '%INSURANCE%'
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
-- C. RECYCLABLE LEADS (180+ days no contact)
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
      AND (la.last_activity_date IS NULL OR DATE_DIFF(CURRENT_DATE(), la.last_activity_date, DAY) > 180)
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
-- E. FIRM HEADCOUNT (FIXED - from ria_contacts_current, NOT employment history!)
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
        COUNT(DISTINCT CASE 
            WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN c.RIA_CONTACT_CRD_ID 
        END) as departures_90d,
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
-- G. FIRM ARRIVALS (12 months) - FIXED: Use ria_contacts_current, NOT history!
-- employment_history only has past jobs (end_date NOT NULL)
-- ria_contacts_current has current advisors with accurate start dates
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
        -- Calculate turnover to identify collapsed firms
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
    -- CRITICAL: Exclude collapsed/dead firms
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
      AND c.PRODUCING_ADVISOR = TRUE  -- V3.2.3: Filter to only producing advisors
      AND NOT EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern)
      -- V3.2.1 Title Exclusions: Data-driven exclusions based on 72,055 historical leads analysis
      AND NOT (
          -- HARD EXCLUSIONS: 0% conversion titles with n >= 30
          UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTIONS ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTION ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE WEALTH ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS MANAGER%'
          OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR OF OPERATIONS%'
          OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS SPECIALIST%'
          OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS ASSOCIATE%'
          OR UPPER(c.TITLE_NAME) LIKE '%CHIEF OPERATING OFFICER%'
          OR UPPER(c.TITLE_NAME) LIKE '%FIRST VICE PRESIDENT%'
          OR UPPER(c.TITLE_NAME) LIKE '%WHOLESALER%'
          OR UPPER(c.TITLE_NAME) LIKE '%INTERNAL WHOLESALER%'
          OR UPPER(c.TITLE_NAME) LIKE '%EXTERNAL WHOLESALER%'
          OR UPPER(c.TITLE_NAME) LIKE '%INTERNAL SALES%'
          OR UPPER(c.TITLE_NAME) LIKE '%EXTERNAL SALES%'
          OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE OFFICER%'
          OR UPPER(c.TITLE_NAME) LIKE '%CHIEF COMPLIANCE%'
          OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE MANAGER%'
          OR UPPER(c.TITLE_NAME) LIKE '%SUPERVISION%'
          OR UPPER(c.TITLE_NAME) LIKE '%REGISTERED ASSISTANT%'
          OR UPPER(c.TITLE_NAME) LIKE '%CLIENT SERVICE ASSOCIATE%'
          OR UPPER(c.TITLE_NAME) LIKE '%SALES ASSISTANT%'
          OR UPPER(c.TITLE_NAME) LIKE '%ADMINISTRATIVE ASSISTANT%'
          OR UPPER(c.TITLE_NAME) LIKE '%BRANCH OFFICE ADMINISTRATOR%'
          OR (UPPER(c.TITLE_NAME) LIKE '%ANALYST%' 
              AND UPPER(c.TITLE_NAME) NOT LIKE '%INVESTMENT ANALYST%'
              AND UPPER(c.TITLE_NAME) NOT LIKE '%FINANCIAL ANALYST%'
              AND UPPER(c.TITLE_NAME) NOT LIKE '%PORTFOLIO ANALYST%')
          OR UPPER(c.TITLE_NAME) = 'SENIOR VICE PRESIDENT, FINANCIAL ADVISOR'
          OR UPPER(c.TITLE_NAME) = 'SENIOR VICE PRESIDENT, WEALTH MANAGEMENT ADVISOR'
          OR UPPER(c.TITLE_NAME) = 'SENIOR VICE PRESIDENT, SENIOR FINANCIAL ADVISOR'
          OR UPPER(c.TITLE_NAME) = 'VICE PRESIDENT, SENIOR FINANCIAL ADVISOR'
          -- V3.2.4: Insurance title exclusions
          OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE AGENT%'
          OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE%'
      )
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
        
        -- FIXED: Use firm_metrics instead of firm_flows
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
             THEN 1 ELSE 0 END as has_cfa,
        
        -- High-Value Wealth Title flag (V3.2.2)
        CASE WHEN (
            (UPPER(c.TITLE_NAME) LIKE '%WEALTH MANAGER%' 
             AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%'
             AND UPPER(c.TITLE_NAME) NOT LIKE '%ASSOCIATE%'
             AND UPPER(c.TITLE_NAME) NOT LIKE '%ASSISTANT%')
            OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%WEALTH%DIRECTOR%'
            OR (UPPER(c.TITLE_NAME) LIKE '%SENIOR VICE%WEALTH%' 
                AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%')
            OR (UPPER(c.TITLE_NAME) LIKE '%SVP%WEALTH%'
                AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%')
            OR UPPER(c.TITLE_NAME) LIKE '%SENIOR WEALTH ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%FOUNDER%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%WEALTH%FOUNDER%'
            OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%WEALTH%PRINCIPAL%'
            OR (UPPER(c.TITLE_NAME) LIKE '%PARTNER%WEALTH%'
                AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%')
            OR UPPER(c.TITLE_NAME) LIKE '%PRESIDENT%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%WEALTH%PRESIDENT%'
            OR (UPPER(c.TITLE_NAME) LIKE '%MANAGING DIRECTOR%WEALTH%'
                AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%')
        ) THEN 1 ELSE 0 END as is_hv_wealth_title,
        
        -- LinkedIn profile URL from FINTRX
        c.LINKEDIN_PROFILE_URL as linkedin_url,
        
        -- LinkedIn availability flag (V3.2.5 - for prioritization)
        CASE WHEN c.LINKEDIN_PROFILE_URL IS NOT NULL 
             AND TRIM(c.LINKEDIN_PROFILE_URL) != '' 
             THEN 1 ELSE 0 END as has_linkedin,
        
        -- FINTRX Title (V3.2.3 - for export)
        c.TITLE_NAME as fintrx_title,
        
        -- PRODUCING_ADVISOR boolean (V3.2.3 - for verification)
        c.PRODUCING_ADVISOR as producing_advisor
        
    FROM base_prospects bp
    LEFT JOIN advisor_moves am ON bp.crd = am.crd
    LEFT JOIN firm_metrics fm ON bp.firm_crd = fm.firm_crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c ON bp.crd = c.RIA_CONTACT_CRD_ID
    -- Exclude advisors at collapsed firms (turnover > 100% indicates firm is dying)
    WHERE COALESCE(fm.turnover_pct, 0) < 100
),

-- ============================================================================
-- K. APPLY V3.2 TIER LOGIC
-- ============================================================================
scored_prospects AS (
    SELECT 
        ep.*,
        
        -- Tier qualification path (V3.2.1 - includes certification tiers)
        CASE 
            -- Tier 1A: CFP at bleeding firm
            WHEN (tenure_years BETWEEN 1 AND 4
                  AND industry_tenure_years >= 5
                  AND firm_net_change_12mo < 0
                  AND has_cfp = 1
                  AND is_wirehouse = 0) THEN 'TIER_1A_CFP'
            -- Tier 1B: Series 65 only + Tier 1 criteria
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 'TIER_1B_SERIES65'
            -- Standard Tier 1 paths
            WHEN (tenure_years BETWEEN 1 AND 3
                  AND industry_tenure_years BETWEEN 5 AND 15
                  AND firm_net_change_12mo < 0
                  AND firm_rep_count <= 50
                  AND is_wirehouse = 0) THEN 'TIER_1_PATH_1A'
            WHEN (tenure_years BETWEEN 1 AND 3
                  AND firm_rep_count <= 10
                  AND is_wirehouse = 0) THEN 'TIER_1_PATH_1B'
            WHEN (tenure_years BETWEEN 1 AND 4
                  AND industry_tenure_years BETWEEN 5 AND 15
                  AND firm_net_change_12mo < 0
                  AND is_wirehouse = 0) THEN 'TIER_1_PATH_1C'
            -- Tier 1F: HV Wealth + Bleeding Firm (V3.2.2)
            WHEN (is_hv_wealth_title = 1
                  AND firm_net_change_12mo < 0
                  AND is_wirehouse = 0) THEN 'TIER_1F_HV_WEALTH'
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 'TIER_2_PROVEN_MOVER'
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5) THEN 'TIER_3_MODERATE_BLEEDER'
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 'TIER_4_EXPERIENCED_MOVER'
            WHEN (firm_net_change_12mo <= -10 AND industry_tenure_years >= 5) THEN 'TIER_5_HEAVY_BLEEDER'
            ELSE 'STANDARD'
        END as tier_qualification_path,
        
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
            -- Tier 1F: HV Wealth + Bleeding Firm (V3.2.2)
            WHEN (is_hv_wealth_title = 1
                  AND firm_net_change_12mo < 0
                  AND is_wirehouse = 0) THEN 'TIER_1F_HV_WEALTH_BLEEDER'
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 'TIER_2_PROVEN_MOVER'
            -- V3.3 NEW: TIER_3A - Accelerating Bleeding
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND bleeding_velocity = 'ACCELERATING'
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 'TIER_3A_ACCELERATING_BLEEDER'
            -- V3.3 UPDATE: Tightened threshold (-15 to -3)
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 'TIER_3_MODERATE_BLEEDER'
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 'TIER_4_EXPERIENCED_MOVER'
            -- V3.3 UPDATE: TIER_5_HEAVY_BLEEDER REMOVED
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
            WHEN (is_hv_wealth_title = 1
                  AND firm_net_change_12mo < 0
                  AND is_wirehouse = 0) THEN 6
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
            WHEN (is_hv_wealth_title = 1
                  AND firm_net_change_12mo < 0
                  AND is_wirehouse = 0) THEN 0.1278
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
                    'Prime Mover tier with 15.92% expected conversion (4.63x baseline).'
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
                    'Prime Mover with 15.92% expected conversion (4.63x baseline).'
                )
            -- Tier 1F: HV Wealth + Bleeding Firm (V3.2.2)
            WHEN (is_hv_wealth_title = 1
                  AND firm_net_change_12mo < 0
                  AND is_wirehouse = 0) THEN
                CONCAT(
                    first_name, ' holds a High-Value Wealth title (Wealth Manager, Director, Senior Advisor, Founder/Principal/Partner) at ', firm_name,
                    ', which has lost ', CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors (net) in the past year. ',
                    'This combination of ownership-level title and firm instability historically converts at 12.78% (3.35x baseline). ',
                    'The title indicates book ownership and client relationships, making this advisor highly portable. ',
                    'Tier 1F: HV Wealth (Bleeding) - High priority lead.'
                )
            WHEN (num_prior_firms >= 3
                  AND industry_tenure_years >= 5) THEN
                CONCAT(
                    first_name, ' has worked at ', CAST(num_prior_firms + 1 AS STRING), ' different firms over a ',
                    CAST(industry_tenure_years AS STRING), '-year career, currently at ', firm_name, '. ',
                    'This history of mobility demonstrates a willingness to change when the right opportunity appears. ',
                    'Proven Mover tier with 8.59% expected conversion (2.50x baseline).'
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
                    'Experienced Mover tier with 11.54% expected conversion (3.35x baseline).'
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
        + (CASE WHEN sp.has_linkedin = 1 THEN 0 ELSE 10000 END)  -- V3.2.5: Prioritize LinkedIn leads
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
),

-- ============================================================================
-- N. APPLY TIER QUOTAS (Stratified Sampling)
-- ============================================================================
-- Exclude STANDARD tier and apply tier-specific quotas to ensure diversity
-- Within each tier, prioritize: NEW prospects > recyclable, then by firm bleeding severity
-- Firm diversity cap (50 leads/firm) already applied in previous step
-- ============================================================================
tier_limited AS (
    SELECT 
        df.*,
        ROW_NUMBER() OVER (
            PARTITION BY df.score_tier
            ORDER BY 
                df.source_priority,  -- NEW_PROSPECT (1) before recyclable (2)
                df.has_linkedin DESC,  -- V3.2.5: Prioritize LinkedIn leads within tier
                df.priority_rank,     -- Within source, by tier priority
                CASE WHEN df.firm_net_change_12mo < 0 
                     THEN ABS(df.firm_net_change_12mo) 
                     ELSE 0 END DESC,  -- More bleeding = higher priority
                df.crd                -- Tie-breaker: CRD ID
        ) as tier_rank
    FROM diversity_filtered df
    WHERE df.score_tier != 'STANDARD'  -- EXCLUDE STANDARD tier (only priority tiers with proven lift)
),

-- ============================================================================
-- O. LINKEDIN PRIORITIZATION & CAP (V3.2.5)
-- ============================================================================
-- Ensure leads with LinkedIn URLs are prioritized
-- Limit leads without LinkedIn to <10% of final list
-- ============================================================================
linkedin_prioritized AS (
    SELECT 
        tl.*,
        -- Rank all leads, prioritizing LinkedIn
        ROW_NUMBER() OVER (
            ORDER BY 
                CASE score_tier
                    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
                    WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
                    WHEN 'TIER_1_PRIME_MOVER' THEN 3
                    WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 6
                    WHEN 'TIER_2_PROVEN_MOVER' THEN 7
                    WHEN 'TIER_3A_ACCELERATING_BLEEDER' THEN 5
                    WHEN 'TIER_3_MODERATE_BLEEDER' THEN 6
                    WHEN 'TIER_4_EXPERIENCED_MOVER' THEN 7
                END,
                source_priority,
                has_linkedin DESC,  -- LinkedIn leads first
                sort_score,
                crd
        ) as overall_rank,
        -- Separate ranking for non-LinkedIn leads (to cap at 10%)
        CASE 
            WHEN has_linkedin = 0 THEN
                ROW_NUMBER() OVER (
                    ORDER BY 
                        CASE score_tier
                            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
                            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
                            WHEN 'TIER_1_PRIME_MOVER' THEN 3
                            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 6
                            WHEN 'TIER_2_PROVEN_MOVER' THEN 7
                            WHEN 'TIER_3_MODERATE_BLEEDER' THEN 8
                            WHEN 'TIER_4_EXPERIENCED_MOVER' THEN 9
                            WHEN 'TIER_5_HEAVY_BLEEDER' THEN 10
                        END,
                        source_priority,
                        sort_score,
                        crd
                )
            ELSE NULL
        END as no_linkedin_rank
    FROM tier_limited tl
    WHERE 
        -- Apply tier quotas (same as before)
        (score_tier = 'TIER_1A_PRIME_MOVER_CFP' AND tier_rank <= 50)
        OR (score_tier = 'TIER_1B_PRIME_MOVER_SERIES65' AND tier_rank <= 60)
        OR (score_tier = 'TIER_1_PRIME_MOVER' AND tier_rank <= 300)
        OR (score_tier = 'TIER_1F_HV_WEALTH_BLEEDER' AND tier_rank <= 50)
        OR (score_tier = 'TIER_2_PROVEN_MOVER' AND tier_rank <= 1500)
        OR (score_tier = 'TIER_3A_ACCELERATING_BLEEDER' AND tier_rank <= 100)
        OR (score_tier = 'TIER_3_MODERATE_BLEEDER' AND tier_rank <= 300)
        OR (score_tier = 'TIER_4_EXPERIENCED_MOVER' AND tier_rank <= 300)
)

-- ============================================================================
-- P. FINAL OUTPUT (Apply LinkedIn Cap)
-- ============================================================================
SELECT 
    crd as advisor_crd,
    existing_lead_id as salesforce_lead_id,
    first_name,
    last_name,
    email,
    phone,
    linkedin_url,
    has_linkedin,  -- V3.2.5: LinkedIn availability flag
    fintrx_title,  -- V3.2.3: FINTRX title (to the left of firm_name)
    producing_advisor,  -- V3.2.3: PRODUCING_ADVISOR boolean (should all be TRUE)
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
    tier_qualification_path,
    priority_rank,
    expected_conversion_rate,
    ROUND(expected_conversion_rate * 100, 2) as expected_rate_pct,
    score_narrative,
    -- Certification flags (for reference)
    has_cfp,
    has_series_65_only,
    has_series_7,
    has_cfa,
    is_hv_wealth_title,
    prospect_type,
    CASE 
        WHEN prospect_type = 'NEW_PROSPECT' THEN 'New - Not in Salesforce'
        ELSE 'Recyclable - 180+ days no contact'
    END as lead_source_description,
    overall_rank as list_rank,
    CURRENT_TIMESTAMP() as generated_at

FROM linkedin_prioritized
WHERE 
    -- V3.2.5: Limit non-LinkedIn leads to <10% of final list (max 240 leads out of 2,400)
    -- All LinkedIn leads are included, non-LinkedIn leads capped at 10%
    has_linkedin = 1 
    OR (has_linkedin = 0 AND no_linkedin_rank <= 240)  -- Max 10% without LinkedIn
ORDER BY 
    overall_rank
LIMIT 2400;