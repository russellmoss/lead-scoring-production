-- ============================================================================
-- INSERT M&A LEADS INTO LEAD LIST (V3.5.0)
-- ============================================================================
-- Version: V3.5.0_01032026_TWO_QUERY_ARCHITECTURE
-- 
-- PURPOSE:
-- This query adds M&A leads to the existing january_2026_lead_list table.
-- Run this AFTER the main lead list query (January_2026_Lead_List_V3_V4_Hybrid.sql)
-- 
-- WHY TWO QUERIES:
-- BigQuery CTE optimization issues prevent M&A advisors from appearing when
-- integrated into the main query. This separate INSERT approach guarantees
-- M&A leads are added successfully.
-- 
-- USAGE:
-- 1. Run January_2026_Lead_List_V3_V4_Hybrid.sql first (creates base lead list)
-- 2. Run this query to insert M&A leads
-- 3. Verify M&A leads appear in the table
-- ============================================================================

INSERT INTO `savvy-gtm-analytics.ml_features.january_2026_lead_list`
(
    advisor_crd,
    salesforce_lead_id,
    first_name,
    last_name,
    email,
    phone,
    linkedin_url,
    has_linkedin,
    job_title,
    producing_advisor,
    firm_name,
    firm_crd,
    firm_rep_count,
    firm_net_change_12mo,
    firm_arrivals_12mo,
    firm_departures_12mo,
    firm_turnover_pct,
    tenure_months,
    tenure_years,
    industry_tenure_years,
    num_prior_firms,
    moves_3yr,
    original_v3_tier,
    score_tier,
    priority_rank,
    expected_conversion_rate,
    expected_rate_pct,
    score_narrative,
    has_cfp,
    has_series_65_only,
    has_series_7,
    has_cfa,
    is_hv_wealth_title,
    prospect_type,
    lead_source_description,
    v4_score,
    v4_percentile,
    is_high_v4_standard,
    v4_status,
    v4_is_recent_mover,
    v4_days_since_last_move,
    v4_firm_departures_corrected,
    v4_bleeding_velocity_encoded,
    v4_is_dual_registered,
    shap_top1_feature,
    shap_top2_feature,
    shap_top3_feature,
    cc_career_pattern,
    cc_cycle_status,
    cc_pct_through_cycle,
    cc_months_until_window,
    sga_owner,
    sga_id,
    list_rank,
    generated_at
)
SELECT 
    ma.crd as advisor_crd,
    CAST(NULL AS STRING) as salesforce_lead_id,
    ma.first_name,
    ma.last_name,
    ma.email,
    ma.phone,
    c.LINKEDIN_PROFILE_URL as linkedin_url,
    CASE WHEN c.LINKEDIN_PROFILE_URL IS NOT NULL AND TRIM(c.LINKEDIN_PROFILE_URL) != '' THEN 1 ELSE 0 END as has_linkedin,
    ma.job_title,
    TRUE as producing_advisor,  -- All M&A advisors are producing
    ma.firm_name,
    ma.firm_crd,
    ma.ma_firm_size as firm_rep_count,
    CAST(NULL AS INT64) as firm_net_change_12mo,  -- Not available for M&A advisors
    CAST(NULL AS INT64) as firm_arrivals_12mo,
    CAST(NULL AS INT64) as firm_departures_12mo,
    CAST(NULL AS FLOAT64) as firm_turnover_pct,
    DATE_DIFF(CURRENT_DATE(), ma.firm_start_date, MONTH) as tenure_months,
    DATE_DIFF(CURRENT_DATE(), ma.firm_start_date, YEAR) as tenure_years,
    DATE_DIFF(CURRENT_DATE(), ma.firm_start_date, YEAR) as industry_tenure_years,  -- Approximate
    CAST(NULL AS INT64) as num_prior_firms,
    CAST(NULL AS INT64) as moves_3yr,
    ma.ma_tier as original_v3_tier,
    ma.ma_tier as score_tier,  -- TIER_MA_ACTIVE_PRIME or TIER_MA_ACTIVE
    CASE 
        WHEN ma.ma_tier = 'TIER_MA_ACTIVE_PRIME' THEN 4
        WHEN ma.ma_tier = 'TIER_MA_ACTIVE' THEN 5
        ELSE 99
    END as priority_rank,
    ma.expected_conversion_rate as expected_conversion_rate,
    ROUND(ma.expected_conversion_rate * 100, 2) as expected_rate_pct,
    -- M&A tier narrative
    CASE 
        WHEN ma.ma_tier = 'TIER_MA_ACTIVE_PRIME' THEN
            CONCAT(
                ma.first_name, ' is a HIGH-VALUE M&A OPPORTUNITY: ',
                CASE WHEN ma.is_senior_title = 1 THEN CONCAT('Senior title (', ma.job_title, ')') 
                     ELSE CONCAT('Mid-career (', CAST(ROUND(ma.industry_tenure_months/12, 0) AS STRING), ' years)') 
                END,
                ' at ', ma.firm_name, ' (', ma.ma_status, ' M&A target, ',
                CAST(ma.days_since_first_news AS STRING), ' days since announcement). ',
                'Advisors at acquired firms actively evaluating options. ',
                '9.0% expected conversion (2.36x baseline).'
            )
        WHEN ma.ma_tier = 'TIER_MA_ACTIVE' THEN
            CONCAT(
                ma.first_name, ' is at M&A TARGET FIRM: ',
                ma.firm_name, ' (', ma.ma_status, ' M&A target, ',
                CAST(ma.days_since_first_news AS STRING), ' days since announcement). ',
                'Firm disruption creates opportunity window. ',
                '5.4% expected conversion (1.41x baseline).'
            )
        ELSE CONCAT(ma.first_name, ' at ', ma.firm_name, ' - M&A target firm.')
    END as score_narrative,
    -- Certifications (from ria_contacts_current if available)
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
    'NEW_PROSPECT' as prospect_type,
    'New - M&A Target Firm' as lead_source_description,
    -- V4 scores (if available)
    COALESCE(v4.v4_score, 0.5) as v4_score,
    COALESCE(v4.v4_percentile, 50) as v4_percentile,
    CASE WHEN COALESCE(v4.v4_percentile, 50) >= 80 THEN 1 ELSE 0 END as is_high_v4_standard,
    CASE 
        WHEN COALESCE(v4.v4_percentile, 50) >= 80 THEN 'High-V4 STANDARD (Backfill)'
        ELSE 'V3 Tier Qualified'
    END as v4_status,
    COALESCE(v4f.is_recent_mover, 0) as v4_is_recent_mover,
    COALESCE(v4f.days_since_last_move, 9999) as v4_days_since_last_move,
    COALESCE(v4f.firm_departures_corrected, 0) as v4_firm_departures_corrected,
    COALESCE(v4f.bleeding_velocity_encoded, 0) as v4_bleeding_velocity_encoded,
    COALESCE(v4f.is_dual_registered, 0) as v4_is_dual_registered,
    v4.shap_top1_feature,
    v4.shap_top2_feature,
    v4.shap_top3_feature,
    -- Career Clock (not applicable for M&A advisors, but include for schema compatibility)
    CAST(NULL AS STRING) as cc_career_pattern,
    CAST(NULL AS STRING) as cc_cycle_status,
    CAST(NULL AS FLOAT64) as cc_pct_through_cycle,
    CAST(NULL AS INT64) as cc_months_until_window,
    -- SGA assignment (will be assigned in post-processing)
    CAST(NULL AS STRING) as sga_owner,
    CAST(NULL AS STRING) as sga_id,
    -- List rank (will be assigned in post-processing)
    CAST(NULL AS INT64) as list_rank,
    CURRENT_TIMESTAMP() as generated_at
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors` ma
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON ma.crd = c.RIA_CONTACT_CRD_ID
LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4
    ON ma.crd = v4.crd
LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_features` v4f
    ON ma.crd = v4f.crd
-- Only insert M&A advisors not already in the lead list
WHERE ma.crd NOT IN (
    SELECT advisor_crd 
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
)
-- Apply quotas (scale based on SGA count - base = 12 SGAs)
-- TIER_MA_ACTIVE_PRIME: 100 per 12 SGAs
-- TIER_MA_ACTIVE: 200 per 12 SGAs
AND (
    (ma.ma_tier = 'TIER_MA_ACTIVE_PRIME' AND ma.expected_conversion_rate >= 0.09)
    OR (ma.ma_tier = 'TIER_MA_ACTIVE' AND ma.expected_conversion_rate >= 0.054)
)
ORDER BY 
    CASE ma.ma_tier 
        WHEN 'TIER_MA_ACTIVE_PRIME' THEN 1 
        WHEN 'TIER_MA_ACTIVE' THEN 2 
        ELSE 3 
    END,
    ma.days_since_first_news ASC  -- Soonest since announcement first
LIMIT 300;  -- Total M&A leads quota (adjust based on SGA count)

-- ============================================================================
-- VERIFICATION QUERY (Run after INSERT to confirm M&A leads were added)
-- ============================================================================
-- SELECT 
--     score_tier,
--     COUNT(*) as lead_count,
--     COUNT(DISTINCT firm_name) as firm_count
-- FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
-- WHERE score_tier LIKE 'TIER_MA%'
-- GROUP BY score_tier
-- ORDER BY score_tier;
-- ============================================================================
