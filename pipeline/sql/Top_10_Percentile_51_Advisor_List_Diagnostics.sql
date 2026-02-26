-- ============================================================================
-- DIAGNOSTIC QUERY: Check why no advisors are returned
-- ============================================================================
-- This query helps debug why the main query returns 0 advisors
-- Run this to see counts at each filtering step
-- ============================================================================

WITH 
-- Same CTEs as main query
salesforce_crds AS (
    SELECT DISTINCT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE FA_CRD__c IS NOT NULL AND IsDeleted = false
),

excluded_firms AS (
    SELECT pattern as firm_pattern
    FROM `savvy-gtm-analytics.ml_features.excluded_firms`
),

excluded_firm_crds AS (
    SELECT firm_crd
    FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
),

advisor_moves AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID) as total_firms,
        MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE) as career_start_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    GROUP BY RIA_CONTACT_CRD_ID
),

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

base_prospects AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        c.CONTACT_FIRST_NAME as first_name,
        c.CONTACT_LAST_NAME as last_name,
        c.PRIMARY_FIRM_NAME as firm_name,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
        DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, YEAR) as tenure_years,
        DATE_DIFF(CURRENT_DATE(), am.career_start_date, YEAR) as industry_tenure_years,
        COALESCE(am.total_firms, 1) - 1 as num_prior_firms,
        COALESCE(fm.firm_rep_count, 1) as firm_rep_count,
        COALESCE(fm.firm_net_change_12mo, 0) as firm_net_change_12mo,
        CASE WHEN EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern) THEN 1 ELSE 0 END as is_wirehouse,
        CASE WHEN c.REP_LICENSES LIKE '%Series 65%' AND c.REP_LICENSES NOT LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_65_only,
        CASE WHEN ccs.cc_tenure_cv < 0.5 
             AND SAFE_DIVIDE(DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, MONTH), ccs.cc_avg_prior_tenure_months) BETWEEN 0.7 AND 1.3
        THEN 1 ELSE 0 END as cc_is_in_move_window
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN salesforce_crds sf ON c.RIA_CONTACT_CRD_ID = sf.crd
    LEFT JOIN excluded_firms ef ON UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
    LEFT JOIN excluded_firm_crds ec ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ec.firm_crd
    LEFT JOIN advisor_moves am ON c.RIA_CONTACT_CRD_ID = am.crd
    LEFT JOIN firm_metrics fm ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = fm.firm_crd
    LEFT JOIN career_clock_stats ccs ON c.RIA_CONTACT_CRD_ID = ccs.advisor_crd
    WHERE c.CONTACT_FIRST_NAME IS NOT NULL AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM_START_DATE IS NOT NULL AND c.PRIMARY_FIRM_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
      AND c.PRODUCING_ADVISOR = TRUE
      AND sf.crd IS NULL  -- Not in Salesforce
      AND ef.firm_pattern IS NULL
      AND ec.firm_crd IS NULL
      AND (c.AGE_RANGE IS NULL 
           OR c.AGE_RANGE NOT IN ('70-74', '75-79', '80-84', '85-89', '90-94', '95-99'))
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = FALSE
      AND COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = FALSE
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
      AND COALESCE(fm.turnover_pct, 0) < 100
),

-- Check tier assignments
tier_check AS (
    SELECT 
        bp.*,
        CASE 
            WHEN bp.cc_is_in_move_window = 1 AND bp.is_wirehouse = 0 THEN 'TIER_0C_CLOCKWORK_DUE'
            WHEN (((bp.tenure_years BETWEEN 1 AND 3 AND bp.industry_tenure_years BETWEEN 5 AND 15 AND bp.firm_net_change_12mo < 0 AND bp.firm_rep_count <= 50 AND bp.is_wirehouse = 0)
                  OR (bp.tenure_years BETWEEN 1 AND 3 AND bp.firm_rep_count <= 10 AND bp.is_wirehouse = 0)
                  OR (bp.tenure_years BETWEEN 1 AND 4 AND bp.industry_tenure_years BETWEEN 5 AND 15 AND bp.firm_net_change_12mo < 0 AND bp.is_wirehouse = 0))
                  AND bp.has_series_65_only = 1) 
            THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            WHEN (bp.num_prior_firms >= 3 AND bp.industry_tenure_years >= 5) 
            THEN 'TIER_2_PROVEN_MOVER'
            ELSE NULL
        END as score_tier,
        v4.v4_percentile
    FROM base_prospects bp
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 
        ON bp.crd = v4.crd
)

SELECT 
    'Total base prospects (after exclusions)' as step,
    COUNT(*) as count
FROM base_prospects

UNION ALL

SELECT 
    'Advisors with V4 percentile >= 90' as step,
    COUNT(*) as count
FROM tier_check
WHERE v4_percentile >= 90

UNION ALL

SELECT 
    'Advisors in TIER_0C_CLOCKWORK_DUE' as step,
    COUNT(*) as count
FROM tier_check
WHERE score_tier = 'TIER_0C_CLOCKWORK_DUE' AND v4_percentile >= 90

UNION ALL

SELECT 
    'Advisors in TIER_1B_PRIME_MOVER_SERIES65' as step,
    COUNT(*) as count
FROM tier_check
WHERE score_tier = 'TIER_1B_PRIME_MOVER_SERIES65' AND v4_percentile >= 90

UNION ALL

SELECT 
    'Advisors in TIER_2_PROVEN_MOVER' as step,
    COUNT(*) as count
FROM tier_check
WHERE score_tier = 'TIER_2_PROVEN_MOVER' AND v4_percentile >= 90

UNION ALL

SELECT 
    'Advisors in ANY target tier with V4 >= 90' as step,
    COUNT(*) as count
FROM tier_check
WHERE score_tier IN ('TIER_0C_CLOCKWORK_DUE', 'TIER_1B_PRIME_MOVER_SERIES65', 'TIER_2_PROVEN_MOVER')
  AND v4_percentile >= 90

ORDER BY step;
