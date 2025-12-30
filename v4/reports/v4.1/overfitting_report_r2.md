# V4.1 R2 Overfitting Detection Report

**Generated**: 2025-12-30 13:23:30  
**Status**: FAILED - OVERFITTING DETECTED  
**Model Version**: v4.1.0_r2 (Retrained with stronger regularization)

## Executive Summary

This report analyzes overfitting indicators for the V4.1 R2 XGBoost model.
R2 was retrained with stronger regularization to address overfitting detected in R1.


## Comparison to R1

| Metric | R1 | R2 | Change | Status |
|--------|----|----|--------|--------|
| Test AUC | 0.5610 | 0.5822 | +0.0212 | IMPROVED |
| AUC Gap | 0.3851 | 0.2723 | -0.1128 | IMPROVED |
| Test Top Decile Lift | 1.50x | 1.28x | -0.23x | WORSE |
| Lift Gap | 6.63x | 3.83x | -2.80x | IMPROVED |
| CV Mean AUC | 0.6412 | 0.6480 | +0.0068 | IMPROVED |


## Performance Metrics

| Metric | Train | Test | Gap | Threshold | Status |
|--------|-------|------|-----|-----------|--------|
| AUC-ROC | 0.8544 | 0.5822 | 0.2723 | < 0.05 | [FAIL] |
| Top Decile Lift | 5.11x | 1.28x | 3.83x | < 0.5x | [FAIL] |
| AUC-PR (Train) | 0.1362 | 0.0577 | - | - | - |

## Cross-Validation Results

- **Mean AUC**: 0.6480
- **Std AUC**: 0.0100
- **Threshold**: std < 0.03
- **Status**: [PASS] Stable

## Validation Gates

### G8.1: Train-Test AUC gap < 0.05
**Status**: [FAIL] FAILED

- Train AUC: 0.8544
- Test AUC: 0.5822
- Gap: 0.2723
- Threshold: < 0.05

**WARNING**: Large AUC gap indicates significant overfitting. Model is memorizing training patterns.

### G8.2: Train-Test top decile lift gap < 0.5x
**Status**: [FAIL] FAILED

- Train top decile lift: 5.11x
- Test top decile lift: 1.28x
- Gap: 3.83x
- Threshold: < 0.5x

### G8.3: Cross-validation AUC std < 0.03
**Status**: [PASS] PASSED

- CV mean AUC: 0.6480
- CV std AUC: 0.0100
- Threshold: std < 0.03

### G8.4: Test AUC > 0.58 (meaningful signal)
**Status**: [PASS] PASSED

- Test AUC: 0.5822
- Threshold: > 0.58
- V4.0.0 baseline: 0.599



## Recommendations

### Overfitting Still Detected (G8.1 Failed)

**Issue**: Large train-test AUC gap (0.2723) indicates significant overfitting persists.

**Recommended Actions**:
1. **Even stronger regularization**:
   - Increase `reg_alpha` from 0.5 to 1.0
   - Increase `reg_lambda` from 3.0 to 5.0
   
2. **Further reduce learning rate**:
   - Decrease `learning_rate` from 0.02 to 0.01
   - Increase `n_estimators` to 1500 to compensate
   
3. **Reduce model complexity further**:
   - Decrease `max_depth` from 3 to 2
   - Increase `min_child_weight` from 20 to 30

4. **Consider feature selection**:
   - Remove redundant features identified in Phase 5
   - Focus on top features by importance


## Conclusion

FAILED: Overfitting detected. Review recommendations above and consider retraining with adjusted hyperparameters.
