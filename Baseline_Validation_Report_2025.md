# Baseline Validation Report - 2025 Data
**Date:** January 2026  
**Queries Executed:** 1.1, 2.1, 3.1 from `lead_list_analysis.md`

---

## Executive Summary

### ✅ Query 1.1: Provided Leads - **MATCHES EXPECTED**

| Metric | Expected | Actual | Status |
|--------|----------|--------|--------|
| **Total Leads** | ~13,701 | **13,701** | ✅ Match |
| **SQOs** | ~566 | **566** | ✅ Match |
| **Conversion Rate** | ~4.13% | **4.13%** | ✅ Match |
| **Unique Advisors** | - | **13,701** | ✅ |

**Conclusion:** Provided leads data is accurate and matches baseline validation.

---

### ⚠️ Query 2.1: LinkedIn Contacts - **DISCREPANCIES FOUND**

| Metric | Expected | Actual (All) | Actual (Active SGAs) | Status |
|--------|----------|--------------|---------------------|--------|
| **Total Contacts** | ~8,474 | **17,490** | **10,641** | ⚠️ Higher |
| **SQOs** | ~195 | **148** | **148** | ❌ Lower |
| **Conversion Rate (All)** | ~2.30% | **0.85%** | - | ❌ Lower |
| **Conversion Rate (Active)** | ~2.30% | - | **1.39%** | ❌ Lower |

**Key Findings:**
1. **Total Contacts:** 17,490 (all) vs 10,641 (active SGAs) vs expected 8,474
   - **17,490 includes inactive SGAs and other owners** (not filtered)
   - **10,641 is active SGAs only** (still higher than expected 8,474)
   - **Discrepancy:** +2,167 contacts (25.6% higher than expected)

2. **SQOs:** 148 actual vs 195 expected
   - **Discrepancy:** -47 SQOs (24.1% lower than expected)
   - Same count for all contacts and active SGAs (148)

3. **Conversion Rates:**
   - **All contacts:** 0.85% (much lower than expected 2.30%)
   - **Active SGAs only:** 1.39% (still lower than expected 2.30%)
   - **Discrepancy:** -0.91 percentage points (39.6% lower)

---

### ⚠️ Query 3.1: Side-by-Side Comparison - **PARTIAL MATCH**

| Source | Metric | Expected | Actual | Status |
|--------|---------|----------|--------|--------|
| **Provided** | Total Leads | ~13,701 | **13,701** | ✅ Match |
| **Provided** | SQOs | ~566 | **566** | ✅ Match |
| **Provided** | Conversion | ~4.13% | **4.13%** | ✅ Match |
| **LinkedIn** | Total Contacts | ~8,474 | **10,641** | ⚠️ Higher |
| **LinkedIn** | SQOs | ~195 | **148** | ❌ Lower |
| **LinkedIn** | Conversion | ~2.30% | **1.39%** | ❌ Lower |

**Note:** Query 3.1 uses `SGA_IsActiveSGA = TRUE` filter, so LinkedIn shows 10,641 contacts (not 17,490).

---

## Detailed Analysis

### LinkedIn Data Discrepancies

#### 1. Contact Volume Discrepancy

**Expected:** 8,474 contacts by active SGAs  
**Actual:** 10,641 contacts by active SGAs  
**Difference:** +2,167 contacts (+25.6%)

**Possible Explanations:**
- **Time Period:** Expected might be for a subset of 2025 (e.g., Q1-Q3 only)
- **Filtering:** Expected might exclude certain lead statuses or dispositions
- **Data Source:** Expected might be from a different view or calculation
- **Date Field:** `FilterDate` might include leads that weren't in original calculation

#### 2. SQO Count Discrepancy

**Expected:** 195 SQOs  
**Actual:** 148 SQOs  
**Difference:** -47 SQOs (-24.1%)

**Possible Explanations:**
- **SQO Definition:** Expected might use different SQO criteria
- **Time Period:** Expected might include SQOs from different time window
- **Data Lag:** Some SQOs might not be marked yet in the funnel view
- **Filtering:** Expected might include SQOs from inactive SGAs or other sources

#### 3. Conversion Rate Discrepancy

**Expected:** 2.30% (195 SQOs / 8,474 contacts)  
**Actual (Active SGAs):** 1.39% (148 SQOs / 10,641 contacts)  
**Difference:** -0.91 percentage points (-39.6%)

**Root Cause Analysis:**
- **Higher denominator:** 10,641 contacts vs 8,474 expected (+25.6%)
- **Lower numerator:** 148 SQOs vs 195 expected (-24.1%)
- **Both factors contribute to lower conversion rate**

---

## Recommendations

### 1. Investigate LinkedIn Contact Count

**Action:** Verify the expected 8,474 contacts calculation
- Check if expected count excludes certain lead statuses
- Verify if expected uses different date field (CreatedDate vs FilterDate)
- Confirm if expected excludes certain lead sources or dispositions

**Query to Run:**
```sql
-- Compare FilterDate vs CreatedDate for LinkedIn leads
SELECT 
    COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as contacts_by_filterdate,
    COUNT(DISTINCT CASE WHEN EXTRACT(YEAR FROM CreatedDate) = 2025 THEN primary_key END) as contacts_by_createddate
FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
WHERE Original_source = 'LinkedIn (Self Sourced)'
  AND SGA_IsActiveSGA = TRUE
  AND (EXTRACT(YEAR FROM FilterDate) = 2025 OR EXTRACT(YEAR FROM CreatedDate) = 2025);
```

### 2. Investigate SQO Count Discrepancy

**Action:** Verify the expected 195 SQOs calculation
- Check if expected includes SQOs from inactive SGAs
- Verify if expected uses different time window
- Confirm if expected includes SQOs from other sources

**Query to Run:**
```sql
-- Check SQOs by different filters
SELECT 
    'All LinkedIn (no SGA filter)' as filter_type,
    COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as sqos
FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
WHERE EXTRACT(YEAR FROM FilterDate) = 2025
  AND Original_source = 'LinkedIn (Self Sourced)'
UNION ALL
SELECT 
    'Active SGAs only' as filter_type,
    COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as sqos
FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
WHERE EXTRACT(YEAR FROM FilterDate) = 2025
  AND Original_source = 'LinkedIn (Self Sourced)'
  AND SGA_IsActiveSGA = TRUE;
```

### 3. Update Expected Values

**Action:** Based on actual data, update expected values in documentation:
- **LinkedIn Contacts:** 10,641 (active SGAs) or 17,490 (all)
- **LinkedIn SQOs:** 148
- **LinkedIn Conversion:** 1.39% (active SGAs) or 0.85% (all)

**Note:** The actual conversion rate (1.39%) is still lower than Provided (4.13%), confirming that Provided leads are more efficient.

---

## Conclusion

### ✅ Provided Leads: **VALIDATED**
- All metrics match expected values exactly
- Data is accurate and reliable

### ⚠️ LinkedIn Leads: **DISCREPANCIES FOUND**
- Contact count is **25.6% higher** than expected
- SQO count is **24.1% lower** than expected
- Conversion rate is **39.6% lower** than expected

### Key Insight
Even with the discrepancies, the core finding remains: **Provided leads convert at 4.13% vs LinkedIn at 1.39%**, confirming that Provided leads are **3x more efficient** than LinkedIn.

---

*Report Generated: January 2026*  
*Next Steps: Investigate LinkedIn data discrepancies and update expected values*

