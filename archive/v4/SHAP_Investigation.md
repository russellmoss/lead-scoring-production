# SHAP Investigation Report

**Date**: 2025-12-30 13:58:03
**Status**: SHAP WORKING
**Working Fix**: Fix 4: KernelExplainer

## Fix Attempts Summary

| Fix | Status |
|-----|--------|
| Fix 1: Patch JSON | Failed |
| Fix 2: Patch Config | Failed |
| Fix 3: Background Data | Failed |
| Fix 4: KernelExplainer | Success |


## SHAP Analysis Results

**SHAP Values Shape**: (200, 22)

### Top 10 Features by SHAP Importance

| Rank | Feature | SHAP Importance | New V4.1? |
|------|---------|-----------------|-----------|
| 1 | has_email | 0.0429 | No |
| 2 | tenure_months | 0.0299 | No |
| 3 | tenure_bucket_encoded | 0.0158 | No |
| 4 | days_since_last_move | 0.0133 | Yes |
| 5 | is_dual_registered | 0.0122 | Yes |
| 6 | has_firm_data | 0.0100 | No |
| 7 | firm_departures_corrected | 0.0093 | Yes |
| 8 | mobility_3yr | 0.0079 | No |
| 9 | firm_net_change_12mo | 0.0048 | No |
| 10 | short_tenure_x_high_mobility | 0.0034 | No |


### New V4.1 Features in Top 10

**Count**: 3 / 7 new features in top 10

| Feature | Rank |
|---------|------|
| days_since_last_move | 4 |
| is_dual_registered | 5 |
| firm_departures_corrected | 7 |


## Files Generated

- `v4/reports/v4.1/shap_summary_r3.png` - SHAP summary plot
- `v4/reports/v4.1/shap_bar_r3.png` - SHAP bar plot
- `v4/reports/v4.1/shap_importance_r3.csv` - Feature importance CSV

## Conclusion

SHAP is now working via Fix 4: KernelExplainer.

The model is interpretable and ready for deployment.
