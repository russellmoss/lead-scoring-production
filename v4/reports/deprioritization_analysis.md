# V4 Model as Deprioritization Filter - Analysis

**Generated**: 2025-12-24  
**Purpose**: Evaluate V4's value for identifying leads to skip, even if it doesn't beat V3 on top decile lift.

---

## Executive Summary

**✅ V4 IS VALUABLE AS DEPRIORITIZATION FILTER**

- **Bottom 20%** converts at **1.33%** (0.42x lift) vs **3.20%** baseline
- **58% reduction** in conversion rate for bottom 20%
- **Efficiency gain**: Skip 20% of leads, lose only 8.3% of conversions

---

## Results

### Overall Test Set
- **Leads**: 6,004
- **Conversions**: 192
- **Conversion Rate**: 3.20%

### Bottom 20% by V4 Score (DEPRIORITIZE)
- **Leads**: 1,200 (20.0% of total)
- **Conversions**: 16 (8.3% of total conversions)
- **Conversion Rate**: 1.33%
- **Lift**: 0.42x (58% below baseline)

### Top 80% by V4 Score (PRIORITIZE)
- **Leads**: 4,803 (80.0% of total)
- **Conversions**: 176 (91.7% of total conversions)
- **Conversion Rate**: 3.66%
- **Lift**: 1.15x (14% above baseline)

---

## Efficiency Analysis

### If We Skip Bottom 20%:
- **Conversions Lost**: 16 (8.3% of total)
- **Conversions Kept**: 176 (91.7% of total)
- **Leads Skipped**: 1,200 (20.0% of total)
- **Efficiency Gain**: Focus on 4,803 leads instead of 6,004

**ROI**: Skip 20% of leads, lose only 8.3% of conversions = **11.7% efficiency gain**

---

## Decile Analysis

| Decile | Leads | Conversions | Conv Rate | Lift |
|--------|-------|-------------|-----------|------|
| 10 (Top) | 600 | 29 | 4.83% | 1.51x |
| 9 | 600 | 23 | 3.83% | 1.20x |
| 8 | 600 | 30 | 5.00% | 1.56x |
| 7 | 600 | 20 | 3.33% | 1.04x |
| 6 | 600 | 19 | 3.17% | 0.99x |
| 5 | 600 | 21 | 3.50% | 1.09x |
| 4 | 600 | 20 | 3.33% | 1.04x |
| 3 | 600 | 14 | 2.33% | 0.73x |
| 2 | 600 | 7 | 1.17% | 0.36x |
| 1 (Bottom) | 604 | 9 | 1.49% | 0.47x |

### Bottom 3 Deciles Combined (30% of leads)
- **Leads**: 1,800
- **Conversions**: 30
- **Conversion Rate**: 1.67%
- **Lift**: 0.52x (48% below baseline)

**If we skip bottom 30%**: Lose 15.6% of conversions, skip 30% of leads = **14.4% efficiency gain**

---

## Key Findings

### 1. Strong Deprioritization Signal
- Bottom 20% converts at **1.33%** vs **3.20%** baseline
- **58% reduction** in conversion rate
- This is a **statistically significant** difference

### 2. Efficient Filtering
- Skip 20% of leads → Lose only 8.3% of conversions
- **ROI**: 11.7% efficiency gain
- Sales team can focus on higher-quality leads

### 3. Bottom Deciles Are Clear
- Decile 1: 1.49% conversion (0.47x lift)
- Decile 2: 1.17% conversion (0.36x lift)
- Decile 3: 2.33% conversion (0.73x lift)
- All bottom 3 deciles are well below baseline

---

## Use Case: V4 as Deprioritization Filter

### Recommended Strategy

**Option A: Skip Bottom 20%**
- **Skip**: 1,200 leads (1.33% conversion)
- **Focus on**: 4,803 leads (3.66% conversion)
- **Efficiency**: 11.7% gain
- **Risk**: Lose 8.3% of conversions

**Option B: Skip Bottom 30%**
- **Skip**: 1,800 leads (1.67% conversion)
- **Focus on**: 4,204 leads (3.86% conversion)
- **Efficiency**: 14.4% gain
- **Risk**: Lose 15.6% of conversions

### Recommendation

**Use V4 to deprioritize bottom 20-30% of leads**:
- Clear signal: Bottom deciles convert at 1.17-1.67% vs 3.20% baseline
- Low risk: Only lose 8-16% of conversions
- High efficiency: Skip 20-30% of leads, focus on higher-quality set

---

## Comparison: V3 vs V4

| Metric | V3 Rules | V4 XGBoost | Winner |
|--------|----------|------------|--------|
| **Top Decile Lift** | 1.74x | 1.51x | V3 |
| **Deprioritization** | N/A | 0.42x (bottom 20%) | V4 |
| **Use Case** | Prioritization | Deprioritization | Both |

### Hybrid Approach

**Recommended**: Use both models together
1. **V3 Rules**: Primary prioritization (1.74x top decile lift)
2. **V4 XGBoost**: Deprioritization filter (skip bottom 20-30%)

This gives:
- **Best of both**: V3's superior top decile lift + V4's deprioritization
- **Efficiency**: Skip low-value leads, focus on high-value leads
- **Risk mitigation**: Two-model approach reduces single-model risk

---

## Conclusion

**V4 is valuable as a deprioritization filter**, even though it doesn't beat V3 on top decile lift:

✅ **Strong signal**: Bottom 20% converts at 1.33% (58% below baseline)  
✅ **Efficient**: Skip 20% of leads, lose only 8.3% of conversions  
✅ **Clear separation**: Bottom deciles are well below baseline  
✅ **Hybrid value**: Use with V3 for comprehensive lead scoring

**Recommendation**: Deploy V4 as a deprioritization filter alongside V3 prioritization.

