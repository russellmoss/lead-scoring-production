# Phase 4: Multi-Period Backtesting - Results

**Date**: 2025-12-30  
**Status**: ✅ Complete

---

## Summary

**Periods Tested**: 4  
**Periods Improved**: 1/4  
**Gate G-NEW-4**: ❌ **FAILED** (requires ≥ 3/4 periods)

---

## Period-by-Period Results

| Period | Train Rows | Test Rows | Baseline AUC | Enhanced AUC | AUC Δ | Baseline Lift | Enhanced Lift | Lift Δ | Improved |
|--------|------------|-----------|--------------|--------------|-------|---------------|---------------|--------|----------|
| **Period 1: Feb-May 2024** | 1,310 | 2,133 | 0.5883 | 0.5654 | -0.0229 | 0.81x | 0.81x | +0.00x | ❌ NO |
| **Period 2: Feb-Jul 2024** | 3,443 | 3,161 | 0.6356 | 0.6332 | -0.0024 | 2.20x | 2.20x | +0.00x | ❌ NO |
| **Period 3: Feb-Sep 2024** | 6,604 | 5,810 | 0.6970 | 0.7031 | +0.0062 | 2.50x | 2.78x | +0.28x | ✅ YES |
| **Period 4: Feb 2024-Mar 2025** | 15,591 | 4,076 | 0.5517 | 0.5503 | -0.0013 | 1.50x | 1.65x | +0.15x | ❌ NO |

---

## Analysis

### Temporal Stability Assessment

**Only 1 out of 4 periods showed improvement**, which fails the G-NEW-4 gate requirement of ≥ 3/4 periods.

**Key Observations**:
- **Period 3** showed improvement (+0.0062 AUC, +0.28x lift), but this is the exception
- **Periods 1, 2, and 4** all showed degradation or no improvement
- The improvement in Period 3 may be due to:
  - Sample size differences (larger train/test sets)
  - Temporal data quality variations
  - Random variation rather than true signal

### Consistency Analysis

The features show **inconsistent performance across time periods**, which is a red flag for deployment:
- Performance varies significantly by period
- No clear pattern of improvement
- Degradation in 3 out of 4 periods

---

## Validation Gates

| Gate | Criterion | Result | Status |
|------|-----------|--------|--------|
| **G-NEW-4** | Improvement in ≥ 3/4 periods | 1/4 periods improved | ❌ FAILED |

---

## Conclusion

**Temporal Stability**: ❌ **FAILED**

The multi-period backtest confirms that the candidate features do not provide consistent improvement across different time periods. This reinforces the Phase 3 finding that these features degrade overall model performance.

---

## Files Generated

- `v5/experiments/reports/multi_period_backtest_results.csv` - Detailed period-by-period results
- `v5/experiments/reports/PHASE4_RESULTS.md` - This summary report

