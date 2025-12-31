# Final Baseline Numbers Report - CreatedDate Analysis
**Date:** January 2026  
**Queries Executed:** 1.1, 2.1, 3.1 from `lead_list_analysis.md`  
**Date Field:** `CreatedDate` (excludes recycled leads from previous years)

---

## Query Results Summary

### ✅ Query 1.1: Total Provided Leads (2025)

| Metric | Value |
|--------|-------|
| **Total Leads** | **13,701** |
| **SQOs** | **566** |
| **Conversion Rate** | **4.13%** |
| **Unique Advisors** | **13,701** |

**Note:** Uses `contacted_date` from `lead_scores_v3` table (unchanged from previous baseline).

---

### ✅ Query 2.1: LinkedIn Contacts (2025)

| Metric | Value |
|--------|-------|
| **Total Contacts (All)** | **13,969** |
| **Contacts (Active SGAs)** | **8,403** |
| **SQOs (All)** | **120** |
| **SQOs (Active SGAs)** | **120** |
| **Conversion Rate (All)** | **0.86%** |
| **Conversion Rate (Active SGAs)** | **1.43%** |

**Note:** Uses `CreatedDate` (excludes 2,238 recycled leads from previous years).

---

### ✅ Query 3.1: Side-by-Side Comparison (2025)

| Source | Total Leads/Contacts | SQOs | Conversion Rate | Leads/SGA/Month |
|--------|---------------------|------|----------------|-----------------|
| **Provided Lead List** | **13,701** | **566** | **4.13%** | **81.6** |
| **LinkedIn Self-Sourced** | **8,403** | **120** | **1.43%** | **50.0** |

**Note:** LinkedIn uses `CreatedDate` and `SGA_IsActiveSGA = TRUE` filter.

---

## Updated Baseline Numbers

### Total 2025 Performance

| Metric | Value |
|--------|-------|
| **Total SQOs** | **686** (566 Provided + 120 LinkedIn) |
| **Provided SQOs** | **566** (82.5% of total) |
| **LinkedIn SQOs** | **120** (17.5% of total) |
| **Provided Conversion** | **4.13%** Contact-to-SQO |
| **LinkedIn Conversion** | **1.43%** Contact-to-SQO (active SGAs, CreatedDate 2025) |
| **Efficiency Ratio** | Provided is **2.9x more efficient** than LinkedIn |

---

## Comparison: Previous vs Updated Baseline

### Previous Baseline (FilterDate - included recycled leads):

| Source | Contacts | SQOs | Conversion | % of Total SQOs |
|--------|----------|------|------------|-----------------|
| **Provided** | 13,701 | 566 | 4.13% | 74% |
| **LinkedIn** | 10,641 | 148 | 1.39% | 26% |
| **Total** | 24,342 | **761** | - | 100% |

### Updated Baseline (CreatedDate - new leads only):

| Source | Contacts | SQOs | Conversion | % of Total SQOs |
|--------|----------|------|------------|-----------------|
| **Provided** | 13,701 | 566 | 4.13% | **82.5%** |
| **LinkedIn** | 8,403 | 120 | 1.43% | **17.5%** |
| **Total** | 22,104 | **686** | - | 100% |

### Key Changes:

| Metric | Previous | Updated | Change |
|--------|----------|---------|--------|
| **Total SQOs** | 761 | **686** | ⬇️ -75 (-9.9%) |
| **LinkedIn Contacts** | 10,641 | **8,403** | ⬇️ -2,238 (-21.0%) |
| **LinkedIn SQOs** | 148 | **120** | ⬇️ -28 (-18.9%) |
| **LinkedIn Conversion** | 1.39% | **1.43%** | ⬆️ +0.04% |
| **Provided % of SQOs** | 74% | **82.5%** | ⬆️ +8.5% |
| **LinkedIn % of SQOs** | 26% | **17.5%** | ⬇️ -8.5% |

---

## Recommended Update for "Actual Findings" Section

### Current Text (needs updating):
```markdown
**Actual Findings (from Baseline Validation with correct SQO definition):**
- 2025 SQOs: 761 total (566 from Provided = 74%, 195 from LinkedIn = 26%)
- **Provided conversion: 4.13%** Contact-to-SQO ✅ (1.8x more efficient)
- **LinkedIn conversion: 2.30%** Contact-to-SQO
- Target: 150 SQOs/quarter = 600/year (achieved 45% in 2025)

**Key Insight:** Provided leads are MORE efficient than LinkedIn, contradicting initial hypothesis.
```

### Recommended Updated Text:
```markdown
**Actual Findings (from Baseline Validation with correct SQO definition and CreatedDate):**
- 2025 SQOs: **686 total** (566 from Provided = **82.5%**, 120 from LinkedIn = **17.5%**)
- **Provided conversion: 4.13%** Contact-to-SQO ✅ (2.9x more efficient)
- **LinkedIn conversion: 1.43%** Contact-to-SQO (active SGAs, CreatedDate 2025 - new leads only)
- Target: 150 SQOs/quarter = 600/year (achieved 45% in 2025)

**Key Insights:**
- Provided leads are **2.9x more efficient** than LinkedIn (4.13% vs 1.43%)
- Provided leads represent **82.5% of all SQOs** despite being only 62% of contacts
- LinkedIn analysis uses `CreatedDate` to count only new leads created in 2025 (excludes 2,238 recycled leads)
- Recycled leads from previous years had 28 SQOs (1.25% conversion rate)
```

---

## Additional Context

### Recycled Leads Impact

**Recycled Leads (excluded from CreatedDate analysis):**
- 2,238 contacts created in 2023-2024 but contacted in 2025
- 28 SQOs from recycled leads (1.25% conversion rate)
- If included: 10,641 contacts, 148 SQOs, 1.39% conversion

**New Leads Only (CreatedDate 2025):**
- 8,403 contacts created in 2025
- 120 SQOs from new leads (1.43% conversion rate)
- **Higher conversion rate** because new leads convert better than recycled leads

### Efficiency Analysis

**Provided Leads:**
- 13,701 contacts → 566 SQOs (4.13%)
- 81.6 leads per SGA per month
- 40.4 SQOs per SGA per year

**LinkedIn Leads:**
- 8,403 contacts → 120 SQOs (1.43%)
- 50.0 leads per SGA per month
- 8.6 SQOs per SGA per year

**Efficiency Gap:**
- Provided converts at **2.9x the rate** of LinkedIn
- Provided produces **4.7x more SQOs per SGA** than LinkedIn
- To match Provided's SQO output, LinkedIn would need **4.7x more contacts per SGA**

---

## Summary

### ✅ Final Baseline Numbers (CreatedDate 2025):

- **Total SQOs:** 686 (566 Provided + 120 LinkedIn)
- **Provided:** 13,701 leads, 566 SQOs, 4.13% conversion
- **LinkedIn:** 8,403 contacts, 120 SQOs, 1.43% conversion
- **Efficiency:** Provided is 2.9x more efficient than LinkedIn
- **Share:** Provided = 82.5% of SQOs, LinkedIn = 17.5% of SQOs

### Key Changes from Previous Baseline:

- **Total SQOs:** 761 → **686** (-75, -9.9%)
- **LinkedIn Contacts:** 10,641 → **8,403** (-2,238, -21.0%)
- **LinkedIn SQOs:** 148 → **120** (-28, -18.9%)
- **LinkedIn Conversion:** 1.39% → **1.43%** (+0.04%)
- **Provided Share:** 74% → **82.5%** (+8.5%)

---

*Report Generated: January 2026*  
*Ready to update "Actual Findings" section in lead_list_analysis.md*

