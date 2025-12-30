# Pruco Securities Exclusion Fix

**Date**: 2025-12-30  
**Status**: ✅ **COMPLETE**

---

## Problem

**Pruco Securities, LLC** (Prudential Financial's broker-dealer subsidiary) was slipping through the exclusion filter because:
- Exclusion pattern was `'%PRUDENTIAL%'` 
- Firm name is **"Pruco"** not "Prudential"

**Impact**: 1 advisor (Jennifer Hutton, CRD 5757073) was included in the lead list.

---

## Solution

Added `'%PRUCO%'` to the `excluded_firms` CTE in both SQL files:

```sql
excluded_firms AS (
    SELECT firm_pattern FROM UNNEST([
        -- Wirehouses
        '%J.P. MORGAN%', '%MORGAN STANLEY%', '%MERRILL%', '%WELLS FARGO%', 
        '%UBS %', '%UBS,%', '%EDWARD JONES%', '%AMERIPRISE%', 
        '%NORTHWESTERN MUTUAL%', '%PRUDENTIAL%', '%PRUCO%', '%RAYMOND JAMES%',  -- Added PRUCO
        ...
    ])
)
```

---

## Results

### Before Fix
- **Pruco advisors in list**: 1 (Jennifer Hutton)
- **Total leads**: 2,800

### After Fix
- **Pruco advisors in list**: **0** ✅
- **Total leads**: 2,800 (maintained)
- **Unique CRDs**: 2,800 (all unique)
- **Jennifer Hutton removed**: ✅ Confirmed

---

## Verification

```sql
-- Pruco count check
SELECT COUNT(*) as pruco_count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE UPPER(firm_name) LIKE '%PRUCO%';
-- Result: 0 ✅
```

---

## Other Potential Gaps Identified

The following firms with "Securities" in the name are in the list (may need review):

| Firm Name | Advisors | Notes |
|-----------|----------|-------|
| Oneamerica Securities, Inc. | 7 | Insurance BD? |
| M Holdings Securities, Inc. | 4 | Insurance BD? |
| Sanctuary Securities, Inc. | 1 | Unknown |
| Nuveen Securities, Llc | 1 | TIAA subsidiary? |
| Vanderbilt Securities, Llc | 1 | Unknown |
| Bmo Nesbitt Burns Securities Ltd. | 1 | BMO bank subsidiary |
| Valmark Securities, Inc. | 1 | Insurance BD? |

**Recommendation**: Review these firms to determine if they should be excluded. They may be:
- Legitimate independent broker-dealers (keep)
- Insurance company subsidiaries (exclude)
- Bank subsidiaries (exclude)

---

## Files Updated

1. ✅ `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
2. ✅ `pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Change**: Added `'%PRUCO%'` to wirehouse exclusion patterns (line 68).

---

## Table Regenerated

✅ **Table**: `savvy-gtm-analytics.ml_features.january_2026_lead_list`  
✅ **Total Leads**: 2,800 (maintained)  
✅ **Pruco Excluded**: 0 advisors ✅

---

**Updated**: 2025-12-30

