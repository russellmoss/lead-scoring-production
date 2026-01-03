-- ============================================================================
-- V3.5.0 M&A TIERS - POST-IMPLEMENTATION VERIFICATION
-- ============================================================================
-- Run these queries AFTER generating the lead list to verify M&A advisors are present.
-- All checks must pass for successful implementation.
-- ============================================================================

-- ============================================================
-- CHECK 8.1: M&A Tiers Are Populated
-- ============================================================
SELECT 
    '1. M&A Tier Population' as check_name,
    score_tier,
    COUNT(*) as lead_count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
GROUP BY score_tier
ORDER BY score_tier;

-- EXPECTED:
-- TIER_MA_ACTIVE_PRIME: 50-200 leads
-- TIER_MA_ACTIVE: 100-400 leads
-- 🛑 FAIL if 0 leads in either tier

-- ============================================================
-- CHECK 8.2: Large Firm Exemption Working
-- ============================================================
SELECT 
    '2. Large Firm Exemption' as check_name,
    CASE WHEN score_tier LIKE 'TIER_MA%' THEN 'M&A Tier' ELSE 'Other Tier' END as tier_type,
    CASE 
        WHEN firm_rep_count <= 50 THEN '≤50 reps'
        WHEN firm_rep_count <= 200 THEN '51-200 reps'
        ELSE '>200 reps'
    END as firm_size,
    COUNT(*) as leads
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY 1, 2, 3
ORDER BY 2, 3;

-- EXPECTED:
-- M&A Tier + >50 reps: >0 (exemption working)
-- Other Tier + >50 reps: 0 (exclusion working)

-- ============================================================
-- CHECK 8.3: Commonwealth Specifically Included
-- ============================================================
SELECT 
    '3. Commonwealth Check' as check_name,
    firm_name,
    score_tier,
    COUNT(*) as leads
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE UPPER(firm_name) LIKE '%COMMONWEALTH%'
GROUP BY firm_name, score_tier;

-- EXPECTED: >0 Commonwealth leads in TIER_MA_ACTIVE or TIER_MA_ACTIVE_PRIME
-- 🛑 FAIL if 0 Commonwealth leads

-- ============================================================
-- CHECK 8.4: No Non-M&A Large Firms Snuck In
-- ============================================================
SELECT 
    '4. Violation Check' as check_name,
    COUNT(*) as violations
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE firm_rep_count > 50
  AND score_tier NOT LIKE 'TIER_MA%'
  AND is_at_ma_target_firm != 1;

-- EXPECTED: 0 violations

-- ============================================================
-- CHECK 8.5: M&A Fields Not NULL
-- ============================================================
SELECT 
    '5. M&A Field Completeness' as check_name,
    SUM(CASE WHEN is_at_ma_target_firm IS NULL THEN 1 ELSE 0 END) as null_ma_flag,
    SUM(CASE WHEN score_tier LIKE 'TIER_MA%' AND ma_status IS NULL THEN 1 ELSE 0 END) as null_ma_status,
    SUM(CASE WHEN score_tier LIKE 'TIER_MA%' AND ma_days_since_news IS NULL THEN 1 ELSE 0 END) as null_days
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;

-- EXPECTED: All zeros

-- ============================================================
-- CHECK 8.6: Tier Distribution Sanity Check
-- ============================================================
SELECT 
    '6. Full Tier Distribution' as check_name,
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(expected_rate_pct), 2) as avg_expected_conv
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY score_tier
ORDER BY 
    CASE score_tier
        WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
        WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
        WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
        WHEN 'TIER_MA_ACTIVE_PRIME' THEN 4
        WHEN 'TIER_MA_ACTIVE' THEN 5
        WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 6
        ELSE 99
    END;

-- ============================================================
-- CHECK 8.7: Spot Check M&A Leads
-- ============================================================
SELECT 
    '7. Spot Check Sample' as check_name,
    crd,
    first_name,
    last_name,
    firm_name,
    job_title,
    score_tier,
    ma_status,
    ma_days_since_news,
    firm_rep_count,
    expected_rate_pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
ORDER BY 
    CASE score_tier WHEN 'TIER_MA_ACTIVE_PRIME' THEN 1 ELSE 2 END,
    ma_days_since_news
LIMIT 20;
