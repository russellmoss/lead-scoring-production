# SHAP Feature Homogeneity Bug - Root Cause & Fix

## 🐛 **BUG IDENTIFIED**

**Issue**: All 2,794 leads in the January 2026 lead list have identical top 3 SHAP features:
- `short_tenure_x_high_mobility`
- `mobility_x_heavy_bleeding`
- `has_linkedin`

**Root Cause**: The scoring script (`score_prospects_monthly.py`) was using a **broken proxy method** instead of computing actual SHAP values.

## 🔍 **TECHNICAL DETAILS**

### The Broken Proxy Method (Lines 438-449)

```python
# OLD CODE - BROKEN
shap_values = np.zeros((len(X), len(feature_list)))
for i, feat in enumerate(feature_list):
    feat_values = X[feat].values
    if feat_values.std() > 0:
        feat_normalized = (feat_values - feat_values.mean()) / feat_values.std()
    else:
        feat_normalized = feat_values
    shap_values[:, i] = feat_normalized * importance_dict.get(feat, 0.0)
```

**Why This Was Wrong**:
1. Normalizes each feature to z-scores (mean=0, std=1)
2. Multiplies by **global** feature importance
3. Result: Ranking is **always the same** for all prospects (based on global importance)
4. Ignores individual prospect feature values and their actual contribution to predictions

### The Fix

**Replaced with actual SHAP computation** using `shap.TreeExplainer`:
- Computes real SHAP values per prospect
- Accounts for feature interactions and individual contributions
- Results vary by prospect (as they should)

**Fallback**: Improved proxy method that accounts for:
- Feature value deviations
- Global importance
- Prediction score impact
- More prospect-specific than the original

## ✅ **FIX APPLIED**

**File**: `pipeline/scripts/score_prospects_monthly.py`

**Changes**:
1. Replaced proxy method with `calculate_shap_values()` function call
2. Added proper error handling with improved fallback
3. Added comments explaining why real SHAP is necessary

## 🚀 **NEXT STEPS**

1. **Re-run Step 2** (V4 scoring) to regenerate scores with correct SHAP values:
   ```bash
   cd pipeline
   python scripts/score_prospects_monthly.py
   ```

2. **Re-run Step 3** (Lead list generation) to update the lead list:
   ```bash
   # Run SQL: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
   ```

3. **Re-run Step 4** (Export) to generate new CSV:
   ```bash
   python scripts/export_lead_list.py
   ```

## ⚠️ **PERFORMANCE NOTE**

- **Real SHAP computation**: ~5-10 minutes for 285k prospects (batched)
- **Previous proxy**: ~30 seconds
- **Trade-off**: Accuracy vs. speed - accuracy wins for production use

## 📊 **EXPECTED RESULTS AFTER FIX**

- **Varied SHAP features**: Each prospect should have different top features based on their individual characteristics
- **More meaningful narratives**: SHAP-based explanations will be prospect-specific
- **Better model interpretability**: Can identify which features drive each prospect's high score

## 🔬 **VALIDATION QUERIES**

After re-running, validate with:

```sql
-- Check SHAP feature diversity
SELECT 
    shap_top1_feature,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as pct
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
WHERE v4_percentile >= 80
GROUP BY shap_top1_feature
ORDER BY count DESC
LIMIT 10;

-- Should show diverse features, not 100% one feature
```

