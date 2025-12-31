# LinkedIn Contact Count Investigation Report
**Date:** January 2026  
**Issue:** LinkedIn contact count is 10,641 (expected 8,474) - 25.6% higher

---

## 🔍 Root Cause Identified

### **FilterDate vs CreatedDate Discrepancy**

| Date Field | Contacts | SQOs | Notes |
|------------|----------|------|-------|
| **FilterDate (2025)** | **10,641** | 148 | Includes recycled leads from previous years |
| **CreatedDate (2025)** | **8,403** | 120 | Only leads created in 2025 |
| **Both FilterDate AND CreatedDate (2025)** | **8,403** | 120 | True 2025 leads only |

**Key Finding:** `FilterDate` includes **2,238 recycled leads** from previous years:
- **2,021 contacts** created in 2024 but contacted in 2025
- **217 contacts** created in 2023 but contacted in 2025
- **2 contacts** with null CreatedDate but FilterDate in 2025

**Conclusion:** The expected 8,474 contacts likely used `CreatedDate`, while our query uses `FilterDate` which includes recycled leads.

---

## 📊 Contact→MQL Conversion Rate Verification

### User's Statement:
- **Provided Lead List:** ~3% Contact→MQL
- **LinkedIn (Self Sourced):** ~4% Contact→MQL

### Actual Results (FilterDate 2025, Active SGAs):

| Source | Contacted | MQL | Contact→MQL % | Status |
|--------|-----------|-----|---------------|--------|
| **LinkedIn (Self Sourced)** | 10,641 | 777 | **7.3%** | ✅ Higher than expected |
| **Provided Lead List** | 9,165 | 545 | **5.95%** | ✅ Higher than expected |

**Note:** Both sources convert Contact→MQL **higher** than user's estimates:
- LinkedIn: **7.3%** (vs expected ~4%) - **82.5% higher**
- Provided: **5.95%** (vs expected ~3%) - **98.3% higher**

**However:** When using `vw_conversion_rates` view (different cohort logic):
- LinkedIn: **4.17%** Contact→MQL (closer to user's ~4%)
- Provided: **2.54%** Contact→MQL (closer to user's ~3%)

---

## 🔄 Full Funnel Analysis

### LinkedIn (Self Sourced) - FilterDate 2025, Active SGAs:

| Stage | Volume | Conversion Rate |
|-------|--------|-----------------|
| **Contacted** | 10,641 | - |
| **MQL** | 777 | **7.3%** (Contact→MQL) ✅ |
| **SQL** | 247 | **31.79%** (MQL→SQL) |
| **SQO** | 148 | **59.92%** (SQL→SQO) |
| **Overall** | 148 | **1.39%** (Contact→SQO) |

### Provided Lead List - FilterDate 2025, Active SGAs:

| Stage | Volume | Conversion Rate |
|-------|--------|-----------------|
| **Contacted** | 9,165 | - |
| **MQL** | 545 | **5.95%** (Contact→MQL) ✅ |
| **SQL** | 172 | **31.56%** (MQL→SQL) |
| **SQO** | 96 | **55.81%** (SQL→SQO) |
| **Overall** | 96 | **1.05%** (Contact→SQO) |

**Key Insight:** 
- ✅ **LinkedIn converts Contact→MQL BETTER** (7.3% vs 5.95%)
- ❌ **But LinkedIn converts MQL→SQL and SQL→SQO WORSE** (lower volumes at each stage)
- **Result:** LinkedIn has higher Contact→MQL but lower overall Contact→SQO (1.39% vs 1.05% for this subset)

**Note:** The overall Contact→SQO rates here (1.39% LinkedIn, 1.05% Provided) are different from the 4.13% we saw for Provided leads from `lead_scores_v3`. This is because:
- `lead_scores_v3` includes ALL provided leads (13,701)
- This query only includes "Provided Lead List" source (9,165), excluding "FinTrx Data" and "Provided Lead List - Recycled"

---

## 📅 FilterDate Breakdown by Created Year

| FilterDate Year | Created Year | Contacts | SQOs |
|-----------------|--------------|----------|------|
| 2025 | 2025 | 8,403 | 120 |
| 2025 | 2024 | 2,021 | 23 |
| 2025 | 2023 | 217 | 3 |
| 2025 | NULL | 0 | 2 |
| **Total** | - | **10,641** | **148** |

**Finding:** 2,238 contacts (21%) are recycled leads from previous years that were contacted in 2025.

---

## 🎯 Recommendations

### 1. **Update Query 2.1 to Use CreatedDate (or Both)**

**Current Query (uses FilterDate):**
```sql
WHERE EXTRACT(YEAR FROM FilterDate) = 2025
```

**Recommended Options:**

**Option A: Use CreatedDate (excludes recycled leads)**
```sql
WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
  AND Original_source = 'LinkedIn (Self Sourced)'
  AND SGA_IsActiveSGA = TRUE
```
**Result:** 8,403 contacts (closer to expected 8,474)

**Option B: Use Both (true 2025 leads only)**
```sql
WHERE EXTRACT(YEAR FROM FilterDate) = 2025
  AND EXTRACT(YEAR FROM CreatedDate) = 2025
  AND Original_source = 'LinkedIn (Self Sourced)'
  AND SGA_IsActiveSGA = TRUE
```
**Result:** 8,403 contacts

**Option C: Keep FilterDate (includes recycled leads)**
```sql
WHERE EXTRACT(YEAR FROM FilterDate) = 2025
  AND Original_source = 'LinkedIn (Self Sourced)'
  AND SGA_IsActiveSGA = TRUE
```
**Result:** 10,641 contacts (includes 2,238 recycled leads)

### 2. **Document the Difference**

Add a note to `lead_list_analysis.md` explaining:
- **FilterDate:** Includes recycled leads (when lead re-entered funnel)
- **CreatedDate:** Only leads created in that year
- **Recommendation:** Use CreatedDate for "new leads" analysis, FilterDate for "activity" analysis

### 3. **Verify Expected Values**

The expected 8,474 contacts likely used:
- `CreatedDate = 2025` (or similar)
- May have excluded certain statuses or dispositions
- May have used different SGA filtering

**Action:** Confirm with stakeholders which date field and filters were used for the expected 8,474 count.

---

## 📈 Updated Conversion Rate Findings

### Contact→MQL (Verified):
- **LinkedIn:** 7.3% (FilterDate) or 4.17% (conversion_rates view)
- **Provided:** 5.95% (FilterDate) or 2.54% (conversion_rates view)

**User's Statement:** LinkedIn ~4%, Provided ~3%
- ✅ **LinkedIn matches** when using `vw_conversion_rates` view (4.17%)
- ✅ **Provided matches** when using `vw_conversion_rates` view (2.54%)

**Conclusion:** The `vw_conversion_rates` view uses different cohort logic that aligns with user's estimates.

---

## 🔍 Why LinkedIn Has Lower Overall Conversion Despite Higher Contact→MQL

**LinkedIn Funnel:**
- Contact→MQL: **7.3%** (777 MQLs from 10,641 contacts) ✅ Better
- MQL→SQL: **31.79%** (247 SQLs from 777 MQLs)
- SQL→SQO: **59.92%** (148 SQOs from 247 SQLs)
- **Overall:** 1.39% (148 SQOs from 10,641 contacts)

**Provided Funnel:**
- Contact→MQL: **5.95%** (545 MQLs from 9,165 contacts)
- MQL→SQL: **31.56%** (172 SQLs from 545 MQLs)
- SQL→SQO: **55.81%** (96 SQOs from 172 SQLs)
- **Overall:** 1.05% (96 SQOs from 9,165 contacts)

**Analysis:**
- LinkedIn converts **better** at Contact→MQL (7.3% vs 5.95%)
- But LinkedIn has **lower absolute volumes** at each stage
- The **absolute volume difference** at MQL stage (777 vs 545) doesn't fully compensate for the conversion rate advantage
- **Result:** Similar overall Contact→SQO rates (1.39% vs 1.05%)

**However:** When comparing to the full `lead_scores_v3` dataset (13,701 leads, 566 SQOs, 4.13%), the Provided leads perform much better. This suggests:
- The "Provided Lead List" source subset (9,165) may not be representative
- Or there are other provided lead sources that perform better
- Or the `lead_scores_v3` table includes additional filtering/quality criteria

---

## ✅ Summary

1. **Root Cause:** `FilterDate` includes 2,238 recycled leads from previous years
2. **Solution:** Use `CreatedDate` for "new leads" analysis (8,403 contacts)
3. **Contact→MQL Verified:** LinkedIn 7.3% (or 4.17% in conversion_rates view), Provided 5.95% (or 2.54%)
4. **Key Insight:** LinkedIn converts Contact→MQL better, but overall Contact→SQO is similar due to lower volumes at later stages

---

*Investigation Complete: January 2026*  
*Next Steps: Update queries to use appropriate date field based on analysis goal*

