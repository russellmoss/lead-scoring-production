# Duplicate Lead Fix - January 2026 Lead List

**Date**: 2025-12-30  
**Status**: ✅ **FIXED**

---

## Problem

The lead list contained duplicate advisors (same CRD appearing multiple times):
- **Jennifer Hutton** (CRD 5757073): Appeared **50 times** across 14 SGAs
- **John Geffert** (CRD 6115212): Appeared **16 times** across 14 SGAs
- **Total duplicates**: 1,162 (2,721 total rows - 1,559 unique CRDs)

**Root Cause**: The round-robin SGA assignment logic was assigning the same lead to multiple SGAs when the same CRD appeared multiple times in the pipeline (likely from multiple employment records or data joins).

---

## Solution

Added deduplication step in the `final_lead_list` CTE:

```sql
-- Deduplicate: Keep only the best instance of each CRD
final_lead_list AS (
    SELECT 
        fl.*
    FROM filtered_leads fl
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY fl.crd
        ORDER BY 
            fl.overall_rank ASC,  -- Best rank first
            fl.v4_percentile DESC,  -- Highest V4 score
            fl.sga_lead_rank ASC   -- First assigned SGA
    ) = 1
)
```

**Logic**: For each CRD, keep only the best-ranked instance:
1. Lowest `overall_rank` (highest priority)
2. Highest `v4_percentile` (best ML score)
3. Lowest `sga_lead_rank` (first assigned SGA)

---

## Results

### Before Fix
- **Total rows**: 2,721
- **Unique CRDs**: 1,559
- **Duplicates**: 1,162

### After Fix
- **Total rows**: 1,559
- **Unique CRDs**: 1,559
- **Duplicates**: **0** ✅

### Specific Examples

**Jennifer Hutton** (CRD 5757073):
- **Before**: 50 duplicate rows across 14 SGAs
- **After**: 1 row assigned to **Helen Kamens** (best rank: 123)

**John Geffert** (CRD 6115212):
- **Before**: 16 duplicate rows across 14 SGAs
- **After**: 1 row assigned to **Chris Morgan** (best rank: 190)

---

## Tier Distribution (After Fix)

| Tier | Leads | Unique CRDs | Avg Percentile |
|------|-------|-------------|----------------|
| TIER_2_PROVEN_MOVER | 705 | 705 | 98.5 |
| TIER_1_PRIME_MOVER | 279 | 279 | 98.7 |
| TIER_3_MODERATE_BLEEDER | 243 | 243 | 82.6 |
| STANDARD_HIGH_V4 | 218 | 218 | 99.0 |
| TIER_1B_PRIME_MOVER_SERIES65 | 70 | 70 | 99.0 |
| TIER_1F_HV_WEALTH_BLEEDER | 43 | 43 | 90.5 |
| TIER_1A_PRIME_MOVER_CFP | 1 | 1 | 99.0 |

**Total**: 1,559 leads, all unique ✅

---

## Files Updated

1. ✅ `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
2. ✅ `pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql` (duplicate)

**Change**: Added `filtered_leads` and `final_lead_list` CTEs with deduplication logic (lines 771-800).

---

## Table Regenerated

✅ **Table**: `savvy-gtm-analytics.ml_features.january_2026_lead_list`  
✅ **Total Leads**: 1,559 (down from 2,721)  
✅ **Unique CRDs**: 1,559 (100% unique)  
✅ **Duplicates**: 0

---

## Validation

✅ **No duplicates**: All 1,559 leads have unique CRDs  
✅ **Best instances kept**: Duplicates resolved by keeping highest-priority instance  
✅ **SGA assignment preserved**: Each lead assigned to exactly one SGA  
✅ **Tier distribution maintained**: All tiers still represented proportionally

---

## Conclusion

✅ **Fix successful**: All duplicates removed, each advisor appears exactly once in the lead list.

**Status**: ✅ **READY FOR PRODUCTION**

---

**Updated**: 2025-12-30  
**Validated By**: Automated Validation Queries

