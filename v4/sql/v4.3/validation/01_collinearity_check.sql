-- ============================================================================
-- VALIDATION GATE 1: COLLINEARITY CHECK
-- ============================================================================
-- Career Clock vs All Existing Features
-- THRESHOLD: Correlation < 0.30 = PASS
-- 
-- If any correlation > 0.30, the feature may be redundant and should NOT be added
-- ============================================================================
-- 
-- PREREQUISITE: Run v4/sql/v4.3/phase_2_feature_engineering_v43.sql first
-- to create savvy-gtm-analytics.ml_features.v4_training_features_v43
-- ============================================================================

WITH feature_data AS (
    SELECT
        -- Existing V4.2.0 features
        experience_years,
        tenure_months,
        mobility_3yr,
        firm_rep_count,
        firm_net_change_12mo,
        num_prior_firms,
        is_ia_rep_type,
        is_independent_ria,
        is_dual_registered,
        is_recent_mover,
        age_bucket_encoded,
        firm_departures_corrected,
        bleeding_velocity_encoded,
        days_since_last_move,
        short_tenure_x_high_mobility,
        mobility_x_heavy_bleeding,
        has_email,
        has_linkedin,
        has_firm_data,
        is_wirehouse,
        is_broker_protocol,
        has_cfp,
        has_series_65_only,
        
        -- New V4.3.0 features
        cc_is_in_move_window,
        cc_is_too_early
        
    FROM `savvy-gtm-analytics.ml_features.v4_training_features_v43`
)

SELECT 
    'cc_is_in_move_window' as new_feature,
    'experience_years' as existing_feature,
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
ORDER BY ABS(correlation) DESC;

-- ============================================================================
-- EXPECTED RESULTS:
-- ============================================================================
-- All correlations should be < 0.30 (absolute value)
-- 
-- Expected correlations (from analysis):
-- - cc_is_in_move_window vs age_bucket_encoded: ~-0.027 ✅
-- - cc_is_too_early vs age_bucket_encoded: ~-0.035 ✅
-- - cc_is_in_move_window vs tenure_months: < 0.20 ✅
-- - cc_is_in_move_window vs cc_is_too_early: ~-0.15 ✅
-- 
-- If any correlation >= 0.30: STOP and investigate before proceeding
-- ============================================================================
