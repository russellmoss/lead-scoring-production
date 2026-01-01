# News Mentions Timing Validation Analysis

**Date:** January 1, 2026  
**Hypothesis:** Advisors mentioned in news within 90 days before contact convert at higher rates (news = "mindset shift" signal)  
**Expected Coverage:** ~4.8% of contacts have news mentions  
**Baseline Conversion Rate:** 3.82%

---

## Executive Summary

**Overall Finding:** ⚠️ **News mentions do NOT significantly improve conversion rates**

- **Recent News (90d):** 3.68% conversion (0.96x baseline) - **Below baseline**
- **No News:** 3.80% conversion (0.99x baseline) - **Slightly below baseline**
- **Statistical Significance:** ❌ **NO** (z-score: -0.08, p > 0.05)

**Key Insights:**
1. News mentions within 90 days actually convert **slightly lower** than no news
2. **31-60 day window** shows promise (1.31x lift) but small sample (40 leads)
3. **"New Hire" news type** shows 1.21x lift (68 leads, 4.62% conversion)
4. News does NOT amplify V3 tier performance

**Recommendation:** ⚠️ **DO NOT DEPLOY** as a standalone feature. Consider "New Hire" news type as a potential signal for future investigation, but current evidence is weak.

---

## PART 1: Basic Validation - News Status vs Conversion

### Results

| News Status | Leads | Conversions | Conversion Rate | Lift vs Baseline | % of Total |
|-------------|-------|-------------|-----------------|------------------|------------|
| **Has Recent News (90d)** | 136 | 5 | **3.68%** | **0.96x** ❌ | 0.35% |
| **Has News (90-180d)** | 136 | 6 | **4.41%** | **1.15x** ✅ | 0.35% |
| **No News** | 39,039 | 1,483 | **3.80%** | **0.99x** | 99.31% |

### Analysis

**❌ Recent News (90d) Underperforms:**
- Conversion rate (3.68%) is **below baseline** (3.82%)
- Lift of 0.96x means news leads convert **4% worse** than baseline
- Sample size: 136 leads (0.35% of total)

**✅ Older News (90-180d) Shows Promise:**
- Conversion rate (4.41%) is **15% above baseline**
- Lift of 1.15x is positive but sample size is small (136 leads)
- May indicate advisors mentioned in news 3-6 months ago are more likely to convert

**Key Finding:** The hypothesis that "recent news = mindset shift = higher conversion" is **NOT supported**. Recent news (90d) actually underperforms.

---

## PART 2: News Recency Effect - Detailed Timing Analysis

### Results

| Recency Bucket | Leads | Conversions | Conversion Rate | Lift vs Baseline |
|----------------|-------|-------------|-----------------|------------------|
| **0-30 days** | 55 | 2 | 3.64% | 0.95x ❌ |
| **31-60 days** | 40 | 2 | **5.00%** | **1.31x** ✅ |
| **61-90 days** | 41 | 1 | 2.44% | 0.64x ❌ |
| **91-180 days** | 136 | 6 | 4.41% | 1.15x ✅ |
| **181-365 days** | 211 | 9 | 4.27% | 1.12x ✅ |
| **365+ days** | 185 | 6 | 3.24% | 0.85x ❌ |
| **No News** | 38,643 | 1,468 | 3.80% | 0.99x |

### Analysis

**⚠️ Sweet Spot: 31-60 Days**
- **5.00% conversion rate** (1.31x baseline lift)
- Small sample (40 leads, 2 conversions)
- **Not statistically significant** due to small sample
- Suggests advisors mentioned in news 1-2 months ago may be more receptive

**Pattern Observed:**
- **0-30 days:** Below baseline (3.64%)
- **31-60 days:** Above baseline (5.00%) ⚠️ **Potential signal**
- **61-90 days:** Well below baseline (2.44%)
- **91-180 days:** Above baseline (4.41%)
- **181-365 days:** Above baseline (4.27%)

**Interpretation:** There may be a "sweet spot" window (31-60 days) where news mentions correlate with higher conversion, but the sample size is too small to be confident. The pattern is inconsistent across buckets.

---

## PART 3: News Type Analysis - Which News Types Signal Conversion?

### Results

| News Type | Leads | Conversions | Conversion Rate | Lift vs Baseline |
|-----------|-------|-------------|-----------------|------------------|
| **New Hire** | 68 | 6 | **4.62%** | **1.21x** ✅ |
| **Mergers & Acquisitions** | 27 | 2 | 4.17% | 1.09x ✅ |
| **General News** | 52 | 0 | 0.00% | 0.00x ❌ |

### Analysis

**✅ "New Hire" News Type Shows Promise:**
- **4.62% conversion rate** (1.21x baseline lift)
- Sample size: 68 leads (6 conversions)
- **Interpretation:** Advisors mentioned in "New Hire" news may be more likely to convert
- **Caveat:** Small sample size, not statistically validated

**✅ "Mergers & Acquisitions" Shows Modest Lift:**
- **4.17% conversion rate** (1.09x baseline lift)
- Sample size: 27 leads (2 conversions)
- **Interpretation:** M&A news may indicate advisor movement/change
- **Caveat:** Very small sample size

**❌ "General News" Shows No Signal:**
- **0.00% conversion rate** (52 leads, 0 conversions)
- **Interpretation:** General news mentions don't correlate with conversion

**Key Finding:** "New Hire" news type shows the strongest signal (1.21x lift), but sample size is small. Worth investigating further with more data.

---

## PART 4: Statistical Significance Test

### Results

| Metric | Value |
|--------|-------|
| **Test Name** | News vs No News Comparison |
| **News Sample Size** | 136 leads |
| **No News Sample Size** | 39,175 leads |
| **News Conversion Rate** | 3.68% |
| **No News Conversion Rate** | 3.80% |
| **Rate Difference** | -0.12 percentage points |
| **Relative Lift** | 0.97x (news converts 3% worse) |
| **Z-Score** | -0.08 |
| **Statistically Significant?** | ❌ **NO** (p > 0.05) |

### Analysis

**❌ NOT Statistically Significant:**
- Z-score of -0.08 is well below the 1.96 threshold for significance (p < 0.05)
- News leads actually convert **slightly worse** than no-news leads
- The difference (-0.12 percentage points) is not statistically meaningful

**Conclusion:** There is **no statistical evidence** that news mentions improve conversion rates. The slight difference observed is within normal statistical variation.

---

## PART 5: Interaction with V3 Tiers - Does News Amplify Tier Performance?

### Results

| V3 Tier | News Status | Leads | Conversions | Conversion Rate | Lift vs Baseline |
|---------|-------------|-------|-------------|-----------------|------------------|
| **TIER_0A_PRIME_MOVER_DUE** | No News | 12 | 2 | 16.67% | 4.36x |
| **TIER_0B_SMALL_FIRM_DUE** | No News | 12 | 4 | 33.33% | 8.73x |
| **TIER_0C_CLOCKWORK_DUE** | No News | 84 | 8 | 9.52% | 2.49x |
| **TIER_1A_PRIME_MOVER_CFP** | No News | 9 | 4 | 44.44% | 11.63x |
| **TIER_1B_PRIME_MOVER_SERIES65** | No News | 43 | 7 | 16.28% | 4.26x |
| **STANDARD** | Has Recent News | 96 | 3 | 3.13% | 0.82x |
| **STANDARD** | No News | 21,791 | 729 | 3.35% | 0.88x |

### Analysis

**❌ News Does NOT Amplify Tier Performance:**
- **High-performing tiers (TIER_0A/0B/1A/1B) have NO news mentions** in the sample
- This suggests news mentions are **not correlated** with high-performing tier characteristics
- **STANDARD tier with news** (3.13%) actually converts **worse** than STANDARD tier without news (3.35%)

**Key Finding:** News mentions do not appear to amplify or improve tier performance. High-performing tiers (Career Clock tiers, Prime Movers) don't have news mentions in the sample, suggesting news is not a strong signal for these high-value leads.

**Sample Size Note:** Very few leads in high-performing tiers have news mentions, making it difficult to draw conclusions about news amplification effects.

---

## Overall Assessment

### Signal Strength: ⚠️ **WEAK**

| Aspect | Assessment | Notes |
|--------|------------|-------|
| **Overall Conversion Impact** | ❌ Negative | Recent news (90d) converts 4% worse than baseline |
| **Statistical Significance** | ❌ Not Significant | Z-score: -0.08 (p > 0.05) |
| **Recency Window** | ⚠️ Inconclusive | 31-60 days shows promise (1.31x) but small sample |
| **News Type Signal** | ⚠️ Weak | "New Hire" shows 1.21x lift but small sample (68 leads) |
| **Tier Amplification** | ❌ None | News does not improve tier performance |

### Key Findings

1. **Recent News (90d) Underperforms:**
   - 3.68% conversion vs 3.82% baseline
   - 0.96x lift (4% worse than baseline)
   - **Conclusion:** Recent news is NOT a positive signal

2. **31-60 Day Window Shows Promise:**
   - 5.00% conversion (1.31x lift)
   - Small sample (40 leads, 2 conversions)
   - **Conclusion:** Worth monitoring but not deployable yet

3. **"New Hire" News Type:**
   - 4.62% conversion (1.21x lift)
   - Sample: 68 leads, 6 conversions
   - **Conclusion:** Potential signal, needs more data

4. **No Statistical Significance:**
   - Z-score: -0.08 (well below 1.96 threshold)
   - **Conclusion:** Differences observed are within normal variation

5. **No Tier Amplification:**
   - High-performing tiers don't have news mentions
   - **Conclusion:** News is not correlated with tier performance

---

## Recommendations

### ❌ **DO NOT DEPLOY** as Standalone Feature

**Reasons:**
1. Recent news (90d) converts **worse** than baseline (0.96x lift)
2. **Not statistically significant** (z-score: -0.08)
3. Small sample sizes make promising signals unreliable
4. No evidence of tier amplification

### ⚠️ **Future Investigation Opportunities**

1. **"New Hire" News Type:**
   - Monitor with more data (target: 200+ leads)
   - If signal persists, consider as binary feature
   - **Current status:** Weak signal, needs validation

2. **31-60 Day Window:**
   - Monitor with more data (target: 100+ leads)
   - If signal persists, consider as timing feature
   - **Current status:** Inconclusive, needs more data

3. **News Type Analysis:**
   - Investigate other news types with larger samples
   - Consider news sentiment analysis (if available)
   - **Current status:** Limited by sample sizes

### Alternative Approaches

1. **Post-Model Filtering:**
   - Use "New Hire" news as a tie-breaker for STANDARD tier leads
   - Not as a model feature, but as a prioritization signal
   - **Risk:** Low (doesn't affect model)

2. **Monitoring Only:**
   - Track news mention conversion rates over time
   - Re-evaluate when sample sizes grow
   - **Risk:** None (no deployment)

3. **News Sentiment Analysis:**
   - If news content is available, analyze sentiment
   - Positive news (awards, growth) vs negative news (departures, issues)
   - **Current status:** Not investigated

---

## Data Quality Notes

### Coverage
- **News Coverage:** 0.70% of leads have recent news (90d)
- **Expected:** ~4.8% (actual is much lower)
- **Possible Reasons:**
  - News data may be incomplete
  - News mentions may be rare for most advisors
  - Data quality issues in `ria_contact_news` table

### Sample Size Concerns
- **Recent News (90d):** 136 leads (0.35% of total)
- **31-60 Day Window:** 40 leads (very small)
- **"New Hire" Type:** 68 leads (small)
- **Impact:** Small samples make findings unreliable

### PIT Compliance
- ✅ **Verified:** All news dates filtered to `WRITTEN_AT < contacted_date`
- ✅ **No Data Leakage:** Only uses historical news data
- ✅ **Temporal Filtering:** Correctly uses date windows

---

## Conclusion

**Overall Assessment:** ⚠️ **News mentions are NOT a strong conversion signal**

The hypothesis that "recent news = mindset shift = higher conversion" is **NOT supported by the data**. In fact, recent news (90d) converts **slightly worse** than baseline, and the difference is not statistically significant.

**Potential Signals (Require More Data):**
- "New Hire" news type (1.21x lift, 68 leads)
- 31-60 day recency window (1.31x lift, 40 leads)

**Recommendation:** **DO NOT DEPLOY** as a model feature. Monitor "New Hire" news type and 31-60 day window with more data, but current evidence is insufficient for production deployment.

---

**Report Generated:** January 1, 2026  
**Next Review:** After collecting 200+ leads with "New Hire" news or 100+ leads in 31-60 day window
