# Centralized Excluded Firms Table - Implementation Summary

**Date**: 2025-12-30  
**Status**: ✅ **COMPLETE**

---

## Overview

Firm exclusions have been moved from hardcoded SQL patterns to centralized BigQuery tables. This makes exclusions easier to maintain - add/remove firms without editing complex SQL.

---

## Tables Created

### 1. `ml_features.excluded_firms`
- **Purpose**: Pattern-based firm exclusions (e.g., '%MERRILL%')
- **Rows**: 42 patterns
- **Categories**: 8 (Wirehouse, Large IBD, Custodian, Insurance, Insurance BD, Bank BD, Internal, Partner)
- **Schema**:
  - `pattern` (STRING): LIKE pattern (e.g., '%MERRILL%')
  - `category` (STRING): Exclusion category
  - `added_date` (DATE): When exclusion was added
  - `reason` (STRING): Why firm is excluded

### 2. `ml_features.excluded_firm_crds`
- **Purpose**: Specific CRD exclusions (more precise than patterns)
- **Rows**: 2 CRDs (Savvy 318493, Ritholtz 168652)
- **Schema**:
  - `firm_crd` (INT64): Firm CRD number
  - `firm_name` (STRING): Firm name
  - `category` (STRING): Exclusion category
  - `added_date` (DATE): When exclusion was added
  - `reason` (STRING): Why firm is excluded

---

## Files Created

1. ✅ `pipeline/sql/create_excluded_firms_table.sql` - Creates the pattern exclusions table
2. ✅ `pipeline/sql/create_excluded_firm_crds_table.sql` - Creates the CRD exclusions table
3. ✅ `pipeline/sql/manage_excluded_firms.sql` - Helper queries for managing exclusions

---

## Files Updated

1. ✅ `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
   - Changed from hardcoded `UNNEST([...])` to `SELECT pattern FROM ml_features.excluded_firms`
   - Changed exclusion logic from `NOT EXISTS` to `LEFT JOIN ... WHERE ... IS NULL` (BigQuery compatibility)
   - Updated header comments to reference centralized tables

2. ✅ `pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql` (duplicate)
   - Same changes as above

---

## Verification Results

### ✅ Excluded Firms Check
```sql
SELECT jl.firm_name, ef.pattern, ef.category
FROM ml_features.january_2026_lead_list jl
INNER JOIN ml_features.excluded_firms ef
    ON UPPER(jl.firm_name) LIKE ef.pattern;
```
**Result**: 0 rows ✅ (All excluded firms removed)

### ✅ Excluded CRDs Check
```sql
SELECT jl.firm_name, jl.firm_crd
FROM ml_features.january_2026_lead_list jl
INNER JOIN ml_features.excluded_firm_crds ec
    ON jl.firm_crd = ec.firm_crd;
```
**Result**: 0 rows ✅ (All excluded CRDs removed)

### ✅ Lead Count Maintained
- **Total Leads**: 2,800 ✅
- **Unique CRDs**: 2,800 ✅
- **SGAs**: 14 ✅
- **Leads per SGA**: 200 each ✅

---

## How to Add a New Exclusion

### Pattern-Based (Recommended)
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firms` 
VALUES ('%FIRM_NAME_PATTERN%', 'Category', CURRENT_DATE(), 'Reason');
```

### CRD-Based (For Specific Firms)
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firm_crds`
VALUES (123456, 'Firm Name', 'Category', CURRENT_DATE(), 'Reason');
```

### After Adding
1. Regenerate the lead list: `python pipeline/scripts/execute_january_lead_list.py`
2. Verify exclusion: Check that the firm no longer appears in `ml_features.january_2026_lead_list`

---

## How to Remove an Exclusion

### Pattern-Based
```sql
DELETE FROM `savvy-gtm-analytics.ml_features.excluded_firms`
WHERE pattern = '%PATTERN_TO_REMOVE%';
```

### CRD-Based
```sql
DELETE FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
WHERE firm_crd = 123456;
```

---

## Exclusion Categories

| Category | Count | Examples |
|----------|-------|-----------|
| Insurance | 12 | State Farm, Allstate, Prudential |
| Wirehouse | 11 | Morgan Stanley, Merrill, Wells Fargo |
| Large IBD | 6 | LPL Financial, Commonwealth, Cetera |
| Insurance BD | 5 | Pruco, NYLIFE, OneAmerica |
| Custodian | 3 | Fidelity, Schwab, Vanguard |
| Bank BD | 2 | BMO Nesbitt, Nesbitt Burns |
| Internal | 2 | Savvy Wealth, Savvy Advisors |
| Partner | 1 | Ritholtz |

---

## Benefits

1. ✅ **Easier Maintenance** - Add/remove exclusions without editing complex SQL
2. ✅ **Audit Trail** - `added_date` tracks when exclusions were added
3. ✅ **Documentation** - `reason` explains why each firm is excluded
4. ✅ **Reusable** - Same tables can be used by future lead lists
5. ✅ **Queryable** - Easy to see all exclusions and their categories

---

## Technical Notes

### BigQuery Compatibility
- Changed from `NOT EXISTS` with `LIKE` to `LEFT JOIN ... WHERE ... IS NULL`
- BigQuery cannot optimize `NOT EXISTS` with `LIKE` into an anti-join
- The `LEFT JOIN` approach is compatible and performs well

### Pattern Matching
- Patterns use SQL `LIKE` syntax (e.g., `'%MERRILL%'`)
- Patterns are case-insensitive (using `UPPER()`)
- Multiple patterns can match the same firm (all are excluded)

---

## Next Steps

- [ ] Update README.md with exclusion management documentation
- [ ] Consider adding a UI/admin tool for managing exclusions
- [ ] Set up alerts if excluded firms appear in lead lists

---

**Updated**: 2025-12-30

