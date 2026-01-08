-- ============================================================================
-- VALIDATION GATE 2: FEATURE COVERAGE CHECK
-- ============================================================================
-- Check Career Clock feature distribution
-- ============================================================================
-- 
-- PREREQUISITE: Run v4/sql/v4.3/phase_2_feature_engineering_v43.sql first
-- to create savvy-gtm-analytics.ml_features.v4_training_features_v43
-- ============================================================================

SELECT 
    'Total prospects' as metric,
    COUNT(*) as value,
    NULL as percentage
FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
UNION ALL
SELECT 
    'cc_is_in_move_window = 1' as metric,
    COUNTIF(cc_is_in_move_window = 1) as value,
    ROUND(COUNTIF(cc_is_in_move_window = 1) * 100.0 / COUNT(*), 2) as percentage
FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
UNION ALL
SELECT 
    'cc_is_too_early = 1' as metric,
    COUNTIF(cc_is_too_early = 1) as value,
    ROUND(COUNTIF(cc_is_too_early = 1) * 100.0 / COUNT(*), 2) as percentage
FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
UNION ALL
SELECT 
    'Both = 0 (no pattern)' as metric,
    COUNTIF(cc_is_in_move_window = 0 AND cc_is_too_early = 0) as value,
    ROUND(COUNTIF(cc_is_in_move_window = 0 AND cc_is_too_early = 0) * 100.0 / COUNT(*), 2) as percentage
FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
UNION ALL
SELECT 
    'Both = 1 (invalid state)' as metric,
    COUNTIF(cc_is_in_move_window = 1 AND cc_is_too_early = 1) as value,
    ROUND(COUNTIF(cc_is_in_move_window = 1 AND cc_is_too_early = 1) * 100.0 / COUNT(*), 2) as percentage
FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`;

-- ============================================================================
-- EXPECTED DISTRIBUTION:
-- ============================================================================
-- | Metric | Expected % | Status |
-- |--------|-----------|--------|
-- | cc_is_in_move_window = 1 | 4-6% | ✅ PASS if in range |
-- | cc_is_too_early = 1 | 8-12% | ✅ PASS if in range |
-- | Both = 0 (no pattern) | 75-85% | ✅ PASS if in range |
-- | Both = 1 (invalid state) | 0% | ❌ FAIL if > 0% |
-- ============================================================================
-- 
-- NOTE: Both features should never be 1 simultaneously (mutually exclusive)
-- ============================================================================
