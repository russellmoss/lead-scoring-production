# Lead List Analysis - Date Field Update Summary

**Date:** January 2026  
**File Updated:** `lead_list_analysis.md`  
**Change:** Replaced all `FilterDate` references with `CreatedDate`

---

## Summary of Changes

### ✅ All Queries Updated

**Total Queries Updated:** 12 queries

1. **Query 2.1:** LinkedIn Contacts in Salesforce (2025)
2. **Query 2.2:** LinkedIn Activity by SGA (2025)
3. **Query 2.3:** LinkedIn Lead Quality (V3/V4 Scored)
4. **Query 3.1:** Side-by-Side Comparison (2025)
5. **Query 3.2:** Efficiency Analysis (Contact-to-SQO Funnel)
6. **Query 4.1:** Activity Volume by Source (Monthly)
7. **Query 4.2:** SGA Activity Distribution
8. **Query 5.1:** All Lead Sources (2025)
9. **Query 5.2:** Campaign Analysis (2025)
10. **Query 6.1:** Lead Volume vs Target (2025)
11. **Query 7.1:** Scenario Analysis
12. **Query 8.1:** Summary Dashboard

---

## Why This Change Was Made

### Investigation Findings:
- **FilterDate (2025):** 10,641 LinkedIn contacts (includes 2,238 recycled leads from previous years)
- **CreatedDate (2025):** 8,403 LinkedIn contacts (true 2025 leads only)
- **Expected:** ~8,474 contacts (closer to CreatedDate count)

### Root Cause:
`FilterDate` includes recycled leads from previous years that were contacted in 2025:
- 2,021 contacts created in 2024 but contacted in 2025
- 217 contacts created in 2023 but contacted in 2025

### Solution:
Use `CreatedDate` for "new leads" analysis to count only leads created in 2025, excluding recycled leads.

---

## Updated Documentation

### Added Section: "Date Field Selection"

Added to Critical Notes section (after Active SGA Filtering):

```markdown
### Date Field Selection
- **Use `CreatedDate`** (not `FilterDate`) for "new leads" analysis
- `CreatedDate` = When lead was first created (true 2025 leads only)
- `FilterDate` = When lead re-entered funnel (includes recycled leads from previous years)
- **All queries use `CreatedDate`** to count only new leads created in 2025, excluding recycled leads
```

### Updated Query Notes

Added note to Query 2.1:
- "Uses `CreatedDate` (not `FilterDate`) to count only new leads created in 2025, excluding recycled leads from previous years"

---

## Expected Impact

### Before (FilterDate):
- LinkedIn Contacts: 10,641
- Includes 2,238 recycled leads (21% of total)

### After (CreatedDate):
- LinkedIn Contacts: 8,403
- Only true 2025 leads
- Closer to expected 8,474

### Conversion Rates:
- Contact→MQL: Should remain similar (LinkedIn ~7.3%, Provided ~5.95%)
- Contact→SQO: May change slightly due to different denominator

---

## Verification

### All FilterDate References:
- ✅ Replaced with `CreatedDate` in all queries
- ✅ Added explanatory notes in documentation
- ✅ Only remaining references are in explanatory text (intentional)

### Query Validation:
- All queries now use `EXTRACT(YEAR FROM CreatedDate) = 2025`
- Monthly breakdowns use `EXTRACT(MONTH FROM CreatedDate)`
- Consistent date field usage across all queries

---

## Next Steps

1. **Re-run baseline validation** with updated queries to verify new counts
2. **Update expected values** in documentation if needed
3. **Monitor** for any queries that might need `FilterDate` for activity analysis (separate use case)

---

*Update Complete: January 2026*  
*All queries now use CreatedDate for accurate "new leads" analysis*

