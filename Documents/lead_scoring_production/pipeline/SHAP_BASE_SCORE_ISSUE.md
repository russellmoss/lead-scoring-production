# SHAP Base Score Issue - Known Problem

## 🐛 **THE ISSUE**

The XGBoost model has `base_score` stored as string `'[5E-1]'` in its internal structure. SHAP's `TreeExplainer` tries to convert this to float and fails with:

```
ValueError: could not convert string to float: '[5E-1]'
```

This is a known compatibility issue between certain XGBoost model versions and SHAP.

## 🔍 **ROOT CAUSE**

When the model was saved, XGBoost stored `base_score` as `'[5E-1]'` (scientific notation in brackets). SHAP expects a clean float string like `'0.5'`.

Even though:
- The model.json file shows `"base_score": "0.5"`
- We can fix it in the config
- We can fix it in the JSON file

SHAP still reads it from the model's internal structure where it remains as `'[5E-1]'`.

## ✅ **SOLUTIONS**

### Option 1: Retrain Model (Recommended for Production)

Retrain the model with a newer XGBoost version that saves `base_score` correctly:

```python
# In model training script, ensure base_score is set explicitly
model = xgb.XGBClassifier(
    base_score=0.5,  # Explicit float, not default
    ...
)
```

### Option 2: Use SHAP Version Workaround

Try downgrading/upgrading SHAP to a version that handles this:

```bash
pip install shap==0.41.0  # Or try latest
```

### Option 3: Temporary Workaround (Current)

For now, we can use a per-lead feature importance calculation that:
- Uses model's feature importance as base
- Adjusts by each lead's feature values
- Produces diverse features per lead (not perfect SHAP, but better than homogeneity)

This is implemented in the scoring script as a fallback when SHAP fails.

## 📊 **CURRENT STATUS**

- **SHAP TreeExplainer**: ❌ Fails due to base_score format
- **SHAP Explainer**: ❌ Also fails (needs callable model)
- **Workaround**: ⚠️ Available but not perfect SHAP values

## 🚀 **RECOMMENDED ACTION**

**For immediate use**: The current lead list (Dec 26) has SHAP values, but they're homogeneous (bug). 

**For proper fix**: Retrain the model with explicit `base_score=0.5` parameter, or upgrade XGBoost/SHAP versions.

## 📝 **FILES AFFECTED**

- `pipeline/scripts/score_prospects_monthly.py` - SHAP calculation
- `v4/models/v4.0.0/model.json` - Model file with base_score issue
- `v4/scripts/phase_6_model_training.py` - Model training (needs update)

