-- ============================================================================
-- V4.3.0 PRE-TRAINING VALIDATION - ALL GATES
-- ============================================================================
-- Run all validation queries in sequence
-- 
-- PREREQUISITE: 
-- 1. Run v4/sql/v4.3/phase_2_feature_engineering_v43.sql first
--    to create savvy-gtm-analytics.ml_features.v4_training_features_v43
-- 2. Ensure the table has the 'converted' column (target variable)
-- ============================================================================
-- 
-- VALIDATION GATES:
-- 1. Collinearity Check: All correlations < 0.30
-- 2. Feature Coverage: Expected distribution of Career Clock features
-- 3. Conversion Rate: Expected conversion lift for Career Clock features
-- ============================================================================

-- ============================================================================
-- GATE 1: COLLINEARITY CHECK
-- ============================================================================
SELECT '=' as separator, 'GATE 1: COLLINEARITY CHECK' as gate_name, '' as result
UNION ALL
SELECT '', 'All correlations must be < 0.30', ''
UNION ALL
SELECT '', '', '';

WITH feature_data AS (
    SELECT
        experience_years, tenure_months, mobility_3yr, firm_rep_count,
        firm_net_change_12mo, num_prior_firms, is_ia_rep_type,
        is_independent_ria, is_dual_registered, is_recent_mover,
        age_bucket_encoded, firm_departures_corrected, bleeding_velocity_encoded,
        days_since_last_move, short_tenure_x_high_mobility, mobility_x_heavy_bleeding,
        has_email, has_linkedin, has_firm_data, is_wirehouse,
        is_broker_protocol, has_cfp, has_series_65_only,
        cc_is_in_move_window, cc_is_too_early
    FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
)
SELECT 
    new_feature,
    existing_feature,
    correlation,
    status
FROM (
    SELECT 'cc_is_in_move_window' as new_feature, 'experience_years' as existing_feature,
           ROUND(CORR(cc_is_in_move_window, experience_years), 4) as correlation,
           CASE WHEN ABS(CORR(cc_is_in_move_window, experience_years)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END as status
    FROM feature_data
    UNION ALL
    SELECT 'cc_is_in_move_window', 'tenure_months', ROUND(CORR(cc_is_in_move_window, tenure_months), 4),
           CASE WHEN ABS(CORR(cc_is_in_move_window, tenure_months)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
    UNION ALL
    SELECT 'cc_is_in_move_window', 'age_bucket_encoded', ROUND(CORR(cc_is_in_move_window, age_bucket_encoded), 4),
           CASE WHEN ABS(CORR(cc_is_in_move_window, age_bucket_encoded)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
    UNION ALL
    SELECT 'cc_is_in_move_window', 'mobility_3yr', ROUND(CORR(cc_is_in_move_window, mobility_3yr), 4),
           CASE WHEN ABS(CORR(cc_is_in_move_window, mobility_3yr)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
    UNION ALL
    SELECT 'cc_is_in_move_window', 'num_prior_firms', ROUND(CORR(cc_is_in_move_window, num_prior_firms), 4),
           CASE WHEN ABS(CORR(cc_is_in_move_window, num_prior_firms)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
    UNION ALL
    SELECT 'cc_is_in_move_window', 'is_recent_mover', ROUND(CORR(cc_is_in_move_window, is_recent_mover), 4),
           CASE WHEN ABS(CORR(cc_is_in_move_window, is_recent_mover)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
    UNION ALL
    SELECT 'cc_is_in_move_window', 'days_since_last_move', ROUND(CORR(cc_is_in_move_window, days_since_last_move), 4),
           CASE WHEN ABS(CORR(cc_is_in_move_window, days_since_last_move)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
    UNION ALL
    SELECT 'cc_is_too_early', 'experience_years', ROUND(CORR(cc_is_too_early, experience_years), 4),
           CASE WHEN ABS(CORR(cc_is_too_early, experience_years)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
    UNION ALL
    SELECT 'cc_is_too_early', 'tenure_months', ROUND(CORR(cc_is_too_early, tenure_months), 4),
           CASE WHEN ABS(CORR(cc_is_too_early, tenure_months)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
    UNION ALL
    SELECT 'cc_is_too_early', 'age_bucket_encoded', ROUND(CORR(cc_is_too_early, age_bucket_encoded), 4),
           CASE WHEN ABS(CORR(cc_is_too_early, age_bucket_encoded)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
    UNION ALL
    SELECT 'cc_is_too_early', 'mobility_3yr', ROUND(CORR(cc_is_too_early, mobility_3yr), 4),
           CASE WHEN ABS(CORR(cc_is_too_early, mobility_3yr)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
    UNION ALL
    SELECT 'cc_is_in_move_window', 'cc_is_too_early', ROUND(CORR(cc_is_in_move_window, cc_is_too_early), 4),
           CASE WHEN ABS(CORR(cc_is_in_move_window, cc_is_too_early)) < 0.30 THEN '✅ PASS' ELSE '❌ FAIL' END FROM feature_data
)
ORDER BY ABS(correlation) DESC;

-- ============================================================================
-- GATE 2: FEATURE COVERAGE CHECK
-- ============================================================================
SELECT '' as separator, '' as gate_name, '' as result
UNION ALL
SELECT '=', 'GATE 2: FEATURE COVERAGE CHECK', ''
UNION ALL
SELECT '', 'Expected: In_Window 4-6%, Too_Early 8-12%, No_Pattern 75-85%', ''
UNION ALL
SELECT '', '', '';

SELECT 
    metric,
    value,
    percentage,
    CASE 
        WHEN metric = 'cc_is_in_move_window = 1' AND percentage BETWEEN 4 AND 6 THEN '✅ PASS'
        WHEN metric = 'cc_is_too_early = 1' AND percentage BETWEEN 8 AND 12 THEN '✅ PASS'
        WHEN metric = 'Both = 0 (no pattern)' AND percentage BETWEEN 75 AND 85 THEN '✅ PASS'
        WHEN metric = 'Both = 1 (invalid state)' AND percentage = 0 THEN '✅ PASS'
        ELSE '⚠️ REVIEW'
    END as status
FROM (
    SELECT 
        'Total prospects' as metric,
        COUNT(*) as value,
        NULL as percentage
    FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
    UNION ALL
    SELECT 
        'cc_is_in_move_window = 1',
        COUNTIF(cc_is_in_move_window = 1),
        ROUND(COUNTIF(cc_is_in_move_window = 1) * 100.0 / COUNT(*), 2)
    FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
    UNION ALL
    SELECT 
        'cc_is_too_early = 1',
        COUNTIF(cc_is_too_early = 1),
        ROUND(COUNTIF(cc_is_too_early = 1) * 100.0 / COUNT(*), 2)
    FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
    UNION ALL
    SELECT 
        'Both = 0 (no pattern)',
        COUNTIF(cc_is_in_move_window = 0 AND cc_is_too_early = 0),
        ROUND(COUNTIF(cc_is_in_move_window = 0 AND cc_is_too_early = 0) * 100.0 / COUNT(*), 2)
    FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
    UNION ALL
    SELECT 
        'Both = 1 (invalid state)',
        COUNTIF(cc_is_in_move_window = 1 AND cc_is_too_early = 1),
        ROUND(COUNTIF(cc_is_in_move_window = 1 AND cc_is_too_early = 1) * 100.0 / COUNT(*), 2)
    FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
);

-- ============================================================================
-- GATE 3: CONVERSION RATE VALIDATION
-- ============================================================================
SELECT '' as separator, '' as gate_name, '' as result
UNION ALL
SELECT '=', 'GATE 3: CONVERSION RATE VALIDATION', ''
UNION ALL
SELECT '', 'Expected: In_Window 5-6%, Too_Early 3.5-4%, No_Pattern 3.5-4%', ''
UNION ALL
SELECT '', '', '';

SELECT 
    cc_status,
    sample_size,
    conversions,
    conversion_rate_pct,
    lift_vs_baseline,
    status
FROM (
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
)
ORDER BY conversion_rate_pct DESC;

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- Review all three gates above. All must PASS before proceeding to training.
-- 
-- If any gate FAILS:
-- 1. Review the results
-- 2. Investigate the issue
-- 3. Fix the feature engineering SQL if needed
-- 4. Re-run validation
-- 
-- Only proceed to training when ALL gates PASS.
-- ============================================================================
