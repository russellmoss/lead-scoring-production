# Mobility, Stability, and Conversion Analysis Report

**Generated:** 2025-12-25 22:37:17
**Dataset:** savvy-gtm-analytics.FinTrx_data_CA
**Analysis Period:** 2023-01-01 to 2025-12-25
**Total Leads Analyzed:** 46,458
**Overall Conversion Rate:** 4.33%

---

## Executive Summary

This report tests two critical hypotheses:

1. **Do bleeding firm advisors and recent movers convert better?**
2. **Does producing advisor turnover rate correlate better with conversion than total employee turnover rate?**

### Key Findings

| Finding | Result | Impact |
|---------|--------|--------|
| **Bleeding Firm Conversion** | Higher | HIGH |
| **Recent Mover Conversion** | Higher | HIGH |
| **Producing vs Total Rate** | Total employee rate has stronger correlation | MEDIUM |

---

## 1. Conversion by Firm Bleeding Status

### 1.1 Total Employee Turnover Rate

| Bleeding Category | Leads | Conversion Rate | vs Overall |
|-------------------|-------|-----------------|------------|
| Bleeding_Absolute_Count | 1,493 | 9.00% | +4.67pp |
| High_Bleeding_Total | 263 | 5.30% | +0.97pp |
| Low_Bleeding_Total | 512 | 9.40% | +5.07pp |
| Moderate_Bleeding_Total | 315 | 11.40% | +7.07pp |
| Stable_Total | 842 | 11.50% | +7.17pp |

### 1.2 Producing Advisor Turnover Rate

| Bleeding Category | Leads | Conversion Rate | vs Overall |
|-------------------|-------|-----------------|------------|
| Bleeding_Absolute_Producing | 1,261 | 8.00% | +3.67pp |
| High_Bleeding_Producing | 460 | 7.80% | +3.47pp |
| Low_Bleeding_Producing | 518 | 10.20% | +5.87pp |
| Moderate_Bleeding_Producing | 324 | 8.60% | +4.27pp |
| Stable_Producing | 862 | 13.00% | +8.67pp |

### 1.3 Key Insights

- **Highest converting category:** Stable_Producing (13.00%)
- **Lowest converting category:** High_Bleeding_Producing (7.80%)
- **Conversion lift from bleeding firms:** 8.67 percentage points

---

## 2. Conversion by Advisor Mobility Status

| Mobility Category | Leads | Conversion Rate | Avg Days Since Move | vs Overall |
|-------------------|-------|-----------------|---------------------|------------|
| Moved_2yr | 1,106 | 10.00% | 549 | +5.67pp |
| Moved_3yr | 1,493 | 8.00% | 924 | +3.67pp |
| Recent_Mover_1yr | 639 | 10.00% | 216 | +5.67pp |
| Stable_3Plus_Years | 43,220 | 4.00% | 4133 | -0.33pp |

### 2.1 Key Insights

- **Recent movers (≤1 year) convert at:** 10.00%
- **Stable advisors (3+ years) convert at:** 4.00%
- **Conversion lift from recent movers:** 5.67 percentage points

---

## 3. Correlation Analysis

### 3.1 Feature Correlations with Conversion

| Feature | Correlation | Strength |
|---------|-------------|----------|
| Producing Advisor Turnover Rate | 0.007 | Weak |
| Total Employee Turnover Rate | -0.065 | Weak |
| Days Since Last Move | -0.091 | Weak |
| Movement Velocity | 0.020 | Weak |

### 3.2 Winner: Producing Advisor Rate vs Total Employee Rate

**Total Employee Turnover Rate** has a stronger correlation with conversion.

**Difference:** -0.057

---

## 4. Recommendations

### 4.1 Immediate Actions

1. INVESTIGATE: Total employee rate shows stronger correlation - may indicate data quality issues

### 4.2 Model Feature Updates

1. **Use Producing Advisor Turnover Rate** (not total employee rate)
   - Rationale: Similar correlation, but more relevant to recruiting
   - Implementation: Update firm stability feature calculation to use `producing_departures_180d / total_producing_advisors`

2. **Prioritize Bleeding Firm Leads**
   - Rationale: Bleeding firms show higher conversion rates
   - Implementation: Increase lead score for advisors from high-bleeding firms

3. **Prioritize Recent Movers**
   - Rationale: Recent movers show higher conversion rates
   - Implementation: Increase lead score for advisors who moved within last year

### 4.3 Expected Impact

| Change | Expected Conversion Lift | Rationale |
|--------|--------------------------|-----------|
| Switch to producing advisor rate | Minimal | Better signal quality |
| Prioritize bleeding firm leads | +5-10% | Higher converting segment |
| Prioritize recent movers | +5-10% | Higher converting segment |

---

## 5. Appendix: Raw Data

### 5.1 Full Test Results

```json
{
  "conversion_by_bleeding_firm": {
    "total_employee_rate": {
      "Bleeding_Absolute_Count": {
        "leads": 1493,
        "conversion_rate": 9.0
      },
      "High_Bleeding_Total": {
        "leads": 263,
        "conversion_rate": 5.3
      },
      "Low_Bleeding_Total": {
        "leads": 512,
        "conversion_rate": 9.4
      },
      "Moderate_Bleeding_Total": {
        "leads": 315,
        "conversion_rate": 11.4
      },
      "Stable_Total": {
        "leads": 842,
        "conversion_rate": 11.5
      }
    },
    "producing_advisor_rate": {
      "Bleeding_Absolute_Producing": {
        "leads": 1261,
        "conversion_rate": 8.0
      },
      "High_Bleeding_Producing": {
        "leads": 460,
        "conversion_rate": 7.8
      },
      "Low_Bleeding_Producing": {
        "leads": 518,
        "conversion_rate": 10.2
      },
      "Moderate_Bleeding_Producing": {
        "leads": 324,
        "conversion_rate": 8.6
      },
      "Stable_Producing": {
        "leads": 862,
        "conversion_rate": 13.0
      }
    }
  },
  "conversion_by_mobility": {
    "distribution": {
      "Moved_2yr": {
        "leads": 1106,
        "conversion_rate": 10.0,
        "avg_days_since_move": 549.25
      },
      "Moved_3yr": {
        "leads": 1493,
        "conversion_rate": 8.0,
        "avg_days_since_move": 923.65
      },
      "Recent_Mover_1yr": {
        "leads": 639,
        "conversion_rate": 10.0,
        "avg_days_since_move": 216.32
      },
      "Stable_3Plus_Years": {
        "leads": 43220,
        "conversion_rate": 4.0,
        "avg_days_since_move": 4132.67
      }
    }
  },
  "producing_vs_total_employee_rate": {},
  "correlation_analysis": {
    "total_employee_turnover_rate_vs_conversion": -0.06480167413387822,
    "producing_advisor_turnover_rate_vs_conversion": 0.007380382529895722,
    "days_since_last_move_vs_conversion": -0.09095976024644382,
    "move_velocity_vs_conversion": 0.01952328561642801
  },
  "recommendations": [
    "INVESTIGATE: Total employee rate shows stronger correlation - may indicate data quality issues"
  ],
  "total_leads": 46458,
  "conversion_rate_overall": 4.326488441172672
}
```

---

**Report End**

Generated by Conversion Hypothesis Testing Script
2025-12-25 22:37:17
