# Lead Scoring V3 & V4: Key Findings and Decisions

**Last Updated:** December 25, 2025  
**Status:** Production Reference Document

---

## Executive Summary

After extensive data analysis, we have validated findings that should guide V3 and V4 lead scoring:

| Finding | Evidence | Action Required |
|---------|----------|-----------------|
| **Advisor mobility predicts conversion** | 10% vs 4% conversion rate | ✅ Increase weight |
| **115-day data lag exists** | Monthly completeness analysis | ✅ Add lag buffer |
| **Firm bleeding does NOT predict conversion** | 7.8% vs 13% (inverse) | ❌ Remove or flip |
| **Seasonality patterns are valid** | January 135 index, December 59 | ✅ Use for outreach timing |

---

## 1. Data Quality Findings

### 1.1 The 115-Day Data Lag

**Finding:** FINTRX employment history has a ~115-day backfill lag. Recent data is incomplete.

| Month | Data Completeness |
|-------|------------------|
| 4+ months ago | ~90% complete |
| 3 months ago | ~75% complete |
| 2 months ago | ~50% complete |
| Last month | ~25% complete |

**Impact:** Any feature using "last 90 days" is working with ~50% of actual data.

**Solution:** Add 115-day buffer to all time-based mobility features.

```sql
-- CURRENT (misses recent movers)
WHERE days_since_last_move <= 365

-- RECOMMENDED (captures hidden movers)
WHERE days_since_last_move <= 365 + 115  -- 480 days
```

### 1.2 No Survivorship Bias

**Finding:** 100% of advisors in employment history exist in `ria_contacts_current`. The INNER JOIN is not causing data loss.

---

## 2. Conversion Analysis Findings

### 2.1 Advisor Mobility: CONFIRMED ✅

**Finding:** Recent movers convert at 2.5x the rate of stable advisors.

| Mobility Status | Leads | Conversion Rate | vs Baseline |
|-----------------|-------|-----------------|-------------|
| Recent Mover (≤1yr) | 639 | **10.0%** | +150% |
| Moved 2yr | 1,106 | 10.0% | +150% |
| Moved 3yr | 1,493 | 8.0% | +100% |
| Stable (3+yr) | 43,220 | 4.0% | Baseline |

**Correlation:** Days since move has -0.091 correlation with conversion (strongest signal).

**Action:** 
- ✅ Increase scoring weight for recent movers
- ✅ Add 115-day lag buffer to capture hidden recent movers
- ✅ Estimate +1,471 additional recent movers will be identified

### 2.2 Firm Bleeding: REJECTED ❌

**Finding:** Firm bleeding signal works OPPOSITE to expectation. Stable firms produce higher-converting leads.

| Firm Status | Conversion Rate | vs Baseline |
|-------------|-----------------|-------------|
| Stable (producing) | **13.0%** | +200% |
| Stable (total) | 11.5% | +165% |
| Low Bleeding | 10.2% | +135% |
| Moderate Bleeding | 8.6% | +98% |
| High Bleeding | **7.8%** | +80% |

**Correlation:** Total employee turnover has -0.065 correlation (negative = stable is better).

**Why This Makes Sense:**
1. Best advisors leave bleeding firms FIRST
2. By the time we detect "bleeding," opportunity has passed
3. Remaining advisors at bleeding firms are lower quality
4. Stable firms = well-run, quality advisor pool

**Action:**
- ❌ Do NOT prioritize bleeding firm advisors
- ❌ Do NOT extend bleeding window to 180 days
- 🔄 Consider flipping: use "firm stability" as positive signal

### 2.3 Producing Advisor Rate vs Total Employee Rate

**Finding:** Neither metric correlates strongly with conversion.

| Metric | Correlation |
|--------|-------------|
| Producing advisor turnover rate | 0.007 (none) |
| Total employee turnover rate | -0.065 (weak negative) |

**Action:** Don't prioritize switching to producing advisor rate - minimal impact.

---

## 3. Seasonality Findings

### 3.1 Monthly Patterns (Valid)

| Month | Seasonal Index | Classification |
|-------|----------------|----------------|
| January | 135.2 | 🔥 Peak |
| August | 115.9 | 📈 Hot |
| March | 111.8 | 📈 Hot |
| December | 59.3 | ❄️ Lowest |
| November | 84.3 | ❄️ Cold |

**Action:** Use for sales team resource allocation and outreach timing.

### 3.2 Quarterly Patterns

| Quarter | Index | Strategy |
|---------|-------|----------|
| Q1 | ~115 | Maximum outreach |
| Q2 | ~100 | Standard operations |
| Q3 | ~105 | Moderate push |
| Q4 | ~80 | Pipeline building |

---

## 4. Recommended V3 Changes

### Current Rules (Assumed)
```
Bleeding firm (5+ departures/90d) → +20 points
Recent mover (≤1 year) → +10 points
```

### Recommended Rules
```
Bleeding firm → REMOVE or REDUCE to +5 points
Stable firm (0-2 departures/180d) → +15 points [NEW]
Recent mover (≤480 days, lag-adjusted) → +25 points [INCREASE]
Movement velocity > 0.5 → +10 points [NEW]
```

---

## 5. Recommended V4 Changes

### Features to Increase Weight
- `days_since_last_move` (correlation: -0.091)
- `movement_velocity` (correlation: 0.020)

### Features to Decrease/Remove Weight
- `firm_departures_90d` (correlation: negative)
- `firm_bleeding_flag` (inverse relationship)

### New Features to Add
- `firm_stability_score` (inverse of bleeding)
- `movement_velocity` (firms per year of career)
- `data_freshness_flag` (is data within lag window)

### Training Data Changes
- Add 115-day buffer when labeling "recent mover" status
- Limit training to data 6+ months old for complete labels

---

## 6. Expected Impact

### If Mobility Changes Implemented

| Metric | Current | After Change | Improvement |
|--------|---------|--------------|-------------|
| Recent movers identified | 1,283 | 2,754 | +114% |
| High-converting leads | Undercounted | Accurate | — |
| Overall conversion rate | 4.33% | ~4.8-5.2% | +10-20% |
| Additional MQLs/month | Baseline | +15-25% | Significant |

### If Bleeding Firm Signal Fixed

| Metric | Current | After Change | Improvement |
|--------|---------|--------------|-------------|
| Bleeding firm boost | +20 points | 0 or negative | — |
| Stable firm boost | 0 points | +15 points | — |
| Targeting accuracy | Inverted | Correct | +5-10% MQLs |

---

## 7. Validation Before Full Rollout

### Recommended A/B Test

**Design:**
- Group A: Current V3/V4 scoring
- Group B: Lag-adjusted mobility + removed bleeding boost
- Duration: 4-6 weeks
- Metric: Contacted-to-MQL conversion rate

**Statistical Requirements:**
- 500+ leads per group
- 3+ weeks of outcome data
- Significant difference: >2 percentage points

---

## 8. Files Reference

| File | Location | Purpose |
|------|----------|---------|
| Full conversion analysis | `validation/mobility_and_stability_and_conversion.md` | Raw data |
| Strategic recommendations | `validation/V3_V4_Strategic_Recommendations.md` | Action plan |
| Data lag proof | `validation/data_lag_diagnostic_report.md` | 115-day finding |
| Feature inventory | `docs/FINTRX_Lead_Scoring_Features.md` | Available features |

---

## 9. Decision Log

| Date | Decision | Rationale | Owner |
|------|----------|-----------|-------|
| 2025-12-25 | Validate mobility hypothesis | Need data before changing scoring | Data Science |
| 2025-12-25 | Reject bleeding firm prioritization | Data shows inverse correlation | Data Science |
| 2025-12-25 | Confirm 115-day lag adjustment | Monthly completeness analysis | Data Science |
| TBD | A/B test mobility changes | Validate before full rollout | TBD |
| TBD | Full rollout of changes | Pending A/B results | TBD |

---

## 10. Open Questions

1. **Why does bleeding firm signal work backwards?**
   - Hypothesis: Selection bias (best leave first)
   - Need: Deeper analysis of timing

2. **Is the 115-day lag consistent?**
   - Need: Monthly monitoring of lag

3. **What's the optimal mobility weight?**
   - Need: A/B testing different weights

4. **Should we completely remove or invert the bleeding signal?**
   - Need: Test both approaches

---

**Document Maintained By:** Data Science Team  
**Next Review:** After A/B test completion
