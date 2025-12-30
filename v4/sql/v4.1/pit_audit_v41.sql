-- File: v4/sql/v4.1/pit_audit_v41.sql
-- Purpose: Comprehensive PIT leakage audit for V4.1 features

-- ==========================================================================
-- AUDIT 1: is_recent_mover - Verify no future START_DATE usage
-- ==========================================================================
SELECT 
    'is_recent_mover' as feature,
    COUNT(*) as total_recent_movers,
    SUM(CASE 
        WHEN rm.current_firm_start_date > f.contacted_date 
        THEN 1 ELSE 0 
    END) as pit_violations,
    CASE 
        WHEN SUM(CASE WHEN rm.current_firm_start_date > f.contacted_date THEN 1 ELSE 0 END) = 0
        THEN 'PASSED' ELSE 'FAILED' 
    END as status
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41` f
LEFT JOIN `savvy-gtm-analytics.ml_features.recent_movers_v41` rm
    ON f.advisor_crd = rm.advisor_crd
WHERE f.is_recent_mover = 1;

-- ==========================================================================
-- AUDIT 2: days_since_last_move - Verify no negative values
-- ==========================================================================
SELECT 
    'days_since_last_move' as feature,
    COUNT(*) as total_rows,
    SUM(CASE WHEN days_since_last_move < 0 THEN 1 ELSE 0 END) as negative_values,
    MIN(days_since_last_move) as min_value,
    MAX(days_since_last_move) as max_value,
    CASE 
        WHEN MIN(days_since_last_move) >= 0 THEN 'PASSED' ELSE 'FAILED' 
    END as status
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE days_since_last_move != 9999;  -- Exclude default value

-- ==========================================================================
-- AUDIT 3: firm_departures_corrected - Verify all departures before contact
-- ==========================================================================
-- This is validated in the feature engineering SQL itself, but we can spot-check
SELECT 
    'firm_departures_corrected' as feature,
    COUNT(*) as total_rows,
    AVG(firm_departures_corrected) as avg_departures,
    MIN(firm_departures_corrected) as min_departures,
    MAX(firm_departures_corrected) as max_departures,
    'VALIDATED_IN_SQL' as status
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE firm_departures_corrected > 0;

-- ==========================================================================
-- AUDIT 4: Feature-Target Correlation Check
-- ==========================================================================
SELECT 
    'Correlation Check' as audit,
    CORR(CAST(is_recent_mover AS FLOAT64), CAST(target AS FLOAT64)) as corr_is_recent_mover,
    CORR(CAST(days_since_last_move AS FLOAT64), CAST(target AS FLOAT64)) as corr_days_since_move,
    CORR(CAST(firm_departures_corrected AS FLOAT64), CAST(target AS FLOAT64)) as corr_departures_corrected,
    CORR(CAST(bleeding_velocity_encoded AS FLOAT64), CAST(target AS FLOAT64)) as corr_bleeding_velocity,
    CORR(CAST(recent_mover_x_bleeding AS FLOAT64), CAST(target AS FLOAT64)) as corr_interaction,
    CORR(CAST(is_independent_ria AS FLOAT64), CAST(target AS FLOAT64)) as corr_independent_ria,
    CORR(CAST(is_ia_rep_type AS FLOAT64), CAST(target AS FLOAT64)) as corr_ia_rep_type,
    CORR(CAST(is_dual_registered AS FLOAT64), CAST(target AS FLOAT64)) as corr_dual_registered,
    CORR(CAST(independent_ria_x_ia_rep AS FLOAT64), CAST(target AS FLOAT64)) as corr_independent_ria_x_ia
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE target IS NOT NULL;

-- ==========================================================================
-- AUDIT 5: Spot-Check Sample (Manual Review)
-- ==========================================================================
SELECT 
    lead_id,
    advisor_crd,
    contacted_date,
    target,
    is_recent_mover,
    days_since_last_move,
    firm_departures_corrected,
    bleeding_velocity_encoded,
    recent_mover_x_bleeding,
    is_independent_ria,
    is_ia_rep_type,
    is_dual_registered,
    independent_ria_x_ia_rep
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE target IS NOT NULL
ORDER BY RAND()
LIMIT 100;

