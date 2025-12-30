# Additional Wirehouse/Insurance BD Exclusions

**Date**: 2025-12-30  
**Status**: ✅ **COMPLETE**

---

## Exclusions Added

### Insurance Broker-Dealers
- `'%ONEAMERICA%'` - Oneamerica Securities, Inc. (7 advisors excluded)
- `'%M HOLDINGS SECURITIES%'` - M Holdings Securities, Inc. (4 advisors excluded)
- `'%NUVEEN SECURITIES%'` - Nuveen Securities, Llc (1 advisor excluded)

### Wirehouse/Bank Subsidiaries
- `'%BMO NESBITT%'` - BMO Nesbitt Burns Securities Ltd. (1 advisor excluded)
- `'%NESBITT BURNS%'` - Alternative pattern for BMO (1 advisor excluded)

**Total Advisors Excluded**: ~14 advisors

---

## Verification Results

### ✅ Excluded Firms Check
```sql
SELECT firm_name, COUNT(*) as advisors
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE UPPER(firm_name) LIKE '%ONEAMERICA%'
   OR UPPER(firm_name) LIKE '%M HOLDINGS%'
   OR UPPER(firm_name) LIKE '%NUVEEN SECURITIES%'
   OR UPPER(firm_name) LIKE '%BMO NESBITT%'
   OR UPPER(firm_name) LIKE '%NESBITT BURNS%'
GROUP BY firm_name;
```
**Result**: 0 rows ✅ (All excluded firms removed)

### ✅ Lead Count Maintained
- **Total Leads**: 2,800 ✅
- **Unique CRDs**: 2,800 ✅
- **Duplicates**: 0 ✅
- **SGAs**: 14 ✅
- **Leads per SGA**: 200 each ✅

### ✅ Tier Distribution
| Tier | Leads | % |
|------|-------|---|
| STANDARD_HIGH_V4 | 1,705 | 60.9% |
| TIER_2_PROVEN_MOVER | 704 | 25.1% |
| TIER_1_PRIME_MOVER | 278 | 9.9% |
| TIER_1B_PRIME_MOVER_SERIES65 | 70 | 2.5% |
| TIER_1F_HV_WEALTH_BLEEDER | 38 | 1.4% |
| TIER_3_MODERATE_BLEEDER | 5 | 0.2% |

**Note**: Tier distribution slightly adjusted due to excluded advisors being replaced with backfill leads.

---

## Files Updated

1. ✅ `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
2. ✅ `pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Changes**:
- Added `'%BMO NESBITT%'`, `'%NESBITT BURNS%'` to Wirehouses section (line 71)
- Added `'%ONEAMERICA%'`, `'%M HOLDINGS SECURITIES%'`, `'%NUVEEN SECURITIES%'` to Insurance section (line 76)

---

## Table Regenerated

✅ **Table**: `savvy-gtm-analytics.ml_features.january_2026_lead_list`  
✅ **Total Leads**: 2,800 (maintained)  
✅ **All Excluded Firms Removed**: 0 advisors from excluded firms ✅

---

## Complete Exclusion List (Updated)

### Wirehouses
- J.P. Morgan, Morgan Stanley, Merrill, Wells Fargo
- UBS, Edward Jones, Ameriprise
- Northwestern Mutual, Prudential, **Pruco**, Raymond James
- Fidelity, Schwab, Vanguard, Goldman Sachs, Citigroup
- LPL Financial, Commonwealth, Cetera, Cambridge
- OSAIC, Primerica
- **BMO Nesbitt, Nesbitt Burns** (NEW)

### Insurance
- State Farm, Allstate, New York Life, NYLIFE
- Transamerica, Farm Bureau, Nationwide
- Lincoln Financial, Mass Mutual, MassMutual
- **Oneamerica, M Holdings Securities, Nuveen Securities** (NEW)
- Insurance (catch-all)

### Specific Firms
- Savvy Wealth, Savvy Advisors
- Ritholtz

---

**Updated**: 2025-12-30

