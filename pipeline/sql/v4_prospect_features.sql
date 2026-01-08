-- ============================================================================
-- V4.3.2 PROSPECT FEATURES (CAREER CLOCK + FUZZY FIRM MATCHING)
-- ============================================================================
-- Version: 4.3.2
-- Updated: 2026-01-08
-- 
-- CHANGES FROM V4.2.0:
-- - ADDED: cc_is_in_move_window (Career Clock timing signal)
-- - ADDED: cc_is_too_early (Career Clock deprioritization signal)
-- - FIXED: SHAP base_score bug - now using true SHAP values for narratives
-- - Total features: 26 (was 23)
--
-- V4.3.1 CHANGES (January 8, 2026):
-- - FIXED: Career Clock data quality - exclude current firm from employment history
-- - ADDED: is_likely_recent_promotee feature (26 total features)
-- - Impact: ~692 advisors had polluted Career Clock data (10-19% of long-tenure advisors)
-- - Example: Rafael Delasierra (founder, 27yr at firm) incorrectly in "move window"
--
-- V4.3.2 CHANGES (January 8, 2026):
-- - FIXED: Career Clock fuzzy firm name matching for re-registrations
-- - Excludes "prior firms" that match current firm name (first 15 chars after cleaning)
-- - Example: James Patton at "Patton Albertson Miller Group" (CRD 281558) had
--   "Patton Albertson & Miller" (CRD 126145) incorrectly counted as prior job
-- - Impact: ~135 advisors removed from incorrect move window status
-- 
-- SHAP FIX:
-- - V4.2.0 used gain-based importance due to XGBoost base_score serialization bug
-- - V4.3.0 explicitly calculates and preserves base_score during training
-- - Narratives now show true SHAP values with direction (increases/decreases)
-- - SHAP values validated to sum to predictions
--
-- CAREER CLOCK VALIDATION:
-- - Independent from age_bucket_encoded (correlation = 0.035)
-- - In_Window adds 2.43x lift within 35-49 age group
-- - Too_Early provides deprioritization signal (3.72% vs 3.82% baseline)
-- - Analysis: career_clock_results.md (January 7, 2026)
--
-- EXISTING V4.2.0 FEATURES (23 - ALL PRESERVED):
-- 1. experience_years           12. firm_departures_corrected
-- 2. tenure_months              13. bleeding_velocity_encoded
-- 3. mobility_3yr               14. days_since_last_move
-- 4. firm_rep_count             15. short_tenure_x_high_mobility
-- 5. firm_net_change_12mo       16. mobility_x_heavy_bleeding
-- 6. num_prior_firms            17. has_email
-- 7. is_ia_rep_type             18. has_linkedin
-- 8. is_independent_ria         19. has_firm_data
-- 9. is_dual_registered         20. is_wirehouse
-- 10. is_recent_mover           21. is_broker_protocol
-- 11. age_bucket_encoded        22. has_cfp
--                               23. has_series_65_only
--
-- NEW V4.3.0 FEATURES (2 - ADDITIVE):
-- 24. cc_is_in_move_window      (Career Clock: In move window flag)
-- 25. cc_is_too_early           (Career Clock: Too early flag)
--
-- PIT COMPLIANCE:
-- - Career Clock uses only completed employment records (END_DATE < prediction_date)
-- - Current tenure calculated as of prediction_date
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_prospect_features` AS

WITH 
-- ============================================================================
-- BASE: All producing advisors from FINTRX
-- ============================================================================
base_prospects AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as current_firm_crd,  -- V4.3.1: For Career Clock current firm exclusion
        c.PRIMARY_FIRM_NAME as firm_name,
        c.LATEST_REGISTERED_EMPLOYMENT_START_DATE as firm_start_date,
        c.PRIMARY_FIRM_START_DATE as primary_firm_start_date,
        c.EMAIL,
        c.LINKEDIN_PROFILE_URL,
        c.REP_TYPE,
        c.REP_LICENSES,
        c.PRIMARY_FIRM_CLASSIFICATION,
        CURRENT_DATE() as prediction_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    WHERE c.RIA_CONTACT_CRD_ID IS NOT NULL
      AND c.PRODUCING_ADVISOR = TRUE
      AND c.ACTIVE = TRUE
),

-- ============================================================================
-- FEATURE GROUP 1: TENURE FEATURES
-- ============================================================================
-- First try employment history (PIT-compliant historical data)
history_firm AS (
    SELECT 
        bp.crd,
        bp.prediction_date,
        bp.firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd_from_history,
        eh.PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name_from_history,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_date_from_history,
        DATE_DIFF(bp.prediction_date, eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) as tenure_months
    FROM base_prospects bp
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON bp.crd = eh.RIA_CONTACT_CRD_ID
        AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= bp.prediction_date
        AND (eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
             OR eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= bp.prediction_date)
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY bp.crd 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
),

-- Fallback to current snapshot if no history found
current_snapshot AS (
    SELECT 
        bp.crd,
        bp.prediction_date,
        bp.firm_crd,
        bp.firm_name,
        bp.firm_start_date,
        CASE 
            WHEN bp.firm_start_date IS NOT NULL AND bp.firm_start_date <= bp.prediction_date 
            THEN DATE_DIFF(bp.prediction_date, bp.firm_start_date, MONTH)
            ELSE NULL
        END as tenure_months
    FROM base_prospects bp
    WHERE bp.firm_start_date IS NOT NULL
      AND bp.firm_start_date <= bp.prediction_date
),

-- Combine: prefer history, fallback to current snapshot
current_firm AS (
    SELECT 
        COALESCE(hf.crd, cs.crd) as crd,
        COALESCE(hf.prediction_date, cs.prediction_date) as prediction_date,
        COALESCE(hf.firm_crd_from_history, cs.firm_crd) as firm_crd,
        COALESCE(hf.firm_name_from_history, cs.firm_name) as firm_name,
        COALESCE(hf.firm_start_date_from_history, cs.firm_start_date) as firm_start_date,
        COALESCE(hf.tenure_months, cs.tenure_months) as tenure_months,
        -- Calculate tenure_days for V4.1 feature
        DATE_DIFF(COALESCE(hf.prediction_date, cs.prediction_date), 
                  COALESCE(hf.firm_start_date_from_history, cs.firm_start_date), 
                  DAY) as tenure_days
    FROM history_firm hf
    FULL OUTER JOIN current_snapshot cs
        ON hf.crd = cs.crd
    WHERE COALESCE(hf.crd, cs.crd) IS NOT NULL
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY COALESCE(hf.crd, cs.crd)
        ORDER BY 
            CASE WHEN hf.crd IS NOT NULL THEN 1 ELSE 2 END,  -- Prefer history
            COALESCE(hf.firm_start_date_from_history, cs.firm_start_date) DESC
    ) = 1
),

-- Calculate industry tenure (OPTIMIZED - use ria_contacts_current as fallback)
-- For simplicity, use the INDUSTRY_TENURE_MONTHS field from ria_contacts_current
-- This is pre-calculated and avoids correlated subqueries
-- Note: This may slightly differ from training data, but acceptable for production
industry_tenure AS (
    SELECT
        cf.crd,
        cf.prediction_date,
        cf.firm_start_date,
        -- Use pre-calculated industry tenure from ria_contacts_current
        -- Subtract current firm tenure to get prior experience
        GREATEST(
            COALESCE(c.INDUSTRY_TENURE_MONTHS, 0) - COALESCE(cf.tenure_months, 0),
            0
        ) as industry_tenure_months
    FROM current_firm cf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON cf.crd = c.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- FEATURE GROUP 2: MOBILITY FEATURES
-- ============================================================================
mobility AS (
    SELECT 
        bp.crd,
        bp.prediction_date,
        COUNT(DISTINCT CASE 
            WHEN eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE > DATE_SUB(bp.prediction_date, INTERVAL 3 YEAR)
                AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= bp.prediction_date
            THEN eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID
        END) as mobility_3yr
    FROM base_prospects bp
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON bp.crd = eh.RIA_CONTACT_CRD_ID
    GROUP BY bp.crd, bp.prediction_date
),

-- ============================================================================
-- FEATURE GROUP 3: FIRM STABILITY (OPTIMIZED - pre-aggregated, no correlated subqueries)
-- ============================================================================

-- Pre-aggregate departures by firm (runs once, not per row)
firm_departures_agg AS (
    SELECT 
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < CURRENT_DATE()
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
),

-- Pre-aggregate arrivals by firm (runs once, not per row)
firm_arrivals_agg AS (
    SELECT 
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PREVIOUS_REGISTRATION_COMPANY_START_DATE < CURRENT_DATE()
    GROUP BY 1
),

-- Pre-aggregate current rep count by firm (runs once, not per row)
firm_rep_count_agg AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as rep_count
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
      AND PRODUCING_ADVISOR = TRUE
      AND ACTIVE = TRUE
    GROUP BY 1
),

-- Combine firm metrics (simple JOINs instead of correlated subqueries)
firm_stability AS (
    SELECT
        cf.crd,
        cf.firm_crd,
        cf.prediction_date,
        COALESCE(fd.departures_12mo, 0) as firm_departures_12mo,
        COALESCE(fa.arrivals_12mo, 0) as firm_arrivals_12mo,
        COALESCE(fr.rep_count, 0) as firm_rep_count_at_contact
    FROM current_firm cf
    LEFT JOIN firm_departures_agg fd ON cf.firm_crd = fd.firm_crd
    LEFT JOIN firm_arrivals_agg fa ON cf.firm_crd = fa.firm_crd
    LEFT JOIN firm_rep_count_agg fr ON cf.firm_crd = fr.firm_crd
    WHERE cf.firm_crd IS NOT NULL
),

-- ============================================================================
-- FEATURE GROUP 4: WIREHOUSE & BROKER PROTOCOL
-- ============================================================================
wirehouse AS (
    SELECT
        cf.crd,
        CASE
            WHEN UPPER(cf.firm_name) LIKE '%MERRILL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%MORGAN STANLEY%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%UBS%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%WELLS FARGO%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%EDWARD JONES%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%RAYMOND JAMES%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%AMERIPRISE%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%LPL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%NORTHWESTERN MUTUAL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%STIFEL%' THEN 1
            ELSE 0
        END as is_wirehouse
    FROM current_firm cf
),

broker_protocol AS (
    SELECT DISTINCT
        cf.crd,
        CASE WHEN bp.firm_crd_id IS NOT NULL THEN 1 ELSE 0 END as is_broker_protocol
    FROM current_firm cf
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.broker_protocol_members` bp
        ON cf.firm_crd = bp.firm_crd_id
    QUALIFY ROW_NUMBER() OVER(PARTITION BY cf.crd ORDER BY bp.firm_crd_id) = 1
),

-- ============================================================================
-- FEATURE GROUP 5: EXPERIENCE
-- ============================================================================
experience AS (
    SELECT
        bp.crd,
        COALESCE(it.industry_tenure_months, c.INDUSTRY_TENURE_MONTHS, 0) / 12.0 as experience_years,
        CASE WHEN COALESCE(it.industry_tenure_months, c.INDUSTRY_TENURE_MONTHS) IS NULL THEN 1 ELSE 0 END as is_experience_missing
    FROM base_prospects bp
    LEFT JOIN industry_tenure it ON bp.crd = it.crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON bp.crd = c.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- FEATURE GROUP 6: DATA QUALITY FLAGS
-- ============================================================================
data_quality AS (
    SELECT
        bp.crd,
        CASE WHEN bp.EMAIL IS NOT NULL AND bp.EMAIL != '' THEN 1 ELSE 0 END as has_email,
        CASE WHEN bp.LINKEDIN_PROFILE_URL IS NOT NULL AND bp.LINKEDIN_PROFILE_URL != '' THEN 1 ELSE 0 END as has_linkedin,
        CASE WHEN cf.firm_crd IS NOT NULL THEN 1 ELSE 0 END as has_firm_data
    FROM base_prospects bp
    LEFT JOIN current_firm cf ON bp.crd = cf.crd
),

-- ============================================================================
-- V4.1 NEW FEATURES: RECENT MOVER DETECTION
-- ============================================================================
recent_mover_features AS (
    SELECT 
        bp.crd,
        bp.prediction_date,
        -- is_recent_mover: moved in last 12 months
        CASE 
            WHEN cf.tenure_months IS NOT NULL AND cf.tenure_months <= 12 
            THEN 1 ELSE 0 
        END as is_recent_mover,
        -- days_since_last_move: days since joining current firm
        COALESCE(cf.tenure_days, 9999) as days_since_last_move
    FROM base_prospects bp
    LEFT JOIN current_firm cf ON bp.crd = cf.crd
),

-- ============================================================================
-- V4.1 NEW FEATURES: CORRECTED FIRM BLEEDING
-- ============================================================================
firm_bleeding_corrected_features AS (
    SELECT 
        fbc.firm_crd,
        fbc.departures_12mo_inferred as firm_departures_corrected
    FROM `savvy-gtm-analytics.ml_features.firm_bleeding_corrected` fbc
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY fbc.firm_crd 
        ORDER BY fbc.departures_12mo_inferred DESC  -- Prefer highest departure count if duplicates exist
    ) = 1
),

-- ============================================================================
-- V4.1 NEW FEATURES: BLEEDING VELOCITY
-- ============================================================================
bleeding_velocity AS (
    SELECT 
        bv.firm_crd,
        bv.bleeding_velocity,
        -- Encode velocity: 0=STABLE, 1=DECELERATING, 2=STEADY, 3=ACCELERATING
        CASE 
            WHEN bv.bleeding_velocity = 'ACCELERATING' THEN 3
            WHEN bv.bleeding_velocity = 'STEADY' THEN 2
            WHEN bv.bleeding_velocity = 'DECELERATING' THEN 1
            ELSE 0  -- STABLE or NULL
        END as bleeding_velocity_encoded
    FROM `savvy-gtm-analytics.ml_features.firm_bleeding_velocity_v41` bv
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY bv.firm_crd 
        ORDER BY 
            CASE bv.bleeding_velocity
                WHEN 'ACCELERATING' THEN 3
                WHEN 'STEADY' THEN 2
                WHEN 'DECELERATING' THEN 1
                ELSE 0
            END DESC  -- Prefer most severe velocity if duplicates exist
    ) = 1
),

-- ============================================================================
-- V4.1 NEW FEATURES: FIRM/REP TYPE FEATURES
-- ============================================================================
firm_rep_type_features AS (
    SELECT 
        bp.crd,
        -- is_independent_ria: Independent RIA flag
        CASE 
            WHEN bp.PRIMARY_FIRM_CLASSIFICATION LIKE '%Independent RIA%' 
            THEN 1 ELSE 0 
        END as is_independent_ria,
        -- is_ia_rep_type: Pure IA rep type
        CASE WHEN bp.REP_TYPE = 'IA' THEN 1 ELSE 0 END as is_ia_rep_type,
        -- is_dual_registered: Dual registered (both IA and BD)
        CASE 
            WHEN bp.REP_TYPE = 'DR' 
                 OR (bp.REP_LICENSES LIKE '%Series 7%' AND bp.REP_LICENSES LIKE '%Series 65%') 
            THEN 1 ELSE 0 
        END as is_dual_registered
    FROM base_prospects bp
),

-- ============================================================================
-- CAREER CLOCK STATS (V4.3.0)
-- ============================================================================
-- Calculates advisor career patterns from completed employment records
-- PIT-SAFE: Only uses jobs with END_DATE < prediction_date
-- 
-- Features:
-- - cc_completed_jobs: Number of completed prior jobs
-- - cc_avg_prior_tenure_months: Average tenure at prior firms
-- - cc_tenure_cv: Coefficient of variation (STDDEV/AVG) of tenure lengths
--   - CV < 0.3 = "Clockwork" (highly predictable pattern)
--   - CV 0.3-0.5 = "Semi-Predictable"
--   - CV >= 0.5 = Unpredictable (no pattern)
-- ============================================================================
career_clock_stats AS (
    SELECT
        bp.crd,
        bp.prediction_date,
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
    FROM base_prospects bp
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON bp.crd = eh.RIA_CONTACT_CRD_ID
    WHERE eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
      -- ⚠️ PIT CRITICAL: Only completed jobs BEFORE prediction_date
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < bp.prediction_date
      -- Valid tenure (positive months)
      AND DATE_DIFF(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                    eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) > 0
      -- ============================================================================
      -- V4.3.1 FIX: Exclude current firm from employment history
      -- ============================================================================
      -- Analysis (January 8, 2026) found ~692 advisors with polluted Career Clock
      -- data because their current firm appeared in employment history (e.g., firm
      -- re-registrations, CRD changes). This caused advisors like Rafael Delasierra
      -- (27yr founder) to incorrectly appear in "move window."
      -- 
      -- Impact by tenure bucket:
      --   10-15 years: 19.3% affected
      --   20+ years: 10.6% affected
      -- ============================================================================
      AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != bp.current_firm_crd
      -- ============================================================================
      -- V4.3.2 FIX: Exclude same firm with different CRD (re-registrations)
      -- ============================================================================
      -- Firms sometimes re-register under new CRDs (LLC changes, mergers, etc.)
      -- Uses first-15-chars fuzzy match on cleaned firm names
      -- Validated: 100% accuracy on test cases (James Patton, Robert Kantor)
      -- Impact: ~135 advisors corrected
      -- ============================================================================
      AND NOT (
          LEFT(REGEXP_REPLACE(LOWER(bp.firm_name), r'[^a-z0-9]', ''), 15) 
          = LEFT(REGEXP_REPLACE(LOWER(eh.PREVIOUS_REGISTRATION_COMPANY_NAME), r'[^a-z0-9]', ''), 15)
      )
    GROUP BY bp.crd, bp.prediction_date
    HAVING COUNT(*) >= 2  -- Need 2+ completed jobs to detect pattern
),

-- ============================================================================
-- CAREER CLOCK FEATURES (V4.3.0)
-- ============================================================================
-- Derives the 2 selective features from career clock stats
-- 
-- Logic:
-- - cc_pct_through_cycle = current_tenure / avg_prior_tenure
-- - In_Window: CV < 0.5 AND 70-130% through cycle
-- - Too_Early: CV < 0.5 AND < 70% through cycle
-- ============================================================================
career_clock_features AS (
    SELECT
        cf.crd,
        cf.prediction_date,
        ccs.cc_completed_jobs,
        ccs.cc_avg_prior_tenure_months,
        ccs.cc_tenure_cv,
        
        -- Calculate percent through typical tenure cycle
        SAFE_DIVIDE(cf.tenure_months, ccs.cc_avg_prior_tenure_months) as cc_pct_through_cycle,
        
        -- ================================================================
        -- FEATURE 24: cc_is_in_move_window (PRIMARY SIGNAL)
        -- ================================================================
        -- Advisor has predictable pattern (CV < 0.5) AND is currently
        -- in their typical "move window" (70-130% through their average tenure)
        -- 
        -- Validation: 5.59% conversion within 35-49 age (2.43x vs No_Pattern)
        -- Correlation with age_bucket_encoded: -0.027 (INDEPENDENT)
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
        -- Advisor has predictable pattern (CV < 0.5) BUT is too early
        -- in their cycle (< 70% through their average tenure)
        -- 
        -- Validation: 3.72% conversion (below 3.82% baseline)
        -- Correlation with age_bucket_encoded: -0.035 (INDEPENDENT)
        -- ================================================================
        CASE 
            WHEN ccs.cc_tenure_cv IS NOT NULL 
                 AND ccs.cc_tenure_cv < 0.5 
                 AND SAFE_DIVIDE(cf.tenure_months, ccs.cc_avg_prior_tenure_months) < 0.7
            THEN 1 
            ELSE 0 
        END as cc_is_too_early
        
    FROM current_firm cf
    LEFT JOIN career_clock_stats ccs 
        ON cf.crd = ccs.crd 
        AND cf.prediction_date = ccs.prediction_date
),

-- ============================================================================
-- RECENT PROMOTEE FEATURE (V4.3.1)
-- ============================================================================
-- Analysis (January 8, 2026) found advisors with <5 years industry tenure
-- holding mid/senior titles convert at 0.29-0.45% (0.10-0.16x baseline).
-- 
-- These "recent promotees" likely don't have portable books yet:
-- - Recently promoted from junior roles
-- - Still building client relationships
-- - May not have decision-making authority to move
--
-- Conversion by career stage:
--   LIKELY_RECENT_PROMOTEE (Senior): 0.29% (0.10x lift) - 348 leads
--   LIKELY_RECENT_PROMOTEE (Mid):    0.45% (0.16x lift) - 1,567 leads
--   ESTABLISHED_PRODUCER:            0.73% (0.27x lift) - baseline comparison
--   FOUNDER_OWNER:                   1.07% (0.39x lift) - DO NOT FLAG
-- ============================================================================
recent_promotee_feature AS (
    SELECT
        bp.crd,
        CASE 
            -- Less than 5 years industry tenure (60 months)
            WHEN COALESCE(it.industry_tenure_months, c.INDUSTRY_TENURE_MONTHS, 0) < 60
            -- Has mid-level or senior title (suggests promotion)
            AND (
                UPPER(c.TITLE_NAME) LIKE '%FINANCIAL ADVISOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%WEALTH ADVISOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%INVESTMENT ADVISOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%FINANCIAL PLANNER%'
                OR UPPER(c.TITLE_NAME) LIKE '%PORTFOLIO MANAGER%'
                OR UPPER(c.TITLE_NAME) LIKE '%SENIOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%MANAGING%'
                OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%'
                OR UPPER(c.TITLE_NAME) LIKE '%VP %'
                OR UPPER(c.TITLE_NAME) LIKE '%VICE PRESIDENT%'
            )
            -- Exclude if they're clearly still junior (shouldn't be on list anyway)
            AND NOT (
                UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE%'
                OR UPPER(c.TITLE_NAME) LIKE '%ASSISTANT%'
                OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
                OR UPPER(c.TITLE_NAME) LIKE '%JUNIOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%INTERN%'
                OR UPPER(c.TITLE_NAME) LIKE '%TRAINEE%'
            )
            -- DO NOT flag founders/owners - they convert at 1.07%
            AND NOT (
                UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
                OR UPPER(c.TITLE_NAME) LIKE '%OWNER%'
                OR UPPER(c.TITLE_NAME) LIKE '%CEO%'
                OR UPPER(c.TITLE_NAME) LIKE '% PRESIDENT%'  -- Space before to avoid VP
            )
            THEN 1
            ELSE 0
        END as is_likely_recent_promotee
    FROM base_prospects bp
    LEFT JOIN industry_tenure it ON bp.crd = it.crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON bp.crd = c.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- COMBINE ALL FEATURES (26 features for V4.3.2: 23 from V4.2.0 + 2 Career Clock + 1 Recent Promotee)
-- ============================================================================
all_features AS (
    SELECT
        -- Base columns
        bp.crd,
        bp.firm_crd,
        bp.prediction_date,

        -- GROUP 1: TENURE FEATURES
        COALESCE(cf.tenure_months, 0) as tenure_months,
        CASE
            WHEN cf.tenure_months IS NULL THEN 'Unknown'
            WHEN cf.tenure_months < 12 THEN '0-12'
            WHEN cf.tenure_months < 24 THEN '12-24'
            WHEN cf.tenure_months < 48 THEN '24-48'
            WHEN cf.tenure_months < 120 THEN '48-120'
            ELSE '120+'
        END as tenure_bucket,
        -- Encoded version for model (V4.3.0)
        CASE 
            WHEN COALESCE(cf.tenure_months, 0) = 0 OR cf.tenure_months IS NULL THEN 5
            WHEN cf.tenure_months < 12 THEN 0
            WHEN cf.tenure_months < 24 THEN 1
            WHEN cf.tenure_months < 48 THEN 2
            WHEN cf.tenure_months < 120 THEN 3
            ELSE 4
        END as tenure_bucket_encoded,

        -- GROUP 2: EXPERIENCE FEATURES
        COALESCE(e.experience_years, 0) as experience_years,
        CASE
            WHEN e.experience_years IS NULL OR e.experience_years = 0 THEN 'Unknown'
            WHEN e.experience_years < 5 THEN '0-5'
            WHEN e.experience_years < 10 THEN '5-10'
            WHEN e.experience_years < 15 THEN '10-15'
            WHEN e.experience_years < 20 THEN '15-20'
            ELSE '20+'
        END as experience_bucket,
        e.is_experience_missing,

        -- GROUP 3: MOBILITY FEATURES
        COALESCE(m.mobility_3yr, 0) as mobility_3yr,
        CASE
            WHEN COALESCE(m.mobility_3yr, 0) = 0 THEN 'Stable'
            WHEN COALESCE(m.mobility_3yr, 0) = 1 THEN 'Low_Mobility'
            ELSE 'High_Mobility'
        END as mobility_tier,
        -- Encoded version for model (V4.3.0)
        CASE 
            WHEN COALESCE(m.mobility_3yr, 0) = 0 THEN 0
            WHEN COALESCE(m.mobility_3yr, 0) = 1 THEN 1
            ELSE 2
        END as mobility_tier_encoded,

        -- GROUP 4: FIRM STABILITY FEATURES
        COALESCE(fs.firm_rep_count_at_contact, 0) as firm_rep_count_at_contact,
        -- V3.3.1: Large firm flag for deprioritization (>50 reps = 0.60x baseline)
        CASE WHEN COALESCE(fs.firm_rep_count_at_contact, 0) > 50 THEN 1 ELSE 0 END as is_large_firm,
        COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) as firm_net_change_12mo,
        CASE
            WHEN cf.firm_crd IS NULL THEN 'Unknown'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < -10 THEN 'Heavy_Bleeding'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < 0 THEN 'Light_Bleeding'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) = 0 THEN 'Stable'
            ELSE 'Growing'
        END as firm_stability_tier,
        -- Encoded version for model (V4.3.0)
        CASE 
            WHEN cf.firm_crd IS NULL THEN 0
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < -10 THEN 1
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < 0 THEN 2
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) = 0 THEN 3
            ELSE 4
        END as firm_stability_tier_encoded,
        dq.has_firm_data,

        -- GROUP 5: WIREHOUSE & BROKER PROTOCOL
        COALESCE(w.is_wirehouse, 0) as is_wirehouse,
        COALESCE(bp_protocol.is_broker_protocol, 0) as is_broker_protocol,

        -- GROUP 6: DATA QUALITY FLAGS
        dq.has_email,
        dq.has_linkedin,

        -- ============================================================================
        -- INTERACTION FEATURES
        -- ============================================================================
        CASE
            WHEN COALESCE(m.mobility_3yr, 0) >= 2
                AND (COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0)) < -10
            THEN 1 ELSE 0
        END as mobility_x_heavy_bleeding,

        CASE
            WHEN COALESCE(cf.tenure_months, 9999) < 24 AND COALESCE(m.mobility_3yr, 0) >= 2
            THEN 1 ELSE 0
        END as short_tenure_x_high_mobility,

        -- ====================================================================
        -- NEW V4.1 FEATURES (16-22)
        -- ====================================================================
        
        -- FEATURE 16: is_recent_mover (NEW in V4.1)
        -- Moved firms in last 12 months
        COALESCE(rm.is_recent_mover, 0) as is_recent_mover,
        
        -- FEATURE 17: days_since_last_move (NEW in V4.1)
        -- Days since joining current firm
        COALESCE(rm.days_since_last_move, 9999) as days_since_last_move,
        
        -- FEATURE 18: firm_departures_corrected (NEW in V4.1)
        -- Corrected firm departure count from inferred_departures_analysis
        COALESCE(fbc.firm_departures_corrected, 0) as firm_departures_corrected,
        
        -- FEATURE 19: bleeding_velocity_encoded (NEW in V4.1)
        -- Firm bleeding acceleration: 0=STABLE, 1=DECELERATING, 2=STEADY, 3=ACCELERATING
        COALESCE(bv.bleeding_velocity_encoded, 0) as bleeding_velocity_encoded,
        
        -- FEATURE 20: is_independent_ria (NEW in V4.1)
        -- Independent RIA flag
        COALESCE(frt.is_independent_ria, 0) as is_independent_ria,
        
        -- FEATURE 21: is_ia_rep_type (NEW in V4.1)
        -- Investment Advisor rep type
        COALESCE(frt.is_ia_rep_type, 0) as is_ia_rep_type,
        
        -- FEATURE 22: is_dual_registered (NEW in V4.1)
        -- Both broker-dealer and investment advisor
        COALESCE(frt.is_dual_registered, 0) as is_dual_registered,

        -- V4.2.0: Age feature
        COALESCE(ad.age_bucket_encoded, 2) as age_bucket_encoded,

        -- ================================================================
        -- V4.3.0: CAREER CLOCK FEATURES (2 new features)
        -- ================================================================
        COALESCE(ccf.cc_is_in_move_window, 0) as cc_is_in_move_window,
        COALESCE(ccf.cc_is_too_early, 0) as cc_is_too_early,

        -- ================================================================
        -- V4.3.1: RECENT PROMOTEE FEATURE (1 new feature)
        -- ================================================================
        -- Analysis (January 8, 2026) found advisors with <5yr tenure + mid/senior
        -- titles convert at 0.29-0.45% (6-9x worse than baseline).
        -- This feature lets the model learn the pattern and find exceptions.
        -- ================================================================
        COALESCE(rp.is_likely_recent_promotee, 0) as is_likely_recent_promotee,

        -- Metadata
        CURRENT_TIMESTAMP() as created_at,
        'v4.3.2' as feature_version

    FROM base_prospects bp
    LEFT JOIN current_firm cf ON bp.crd = cf.crd
    LEFT JOIN industry_tenure it ON bp.crd = it.crd
    LEFT JOIN mobility m ON bp.crd = m.crd
    LEFT JOIN firm_stability fs ON bp.crd = fs.crd
    LEFT JOIN wirehouse w ON bp.crd = w.crd
    LEFT JOIN broker_protocol bp_protocol ON bp.crd = bp_protocol.crd
    LEFT JOIN experience e ON bp.crd = e.crd
    LEFT JOIN data_quality dq ON bp.crd = dq.crd
    -- NEW V4.1 JOINs:
    LEFT JOIN recent_mover_features rm ON bp.crd = rm.crd
    LEFT JOIN firm_bleeding_corrected_features fbc ON cf.firm_crd = fbc.firm_crd
    LEFT JOIN bleeding_velocity bv ON cf.firm_crd = bv.firm_crd
    LEFT JOIN firm_rep_type_features frt ON bp.crd = frt.crd
    LEFT JOIN (
        SELECT 
            RIA_CONTACT_CRD_ID as crd,
            CASE 
                WHEN AGE_RANGE IN ('18-24', '25-29', '30-34') THEN 0
                WHEN AGE_RANGE IN ('35-39', '40-44', '45-49') THEN 1
                WHEN AGE_RANGE IN ('50-54', '55-59', '60-64') THEN 2
                WHEN AGE_RANGE IN ('65-69') THEN 3
                WHEN AGE_RANGE IN ('70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 4
                ELSE 2
            END as age_bucket_encoded
        FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    ) ad ON bp.crd = ad.crd
    LEFT JOIN career_clock_features ccf ON bp.crd = ccf.crd AND bp.prediction_date = ccf.prediction_date
    LEFT JOIN recent_promotee_feature rp ON bp.crd = rp.crd
)

SELECT * FROM all_features;

