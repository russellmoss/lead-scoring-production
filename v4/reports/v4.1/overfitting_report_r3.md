# V4.1 R3 Overfitting Detection Report

**Generated**: 2025-12-30 13:31:48  
**Status**: FAILED - OVERFITTING DETECTED  
**Model Version**: v4.1.0_r3 (Feature Selection + Stronger Regularization)

## Executive Summary

This report analyzes overfitting indicators for the V4.1 R3 XGBoost model.
R3 was retrained with:
1. Feature selection (22 features, removed 4 redundant)
2. Even stronger regularization
3. Shallower trees (max_depth=2) and lower learning rate (0.01)


## Comparison to R1 and R2

| Metric | R1 | R2 | R3 | Change (R2->R3) | Status |
|--------|----|----|----|-----------------|--------|
| Features | 26 | 26 | 22 | -4 | Reduced |
| Test AUC | 0.5610 | 0.5822 | 0.6198 | +0.0377 | IMPROVED |
| AUC Gap | 0.3851 | 0.2723 | 0.0746 | -0.1976 | IMPROVED |
| Test Top Decile Lift | 1.50x | 1.28x | 2.03x | +0.75x | IMPROVED |
| Lift Gap | 6.63x | 3.83x | 0.62x | -3.21x | IMPROVED |
| CV Mean AUC | 0.6412 | 0.6480 | 0.6459 | -0.0021 | WORSE |
| Early Stop Iteration | 498 | 996 | 223 | -773 | IMPROVED |


## Performance Metrics

| Metric | Train | Test | Gap | Threshold | Status |
|--------|-------|------|-----|-----------|--------|
| AUC-ROC | 0.6945 | 0.6198 | 0.0746 | < 0.05 | [FAIL] |
| Top Decile Lift | 2.65x | 2.03x | 0.62x | < 0.5x | [FAIL] |
| AUC-PR (Train) | 0.0598 | 0.0697 | - | - | - |

## Cross-Validation Results

- **Mean AUC**: 0.6459
- **Std AUC**: 0.0082
- **Threshold**: std < 0.03
- **Status**: [PASS] Stable

## Validation Gates

### G8.1: Train-Test AUC gap < 0.05
**Status**: [FAIL] FAILED

- Train AUC: 0.6945
- Test AUC: 0.6198
- Gap: 0.0746
- Threshold: < 0.05

**WARNING**: Large AUC gap indicates significant overfitting. Model is memorizing training patterns.

### G8.2: Train-Test top decile lift gap < 0.5x
**Status**: [FAIL] FAILED

- Train top decile lift: 2.65x
- Test top decile lift: 2.03x
- Gap: 0.62x
- Threshold: < 0.5x

### G8.3: Cross-validation AUC std < 0.03
**Status**: [PASS] PASSED

- CV mean AUC: 0.6459
- CV std AUC: 0.0082
- Threshold: std < 0.03

### G8.4: Test AUC > 0.58 (meaningful signal)
**Status**: [PASS] PASSED

- Test AUC: 0.6198
- Threshold: > 0.58
- V4.0.0 baseline: 0.599

**SUCCESS**: Test AUC exceeds threshold AND V4.0.0 baseline. Model is ready for deployment consideration.

## Recommendations

### Some Gates Failed

**Issue**: Some validation gates did not pass strict thresholds.

**Recommended Actions**:
1. Review which gates failed and why
2. Consider if relaxed thresholds are acceptable for deployment
3. Document limitations and proceed to Phase 9 for full validation


## Conclusion

PARTIAL: Some gates passed, some failed. Review recommendations above.
