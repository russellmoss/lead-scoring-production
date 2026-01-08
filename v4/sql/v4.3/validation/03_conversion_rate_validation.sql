-- ============================================================================
-- VALIDATION GATE 3: CONVERSION RATE VALIDATION
-- ============================================================================
-- Validate Career Clock features show expected conversion lift
-- ============================================================================
-- 
-- PREREQUISITE: Run v4/sql/v4.3/phase_2_feature_engineering_v43.sql first
-- to create savvy-gtm-analytics.ml_features.v4_training_features_v43
-- ============================================================================

SELECT 
    CASE 
        WHEN cc_is_in_move_window = 1 THEN 'In_Window'
        WHEN cc_is_too_early = 1 THEN 'Too_Early'
        ELSE 'No_Pattern'
    END as cc_status,
    COUNT(*) as sample_size,
    SUM(converted) as conversions,
    ROUND(SUM(converted) * 100.0 / COUNT(*), 2) as conversion_rate_pct,
    ROUND(SUM(converted) * 100.0 / COUNT(*) / 3.82, 2) as lift_vs_baseline,
    CASE 
        WHEN cc_is_in_move_window = 1 AND SUM(converted) * 100.0 / COUNT(*) BETWEEN 5.0 AND 6.0 THEN '✅ PASS'
        WHEN cc_is_too_early = 1 AND SUM(converted) * 100.0 / COUNT(*) BETWEEN 3.5 AND 4.0 THEN '✅ PASS'
        WHEN cc_is_in_move_window = 0 AND cc_is_too_early = 0 AND SUM(converted) * 100.0 / COUNT(*) BETWEEN 3.5 AND 4.0 THEN '✅ PASS'
        ELSE '⚠️ REVIEW'
    END as status
FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
GROUP BY 1
ORDER BY conversion_rate_pct DESC;

-- ============================================================================
-- EXPECTED RESULTS:
-- ============================================================================
-- | CC Status | Expected Conv Rate | Expected Lift | Status |
-- |-----------|-------------------|---------------|--------|
-- | In_Window | 5.0-6.0% | 1.3-1.6x | ✅ PASS if in range |
-- | Too_Early | 3.5-4.0% | 0.9-1.0x | ✅ PASS if in range |
-- | No_Pattern | 3.5-4.0% | ~1.0x | ✅ PASS if in range |
-- ============================================================================
-- 
-- VALIDATION GATE: Conversion rates must match analysis results
-- - In_Window should show significantly higher conversion than baseline
-- - Too_Early should show similar or slightly lower conversion than baseline
-- - No_Pattern should match baseline conversion rate
-- ============================================================================
