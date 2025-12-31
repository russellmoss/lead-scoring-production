# Phase 3: Ablation Study - Results

**Date**: 2025-12-30  
**Status**: ✅ Complete

---

## Summary

**Baseline Model Performance**:
- **AUC-ROC**: 0.6277
- **PR-AUC**: 0.0514
- **Top Decile Lift**: 2.05x
- **Features**: 22 (V4.1 baseline)

**Key Finding**: ❌ **Both promising features from Phase 2 degrade model performance when added**

---

## Ablation Study Results

| Model | Features | AUC-ROC | PR-AUC | Lift | AUC Δ | Lift Δ | Recommendation |
|-------|----------|---------|--------|------|-------|--------|----------------|
| **BASELINE** | 22 | 0.6277 | 0.0514 | 2.05x | - | - | BASELINE |
| + firm_aum_bucket | 23 | 0.6273 | 0.0502 | 1.72x | -0.0004 | -0.34 | ❌ HARMFUL |
| + has_accolade | 23 | 0.6231 | 0.0478 | 1.86x | -0.0046 | -0.19 | ❌ HARMFUL |
| + combined_promising | 24 | 0.6275 | 0.0507 | 1.73x | -0.0001 | -0.32 | ❌ HARMFUL |

---

## Analysis

### Why Features Degrade Performance

1. **Redundancy with Existing Features**
   - `firm_aum_bucket` may be correlated with existing firm stability features (`firm_net_change_12mo`, `firm_stability_tier`)
   - `has_accolade` may overlap with experience/tenure signals already captured

2. **Overfitting Risk**
   - Adding features to an already well-regularized model (V4.1 R3) can introduce noise
   - The model may be using these features in ways that hurt generalization

3. **Low Coverage Impact**
   - `has_accolade` has only 4.5% coverage, which may cause instability
   - When combined with other features, the signal-to-noise ratio decreases

4. **Univariate vs Multivariate Signal**
   - Univariate analysis shows signal in isolation
   - In a multivariate model, the signal may be redundant or conflicting with existing features

---

## Validation Gates

| Gate | Criterion | Result | Status |
|------|-----------|--------|--------|
| **G-NEW-1** | AUC improvement ≥ 0.005 | Best: -0.0001 | ❌ FAILED |
| **G-NEW-2** | Lift improvement ≥ 0.1x | Best: -0.32 | ❌ FAILED |

**All candidate features FAIL both gates**

---

## Recommendations

### ❌ DO NOT DEPLOY

**Reason**: Both features degrade model performance:
- AUC decreases (fails G-NEW-1)
- Lift decreases significantly (fails G-NEW-2)
- PR-AUC also decreases

### Next Steps

1. **Document Findings**: Archive these features as "tested but not beneficial"
2. **Investigate Redundancy**: Analyze correlation between candidate features and existing V4.1 features
3. **Consider Alternative Features**: Review weak features from Phase 2 that might work better in combination
4. **Feature Engineering**: Consider interaction features or different transformations

### Alternative Approaches

1. **Interaction Features**: Test `firm_aum_bucket` × `firm_stability_tier` instead of standalone
2. **Different Transformations**: Try `log_firm_aum` with different bucketing strategy
3. **Ensemble Approach**: Use `has_accolade` as a post-model filter rather than a feature

---

## Key Learnings

1. **Univariate signal ≠ Multivariate value**: Features that show promise in isolation may not improve the full model
2. **Model context matters**: V4.1 R3 is already well-optimized, making marginal improvements harder
3. **Regularization impact**: Strong regularization (V4.1 R3) may prevent new features from adding value
4. **Coverage matters**: Low-coverage features (`has_accolade` at 4.5%) can cause instability

---

## Files Generated

- `v5/experiments/reports/ablation_study_results.csv` - Detailed ablation study results
- `v5/experiments/reports/PHASE3_RESULTS.md` - This summary report

---

## Conclusion

**Status**: ❌ **Enhancement NOT Recommended**

The ablation study demonstrates that the promising features from Phase 2 do not improve model performance when added to the V4.1 baseline. Both features degrade AUC and lift, indicating they should **not** be deployed to production.

This is a valid outcome - not all promising univariate signals translate to model improvements. The validation framework successfully identified that these features would harm performance before any production deployment.

