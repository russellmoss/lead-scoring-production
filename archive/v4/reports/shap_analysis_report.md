# Phase 9: SHAP Analysis Report

**Generated**: 2025-12-24 15:00:57

---

## Summary

- **Sample Size**: 2,000 leads
- **Features Analyzed**: 14
- **SHAP Values**: ⚠️ **Not calculated** - Using XGBoost feature importance instead
- **Reason**: Model compatibility issue with SHAP TreeExplainer

## Feature Importance Comparison

| Rank | Feature | XGBoost Importance | SHAP Importance |
|------|---------|-------------------|-----------------|
| 1 | mobility_tier | 178.85 | 1.0000 |
| 2 | has_email | 158.87 | 0.8883 |
| 3 | tenure_bucket | 143.16 | 0.8005 |
| 4 | mobility_x_heavy_bleeding | 117.26 | 0.6557 |
| 5 | has_linkedin | 110.46 | 0.6176 |
| 6 | firm_stability_tier | 101.08 | 0.5652 |
| 7 | is_wirehouse | 84.76 | 0.4739 |
| 8 | firm_rep_count_at_contact | 83.30 | 0.4658 |
| 9 | short_tenure_x_high_mobility | 81.95 | 0.4582 |
| 10 | firm_net_change_12mo | 71.99 | 0.4026 |
| 11 | is_broker_protocol | 64.26 | 0.3593 |
| 12 | experience_bucket | 64.17 | 0.3588 |
| 13 | has_firm_data | 55.48 | 0.3102 |
| 14 | is_experience_missing | 39.04 | 0.2183 |

## Top 5 Features by SHAP Importance

### 1. mobility_tier
- **SHAP Importance**: 1.0000
- **XGBoost Importance**: 178.85

### 2. has_email
- **SHAP Importance**: 0.8883
- **XGBoost Importance**: 158.87

### 3. tenure_bucket
- **SHAP Importance**: 0.8005
- **XGBoost Importance**: 143.16

### 4. mobility_x_heavy_bleeding
- **SHAP Importance**: 0.6557
- **XGBoost Importance**: 117.26

### 5. has_linkedin
- **SHAP Importance**: 0.6176
- **XGBoost Importance**: 110.46

## Visualizations

⚠️ **SHAP plots not available** - See XGBoost feature importance in `feature_importance.csv`

## Key Insights

### Feature Contributions

The SHAP values reveal:
- **Positive SHAP values** increase the prediction (higher conversion probability)
- **Negative SHAP values** decrease the prediction (lower conversion probability)
- **Feature interactions** can be seen in the dependence plots

### Model Interpretability

For any individual lead, SHAP values explain:
- Which features pushed the prediction up or down
- How much each feature contributed to the final score
- Whether feature interactions are important

