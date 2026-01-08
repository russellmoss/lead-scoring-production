# V4.3.0 Pre-Training Validation Queries

This directory contains validation queries that must be run **before** training the V4.3.0 model.

## Prerequisites

1. **Run training feature engineering SQL first:**
   ```sql
   -- Execute: v4/sql/v4.3/phase_2_feature_engineering_v43.sql
   -- This creates: savvy-gtm-analytics.ml_features.v4_training_features_v43
   ```

2. **Ensure the table has all required columns:**
   - All 23 V4.2.0 features
   - `cc_is_in_move_window` (new)
   - `cc_is_too_early` (new)
   - `converted` (target variable)

## Validation Gates

### Gate 1: Collinearity Check
**File:** `01_collinearity_check.sql`

**Purpose:** Verify Career Clock features are independent from all existing features.

**Threshold:** All correlations must be < 0.30 (absolute value)

**Expected Results:**
- `cc_is_in_move_window` vs `age_bucket_encoded`: ~-0.027 ✅
- `cc_is_too_early` vs `age_bucket_encoded`: ~-0.035 ✅
- `cc_is_in_move_window` vs `tenure_months`: < 0.20 ✅
- `cc_is_in_move_window` vs `cc_is_too_early`: ~-0.15 ✅

**Action if FAIL:** STOP and investigate. Features may be redundant.

---

### Gate 2: Feature Coverage Check
**File:** `02_feature_coverage_check.sql`

**Purpose:** Verify Career Clock features have expected distribution.

**Expected Distribution:**
| Metric | Expected % | Status |
|--------|-----------|--------|
| `cc_is_in_move_window = 1` | 4-6% | ✅ PASS if in range |
| `cc_is_too_early = 1` | 8-12% | ✅ PASS if in range |
| Both = 0 (no pattern) | 75-85% | ✅ PASS if in range |
| Both = 1 (invalid) | 0% | ❌ FAIL if > 0% |

**Action if FAIL:** Review feature engineering logic. Features should be mutually exclusive.

---

### Gate 3: Conversion Rate Validation
**File:** `03_conversion_rate_validation.sql`

**Purpose:** Validate Career Clock features show expected conversion lift.

**Expected Results:**
| CC Status | Expected Conv Rate | Expected Lift | Status |
|-----------|-------------------|---------------|--------|
| In_Window | 5.0-6.0% | 1.3-1.6x | ✅ PASS if in range |
| Too_Early | 3.5-4.0% | 0.9-1.0x | ✅ PASS if in range |
| No_Pattern | 3.5-4.0% | ~1.0x | ✅ PASS if in range |

**Action if FAIL:** Review Career Clock logic. Conversion rates should match analysis results.

---

## Running Validation

### Option 1: Run All Gates at Once
```sql
-- Execute: 00_run_all_validation_gates.sql
-- This runs all three gates in sequence with summary results
```

### Option 2: Run Gates Individually
```sql
-- Execute each file separately:
-- 1. 01_collinearity_check.sql
-- 2. 02_feature_coverage_check.sql
-- 3. 03_conversion_rate_validation.sql
```

## Next Steps

**If ALL gates PASS:**
- ✅ Proceed to model training: `v4/scripts/train_model_v43.py`
- ✅ Training will run additional validation gates (AUC, overfitting, SHAP validation)

**If ANY gate FAILS:**
- ❌ DO NOT proceed to training
- ❌ Review the failing gate results
- ❌ Investigate and fix the issue
- ❌ Re-run validation until all gates pass

## Notes

- These validation gates are **CRITICAL** - they ensure Career Clock features are:
  1. Independent (not redundant with existing features)
  2. Well-distributed (sufficient coverage for model learning)
  3. Predictive (show expected conversion lift)

- All gates must pass before training to avoid:
  - Overfitting (if features are redundant)
  - Poor model performance (if features don't add signal)
  - Deployment issues (if features don't work as expected)
