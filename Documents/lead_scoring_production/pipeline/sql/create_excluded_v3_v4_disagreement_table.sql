-- ============================================================================
-- EXCLUDED LEADS TABLE (V3/V4 Disagreement)
-- Run this AFTER the main lead list query (Step 3)
-- ============================================================================
-- This query creates a table of leads excluded due to V3/V4 disagreement:
-- Tier 1 leads with V4 < 70th percentile (0% conversion rate)
-- Updated threshold from 50th to 70th percentile based on Q1 2026 analysis
--
-- NOTE: Since the main query filters these out, this table will be empty
-- if the filter is working correctly. This serves as a validation check.
-- To capture actual excluded leads, you would need to modify the main query
-- to output them before filtering.

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.january_2026_excluded_v3_v4_disagreement` AS

-- This query checks the final list for any disagreement leads (should be 0)
SELECT 
    advisor_crd as crd,
    salesforce_lead_id as existing_lead_id,
    first_name,
    last_name,
    CONCAT(first_name, ' ', last_name) as name,
    email,
    phone,
    firm_name,
    firm_crd,
    original_v3_tier as score_tier,
    score_tier as final_tier,
    v4_score,
    v4_percentile,
    expected_rate_pct,
    'V3_V4_DISAGREEMENT: Tier 1 with V4 < 70th percentile' as exclusion_reason,
    CURRENT_TIMESTAMP() as excluded_at
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
WHERE score_tier IN (
    'TIER_1A_PRIME_MOVER_CFP',
    'TIER_1B_PRIME_MOVER_SERIES65',
    'TIER_1_PRIME_MOVER',
    'TIER_1F_HV_WEALTH_BLEEDER'
)
AND v4_percentile < 70
ORDER BY 
    score_tier,
    v4_percentile;

-- NOTE: If this returns 0 rows, the filter is working correctly.
-- The excluded leads are filtered out in the main query's final_lead_list CTE.
