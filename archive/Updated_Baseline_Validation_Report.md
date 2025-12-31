# Updated Baseline Validation Report - CreatedDate Analysis
**Date:** January 2026  
**Queries Executed:** 1.1, 2.1, 3.1 from `lead_list_analysis.md`  
**Change:** Using `CreatedDate` instead of `FilterDate` (excludes recycled leads)

---

## Executive Summary

### ✅ Query 1.1: Provided Leads - **UNCHANGED**

| Metric | Previous (FilterDate) | New (CreatedDate) | Change |
|--------|----------------------|-------------------|--------|
| **Total Leads** | 13,701 | **13,701** | ✅ No change |
| **SQOs** | 566 | **566** | ✅ No change |
| **Conversion Rate** | 4.13% | **4.13%** | ✅ No change |

**Note:** Query 1.1 uses `contacted_date` from `lead_scores_v3` table, so it's unaffected by the CreatedDate/FilterDate change.

---

### 📊 Query 2.1: LinkedIn Contacts - **UPDATED (Lower Counts)**

| Metric | Previous (FilterDate) | New (CreatedDate) | Change |
|--------|----------------------|-------------------|--------|
| **Total Contacts (All)** | 17,490 | **13,969** | ⬇️ -3,521 (-20.1%) |
| **Contacts (Active SGAs)** | 10,641 | **8,403** | ⬇️ -2,238 (-21.0%) |
| **SQOs (All)** | 148 | **120** | ⬇️ -28 (-18.9%) |
| **SQOs (Active SGAs)** | 148 | **120** | ⬇️ -28 (-18.9%) |
| **Conversion Rate (All)** | 0.85% | **0.86%** | ⬆️ +0.01% |
| **Conversion Rate (Active)** | 1.39% | **1.43%** | ⬆️ +0.04% |

**Key Findings:**
- **2,238 fewer contacts** when using CreatedDate (excludes recycled leads from previous years)
- **28 fewer SQOs** (recycled leads had lower conversion)
- **Slightly higher conversion rate** (1.43% vs 1.39%) because we removed more contacts than SQOs

---

### 📊 Query 3.1: Side-by-Side Comparison - **UPDATED**

| Source | Metric | Previous (FilterDate) | New (CreatedDate) | Change |
|--------|--------|----------------------|-------------------|--------|
| **Provided** | Total Leads | 13,701 | **13,701** | ✅ No change |
| **Provided** | SQOs | 566 | **566** | ✅ No change |
| **Provided** | Conversion | 4.13% | **4.13%** | ✅ No change |
| **Provided** | Leads/SGA/Month | 81.6 | **81.6** | ✅ No change |
| **LinkedIn** | Total Contacts | 10,641 | **8,403** | ⬇️ -2,238 (-21.0%) |
| **LinkedIn** | SQOs | 148 | **120** | ⬇️ -28 (-18.9%) |
| **LinkedIn** | Conversion | 1.39% | **1.43%** | ⬆️ +0.04% |
| **LinkedIn** | Leads/SGA/Month | 50.0 | **50.0** | ✅ No change (rounded) |

**Note:** Query 3.1 uses `SGA_IsActiveSGA = TRUE` filter, so LinkedIn shows 8,403 contacts (active SGAs only).

---

## Comparison: FilterDate vs CreatedDate

### LinkedIn Contacts Breakdown:

| Date Field | Contacts | SQOs | Conversion | Notes |
|------------|----------|------|------------|-------|
| **FilterDate (2025)** | 10,641 | 148 | 1.39% | Includes recycled leads from 2023-2024 |
| **CreatedDate (2025)** | **8,403** | **120** | **1.43%** | True 2025 leads only |
| **Difference** | -2,238 | -28 | +0.04% | Recycled leads had lower conversion |

**Analysis:**
- **2,238 recycled leads** (21% of FilterDate total) were created in previous years
- Recycled leads had **28 SQOs** (1.25% conversion rate)
- True 2025 leads have **slightly higher conversion** (1.43% vs 1.39%)

---

## Updated Baseline Numbers for Documentation

### For "Actual Findings" Section:

**Previous (FilterDate):**
- 2025 SQOs: 761 total (566 from Provided = 74%, 195 from LinkedIn = 26%)
- Provided conversion: 4.13% Contact-to-SQO
- LinkedIn conversion: 2.30% Contact-to-SQO

**New (CreatedDate - Recommended):**
- **2025 SQOs: 686 total (566 from Provided = 82.5%, 120 from LinkedIn = 17.5%)**
- **Provided conversion: 4.13%** Contact-to-SQO ✅
- **LinkedIn conversion: 1.43%** Contact-to-SQO (active SGAs only)

**Key Changes:**
- Total SQOs: 761 → **686** (-75 SQOs, -9.9%)
- Provided %: 74% → **82.5%** (higher share)
- LinkedIn %: 26% → **17.5%** (lower share)
- LinkedIn conversion: 2.30% → **1.43%** (lower, but more accurate)

---

## Recommendations

### 1. Update "Actual Findings" Section

**Recommended Update:**
```markdown
**Actual Findings (from Baseline Validation with correct SQO definition):**
- 2025 SQOs: **686 total** (566 from Provided = **82.5%**, 120 from LinkedIn = **17.5%**)
- **Provided conversion: 4.13%** Contact-to-SQO ✅ (1.8x more efficient)
- **LinkedIn conversion: 1.43%** Contact-to-SQO (active SGAs, CreatedDate 2025)
- Target: 150 SQOs/quarter = 600/year (achieved 45% in 2025)

**Key Insight:** Provided leads are MORE efficient than LinkedIn (4.13% vs 1.43%), and represent 82.5% of all SQOs.
```

### 2. Note on LinkedIn Conversion Rate

The LinkedIn conversion rate (1.43%) is now **lower** than the previous estimate (2.30%) because:
- Previous estimate may have used different filtering or date logic
- New calculation uses `CreatedDate` (excludes recycled leads)
- Uses `SGA_IsActiveSGA = TRUE` filter (active SGAs only)
- Uses correct SQO definition (`Opportunity.SQL__c = 'yes'`)

### 3. Context on Recycled Leads

**Recycled Leads Impact:**
- 2,238 recycled leads from previous years were contacted in 2025
- These recycled leads had 28 SQOs (1.25% conversion)
- Including them would show 10,641 contacts and 148 SQOs (1.39% conversion)
- Excluding them shows 8,403 contacts and 120 SQOs (1.43% conversion)

**Recommendation:** Use CreatedDate for "new leads" analysis, but note that recycled leads are still valuable (28 SQOs).

---

## Summary

### ✅ Provided Leads: **UNCHANGED**
- All metrics remain the same (uses `contacted_date` from `lead_scores_v3`)

### 📊 LinkedIn Leads: **UPDATED**
- **Contacts:** 10,641 → **8,403** (-21.0%, excludes recycled leads)
- **SQOs:** 148 → **120** (-18.9%)
- **Conversion:** 1.39% → **1.43%** (slightly higher, more accurate)

### 🎯 Overall Impact
- **Total SQOs:** 761 → **686** (-75, -9.9%)
- **Provided share:** 74% → **82.5%** (higher)
- **LinkedIn share:** 26% → **17.5%** (lower)
- **Efficiency gap:** Provided is **2.9x more efficient** than LinkedIn (4.13% vs 1.43%)

---

*Report Generated: January 2026*  
*Next Steps: Update "Actual Findings" section in lead_list_analysis.md with new baseline numbers*

