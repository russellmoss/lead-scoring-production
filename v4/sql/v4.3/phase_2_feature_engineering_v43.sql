-- ============================================================================
-- V4.3.0 TRAINING FEATURE ENGINEERING (CAREER CLOCK + SHAP FIX)
-- ============================================================================
-- 
-- CRITICAL: All features must use only data available at contacted_date
-- 
-- CHANGES FROM V4.2.0:
-- - ADDED: cc_is_in_move_window (Career Clock timing signal)
-- - ADDED: cc_is_too_early (Career Clock deprioritization signal)
-- - Total features: 25 (was 23)
-- 
-- PIT Compliance Rules:
-- - Employment history: START_DATE <= contacted_date
-- - Career Clock: END_DATE < contacted_date (only completed jobs)
-- - NEVER use *_current tables for calculations (except null indicators)
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_training_features_v43` AS

WITH 
-- ============================================================================
-- BASE: Get target variable data
-- ============================================================================
base AS (
    SELECT 
        lead_id,
        advisor_crd,
        contacted_date,
        target as converted,  -- Renamed for validation queries
        lead_source_grouped
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable`
    WHERE target IS NOT NULL  -- Only mature leads for training
),

-- ============================================================================
-- CAREER CLOCK STATS (V4.3.0) - TRAINING VERSION
-- ============================================================================
-- Calculates advisor career patterns from completed employment records
-- PIT-SAFE: Only uses jobs with END_DATE < contacted_date
-- ============================================================================
career_clock_stats_training AS (
    SELECT
        b.lead_id,
        b.crd,
        b.contacted_date,
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
    FROM base b
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.crd = eh.RIA_CONTACT_CRD_ID
    WHERE eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
      -- ⚠️ PIT CRITICAL: Only completed jobs BEFORE contacted_date
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < b.contacted_date
      -- Valid tenure (positive months)
      AND DATE_DIFF(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                    eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) > 0
    GROUP BY b.lead_id, b.crd, b.contacted_date
    HAVING COUNT(*) >= 2  -- Need 2+ completed jobs to detect pattern
),

-- ============================================================================
-- CAREER CLOCK FEATURES (V4.3.0) - TRAINING VERSION
-- ============================================================================
-- Derives the 2 selective features from career clock stats
-- Uses tenure at contacted_date (PIT-safe)
-- ============================================================================
career_clock_features_training AS (
    SELECT
        cf.lead_id,
        cf.crd,
        cf.contacted_date,
        
        -- ================================================================
        -- FEATURE 24: cc_is_in_move_window (PRIMARY SIGNAL)
        -- ================================================================
        CASE 
            WHEN ccs.cc_tenure_cv IS NOT NULL 
                 AND ccs.cc_tenure_cv < 0.5 
                 AND SAFE_DIVIDE(cf.tenure_months, ccs.cc_avg_prior_tenure_months) BETWEEN 0.7 AND 1.3
            THEN 1 
            ELSE 0 
        END as cc_is_in_move_window,
        
        -- ================================================================
        -- FEATURE 25: cc_is_too_early (DEPRIORITIZATION SIGNAL)
        -- ================================================================
        CASE 
            WHEN ccs.cc_tenure_cv IS NOT NULL 
                 AND ccs.cc_tenure_cv < 0.5 
                 AND SAFE_DIVIDE(cf.tenure_months, ccs.cc_avg_prior_tenure_months) < 0.7
            THEN 1 
            ELSE 0 
        END as cc_is_too_early
        
    FROM current_firm cf
    LEFT JOIN career_clock_stats_training ccs 
        ON cf.lead_id = ccs.lead_id
        AND cf.contacted_date = ccs.contacted_date
),

-- ============================================================================
-- COMBINE ALL FEATURES (25 features for V4.3.0)
-- ============================================================================
all_features AS (
    SELECT
        -- Base columns
        b.lead_id,
        b.crd,
        b.contacted_date,
        b.converted,
        b.lead_source_grouped,
        
        -- ====================================================================
        -- EXISTING V4.2.0 FEATURES (23 - ALL PRESERVED)
        -- ====================================================================
        -- [Include all 23 features from v4.1 training SQL]
        -- 1. experience_years
        -- 2. tenure_months
        -- 3. mobility_3yr
        -- 4. firm_rep_count (or firm_rep_count_at_contact)
        -- 5. firm_net_change_12mo
        -- 6. num_prior_firms
        -- 7. is_ia_rep_type
        -- 8. is_independent_ria
        -- 9. is_dual_registered
        -- 10. is_recent_mover
        -- 11. age_bucket_encoded
        -- 12. firm_departures_corrected
        -- 13. bleeding_velocity_encoded
        -- 14. days_since_last_move
        -- 15. short_tenure_x_high_mobility
        -- 16. mobility_x_heavy_bleeding
        -- 17. has_email
        -- 18. has_linkedin
        -- 19. has_firm_data
        -- 20. is_wirehouse
        -- 21. is_broker_protocol
        -- 22. has_cfp
        -- 23. has_series_65_only
        -- 
        -- NOTE: Copy all feature selections from v4.1 training SQL
        -- ====================================================================
        
        -- ================================================================
        -- V4.3.0: CAREER CLOCK FEATURES (2 new features)
        -- ================================================================
        COALESCE(ccf.cc_is_in_move_window, 0) as cc_is_in_move_window,
        COALESCE(ccf.cc_is_too_early, 0) as cc_is_too_early
        
    FROM base b
    -- [Include all existing JOINs from v4.1 training SQL]
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id
    -- ... [all other JOINs]
    -- V4.3.0: Career Clock features
    LEFT JOIN career_clock_features_training ccf 
        ON b.lead_id = ccf.lead_id
        AND b.contacted_date = ccf.contacted_date
)

SELECT DISTINCT * FROM all_features;

-- ============================================================================
-- NOTE: This is a template. You must:
-- 1. Copy all CTEs from v4/sql/v4.1/phase_2_feature_engineering_v41.sql
-- 2. Replace the Career Clock CTEs with the V4.3.0 versions above
-- 3. Update the final SELECT to include all 23 V4.2.0 features + 2 Career Clock
-- 4. Update table name to v4_training_features_v43
-- ============================================================================
