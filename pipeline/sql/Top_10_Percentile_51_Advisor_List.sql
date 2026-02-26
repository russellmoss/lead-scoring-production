-- ============================================================================
-- V4 DEPRIORITIZATION + SPECIFIC TIERS: 51 ADVISOR LIST
-- ============================================================================
-- Version: 1.1
-- Created: 2026-01-XX
-- Purpose: Generate a list of 51 advisors that are:
--   1. V4 bottom 20% excluded (v4_percentile >= 20, same as January lead list)
--   2. In specific tiers: TIER_2_PROVEN_MOVER, TIER_1B_PRIME_MOVER_SERIES65, TIER_0C_CLOCKWORK_DUE
--   3. Target ~17 from each category (or distribute if one doesn't have enough)
--   4. Exclude advisors already in Salesforce
--   5. Ranked by V4 percentile within each tier (highest first)
--
-- OUTPUT: ml_features.top_10_percentile_51_advisor_list
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_deprioritized_51_advisor_list` AS

WITH 
-- ============================================================================
-- A. EXISTING SALESFORCE CRDs (Exclude these)
-- ============================================================================
salesforce_crds AS (
    SELECT DISTINCT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE FA_CRD__c IS NOT NULL AND IsDeleted = false
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
-- C. ADVISOR EMPLOYMENT HISTORY
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
-- D. FIRM METRICS
-- ============================================================================
firm_headcount AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_reps
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY PRIMARY_FIRM
),

firm_departures AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),

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
-- E. CAREER CLOCK STATS (V3.6.0)
-- ============================================================================
career_clock_stats AS (
    SELECT
        eh.RIA_CONTACT_CRD_ID as advisor_crd,
        COUNT(*) as cc_completed_jobs,
        AVG(DATE_DIFF(
            eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
            eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
            MONTH
        )) as cc_avg_prior_tenure_months,
        SAFE_DIVIDE(
            STDDEV(DATE_DIFF(
                eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                MONTH
            )),
            AVG(DATE_DIFF(
                eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                MONTH
            ))
        ) as cc_tenure_cv
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
    WHERE eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < CURRENT_DATE()
      AND DATE_DIFF(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                    eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) > 0
    GROUP BY eh.RIA_CONTACT_CRD_ID
    HAVING COUNT(*) >= 2
),

-- ============================================================================
-- F. BASE PROSPECT DATA
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
        DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, MONTH) as tenure_months,
        DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, YEAR) as tenure_years,
        c.TITLE_NAME as job_title,
        c.LINKEDIN_PROFILE_URL as linkedin_url
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN salesforce_crds sf ON c.RIA_CONTACT_CRD_ID = sf.crd
    LEFT JOIN excluded_firms ef ON UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
    LEFT JOIN excluded_firm_crds ec ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ec.firm_crd
    WHERE c.CONTACT_FIRST_NAME IS NOT NULL AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM_START_DATE IS NOT NULL AND c.PRIMARY_FIRM_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
      AND c.PRODUCING_ADVISOR = TRUE
      -- Exclude advisors already in Salesforce
      AND sf.crd IS NULL
      -- Firm exclusions
      AND ef.firm_pattern IS NULL
      AND ec.firm_crd IS NULL
      -- Age exclusion: Exclude advisors over 70
      AND (c.AGE_RANGE IS NULL 
           OR c.AGE_RANGE NOT IN ('70-74', '75-79', '80-84', '85-89', '90-94', '95-99'))
      -- Disclosure exclusions
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = FALSE
      -- Title exclusions
      AND NOT (
          UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTIONS ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE%'  -- Excludes any title with "associate"
          OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS%'
          OR UPPER(c.TITLE_NAME) LIKE '%WHOLESALER%'
          OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSISTANT%'
          OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE AGENT%'
          OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE%'
          -- Senior/Executive title exclusions
          OR UPPER(c.TITLE_NAME) LIKE '%MANAGING DIRECTOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%VICE PRESIDENT%'
          OR UPPER(c.TITLE_NAME) LIKE '%VP %'  -- VP with space to avoid false positives
          OR UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
          OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%CEO%'
          OR UPPER(c.TITLE_NAME) LIKE '%CHIEF EXECUTIVE OFFICER%'
      )
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
        COALESCE(fm.firm_rep_count, 1) as firm_rep_count,
        COALESCE(fm.firm_net_change_12mo, 0) as firm_net_change_12mo,
        CASE WHEN EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(bp.firm_name) LIKE ef.firm_pattern) THEN 1 ELSE 0 END as is_wirehouse,
        
        -- Certifications
        CASE WHEN c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%' THEN 1 ELSE 0 END as has_cfp,
        CASE WHEN c.REP_LICENSES LIKE '%Series 65%' AND c.REP_LICENSES NOT LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_65_only,
        CASE WHEN c.REP_LICENSES LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_7,
        
        -- Portable custodian flag
        COALESCE(fc.has_portable_custodian, 0) as has_portable_custodian,
        
        -- LinkedIn flag
        CASE WHEN c.LINKEDIN_PROFILE_URL IS NOT NULL AND TRIM(c.LINKEDIN_PROFILE_URL) != '' THEN 1 ELSE 0 END as has_linkedin,
        
        -- Career Clock features
        ccs.cc_completed_jobs,
        ccs.cc_avg_prior_tenure_months,
        ccs.cc_tenure_cv,
        SAFE_DIVIDE(bp.tenure_months, ccs.cc_avg_prior_tenure_months) as cc_pct_through_cycle,
        CASE
            WHEN ccs.cc_tenure_cv IS NULL THEN 'No_Pattern'
            WHEN ccs.cc_tenure_cv < 0.3 THEN 'Clockwork'
            WHEN ccs.cc_tenure_cv < 0.5 THEN 'Semi_Predictable'
            WHEN ccs.cc_tenure_cv < 0.8 THEN 'Variable'
            ELSE 'Chaotic'
        END as cc_career_pattern,
        CASE
            WHEN ccs.cc_tenure_cv IS NULL THEN 'No_Pattern'
            WHEN ccs.cc_tenure_cv >= 0.5 THEN 'Unpredictable'
            WHEN SAFE_DIVIDE(bp.tenure_months, ccs.cc_avg_prior_tenure_months) < 0.7 THEN 'Too_Early'
            WHEN SAFE_DIVIDE(bp.tenure_months, ccs.cc_avg_prior_tenure_months) BETWEEN 0.7 AND 1.3 THEN 'In_Window'
            ELSE 'Overdue'
        END as cc_cycle_status,
        CASE WHEN ccs.cc_tenure_cv < 0.5 
             AND SAFE_DIVIDE(bp.tenure_months, ccs.cc_avg_prior_tenure_months) BETWEEN 0.7 AND 1.3
        THEN 1 ELSE 0 END as cc_is_in_move_window
        
    FROM base_prospects bp
    LEFT JOIN advisor_moves am ON bp.crd = am.crd
    LEFT JOIN firm_metrics fm ON bp.firm_crd = fm.firm_crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c ON bp.crd = c.RIA_CONTACT_CRD_ID
    LEFT JOIN career_clock_stats ccs ON bp.crd = ccs.advisor_crd
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
),

-- ============================================================================
-- H. JOIN V4 SCORES (Bottom 20% excluded, same as January lead list)
-- ============================================================================
v4_enriched AS (
    SELECT 
        ep.*,
        COALESCE(v4.v4_score, 0.5) as v4_score,
        COALESCE(v4.v4_percentile, 50) as v4_percentile,
        v4.shap_top1_feature,
        v4.shap_top1_value,
        v4.shap_top2_feature,
        v4.shap_top2_value,
        v4.shap_top3_feature,
        v4.shap_top3_value,
        v4.v4_narrative as v4_narrative
    FROM enriched_prospects ep
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 
        ON ep.crd = v4.crd
    WHERE v4.v4_percentile >= 20 OR v4.v4_percentile IS NULL  -- Bottom 20% excluded (same as January list)
),

-- ============================================================================
-- I. APPLY V3 TIER LOGIC (Only specific tiers)
-- ============================================================================
scored_prospects AS (
    SELECT 
        ep.*,
        
        -- Score tier (only the three specific tiers we want)
        CASE 
            -- TIER_0C_CLOCKWORK_DUE: Any predictable advisor in move window
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.is_wirehouse = 0
            THEN 'TIER_0C_CLOCKWORK_DUE'
            
            -- TIER_1B_PRIME_MOVER_SERIES65: Series 65 only + Prime Mover criteria
            WHEN (((ep.tenure_years BETWEEN 1 AND 3 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.firm_rep_count <= 50 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 3 AND ep.firm_rep_count <= 10 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0))
                  AND ep.has_series_65_only = 1) 
            THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            
            -- TIER_2_PROVEN_MOVER: 3+ prior firms
            WHEN (ep.num_prior_firms >= 3 AND ep.industry_tenure_years >= 5) 
            THEN 'TIER_2_PROVEN_MOVER'
            
            ELSE NULL  -- Not in our target tiers
        END as score_tier,
        
        -- Priority rank
        CASE 
            WHEN ep.cc_is_in_move_window = 1 AND ep.is_wirehouse = 0 THEN 1  -- TIER_0C
            WHEN (((ep.tenure_years BETWEEN 1 AND 3 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.firm_rep_count <= 50 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 3 AND ep.firm_rep_count <= 10 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0))
                  AND ep.has_series_65_only = 1) THEN 2  -- TIER_1B
            WHEN (ep.num_prior_firms >= 3 AND ep.industry_tenure_years >= 5) THEN 3  -- TIER_2
            ELSE 99
        END as priority_rank
        
    FROM v4_enriched ep
    WHERE ep.v4_percentile >= 20 OR ep.v4_percentile IS NULL  -- Ensure bottom 20% excluded
),

-- ============================================================================
-- J. FILTER TO ONLY TARGET TIERS
-- ============================================================================
target_tier_prospects AS (
    SELECT *
    FROM scored_prospects
    WHERE score_tier IN ('TIER_0C_CLOCKWORK_DUE', 'TIER_1B_PRIME_MOVER_SERIES65', 'TIER_2_PROVEN_MOVER')
),

-- ============================================================================
-- K. RANK WITHIN EACH TIER
-- ============================================================================
ranked_by_tier AS (
    SELECT 
        ttp.*,
        ROW_NUMBER() OVER (
            PARTITION BY ttp.score_tier
            ORDER BY 
                ttp.v4_percentile DESC,  -- Highest V4 first
                ttp.has_linkedin DESC,   -- LinkedIn preferred
                ttp.priority_rank,
                ttp.crd
        ) as rank_within_tier
    FROM target_tier_prospects ttp
),

-- ============================================================================
-- L. DISTRIBUTE 51 ADVISORS (~17 per tier, adjust if needed)
-- ============================================================================
-- Strategy: Take up to 17 from each tier, but if one tier doesn't have enough,
-- we'll take more from the others to reach 51 total
-- 
-- Simple approach: Use ROW_NUMBER to prioritize initial 17 per tier, then fill gaps
final_selection AS (
    SELECT 
        rbt.*,
        -- Priority: First 17 from each tier get priority 1, rest get priority 2
        CASE 
            WHEN rbt.rank_within_tier <= 17 THEN 1
            ELSE 2
        END as selection_priority,
        -- Overall rank for final selection
        ROW_NUMBER() OVER (
            ORDER BY 
                CASE WHEN rbt.rank_within_tier <= 17 THEN 1 ELSE 2 END,  -- Initial quota first
                rbt.score_tier,
                rbt.rank_within_tier
        ) as final_rank
    FROM ranked_by_tier rbt
)

-- ============================================================================
-- M. FINAL OUTPUT (51 advisors total)
-- ============================================================================
SELECT 
    fs.crd as advisor_crd,
    fs.first_name,
    fs.last_name,
    fs.email,
    fs.phone,
    fs.linkedin_url,
    fs.job_title,
    fs.firm_name,
    fs.firm_crd,
    fs.firm_rep_count,
    fs.firm_net_change_12mo,
    fs.tenure_months,
    fs.tenure_years,
    fs.industry_tenure_years,
    fs.num_prior_firms,
    fs.moves_3yr,
    fs.score_tier,
    fs.priority_rank,
    ROUND(fs.v4_score, 4) as v4_score,
    fs.v4_percentile,
    fs.has_series_65_only,
    fs.has_cfp,
    fs.cc_career_pattern,
    fs.cc_cycle_status,
    ROUND(fs.cc_pct_through_cycle, 2) as cc_pct_through_cycle,
    fs.cc_is_in_move_window,
    fs.shap_top1_feature,
    fs.shap_top2_feature,
    fs.shap_top3_feature,
    fs.v4_narrative,
    fs.rank_within_tier,
    CURRENT_TIMESTAMP() as generated_at

FROM final_selection fs
WHERE fs.final_rank <= 51
ORDER BY 
    fs.score_tier,
    fs.rank_within_tier;
