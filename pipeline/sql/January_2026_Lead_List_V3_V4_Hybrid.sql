-- ============================================================================
-- JANUARY 2026 LEAD LIST GENERATOR (V3.3.1 + V4.1.0 R3 HYBRID)
-- ============================================================================
-- Version: 2.2 with V3.3.1 Portable Book Exclusions (Updated 2025-12-31)
-- 
-- V4.1 INTEGRATION CHANGES:
-- - Scores table: ml_features.v4_prospect_scores (SAME NAME, updated with V4.1 scores)
-- - Features: 22 (was 14)
-- - New columns: is_recent_mover, days_since_last_move, firm_departures_corrected,
--                bleeding_velocity_encoded, is_dual_registered
-- - Disagreement threshold: 60th percentile (was 70th) - V4.1 is more accurate
-- 
-- V4.1 PERFORMANCE IMPROVEMENTS:
-- - Test AUC-ROC: 0.620 (+3.5% vs V4.0.0)
-- - Top Decile Lift: 2.03x (+34% vs V4.0.0)
-- - Better bleeding signal detection
-- 
-- FEATURES:
-- - V3 Rules: Tier assignment with rich human-readable narratives
-- - V4.1 XGBoost: Upgrade path with SHAP-based narratives
-- - Job Titles: Included in output for SDR context
-- - Firm Exclusions: Managed in ml_features.excluded_firms table
--                    (easier to maintain - no SQL edits needed)
--
-- FIRM EXCLUSIONS:
-- - Savvy Advisors, Inc. (CRD 318493) - Internal firm
-- - Ritholtz Wealth Management (CRD 168652) - Partner firm
--
-- OUTPUT: ml_features.january_2026_lead_list (NEW SINGLE TABLE - replaces old tables)
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.january_2026_lead_list` AS

WITH 
-- ============================================================================
-- A. ACTIVE SGAs (Dynamic - pulls from Salesforce User table)
-- ============================================================================
-- Moved to beginning to calculate total leads needed (200 per SGA)
active_sgas AS (
    SELECT 
        Id as sga_id,
        Name as sga_name,
        ROW_NUMBER() OVER (ORDER BY Name) as sga_number,
        COUNT(*) OVER () as total_sgas,
        COUNT(*) OVER () * 200 as total_leads_needed
    FROM `savvy-gtm-analytics.SavvyGTMData.User`
    WHERE IsActive = true
      AND IsSGA__c = true
      AND Name NOT IN ('Jacqueline Tully', 'GinaRose', 'Savvy Marketing', 'Savvy Operations', 'Anett Davis', 'Anett Diaz')
),

-- Get SGA constants for use throughout query
sga_constants AS (
    SELECT 
        MAX(total_sgas) as total_sgas,
        MAX(total_leads_needed) as total_leads_needed,
        MAX(total_sgas) * 200 as leads_per_sga
    FROM active_sgas
),

-- ============================================================================
-- B. EXCLUSIONS (Reference centralized tables)
-- ============================================================================
-- Firm exclusions now managed in: ml_features.excluded_firms
-- To add/remove exclusions, update that table instead of this SQL
-- ============================================================================
excluded_firms AS (
    SELECT pattern as firm_pattern
    FROM `savvy-gtm-analytics.ml_features.excluded_firms`
),

-- Specific CRD exclusions managed in: ml_features.excluded_firm_crds
excluded_firm_crds AS (
    SELECT firm_crd
    FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
),

-- ============================================================================
-- C. EXISTING SALESFORCE CRDs
-- ============================================================================
salesforce_crds AS (
    SELECT DISTINCT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE FA_CRD__c IS NOT NULL AND IsDeleted = false
),

-- ============================================================================
-- D. RECYCLABLE LEADS (180+ days no contact)
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
-- E. ADVISOR EMPLOYMENT HISTORY
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
-- F. FIRM HEADCOUNT
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
-- G. FIRM DEPARTURES
-- ============================================================================
firm_departures AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),

-- ============================================================================
-- H. FIRM ARRIVALS
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
             ELSE 0 END as turnover_pct
    FROM firm_headcount h
    LEFT JOIN firm_departures d ON h.firm_crd = d.firm_crd
    LEFT JOIN firm_arrivals a ON h.firm_crd = a.firm_crd
    WHERE h.current_reps >= 20
),

-- ============================================================================
-- J. BASE PROSPECT DATA (with firm CRD exclusions)
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
        sf.lead_id as existing_lead_id,
        -- JOB TITLE (NEW!)
        c.TITLE_NAME as job_title
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN salesforce_crds sf ON c.RIA_CONTACT_CRD_ID = sf.crd
    -- Exclude by firm name pattern (LEFT JOIN approach for BigQuery compatibility)
    LEFT JOIN excluded_firms ef ON UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
    -- Exclude by firm CRD
    LEFT JOIN excluded_firm_crds ec ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ec.firm_crd
    WHERE c.CONTACT_FIRST_NAME IS NOT NULL AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM_START_DATE IS NOT NULL AND c.PRIMARY_FIRM_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
      AND c.PRODUCING_ADVISOR = TRUE
      -- Exclude matched patterns and CRDs
      AND ef.firm_pattern IS NULL
      AND ec.firm_crd IS NULL
      -- Title exclusions
      AND NOT (
          UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTIONS ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS%'
          OR UPPER(c.TITLE_NAME) LIKE '%WHOLESALER%'
          OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSISTANT%'
          OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE AGENT%'
          OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE%'
      )
),

-- ============================================================================
-- K. ENRICH WITH ADVISOR HISTORY, FIRM METRICS, AND CERTIFICATIONS
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
        CASE WHEN EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(bp.firm_name) LIKE ef.firm_pattern) THEN 1 ELSE 0 END as is_wirehouse,
        
        -- Certifications
        CASE WHEN c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%' THEN 1 ELSE 0 END as has_cfp,
        CASE WHEN c.REP_LICENSES LIKE '%Series 65%' AND c.REP_LICENSES NOT LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_65_only,
        CASE WHEN c.REP_LICENSES LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_7,
        CASE WHEN c.CONTACT_BIO LIKE '%CFA%' OR c.TITLE_NAME LIKE '%CFA%' THEN 1 ELSE 0 END as has_cfa,
        
        -- High-value wealth title
        CASE WHEN (
            UPPER(c.TITLE_NAME) LIKE '%WEALTH MANAGER%'
            OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%SENIOR WEALTH ADVISOR%'
        ) THEN 1 ELSE 0 END as is_hv_wealth_title,
        
        -- LinkedIn
        c.LINKEDIN_PROFILE_URL as linkedin_url,
        CASE WHEN c.LINKEDIN_PROFILE_URL IS NOT NULL AND TRIM(c.LINKEDIN_PROFILE_URL) != '' THEN 1 ELSE 0 END as has_linkedin,
        c.PRODUCING_ADVISOR as producing_advisor
        
    FROM base_prospects bp
    LEFT JOIN advisor_moves am ON bp.crd = am.crd
    LEFT JOIN firm_metrics fm ON bp.firm_crd = fm.firm_crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c ON bp.crd = c.RIA_CONTACT_CRD_ID
    -- V3.3.1: Add discretionary ratio for portable book exclusion
    LEFT JOIN (
        SELECT 
            CRD_ID as firm_crd,
            SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) as discretionary_ratio,
            CASE 
                WHEN TOTAL_AUM IS NULL OR TOTAL_AUM = 0 THEN 'UNKNOWN'
                WHEN SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) < 0.50 THEN 'LOW_DISCRETIONARY'
                WHEN SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) >= 0.80 THEN 'HIGH_DISCRETIONARY'
                ELSE 'MODERATE_DISCRETIONARY'
            END as discretionary_tier
        FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    ) fd ON bp.firm_crd = fd.firm_crd
    WHERE COALESCE(fm.turnover_pct, 0) < 100
      -- V3.3.1: Exclude low discretionary firms (0.34x baseline)
      -- Allow NULL/Unknown - don't penalize missing data
      AND (fd.discretionary_ratio >= 0.50 OR fd.discretionary_ratio IS NULL)
),

-- ============================================================================
-- J2. JOIN V4 SCORES + SHAP NARRATIVES + V4.1 FEATURES
-- ============================================================================
v4_enriched AS (
    SELECT 
        ep.*,
        -- V4.1 Score and percentile (from v4_prospect_scores table)
        COALESCE(v4.v4_score, 0.5) as v4_score,
        COALESCE(v4.v4_percentile, 50) as v4_percentile,
        COALESCE(v4.v4_deprioritize, FALSE) as v4_deprioritize,
        COALESCE(v4.v4_upgrade_candidate, FALSE) as v4_upgrade_candidate,
        
        -- V4.1 SHAP narratives (from scores table)
        v4.shap_top1_feature,
        v4.shap_top1_value,
        v4.shap_top2_feature,
        v4.shap_top2_value,
        v4.shap_top3_feature,
        v4.shap_top3_value,
        v4.v4_narrative as v4_shap_narrative,
        
        -- NEW V4.1 Feature columns (from v4_prospect_features table)
        COALESCE(v4f.is_recent_mover, 0) as v4_is_recent_mover,
        COALESCE(v4f.days_since_last_move, 9999) as v4_days_since_last_move,
        COALESCE(v4f.firm_departures_corrected, 0) as v4_firm_departures_corrected,
        COALESCE(v4f.bleeding_velocity_encoded, 0) as v4_bleeding_velocity_encoded,
        COALESCE(v4f.is_dual_registered, 0) as v4_is_dual_registered
    FROM enriched_prospects ep
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 
        ON ep.crd = v4.crd
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_features` v4f
        ON ep.crd = v4f.crd
),

-- ============================================================================
-- K. APPLY V4 DEPRIORITIZATION FILTER (Bottom 20% excluded)
-- ============================================================================
-- Optimization: Remove bottom 20% V4 scores to improve overall conversion rate
v4_filtered AS (
    SELECT *
    FROM v4_enriched
    WHERE v4_percentile >= 20 OR v4_percentile IS NULL  -- Filter bottom 20%
),

-- ============================================================================
-- K2. APPLY V3.2 TIER LOGIC WITH NARRATIVES
-- ============================================================================
scored_prospects AS (
    SELECT 
        ep.*,
        
        -- Score tier
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years >= 5 AND firm_net_change_12mo < 0 AND has_cfp = 1 AND is_wirehouse = 0) THEN 'TIER_1A_PRIME_MOVER_CFP'
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 'TIER_1_PRIME_MOVER'
            WHEN (is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND is_wirehouse = 0) THEN 'TIER_1F_HV_WEALTH_BLEEDER'
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 'TIER_2_PROVEN_MOVER'
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5) THEN 'TIER_3_MODERATE_BLEEDER'
            -- OPTION C: TIER_4_EXPERIENCED_MOVER EXCLUDED (converts at baseline 2.74%, no value)
            -- OPTION C: TIER_5_HEAVY_BLEEDER EXCLUDED (marginal lift 3.42%, not worth including)
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 'STANDARD'  -- Map to STANDARD (excluded)
            WHEN (firm_net_change_12mo <= -10 AND industry_tenure_years >= 5) THEN 'STANDARD'  -- Map to STANDARD (excluded)
            ELSE 'STANDARD'
        END as score_tier,
        
        -- Priority rank
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years >= 5 AND firm_net_change_12mo < 0 AND has_cfp = 1 AND is_wirehouse = 0) THEN 1
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 2
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 3
            WHEN (is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND is_wirehouse = 0) THEN 4
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 5
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5) THEN 6
            -- OPTION C: TIER_4 and TIER_5 excluded (map to 99)
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 99  -- TIER_4 excluded
            WHEN (firm_net_change_12mo <= -10 AND industry_tenure_years >= 5) THEN 99  -- TIER_5 excluded
            ELSE 99
        END as priority_rank,
        
        -- Expected conversion rate
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years >= 5 AND firm_net_change_12mo < 0 AND has_cfp = 1 AND is_wirehouse = 0) THEN 0.087
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 0.079
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 0.071
            WHEN (is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND is_wirehouse = 0) THEN 0.065
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 0.052
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5) THEN 0.044
            -- OPTION C: TIER_4 and TIER_5 excluded (map to STANDARD rate)
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 0.025  -- TIER_4 excluded
            WHEN (firm_net_change_12mo <= -10 AND industry_tenure_years >= 5) THEN 0.025  -- TIER_5 excluded
            ELSE 0.025
        END as expected_conversion_rate,
        
        -- V3 TIER NARRATIVES
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years >= 5 AND firm_net_change_12mo < 0 AND has_cfp = 1 AND is_wirehouse = 0) THEN
                CONCAT(first_name, ' is a CFP holder at ', firm_name, ', which has lost ', CAST(ABS(firm_net_change_12mo) AS STRING), 
                       ' advisors (net) in the past year. CFP designation indicates book ownership and client relationships. ',
                       'With ', CAST(tenure_years AS STRING), ' years at the firm and ', CAST(industry_tenure_years AS STRING), 
                       ' years of experience, this is an ULTRA-PRIORITY lead. Tier 1A: 8.7% expected conversion.')
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN
                CONCAT(first_name, ' is a fee-only RIA advisor (Series 65 only) at ', firm_name, 
                       '. Pure RIA advisors have no broker-dealer ties, making transitions easier. ',
                       'Tier 1B: Prime Mover (Pure RIA) with 7.9% expected conversion.')
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN
                CONCAT(first_name, ' has been at ', firm_name, ' for ', CAST(tenure_years AS STRING), ' years with ', 
                       CAST(industry_tenure_years AS STRING), ' years of experience. ',
                       CASE WHEN firm_net_change_12mo < 0 THEN CONCAT('The firm has lost ', CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors. ') ELSE '' END,
                       'Prime Mover tier with 7.1% expected conversion.')
            WHEN (is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND is_wirehouse = 0) THEN
                CONCAT(first_name, ' holds a High-Value Wealth title at ', firm_name, ', which has lost ', 
                       CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors. Tier 1F: HV Wealth (Bleeding) with 6.5% expected conversion.')
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN
                CONCAT(first_name, ' has worked at ', CAST(num_prior_firms + 1 AS STRING), ' different firms over ', 
                       CAST(industry_tenure_years AS STRING), ' years. History of mobility demonstrates willingness to change. ',
                       'Proven Mover tier with 5.2% expected conversion.')
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5) THEN
                CONCAT(firm_name, ' has experienced moderate advisor departures (net change: ', CAST(firm_net_change_12mo AS STRING), '). ',
                       first_name, ' is likely hearing about opportunities from departing colleagues. Moderate Bleeder tier: 4.4% expected conversion.')
            -- OPTION C: TIER_4 and TIER_5 excluded (map to STANDARD narrative)
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN
                CONCAT(first_name, ' at ', firm_name, ' - STANDARD tier lead (TIER_4 excluded per Option C optimization).')
            WHEN (firm_net_change_12mo <= -10 AND industry_tenure_years >= 5) THEN
                CONCAT(first_name, ' at ', firm_name, ' - STANDARD tier lead (TIER_5 excluded per Option C optimization).')
            ELSE
                CONCAT(first_name, ' at ', firm_name, ' - STANDARD tier lead.')
        END as v3_score_narrative
        
    FROM v4_filtered ep
),

-- ============================================================================
-- M. RANK PROSPECTS
-- ============================================================================
ranked_prospects AS (
    SELECT 
        sp.*,
        CASE 
            WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 1
            WHEN sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids) THEN 2
            ELSE 99
        END as source_priority,
        ROW_NUMBER() OVER (
            PARTITION BY sp.firm_crd 
            ORDER BY 
                CASE WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 0 ELSE 1 END,
                sp.priority_rank,
                sp.v4_percentile DESC,
                sp.crd
        ) as rank_within_firm
    FROM scored_prospects sp
    WHERE sp.prospect_type = 'NEW_PROSPECT'
       OR sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids)
),

-- ============================================================================
-- N. APPLY FIRM DIVERSITY CAP
-- ============================================================================
diversity_filtered AS (
    SELECT * FROM ranked_prospects
    WHERE rank_within_firm <= 50 
      AND source_priority < 99
),

-- ============================================================================
-- O. APPLY TIER QUOTAS + HIGH-V4 STANDARD BACKFILL (Dynamic based on SGA count)
-- ============================================================================
-- Optimization: Removed V4_UPGRADE tier (underperforms). Use high-V4 STANDARD for backfill only.
tier_limited AS (
    SELECT 
        df.*,
        -- High-V4 STANDARD flag (for backfill only, not a separate tier)
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 1 
            ELSE 0 
        END as is_high_v4_standard,
        -- Final tier (keep STANDARD, mark as HIGH_V4 for backfill)
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 'STANDARD_HIGH_V4'
            ELSE df.score_tier 
        END as final_tier,
        -- Final expected rate (updated based on optimization analysis)
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 0.035  -- High-V4 STANDARD: 3.5%
            WHEN df.score_tier = 'TIER_1B_PRIME_MOVER_SERIES65' THEN 0.1176  -- Updated from optimization
            WHEN df.score_tier = 'TIER_1F_HV_WEALTH_BLEEDER' THEN 0.0606  -- Updated from optimization
            WHEN df.score_tier = 'TIER_2_PROVEN_MOVER' THEN 0.0591  -- Updated from optimization
            WHEN df.score_tier = 'TIER_1_PRIME_MOVER' THEN 0.0476  -- Updated from optimization
            WHEN df.score_tier = 'TIER_1A_PRIME_MOVER_CFP' THEN 0.0274  -- Updated from optimization
            ELSE df.expected_conversion_rate 
        END as final_expected_rate,
        -- FINAL NARRATIVE: V3 or High-V4 STANDARD (with SHAP features)
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN
                CONCAT(
                    df.first_name, ' at ', df.firm_name, ' - ML model identified key signals: ',
                    CASE df.shap_top1_feature
                        WHEN 'is_ia_rep_type' THEN 'pure investment advisor (no BD ties)'
                        WHEN 'is_independent_ria' THEN 'independent RIA (portable book)'
                        WHEN 'is_dual_registered' THEN 'dual-registered (flexible transition options)'
                        WHEN 'mobility_3yr' THEN 'history of firm moves'
                        WHEN 'short_tenure_x_high_mobility' THEN 'short tenure combined with high mobility'
                        WHEN 'mobility_x_heavy_bleeding' THEN 'mobile advisor at a firm losing advisors'
                        WHEN 'experience_years' THEN 'significant industry experience'
                        WHEN 'tenure_months' THEN 'tenure pattern suggests transition readiness'
                        WHEN 'firm_net_change_12mo' THEN 'firm instability (net advisor losses)'
                        WHEN 'firm_departures_corrected' THEN 'firm experiencing departures'
                        WHEN 'bleeding_velocity_encoded' THEN 'accelerating firm departures'
                        WHEN 'is_recent_mover' THEN 'recently changed firms (proven mobility)'
                        WHEN 'days_since_last_move' THEN 'timing since last move suggests readiness'
                        WHEN 'has_firm_data' THEN 'strong data profile'
                        WHEN 'has_email' THEN 'contactable (email available)'
                        WHEN 'has_linkedin' THEN 'professional presence (LinkedIn)'
                        WHEN 'is_wirehouse' THEN 'wirehouse advisor (large book potential)'
                        WHEN 'is_broker_protocol' THEN 'broker protocol firm (easier transition)'
                        ELSE REPLACE(df.shap_top1_feature, '_', ' ')
                    END,
                    CASE WHEN df.shap_top2_feature IS NOT NULL THEN CONCAT(', ',
                        CASE df.shap_top2_feature
                            WHEN 'is_ia_rep_type' THEN 'IA rep type'
                            WHEN 'is_independent_ria' THEN 'independent RIA'
                            WHEN 'is_dual_registered' THEN 'dual-registered'
                            WHEN 'mobility_3yr' THEN 'mobility history'
                            WHEN 'short_tenure_x_high_mobility' THEN 'short tenure + mobility'
                            WHEN 'mobility_x_heavy_bleeding' THEN 'mobile + bleeding firm'
                            WHEN 'experience_years' THEN 'experience level'
                            WHEN 'firm_net_change_12mo' THEN 'firm instability'
                            WHEN 'firm_departures_corrected' THEN 'firm departures'
                            WHEN 'bleeding_velocity_encoded' THEN 'departure acceleration'
                            WHEN 'is_recent_mover' THEN 'recent mover'
                            WHEN 'has_firm_data' THEN 'data quality'
                            ELSE REPLACE(df.shap_top2_feature, '_', ' ')
                        END
                    ) ELSE '' END,
                    CASE WHEN df.shap_top3_feature IS NOT NULL THEN CONCAT(', ',
                        CASE df.shap_top3_feature
                            WHEN 'is_ia_rep_type' THEN 'IA rep type'
                            WHEN 'is_independent_ria' THEN 'independent RIA'
                            WHEN 'is_dual_registered' THEN 'dual-registered'
                            WHEN 'mobility_3yr' THEN 'mobility pattern'
                            WHEN 'experience_years' THEN 'experience'
                            WHEN 'has_firm_data' THEN 'profile completeness'
                            ELSE REPLACE(df.shap_top3_feature, '_', ' ')
                        END
                    ) ELSE '' END,
                    '. V4 Score: ', CAST(df.v4_percentile AS STRING), 'th percentile. Expected conversion: 3.5%.'
                )
            ELSE df.v3_score_narrative
        END as score_narrative,
        ROW_NUMBER() OVER (
            PARTITION BY 
                CASE 
                    WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 'STANDARD_HIGH_V4'
                    ELSE df.score_tier 
                END
            ORDER BY 
                df.source_priority,
                df.has_linkedin DESC,
                df.v4_percentile DESC,
                df.priority_rank,
                CASE WHEN df.firm_net_change_12mo < 0 THEN ABS(df.firm_net_change_12mo) ELSE 0 END DESC,
                df.crd
        ) as tier_rank
    FROM diversity_filtered df
    -- Priority tiers always included; STANDARD only if high-V4 (for backfill)
    -- OPTION C: EXCLUDE TIER_4 and TIER_5 (they convert at/below baseline)
    WHERE (df.score_tier != 'STANDARD' AND df.score_tier NOT IN ('TIER_4_EXPERIENCED_MOVER', 'TIER_5_HEAVY_BLEEDER'))
       OR (df.score_tier = 'STANDARD' AND df.v4_percentile >= 80)
),

-- ============================================================================
-- P. DEDUPLICATE BEFORE TIER QUOTAS (CRITICAL: Preserve priority tier leads)
-- ============================================================================
-- Deduplicate by CRD BEFORE applying tier quotas to ensure priority tiers aren't lost
-- Keep the best-ranked instance of each CRD
-- ============================================================================
deduplicated_before_quotas AS (
    SELECT 
        tl.*
    FROM tier_limited tl
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY tl.crd
        ORDER BY 
            CASE tl.final_tier
                WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
                WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
                WHEN 'TIER_1_PRIME_MOVER' THEN 3
                WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
                WHEN 'TIER_2_PROVEN_MOVER' THEN 5
                WHEN 'TIER_3_MODERATE_BLEEDER' THEN 6
                WHEN 'STANDARD_HIGH_V4' THEN 7
            END,
            tl.source_priority,
            tl.has_linkedin DESC,
            tl.v4_percentile DESC,
            tl.crd
    ) = 1
),

-- ============================================================================
-- P2. LINKEDIN PRIORITIZATION (Dynamic tier quotas based on SGA count)
-- ============================================================================
linkedin_prioritized AS (
    SELECT 
        dtl.*,
        ROW_NUMBER() OVER (
            ORDER BY 
                CASE final_tier
                    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
                    WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
                    WHEN 'TIER_1_PRIME_MOVER' THEN 3
                    WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
                    WHEN 'TIER_2_PROVEN_MOVER' THEN 5
                    WHEN 'TIER_3_MODERATE_BLEEDER' THEN 6
                    -- OPTION C: TIER_4 and TIER_5 excluded
                    WHEN 'STANDARD_HIGH_V4' THEN 7  -- Backfill only
                END,
                source_priority,
                has_linkedin DESC,
                v4_percentile DESC,
                crd
        ) as overall_rank,
        CASE 
            WHEN has_linkedin = 0 THEN
                ROW_NUMBER() OVER (
                    PARTITION BY CASE WHEN has_linkedin = 0 THEN 1 ELSE 0 END
                    ORDER BY 
                        CASE final_tier
                            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
                            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
                            WHEN 'TIER_1_PRIME_MOVER' THEN 3
                            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
                            WHEN 'TIER_2_PROVEN_MOVER' THEN 5
                            WHEN 'TIER_3_MODERATE_BLEEDER' THEN 6
                            -- OPTION C: TIER_4 and TIER_5 excluded
                        END,
                        source_priority,
                        v4_percentile DESC,
                        crd
                )
            ELSE NULL
        END as no_linkedin_rank,
        ROW_NUMBER() OVER (
            PARTITION BY 
                CASE 
                    WHEN final_tier = 'STANDARD' AND v4_percentile >= 80 THEN 'STANDARD_HIGH_V4'
                    ELSE final_tier 
                END
            ORDER BY 
                source_priority,
                has_linkedin DESC,
                v4_percentile DESC,
                priority_rank,
                CASE WHEN firm_net_change_12mo < 0 THEN ABS(firm_net_change_12mo) ELSE 0 END DESC,
                crd
        ) as tier_rank
    FROM deduplicated_before_quotas dtl
    CROSS JOIN sga_constants sc
    WHERE 
        -- Dynamic tier quotas: Scale proportionally to ensure we have enough leads
        -- Base quotas are for 12 SGAs (2400 leads), scale up/down based on actual SGA count
        -- NOTE: These quotas are applied AFTER deduplication, so we have unique leads
        (final_tier = 'TIER_1A_PRIME_MOVER_CFP' AND tier_rank <= CAST(50 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_1B_PRIME_MOVER_SERIES65' AND tier_rank <= CAST(60 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_1_PRIME_MOVER' AND tier_rank <= CAST(300 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_1F_HV_WEALTH_BLEEDER' AND tier_rank <= CAST(50 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_2_PROVEN_MOVER' AND tier_rank <= CAST(1500 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_3_MODERATE_BLEEDER' AND tier_rank <= CAST(300 * sc.total_sgas / 12.0 AS INT64))
        -- OPTION C: TIER_4_EXPERIENCED_MOVER EXCLUDED (converts at baseline 2.74%)
        -- OPTION C: TIER_5_HEAVY_BLEEDER EXCLUDED (marginal lift 3.42%)
        -- STANDARD_HIGH_V4: Backfill to fill remaining slots (increased to 1500 to ensure 200 per SGA)
        -- We deduplicate BEFORE tier quotas, so priority tiers are preserved
        OR (final_tier = 'STANDARD_HIGH_V4' AND tier_rank <= CAST(1500 * sc.total_sgas / 12.0 AS INT64))
),

-- ============================================================================
-- Q. DEDUPLICATED LEADS (Already deduplicated, just pass through)
-- ============================================================================
deduplicated_leads AS (
    SELECT 
        lp.*
    FROM linkedin_prioritized lp
    -- Already deduplicated in deduplicated_before_quotas, so no need to dedupe again
),

-- ============================================================================
-- Q2. SGA ASSIGNMENT (Equitable distribution based on expected conversion rate)
-- ============================================================================
-- Strategy: Distribute leads using stratified round-robin within conversion rate buckets
-- This ensures each SGA gets similar expected conversion value, not just tier distribution
-- Each SGA will receive exactly 200 leads with equitable conversion rate distribution
leads_with_conv_bucket AS (
    SELECT 
        dl.*,
        sc.total_leads_needed,
        sc.total_sgas,
        -- Create conversion rate buckets for stratified distribution
        CASE 
            WHEN dl.final_expected_rate >= 0.10 THEN 'HIGH_CONV'      -- 10%+ (T1B)
            WHEN dl.final_expected_rate >= 0.06 THEN 'MED_HIGH_CONV'  -- 6-10% (T1, T1F)
            WHEN dl.final_expected_rate >= 0.05 THEN 'MED_CONV'       -- 5-6% (T2)
            WHEN dl.final_expected_rate >= 0.04 THEN 'MED_LOW_CONV'   -- 4-5% (T3, T4)
            WHEN dl.final_expected_rate >= 0.03 THEN 'LOW_CONV'       -- 3-4% (T5, STANDARD_HIGH_V4)
            ELSE 'VERY_LOW_CONV'                                       -- <3% (should not appear)
        END as conv_rate_bucket,
        -- Rank within conversion bucket and tier for round-robin
        ROW_NUMBER() OVER (
            PARTITION BY 
                CASE 
                    WHEN dl.final_expected_rate >= 0.10 THEN 'HIGH_CONV'
                    WHEN dl.final_expected_rate >= 0.06 THEN 'MED_HIGH_CONV'
                    WHEN dl.final_expected_rate >= 0.05 THEN 'MED_CONV'
                    WHEN dl.final_expected_rate >= 0.04 THEN 'MED_LOW_CONV'
                    WHEN dl.final_expected_rate >= 0.03 THEN 'LOW_CONV'
                    ELSE 'VERY_LOW_CONV'
                END,
                dl.final_tier
            ORDER BY dl.overall_rank
        ) as rank_within_bucket
    FROM deduplicated_leads dl
    CROSS JOIN sga_constants sc
    WHERE 
        dl.has_linkedin = 1 
        OR (dl.has_linkedin = 0 AND dl.no_linkedin_rank <= CAST(240 * sc.total_sgas / 12.0 AS INT64))
    -- NOTE: No limit here - we already deduplicated, so we want all unique leads
    -- The SGA assignment will handle distributing them
),

-- Assign SGA using round-robin within conversion buckets
-- This ensures each SGA gets leads from all conversion buckets proportionally
leads_assigned AS (
    SELECT 
        l.*,
        -- Calculate which SGA number this lead should get (round-robin)
        MOD(l.rank_within_bucket - 1, l.total_sgas) + 1 as assigned_sga_num,
        -- Flag for partner/founder leads (case-insensitive)
        CASE 
            WHEN UPPER(COALESCE(l.job_title, '')) LIKE '%PARTNER%' 
                 OR UPPER(COALESCE(l.job_title, '')) LIKE '%FOUNDER%' 
            THEN 1 
            ELSE 0 
        END as is_partner_founder
    FROM leads_with_conv_bucket l
),

-- Group partner/founder leads by firm and assign to same SGA
-- This prevents multiple SGAs from reaching out to the same firm's leadership
partner_founder_groups AS (
    SELECT DISTINCT
        firm_crd,
        -- Get the SGA assigned to the highest-ranked (lowest overall_rank) lead in this firm group
        FIRST_VALUE(assigned_sga_num) OVER (
            PARTITION BY firm_crd
            ORDER BY overall_rank
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) as group_sga_num
    FROM leads_assigned
    WHERE is_partner_founder = 1
),

-- Update SGA assignment for partner/founder leads to use group SGA
leads_with_partner_founder_fix AS (
    SELECT 
        la.*,
        -- If this is a partner/founder lead, use the group SGA; otherwise keep original assignment
        CASE 
            WHEN la.is_partner_founder = 1 AND pfg.group_sga_num IS NOT NULL 
            THEN pfg.group_sga_num
            ELSE la.assigned_sga_num
        END as final_assigned_sga_num
    FROM leads_assigned la
    LEFT JOIN partner_founder_groups pfg 
        ON la.firm_crd = pfg.firm_crd
),

-- Join to get SGA details and ensure exactly 200 leads per SGA
leads_with_sga AS (
    SELECT 
        lapf.*,
        sga.sga_id,
        sga.sga_name as sga_owner,
        -- Rank within each SGA to ensure exactly 200 leads per SGA
        ROW_NUMBER() OVER (
            PARTITION BY sga.sga_id
            ORDER BY 
                lapf.conv_rate_bucket,
                lapf.final_tier,
                lapf.overall_rank
        ) as sga_lead_rank
    FROM leads_with_partner_founder_fix lapf
    INNER JOIN active_sgas sga ON lapf.final_assigned_sga_num = sga.sga_number
    -- Limit to exactly 200 leads per SGA
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY sga.sga_id
        ORDER BY 
            lapf.conv_rate_bucket,
            lapf.final_tier,
            lapf.overall_rank
    ) <= 200
),

-- ============================================================================
-- R. FINAL LEAD LIST (Exclude V3/V4.1 disagreement leads)
-- ============================================================================
-- V4.1 has better lift (2.03x vs 1.51x), so we can be more aggressive
-- Updated threshold from 70th to 60th percentile for disagreement filtering
-- 
-- Logic: Tier 1 leads with V4.1 < 60th percentile are likely false positives
-- V4.1 now has bleeding signal built-in, so it better understands V3 rules
-- 
-- NOTE: Deduplication already happened BEFORE SGA assignment, so no need to dedupe again
-- ============================================================================
final_lead_list AS (
    SELECT 
        lws.*
    FROM leads_with_sga lws
    WHERE NOT (
        -- V3/V4.1 Disagreement Filter
        -- Exclude Tier 1 leads where V4.1 < 60th percentile (was 70th for V4.0)
        lws.score_tier IN (
            'TIER_1A_PRIME_MOVER_CFP',
            'TIER_1B_PRIME_MOVER_SERIES65',
            'TIER_1_PRIME_MOVER',
            'TIER_1F_HV_WEALTH_BLEEDER'
        )
        AND lws.v4_percentile < 60  -- CHANGED from 70 (V4.1 is more accurate)
    )
)

-- ============================================================================
-- T. FINAL OUTPUT (with SGA assignment, excluding V3/V4 disagreements)
-- ============================================================================
SELECT 
    crd as advisor_crd,
    existing_lead_id as salesforce_lead_id,
    first_name,
    last_name,
    email,
    phone,
    linkedin_url,
    has_linkedin,
    
    -- JOB TITLE
    job_title,
    
    producing_advisor,
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
    score_tier as original_v3_tier,
    final_tier as score_tier,
    priority_rank,
    final_expected_rate as expected_conversion_rate,
    ROUND(final_expected_rate * 100, 2) as expected_rate_pct,
    
    -- SCORE NARRATIVE (V3 rules or V4 SHAP)
    score_narrative,
    
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
    
    -- V4.1 Scoring (UPDATED)
    ROUND(v4_score, 4) as v4_score,
    v4_percentile,
    is_high_v4_standard,
    CASE 
        WHEN is_high_v4_standard = 1 THEN 'High-V4 STANDARD (Backfill)'
        WHEN score_tier != 'STANDARD_HIGH_V4' THEN 'V3 Tier Qualified'
        ELSE 'STANDARD'
    END as v4_status,
    
    -- V4.1 Feature Values (NEW - for transparency)
    v4_is_recent_mover,
    v4_days_since_last_move,
    v4_firm_departures_corrected,
    v4_bleeding_velocity_encoded,
    v4_is_dual_registered,
    
    -- V4.1 SHAP Features (for SDR context)
    shap_top1_feature,
    shap_top2_feature,
    shap_top3_feature,
    
    -- SGA ASSIGNMENT (NEW!)
    sga_owner,
    sga_id,
    
    overall_rank as list_rank,
    CURRENT_TIMESTAMP() as generated_at

FROM final_lead_list
ORDER BY 
    overall_rank;