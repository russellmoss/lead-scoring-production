-- ============================================================================
-- SUPPLEMENTAL LEAD LIST GENERATOR (Under 70 Years Old)
-- ============================================================================
-- Version: 1.0
-- Created: January 7, 2026
-- Purpose: Generate supplemental lead list with specific tier quotas
--          Excludes leads already in January_Leads_Real
--          Follows same V3/V4 pipeline rules
--          Age restriction: Under 70 years old (AGE_RANGE < '70-74')
--
-- TIER QUOTAS:
--   STANDARD_HIGH_V4: 209
--   TIER_2_PROVEN_MOVER: 43
--   TIER_1_PRIME_MOVER: 6
--   TIER_1B_PRIME_MOVER_SERIES65: 2
--   TIER_1F_HV_WEALTH_BLEEDER: 2
--   TIER_3_MODERATE_BLEEDER: 1
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.supplemental_lead_list_under_70` AS

WITH 
-- ============================================================================
-- A. EXISTING LEADS (Exclude from supplemental list)
-- ============================================================================
existing_leads AS (
    SELECT DISTINCT 
        SAFE_CAST(advisor_crd AS INT64) as crd
    FROM `savvy-gtm-analytics.ml_features.January_Leads_Real`
    WHERE advisor_crd IS NOT NULL
),

-- ============================================================================
-- B. EXCLUSIONS (Reference centralized tables)
-- ============================================================================
excluded_firms AS (
    SELECT pattern as firm_pattern
    FROM `savvy-gtm-analytics.ml_features.excluded_firms`
),

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
-- D. BASE PROSPECT DATA (with age < 70 exclusion)
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
        c.TITLE_NAME as job_title
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN salesforce_crds sf ON c.RIA_CONTACT_CRD_ID = sf.crd
    LEFT JOIN excluded_firms ef ON UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
    LEFT JOIN excluded_firm_crds ec ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ec.firm_crd
    LEFT JOIN existing_leads el ON c.RIA_CONTACT_CRD_ID = el.crd
    WHERE c.CONTACT_FIRST_NAME IS NOT NULL AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM_START_DATE IS NOT NULL AND c.PRIMARY_FIRM_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
      AND c.PRODUCING_ADVISOR = TRUE
      -- Exclude matched patterns and CRDs
      AND ef.firm_pattern IS NULL
      AND ec.firm_crd IS NULL
      -- Exclude existing leads
      AND el.crd IS NULL
      -- Age exclusion: Exclude advisors 70+ (AGE_RANGE >= '70-74')
      -- Include if NULL (missing data) or if AGE_RANGE < '70-74'
      AND (c.AGE_RANGE IS NULL 
           OR c.AGE_RANGE NOT IN ('70-74', '75-79', '80-84', '85-89', '90-94', '95-99'))
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
          -- Executive/Senior title exclusions
          OR UPPER(c.TITLE_NAME) LIKE '%CHIEF FINANCIAL OFFICER%'
          OR UPPER(c.TITLE_NAME) LIKE '%CFO%'
          OR UPPER(c.TITLE_NAME) LIKE '%CHIEF INVESTMENT OFFICER%'
          OR UPPER(c.TITLE_NAME) LIKE '%CIO%'
          OR UPPER(c.TITLE_NAME) LIKE '%VICE PRESIDENT%'
          OR UPPER(c.TITLE_NAME) LIKE '%VP %'  -- VP with space to avoid false positives
      )
),

-- ============================================================================
-- E. ADVISOR MOVES HISTORY
-- ============================================================================
advisor_moves AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID) as total_firms,
        COUNT(DISTINCT CASE 
            WHEN PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 YEAR)
            THEN PREVIOUS_REGISTRATION_COMPANY_CRD_ID 
        END) as moves_3yr,
        MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE) as career_start_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    GROUP BY RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- F. FIRM METRICS
-- ============================================================================
firm_headcount AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as firm_rep_count
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY PRIMARY_FIRM
),

-- Firm departures (12 months)
firm_departures AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),

-- Firm arrivals (12 months)
firm_arrivals AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

firm_metrics AS (
    SELECT 
        h.firm_crd,
        h.firm_rep_count,
        COALESCE(fa.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(fd.departures_12mo, 0) as departures_12mo,
        COALESCE(fa.arrivals_12mo, 0) - COALESCE(fd.departures_12mo, 0) as firm_net_change_12mo,
        CASE 
            WHEN h.firm_rep_count > 0 
            THEN SAFE_DIVIDE(COALESCE(fd.departures_12mo, 0), h.firm_rep_count) * 100
            ELSE 0
        END as turnover_pct
    FROM firm_headcount h
    LEFT JOIN firm_arrivals fa ON h.firm_crd = fa.firm_crd
    LEFT JOIN firm_departures fd ON h.firm_crd = fd.firm_crd
),

-- ============================================================================
-- G. ENRICH WITH ADVISOR HISTORY, FIRM METRICS, AND CERTIFICATIONS
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
        c.PRODUCING_ADVISOR as producing_advisor,
        
        -- Portable custodian flag
        COALESCE(fc.has_portable_custodian, 0) as has_portable_custodian,
        
        -- Discretionary ratio
        COALESCE(fd.discretionary_ratio, 1.0) as discretionary_ratio
        
    FROM base_prospects bp
    LEFT JOIN advisor_moves am ON bp.crd = am.crd
    LEFT JOIN firm_metrics fm ON bp.firm_crd = fm.firm_crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c ON bp.crd = c.RIA_CONTACT_CRD_ID
    LEFT JOIN (
        SELECT 
            CRD_ID as firm_crd,
            SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) as discretionary_ratio
        FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    ) fd ON bp.firm_crd = fd.firm_crd
    LEFT JOIN (
        SELECT 
            CRD_ID as firm_crd,
            CASE WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                      OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%'
                      OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
                      OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
                 THEN 1 ELSE 0 
            END as has_portable_custodian
        FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    ) fc ON bp.firm_crd = fc.firm_crd
    WHERE COALESCE(fm.turnover_pct, 0) < 100
      -- Exclude low discretionary firms
      AND (fd.discretionary_ratio >= 0.50 OR fd.discretionary_ratio IS NULL)
      -- Exclude large firms (>50 reps)
      AND COALESCE(fm.firm_rep_count, bp.firm_employee_count, 1) <= 50
),

-- ============================================================================
-- H. JOIN V4 SCORES
-- ============================================================================
v4_enriched AS (
    SELECT 
        ep.*,
        COALESCE(v4.v4_score, 0.5) as v4_score,
        COALESCE(v4.v4_percentile, 50) as v4_percentile,
        COALESCE(v4.v4_deprioritize, FALSE) as v4_deprioritize,
        COALESCE(v4.v4_upgrade_candidate, FALSE) as v4_upgrade_candidate,
        v4.shap_top1_feature,
        v4.shap_top1_value,
        v4.shap_top2_feature,
        v4.shap_top2_value,
        v4.shap_top3_feature,
        v4.shap_top3_value,
        v4.v4_narrative as v4_shap_narrative
    FROM enriched_prospects ep
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4
        ON ep.crd = v4.crd
),

-- ============================================================================
-- I. V3 TIER ASSIGNMENT
-- ============================================================================
scored_prospects AS (
    SELECT 
        ve.*,
        CASE 
            -- TIER_1B_PRIME_MOVER_SERIES65: Series 65 only + bleeding firm
            WHEN has_series_65_only = 1 
                 AND firm_net_change_12mo < 0 
                 AND has_portable_custodian = 1
                 AND firm_rep_count <= 10
                 AND has_cfp = 0
            THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            
            -- TIER_1F_HV_WEALTH_BLEEDER: High-value wealth title + bleeding
            WHEN is_hv_wealth_title = 1 
                 AND firm_net_change_12mo < 0
                 AND industry_tenure_years >= 5
            THEN 'TIER_1F_HV_WEALTH_BLEEDER'
            
            -- TIER_1_PRIME_MOVER: Prime mover criteria
            WHEN (tenure_years BETWEEN 1 AND 4 
                  AND industry_tenure_years BETWEEN 5 AND 15 
                  AND firm_net_change_12mo < 0 
                  AND is_wirehouse = 0)
            THEN 'TIER_1_PRIME_MOVER'
            
            -- TIER_2_PROVEN_MOVER: 3+ prior firms
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5)
            THEN 'TIER_2_PROVEN_MOVER'
            
            -- TIER_3_MODERATE_BLEEDER: Moderate bleeding
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 
                  AND industry_tenure_years >= 5)
            THEN 'TIER_3_MODERATE_BLEEDER'
            
            -- STANDARD: Everything else
            ELSE 'STANDARD'
        END as score_tier,
        
        -- Priority rank
        CASE 
            WHEN has_series_65_only = 1 AND firm_net_change_12mo < 0 AND has_portable_custodian = 1 AND firm_rep_count <= 10 AND has_cfp = 0 THEN 1
            WHEN is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND industry_tenure_years >= 5 THEN 2
            WHEN tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0 THEN 3
            WHEN num_prior_firms >= 3 AND industry_tenure_years >= 5 THEN 4
            WHEN firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5 THEN 5
            ELSE 99
        END as priority_rank,
        
        -- Expected conversion rate
        CASE 
            WHEN has_series_65_only = 1 AND firm_net_change_12mo < 0 AND has_portable_custodian = 1 AND firm_rep_count <= 10 AND has_cfp = 0 THEN 0.0549
            WHEN is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND industry_tenure_years >= 5 THEN 0.0606
            WHEN tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0 THEN 0.0476
            WHEN num_prior_firms >= 3 AND industry_tenure_years >= 5 THEN 0.0591
            WHEN firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5 THEN 0.0300
            ELSE 0.0382
        END as expected_conversion_rate,
        
        -- V3 narrative
        CASE 
            WHEN has_series_65_only = 1 AND firm_net_change_12mo < 0 AND has_portable_custodian = 1 AND firm_rep_count <= 10 AND has_cfp = 0 
            THEN CONCAT(first_name, ' at ', firm_name, ' - Series 65 only advisor at small bleeding firm with portable custodian. Expected conversion: 5.49%.')
            WHEN is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND industry_tenure_years >= 5 
            THEN CONCAT(first_name, ' at ', firm_name, ' - High-value wealth manager at bleeding firm. Expected conversion: 6.06%.')
            WHEN tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0 
            THEN CONCAT(first_name, ' at ', firm_name, ' - Prime mover: ', tenure_years, ' years at firm, ', industry_tenure_years, ' years experience, firm losing advisors. Expected conversion: 4.76%.')
            WHEN num_prior_firms >= 3 AND industry_tenure_years >= 5 
            THEN CONCAT(first_name, ' at ', firm_name, ' - Proven mover: ', num_prior_firms, ' prior firms, ', industry_tenure_years, ' years experience. Expected conversion: 5.91%.')
            WHEN firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5 
            THEN CONCAT(first_name, ' at ', firm_name, ' - Moderate bleeder: firm lost ', ABS(firm_net_change_12mo), ' advisors. Expected conversion: 3.00%.')
            ELSE CONCAT(first_name, ' at ', firm_name, ' - Standard lead. Expected conversion: 3.82%.')
        END as v3_score_narrative
    FROM v4_enriched ve
),

-- ============================================================================
-- J. DIVERSITY FILTER (Exclude V3/V4 disagreement for Tier 1)
-- ============================================================================
diversity_filtered AS (
    SELECT 
        sp.*,
        CASE 
            WHEN sp.score_tier IN ('TIER_1_PRIME_MOVER', 'TIER_1B_PRIME_MOVER_SERIES65', 'TIER_1F_HV_WEALTH_BLEEDER')
                 AND sp.v4_percentile < 60
            THEN 0  -- Exclude Tier 1 with low V4 score
            ELSE 1
        END as passes_diversity_filter
    FROM scored_prospects sp
    WHERE sp.score_tier != 'STANDARD' 
       OR (sp.score_tier = 'STANDARD' AND sp.v4_percentile >= 80)
),

-- ============================================================================
-- K. FINAL TIER ASSIGNMENT (STANDARD_HIGH_V4 for high-V4 STANDARD)
-- ============================================================================
tier_limited AS (
    SELECT 
        df.*,
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 'STANDARD_HIGH_V4'
            ELSE df.score_tier 
        END as final_tier,
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 0.035
            ELSE df.expected_conversion_rate 
        END as final_expected_rate,
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN
                CONCAT(df.first_name, ' at ', df.firm_name, ' - ML model identified key signals: ',
                       COALESCE(df.shap_top1_feature, 'strong profile'), '. V4 Score: ', 
                       CAST(df.v4_percentile AS STRING), 'th percentile. Expected conversion: 3.5%.')
            ELSE df.v3_score_narrative
        END as score_narrative,
        ROW_NUMBER() OVER (
            PARTITION BY 
                CASE 
                    WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 'STANDARD_HIGH_V4'
                    ELSE df.score_tier 
                END
            ORDER BY 
                df.priority_rank,
                df.has_linkedin DESC,
                df.v4_percentile DESC,
                CASE WHEN df.firm_net_change_12mo < 0 THEN ABS(df.firm_net_change_12mo) ELSE 0 END DESC,
                df.crd
        ) as tier_rank
    FROM diversity_filtered df
    WHERE df.passes_diversity_filter = 1
),

-- ============================================================================
-- L. DEDUPLICATE BEFORE QUOTAS
-- ============================================================================
deduplicated_before_quotas AS (
    SELECT 
        tl.*
    FROM tier_limited tl
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY tl.crd
        ORDER BY 
            CASE tl.final_tier
                WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 1
                WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 2
                WHEN 'TIER_1_PRIME_MOVER' THEN 3
                WHEN 'TIER_2_PROVEN_MOVER' THEN 4
                WHEN 'TIER_3_MODERATE_BLEEDER' THEN 5
                WHEN 'STANDARD_HIGH_V4' THEN 6
            END,
            tl.priority_rank,
            tl.has_linkedin DESC,
            tl.v4_percentile DESC,
            tl.crd
    ) = 1
),

-- ============================================================================
-- M. APPLY TIER QUOTAS
-- ============================================================================
quota_limited AS (
    SELECT 
        dtl.*
    FROM deduplicated_before_quotas dtl
    WHERE 
        (final_tier = 'STANDARD_HIGH_V4' AND tier_rank <= 209)
        OR (final_tier = 'TIER_2_PROVEN_MOVER' AND tier_rank <= 43)
        OR (final_tier = 'TIER_1_PRIME_MOVER' AND tier_rank <= 6)
        OR (final_tier = 'TIER_1B_PRIME_MOVER_SERIES65' AND tier_rank <= 2)
        OR (final_tier = 'TIER_1F_HV_WEALTH_BLEEDER' AND tier_rank <= 2)
        OR (final_tier = 'TIER_3_MODERATE_BLEEDER' AND tier_rank <= 1)
)

-- ============================================================================
-- FINAL OUTPUT
-- ============================================================================
SELECT 
    crd as advisor_crd,
    first_name,
    last_name,
    email,
    phone,
    linkedin_url,
    has_linkedin,
    job_title,
    firm_name,
    firm_crd,
    firm_rep_count,
    firm_net_change_12mo,
    tenure_months,
    tenure_years,
    industry_tenure_years,
    num_prior_firms,
    moves_3yr,
    has_cfp,
    has_series_65_only,
    has_series_7,
    has_cfa,
    is_hv_wealth_title,
    producing_advisor,
    prospect_type,
    existing_lead_id,
    score_tier,
    final_tier as score_tier_final,
    priority_rank,
    expected_conversion_rate,
    final_expected_rate as expected_rate_pct,
    score_narrative,
    v4_score,
    v4_percentile,
    v4_deprioritize,
    v4_upgrade_candidate,
    shap_top1_feature,
    shap_top1_value,
    shap_top2_feature,
    shap_top2_value,
    shap_top3_feature,
    shap_top3_value,
    v4_shap_narrative,
    tier_rank,
    CURRENT_TIMESTAMP() as generated_at
FROM quota_limited
ORDER BY 
    CASE final_tier
        WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 1
        WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 2
        WHEN 'TIER_1_PRIME_MOVER' THEN 3
        WHEN 'TIER_2_PROVEN_MOVER' THEN 4
        WHEN 'TIER_3_MODERATE_BLEEDER' THEN 5
        WHEN 'STANDARD_HIGH_V4' THEN 6
    END,
    tier_rank;

-- ============================================================================
-- VERIFICATION QUERIES (Run after table creation)
-- ============================================================================

-- Query 1: Verify tier quotas were met
-- SELECT 
--     final_tier as score_tier_final,
--     COUNT(*) as actual_count,
--     CASE 
--         WHEN final_tier = 'STANDARD_HIGH_V4' THEN 209
--         WHEN final_tier = 'TIER_2_PROVEN_MOVER' THEN 43
--         WHEN final_tier = 'TIER_1_PRIME_MOVER' THEN 6
--         WHEN final_tier = 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
--         WHEN final_tier = 'TIER_1F_HV_WEALTH_BLEEDER' THEN 2
--         WHEN final_tier = 'TIER_3_MODERATE_BLEEDER' THEN 1
--     END as target_count,
--     CASE 
--         WHEN COUNT(*) >= CASE 
--             WHEN final_tier = 'STANDARD_HIGH_V4' THEN 209
--             WHEN final_tier = 'TIER_2_PROVEN_MOVER' THEN 43
--             WHEN final_tier = 'TIER_1_PRIME_MOVER' THEN 6
--             WHEN final_tier = 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
--             WHEN final_tier = 'TIER_1F_HV_WEALTH_BLEEDER' THEN 2
--             WHEN final_tier = 'TIER_3_MODERATE_BLEEDER' THEN 1
--         END THEN '✅ MET'
--         ELSE '⚠️ BELOW TARGET'
--     END as status
-- FROM `savvy-gtm-analytics.ml_features.supplemental_lead_list_under_70`
-- GROUP BY final_tier
-- ORDER BY 
--     CASE final_tier
--         WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 1
--         WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 2
--         WHEN 'TIER_1_PRIME_MOVER' THEN 3
--         WHEN 'TIER_2_PROVEN_MOVER' THEN 4
--         WHEN 'TIER_3_MODERATE_BLEEDER' THEN 5
--         WHEN 'STANDARD_HIGH_V4' THEN 6
--     END;

-- Query 2: Verify no duplicates with January_Leads_Real
-- SELECT 
--     COUNT(*) as total_supplemental_leads,
--     COUNT(DISTINCT sl.advisor_crd) as unique_crds,
--     COUNT(CASE WHEN jl.advisor_crd IS NOT NULL THEN 1 END) as duplicates_found
-- FROM `savvy-gtm-analytics.ml_features.supplemental_lead_list_under_70` sl
-- LEFT JOIN `savvy-gtm-analytics.ml_features.January_Leads_Real` jl
--     ON sl.advisor_crd = SAFE_CAST(jl.advisor_crd AS INT64);

-- Query 3: Verify age restriction (should all be < 70)
-- SELECT 
--     c.AGE_RANGE,
--     COUNT(*) as count
-- FROM `savvy-gtm-analytics.ml_features.supplemental_lead_list_under_70` sl
-- LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
--     ON sl.advisor_crd = c.RIA_CONTACT_CRD_ID
-- GROUP BY c.AGE_RANGE
-- ORDER BY c.AGE_RANGE;
