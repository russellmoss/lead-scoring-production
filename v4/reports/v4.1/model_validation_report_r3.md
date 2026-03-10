# V4.1 R3 Model Validation Report

**Generated**: 2025-12-30 13:41:12  
**Model Version**: v4.1.0_r3  
**Status**: ✅ PASSED - READY FOR DEPLOYMENT

## Executive Summary

This report validates the performance of the V4.1 R3 model and compares it to the V4.0.0 baseline.
R3 was trained with feature selection (22 features) and stronger regularization to address overfitting.


| Metric | V4.0.0 Baseline | V4.1 R3 | Change | Status |
|--------|-----------------|---------|--------|--------|
| Test AUC-ROC | 0.5989 | 0.6198 | +0.0210 | ✅ Improved |
| Test AUC-PR | 0.0432 | 0.0697 | +0.0264 | ✅ Improved |
| Top Decile Lift | 1.51x | 2.03x | +0.52x | ✅ Improved |
| Test Conv Rate | 3.20% | 3.92% | +0.72% | - |


## Performance Metrics

### AUC Metrics

- **AUC-ROC**: 0.6198 (Target: ≥ 0.58, Baseline: 0.5989)
- **AUC-PR**: 0.0697 (Baseline: 0.0432)

### Lift Analysis

- **Top Decile Lift**: 2.03x (Target: ≥ 1.4x, Baseline: 1.51x)
- **Bottom 20% Conversion Rate**: 1.40% (Target: < 2%)
- **Baseline Conversion Rate**: 3.92%

### Test Set Summary

- **Total Rows**: 3,393
- **Conversions**: 133
- **Conversion Rate**: 3.92%

## Lift by Decile

| Decile | Avg Score | Conversions | Count | Conv Rate | Lift |
|--------|-----------|-------------|-------|------------|------|
| 0 | 0.3306 | 4 | 404 | 0.99% | 0.25x |
| 1 | 0.3791 | 5 | 275 | 1.82% | 0.46x |
| 2 | 0.4015 | 11 | 339 | 3.24% | 0.83x |
| 3 | 0.4443 | 13 | 339 | 3.83% | 0.98x |
| 4 | 0.4720 | 21 | 340 | 6.18% | 1.58x |
| 5 | 0.4968 | 10 | 339 | 2.95% | 0.75x |
| 6 | 0.5196 | 12 | 339 | 3.54% | 0.90x |
| 7 | 0.5390 | 9 | 339 | 2.65% | 0.68x |
| 8 | 0.5662 | 21 | 339 | 6.19% | 1.58x |
| 9 | 0.6193 | 27 | 340 | 7.94% | 2.03x |

## Precision-Recall at Thresholds

| Threshold | Precision | Recall | TP | FP | FN |
|-----------|-----------|--------|----|----|----|
| 0.01 | 0.0392 | 1.0000 | 133.0 | 3260.0 | 0.0 |
| 0.02 | 0.0392 | 1.0000 | 133.0 | 3260.0 | 0.0 |
| 0.03 | 0.0392 | 1.0000 | 133.0 | 3260.0 | 0.0 |
| 0.05 | 0.0392 | 1.0000 | 133.0 | 3260.0 | 0.0 |
| 0.10 | 0.0392 | 1.0000 | 133.0 | 3260.0 | 0.0 |
| 0.20 | 0.0392 | 1.0000 | 133.0 | 3260.0 | 0.0 |
| 0.30 | 0.0395 | 1.0000 | 133.0 | 3233.0 | 0.0 |
| 0.50 | 0.0506 | 0.5639 | 75.0 | 1408.0 | 58.0 |

## Validation Gates

### G9.1: Test AUC-ROC >= 0.58
**Status**: ✅ PASSED

- Test AUC-ROC: 0.6198
- Threshold: ≥ 0.58

### G9.2: Top Decile Lift >= 1.4x
**Status**: ✅ PASSED

- Top Decile Lift: 2.03x
- Threshold: ≥ 1.4x

### G9.3: V4.1 AUC >= V4.0.0 AUC (Improvement)
**Status**: ✅ PASSED

- V4.1 R3 AUC: 0.6198
- V4.0.0 Baseline AUC: 0.5989
- Improvement: +0.0210

**✅ SUCCESS**: V4.1 R3 exceeds V4.0.0 baseline.

### G9.4: Bottom 20% Conversion Rate < 2%
**Status**: ✅ PASSED

- Bottom 20% Conversion Rate: 1.40%
- Threshold: < 2%

## Recommendation

✅ **PROCEED TO DEPLOYMENT** - All validation gates passed.

The V4.1 R3 model:
- Exceeds V4.0.0 baseline performance
- Shows strong predictive signal (AUC-ROC = 0.6198)
- Demonstrates effective lift (top decile = 2.03x)
- Effectively deprioritizes low-value leads (bottom 20% < 2%)

**Next Steps:**
1. Proceed to Phase 10: SHAP Analysis
2. Prepare deployment artifacts
3. Update model registry
