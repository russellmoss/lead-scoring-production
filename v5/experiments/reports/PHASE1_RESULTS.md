# Phase 1: Feature Candidate Creation - Results

**Date**: 2025-12-30  
**Status**: ✅ Complete

---

## Table Created

**Table**: `savvy-gtm-analytics.ml_experiments.feature_candidates_v5`  
**Rows**: 285,690  
**Size**: 102.5 MB  
**Unique Advisors**: 285,690 (one row per advisor)

---

## Feature Coverage Summary

| Feature Category | Coverage | Count | Status |
|-----------------|----------|-------|--------|
| **Firm AUM** | 87.76% | 250,731 | ✅ Excellent |
| **Accolades** | 4.5% | 12,851 | ⚠️ Low (expected) |
| **Custodians** | 64.37% | 183,893 | ✅ Good |
| **Disclosures** | 17.89% | 51,110 | ✅ Acceptable |
| **Licenses** | 100% | 285,690 | ✅ Perfect |

---

## Validation Gates

| Gate | Criterion | Result | Status |
|------|-----------|--------|--------|
| **G1.1** | Row count matches unique advisors | 285,690 = 285,690 | ✅ PASSED |
| **G1.2** | AUM coverage > 80% | 87.76% | ✅ PASSED |
| **G1.3** | Licenses coverage = 100% | 100% | ✅ PASSED |

---

## Issues Resolved

1. **Dataset Location Mismatch**
   - Issue: `ml_experiments` in `northamerica-northeast2`, `FinTrx_data` in `US`
   - Solution: Updated SQL to use `FinTrx_data_CA` (same location)

2. **Deduplication**
   - Issue: Initial query created 637M rows (duplicates)
   - Solution: Added `QUALIFY ROW_NUMBER() OVER (PARTITION BY crd ORDER BY prediction_date DESC, created_at DESC) = 1` to base_features CTE

3. **Column Name Mismatch**
   - Issue: SQL referenced `tenure_bucket_encoded`, `mobility_tier_encoded`, `firm_stability_tier_encoded`
   - Solution: Updated to use `tenure_bucket`, `mobility_tier`, `firm_stability_tier` (actual column names)

---

## Next Steps

Proceed to **Phase 2: Univariate Analysis** to evaluate individual candidate features.

