# SHAP base_score Issue - Debug Summary

**Date:** January 7, 2026  
**Model:** V4.2.0 (Age Feature)  
**Issue:** SHAP TreeExplainer fails with `could not convert string to float: '[5E-1]'`

---

## Problem Statement

When attempting to initialize SHAP TreeExplainer for V4.2.0 model narratives, we encountered a persistent error:

```
ValueError: could not convert string to float: '[5E-1]'
```

This error occurs in SHAP's `XGBTreeModelLoader.__init__` when it tries to parse the `base_score` parameter from the XGBoost model's internal configuration.

### Root Cause

XGBoost models saved with pickle (or even JSON in some cases) can store `base_score` as a string `'[5E-1]'` instead of the float `0.5`. This is a known XGBoost serialization quirk where scientific notation gets wrapped in brackets.

When SHAP's TreeExplainer tries to read this value:
```python
self.base_score = float(learner_model_param["base_score"])
```

It fails because `float('[5E-1]')` raises a ValueError.

---

## Attempted Solutions

### 1. Model Conversion to JSON Format

**Approach:** Convert the pickle model to XGBoost's native JSON format, which should have cleaner serialization.

**Implementation:**
- Created `v4/scripts/convert_model_to_json.py`
- Loaded model from pickle
- Saved to JSON using `model.save_model()`
- Attempted to fix base_score in JSON file directly

**Result:** ❌ **Failed**
- Even after conversion, the JSON file still contained `base_score: '[5E-1]'`
- When reloaded, the booster's internal state still had the string format
- SHAP TreeExplainer still failed

**Why it failed:**
- The base_score issue is in the model's internal C++ state, not just the file format
- `load_config()` doesn't actually update the internal structure that SHAP reads
- The JSON format doesn't automatically fix the serialization bug

### 2. Monkey-Patching SHAP's XGBTreeModelLoader

**Approach:** Intercept SHAP's initialization and fix base_score before it's parsed.

**Implementation:**
- Created module-level patch in `v4/inference/lead_scorer_v4.py`
- Patched `XGBTreeModelLoader.__init__` to fix base_score before calling original init
- Attempted to fix via `booster.load_config()` with corrected JSON

**Result:** ❌ **Failed**
- The patch was applied, but SHAP still read the old value
- `load_config()` doesn't persist changes to the internal C++ structure
- The error occurred before our patch could intercept it

### 3. Explainer with Prediction Wrapper (Fallback)

**Approach:** Use SHAP's generic `Explainer` with a prediction function wrapper instead of TreeExplainer.

**Implementation:**
- Modified `_init_shap_explainer()` to catch base_score errors
- Created `model_predict()` wrapper function
- Used `shap.Explainer()` with the wrapper instead of `TreeExplainer()`

**Result:** ⚠️ **Partially Working**
- Explainer initializes successfully (bypasses base_score issue)
- Can generate SHAP values
- **BUT:** Feature shape mismatch error (expected 23, got 22)

**Current Status:**
```python
[INFO] TreeExplainer failed due to base_score issue, using Explainer with prediction wrapper
[INFO] Initialized SHAP Explainer (with prediction wrapper - slower but works)
```

However, when calling `get_shap_narrative()`:
```
ValueError: Feature shape mismatch, expected: 23, got 22
```

---

## Current Implementation

### Model Loading (Updated)

The inference script now:
1. **Prefers JSON format** (if `model.json` exists)
2. **Falls back to pickle** (if JSON not found)
3. **Logs format used** for debugging

```python
def _load_model(self):
    json_path = self.model_dir / "model.json"
    pkl_path = self.model_dir / "model.pkl"
    
    if json_path.exists():
        self.model = xgb.XGBClassifier()
        self.model.load_model(str(json_path))
        print(f"[INFO] Loaded model from {json_path} (JSON format)")
    elif pkl_path.exists():
        with open(pkl_path, 'rb') as f:
            self.model = pickle.load(f)
        print(f"[INFO] Loaded model from {pkl_path} (pickle format - SHAP may not work)")
```

### SHAP Initialization (With Fallback)

```python
def _init_shap_explainer(self):
    try:
        # Try TreeExplainer first (fastest)
        booster = self.model.get_booster()
        self.explainer = shap.TreeExplainer(booster)
        self.shap_available = True
    except Exception as e:
        error_str = str(e).lower()
        is_base_score_error = (
            'base_score' in error_str or 
            ('could not convert string to float' in error_str and '[5e-1]' in error_str)
        )
        
        if is_base_score_error:
            # Use Explainer with prediction wrapper
            def model_predict(X):
                if isinstance(X, xgb.DMatrix):
                    return self.model.predict(X)
                elif isinstance(X, pd.DataFrame):
                    X_prep = X[self.feature_list]
                    return self.model.predict_proba(X_prep)[:, 1]
                else:
                    return self.model.predict_proba(X)[:, 1]
            
            self.explainer = shap.Explainer(
                model_predict,
                background=np.zeros((1, len(self.feature_list))),
                feature_names=self.feature_list
            )
            self.shap_available = True
```

---

## Persisting Issues

### 1. Feature Shape Mismatch

**Error:**
```
ValueError: Feature shape mismatch, expected: 23, got 22
```

**Location:** When SHAP Explainer calls `model_predict()` with masked inputs

**Root Cause:**
- Model expects 23 features (V4.2.0 with `age_bucket_encoded`)
- SHAP is providing 22 features (missing one)
- Likely issue in how features are prepared or passed to the prediction wrapper

**Investigation Needed:**
- Check if `self.feature_list` has all 23 features
- Verify feature preparation in `prepare_features()`
- Ensure SHAP's masking doesn't drop features

### 2. base_score Still Not Fixed in Model

**Status:** The model's internal base_score remains as `'[5E-1]'` string

**Impact:**
- TreeExplainer cannot be used (primary method)
- Must use Explainer fallback (slower, but works once feature issue is fixed)

**Why it persists:**
- XGBoost's internal C++ structure can't be easily modified after model creation
- `load_config()` doesn't actually update the internal state
- Would require retraining model with explicit `base_score=0.5` parameter

---

## Files Modified

### Created
- `v4/scripts/convert_model_to_json.py` - Model conversion script
- `v4/models/v4.2.0/model.json` - JSON format model (still has base_score issue)
- `v4/models/v4.2.0/model_backup.pkl` - Backup of original pickle

### Updated
- `v4/inference/lead_scorer_v4.py`:
  - Updated `_load_model()` to prefer JSON format
  - Added Explainer fallback in `_init_shap_explainer()`
  - Added `shap_available` flag
  - Updated error handling for base_score issues

- `v4/training/train_v42_age_feature.py`:
  - Updated to save as JSON format (primary)
  - Still saves pickle as `model_legacy.pkl` for backward compatibility

---

## Next Steps

### Immediate (To Fix Feature Mismatch)

1. **Debug Feature Preparation:**
   ```python
   # In get_shap_narrative(), verify:
   print(f"Feature list length: {len(self.feature_list)}")
   print(f"X_prep shape: {X_prep.shape}")
   print(f"Features: {self.feature_list}")
   ```

2. **Check Feature List Loading:**
   - Verify `FEATURES_V42` has all 23 features
   - Check if `_load_features()` is correctly loading all features
   - Ensure `age_bucket_encoded` is included

3. **Fix Prediction Wrapper:**
   - Ensure all 23 features are passed to model
   - Handle feature ordering correctly
   - Verify SHAP's masking doesn't drop features

### Long-term (To Fix base_score Permanently)

1. **Retrain Model with Explicit base_score:**
   ```python
   # In training script, add:
   model = xgb.XGBClassifier(
       base_score=0.5,  # Explicitly set
       ...
   )
   ```

2. **Verify After Training:**
   ```python
   # Check base_score after training
   config = json.loads(model.get_booster().save_config())
   base_score = config['learner']['learner_model_param']['base_score']
   assert base_score == '0.5' or base_score == 0.5
   ```

3. **Update Training Documentation:**
   - Document that `base_score=0.5` must be explicitly set
   - Add validation check in training script
   - Update model registry with base_score value

---

## Workaround Status

**Current Workaround:** ✅ **Functional (with feature fix needed)**

- Explainer fallback successfully bypasses base_score issue
- Can generate SHAP values once feature shape is fixed
- Slower than TreeExplainer but acceptable for production

**To Complete:**
- Fix feature shape mismatch (expected 23, got 22)
- Test end-to-end narrative generation
- Verify performance is acceptable

---

## Key Learnings

1. **XGBoost Serialization Quirks:**
   - Pickle format can serialize base_score incorrectly
   - JSON format doesn't automatically fix it
   - Internal C++ state can't be easily modified post-creation

2. **SHAP Compatibility:**
   - TreeExplainer requires perfect model format compatibility
   - Explainer is more flexible but slower
   - Prediction wrappers can bypass format issues

3. **Best Practices:**
   - Always set `base_score=0.5` explicitly during training
   - Save models in JSON format (cleaner, more portable)
   - Keep pickle as backup for backward compatibility
   - Test SHAP initialization immediately after training

---

## References

- XGBoost Documentation: Model Serialization
- SHAP Documentation: TreeExplainer vs Explainer
- Issue: `base_score` serialization bug in XGBoost pickle format
- Related: SHAP TreeExplainer base_score parsing

---

**Last Updated:** January 7, 2026  
**Status:** ✅ **RESOLVED** - Switched to gain-based narratives (working in production)

---

## Final Solution: Gain-Based Narratives

**Decision:** Instead of continuing to fight the SHAP base_score bug, we implemented gain-based narratives using XGBoost's native feature importance.

### Implementation

1. **Removed all SHAP code** from `v4/inference/lead_scorer_v4.py`
2. **Implemented gain-based narrative generation** using:
   - Feature importance from `feature_importance.csv` (or computed from model)
   - Feature values for each lead
   - Logic to identify "notable" features (high importance + notable values)
3. **Created human-readable labels** for all 23 features
4. **Tested and verified** with `v4/scripts/test_gain_narratives.py`

### Benefits

- ✅ **Works immediately** - No base_score issues
- ✅ **Fast** - No SHAP computation overhead
- ✅ **Deterministic** - Same lead always gets same narrative
- ✅ **Meaningful** - Highlights top 3 notable features per lead
- ✅ **Production-ready** - Tested and working

### Trade-offs

- ⚠️ **Global importance** - Uses model-wide feature importance, not per-lead SHAP values
- ⚠️ **Less precise** - Doesn't show exact contribution of each feature to the score
- ✅ **Still useful** - Provides meaningful context about why a lead scored high/low

### Example Output

```
Score: 0.6543 (Percentile: 85.2)
Narrative: Key factors: Tenure Category (Down), Recent Mobility (Up (mobile)), Firm Net Change (Down (bleeding))
Top 1: Tenure Category = 1
Top 2: Recent Mobility = 2
Top 3: Firm Net Change = -7
```

### Files Updated

- `v4/inference/lead_scorer_v4.py` - Complete rewrite with gain-based narratives
- `v4/scripts/test_gain_narratives.py` - Test script (all tests passing)

### Future: SHAP for V4.3.0+

When retraining future models, ensure:
```python
model = xgb.XGBClassifier(base_score=0.5, ...)  # Explicit float
# Test SHAP before saving
explainer = shap.TreeExplainer(model)  # Should work
```

Then we can switch back to SHAP for per-lead importance if desired.
