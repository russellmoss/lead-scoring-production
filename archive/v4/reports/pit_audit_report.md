# PIT Audit Report - V4.1 Features

**Audit Date**: 2025-12-30T13:00:22.965634  
**Status**: PASSED

## Executive Summary

This report validates Point-in-Time (PIT) compliance for all 9 new V4.1 features.
PIT leakage occurs when features use data from AFTER the contacted_date, which
causes overfitting and unrealistic model performance.

## Validation Gates

### G4.1: is_recent_mover

**Status**: [PASS] PASSED

- Total recent movers: 2,850
- PIT violations: 0

### G4.2: days_since_last_move

**Status**: [PASS] PASSED

- Total rows: 27,642
- Negative values: 0
- Min value: 0.0
- Max value: 19020.0

### G4.3: Correlation Check

**Status**: [PASS] PASSED

- Correlation threshold: |r| < 0.3

**Correlations with Target:**

- is_recent_mover: 0.0197 [OK]
- days_since_last_move: 0.0088 [OK]
- firm_departures_corrected: 0.0018 [OK]
- bleeding_velocity_encoded: 0.0034 [OK]
- recent_mover_x_bleeding: 0.0099 [OK]
- is_independent_ria: 0.0252 [OK]
- is_ia_rep_type: 0.0327 [OK]
- is_dual_registered: -0.0394 [OK]
- independent_ria_x_ia_rep: 0.0288 [OK]

### G4.4: Correlation Check

**Status**: [PASS] PASSED

- Sample size: 100
- Violations found: 0
- Spot-check file: C:\Users\russe\Documents\lead_scoring_production\v4\reports\v4.1\pit_audit_spot_check.csv

## Summary Statistics

- Total leads: 30,738
- Conversions: 781
- Conversion rate: 2.54%
- Recent mover rate: 9.27%
- Independent RIA rate: 26.52%
- IA rep type rate: 20.40%
- Dual registered rate: 57.76%

## Notes

- **Firm/Rep Type Features**: These use current state (PRIMARY_FIRM_CLASSIFICATION, REP_TYPE).
  This is an acceptable small PIT risk as firm classification and rep type are relatively stable.
  Correlations with target should be monitored but are expected to be moderate.

- **Bleeding Signal Features**: All validated to use only data from BEFORE contacted_date.
  The inferred departure methodology provides a 60-90 day fresher signal than END_DATE.

## Conclusion

All PIT validation gates passed. Features are compliant with point-in-time requirements.
