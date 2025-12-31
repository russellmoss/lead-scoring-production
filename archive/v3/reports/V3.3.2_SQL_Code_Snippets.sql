-- =============================================================================
-- V3.3.2 T1G GROWTH STAGE ADVISOR: SQL CODE SNIPPETS
-- =============================================================================
-- Purpose: Ready-to-use SQL snippets for Cursor.ai implementation
-- Version: V3.3.2_01012026_GROWTH_STAGE_TIER
-- =============================================================================

-- =============================================================================
-- SNIPPET 1: FIRM_ACCOUNT_SIZE CTE
-- Add this CTE after firm_discretionary in phase_4_v3_tiered_scoring.sql
-- =============================================================================

-- V3.3.2: Firm average account size for T1G Growth Stage tier
-- Calculated as TOTAL_AUM / TOTAL_ACCOUNTS
-- Used to identify "established practice" advisors ($250K+ avg)
-- Source: V3.3.2 Growth Stage Hypothesis Validation (December 2025)
firm_account_size AS (
    SELECT 
        CRD_ID as firm_crd,
        TOTAL_AUM,
        TOTAL_ACCOUNTS,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size,
        CASE 
            WHEN SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) >= 250000 THEN 'ESTABLISHED'
            WHEN SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) IS NULL THEN 'UNKNOWN'
            ELSE 'GROWTH_STAGE'
        END as practice_maturity
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
),


-- =============================================================================
-- SNIPPET 2: UPDATED HEADER COMMENT
-- Replace existing header in phase_4_v3_tiered_scoring.sql
-- =============================================================================

-- =============================================================================
-- LEAD SCORING V3.3.2: GROWTH STAGE ADVISOR TIER
-- =============================================================================
-- Version: V3.3.2_01012026_GROWTH_STAGE_TIER
-- 
-- CHANGES FROM V3.3.1:
--   - ADDED: TIER_1G_GROWTH_STAGE_ADVISOR - Proactive movers at stable firms
--   - ADDED: avg_account_size calculation (TOTAL_AUM / TOTAL_ACCOUNTS)
--   - ADDED: practice_maturity classification (ESTABLISHED / GROWTH_STAGE)
--
-- T1G TIER DETAILS:
--   Target: "Proactive Movers" - advisors seeking platform upgrade, not crisis-driven
--   
--   CRITERIA:
--   - industry_tenure_months BETWEEN 60 AND 180 (5-15 years, mid-career)
--   - avg_account_size >= 250000 ($250K+ avg account, established practice)
--   - firm_net_change_12mo > -3 (stable firm, NOT bleeding)
--
--   VALIDATION:
--   - Conversion: 7.20% (1.88x baseline)
--   - Sample: 125 leads
--   - Overlap with T1A/T1B: 0 (mutually exclusive - requires stable vs bleeding)
--
-- TWO TYPES OF HIGH-CONVERTING LEADS:
--   | Type             | Firm Status | Motivation            | Tiers         |
--   |------------------|-------------|----------------------|---------------|
--   | Reactive Movers  | Bleeding    | "My firm is failing"  | T1A, T1B, T1F |
--   | Proactive Movers | Stable      | "I want better"       | T1G (NEW)     |
--
-- PREVIOUS CHANGES (V3.3.1):
--   - Low discretionary AUM exclusion (<50% = 0.34x baseline)
--   - Large firm flag (>50 reps = 0.60x baseline)
--   - Servicer title exclusions confirmed
--
-- TIER PERFORMANCE SUMMARY:
--   | Tier | Conversion | Lift  | Definition                    |
--   |------|------------|-------|-------------------------------|
--   | T1A  | 9.80%      | 2.57x | CFP + Bleeding Firm           |
--   | T1G  | 7.20%      | 1.88x | Growth Stage + Stable Firm    |
--   | T1B  | 6.18%      | 1.62x | Series 65 Only + Bleeding     |
--   | T1F  | ~5%        | ~1.3x | HV Wealth Title + Bleeding    |
-- =============================================================================


-- =============================================================================
-- SNIPPET 3: JOIN FIRM_ACCOUNT_SIZE IN leads_with_flags CTE
-- Add this join and these fields
-- =============================================================================

-- Add this LEFT JOIN:
LEFT JOIN firm_account_size fas ON lf.firm_crd = fas.firm_crd

-- Add these fields to the SELECT:
COALESCE(fas.avg_account_size, 0) as avg_account_size,
COALESCE(fas.practice_maturity, 'UNKNOWN') as practice_maturity,


-- =============================================================================
-- SNIPPET 4: T1G TIER LOGIC
-- Add this to the tier assignment CASE statement
-- Place AFTER T1A/T1B/T1/T1F but BEFORE T2 and lower tiers
-- =============================================================================

-- ==========================================================================
-- TIER 1G: GROWTH STAGE ADVISOR (Proactive Movers at Stable Firms)
-- ==========================================================================
-- V3.3.2: NEW TIER - Captures "proactive movers" at stable firms
-- 
-- THEORY: These advisors have built a successful practice but hit a ceiling.
-- They're not in crisis (stable firm), but want a better platform to grow.
-- This is DIFFERENT from T1A/T1B which target crisis-driven movers.
--
-- VALIDATION:
-- - Conversion: 7.20% (1.88x baseline)
-- - Sample: 125 leads
-- - Zero overlap with bleeding-firm tiers (mutually exclusive)
--
-- CRITERIA:
-- - Mid-career (5-15 years) - Still growing, not established/complacent
-- - Established practice ($250K+ avg account) - Has real book to move
-- - Stable firm (net_change > -3) - Strategic move, not crisis
-- ==========================================================================
WHEN industry_tenure_months BETWEEN 60 AND 180  -- Mid-career (5-15 years)
     AND avg_account_size >= 250000              -- Established practice ($250K+)
     AND firm_net_change_12mo > -3               -- Stable firm (NOT bleeding)
     AND is_wirehouse = 0                        -- Not at wirehouse
     AND is_excluded_title = 0                   -- Not excluded title
THEN 'TIER_1G_GROWTH_STAGE_ADVISOR'


-- =============================================================================
-- SNIPPET 5: T1G EXPECTED CONVERSION RATE
-- Add to the expected_conversion_rate assignment
-- =============================================================================

WHEN score_tier = 'TIER_1G_GROWTH_STAGE_ADVISOR' THEN 0.072


-- =============================================================================
-- SNIPPET 6: T1G SCORE NARRATIVE
-- Add to the score_narrative generation
-- =============================================================================

WHEN score_tier = 'TIER_1G_GROWTH_STAGE_ADVISOR' THEN
    CONCAT(
        first_name, ' is a GROWTH STAGE ADVISOR: ',
        'Mid-career professional (', CAST(ROUND(industry_tenure_months/12, 0) AS STRING), ' years experience) ',
        'with an established practice at ', firm_name, '. ',
        'Firm is stable but advisor may be seeking platform upgrade. ',
        'Proactive mover - strategic growth opportunity, not crisis-driven.'
    )


-- =============================================================================
-- SNIPPET 7: T1G OUTPUT COLUMNS
-- Add these to final SELECT for monitoring
-- =============================================================================

avg_account_size,
practice_maturity,


-- =============================================================================
-- VALIDATION QUERIES
-- Run these after implementation to verify correctness
-- =============================================================================

-- VALIDATION 1: Check T1G tier exists and has correct count
SELECT 
    'VALIDATION 1: T1G Exists' as check_name,
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_pct
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE score_tier = 'TIER_1G_GROWTH_STAGE_ADVISOR'
GROUP BY score_tier;
-- Expected: ~125 leads, 7.20% expected rate


-- VALIDATION 2: Check T1G has NO overlap with bleeding-firm tiers
SELECT 
    'VALIDATION 2: Zero Bleeding Overlap' as check_name,
    COUNT(*) as t1g_leads,
    COUNTIF(f.firm_net_change_12mo <= -3) as bleeding_firm_count,
    ROUND(COUNTIF(f.firm_net_change_12mo <= -3) / COUNT(*) * 100, 2) as bleeding_pct
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3` ls
JOIN `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
    ON ls.lead_id = f.lead_id
WHERE ls.score_tier = 'TIER_1G_GROWTH_STAGE_ADVISOR';
-- Expected: bleeding_firm_count = 0, bleeding_pct = 0


-- VALIDATION 3: Check T1G criteria are correct
SELECT 
    'VALIDATION 3: T1G Criteria Check' as check_name,
    COUNT(*) as t1g_leads,
    ROUND(AVG(f.industry_tenure_months), 1) as avg_tenure_months,
    ROUND(AVG(f.industry_tenure_months) / 12, 1) as avg_tenure_years,
    MIN(f.industry_tenure_months) as min_tenure_months,
    MAX(f.industry_tenure_months) as max_tenure_months,
    ROUND(AVG(f.firm_net_change_12mo), 1) as avg_firm_net_change,
    MIN(f.firm_net_change_12mo) as min_net_change,
    MAX(f.firm_net_change_12mo) as max_net_change
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3` ls
JOIN `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
    ON ls.lead_id = f.lead_id
WHERE ls.score_tier = 'TIER_1G_GROWTH_STAGE_ADVISOR';
-- Expected:
-- avg_tenure_months: 60-180 (5-15 years)
-- min_net_change: > -3 (all stable)


-- VALIDATION 4: Check avg_account_size is populated correctly
SELECT 
    'VALIDATION 4: Account Size Check' as check_name,
    COUNT(*) as t1g_leads,
    ROUND(AVG(fas.avg_account_size), 0) as avg_account_size,
    MIN(fas.avg_account_size) as min_account_size,
    MAX(fas.avg_account_size) as max_account_size
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3` ls
JOIN `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
    ON ls.lead_id = f.lead_id
JOIN (
    SELECT CRD_ID as firm_crd, SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
) fas ON f.firm_crd = fas.firm_crd
WHERE ls.score_tier = 'TIER_1G_GROWTH_STAGE_ADVISOR';
-- Expected: min_account_size >= 250,000


-- VALIDATION 5: Compare all Tier 1 performance
SELECT 
    'VALIDATION 5: Tier 1 Comparison' as check_name,
    ls.score_tier,
    COUNT(*) as leads,
    SUM(CASE WHEN tv.target = 1 THEN 1 ELSE 0 END) as conversions,
    ROUND(AVG(CASE WHEN tv.target = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) as actual_conv_pct,
    ROUND(AVG(ls.expected_conversion_rate) * 100, 2) as expected_conv_pct
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3` ls
JOIN `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    ON ls.lead_id = tv.lead_id
WHERE ls.score_tier LIKE 'TIER_1%'
GROUP BY ls.score_tier
ORDER BY actual_conv_pct DESC;
-- Expected: T1G should show ~7.2% actual conversion


-- VALIDATION 6: Check tier assignment order is correct (no double-counting)
SELECT 
    'VALIDATION 6: Tier Priority Check' as check_name,
    advisor_crd,
    COUNT(DISTINCT score_tier) as tier_count
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
GROUP BY advisor_crd
HAVING COUNT(DISTINCT score_tier) > 1;
-- Expected: 0 rows (each advisor should have exactly 1 tier)


-- VALIDATION 7: Lead list includes T1G leads
SELECT 
    'VALIDATION 7: T1G in Lead List' as check_name,
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(expected_rate_pct), 2) as avg_expected_rate
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier = 'TIER_1G_GROWTH_STAGE_ADVISOR'
GROUP BY score_tier;
-- Expected: T1G leads present with 7.2% expected rate


-- =============================================================================
-- DIAGNOSTIC QUERIES
-- Use these if validation fails
-- =============================================================================

-- DIAGNOSTIC 1: Check if industry_tenure_months field is populated
SELECT 
    'DIAGNOSTIC: Tenure Distribution' as check_name,
    CASE 
        WHEN industry_tenure_months IS NULL THEN 'NULL'
        WHEN industry_tenure_months < 60 THEN '<5 years'
        WHEN industry_tenure_months BETWEEN 60 AND 180 THEN '5-15 years (T1G target)'
        ELSE '>15 years'
    END as tenure_bucket,
    COUNT(*) as leads
FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`
GROUP BY tenure_bucket
ORDER BY leads DESC;


-- DIAGNOSTIC 2: Check firm_net_change_12mo distribution
SELECT 
    'DIAGNOSTIC: Firm Stability Distribution' as check_name,
    CASE 
        WHEN firm_net_change_12mo IS NULL THEN 'NULL'
        WHEN firm_net_change_12mo <= -10 THEN 'Heavy Bleeding (<=-10)'
        WHEN firm_net_change_12mo <= -3 THEN 'Bleeding (-10 to -3)'
        WHEN firm_net_change_12mo < 0 THEN 'Slight Decline (-3 to 0)'
        ELSE 'Stable/Growing (>=0)'
    END as stability_bucket,
    COUNT(*) as leads
FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`
GROUP BY stability_bucket
ORDER BY leads DESC;


-- DIAGNOSTIC 3: Check avg_account_size distribution
SELECT 
    'DIAGNOSTIC: Account Size Distribution' as check_name,
    CASE 
        WHEN avg_account_size IS NULL THEN 'NULL/Unknown'
        WHEN avg_account_size >= 1000000 THEN '$1M+ (HNW)'
        WHEN avg_account_size >= 500000 THEN '$500K-1M'
        WHEN avg_account_size >= 250000 THEN '$250K-500K (T1G threshold)'
        WHEN avg_account_size >= 100000 THEN '$100K-250K'
        ELSE '<$100K (Retail)'
    END as account_bucket,
    COUNT(*) as firms
FROM (
    SELECT 
        CRD_ID,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
)
GROUP BY account_bucket
ORDER BY firms DESC;


-- DIAGNOSTIC 4: Check how many leads COULD qualify for T1G
SELECT 
    'DIAGNOSTIC: T1G Candidate Pool' as check_name,
    COUNT(*) as potential_t1g_leads
FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
JOIN (
    SELECT CRD_ID as firm_crd, SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
) fas ON f.firm_crd = fas.firm_crd
WHERE f.industry_tenure_months BETWEEN 60 AND 180
  AND fas.avg_account_size >= 250000
  AND f.firm_net_change_12mo > -3;
-- Expected: ~125 leads (matching validation sample)


-- =============================================================================
-- MODEL REGISTRY UPDATE (JSON)
-- Add this to v3/models/model_registry_v3.json
-- =============================================================================
/*
{
  "model_version": "V3.3.2_01012026_GROWTH_STAGE_TIER",
  "updated_date": "2026-01-01",
  "changes_from_v3.3.1": [
    "ADDED: TIER_1G_GROWTH_STAGE_ADVISOR - Mid-career advisors at stable firms with established practices",
    "CRITERIA: industry_tenure 5-15 years + avg_account_size >= $250K + firm_net_change > -3 (stable)",
    "PERFORMANCE: 7.20% conversion rate (1.88x lift vs 3.82% baseline)",
    "SAMPLE SIZE: 125 leads (validated)",
    "KEY INSIGHT: Captures 'proactive movers' - advisors seeking platform upgrade, not crisis-driven",
    "ZERO OVERLAP: T1G is mutually exclusive with T1A/T1B (requires stable firm vs bleeding firm)",
    "NEW FEATURE: avg_account_size calculated from TOTAL_AUM / TOTAL_ACCOUNTS",
    "ANALYSIS: V3.3.2 Growth Stage Hypothesis Validation (December 2025)"
  ],
  "tier_definitions": {
    "TIER_1G_GROWTH_STAGE_ADVISOR": {
      "description": "Mid-career advisors at stable firms with established practices seeking platform upgrade",
      "criteria": {
        "industry_tenure_months": "60-180 (5-15 years)",
        "avg_account_size": ">= 250000",
        "firm_net_change_12mo": "> -3 (stable, not bleeding)"
      },
      "expected_conversion_rate": 0.072,
      "expected_lift": 1.88,
      "sample_size_validated": 125,
      "added_version": "V3.3.2"
    }
  }
}
*/
