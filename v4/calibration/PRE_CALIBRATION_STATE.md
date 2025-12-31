# Pre-Calibration State

## Path Discovery Results (from Step 0.5)

| Item | Value |
|------|-------|
| ACTUAL_MODEL_DIR | v4/models/v4.1.0_r3 |
| ACTUAL_DATA_DIR | v4/data/v4.1.0_r3 |
| CRD_COLUMN_NAME | crd (v4_prospect_scores) / advisor_crd (v4_target_variable) |
| SCORING_SCRIPT_PATTERN | Pattern A (simple: scores = score_prospects(model, X)) |

## File Checksums (Before)

| File | MD5 Checksum |
|------|--------------|
| model.pkl | 3bad9038854afa544d8d0b41180e9457 |
| model.json | ce9a7517eeab406227d84bf92e0c770f |
| hyperparameters.json | 2d8d614cc3c95970c156aea405ee82a3 |
| final_features.json | bb3b36d894b8e1360682265b80756eaf |

## Baseline Lift Curve (Before Calibration)

| Decile | N | Conversions | Conv Rate | Lift |
|--------|---|-------------|-----------|------|
| 1 (bottom) | 7,373 | 92 | 1.25% | 0.53x |
| 2 | 7,373 | 130 | 1.76% | 0.74x |
| 3 | 7,373 | 110 | 1.49% | 0.63x |
| 4 | 7,373 | 82 | 1.11% | 0.47x |
| 5 | 7,373 | 85 | 1.15% | 0.49x |
| 6 | 7,372 | 139 | 1.89% | 0.80x |
| 7 | 7,372 | 210 | 2.85% | 1.20x |
| 8 | 7,372 | 291 | 3.95% | 1.67x |
| 9 | 7,372 | 302 | 4.10% | 1.73x |
| 10 (top) | 7,372 | 306 | 4.15% | 1.75x |

## Non-Monotonicity Detected

- Decile 3: 0.63x (higher than decile 4) ❌
- Decile 4: 0.47x (lower than decile 3) ❌
- Decile 5: 0.49x (lower than decile 3) ❌
- Decile 6: 0.80x (finally higher than decile 3)

**Problem**: Deciles 4-5 have lower lift than decile 3, breaking monotonicity. This means percentile rankings are unreliable for within-tier sorting.

## BigQuery Tables Used

- **Scores Table**: `savvy-gtm-analytics.ml_features.v4_prospect_scores` (has `crd` column)
- **Target Table**: `savvy-gtm-analytics.ml_features.v4_target_variable` (has `advisor_crd` column)
- **Join**: `s.crd = t.advisor_crd`
- **Filter**: `contacted_date >= '2024-10-01' AND target IS NOT NULL`

## Scoring Script Pattern

**File**: `pipeline/scripts/score_prospects_monthly.py`

**Pattern**: Pattern A (Simple)
```python
# Score
scores = score_prospects(model, X)
percentiles = calculate_percentiles(scores)
```

**Location**: Lines 815-816

