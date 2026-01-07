# Cursor.ai Prompt: V4.2.0 Age Feature Retraining

Copy and paste this into Cursor.ai to execute the V4.2.0 retraining with age bucket feature.

---

```
# V4.2.0 Model Retraining - Age Bucket Feature Addition

## Context
We're adding `age_bucket_encoded` as the 23rd feature to V4.1.0 (currently 22 features). Analysis showed:
- Age correlation with experience_years = 0.072 (not redundant)
- Age provides unique conversion signal not captured by V4.1.0

## Critical: Validation Gates
DO NOT deploy V4.2.0 if any gate fails:
- G1: Test AUC ≥ 0.620 (V4.1.0 baseline)
- G2: Top Decile Lift ≥ 2.03x (V4.1.0 baseline)
- G3: Overfitting Gap < 0.15
- G4: Age feature importance > 0 (warning only)

## Instructions

Follow the guide in `V4.2.0_AGE_FEATURE_RETRAINING_GUIDE.md` exactly.

### Phase 1: Feature Engineering (BigQuery)

1. Run the SQL to update `v4_prospect_features` view with age_bucket_encoded
2. Run the SQL to create `v4_features_pit_v42` training table
3. Verify both with the verification queries provided

### Phase 2: Model Training (Python)

1. Create directories:
   - `v4/models/v4.2.0/`
   - `v4/reports/v4.2/`

2. Create the training script at `v4/training/train_v42_age_feature.py` using the code in the guide

3. Run the training script:
   ```bash
   python v4/training/train_v42_age_feature.py
   ```

4. Record all metrics from the output

### Phase 3: Validation Decision

Fill in this table with actual results:

| Gate | Criterion | V4.1.0 | V4.2.0 | Passed? |
|------|-----------|--------|--------|---------|
| G1 | Test AUC ≥ 0.620 | 0.620 | [?] | [?] |
| G2 | Lift ≥ 2.03x | 2.03x | [?] | [?] |
| G3 | Overfit < 0.15 | 0.075 | [?] | [?] |
| G4 | Age Imp > 0 | N/A | [?] | [?] |

**DECISION:**
- If ALL gates pass → Proceed to Phase 4
- If ANY gate fails → STOP. Keep V4.1.0. Document findings.

### Phase 4: Deployment (Only If Gates Pass)

1. Update `v4_prospect_scores` table with new model scores
2. Update inference script `v4/inference/lead_scorer_v4.py`
3. Create backup of V4.1.0 scores

### Phase 5: Documentation Updates

Update these files with actual results:

1. `v4/models/registry.json` - Add V4.2.0 entry
2. `v4/VERSION_4_MODEL_REPORT.md` - Add V4.2.0 section
3. `v4/reports/v4.2/V4.2_Final_Summary.md` - Create with results
4. `v4/reports/v4.2/model_validation_report.md` - Create with results

### Output Required

After completing, provide:

1. **Gate Results Table** - Filled in with actual values
2. **GO/NO-GO Decision** - Clear statement
3. **If GO**: List of all files created/updated
4. **If NO-GO**: Explanation of why age feature doesn't help

## Files Reference

The complete guide with all SQL, Python code, and templates is in:
`V4.2.0_AGE_FEATURE_RETRAINING_GUIDE.md`

## BigQuery Connection
Project: `savvy-gtm-analytics`
Dataset: `ml_features`

Begin by verifying BigQuery connection, then proceed through phases sequentially.
```

---

## Quick Reference: Expected Outcomes

### If V4.2.0 IMPROVES model:

```
Gate Results:
- G1: Test AUC = 0.63+ (≥ 0.620) ✅
- G2: Top Decile = 2.1x+ (≥ 2.03x) ✅
- G3: Overfit = 0.08 (< 0.15) ✅
- G4: Age Importance = 0.02+ (> 0) ✅

Decision: DEPLOY V4.2.0
```

### If V4.2.0 DOES NOT improve model:

```
Gate Results:
- G1: Test AUC = 0.615 (< 0.620) ❌
- G2: Top Decile = 1.95x (< 2.03x) ❌

Decision: DO NOT DEPLOY
Keep V4.1.0 in production.
Age feature does not improve model - likely because:
1. V4 already captures age signal through experience_years correlation
2. Age effect is already in the bleeding/mobility features
3. Sample size in 65+ bucket too small to learn from
```
