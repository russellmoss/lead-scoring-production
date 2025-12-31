# Lead List Analysis - Conversion Rate Calculation Fix

**Date:** January 2026  
**File Updated:** `lead_list_analysis.md`  
**Issue:** Query 3.2 was using wrong denominators for conversion rate calculations

---

## Problem Identified

**User's Looker Studio Calculation Method:**
- Contact→MQL: `SUM(contacted_to_mql_numerator) / SUM(contacted_denominator)`
- MQL→SQL: `SUM(mql_to_sql_numerator) / SUM(mql_denominator)`
- SQL→SQO: `SUM(sql_to_sqo_numerator) / SUM(sql_to_sqo_denominator)`

**Previous Query 3.2 (WRONG):**
- Contact→MQL: `SUM(contacted_to_mql_numerator) / SUM(contacted_volume)` ❌
- MQL→SQL: `SUM(mql_to_sql_numerator) / SUM(mql_volume)` ❌
- SQL→SQO: `SUM(sql_to_sqo_numerator) / SUM(sql_to_sqo_denominator)` ✅ (was correct)

---

## Fix Applied

### Query 3.2: Updated Conversion Rate Calculations

**Before:**
```sql
ROUND(SAFE_DIVIDE(SUM(contacted_to_mql_numerator), SUM(contacted_volume)) * 100, 2) as contacted_to_mql_pct,
ROUND(SAFE_DIVIDE(SUM(mql_to_sql_numerator), SUM(mql_volume)) * 100, 2) as mql_to_sql_pct,
```

**After:**
```sql
-- Conversion rates match Looker Studio calculation method
ROUND(SAFE_DIVIDE(SUM(contacted_to_mql_numerator), SUM(contacted_denominator)) * 100, 2) as contacted_to_mql_pct,
ROUND(SAFE_DIVIDE(SUM(mql_to_sql_numerator), SUM(mql_denominator)) * 100, 2) as mql_to_sql_pct,
ROUND(SAFE_DIVIDE(SUM(sql_to_sqo_numerator), SUM(sql_to_sqo_denominator)) * 100, 2) as sql_to_sqo_pct,
```

**Changes:**
- ✅ Contact→MQL: Now uses `contacted_denominator` (was `contacted_volume`)
- ✅ MQL→SQL: Now uses `mql_denominator` (was `mql_volume`)
- ✅ SQL→SQO: Already correct (uses `sql_to_sqo_denominator`)

---

## Documentation Updates

### 1. Updated "Recommended Views" Section

Added explicit conversion rate calculation formulas to match Looker Studio:

```markdown
2. **`savvy-gtm-analytics.savvy_analytics.vw_conversion_rates`**
   - Has pre-calculated conversion numerators/denominators
   - **Conversion rate calculation (matches Looker Studio):**
     - Contact→MQL: `SUM(contacted_to_mql_numerator) / SUM(contacted_denominator)`
     - MQL→SQL: `SUM(mql_to_sql_numerator) / SUM(mql_denominator)`
     - SQL→SQO: `SUM(sql_to_sqo_numerator) / SUM(sql_to_sqo_denominator)`
   - Has `contacted_volume`, `mql_volume`, `sql_volume`, `sqo_volume` for volume metrics
   - Aggregated by cohort month and source
```

### 2. Updated Query 3.2 Notes

Added note explaining the calculation method matches Looker Studio:

```markdown
**Note:** 
- Uses `vw_conversion_rates` which has pre-calculated conversion metrics
- **Conversion rates match Looker Studio calculation method:**
  - Contact→MQL: `SUM(contacted_to_mql_numerator) / SUM(contacted_denominator)`
  - MQL→SQL: `SUM(mql_to_sql_numerator) / SUM(mql_denominator)`
  - SQL→SQO: `SUM(sql_to_sqo_numerator) / SUM(sql_to_sqo_denominator)`
- All metrics use correct SQO definition (`Opportunity.SQL__c = 'yes'`)
- Shows full funnel: Contacted → MQL → SQL → SQO
```

---

## Why This Matters

### Difference Between `_volume` and `_denominator`

From the `vw_conversion_rates` schema:
- **`contacted_volume`** = Total contacted leads (volume metric)
- **`contacted_denominator`** = Leads eligible for Contact→MQL conversion (excludes open/ongoing leads)
- **`mql_volume`** = Total MQL leads (volume metric)
- **`mql_denominator`** = MQLs eligible for MQL→SQL conversion (excludes open MQLs)

**Key Difference:**
- `_denominator` fields exclude leads that are still "open" (haven't reached final outcome)
- `_volume` fields include all leads at that stage
- **For conversion rates, we need `_denominator`** to get accurate rates

### Example Impact

If there are 1,000 contacted leads:
- 800 have reached final outcome (MQL, SQL, SQO, or Closed) → `contacted_denominator = 800`
- 200 are still open (being worked) → excluded from denominator
- 50 became MQL → `contacted_to_mql_numerator = 50`

**Correct calculation:** 50 / 800 = 6.25%  
**Wrong calculation (using volume):** 50 / 1,000 = 5.00%

---

## Verification

### Query 3.2 Now Matches Looker Studio

All conversion rate calculations in Query 3.2 now use the same method as Looker Studio:
- ✅ Contact→MQL: Uses `contacted_denominator`
- ✅ MQL→SQL: Uses `mql_denominator`
- ✅ SQL→SQO: Uses `sql_to_sqo_denominator`

### Volume Metrics Still Available

The query still includes volume metrics for reference:
- `contacted_volume` - Total contacted leads
- `mql_volume` - Total MQL leads
- `sql_volume` - Total SQL leads
- `sqo_volume` - Total SQO leads

These are useful for understanding total activity, but conversion rates use the denominator fields.

---

## Summary

✅ **Query 3.2 Updated:** Now uses correct denominator fields matching Looker Studio  
✅ **Documentation Updated:** Added explicit calculation formulas  
✅ **Alignment Achieved:** All conversion rate calculations now match Looker Studio methodology

---

*Fix Complete: January 2026*  
*All conversion rate calculations now align with Looker Studio*

