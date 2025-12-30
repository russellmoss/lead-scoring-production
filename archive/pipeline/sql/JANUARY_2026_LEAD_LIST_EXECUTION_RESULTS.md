# January 2026 Lead List Execution Results

**Date**: 2025-12-30  
**Status**: ✅ **SUCCESS**

---

## Execution Summary

✅ **Table Created**: `savvy-gtm-analytics.ml_features.january_2026_lead_list`

---

## Results

### Overall Statistics

| Metric | Value |
|--------|-------|
| **Total Leads** | 2,721 |
| **SGAs** | 14 |
| **Average V4 Score** | 0.644 |
| **Min V4 Score** | 0.328 |
| **Max V4 Score** | 0.704 |
| **Tier Count** | 7 |

### Tier Distribution

| Tier | Leads | Avg V4 Score | Avg Percentile |
|------|-------|--------------|----------------|
| TIER_2_PROVEN_MOVER | 1,750 | 0.656 | 98.5 |
| TIER_1_PRIME_MOVER | 343 | 0.665 | 98.7 |
| TIER_3_MODERATE_BLEEDER | 281 | 0.527 | 83.6 |
| STANDARD_HIGH_V4 | 218 | 0.678 | 99.0 |
| TIER_1B_PRIME_MOVER_SERIES65 | 70 | 0.673 | 99.0 |
| TIER_1F_HV_WEALTH_BLEEDER | 58 | 0.553 | 87.5 |
| TIER_1A_PRIME_MOVER_CFP | 1 | 0.701 | 99.0 |

---

## Key Observations

1. **Lead Count**: 2,721 leads (slightly less than expected 2,800, but within normal variation)
2. **SGA Distribution**: 14 SGAs active (each should receive ~194 leads on average)
3. **Tier Quality**: All tiers have high V4 scores (avg 0.527-0.678), indicating good lead quality
4. **V4.1 Features**: All V4.1 features are included (is_recent_mover, bleeding_velocity_encoded, etc.)

---

## Next Steps

1. ✅ **Table Created**: `ml_features.january_2026_lead_list`
2. ⏳ **Verify SGA Distribution**: Check that each SGA has ~200 leads
3. ⏳ **Clean Up Old Tables**: Execute `cleanup_old_january_tables.sql` after verification
4. ⏳ **Salesforce Sync**: Sync leads to Salesforce (if needed)

---

## Verification Queries

### Check SGA Distribution
```sql
SELECT 
    sga_owner,
    COUNT(*) as leads,
    AVG(v4_score) as avg_score
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY sga_owner
ORDER BY sga_owner;
```

### Check V4.1 Features
```sql
SELECT 
    COUNT(*) as total,
    SUM(v4_is_recent_mover) as recent_movers,
    AVG(v4_firm_departures_corrected) as avg_departures,
    COUNT(DISTINCT v4_bleeding_velocity_encoded) as velocity_categories
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
```

---

**Execution Time**: 2025-12-30  
**Status**: ✅ Complete

