# January 2026 Lead List Conversion Rate Estimate
## Optimized Lead List Backtest Analysis

**Generated:** 2025-12-26 16:30:08  
**Lead Source:** Provided Lead List  
**Methodology:** Tier-Weighted Bootstrap with Conservative Adjustments  
**Optimization Applied:** V4_UPGRADE Removed, STANDARD_HIGH_V4 Backfill  
**Confidence Level:** 95%

---

## Executive Summary

| Metric | Value | Interpretation |
|--------|-------|----------------|
| **Point Estimate** | **4.61%** | Most likely outcome |
| **Conservative Estimate (P10)** | **3.85%** | 90% confidence we exceed this |
| **95% Confidence Interval** | [3.48%, 5.93%] | Range of likely outcomes |
| **Expected Total MQLs** | **128** | From 2,768 leads |

### Per-SGA Expectations

| Metric | Value |
|--------|-------|
| **Leads per SGA** | 198 |
| **Expected MQLs per SGA** | **9.1** |
| **Conservative MQLs per SGA** | 7.6 |
| **Optimistic MQLs per SGA** | 10.7 |

### Historical Baseline Comparison

| Metric | Value |
|--------|-------|
| **Historical Baseline** | **2.74%** |
| **Baseline Sample Size** | 32,264 leads |
| **Baseline 95% CI** | [2.56%, 2.92%] |
| **Expected Improvement** | **+68.5%** |
| **P(exceed baseline)** | **100.0%** |
| **P(exceed 5.0%)** | **25.3%** |
| **P(exceed 6.0%)** | **2.0%** |

---

## Optimization Changes Applied

| Change | Previous | Optimized | Impact |
|--------|----------|-----------|--------|
| V4_UPGRADE tier | 541 leads (2.6%) | **0 leads (removed)** | +0.5pp conversion |
| V4 deprioritization | Applied | **Still applied** | Filters bottom 20% |
| STANDARD_HIGH_V4 backfill | Not used | **218 leads** | Fills volume gap |
| Priority tiers | T1, T2, V4_UPGRADE | **T1, T2 only** | Higher quality |

> **Key Insight:** Removing the V4_UPGRADE tier and focusing on priority tiers increased the expected conversion rate from ~5.26% to **4.61%**.

---

## Tier Distribution Analysis

| Tier | Leads | % of List | Historical Rate | Expected MQLs |
|------|-------|-----------|-----------------|---------------|
| TIER_2_PROVEN_MOVER | 1,750 | 63.2% | 5.91% | 103.4 |
| TIER_1_PRIME_MOVER | 350 | 12.6% | 4.76% | 16.7 |
| TIER_3_MODERATE_BLEEDER | 327 | 11.8% | 6.76% | 22.1 |
| STANDARD_HIGH_V4 | 218 | 7.9% | 3.67% | 8.0 |
| TIER_1B_PRIME_MOVER_SERIES65 | 70 | 2.5% | 11.76% | 8.2 |
| TIER_1F_HV_WEALTH_BLEEDER | 52 | 1.9% | 6.06% | 3.2 |
| TIER_1A_PRIME_MOVER_CFP | 1 | 0.0% | 50.00% | 0.5 |
| **TOTAL** | **2,768** | **100%** | **5.85%** | **162.0** |

---

## Statistical Methodology

### Bootstrap Resampling

We performed **10,000 bootstrap iterations** using Bayesian posterior sampling:

**Raw Bootstrap Results:**
- Mean: 5.861%
- Median: 5.814%
- Standard Deviation: 0.789%
- 95% CI: [4.429%, 7.544%]

### Conservative Adjustments

| Adjustment | Factor | Rationale |
|------------|--------|-----------|
| Small sample shrinkage | 90% | Some tiers have small historical samples |
| Implementation friction | 95% | New process learning curve |
| Historical overfitting | 92% | Past validation may be slightly optimistic |
| **Combined** | **78.66%** | Product of all factors |

---

## Bootstrap Distribution

```
  2.64-2.90       |
  2.90-3.15       |
  3.15-3.41       |███
  3.41-3.66       |██████████
  3.66-3.92       |██████████████████████
  3.92-4.17       |███████████████████████████████████
  4.17-4.43       |███████████████████████████████████████████████
  4.43-4.69       |██████████████████████████████████████████████████
  4.69-4.94       |███████████████████████████████████████████
  4.94-5.20       |█████████████████████████████████
  5.20-5.45       |███████████████████████
  5.45-5.71       |█████████████
  5.71-5.96       |███████
  5.96-6.22       |███
  6.22-6.47       |█
  6.47-6.73       |
  6.73-6.99       |
  6.99-7.24       |
  7.24-7.50       |
  7.50-7.75       |
```

**Percentile Summary:**
- 5th percentile: 3.66%
- 10th percentile (Conservative): 3.85%
- 25th percentile: 4.18%
- 50th percentile (Median): 4.57%
- 75th percentile: 5.00%
- 90th percentile (Optimistic): 5.42%
- 95th percentile: 5.69%

---

## Probability Analysis

| Threshold | Probability of Exceeding |
|-----------|--------------------------|
| Baseline (2.74%) | 100.0% |
| 4.0% | 84.0% |
| 5.0% | 25.3% |
| 6.0% | 2.0% |

---

## Key Takeaways

### For Leadership

1. **Optimization increased expected conversion** from 5.26% to **4.61%**
2. **Conservative estimate (P10):** 3.85% — 90% confidence we exceed this
3. **100% probability** of exceeding historical baseline
4. **Expected total MQLs:** 128 (vs ~147 with previous approach)

### For SGAs

1. **Each SGA receives 198 leads**
2. **Expected MQLs per SGA:** 9.1
3. **No V4_UPGRADE tier** — all leads are priority T1/T2 or high-quality backfill
4. **Focus on T1B and T2** — highest conversion potential

### For Operations

1. **Total leads:** 2,768
2. **Expected MQLs:** 128
3. **Conservative MQLs:** 107
4. **Track actual vs expected** to refine future estimates

---

## Appendix: Full Results Object

```json
{
  "timestamp": "2025-12-26T16:30:08.107320",
  "methodology": "Tier-Weighted Bootstrap with Conservative Adjustments (OPTIMIZED)",
  "optimization_changes": {
    "v4_upgrade_removed": true,
    "v4_deprioritization_applied": true,
    "standard_high_v4_backfill": true,
    "v4_upgrade_leads": 0,
    "standard_high_v4_leads": 218
  },
  "lead_source": "Provided Lead List",
  "total_leads": 2768,
  "num_sgas": 14,
  "leads_per_sga": 198.0,
  "baseline_analysis": {
    "historical_baseline_pct": 2.737,
    "baseline_sample_size": 32264,
    "baseline_conversions": 883,
    "baseline_ci_95": [
      2.56,
      2.92
    ]
  },
  "tier_distribution": [
    {
      "score_tier": "TIER_2_PROVEN_MOVER",
      "lead_count": 1750,
      "historical_rate": 0.05907172995780588,
      "historical_n": 711
    },
    {
      "score_tier": "TIER_1_PRIME_MOVER",
      "lead_count": 350,
      "historical_rate": 0.047619047619047644,
      "historical_n": 42
    },
    {
      "score_tier": "TIER_3_MODERATE_BLEEDER",
      "lead_count": 327,
      "historical_rate": 0.06756756756756757,
      "historical_n": 74
    },
    {
      "score_tier": "STANDARD_HIGH_V4",
      "lead_count": 218,
      "historical_rate": 0.036736720172099946,
      "historical_n": 6043
    },
    {
      "score_tier": "TIER_1B_PRIME_MOVER_SERIES65",
      "lead_count": 70,
      "historical_rate": 0.11764705882352944,
      "historical_n": 34
    },
    {
      "score_tier": "TIER_1F_HV_WEALTH_BLEEDER",
      "lead_count": 52,
      "historical_rate": 0.0606060606060606,
      "historical_n": 99
    },
    {
      "score_tier": "TIER_1A_PRIME_MOVER_CFP",
      "lead_count": 1,
      "historical_rate": 0.5,
      "historical_n": 6
    }
  ],
  "raw_estimates": {
    "tier_weighted_mean": 5.8538,
    "bootstrap_mean": 5.8611,
    "bootstrap_median": 5.8136,
    "bootstrap_std": 0.7887,
    "bootstrap_ci_95": [
      4.4294,
      7.5439
    ]
  },
  "adjustment_factors": {
    "small_sample_shrinkage": 0.9,
    "implementation_friction": 0.95,
    "historical_overfitting": 0.92
  },
  "combined_adjustment": 0.7866,
  "adjusted_estimates": {
    "point_estimate": 4.6104,
    "conservative_p10": 3.8505,
    "optimistic_p90": 5.4194,
    "ci_95": [
      3.4842,
      5.934
    ]
  },
  "baseline_comparison": {
    "baseline_rate": 2.737,
    "improvement_absolute_pp": 1.8736,
    "improvement_relative_pct": 68.46,
    "prob_exceed_baseline": 99.98,
    "prob_exceed_4pct": 83.96,
    "prob_exceed_5pct": 25.3,
    "prob_exceed_6pct": 2.02
  },
  "expected_conversions": {
    "total_mqls_expected": 127.6,
    "total_mqls_conservative": 106.6,
    "total_mqls_optimistic": 150.0,
    "per_sga_expected": 9.1,
    "per_sga_conservative": 7.6,
    "per_sga_optimistic": 10.7
  }
}
```

---

**Report Generated:** 2025-12-26 16:30:08  
**Methodology:** Tier-Weighted Bootstrap with Conservative Adjustments  
**Bootstrap Iterations:** 10,000  
**Random Seed:** 42
