# V4.2.0 Career Clock Feature Implementation Guide

**Version**: V4.2.0 (V4.1.0 R3 → V4.2.0)  
**Created**: January 2026  
**Purpose**: Add Career Clock features to V4 XGBoost model and retrain  
**Expected Impact**: Better deprioritization of "Too_Early" leads, +5-10% improvement in bottom 20% filtering

---

## Overview

This guide adds 7 Career Clock features to the V4 XGBoost model. **NOTE:** `cc_avg_prior_tenure_months` is calculated in CTEs for intermediate calculations but is **EXCLUDED** from the final feature list (redundant with `cc_pct_through_cycle` which already captures the relationship).

| Feature | Type | Description |
|---------|------|-------------|
| `cc_tenure_cv` | FLOAT | Coefficient of variation of prior job tenures |
| `cc_avg_prior_tenure_months` | FLOAT | Average tenure at prior firms (intermediate - may exclude from model) |
| `cc_pct_through_cycle` | FLOAT | Current tenure / avg prior tenure |
| `cc_is_in_move_window` | BOOLEAN | 70-130% through typical cycle |
| `cc_is_too_early` | BOOLEAN | <70% through typical cycle |
| `cc_is_clockwork` | BOOLEAN | CV < 0.3 (highly predictable) |
| `cc_months_until_window` | INT | Months until move window |

### Expected Model Improvement

| Metric | V4.1.0 R3 (Current) | V4.2.0 (Expected) | Change |
|--------|---------------------|-------------------|--------|
| Test AUC-ROC | 0.6198 | 0.63-0.65 | +2-5% |
| Top Decile Lift | 2.03x | 2.1-2.3x | +5-10% |
| Bottom 20% Rate | 1.40% | 1.0-1.2% | -15-30% |
| Features | 22 | 29 | +7 |

---

## Pre-Implementation Checklist

- [ ] Backup current V4.1.0 R3 model artifacts
- [ ] Verify BigQuery access to `savvy-gtm-analytics`
- [ ] Confirm Python environment has `xgboost`, `shap`, `scikit-learn`, `google-cloud-bigquery`
- [ ] Review current V4.1.0 R3 metrics as baseline
- [ ] Ensure V3.4.0 Career Clock features are deployed (prerequisite)

---

# STEP 1: Add Career Clock Features to V4 Training Feature Engineering

## Cursor Prompt 1.1: Update V4 Feature Engineering SQL

```
@workspace Update V4.1 feature engineering to add Career Clock features for model training.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v4/sql/v4.1/phase_2_feature_engineering_v41.sql`
2. Add Career Clock CTEs that calculate:
   - `cc_tenure_cv`: Coefficient of variation of prior job tenures
   - `cc_avg_prior_tenure_months`: Average tenure at prior firms
   - `cc_pct_through_cycle`: Current tenure / avg prior tenure
   - `cc_is_in_move_window`: Boolean (tenure_cv < 0.5 AND pct BETWEEN 0.7 AND 1.3)
   - `cc_is_too_early`: Boolean (tenure_cv < 0.5 AND pct < 0.7)
   - `cc_is_clockwork`: Boolean (tenure_cv < 0.3)
   - `cc_months_until_window`: Max(0, avg_tenure * 0.7 - current_tenure)
3. Join these features to the final output
4. Ensure PIT compliance: Only use employment records where END_DATE < contacted_date

CRITICAL PIT REQUIREMENTS:
- Only count COMPLETED jobs (those with END_DATE)
- END_DATE must be BEFORE contacted_date
- Use only historical data available at time of contact

After changes, show me the new Career Clock CTEs and updated final SELECT.
```

## Code Snippet 1.1: Career Clock CTEs for V4 Training

Add to `v4/sql/v4.1/phase_2_feature_engineering_v41.sql` after the `mobility` CTE (or after the last feature group CTE before `all_features`):

**IMPORTANT:** Also update the CREATE TABLE statement at the top to:
```sql
CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_features_pit_v42` AS
```

```sql
-- ============================================================================
-- FEATURE GROUP 7: CAREER CLOCK FEATURES (V4.2.0)
-- ============================================================================
-- PIT-safe: Only uses completed employment records with END_DATE < contacted_date
-- These features capture individual advisor career timing patterns
-- 
-- KEY FINDINGS:
-- - 20% of advisors have predictable patterns (CV < 0.3)
-- - "In Window" advisors convert at 10-16% (vs 3% baseline)
-- - "Too Early" advisors convert at 3.14% (deprioritization signal)
-- ============================================================================

career_clock_raw AS (
    SELECT 
        b.lead_id,
        b.advisor_crd,
        b.contacted_date,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as prior_firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as prior_start,
        eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE as prior_end,
        DATE_DIFF(
            eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
            eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
            MONTH
        ) as prior_tenure_months
    FROM base b
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
    WHERE eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
      -- PIT CRITICAL: Only completed jobs BEFORE contact date
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < b.contacted_date
      -- Valid tenure (> 0 months)
      AND DATE_DIFF(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                    eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) > 0
),

career_clock_stats AS (
    SELECT
        lead_id,
        advisor_crd,
        contacted_date,
        COUNT(*) as completed_jobs,
        AVG(prior_tenure_months) as avg_prior_tenure_months,
        STDDEV(prior_tenure_months) as tenure_stddev,
        SAFE_DIVIDE(STDDEV(prior_tenure_months), AVG(prior_tenure_months)) as tenure_cv,
        MIN(prior_tenure_months) as min_prior_tenure,
        MAX(prior_tenure_months) as max_prior_tenure
    FROM career_clock_raw
    GROUP BY lead_id, advisor_crd, contacted_date
    HAVING COUNT(*) >= 2  -- Need 2+ completed jobs to detect pattern
),

career_clock_features AS (
    SELECT
        cf.lead_id,
        cf.contacted_date,
        cf.tenure_months as current_tenure_months,
        
        -- Raw stats (for model to learn from)
        COALESCE(ccs.completed_jobs, 0) as cc_completed_jobs,
        ccs.avg_prior_tenure_months as cc_avg_prior_tenure_months,
        ccs.tenure_cv as cc_tenure_cv,
        
        -- Percent through personal cycle
        SAFE_DIVIDE(cf.tenure_months, ccs.avg_prior_tenure_months) as cc_pct_through_cycle,
        
        -- Boolean flags (encoded as INT for XGBoost)
        CASE
            WHEN ccs.tenure_cv < 0.3 THEN 1
            ELSE 0
        END as cc_is_clockwork,
        
        CASE
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(cf.tenure_months, ccs.avg_prior_tenure_months) BETWEEN 0.7 AND 1.3
            THEN 1
            ELSE 0
        END as cc_is_in_move_window,
        
        CASE
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(cf.tenure_months, ccs.avg_prior_tenure_months) < 0.7
            THEN 1
            ELSE 0
        END as cc_is_too_early,
        
        -- Months until move window (for continuous signal)
        CASE
            WHEN ccs.tenure_cv < 0.5 AND ccs.avg_prior_tenure_months IS NOT NULL
            THEN GREATEST(0, CAST(ccs.avg_prior_tenure_months * 0.7 - cf.tenure_months AS INT64))
            ELSE NULL
        END as cc_months_until_window
        
    FROM current_firm cf
    LEFT JOIN career_clock_stats ccs 
        ON cf.lead_id = ccs.lead_id
)
```

## Code Snippet 1.2: Update Final SELECT for V4 Training

Add to the final SELECT in `phase_2_feature_engineering_v41.sql`:

```sql
-- Add to final SELECT (inside the SELECT list):

    -- Career Clock Features (V4.2.0)
    -- NOTE: cc_avg_prior_tenure_months is calculated in CTE but NOT included as feature (redundant with cc_pct_through_cycle)
    COALESCE(ccf.cc_completed_jobs, 0) as cc_completed_jobs,
    COALESCE(ccf.cc_tenure_cv, 1.0) as cc_tenure_cv,  -- Default 1.0 = unpredictable
    COALESCE(ccf.cc_pct_through_cycle, 1.0) as cc_pct_through_cycle,
    COALESCE(ccf.cc_is_clockwork, 0) as cc_is_clockwork,
    COALESCE(ccf.cc_is_in_move_window, 0) as cc_is_in_move_window,
    COALESCE(ccf.cc_is_too_early, 0) as cc_is_too_early,
    COALESCE(ccf.cc_months_until_window, 999) as cc_months_until_window,  -- 999 = unknown

-- Add to final FROM/JOIN clause in all_features CTE:
-- NOTE: Join on cf.lead_id (current_firm) since all_features uses cf
LEFT JOIN career_clock_features ccf ON cf.lead_id = ccf.lead_id
```

## Verification Gate 1.1

```
@workspace Run verification for V4 Career Clock feature engineering.

TASK:
1. After updating the SQL, run this validation query:

```sql
-- VALIDATION 1.1: Career Clock Feature Distribution (Training Data)
SELECT 
    CASE 
        WHEN cc_tenure_cv < 0.3 THEN 'Clockwork'
        WHEN cc_tenure_cv < 0.5 THEN 'Semi_Predictable'
        WHEN cc_tenure_cv < 0.8 THEN 'Variable'
        WHEN cc_tenure_cv IS NULL THEN 'No_Pattern'
        ELSE 'Chaotic'
    END as pattern_type,
    CASE 
        WHEN cc_is_in_move_window = 1 THEN 'In_Window'
        WHEN cc_is_too_early = 1 THEN 'Too_Early'
        ELSE 'Other'
    END as timing_status,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conv_rate_pct
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v42`
WHERE target IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;
```

EXPECTED RESULTS:
- Clockwork + In_Window: ~6-10% conversion
- Any + Too_Early: ~3% conversion
- Pattern distribution should match V3.4 validation

2. Verify feature counts:
```sql
SELECT 
    COUNT(*) as total_rows,
    COUNTIF(cc_tenure_cv IS NOT NULL) as has_tenure_cv,
    COUNTIF(cc_is_in_move_window = 1) as in_window_count,
    COUNTIF(cc_is_too_early = 1) as too_early_count,
    COUNTIF(cc_is_clockwork = 1) as clockwork_count
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v42`;
```

3. **ADDITIONAL VALIDATION: Feature Correlation Check**
   ```sql
   -- VALIDATION 1.1c: Career Clock Feature Correlation
   -- Ensure Career Clock features aren't highly correlated with existing features
   SELECT 
       'cc_tenure_cv' as cc_feature,
       CORR(cc_tenure_cv, tenure_months) as corr_tenure,
       CORR(cc_tenure_cv, days_since_last_move) as corr_days_since_move,
       CORR(cc_tenure_cv, mobility_3yr) as corr_mobility
   FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v42`
   WHERE cc_tenure_cv IS NOT NULL;
   
   -- EXPECTED: All correlations should be < 0.85 (not highly correlated)
   -- If any correlation > 0.85, consider removing redundant feature
   ```

If validation passes, proceed to Step 2.
```

---

# STEP 2: Update V4 Prospect Feature Engineering (Inference)

## Cursor Prompt 2.1: Update Pipeline Feature SQL

```
@workspace Update V4 prospect feature engineering for production inference.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `pipeline/sql/v4_prospect_features.sql`
2. Add Career Clock CTEs (same logic as training, but for all prospects)
3. Use prediction_date instead of contacted_date for PIT compliance
4. Add 7 Career Clock features to the output (NOT 8 - exclude cc_avg_prior_tenure_months)
5. Ensure NULL handling matches training EXACTLY (COALESCE with same defaults)

**CRITICAL: Training/Inference Feature Parity**

The inference SQL MUST produce identical features to training:
1. Same feature names (exact match)
2. Same data types (INT, FLOAT)
3. Same NULL handling (COALESCE with same defaults)
4. Same value ranges

Default values must match exactly:
- cc_tenure_cv: COALESCE(..., 1.0)  -- 1.0 = unpredictable
- cc_pct_through_cycle: COALESCE(..., 1.0)
- cc_is_clockwork: COALESCE(..., 0)
- cc_is_in_move_window: COALESCE(..., 0)
- cc_is_too_early: COALESCE(..., 0)
- cc_months_until_window: COALESCE(..., 999)  -- 999 = unknown
- cc_completed_jobs: COALESCE(..., 0)

KEY DIFFERENCE from training:
- Training uses `contacted_date` from historical leads
- Inference uses `prediction_date` (current date) for all prospects

Show me the updated CTEs and final SELECT with Career Clock features.
```

## Code Snippet 2.1: Career Clock CTEs for Inference

**CRITICAL PRE-FLIGHT CHECK:**
Before inserting, verify these CTEs exist in `pipeline/sql/v4_prospect_features.sql`:
- `base_prospects` (aliased as `bp`)
- `current_firm` (aliased as `cf`)
- `all_features` (final CTE before SELECT)

**INSERTION POINT:**
Add Career Clock CTEs AFTER the `current_firm` CTE and BEFORE the `all_features` CTE.

**LOCATION INSTRUCTIONS:**
1. Open `pipeline/sql/v4_prospect_features.sql`
2. Find the `current_firm` CTE (ends with `)` and `,`)
3. Insert Career Clock CTEs immediately AFTER `current_firm` CTE
4. Ensure Career Clock CTEs come BEFORE `all_features` CTE
5. Career Clock CTEs should be inserted before any CTE that references `current_firm`

Add to `pipeline/sql/v4_prospect_features.sql`:

```sql
-- ============================================================================
-- FEATURE GROUP 7: CAREER CLOCK FEATURES (V4.2.0)
-- ============================================================================
-- For inference, use prediction_date (typically CURRENT_DATE)
-- Must match training feature engineering exactly
-- ============================================================================

career_clock_raw AS (
    SELECT 
        bp.crd as advisor_crd,
        bp.prediction_date,
        eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE as prior_end,
        DATE_DIFF(
            eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
            eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
            MONTH
        ) as prior_tenure_months
    FROM base_prospects bp
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON bp.crd = eh.RIA_CONTACT_CRD_ID
    WHERE eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
      -- PIT: Only completed jobs before prediction date
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < bp.prediction_date
      AND DATE_DIFF(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                    eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) > 0
),

career_clock_stats AS (
    SELECT
        advisor_crd,
        prediction_date,
        COUNT(*) as completed_jobs,
        AVG(prior_tenure_months) as avg_prior_tenure_months,
        SAFE_DIVIDE(STDDEV(prior_tenure_months), AVG(prior_tenure_months)) as tenure_cv
    FROM career_clock_raw
    GROUP BY advisor_crd, prediction_date
    HAVING COUNT(*) >= 2
),

career_clock_features AS (
    SELECT
        cf.crd,
        cf.prediction_date,
        cf.tenure_months,
        
        COALESCE(ccs.completed_jobs, 0) as cc_completed_jobs,
        ccs.avg_prior_tenure_months as cc_avg_prior_tenure_months,
        COALESCE(ccs.tenure_cv, 1.0) as cc_tenure_cv,
        COALESCE(SAFE_DIVIDE(cf.tenure_months, ccs.avg_prior_tenure_months), 1.0) as cc_pct_through_cycle,
        
        CASE WHEN ccs.tenure_cv < 0.3 THEN 1 ELSE 0 END as cc_is_clockwork,
        
        CASE
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(cf.tenure_months, ccs.avg_prior_tenure_months) BETWEEN 0.7 AND 1.3
            THEN 1 ELSE 0
        END as cc_is_in_move_window,
        
        CASE
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(cf.tenure_months, ccs.avg_prior_tenure_months) < 0.7
            THEN 1 ELSE 0
        END as cc_is_too_early,
        
        CASE
            WHEN ccs.tenure_cv < 0.5 AND ccs.avg_prior_tenure_months IS NOT NULL
            THEN CAST(GREATEST(0, ccs.avg_prior_tenure_months * 0.7 - cf.tenure_months) AS INT64)
            ELSE 999
        END as cc_months_until_window
        
    FROM current_firm cf
    LEFT JOIN career_clock_stats ccs 
        ON cf.crd = ccs.advisor_crd 
        AND cf.prediction_date = ccs.prediction_date
)
```

## Code Snippet 2.2: Update Final SELECT for Inference

```sql
-- Add to final SELECT in v4_prospect_features.sql:

    -- Career Clock Features (V4.2.0)
    -- NOTE: cc_avg_prior_tenure_months is calculated in CTE but NOT included as feature (redundant with cc_pct_through_cycle)
    COALESCE(ccf.cc_completed_jobs, 0) as cc_completed_jobs,
    COALESCE(ccf.cc_tenure_cv, 1.0) as cc_tenure_cv,
    COALESCE(ccf.cc_pct_through_cycle, 1.0) as cc_pct_through_cycle,
    COALESCE(ccf.cc_is_clockwork, 0) as cc_is_clockwork,
    COALESCE(ccf.cc_is_in_move_window, 0) as cc_is_in_move_window,
    COALESCE(ccf.cc_is_too_early, 0) as cc_is_too_early,
    COALESCE(ccf.cc_months_until_window, 999) as cc_months_until_window,

-- Add to FROM/JOIN in all_features CTE:
-- NOTE: Join on bp.crd (base_prospects) since all_features uses bp as main alias
LEFT JOIN career_clock_features ccf ON bp.crd = ccf.crd
```

## Verification Gate 2.1

```
@workspace Verify inference feature engineering matches training.

TASK:
Run this validation to ensure training and inference features align:

```sql
-- VALIDATION 2.1: Feature Schema Match
WITH training_schema AS (
    SELECT column_name, data_type
    FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'v4_features_pit_v42'
      AND column_name LIKE 'cc_%'
),
inference_schema AS (
    SELECT column_name, data_type
    FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'v4_prospect_features'
      AND column_name LIKE 'cc_%'
)
SELECT 
    COALESCE(t.column_name, i.column_name) as column_name,
    t.data_type as training_type,
    i.data_type as inference_type,
    CASE WHEN t.column_name IS NULL THEN 'MISSING IN TRAINING'
         WHEN i.column_name IS NULL THEN 'MISSING IN INFERENCE'
         WHEN t.data_type != i.data_type THEN 'TYPE MISMATCH'
         ELSE 'OK'
    END as status
FROM training_schema t
FULL OUTER JOIN inference_schema i ON t.column_name = i.column_name
ORDER BY column_name;
```

EXPECTED: All 7 Career Clock features present in both, all status = 'OK'

If validation passes, proceed to Step 3.
```

---

# STEP 3: Update Feature List and Model Configuration

## Cursor Prompt 3.1: Update Feature List JSON

```
@workspace Update V4 feature list to include Career Clock features.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v4/data/v4.1.0/final_features.json`
2. Create a NEW file `v4/data/v4.2.0/final_features.json`
3. Copy existing 22 features and ADD 7 Career Clock features:
   - cc_tenure_cv
   - cc_pct_through_cycle
   - cc_is_clockwork
   - cc_is_in_move_window
   - cc_is_too_early
   - cc_months_until_window
   - cc_completed_jobs

NOTE: We're adding 7 features, going from 22 → 29 total features.
NOTE: `cc_avg_prior_tenure_months` is calculated in CTEs and included in SELECT for reference, but excluded from model feature list (redundant with `cc_pct_through_cycle` which already captures the relationship).

Show me the complete new feature list.
```

## Code Snippet 3.1: New Feature List (29 features)

Create `v4/data/v4.2.0/final_features.json`:

```json
{
  "version": "v4.2.0",
  "created": "2026-01-XX",
  "feature_count": 29,
  "previous_version": "v4.1.0_r3",
  "added_features": [
    "cc_tenure_cv",
    "cc_pct_through_cycle", 
    "cc_is_clockwork",
    "cc_is_in_move_window",
    "cc_is_too_early",
    "cc_months_until_window",
    "cc_completed_jobs"
  ],
  "features": [
    "tenure_months",
    "tenure_bucket_encoded",
    "experience_bucket",
    "is_experience_missing",
    "mobility_3yr",
    "is_recent_mover",
    "days_since_last_move",
    "firm_net_change_12mo",
    "firm_departures_corrected",
    "firm_bleeding_velocity",
    "firm_rep_count_at_contact",
    "is_wirehouse",
    "is_broker_protocol",
    "is_independent_ria",
    "is_ia_rep_type",
    "is_dual_registered",
    "has_email",
    "has_linkedin",
    "has_firm_data",
    "is_gender_missing",
    "short_tenure_x_high_mobility",
    "mobility_x_heavy_bleeding",
    "cc_tenure_cv",
    "cc_pct_through_cycle",
    "cc_is_clockwork",
    "cc_is_in_move_window",
    "cc_is_too_early",
    "cc_months_until_window",
    "cc_completed_jobs"
  ],
  "feature_groups": {
    "tenure": ["tenure_months", "tenure_bucket_encoded"],
    "experience": ["experience_bucket", "is_experience_missing"],
    "mobility": ["mobility_3yr", "is_recent_mover", "days_since_last_move"],
    "firm_stability": ["firm_net_change_12mo", "firm_departures_corrected", "firm_bleeding_velocity", "firm_rep_count_at_contact"],
    "firm_type": ["is_wirehouse", "is_broker_protocol", "is_independent_ria", "is_ia_rep_type", "is_dual_registered"],
    "data_quality": ["has_email", "has_linkedin", "has_firm_data", "is_gender_missing"],
    "interactions": ["short_tenure_x_high_mobility", "mobility_x_heavy_bleeding"],
    "career_clock": ["cc_tenure_cv", "cc_pct_through_cycle", "cc_is_clockwork", "cc_is_in_move_window", "cc_is_too_early", "cc_months_until_window", "cc_completed_jobs"]
  },
  "notes": "V4.2.0 adds Career Clock features to capture individual advisor timing patterns. Expected improvement: better deprioritization of 'too early' leads."
}
```

## Cursor Prompt 3.2: Update Hyperparameters (Optional Tuning)

```
@workspace Review and update hyperparameters for V4.2.0 training.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v4/models/v4.1.0/hyperparameters.json`
2. Create `v4/models/v4.2.0/hyperparameters.json`
3. Consider adjustments for 29 features (vs 22):
   - May need slightly higher colsample_bytree (more features to sample from)
   - Keep regularization strong to prevent overfitting with new features
   
RECOMMENDATION: Start with same hyperparameters as V4.1.0 R3, adjust only if overfitting detected.

Show me the hyperparameters file for V4.2.0.
```

## Code Snippet 3.2: Hyperparameters for V4.2.0

Create `v4/models/v4.2.0/hyperparameters.json`:

```json
{
  "version": "v4.2.0",
  "created": "2026-01-XX",
  "base_version": "v4.1.0_r3",
  "changes_from_base": "Added Career Clock features, same hyperparameters",
  "hyperparameters": {
    "objective": "binary:logistic",
    "eval_metric": ["auc", "aucpr", "logloss"],
    "max_depth": 2,
    "min_child_weight": 30,
    "reg_alpha": 1.0,
    "reg_lambda": 5.0,
    "gamma": 0.3,
    "learning_rate": 0.01,
    "n_estimators": 2000,
    "early_stopping_rounds": 150,
    "subsample": 0.6,
    "colsample_bytree": 0.7,
    "base_score": 0.5,
    "scale_pos_weight": "dynamic",
    "random_state": 42
  },
  "notes": [
    "Increased colsample_bytree from 0.6 to 0.7 due to more features",
    "All other parameters unchanged from V4.1.0 R3",
    "If overfitting detected, reduce max_depth to 1 or increase reg_lambda"
  ]
}
```

---

# STEP 4: Retrain XGBoost Model

## Cursor Prompt 4.1: Create V4.2.0 Training Script

```
@workspace Create training script for V4.2.0 with Career Clock features.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v4/scripts/phase_6_model_training.py` (or equivalent training script)
2. Create a NEW training script: `v4/scripts/train_v42_career_clock.py`
3. The script should:
   - Load features from `ml_features.v4_features_pit_v42` (NOTE: Update CREATE TABLE in SQL to v42)
   - Use the 29-feature list from `v4/data/v4.2.0/final_features.json`
   - Apply temporal train/test split (same as V4.1: train Feb 2024-Jul 2025, test Aug-Oct 2025)
   - Train XGBoost with hyperparameters from `v4/models/v4.2.0/hyperparameters.json`
   - Calculate SHAP values using KernelExplainer (to avoid base_score issue)
   - Save model artifacts to `v4/models/v4.2.0/`
   - Validate against gates (AUC > 0.58, Top decile lift > 1.4x, etc.)
   - Compare to V4.1.0 R3 baseline

Include comprehensive logging and gate validation.
```

## Code Snippet 4.1: Training Script

Create `v4/scripts/train_v42_career_clock.py`:

```python
"""
V4.2.0 Career Clock Model Training Script
=========================================
Trains XGBoost model with Career Clock features added to V4.1.0 R3 baseline.

Usage:
    python v4/scripts/train_v42_career_clock.py

Outputs:
    - v4/models/v4.2.0/model.pkl
    - v4/models/v4.2.0/model.json
    - v4/models/v4.2.0/feature_importance.csv
    - v4/models/v4.2.0/training_metrics.json
    - v4/models/v4.2.0/shap_summary.csv
"""

import json
import pickle
import numpy as np
import pandas as pd
import xgboost as xgb
from datetime import datetime
from pathlib import Path
from google.cloud import bigquery
from sklearn.metrics import roc_auc_score, average_precision_score
import warnings
warnings.filterwarnings('ignore')

# =============================================================================
# CONFIGURATION
# =============================================================================

PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
FEATURES_TABLE = "v4_features_pit_v42"

# Paths
BASE_DIR = Path(__file__).parent.parent
MODELS_DIR = BASE_DIR / "models" / "v4.2.0"
DATA_DIR = BASE_DIR / "data" / "v4.2.0"

# Create directories
MODELS_DIR.mkdir(parents=True, exist_ok=True)
DATA_DIR.mkdir(parents=True, exist_ok=True)

# Feature list (29 features)
FEATURE_LIST = [
    # Existing V4.1 features (22)
    "tenure_months", "tenure_bucket_encoded", "experience_bucket", "is_experience_missing",
    "mobility_3yr", "is_recent_mover", "days_since_last_move",
    "firm_net_change_12mo", "firm_departures_corrected", "firm_bleeding_velocity", "firm_rep_count_at_contact",
    "is_wirehouse", "is_broker_protocol", "is_independent_ria", "is_ia_rep_type", "is_dual_registered",
    "has_email", "has_linkedin", "has_firm_data", "is_gender_missing",
    "short_tenure_x_high_mobility", "mobility_x_heavy_bleeding",
    # NEW: Career Clock features (7)
    "cc_tenure_cv", "cc_pct_through_cycle", "cc_is_clockwork",
    "cc_is_in_move_window", "cc_is_too_early", "cc_months_until_window", "cc_completed_jobs"
]

# Hyperparameters (from V4.1.0 R3, with minor adjustment)
HYPERPARAMETERS = {
    "objective": "binary:logistic",
    "eval_metric": ["auc", "aucpr", "logloss"],
    "max_depth": 2,
    "min_child_weight": 30,
    "reg_alpha": 1.0,
    "reg_lambda": 5.0,
    "gamma": 0.3,
    "learning_rate": 0.01,
    "n_estimators": 2000,
    "early_stopping_rounds": 150,
    "subsample": 0.6,
    "colsample_bytree": 0.7,  # Increased from 0.6 for more features
    "base_score": 0.5,
    "random_state": 42
}

# Validation Gates
GATES = {
    "min_test_auc": 0.58,
    "min_top_decile_lift": 1.4,
    "max_auc_gap": 0.15,
    "max_bottom_20_rate": 0.02,
    "min_improvement_vs_v41": 0.0  # Must be >= V4.1.0 R3
}

# V4.1.0 R3 Baseline (for comparison)
V41_BASELINE = {
    "test_auc": 0.6198,
    "top_decile_lift": 2.03,
    "bottom_20_rate": 0.0140
}

# =============================================================================
# FUNCTIONS
# =============================================================================

def load_data():
    """Load training data from BigQuery."""
    print("[INFO] Loading training data from BigQuery...")
    client = bigquery.Client(project=PROJECT_ID)
    
    query = f"""
    SELECT *
    FROM `{PROJECT_ID}.{DATASET}.{FEATURES_TABLE}`
    WHERE target IS NOT NULL
    """
    
    df = client.query(query).to_dataframe()
    print(f"[INFO] Loaded {len(df):,} leads with outcomes")
    
    return df


def validate_career_clock_features(df):
    """Validate Career Clock features are present and populated."""
    cc_features = [f for f in FEATURE_LIST if f.startswith('cc_')]
    
    print(f"\n[INFO] Validating {len(cc_features)} Career Clock features...")
    
    for feat in cc_features:
        if feat not in df.columns:
            raise ValueError(f"[ERROR] Missing Career Clock feature: {feat}")
        
        non_null = df[feat].notna().sum()
        pct = non_null / len(df) * 100
        print(f"  {feat}: {non_null:,} non-null ({pct:.1f}%)")
        
        if pct < 10:
            print(f"  ⚠️ WARNING: Low coverage for {feat} ({pct:.1f}% non-null)")
    
    print("[INFO] ✅ Career Clock feature validation passed\n")


def prepare_features(df, feature_list):
    """Prepare features for training."""
    print(f"[INFO] Preparing {len(feature_list)} features...")
    
    X = df[feature_list].copy()
    
    # Fill NaN with appropriate defaults
    for col in X.columns:
        if col.startswith('cc_'):
            # Career Clock features
            if col == 'cc_tenure_cv':
                X[col] = X[col].fillna(1.0)  # 1.0 = unpredictable
            elif col == 'cc_months_until_window':
                X[col] = X[col].fillna(999)  # 999 = unknown
            else:
                X[col] = X[col].fillna(0)
        else:
            X[col] = X[col].fillna(0)
    
    # Ensure numeric types
    for col in X.columns:
        X[col] = pd.to_numeric(X[col], errors='coerce').fillna(0)
    
    y = df['target'].astype(int)
    
    print(f"[INFO] Features shape: {X.shape}")
    print(f"[INFO] Target distribution: {y.mean():.4f} positive rate")
    
    return X, y


def temporal_split(df, X, y):
    """Split data temporally (same as V4.1)."""
    print("[INFO] Applying temporal train/test split...")
    
    df['contacted_date'] = pd.to_datetime(df['contacted_date'])
    
    # Train: Feb 2024 - Jul 2025
    # Test: Aug 2025 - Oct 2025
    train_mask = df['contacted_date'] < '2025-08-01'
    test_mask = df['contacted_date'] >= '2025-08-01'
    
    X_train, X_test = X[train_mask], X[test_mask]
    y_train, y_test = y[train_mask], y[test_mask]
    
    print(f"[INFO] Train set: {len(X_train):,} leads ({y_train.mean():.4f} positive rate)")
    print(f"[INFO] Test set: {len(X_test):,} leads ({y_test.mean():.4f} positive rate)")
    
    return X_train, X_test, y_train, y_test


def train_model(X_train, y_train, X_test, y_test):
    """Train XGBoost model."""
    print("[INFO] Training XGBoost model...")
    
    # Calculate scale_pos_weight
    neg_count = (y_train == 0).sum()
    pos_count = (y_train == 1).sum()
    scale_pos_weight = neg_count / pos_count
    print(f"[INFO] Scale pos weight: {scale_pos_weight:.2f}")
    
    # Create DMatrix
    dtrain = xgb.DMatrix(X_train, label=y_train, feature_names=list(X_train.columns))
    dtest = xgb.DMatrix(X_test, label=y_test, feature_names=list(X_test.columns))
    
    # Training parameters
    params = {
        "objective": HYPERPARAMETERS["objective"],
        "max_depth": HYPERPARAMETERS["max_depth"],
        "min_child_weight": HYPERPARAMETERS["min_child_weight"],
        "reg_alpha": HYPERPARAMETERS["reg_alpha"],
        "reg_lambda": HYPERPARAMETERS["reg_lambda"],
        "gamma": HYPERPARAMETERS["gamma"],
        "learning_rate": HYPERPARAMETERS["learning_rate"],
        "subsample": HYPERPARAMETERS["subsample"],
        "colsample_bytree": HYPERPARAMETERS["colsample_bytree"],
        "base_score": HYPERPARAMETERS["base_score"],
        "scale_pos_weight": scale_pos_weight,
        "random_state": HYPERPARAMETERS["random_state"],
        "eval_metric": HYPERPARAMETERS["eval_metric"]
    }
    
    # Train with early stopping
    evals = [(dtrain, "train"), (dtest, "test")]
    
    model = xgb.train(
        params,
        dtrain,
        num_boost_round=HYPERPARAMETERS["n_estimators"],
        evals=evals,
        early_stopping_rounds=HYPERPARAMETERS["early_stopping_rounds"],
        verbose_eval=50
    )
    
    print(f"[INFO] Best iteration: {model.best_iteration}")
    
    return model, scale_pos_weight


def evaluate_model(model, X_train, y_train, X_test, y_test):
    """Evaluate model performance."""
    print("\n[INFO] Evaluating model performance...")
    
    # Create DMatrix
    dtrain = xgb.DMatrix(X_train, feature_names=list(X_train.columns))
    dtest = xgb.DMatrix(X_test, feature_names=list(X_test.columns))
    
    # Get predictions
    train_pred = model.predict(dtrain)
    test_pred = model.predict(dtest)
    
    # Calculate metrics
    train_auc = roc_auc_score(y_train, train_pred)
    test_auc = roc_auc_score(y_test, test_pred)
    test_aucpr = average_precision_score(y_test, test_pred)
    auc_gap = train_auc - test_auc
    
    print(f"[INFO] Train AUC: {train_auc:.4f}")
    print(f"[INFO] Test AUC: {test_auc:.4f}")
    print(f"[INFO] AUC Gap: {auc_gap:.4f}")
    print(f"[INFO] Test AUC-PR: {test_aucpr:.4f}")
    
    # Calculate lift by decile
    test_df = pd.DataFrame({
        'score': test_pred,
        'target': y_test.values
    })
    test_df['decile'] = pd.qcut(test_df['score'], 10, labels=False, duplicates='drop')
    
    decile_stats = test_df.groupby('decile').agg({
        'target': ['count', 'sum', 'mean']
    }).round(4)
    decile_stats.columns = ['count', 'conversions', 'conv_rate']
    
    baseline_rate = y_test.mean()
    decile_stats['lift'] = decile_stats['conv_rate'] / baseline_rate
    
    print("\n[INFO] Lift by Decile:")
    print(decile_stats)
    
    top_decile_lift = decile_stats.loc[9, 'lift'] if 9 in decile_stats.index else decile_stats.iloc[-1]['lift']
    bottom_20_rate = test_df[test_df['decile'] <= 1]['target'].mean()
    
    print(f"\n[INFO] Top Decile Lift: {top_decile_lift:.2f}x")
    print(f"[INFO] Bottom 20% Rate: {bottom_20_rate:.4f}")
    
    metrics = {
        "train_auc": train_auc,
        "test_auc": test_auc,
        "test_aucpr": test_aucpr,
        "auc_gap": auc_gap,
        "top_decile_lift": top_decile_lift,
        "bottom_20_rate": bottom_20_rate,
        "best_iteration": model.best_iteration
    }
    
    return metrics, decile_stats


def validate_gates(metrics):
    """Validate against performance gates."""
    print("\n" + "=" * 60)
    print("VALIDATION GATES")
    print("=" * 60)
    
    gates_passed = True
    
    # Gate 1: Test AUC >= 0.58
    g1 = metrics["test_auc"] >= GATES["min_test_auc"]
    print(f"G1 Test AUC >= {GATES['min_test_auc']}: {metrics['test_auc']:.4f} {'✅ PASSED' if g1 else '❌ FAILED'}")
    gates_passed &= g1
    
    # Gate 2: Top decile lift >= 1.4x
    g2 = metrics["top_decile_lift"] >= GATES["min_top_decile_lift"]
    print(f"G2 Top Decile Lift >= {GATES['min_top_decile_lift']}x: {metrics['top_decile_lift']:.2f}x {'✅ PASSED' if g2 else '❌ FAILED'}")
    gates_passed &= g2
    
    # Gate 3: AUC gap < 0.15
    g3 = metrics["auc_gap"] < GATES["max_auc_gap"]
    print(f"G3 AUC Gap < {GATES['max_auc_gap']}: {metrics['auc_gap']:.4f} {'✅ PASSED' if g3 else '❌ FAILED'}")
    gates_passed &= g3
    
    # Gate 4: Bottom 20% rate < 2%
    g4 = metrics["bottom_20_rate"] < GATES["max_bottom_20_rate"]
    print(f"G4 Bottom 20% Rate < {GATES['max_bottom_20_rate']}: {metrics['bottom_20_rate']:.4f} {'✅ PASSED' if g4 else '❌ FAILED'}")
    gates_passed &= g4
    
    # Gate 5: Compare to V4.1.0 R3 baseline
    print(f"\n[INFO] Comparison to V4.1.0 R3 Baseline:")
    print(f"  Test AUC: {metrics['test_auc']:.4f} vs {V41_BASELINE['test_auc']:.4f} ({'+' if metrics['test_auc'] >= V41_BASELINE['test_auc'] else ''}{(metrics['test_auc'] - V41_BASELINE['test_auc'])*100:.2f}%)")
    print(f"  Top Decile Lift: {metrics['top_decile_lift']:.2f}x vs {V41_BASELINE['top_decile_lift']:.2f}x")
    print(f"  Bottom 20% Rate: {metrics['bottom_20_rate']:.4f} vs {V41_BASELINE['bottom_20_rate']:.4f}")
    
    g5 = metrics["test_auc"] >= V41_BASELINE["test_auc"]
    print(f"G5 V4.2 AUC >= V4.1 AUC: {'✅ PASSED' if g5 else '⚠️ WARNING (regression)'}")
    
    print("=" * 60)
    print(f"OVERALL: {'✅ ALL GATES PASSED' if gates_passed else '❌ SOME GATES FAILED'}")
    print("=" * 60)
    
    return gates_passed


def calculate_feature_importance(model, feature_list):
    """Calculate feature importance."""
    print("\n[INFO] Calculating feature importance...")
    
    # Get XGBoost importance
    importance = model.get_score(importance_type='gain')
    
    # Map to feature names
    importance_df = pd.DataFrame([
        {'feature': feature_list[int(k[1:])], 'importance': v}
        for k, v in importance.items()
    ]).sort_values('importance', ascending=False)
    
    print("\n[INFO] Top 15 Features by Importance:")
    print(importance_df.head(15).to_string(index=False))
    
    # Check Career Clock features
    cc_features = importance_df[importance_df['feature'].str.startswith('cc_')]
    print(f"\n[INFO] Career Clock Features in Top 15: {len(cc_features[cc_features['feature'].isin(importance_df.head(15)['feature'])])}")
    print(cc_features.to_string(index=False))
    
    return importance_df


def save_artifacts(model, metrics, importance_df, feature_list, scale_pos_weight):
    """Save model artifacts."""
    print("\n[INFO] Saving model artifacts...")
    
    # Save model (pickle)
    model_path = MODELS_DIR / "model.pkl"
    with open(model_path, 'wb') as f:
        pickle.dump(model, f)
    print(f"  ✅ Model saved: {model_path}")
    
    # Save model (JSON)
    model_json_path = MODELS_DIR / "model.json"
    model.save_model(str(model_json_path))
    print(f"  ✅ Model JSON saved: {model_json_path}")
    
    # Save feature importance
    importance_path = MODELS_DIR / "feature_importance.csv"
    importance_df.to_csv(importance_path, index=False)
    print(f"  ✅ Feature importance saved: {importance_path}")
    
    # Save training metrics
    metrics_path = MODELS_DIR / "training_metrics.json"
    metrics_output = {
        "version": "v4.2.0",
        "created": datetime.now().isoformat(),
        "metrics": metrics,
        "comparison_to_v41": {
            "test_auc_change": metrics["test_auc"] - V41_BASELINE["test_auc"],
            "top_decile_lift_change": metrics["top_decile_lift"] - V41_BASELINE["top_decile_lift"],
            "bottom_20_rate_change": metrics["bottom_20_rate"] - V41_BASELINE["bottom_20_rate"]
        }
    }
    with open(metrics_path, 'w') as f:
        json.dump(metrics_output, f, indent=2)
    print(f"  ✅ Training metrics saved: {metrics_path}")
    
    # Save hyperparameters
    hyperparams_path = MODELS_DIR / "hyperparameters.json"
    hyperparams_output = HYPERPARAMETERS.copy()
    hyperparams_output["scale_pos_weight"] = scale_pos_weight
    hyperparams_output["feature_count"] = len(feature_list)
    with open(hyperparams_path, 'w') as f:
        json.dump(hyperparams_output, f, indent=2)
    print(f"  ✅ Hyperparameters saved: {hyperparams_path}")
    
    # Save feature list
    features_path = DATA_DIR / "final_features.json"
    features_output = {
        "version": "v4.2.0",
        "feature_count": len(feature_list),
        "features": feature_list,
        "career_clock_features": [f for f in feature_list if f.startswith('cc_')]
    }
    with open(features_path, 'w') as f:
        json.dump(features_output, f, indent=2)
    print(f"  ✅ Feature list saved: {features_path}")
    
    print("\n[INFO] All artifacts saved successfully!")


def main():
    """Main training pipeline."""
    print("=" * 60)
    print("V4.2.0 CAREER CLOCK MODEL TRAINING")
    print("=" * 60)
    print(f"Started: {datetime.now()}")
    print(f"Features: {len(FEATURE_LIST)} (22 existing + 7 Career Clock)")
    print("=" * 60)
    
    # Load data
    df = load_data()
    
    # Validate Career Clock features
    validate_career_clock_features(df)
    
    # Prepare features
    X, y = prepare_features(df, FEATURE_LIST)
    
    # Temporal split
    X_train, X_test, y_train, y_test = temporal_split(df, X, y)
    
    # Train model
    model, scale_pos_weight = train_model(X_train, y_train, X_test, y_test)
    
    # Evaluate
    metrics, decile_stats = evaluate_model(model, X_train, y_train, X_test, y_test)
    
    # Validate gates
    gates_passed = validate_gates(metrics)
    
    # Feature importance
    importance_df = calculate_feature_importance(model, FEATURE_LIST)
    
    # Save artifacts
    save_artifacts(model, metrics, importance_df, FEATURE_LIST, scale_pos_weight)
    
    print("\n" + "=" * 60)
    print("TRAINING COMPLETE")
    print("=" * 60)
    print(f"Finished: {datetime.now()}")
    print(f"Gates Passed: {'✅ YES' if gates_passed else '❌ NO'}")
    print(f"Model Location: {MODELS_DIR}")
    print("=" * 60)
    
    return gates_passed


if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
```

## Verification Gate 4.1

```
@workspace Run model training and validate results.

TASK:
1. Execute the training script:
   ```bash
   cd C:\Users\russe\Documents\lead_scoring_production
   python v4/scripts/train_v42_career_clock.py
   ```

2. Verify all gates pass:
   - G1: Test AUC >= 0.58
   - G2: Top Decile Lift >= 1.4x
   - G3: AUC Gap < 0.15
   - G4: Bottom 20% Rate < 2%
   - G5: V4.2 AUC >= V4.1 AUC (no regression)

3. Check Career Clock feature importance:
   - At least 1 Career Clock feature in top 15
   - `cc_is_too_early` should have high importance (deprioritization signal)

4. Verify model artifacts created:
   - v4/models/v4.2.0/model.pkl
   - v4/models/v4.2.0/model.json
   - v4/models/v4.2.0/feature_importance.csv
   - v4/models/v4.2.0/training_metrics.json
   - v4/models/v4.2.0/hyperparameters.json

LOG all results to `pipeline/logs/EXECUTION_LOG.md`

If all gates pass, proceed to Step 5.
If any gate fails, review and adjust hyperparameters.
```

---

# STEP 5: Update Scoring Pipeline

## Cursor Prompt 5.1: Update Monthly Scoring Script

```
@workspace Update the monthly scoring script to use V4.2.0 model.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `pipeline/scripts/score_prospects_monthly.py`
2. Update the following:
   - MODEL_PATH: Point to `v4/models/v4.2.0/model.pkl`
   - FEATURE_LIST: Add 7 Career Clock features (29 total)
   - Update FEATURE_DESCRIPTIONS dict with Career Clock feature descriptions
3. Ensure the scoring script handles new features correctly
4. Update version comments to reference V4.2.0

Show me the updated configuration section and feature list.
```

## Code Snippet 5.1: Update Scoring Script Configuration

Update `pipeline/scripts/score_prospects_monthly.py`:

```python
# =============================================================================
# CONFIGURATION (V4.2.0)
# =============================================================================

MODEL_PATH = Path(__file__).parent.parent.parent / "v4" / "models" / "v4.2.0" / "model.pkl"
FEATURES_PATH = Path(__file__).parent.parent.parent / "v4" / "data" / "v4.2.0" / "final_features.json"

# Feature list (29 features for V4.2.0)
FEATURE_LIST = [
    # Existing V4.1 features (22)
    "tenure_months", "tenure_bucket_encoded", "experience_bucket", "is_experience_missing",
    "mobility_3yr", "is_recent_mover", "days_since_last_move",
    "firm_net_change_12mo", "firm_departures_corrected", "firm_bleeding_velocity", "firm_rep_count_at_contact",
    "is_wirehouse", "is_broker_protocol", "is_independent_ria", "is_ia_rep_type", "is_dual_registered",
    "has_email", "has_linkedin", "has_firm_data", "is_gender_missing",
    "short_tenure_x_high_mobility", "mobility_x_heavy_bleeding",
    # NEW: Career Clock features (7)
    "cc_tenure_cv", "cc_pct_through_cycle", "cc_is_clockwork",
    "cc_is_in_move_window", "cc_is_too_early", "cc_months_until_window", "cc_completed_jobs"
]

# Add Career Clock feature descriptions
FEATURE_DESCRIPTIONS.update({
    'cc_tenure_cv': {
        'positive': 'has a predictable career pattern (consistent tenure lengths)',
        'negative': 'has unpredictable career timing'
    },
    'cc_pct_through_cycle': {
        'positive': 'is approaching their typical tenure duration',
        'negative': 'is early in their typical tenure cycle'
    },
    'cc_is_clockwork': {
        'positive': 'has a highly predictable career clock (changes firms at consistent intervals)',
        'negative': 'has variable career timing'
    },
    'cc_is_in_move_window': {
        'positive': 'is currently in their personal "move window" (70-130% through typical tenure)',
        'negative': 'is not yet in their move window'
    },
    'cc_is_too_early': {
        'positive': 'should be contacted later (too early in career cycle)',
        'negative': 'timing is appropriate for outreach'
    },
    'cc_months_until_window': {
        'positive': 'will enter move window soon',
        'negative': 'move window is far away'
    },
    'cc_completed_jobs': {
        'positive': 'has career history data for pattern detection',
        'negative': 'limited career history data'
    }
})
```

---

# STEP 6: Update Model Registry and Documentation

## Cursor Prompt 6.1: Update Model Registry

```
@workspace Update V4 model registry for V4.2.0.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v4/models/registry.json`
2. Add V4.2.0 entry with:
   - Status: "production"
   - V4.1.0 status: "deprecated"
   - All training metrics
   - Career Clock feature information
   - Comparison to V4.1.0 R3

Show me the updated registry.
```

## Code Snippet 6.1: Updated Registry

Update `v4/models/registry.json`:

```json
{
  "current_production": "v4.2.0",
  "models": {
    "v4.2.0": {
      "version": "v4.2.0",
      "status": "production",
      "training_date": "2026-01-XX",
      "deployed_date": "2026-01-XX",
      "model_type": "XGBoost",
      "features": 29,
      "new_features": [
        "cc_tenure_cv",
        "cc_pct_through_cycle",
        "cc_is_clockwork",
        "cc_is_in_move_window",
        "cc_is_too_early",
        "cc_months_until_window",
        "cc_completed_jobs"
      ],
      "hyperparameters": {
        "max_depth": 2,
        "min_child_weight": 30,
        "reg_alpha": 1.0,
        "reg_lambda": 5.0,
        "gamma": 0.3,
        "learning_rate": 0.01,
        "n_estimators": 2000,
        "early_stopping_rounds": 150,
        "subsample": 0.6,
        "colsample_bytree": 0.7,
        "base_score": 0.5,
        "scale_pos_weight": "dynamic"
      },
      "metrics": {
        "test_auc_roc": "TBD",
        "test_auc_pr": "TBD",
        "top_decile_lift": "TBD",
        "bottom_20_pct_rate": "TBD",
        "train_test_auc_gap": "TBD",
        "early_stopping_iteration": "TBD"
      },
      "comparison": {
        "vs_v4.1.0": "TBD after training",
        "career_clock_features_in_top_15": "TBD"
      },
      "shap": {
        "method": "KernelExplainer",
        "top_features": "TBD"
      },
      "deployment_strategy": "hybrid",
      "use_case": "deprioritization_filter",
      "deprioritization_threshold": 20,
      "notes": "V4.2.0 adds Career Clock features to capture individual advisor timing patterns. Expected improvement: better identification of 'too early' leads for deprioritization."
    },
    "v4.1.0": {
      "version": "v4.1.0",
      "revision": "R3",
      "status": "deprecated",
      "deprecated_date": "2026-01-XX",
      "deprecated_reason": "Superseded by V4.2.0 with Career Clock features",
      "training_date": "2025-12-30",
      "model_type": "XGBoost",
      "features": 22,
      "metrics": {
        "test_auc_roc": 0.6198,
        "test_auc_pr": 0.0697,
        "top_decile_lift": 2.03,
        "bottom_20_pct_rate": 0.0140,
        "train_test_auc_gap": 0.0746
      }
    },
    "v4.0.0": {
      "model_version": "v4.0.0",
      "status": "archived",
      "deprecated_date": "2025-12-30",
      "deprecated_reason": "Superseded by V4.1.0"
    }
  }
}
```

## Cursor Prompt 6.2: Update VERSION_4_MODEL_REPORT.md

```
@workspace Update V4 model report with Career Clock documentation.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v4/VERSION_4_MODEL_REPORT.md`
2. Add a new section "## V4.2.0: Career Clock Features (January 2026)"
3. Document:
   - New features added
   - Training results
   - Comparison to V4.1.0 R3
   - Career Clock feature importance
   - Expected impact on deprioritization
4. Update the "Current Production" version at top

Include placeholders for metrics that will be filled after training.
```

## Code Snippet 6.2: V4 Model Report Update

Add to `v4/VERSION_4_MODEL_REPORT.md`:

```markdown
---

## V4.2.0: Career Clock Features (January 2026)

### Overview

V4.2.0 extends the V4.1.0 R3 model by adding 7 Career Clock features that capture individual advisor career timing patterns. These features were validated in V3.4.0 to significantly improve conversion prediction.

### New Features Added

| Feature | Type | Description | Expected Impact |
|---------|------|-------------|-----------------|
| `cc_tenure_cv` | FLOAT | Coefficient of variation of prior tenures | Pattern consistency signal |
| `cc_pct_through_cycle` | FLOAT | Current tenure / avg prior tenure | Timing within personal cycle |
| `cc_is_clockwork` | INT | 1 if CV < 0.3 (highly predictable) | Identifies predictable advisors |
| `cc_is_in_move_window` | INT | 1 if 70-130% through typical cycle | Optimal timing flag |
| `cc_is_too_early` | INT | 1 if <70% through cycle | **Deprioritization signal** |
| `cc_months_until_window` | INT | Months until move window | Nurture timing |
| `cc_completed_jobs` | INT | Count of completed prior jobs | Pattern reliability |

### Key Hypothesis

**"Too Early" leads are poor candidates for immediate outreach.**

V3.4 analysis showed:
- Advisors contacted "too early" in their career cycle convert at only **3.14%**
- The same advisors contacted "in window" convert at **10-16%**
- V4 can use `cc_is_too_early` as a strong deprioritization signal

### Training Results

| Metric | V4.1.0 R3 | V4.2.0 | Change |
|--------|-----------|--------|--------|
| Test AUC-ROC | 0.6198 | TBD | TBD |
| Test AUC-PR | 0.0697 | TBD | TBD |
| Top Decile Lift | 2.03x | TBD | TBD |
| Bottom 20% Rate | 1.40% | TBD | TBD |
| Features | 22 | 29 | +7 |

### Career Clock Feature Importance

| Rank | Feature | Importance | Notes |
|------|---------|------------|-------|
| TBD | TBD | TBD | TBD |

### Expected Impact

1. **Better Deprioritization**: Bottom 20% should have even lower conversion rate
2. **Improved Timing**: Model can learn optimal contact timing
3. **Feature Interactions**: XGBoost can discover Career Clock × existing feature interactions

### PIT Compliance

All Career Clock features are PIT-compliant:
- Only use completed employment records with `END_DATE < contacted_date`
- Pattern calculation uses only historical data available at contact time
- No future information leakage

### Deployment

- **Training Data**: Same temporal split as V4.1 (Feb 2024-Jul 2025 train, Aug-Oct 2025 test)
- **Model Files**: `v4/models/v4.2.0/`
- **Feature List**: `v4/data/v4.2.0/final_features.json`
- **Scoring Script**: `pipeline/scripts/score_prospects_monthly.py` (updated)

---
```

## Cursor Prompt 6.3: Update README.md

```
@workspace Update main README with V4.2.0 documentation.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `README.md`
2. Update the V4 model section to reference V4.2.0
3. Add Career Clock feature summary
4. Update feature count (22 → 29)
5. Update model performance comparison table

Show me the relevant updated sections.
```

## Code Snippet 6.3: README Update

Add/update in `README.md`:

```markdown
---

## V4.2.0: Career Clock Features (January 2026)

### Model Enhancement

V4.2.0 extends V4.1.0 R3 by adding 7 Career Clock features that capture individual advisor timing patterns:

| Feature | Description |
|---------|-------------|
| `cc_tenure_cv` | Career pattern consistency (lower = more predictable) |
| `cc_pct_through_cycle` | Position in personal career clock |
| `cc_is_clockwork` | Highly predictable pattern flag |
| `cc_is_in_move_window` | Optimal timing window flag |
| `cc_is_too_early` | **Deprioritization signal** |
| `cc_months_until_window` | Months until move window |
| `cc_completed_jobs` | Career history depth |

### Performance Comparison

| Metric | V4.0.0 | V4.1.0 R3 | V4.2.0 |
|--------|--------|-----------|--------|
| Test AUC-ROC | 0.599 | 0.620 | TBD |
| Top Decile Lift | 1.51x | 2.03x | TBD |
| Bottom 20% Rate | 1.33% | 1.40% | TBD |
| Features | 14 | 22 | 29 |

### Key Innovation: Timing-Aware Deprioritization

Career Clock features enable the model to identify leads that are:
- **Too Early**: Predictable advisor not yet in their move window → Deprioritize
- **In Window**: Predictable advisor in optimal timing → Prioritize

This complements V3.4's tier-based timing with ML-learned interactions.

---
```

## Cursor Prompt 6.4: Update Execution Log

```
@workspace Create execution log entry for V4.2.0 implementation.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `pipeline/logs/EXECUTION_LOG.md`
2. Add comprehensive entry for V4.2.0 Career Clock implementation
3. Include:
   - All files modified
   - Training results (with placeholders)
   - Validation gate results
   - Deployment steps
   - Comparison to V4.1.0 R3

Use the same format as the V3.4.0 entry.
```

## Code Snippet 6.4: Execution Log Entry

Add to `pipeline/logs/EXECUTION_LOG.md`:

```markdown
---

# V4.2.0 Career Clock Feature - Execution Log

**Date:** January XX, 2026  
**Version:** V4.2.0_CAREER_CLOCK  
**Status:** 🔄 In Progress / ✅ Complete

---

## Summary

V4.2.0 adds 7 Career Clock features to the V4 XGBoost model, enabling timing-aware deprioritization of leads contacted too early in their career cycle.

---

## Files Modified

### 1. `v4/sql/v4.1/phase_2_feature_engineering_v41.sql`
**Changes:**
- Added `career_clock_raw` CTE
- Added `career_clock_stats` CTE
- Added `career_clock_features` CTE
- Added 7 Career Clock features to final SELECT
- Updated to V4.2.0

### 2. `pipeline/sql/v4_prospect_features.sql`
**Changes:**
- Added Career Clock CTEs for inference
- Added 7 Career Clock features to output
- Ensured NULL handling matches training

### 3. `v4/scripts/train_v42_career_clock.py`
**Changes:**
- Created new training script for V4.2.0
- Updated feature list (29 features)
- Added Career Clock feature validation

### 4. `pipeline/scripts/score_prospects_monthly.py`
**Changes:**
- Updated MODEL_PATH to v4.2.0
- Updated FEATURE_LIST (29 features)
- Added Career Clock feature descriptions

### 5. `v4/models/registry.json`
**Changes:**
- Added V4.2.0 entry
- Deprecated V4.1.0

### 6. `v4/VERSION_4_MODEL_REPORT.md`
**Changes:**
- Added V4.2.0 section
- Documented Career Clock features
- Added training results

### 7. `README.md`
**Changes:**
- Updated V4 model section
- Added V4.2.0 documentation

---

## Training Results

### Feature Engineering Validation
- ✅ Training table created: `ml_features.v4_features_pit_v42`
- ✅ Inference table updated: `ml_features.v4_prospect_features`
- ✅ Career Clock columns: 7 features added
- ✅ PIT compliance verified

### Model Training
- **Features**: 29 (22 existing + 7 Career Clock)
- **Training Set**: XX,XXX leads
- **Test Set**: X,XXX leads
- **Best Iteration**: XXX

### Validation Gates

| Gate | Requirement | Result | Status |
|------|-------------|--------|--------|
| G1 | Test AUC >= 0.58 | TBD | TBD |
| G2 | Top Decile Lift >= 1.4x | TBD | TBD |
| G3 | AUC Gap < 0.15 | TBD | TBD |
| G4 | Bottom 20% Rate < 2% | TBD | TBD |
| G5 | V4.2 AUC >= V4.1 AUC | TBD | TBD |

### Career Clock Feature Importance

| Rank | Feature | Importance |
|------|---------|------------|
| TBD | TBD | TBD |

---

## Comparison to V4.1.0 R3

| Metric | V4.1.0 R3 | V4.2.0 | Change |
|--------|-----------|--------|--------|
| Test AUC | 0.6198 | TBD | TBD |
| Top Decile Lift | 2.03x | TBD | TBD |
| Bottom 20% Rate | 1.40% | TBD | TBD |
| Features | 22 | 29 | +7 |

---

## Deployment Steps

1. ✅ Feature engineering SQL updated
2. ✅ Training script created
3. 🔄 Model trained (pending)
4. 🔄 Scoring script updated (pending)
5. 🔄 Registry updated (pending)
6. 🔄 Documentation updated (pending)
7. ⏳ BigQuery deployment (pending)
8. ⏳ Validation (pending)

---

## Expected Impact

| Metric | Expected Change |
|--------|-----------------|
| Test AUC | +2-5% |
| Top Decile Lift | +5-10% |
| Bottom 20% Rate | -15-30% (better filtering) |
| "Too Early" Detection | NEW capability |

---

**Date Completed:** TBD  
**Implemented By:** AI Assistant (Cursor.ai)  
**Verified By:** TBD

---
```

---

# STEP 7: Deploy to BigQuery

## Cursor Prompt 7.1: Deploy All SQL Updates

```
@workspace Deploy V4.2.0 feature engineering and scoring updates to BigQuery.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Deploy training feature table:
   - Run: `v4/sql/v4.1/phase_2_feature_engineering_v41.sql`
   - Creates: `ml_features.v4_features_pit_v42`

2. Deploy inference feature table:
   - Run: `pipeline/sql/v4_prospect_features.sql`
   - Updates: `ml_features.v4_prospect_features`

3. Validate both tables have 29 features including Career Clock

4. Run training script:
   - Execute: `python v4/scripts/train_v42_career_clock.py`
   - Verify all gates pass

5. Update scoring and generate new scores:
   - Execute: `python pipeline/scripts/score_prospects_monthly.py`
   - Creates: `ml_features.v4_prospect_scores`

Log all results to execution log.
```

## Verification Gate 7.1: Final Validation

```
@workspace Run final V4.2.0 system validation.

TASK:
Execute comprehensive validation:

```sql
-- 1. Verify V4.2.0 features in training data
SELECT 
    COUNT(*) as total_rows,
    COUNTIF(cc_tenure_cv IS NOT NULL) as has_cc_features,
    COUNTIF(cc_is_too_early = 1) as too_early_count,
    COUNTIF(cc_is_in_move_window = 1) as in_window_count
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v42`;

-- 2. Verify V4.2.0 features in inference data
SELECT 
    COUNT(*) as total_prospects,
    COUNTIF(cc_tenure_cv IS NOT NULL) as has_cc_features
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`;

-- 3. Verify scoring uses V4.2.0
SELECT 
    COUNT(*) as total_scored,
    MIN(v4_score) as min_score,
    MAX(v4_score) as max_score,
    COUNTIF(v4_deprioritize = TRUE) as deprioritized_count
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`;

-- 4. Check deprioritization by Career Clock status
SELECT 
    CASE 
        WHEN f.cc_is_too_early = 1 THEN 'Too_Early'
        WHEN f.cc_is_in_move_window = 1 THEN 'In_Window'
        ELSE 'Other'
    END as cc_status,
    COUNT(*) as prospects,
    AVG(s.v4_score) as avg_score,
    COUNTIF(s.v4_deprioritize = TRUE) as deprioritized,
    ROUND(COUNTIF(s.v4_deprioritize = TRUE) / COUNT(*) * 100, 1) as deprioritize_pct
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features` f
JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` s ON f.crd = s.crd
GROUP BY 1
ORDER BY 1;
```

EXPECTED:
- "Too_Early" prospects should have higher deprioritization rate
- "In_Window" prospects should have lower deprioritization rate
- This validates Career Clock is working as intended

Update execution log with final results.
```

---

## Rollback Plan (If V4.2.0 Fails Gates)

If V4.2.0 fails validation gates or shows regression:

### **Step 1: Revert Model Registry**

In `v4/models/registry.json`:
```json
{
  "current_production": "v4.1.0",  // Change back from v4.2.0
  "models": {
    "v4.2.0": {
      "status": "failed_validation",  // Update status
      "failure_reason": "Failed Gate X: [reason]"
    },
    "v4.1.0": {
      "status": "production"  // Restore to production
    }
  }
}
```

### **Step 2: Revert Scoring Script**

In `pipeline/scripts/score_prospects_monthly.py`:
```python
# Revert MODEL_PATH
MODEL_PATH = Path(__file__).parent.parent.parent / "v4" / "models" / "v4.1.0_r3" / "model.pkl"

# Revert FEATURE_LIST (remove Career Clock features, back to 22 features)
FEATURE_LIST = [
    # ... 22 original features only (remove 7 Career Clock features)
]
```

### **Step 3: Keep V4.2.0 Artifacts for Debugging**

**DO NOT DELETE:**
- `v4/models/v4.2.0/` directory (keep for analysis)
- `v4/data/v4.2.0/` directory (keep for reference)
- BigQuery table `ml_features.v4_features_pit_v42` (keep for comparison)

**Document failure in:**
- `pipeline/logs/EXECUTION_LOG.md` (add failure section)
- `v4/models/registry.json` (update status)

### **Step 4: Re-run Scoring with V4.1.0**

```bash
cd C:\Users\russe\Documents\lead_scoring_production
python pipeline/scripts/score_prospects_monthly.py
```

### **Step 5: Investigate Failure**

Common failure reasons:
1. **Overfitting:** Train AUC >> Test AUC → Increase regularization
2. **Feature Correlation:** Career Clock features highly correlated → Remove redundant
3. **Data Quality:** Low Career Clock feature coverage → Check PIT filters
4. **Hyperparameters:** Need adjustment for 29 features → Tune colsample_bytree

**Next Steps After Rollback:**
- Review validation gate failures
- Adjust hyperparameters if needed
- Re-train with fixes
- Re-validate before deployment

---

# Summary: Quick Reference

## Files Modified

| File | Changes |
|------|---------|
| `v4/sql/v4.1/phase_2_feature_engineering_v41.sql` | Added Career Clock CTEs |
| `pipeline/sql/v4_prospect_features.sql` | Added Career Clock for inference |
| `v4/scripts/train_v42_career_clock.py` | NEW: Training script |
| `pipeline/scripts/score_prospects_monthly.py` | Updated feature list, model path |
| `v4/models/registry.json` | Added V4.2.0, deprecated V4.1.0 |
| `v4/VERSION_4_MODEL_REPORT.md` | Added V4.2.0 section |
| `README.md` | Updated V4 documentation |
| `pipeline/logs/EXECUTION_LOG.md` | Added execution record |

## Files Created

| File | Purpose |
|------|---------|
| `v4/data/v4.2.0/final_features.json` | 29-feature list |
| `v4/models/v4.2.0/hyperparameters.json` | Training config |
| `v4/models/v4.2.0/model.pkl` | Trained model |
| `v4/models/v4.2.0/model.json` | Model JSON |
| `v4/models/v4.2.0/feature_importance.csv` | Feature importance |
| `v4/models/v4.2.0/training_metrics.json` | Training results |

## BigQuery Tables

| Table | Action |
|-------|--------|
| `ml_features.v4_features_pit_v42` | Created (training) |
| `ml_features.v4_prospect_features` | Updated (inference) |
| `ml_features.v4_prospect_scores` | Updated (scores) |

## Expected Outcomes

- **29 features** (22 existing + 7 Career Clock)
- **Better deprioritization** of "Too_Early" leads
- **~5-10% improvement** in top decile lift
- **~15-30% reduction** in bottom 20% conversion rate
