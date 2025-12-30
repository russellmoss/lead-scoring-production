# V4.1 Overfitting Detection Report

**Generated**: 2025-12-30 13:15:50  
**Status**: FAILED - OVERFITTING DETECTED

## Executive Summary

This report analyzes overfitting indicators for the V4.1 XGBoost model.
Overfitting occurs when a model performs well on training data but poorly on test data,
indicating it has memorized training patterns rather than learning generalizable rules.

## Performance Metrics

| Metric | Train | Test | Gap | Threshold | Status |
|--------|-------|------|-----|-----------|--------|
| AUC-ROC | 0.9461 | 0.5610 | 0.3851 | < 0.05 | [FAIL] |
| Top Decile Lift | 8.13x | 1.50x | 6.63x | < 0.5x | [FAIL] |
| AUC-PR (Train) | 0.3425 | 0.0566 | - | - | - |

## Cross-Validation Results

- **Mean AUC**: 0.6412
- **Std AUC**: 0.0155
- **Threshold**: std < 0.03
- **Status**: [PASS] Stable

## Validation Gates

### G8.1: Train-Test AUC gap < 0.05
**Status**: [FAIL] FAILED

- Train AUC: 0.9461
- Test AUC: 0.5610
- Gap: 0.3851
- Threshold: < 0.05

**⚠️ CRITICAL**: Large AUC gap indicates significant overfitting. Model is memorizing training patterns.

### G8.2: Train-Test top decile lift gap < 0.5x
**Status**: [FAIL] FAILED

- Train top decile lift: 8.13x
- Test top decile lift: 1.50x
- Gap: 6.63x
- Threshold: < 0.5x

### G8.3: Cross-validation AUC std < 0.03
**Status**: [PASS] PASSED

- CV mean AUC: 0.6412
- CV std AUC: 0.0155
- Threshold: std < 0.03

### G8.4: Test AUC > 0.58 (meaningful signal)
**Status**: [FAIL] FAILED

- Test AUC: 0.5610
- Threshold: > 0.58
- V4.0.0 baseline: 0.599

**⚠️ CRITICAL**: Test AUC is below threshold and below V4.0.0 baseline. Model may not be ready for deployment.

## Lift Analysis by Decile

### Train Set
 decile  conv_rate  conversions  count      lift
      0        0.0            0   2474       0.0
      1        0.0            0   2473       0.0
      2        0.0            0   2473       0.0
      3        0.0            0   2474       0.0
      4   0.000404            1   2473  0.016981
      5   0.002425            6   2474  0.101843
      6   0.006066           15   2473   0.25471
      7     0.0093           23   2473  0.390556
      8   0.026284           65   2473  1.103744
      9   0.193614          479   2474  8.130456

### Test Set
 decile  conv_rate  conversions  count      lift
      0   0.035294           12    340  0.900398
      1    0.02924           10    342  0.745944
      2   0.029412           10    340  0.750332
      3    0.01791            6    335  0.456918
      4   0.044118           15    340  1.125498
      5   0.041298           14    339  1.053563
      6   0.041298           14    339  1.053563
      7   0.056047           19    339  1.429836
      8   0.038348           13    339  0.978309
      9   0.058824           20    340  1.500663

## Recommendations

### Overfitting Detected (G8.1 Failed)

**Issue**: Large train-test AUC gap (0.3851) indicates significant overfitting.

**Recommended Actions**:
1. **Increase regularization**:
   - Increase `reg_alpha` from 0.1 to 0.3
   - Increase `reg_lambda` from 1.0 to 2.0
   
2. **Reduce learning rate**:
   - Decrease `learning_rate` from 0.05 to 0.03
   - Increase `n_estimators` to 800 to compensate
   
3. **Increase early stopping**:
   - Increase `early_stopping_rounds` from 50 to 100
   
4. **Reduce model complexity**:
   - Decrease `max_depth` from 4 to 3
   - Increase `min_child_weight` from 10 to 15

### Low Test Performance (G8.4 Failed)

**Issue**: Test AUC (0.5610) is below threshold (0.58) and below V4.0.0 baseline (0.599).

**Recommended Actions**:
1. Review feature engineering - may need additional features
2. Check for data quality issues
3. Consider ensemble methods
4. Retrain with adjusted hyperparameters (see G8.1 recommendations)


## Conclusion

⚠️ Overfitting detected. Review recommendations above and consider retraining with adjusted hyperparameters.
