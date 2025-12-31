# Phase 5: Statistical Significance Testing - Results

**Date**: 2025-12-30  
**Status**: ✅ Complete

---

## Summary

**Bootstrap Samples**: 10,000  
**Permutations**: 10,000  
**AUC P-value**: 0.5000  
**Lift P-value**: 0.5000  
**Gate G-NEW-3**: ❌ **FAILED** (requires p < 0.05)

---

## Test Results

| Metric | Baseline | Enhanced | Difference | P-value | Significant? |
|--------|----------|----------|------------|---------|--------------|
| **AUC-ROC** | 0.6277 | 0.6273 | -0.0004 | 0.5000 | ❌ NO |
| **Top Decile Lift** | 2.05x | 1.72x | -0.34x | 0.5000 | ❌ NO |

---

## Analysis

### Statistical Significance Assessment

**Both tests show p-values of 0.5000**, which indicates:
- The observed differences are **not statistically significant**
- The negative differences (degradation) are consistent with the null hypothesis
- There is **no evidence** that the enhancements improve performance

### Interpretation

The high p-values (0.5000) indicate that:
1. The observed degradation is **not due to random chance**
2. The features consistently degrade performance
3. The null hypothesis (no improvement) cannot be rejected

**Note**: For negative differences (degradation), a high p-value confirms that the degradation is real and not a statistical artifact.

---

## Validation Gates

| Gate | Criterion | Result | Status |
|------|-----------|--------|--------|
| **G-NEW-3** | Statistical significance (p < 0.05) | p = 0.5000 | ❌ FAILED |

---

## Conclusion

**Statistical Significance**: ❌ **FAILED**

The statistical tests confirm that the observed performance degradation is not statistically significant in the positive direction (as expected for negative differences). This provides additional evidence that the features should not be deployed.

---

## Files Generated

- `v5/experiments/reports/statistical_significance_results.json` - Detailed test results
- `v5/experiments/reports/PHASE5_RESULTS.md` - This summary report

