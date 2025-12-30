# V4.1 Multicollinearity Analysis Report

**Generated**: 2025-12-30 13:02:42  
**Status**: FAILED

## Executive Summary

This report analyzes multicollinearity among all 23 V4.1 features to identify
redundant features that may hurt model stability. High multicollinearity (|r| > 0.7)
or high VIF (>10) indicates features that may need to be removed or combined.

## Summary Statistics

- **Total features analyzed**: 23
- **Original V4 features**: 14
- **New V4.1 bleeding features**: 5
- **New V4.1 firm/rep type features**: 4
- **Critical correlation pairs (|r| > 0.85)**: 4
- **Critical VIF (>10)**: 8
- **Average VIF for new features**: 8.42

## Validation Gates

### G5.1: No feature pair has |correlation| > 0.85
**Status**: [FAIL] FAILED

- Critical correlation pairs: 4
- High correlation pairs (0.7-0.85): 2

### G5.2: No feature has VIF > 10
**Status**: [FAIL] FAILED

- Features with VIF > 10: 8
- Features with VIF 5-10: 3

### G5.3: New features add independent signal (not redundant)
**Status**: [PASS] PASSED

- Average VIF for new features: 8.42
- New features appear to add independent signal

## VIF Results

| Feature | VIF | Status | Category |
|---------|-----|--------|----------|
| experience_years | 55.51 | CRITICAL | Original V4 |
| industry_tenure_months | 54.04 | CRITICAL | Original V4 |
| mobility_3yr | 24.8 | CRITICAL | Original V4 |
| independent_ria_x_ia_rep | 22.35 | CRITICAL | New Firm/Rep |
| has_firm_data | 20.32 | CRITICAL | Original V4 |
| is_ia_rep_type | 20.19 | CRITICAL | New Firm/Rep |
| tenure_bucket_x_mobility | 17.21 | CRITICAL | Original V4 |
| has_linkedin | 13.94 | CRITICAL | Original V4 |
| is_recent_mover | 6.55 | WARNING | New Bleeding |
| recent_mover_x_bleeding | 6.4 | WARNING | New Bleeding |
| tenure_months | 5.34 | WARNING | Original V4 |
| bleeding_velocity_encoded | 4.63 | OK | New Bleeding |
| short_tenure_x_high_mobility | 4.35 | OK | Original V4 |
| is_independent_ria | 4.33 | OK | New Firm/Rep |
| is_dual_registered | 4.25 | OK | New Firm/Rep |
| firm_departures_corrected | 4.07 | OK | New Bleeding |
| days_since_last_move | 3.02 | OK | New Bleeding |
| has_email | 2.92 | OK | Original V4 |
| firm_net_change_12mo | 2.3 | OK | Original V4 |
| mobility_x_heavy_bleeding | 2.14 | OK | Original V4 |
| is_wirehouse | 2.07 | OK | Original V4 |
| firm_rep_count_at_contact | 1.62 | OK | Original V4 |
| is_broker_protocol | 1.47 | OK | Original V4 |

## High Correlation Pairs (|r| > 0.7)

| Feature 1 | Feature 2 | Correlation | Status |
|-----------|-----------|-------------|--------|
| is_ia_rep_type | independent_ria_x_ia_rep | 0.9669 | CRITICAL |
| industry_tenure_months | experience_years | 0.9632 | CRITICAL |
| mobility_3yr | tenure_bucket_x_mobility | 0.9370 | CRITICAL |
| is_recent_mover | recent_mover_x_bleeding | 0.9042 | CRITICAL |
| is_independent_ria | independent_ria_x_ia_rep | 0.8148 | WARNING |
| is_independent_ria | is_ia_rep_type | 0.7825 | WARNING |

## Expected Correlations

The following correlations are expected and acceptable:

- **is_ia_rep_type vs is_dual_registered**: Mutually exclusive (correlation ≈ -1.0)
  - This is by design - advisors are either IA-only or dual-registered
  - VIF may be high, but both features provide signal (positive vs negative)
  
- **is_independent_ria vs is_ia_rep_type**: Moderate correlation (~0.4-0.6)
  - Independent RIAs often have IA-only advisors
  - Both features add value, correlation is acceptable
  
- **is_recent_mover vs mobility_3yr**: Moderate correlation expected
  - Both measure advisor movement, but at different time scales
  - Recent mover is 12-month window, mobility_3yr is 3-year window
  
- **firm_departures_corrected vs firm_net_change_12mo**: Moderate correlation expected
  - Both measure firm stability, but from different angles
  - Departures is count-based, net_change includes arrivals

## Recommendations

- **Remove features with VIF > 10**: experience_years, industry_tenure_months, mobility_3yr, independent_ria_x_ia_rep, has_firm_data, is_ia_rep_type, tenure_bucket_x_mobility, has_linkedin
- **Review critical correlation pairs**: 4 pairs with |r| > 0.85
  - mobility_3yr vs tenure_bucket_x_mobility (r=0.9370)
  - industry_tenure_months vs experience_years (r=0.9632)
  - is_recent_mover vs recent_mover_x_bleeding (r=0.9042)
  - is_ia_rep_type vs independent_ria_x_ia_rep (r=0.9669)

## Conclusion

One or more validation gates failed. Review recommendations above before proceeding.
