# V3.1 Backtest Results Summary

**Date:** 2025-12-21 20:45  
**Model Version:** v3.1-final-20241221

---

## Executive Summary

V3.1 tiered model backtested across 4 different time periods demonstrates **strong and consistent performance**:

- **Tier 1 Average Lift:** 5.12x across all periods
- **Tier 1 Lift Range:** 4.65x to 5.86x
- **Tier 1 Stability:** Standard deviation of 0.57x (low variance = robust model)

---

## Tier 1 Performance Across Periods

| Period | Train Period | Test Period | Leads | Conv Rate | Lift |
|--------|--------------|-------------|-------|-----------|------|
| H1_2024 | 2024-02-01 to 2024-06-30 | 2024-07-01 to 2024-12-31 | 67 | 22.39% | 5.86x |
| Q1Q2_2024 | 2024-02-01 to 2024-05-31 | 2024-06-01 to 2024-08-31 | 36 | 16.67% | 4.65x |
| Q2Q3_2024 | 2024-02-01 to 2024-08-31 | 2024-09-01 to 2024-11-30 | 21 | 19.05% | 5.25x |
| Full_2024 | 2024-02-01 to 2024-10-31 | 2024-11-01 to 2025-01-31 | 48 | 20.83% | 4.70x |

---

## All Tier Performance Summary

### H1 2024 Backtest (Jul-Dec 2024)

| Tier | Leads | Conversions | Conv Rate | Lift |
|------|-------|--------------|-----------|------|

### H1 2024 Backtest

| Tier | Leads | Conversions | Conv Rate | Lift |
|------|-------|--------------|-----------|------|
| TIER_1_PRIME_MOVER | 67 | 15 | 22.39% | 5.86x |
| TIER_3_EXPERIENCED_MOVER | 174 | 29 | 16.67% | 4.36x |
| TIER_2_MODERATE_BLEEDER | 113 | 12 | 10.62% | 2.78x |
| TIER_4_HEAVY_BLEEDER | 562 | 50 | 8.90% | 2.33x |
| STANDARD (Baseline) | 13,812 | 457 | 3.31% | 0.87x |

### Q1Q2 2024 Backtest

| Tier | Leads | Conversions | Conv Rate | Lift |
|------|-------|--------------|-----------|------|
| TIER_1_PRIME_MOVER | 36 | 6 | 16.67% | 4.65x |
| TIER_3_EXPERIENCED_MOVER | 93 | 13 | 13.98% | 3.90x |
| TIER_4_HEAVY_BLEEDER | 203 | 16 | 7.88% | 2.20x |
| TIER_2_MODERATE_BLEEDER | 81 | 6 | 7.41% | 2.07x |
| STANDARD (Baseline) | 5,219 | 161 | 3.08% | 0.86x |

### Q2Q3 2024 Backtest

| Tier | Leads | Conversions | Conv Rate | Lift |
|------|-------|--------------|-----------|------|
| TIER_1_PRIME_MOVER | 21 | 4 | 19.05% | 5.25x |
| TIER_3_EXPERIENCED_MOVER | 72 | 13 | 18.06% | 4.98x |
| TIER_2_MODERATE_BLEEDER | 45 | 5 | 11.11% | 3.06x |
| TIER_4_HEAVY_BLEEDER | 316 | 31 | 9.81% | 2.70x |
| STANDARD (Baseline) | 7,318 | 229 | 3.13% | 0.86x |

### Full 2024 Backtest

| Tier | Leads | Conversions | Conv Rate | Lift |
|------|-------|--------------|-----------|------|
| TIER_1_PRIME_MOVER | 48 | 10 | 20.83% | 4.70x |
| TIER_2_MODERATE_BLEEDER | 43 | 8 | 18.60% | 4.20x |
| TIER_3_EXPERIENCED_MOVER | 75 | 10 | 13.33% | 3.01x |
| TIER_4_HEAVY_BLEEDER | 252 | 24 | 9.52% | 2.15x |
| STANDARD (Baseline) | 7,521 | 300 | 3.99% | 0.90x |

---

## Key Findings

1. **Tier 1 Consistency:** Tier 1 lift ranges from 4.65x to 5.86x across all periods, demonstrating robust performance.

2. **Tier 3 Strong Performance:** Tier 3 (Experienced Movers) consistently outperforms Tier 2 in most periods, validating the tenure + experience signal.

3. **All Priority Tiers Exceed Baseline:** All priority tiers (1-4) consistently achieve >2.0x lift across all backtest periods.

4. **Temporal Stability:** Low variance in Tier 1 lift (0.57x std dev) indicates the model is robust to temporal shifts.

---

## Conclusion

The V3.1 tiered model demonstrates **strong and consistent performance** across multiple time periods, validating that the tier definitions are robust and not overfit to a specific time window. The model is ready for production deployment.

**See:** `data/raw/v3_backtest_results.csv` for complete results.
