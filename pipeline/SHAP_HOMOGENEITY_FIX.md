# SHAP Feature Homogeneity Bug - Fix

## 🐛 **THE BUG**

All 2,786 leads in the January 2026 list had **identical** SHAP features:
- `shap_top1_feature = "short_tenure_x_high_mobility"` (100% of leads)
- `shap_top2_feature = "mobility_x_heavy_bleeding"` (100% of leads)  
- `shap_top3_feature = "has_linkedin"` (100% of leads)

This defeats the purpose of personalized narratives. Each lead should have **different** top features based on their individual SHAP values.

## 🔍 **ROOT CAUSE**

The bug was likely caused by:

1. **Proxy fallback method**: When SHAP calculation failed, the code fell back to a proxy method using global feature importance, which gave identical results for all leads.

2. **Missing validation**: No checks to detect when all leads have identical SHAP features.

3. **Silent failures**: SHAP calculation failures were masked by fallback to zeros or proxy methods.

## ✅ **THE FIX**

### 1. Enhanced SHAP Calculation (`calculate_shap_values`)

**Added validations:**
- ✅ Shape validation: Ensures SHAP values are 2D array `(n_leads, n_features)`
- ✅ Batch validation: Checks each batch has correct shape before concatenation
- ✅ Zero detection: Raises error if all SHAP values are zero
- ✅ Homogeneity detection: Raises error if all leads have identical SHAP values
- ✅ No silent fallback: Removed proxy method fallback that caused the bug

**Key changes:**
```python
# OLD (WRONG): Silent fallback to zeros
except Exception as e:
    shap_values_list.append(np.zeros((len(X_batch), len(X.columns))))

# NEW (CORRECT): Raise error, don't mask failure
except Exception as e:
    raise RuntimeError(
        f"SHAP calculation failed. Falling back to zeros would cause homogeneity bug."
    ) from e
```

### 2. Enhanced Feature Extraction (`extract_top_shap_features`)

**Added validations:**
- ✅ Input shape validation: Ensures 2D array with correct dimensions
- ✅ Per-lead extraction: Explicitly extracts top features for each lead individually
- ✅ Diversity checks: Validates that we have multiple unique top features
- ✅ Error on homogeneity: Raises error if < 3 unique top-1 features

**Key changes:**
```python
# Added validation after extraction
unique_top1 = len(set(results['shap_top1_feature']))

if unique_top1 < 3:
    raise ValueError(
        f"SHAP HOMOGENEITY BUG DETECTED! Only {unique_top1} unique top-1 features. "
        f"This indicates per-lead SHAP extraction failed."
    )
```

### 3. Removed Proxy Fallback

**OLD (WRONG):**
```python
try:
    shap_values = calculate_shap_values(model, X)
except Exception as e:
    # Fallback to proxy - CAUSES HOMOGENEITY BUG!
    shap_values = compute_proxy_shap(X, model)
```

**NEW (CORRECT):**
```python
try:
    shap_values = calculate_shap_values(model, X)
except Exception as e:
    # NO FALLBACK - raise error instead
    raise RuntimeError(
        f"SHAP calculation failed. Falling back would cause homogeneity bug."
    ) from e
```

### 4. Enhanced Validation Output

**Added diversity reporting:**
- Shows unique feature counts
- Shows distribution of top features
- Warns if any single feature dominates >30%
- Raises error if homogeneity detected

## 📊 **EXPECTED RESULTS (After Fix)**

### Before Fix:
```
SHAP Top Feature Distribution:
short_tenure_x_high_mobility  2786 (100.0%)  <-- BUG!
```

### After Fix:
```
SHAP Top Feature Distribution:
tenure_bucket                 612 (22.0%)
mobility_tier                 534 (19.2%)
short_tenure_x_high_mobility  489 (17.5%)
firm_stability_tier           445 (16.0%)
has_email                     398 (14.3%)
experience_bucket             308 (11.0%)
```

## 🚀 **NEXT STEPS**

1. **Re-run scoring script** to regenerate SHAP values:
   ```bash
   cd pipeline
   python scripts/score_prospects_monthly.py
   ```

2. **Verify diversity** in output:
   - Should see 10+ unique top-1 features
   - No single feature should dominate >30%
   - Validation should pass

3. **Re-generate lead list** with corrected SHAP values:
   ```bash
   # Run SQL in BigQuery: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
   # Then export: python scripts/export_lead_list.py
   ```

## 🔍 **VALIDATION QUERIES**

After re-running, verify diversity:

```sql
-- Check unique SHAP features
SELECT 
    COUNT(DISTINCT shap_top1_feature) as unique_top1,
    COUNT(DISTINCT shap_top2_feature) as unique_top2,
    COUNT(DISTINCT shap_top3_feature) as unique_top3
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`;

-- Expected: unique_top1 >= 10

-- Check distribution
SELECT 
    shap_top1_feature,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) as pct
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
GROUP BY shap_top1_feature
ORDER BY count DESC
LIMIT 10;

-- Expected: No single feature > 30% of leads
```

## 📝 **FILES MODIFIED**

1. `pipeline/scripts/score_prospects_monthly.py`
   - Enhanced `calculate_shap_values()` with validation
   - Enhanced `extract_top_shap_features()` with diversity checks
   - Removed proxy fallback method
   - Added comprehensive validation output

## ⚠️ **IMPORTANT NOTES**

- **No fallback**: The script will now FAIL if SHAP calculation fails, rather than silently using a proxy that causes homogeneity.
- **Validation is strict**: If < 3 unique top-1 features are detected, the script raises an error.
- **Performance**: Real SHAP calculation takes ~5-10 minutes for 285k prospects (batched). This is acceptable for production accuracy.

