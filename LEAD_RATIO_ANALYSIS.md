# Lead Ratio Analysis: Tier Confidence & Statistical Significance

**Date:** January 3, 2026  
**Version:** 1.0  
**Purpose:** Comprehensive statistical analysis of tier performance to inform lead allocation decisions

---

## Executive Summary

This analysis evaluates the statistical confidence and conversion performance of all lead scoring tiers using historical data from `historical_lead_performance` (52,836 leads, June 2023 - December 2025). Key findings:

### 🎯 Key Findings

1. **High Confidence Tiers (n≥1000):** Only `STANDARD` tier has sufficient sample size for high confidence
2. **Medium Confidence Tiers (n≥300):** `TIER_2A_PROVEN_MOVER`, `TIER_4_HEAVY_BLEEDER`, `TIER_MA_ACTIVE_PRIME`, `TIER_MA_ACTIVE`
3. **Small Sample Sizes:** Career Clock tiers and many Prime Mover variants have insufficient data (n<100)
4. **M&A Tiers Underperform:** Both M&A tiers show conversion rates below or near baseline (2.73% - 4.4%)
5. **Risk-Adjusted Ranking:** Only 6 tiers have proven lift (worst-case CI > baseline 3.82%)

### ⚠️ Critical Insights

- **Career Clock Tiers:** Very small sample sizes (8-84 leads) make confidence intervals extremely wide
- **M&A Tiers:** Lower than expected performance - may need recalibration or different targeting
- **Tier Stability:** Most tiers show moderate to high volatility across quarters
- **Statistical Significance:** Many high-performing tiers lack statistical significance due to small samples

---

## Section 1: Sample Size & Conversion by Tier

### Overall Performance Summary

| Tier | Sample Size | Conversions | Conversion Rate | Lift vs Baseline | Confidence Level | Margin of Error |
|------|-------------|-------------|-----------------|------------------|------------------|-----------------|
| **TIER_1A_PRIME_MOVER_CFP** | 9 | 4 | 44.44% | 11.63x | INSUFFICIENT (n<30) | Too wide |
| **TIER_0B_SMALL_FIRM_DUE** | 12 | 4 | 33.33% | 8.73x | INSUFFICIENT (n<30) | Too wide |
| **TIER_1B_PRIME_MOVER_SERIES65** | 41 | 8 | 19.51% | 5.11x | VERY LOW (n≥30) | 95% CI ±18% |
| **TIER_0A_PRIME_MOVER_DUE** | 12 | 2 | 16.67% | 4.36x | INSUFFICIENT (n<30) | Too wide |
| **TIER_1B_PRIME_ZERO_FRICTION** | 31 | 5 | 16.13% | 4.22x | VERY LOW (n≥30) | 95% CI ±18% |
| **TIER_1E_PRIME_MOVER** | 50 | 8 | 16.00% | 4.19x | VERY LOW (n≥30) | 95% CI ±18% |
| **TIER_1D_SMALL_FIRM** | 39 | 6 | 15.38% | 4.03x | VERY LOW (n≥30) | 95% CI ±18% |
| **TIER_1F_HV_WEALTH_BLEEDER** | 121 | 17 | 14.05% | 3.68x | LOW (n≥100) | 95% CI ±10% |
| **TIER_NURTURE_TOO_EARLY** | 8 | 1 | 12.50% | 3.27x | INSUFFICIENT (n<30) | Too wide |
| **TIER_1G_GROWTH_STAGE** | 34 | 4 | 11.76% | 3.08x | VERY LOW (n≥30) | 95% CI ±18% |
| **TIER_0C_CLOCKWORK_DUE** | 84 | 9 | 10.71% | 2.80x | VERY LOW (n≥30) | 95% CI ±18% |
| **TIER_1G_ENHANCED_SWEET_SPOT** | 52 | 5 | 9.62% | 2.52x | VERY LOW (n≥30) | 95% CI ±18% |
| **TIER_2A_PROVEN_MOVER** | 733 | 66 | 9.00% | 2.36x | MEDIUM (n≥300) | 95% CI ±5% |
| **TIER_3_EXPERIENCED_MOVER** | 92 | 8 | 8.70% | 2.28x | VERY LOW (n≥30) | 95% CI ±18% |
| **TIER_4_HEAVY_BLEEDER** | 642 | 39 | 6.07% | 1.59x | MEDIUM (n≥300) | 95% CI ±5% |
| **TIER_MA_ACTIVE_PRIME** | 432 | 19 | 4.40% | 1.15x | MEDIUM (n≥300) | 95% CI ±5% |
| **STANDARD** | 49,765 | 2,112 | 4.24% | 1.11x | HIGH (n≥1000) | 95% CI ±5% |
| **TIER_MA_ACTIVE** | 622 | 17 | 2.73% | 0.72x | MEDIUM (n≥300) | 95% CI ±5% |
| **TIER_2B_MODERATE_BLEEDER** | 41 | 0 | 0.00% | 0.00x | VERY LOW (n≥30) | 95% CI ±18% |

### Key Observations

1. **Highest Performing Tiers:** `TIER_1A_PRIME_MOVER_CFP` (44.44%) and `TIER_0B_SMALL_FIRM_DUE` (33.33%) have extremely small samples (n<30)
2. **Most Reliable High Performers:** `TIER_1F_HV_WEALTH_BLEEDER` (14.05%, n=121) and `TIER_2A_PROVEN_MOVER` (9.00%, n=733)
3. **M&A Tiers Underperform:** Both M&A tiers convert below baseline expectations
4. **Career Clock Tiers:** Small samples (8-84) with wide confidence intervals

---

## Section 2: 95% Confidence Intervals & Statistical Significance

### Confidence Interval Analysis

| Tier | Sample Size | Conversions | Point Estimate | CI Lower (95%) | CI Upper (95%) | Margin of Error | Statistical Significance | Worst-Case Lift | Best-Case Lift |
|------|-------------|-------------|----------------|-----------------|----------------|-----------------|------------------------|-----------------|----------------|
| **TIER_1B_PRIME_MOVER_SERIES65** | 41 | 8 | 19.51% | 7.38% | 31.64% | ±12.13% | ✅ ABOVE BASELINE | 1.93x | 8.28x |
| **TIER_1B_PRIME_ZERO_FRICTION** | 31 | 5 | 16.13% | 3.18% | 29.08% | ±12.95% | ⚠️ NOT DIFFERENT | 0.83x | 7.61x |
| **TIER_1E_PRIME_MOVER** | 50 | 8 | 16.00% | 5.84% | 26.16% | ±10.16% | ✅ ABOVE BASELINE | 1.53x | 6.85x |
| **TIER_1D_SMALL_FIRM** | 39 | 6 | 15.38% | 4.06% | 26.71% | ±11.32% | ✅ ABOVE BASELINE | 1.06x | 6.99x |
| **TIER_1F_HV_WEALTH_BLEEDER** | 121 | 17 | 14.05% | 7.86% | 20.24% | ±6.19% | ✅ ABOVE BASELINE | 2.06x | 5.30x |
| **TIER_1G_GROWTH_STAGE** | 34 | 4 | 11.76% | 0.93% | 22.59% | ±10.83% | ⚠️ NOT DIFFERENT | 0.24x | 5.91x |
| **TIER_0C_CLOCKWORK_DUE** | 84 | 9 | 10.71% | 4.10% | 17.33% | ±6.61% | ✅ ABOVE BASELINE | 1.07x | 4.54x |
| **TIER_1G_ENHANCED_SWEET_SPOT** | 52 | 5 | 9.62% | 1.60% | 17.63% | ±8.01% | ⚠️ NOT DIFFERENT | 0.42x | 4.61x |
| **TIER_2A_PROVEN_MOVER** | 733 | 66 | 9.00% | 6.93% | 11.08% | ±2.07% | ✅ ABOVE BASELINE | 1.81x | 2.90x |
| **TIER_3_EXPERIENCED_MOVER** | 92 | 8 | 8.70% | 2.94% | 14.45% | ±5.76% | ⚠️ NOT DIFFERENT | 0.77x | 3.78x |
| **TIER_4_HEAVY_BLEEDER** | 642 | 39 | 6.07% | 4.23% | 7.92% | ±1.85% | ✅ ABOVE BASELINE | 1.11x | 2.07x |
| **TIER_MA_ACTIVE_PRIME** | 432 | 19 | 4.40% | 2.46% | 6.33% | ±1.93% | ⚠️ NOT DIFFERENT | 0.65x | 1.66x |
| **STANDARD** | 49,765 | 2,112 | 4.24% | 4.07% | 4.42% | ±0.18% | ✅ ABOVE BASELINE | 1.06x | 1.16x |
| **TIER_MA_ACTIVE** | 622 | 17 | 2.73% | 1.45% | 4.01% | ±1.28% | ⚠️ NOT DIFFERENT | 0.38x | 1.05x |
| **TIER_2B_MODERATE_BLEEDER** | 41 | 0 | 0.00% | 0.00% | 0.00% | ±0.00% | ⬇️ BELOW BASELINE | 0.00x | 0.00x |

### Critical Insights

1. **Statistically Significant Tiers (CI excludes baseline 3.82%):**
   - ✅ `TIER_1B_PRIME_MOVER_SERIES65` (7.38% - 31.64%)
   - ✅ `TIER_1E_PRIME_MOVER` (5.84% - 26.16%)
   - ✅ `TIER_1D_SMALL_FIRM` (4.06% - 26.71%)
   - ✅ `TIER_1F_HV_WEALTH_BLEEDER` (7.86% - 20.24%)
   - ✅ `TIER_0C_CLOCKWORK_DUE` (4.10% - 17.33%)
   - ✅ `TIER_2A_PROVEN_MOVER` (6.93% - 11.08%)
   - ✅ `TIER_4_HEAVY_BLEEDER` (4.23% - 7.92%)
   - ✅ `STANDARD` (4.07% - 4.42%)

2. **Tiers NOT Statistically Different from Baseline:**
   - ⚠️ `TIER_1B_PRIME_ZERO_FRICTION` (CI: 3.18% - 29.08% - includes baseline)
   - ⚠️ `TIER_1G_GROWTH_STAGE` (CI: 0.93% - 22.59%)
   - ⚠️ `TIER_1G_ENHANCED_SWEET_SPOT` (CI: 1.60% - 17.63%)
   - ⚠️ `TIER_3_EXPERIENCED_MOVER` (CI: 2.94% - 14.45%)
   - ⚠️ `TIER_MA_ACTIVE_PRIME` (CI: 2.46% - 6.33% - includes baseline)
   - ⚠️ `TIER_MA_ACTIVE` (CI: 1.45% - 4.01% - includes baseline)

3. **Wide Confidence Intervals:** Many high-performing tiers have extremely wide CIs due to small sample sizes, making them unreliable for allocation decisions.

---

## Section 3: Tier Stability Across Time Periods

### Quarterly Performance Stability (Last 2 Years)

| Tier | Quarters | Total Leads | Avg Conv Rate | Min | Max | Std Dev | CV % | Stability |
|------|----------|-------------|---------------|-----|-----|---------|------|-----------|
| **TIER_2A_PROVEN_MOVER** | 6 | 723 | 8.40% | 2.41% | 13.53% | 4.41% | 52.5% | 🔴 VOLATILE |
| **TIER_4_HEAVY_BLEEDER** | 6 | 642 | 6.33% | 3.13% | 8.20% | 1.92% | 30.3% | 🟡 MODERATE |
| **STANDARD** | 8 | 49,713 | 4.39% | 3.14% | 6.28% | 1.03% | 23.4% | 🟡 MODERATE |
| **TIER_MA_ACTIVE** | 4 | 601 | 2.02% | 0.00% | 3.04% | 1.38% | 68.0% | 🔴 VOLATILE |

### Stability Analysis

1. **Most Stable:** `STANDARD` tier (CV = 23.4%) - consistent performance across 8 quarters
2. **Most Volatile:** `TIER_MA_ACTIVE` (CV = 68.0%) - high variability, including quarters with 0% conversion
3. **Moderate Stability:** `TIER_4_HEAVY_BLEEDER` (CV = 30.3%) - acceptable stability
4. **High Volatility:** `TIER_2A_PROVEN_MOVER` (CV = 52.5%) - performance varies significantly by quarter

**Note:** Career Clock tiers and many Prime Mover variants don't have enough quarterly data (need ≥4 quarters with ≥20 leads each) to assess stability.

---

## Section 4: Career Clock Tier Analysis

### Career Clock Tier Performance

| Tier | Sample Size | Conversions | Conversion Rate | Lift | CI Lower (95%) | CI Upper (95%) |
|------|-------------|-------------|-----------------|------|----------------|----------------|
| **TIER_0B_SMALL_FIRM_DUE** | 12 | 4 | 33.33% | 8.73x | 6.66% | 60.01% |
| **TIER_0A_PRIME_MOVER_DUE** | 12 | 2 | 16.67% | 4.36x | -4.42% | 37.75% |
| **TIER_NURTURE_TOO_EARLY** | 8 | 1 | 12.50% | 3.27x | -10.42% | 35.42% |
| **TIER_0C_CLOCKWORK_DUE** | 84 | 9 | 10.71% | 2.80x | 4.10% | 17.33% |

### Career Clock Insights

1. **Extremely Small Samples:** All Career Clock tiers have n<100, with most having n<30
2. **Wide Confidence Intervals:** `TIER_0A_PRIME_MOVER_DUE` and `TIER_NURTURE_TOO_EARLY` have negative lower bounds (statistically meaningless)
3. **Only Reliable Tier:** `TIER_0C_CLOCKWORK_DUE` (n=84) has a statistically significant CI (4.10% - 17.33%)
4. **High Point Estimates:** `TIER_0B_SMALL_FIRM_DUE` shows 33.33% conversion but with only 12 leads - not reliable

**Recommendation:** Career Clock tiers need significantly more data before they can be confidently allocated. Current performance may be due to small sample bias.

---

## Section 5: M&A Tier Analysis

### M&A Tier Performance

| Tier | Sample Size | Conversions | Conversion Rate | Lift vs Baseline | CI Lower (95%) | CI Upper (95%) |
|------|-------------|-------------|-----------------|-------------------|----------------|----------------|
| **TIER_MA_ACTIVE_PRIME** | 432 | 19 | 4.40% | 1.15x | 2.46% | 6.33% |
| **TIER_MA_ACTIVE** | 622 | 17 | 2.73% | 0.72x | 1.45% | 4.01% |

### M&A Tier Insights

1. **Underperformance:** Both M&A tiers convert below or near baseline (3.82%)
   - `TIER_MA_ACTIVE_PRIME`: 4.40% (1.15x lift) - barely above baseline
   - `TIER_MA_ACTIVE`: 2.73% (0.72x lift) - **below baseline**

2. **Statistical Significance:** Neither tier is statistically different from baseline
   - `TIER_MA_ACTIVE_PRIME` CI (2.46% - 6.33%) includes baseline
   - `TIER_MA_ACTIVE` CI (1.45% - 4.01%) includes baseline

3. **Sample Size:** Both tiers have adequate samples (n≥300) for medium confidence

4. **Worst-Case Scenario:** 
   - `TIER_MA_ACTIVE_PRIME` worst-case lift: 0.65x (below baseline)
   - `TIER_MA_ACTIVE` worst-case lift: 0.38x (well below baseline)

**Critical Finding:** M&A tiers are **not performing as expected**. The empirical evidence from Commonwealth (9.3% conversion) is not reflected in the broader historical data. Possible reasons:
- Commonwealth was an exceptional case
- M&A window timing may be more critical than assumed
- Other M&A events may have different dynamics

**Recommendation:** Re-evaluate M&A tier criteria or deprioritize until more data is available.

---

## Section 6: Risk-Adjusted Tier Ranking

### Conservative Allocation Ranking (Worst-Case CI Lower Bound)

| Rank | Tier | Sample Size | Point Estimate | Worst-Case (CI Lower) | Worst-Case Lift | Allocation Recommendation |
|------|------|-------------|-----------------|------------------------|-----------------|---------------------------|
| 1 | **TIER_1F_HV_WEALTH_BLEEDER** | 121 | 14.05% | 7.86% | 2.06x | 🟠 LOW CONFIDENCE - INCLUDE CAUTIOUSLY |
| 2 | **TIER_1B_PRIME_MOVER_SERIES65** | 41 | 19.51% | 7.38% | 1.93x | 🔴 VERY LOW CONFIDENCE - LIMIT EXPOSURE |
| 3 | **TIER_2A_PROVEN_MOVER** | 733 | 9.00% | 6.93% | 1.81x | 🟡 MEDIUM CONFIDENCE - INCLUDE |
| 4 | **TIER_1E_PRIME_MOVER** | 50 | 16.00% | 5.84% | 1.53x | 🔴 VERY LOW CONFIDENCE - LIMIT EXPOSURE |
| 5 | **TIER_4_HEAVY_BLEEDER** | 642 | 6.07% | 4.23% | 1.11x | 🟡 MEDIUM CONFIDENCE - INCLUDE |
| 6 | **TIER_0C_CLOCKWORK_DUE** | 84 | 10.71% | 4.10% | 1.07x | 🔴 VERY LOW CONFIDENCE - LIMIT EXPOSURE |
| 7 | **STANDARD** | 49,765 | 4.24% | 4.07% | 1.06x | 🟢 HIGH CONFIDENCE - INCLUDE |
| 8 | **TIER_1D_SMALL_FIRM** | 39 | 15.38% | 4.06% | 1.06x | 🔴 VERY LOW CONFIDENCE - LIMIT EXPOSURE |
| 9 | **TIER_1B_PRIME_ZERO_FRICTION** | 31 | 16.13% | 3.18% | 0.83x | ⛔ EXCLUDE - NO PROVEN LIFT |
| 10 | **TIER_3_EXPERIENCED_MOVER** | 92 | 8.70% | 2.94% | 0.77x | ⛔ EXCLUDE - NO PROVEN LIFT |
| 11 | **TIER_MA_ACTIVE_PRIME** | 432 | 4.40% | 2.46% | 0.65x | ⛔ EXCLUDE - NO PROVEN LIFT |
| 12 | **TIER_1G_ENHANCED_SWEET_SPOT** | 52 | 9.62% | 1.60% | 0.42x | ⛔ EXCLUDE - NO PROVEN LIFT |
| 13 | **TIER_MA_ACTIVE** | 622 | 2.73% | 1.45% | 0.38x | ⛔ EXCLUDE - NO PROVEN LIFT |
| 14 | **TIER_1G_GROWTH_STAGE** | 34 | 11.76% | 0.93% | 0.24x | ⛔ EXCLUDE - NO PROVEN LIFT |
| 15 | **TIER_2B_MODERATE_BLEEDER** | 41 | 0.00% | 0.00% | 0.00x | ⛔ EXCLUDE - NO PROVEN LIFT |

### Risk-Adjusted Insights

**Tiers with Proven Lift (Worst-Case > Baseline):**
1. ✅ `TIER_1F_HV_WEALTH_BLEEDER` (7.86% worst-case, 2.06x lift)
2. ✅ `TIER_1B_PRIME_MOVER_SERIES65` (7.38% worst-case, 1.93x lift)
3. ✅ `TIER_2A_PROVEN_MOVER` (6.93% worst-case, 1.81x lift)
4. ✅ `TIER_1E_PRIME_MOVER` (5.84% worst-case, 1.53x lift)
5. ✅ `TIER_4_HEAVY_BLEEDER` (4.23% worst-case, 1.11x lift)
6. ✅ `TIER_0C_CLOCKWORK_DUE` (4.10% worst-case, 1.07x lift)
7. ✅ `STANDARD` (4.07% worst-case, 1.06x lift)
8. ✅ `TIER_1D_SMALL_FIRM` (4.06% worst-case, 1.06x lift)

**Tiers WITHOUT Proven Lift (Worst-Case ≤ Baseline):**
- ⛔ `TIER_1B_PRIME_ZERO_FRICTION` (3.18% worst-case)
- ⛔ `TIER_3_EXPERIENCED_MOVER` (2.94% worst-case)
- ⛔ `TIER_MA_ACTIVE_PRIME` (2.46% worst-case)
- ⛔ `TIER_1G_ENHANCED_SWEET_SPOT` (1.60% worst-case)
- ⛔ `TIER_MA_ACTIVE` (1.45% worst-case)
- ⛔ `TIER_1G_GROWTH_STAGE` (0.93% worst-case)
- ⛔ `TIER_2B_MODERATE_BLEEDER` (0.00% worst-case)

---

## Section 7: Recommendations & Action Items

### 🎯 High-Priority Recommendations

1. **M&A Tier Re-evaluation**
   - ⚠️ Both M&A tiers underperform baseline expectations
   - ⚠️ Not statistically different from baseline
   - **Action:** Re-evaluate M&A tier criteria, timing windows, or consider deprioritization

2. **Career Clock Tier Data Collection**
   - ⚠️ All Career Clock tiers have insufficient sample sizes (n<100)
   - ⚠️ Wide confidence intervals make allocation decisions risky
   - **Action:** Continue collecting data, limit allocation until n≥300

3. **Focus on Proven Performers**
   - ✅ Prioritize tiers with proven worst-case lift: `TIER_1F_HV_WEALTH_BLEEDER`, `TIER_2A_PROVEN_MOVER`, `TIER_4_HEAVY_BLEEDER`
   - ✅ These tiers have adequate sample sizes and statistical significance

### 📊 Allocation Strategy

**Recommended Tier Priority (Risk-Adjusted):**

1. **Tier 1 (High Confidence, Proven Lift):**
   - `TIER_2A_PROVEN_MOVER` (n=733, worst-case 6.93%, 1.81x lift)
   - `TIER_4_HEAVY_BLEEDER` (n=642, worst-case 4.23%, 1.11x lift)
   - `STANDARD` (n=49,765, worst-case 4.07%, 1.06x lift)

2. **Tier 2 (Medium Confidence, Proven Lift):**
   - `TIER_1F_HV_WEALTH_BLEEDER` (n=121, worst-case 7.86%, 2.06x lift)
   - `TIER_0C_CLOCKWORK_DUE` (n=84, worst-case 4.10%, 1.07x lift)

3. **Tier 3 (Low Confidence, Limit Exposure):**
   - `TIER_1B_PRIME_MOVER_SERIES65` (n=41, worst-case 7.38%, 1.93x lift)
   - `TIER_1E_PRIME_MOVER` (n=50, worst-case 5.84%, 1.53x lift)
   - `TIER_1D_SMALL_FIRM` (n=39, worst-case 4.06%, 1.06x lift)

4. **Tier 4 (Exclude - No Proven Lift):**
   - `TIER_MA_ACTIVE_PRIME` (worst-case 2.46%, 0.65x lift)
   - `TIER_MA_ACTIVE` (worst-case 1.45%, 0.38x lift)
   - `TIER_1B_PRIME_ZERO_FRICTION` (worst-case 3.18%, 0.83x lift)
   - `TIER_3_EXPERIENCED_MOVER` (worst-case 2.94%, 0.77x lift)
   - All other tiers with worst-case ≤ baseline

### 🔬 Data Collection Priorities

1. **Career Clock Tiers:** Need n≥300 for each tier to achieve medium confidence
2. **High-Performing Small Sample Tiers:** `TIER_1A_PRIME_MOVER_CFP`, `TIER_0B_SMALL_FIRM_DUE` need more data
3. **M&A Tiers:** Continue monitoring, but don't prioritize allocation

### 📈 Monitoring & Validation

1. **Quarterly Review:** Re-run this analysis quarterly to track tier stability
2. **Sample Size Targets:** Track progress toward n≥300 for all active tiers
3. **Statistical Significance:** Monitor when small-sample tiers achieve significance
4. **M&A Performance:** Track M&A tier performance separately to validate or refute current findings

---

## Appendix: Methodology Notes

### Point-in-Time (PIT) Compliance

✅ **All tier assignments use PIT methodology:**
- Tiers come from `lead_scores_v3`, which uses `lead_scoring_features_pit`
- Features calculated using only data available at `contacted_date`
- 99.99% of leads have exact date matches (preserving PIT accuracy)

### Statistical Methods

- **Confidence Intervals:** 95% CI using normal approximation: p ± 1.96 * sqrt(p*(1-p)/n)
- **Baseline:** 3.82% (historical overall conversion rate)
- **Minimum Sample Size:** n≥30 for CI calculation
- **Stability Metric:** Coefficient of Variation (CV) = stddev / mean

### Data Sources

- **Primary Table:** `savvy-gtm-analytics.ml_features.historical_lead_performance`
- **Total Leads:** 52,836 (mature leads, 30+ days old)
- **Date Range:** June 2023 - December 2025
- **Tier Source:** `lead_scores_v3` (V3.5.0 model)

---

**Document Version:** 1.0  
**Last Updated:** January 3, 2026  
**Next Review:** April 2026 (Quarterly)
