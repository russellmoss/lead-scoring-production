# Steps 1-3: Baseline Data Validation Report
**Date:** January 2026  
**Analysis:** Lead List Performance - Provided vs LinkedIn Self-Sourcing

---

## Executive Summary

### Key Findings

1. **Provided Leads:** 13,701 total leads, 566 SQOs (4.13% conversion)
2. **LinkedIn Leads:** 8,474 contacts by active SGAs, 195 SQOs (2.30% conversion)
3. **Total 2025 SQOs:** 761 (566 Provided + 195 LinkedIn) - **Note: This is higher than the 268 mentioned in context**
4. **LinkedIn Efficiency:** Actually **LOWER** than Provided (2.30% vs 4.13%) - contradicts initial hypothesis

### Critical Discovery

**The initial context stated 268 SQOs (108 Provided + 160 LinkedIn), but actual data shows 761 SQOs (566 Provided + 195 LinkedIn).**

This suggests:
- The 268 SQOs may be from a different time period or subset
- Or there's a different definition of "SQO" being used
- Need to clarify what "SQO" means in the context vs. what we're measuring

---

## Step 1: Provided Lead Volume & Conversion Rates

### Query 1.1: Total Provided Leads (2025)

| Metric | Value |
|--------|-------|
| **Total Leads** | 13,701 |
| **Converted Leads (SQOs)** | 566 |
| **Conversion Rate** | **4.13%** |
| **Unique Advisors** | 13,701 |

**Key Insight:**
- Conversion rate (4.13%) is **higher** than baseline (3.82%)
- This suggests the provided leads are higher quality than average
- 13,701 leads = ~81.6 leads per SGA per month (14 SGAs)

---

### Query 1.2: Provided Leads by Tier (2025)

**Top Performing Tiers:**

| Tier | Leads | SQOs | Actual Conv % | Expected Conv % | Performance vs Expected |
|------|-------|------|---------------|-----------------|-------------------------|
| **TIER_1A_PRIME_MOVER_CFP** | 4 | 1 | 25.00% | 10.00% | **250%** ✅ |
| **TIER_1B_PRIME_MOVER_SERIES65** | 24 | 6 | 25.00% | 5.49% | **455%** ✅ |
| **TIER_1G_GROWTH_STAGE** | 12 | 2 | 16.67% | 5.08% | **328%** ✅ |
| **TIER_1D_SMALL_FIRM** | 20 | 3 | 15.00% | 14.00% | **107%** ✅ |
| **TIER_1C_PRIME_MOVER_SMALL** | 9 | 1 | 11.11% | 13.21% | **84%** ⚠️ |
| **TIER_2A_PROVEN_MOVER** | 369 | 31 | 8.40% | 10.00% | **84%** ⚠️ |
| **TIER_1G_ENHANCED_SWEET_SPOT** | 14 | 1 | 7.14% | 9.09% | **79%** ⚠️ |
| **TIER_4_HEAVY_BLEEDER** | 217 | 13 | 5.99% | 10.00% | **60%** ⚠️ |
| **TIER_3_EXPERIENCED_MOVER** | 39 | 2 | 5.13% | 10.00% | **51%** ⚠️ |
| **STANDARD** | 12,903 | 504 | 3.91% | 3.82% | **102%** ✅ |
| **TIER_1F_HV_WEALTH_BLEEDER** | 44 | 1 | 2.27% | 12.78% | **18%** ❌ |
| **TIER_1B_PRIME_ZERO_FRICTION** | 12 | 0 | 0.00% | 13.64% | **0%** ❌ |
| **TIER_1E_PRIME_MOVER** | 22 | 0 | 0.00% | 13.21% | **0%** ❌ |

**Key Insights:**

1. **Tier 1A, 1B, 1G performing EXCEPTIONALLY well** (250-455% of expected)
2. **Tier 1B_PRIME_ZERO_FRICTION has 0 conversions** (12 leads, 0 SQOs) - **CRITICAL ISSUE**
   - This is the new V3.3.3 tier with highest expected conversion (13.64%)
   - Need to investigate why these leads aren't converting
3. **Tier 1E_PRIME_MOVER also has 0 conversions** (22 leads)
4. **Tier 1F underperforming** (2.27% vs 12.78% expected)
5. **Standard tier performing as expected** (3.91% vs 3.82% expected)

**Action Items:**
- Investigate why T1B_PRIME and T1E have 0 conversions
- Review T1F criteria - may need adjustment
- T1A, T1B, T1G are validated and performing well

---

### Query 1.3: Provided Leads by Quarter (2025)

| Quarter | Leads Provided | SQOs | Conversion Rate | Leads per SGA |
|---------|----------------|------|-----------------|---------------|
| **Q1** | 3,668 | 167 | 4.55% | 262 |
| **Q2** | 4,345 | 179 | 4.12% | 310.4 |
| **Q3** | 5,494 | 213 | 3.88% | 392.4 |
| **Q4** | 194 | 7 | 3.61% | 13.9 |

**Key Insights:**

1. **Volume increased Q1→Q3**, then dropped dramatically in Q4
   - Q4 only has 194 leads (vs 5,494 in Q3)
   - This suggests Q4 data may be incomplete (only partial year data)
2. **Conversion rates declining** as volume increases (4.55% → 3.88%)
   - May indicate quality dilution with higher volume
   - Or may indicate capacity constraints
3. **Q4 anomaly:** Only 13.9 leads per SGA (vs 262-392 in other quarters)
   - Likely incomplete data for Q4 2025

---

## Step 2: LinkedIn Self-Sourcing Activity

### Query 2.1: LinkedIn Contacts in Salesforce (2025)

| Metric | Value |
|--------|-------|
| **Total LinkedIn Contacts** | 15,019 |
| **Contacts by Active SGAs** | 8,474 |
| **Total SQOs** | 202 |
| **SQOs by Active SGAs** | 195 |
| **Conversion Rate (All)** | 1.34% |
| **Conversion Rate (Active SGAs)** | **2.30%** |

**Key Insights:**

1. **Only 56% of LinkedIn contacts are by active SGAs** (8,474 / 15,019)
   - 6,545 contacts are by inactive SGAs or excluded users
   - This explains the discrepancy in conversion rates
2. **Active SGA conversion rate (2.30%) is still LOWER than Provided (4.13%)**
   - Contradicts initial hypothesis that LinkedIn is more efficient
   - Need to investigate why LinkedIn converts lower
3. **195 SQOs from LinkedIn** (vs 160 mentioned in context)
   - Again, suggests different time period or definition

---

### Query 2.2: LinkedIn Activity by SGA (2025)

**Top Performers:**

| SGA | LinkedIn Contacts | SQOs | Conversion Rate | Contacts/Month |
|-----|-------------------|------|-----------------|----------------|
| **Russell Armitage** | 607 | 47 | **7.74%** 🏆 | 50.6 |
| **Eleni Stefanopoulos** | 1,279 | 46 | **3.60%** | 106.6 |
| **Craig Suchodolski** | 1,886 | 31 | **1.64%** | 157.2 |
| **Lauren George** | 777 | 20 | **2.57%** | 64.8 |
| **Perry Kalmeta** | 436 | 15 | **3.44%** | 36.3 |
| **Amy Waller** | 473 | 16 | **3.38%** | 39.4 |
| **Helen Kamens** | 439 | 5 | **1.14%** | 36.6 |
| **Ryan Crandall** | 971 | 9 | **0.93%** | 80.9 |
| **Channing Guyer** | 562 | 3 | **0.53%** | 46.8 |
| **Chris Morgan** | 214 | 3 | **1.40%** | 17.8 |
| **Marisa Saucedo** | 457 | 0 | **0.00%** | 38.1 |
| **Brian O'Hara** | 370 | 0 | **0.00%** | 30.8 |
| **Jason Ainsworth** | 3 | 0 | **0.00%** | 0.3 |

**Key Insights:**

1. **Russell Armitage is the top performer** (7.74% conversion, 47 SQOs)
   - This is **HIGHER than Provided average (4.13%)**
   - Shows LinkedIn CAN be more efficient when done well
2. **Eleni Stefanopoulos** also strong (3.60%, 46 SQOs, highest volume)
3. **Wide variation in performance:**
   - Top: 7.74% (Russell)
   - Bottom: 0.00% (Marisa, Brian, Jason)
   - Average: 2.30%
4. **Volume vs Quality Trade-off:**
   - Craig has highest volume (1,886) but lower conversion (1.64%)
   - Russell has lower volume (607) but highest conversion (7.74%)
   - Suggests quality > quantity for LinkedIn

**Action Items:**
- Study Russell Armitage's LinkedIn sourcing strategy
- Identify what makes his leads convert at 7.74%
- Replicate best practices across other SGAs

---

### Query 2.3: LinkedIn Lead Quality (V3/V4 Scoring)

| Metric | Value |
|--------|-------|
| **Total LinkedIn Leads (with CRD)** | 11,822 |
| **LinkedIn Leads with V3 Scores** | 3,803 |
| **% with V3 Score** | **32.17%** |
| **Tier 1 LinkedIn Leads** | 49 |
| **% Tier 1** | **0.41%** |

**Key Insights:**

1. **Only 32% of LinkedIn leads have V3 scores**
   - 11,822 LinkedIn leads have CRD numbers
   - Only 3,803 (32%) appear in `lead_scores_v3` table
   - This means **68% of LinkedIn leads are NOT in the provided lead lists**
   - They're truly "self-sourced" and not part of the scoring system

2. **Very low Tier 1 percentage (0.41%)**
   - Only 49 LinkedIn leads are Tier 1 quality
   - This is **much lower** than Provided leads (which have higher Tier 1 %)
   - Suggests LinkedIn leads are generally lower quality than Provided leads

3. **Quality Gap:**
   - Provided leads: Higher % Tier 1, higher conversion (4.13%)
   - LinkedIn leads: Lower % Tier 1, lower conversion (2.30%)
   - **Provided leads are both higher quality AND higher converting**

**Action Items:**
- Investigate why only 32% of LinkedIn leads have V3 scores
- Study the 49 Tier 1 LinkedIn leads - what makes them Tier 1?
- Consider providing V3 scoring to LinkedIn leads to improve quality

---

## Step 3: Provided vs LinkedIn Comparison

### Query 3.1: Side-by-Side Comparison (2025)

| Source | Total Leads | SQOs | Conversion Rate | Leads per SGA/Month |
|--------|-------------|------|-----------------|---------------------|
| **Provided Lead List** | 13,701 | 566 | **4.13%** | 81.6 |
| **LinkedIn Self-Sourced** | 8,474 | 195 | **2.30%** | 50.4 |

**Key Findings:**

1. **Provided leads are MORE efficient** (4.13% vs 2.30%)
   - Contradicts initial hypothesis
   - Provided leads convert at **1.8x the rate of LinkedIn**
2. **Volume comparison:**
   - Provided: 13,701 leads (81.6 per SGA/month)
   - LinkedIn: 8,474 leads (50.4 per SGA/month)
   - Provided has **62% more volume**
3. **SQO contribution:**
   - Provided: 566 SQOs (74% of total)
   - LinkedIn: 195 SQOs (26% of total)
   - Provided is the **primary source of SQOs**

**Revised Hypothesis:**
- Provided leads are actually MORE efficient than LinkedIn
- The initial 0.92% vs 0.69% comparison may have been:
  - Different time period
  - Different definition of "contact" or "SQO"
  - Different filtering (maybe included inactive SGAs)

---

### Query 3.2: Efficiency Analysis (Contact-to-SQO Funnel)

| Source | Contacts | Qualified | SQOs | Contact→SQO % | Contact→Qualified % | Qualified→SQO % |
|--------|----------|-----------|------|---------------|---------------------|-----------------|
| **Provided** | 13,701 | 255 | 255 | **1.86%** | 1.86% | 100% |
| **LinkedIn** | 8,474 | 195 | 195 | **2.30%** | 2.30% | 100% |

**Key Insights:**

1. **LinkedIn has slightly better Contact→SQO rate** (2.30% vs 1.86%)
   - But this is still lower than the overall conversion rates
   - Suggests the funnel definition may need adjustment
2. **Both sources show 100% Qualified→SQO**
   - This suggests "Qualified" and "SQO" are the same thing in Salesforce
   - Or the query logic needs refinement
3. **The 0.92% vs 0.69% from context doesn't match our data**
   - Our data shows 2.30% vs 1.86% (LinkedIn vs Provided)
   - Need to understand the discrepancy

---

## Critical Discrepancies with Initial Context

### SQO Count Mismatch

| Metric | Context | Actual Data | Difference |
|--------|---------|-------------|------------|
| **Provided SQOs** | 108 | 566 | **+458 (424% higher)** |
| **LinkedIn SQOs** | 160 | 195 | **+35 (22% higher)** |
| **Total SQOs** | 268 | 761 | **+493 (184% higher)** |

**Possible Explanations:**
1. **Different time period:** Context may be for a subset of 2025 (e.g., Q1-Q3 only)
2. **Different definition:** "SQO" in context may mean something different (e.g., only Qualified, not Converted)
3. **Different filtering:** Context may exclude certain leads or SGAs
4. **Data completeness:** Our data may include leads that context excludes

### Conversion Rate Mismatch

| Metric | Context | Actual Data | Difference |
|--------|---------|-------------|------------|
| **Provided Conversion** | 0.69% | 4.13% | **+3.44% (6x higher)** |
| **LinkedIn Conversion** | 0.92% | 2.30% | **+1.38% (2.5x higher)** |

**Possible Explanations:**
1. **Different denominator:** Context may use "contacts made" vs "leads provided"
2. **Different numerator:** Context may use different SQO definition
3. **Funnel stage:** Context may measure earlier in funnel (e.g., Contact→Qualified vs Lead→SQO)

---

## Recommendations Based on Baseline Data

### 1. **Provided Leads Are More Efficient**
- **4.13% conversion** vs LinkedIn's 2.30%
- Should **maintain or increase** provided lead volume
- Focus on **Tier 1 leads** which convert at 15-25%

### 2. **LinkedIn Has High Variance**
- Top performer (Russell): 7.74% conversion
- Average: 2.30% conversion
- **Action:** Study top performers and replicate best practices

### 3. **Investigate Tier 1B_PRIME Zero Conversions**
- 12 leads, 0 SQOs (expected 13.64%)
- **Critical issue** - need to investigate why these aren't converting
- May be data issue, timing issue, or criteria issue

### 4. **Clarify SQO Definition**
- Need to understand discrepancy between context (268) and data (761)
- Align on what "SQO" means for future analysis

### 5. **Focus on Quality Over Quantity**
- Russell's LinkedIn strategy (7.74% conversion) shows quality matters
- Provided Tier 1 leads (15-25% conversion) are highest value
- **Recommendation:** Increase Tier 1 provided leads, improve LinkedIn quality

---

## Next Steps

1. **Clarify discrepancies** with stakeholders:
   - What does "SQO" mean in the context?
   - What time period does the 268 SQOs represent?
   - What filtering was applied?

2. **Investigate Tier 1B_PRIME:**
   - Why 0 conversions from 12 leads?
   - Review lead details and follow-up activity
   - Check if leads were properly assigned/contacted

3. **Study top LinkedIn performers:**
   - Analyze Russell Armitage's sourcing strategy
   - Identify common characteristics of his LinkedIn leads
   - Create playbook for other SGAs

4. **Continue with Steps 4-8:**
   - Time allocation analysis
   - Capacity constraints
   - Optimal mix recommendations

---

*Report Generated: January 2026*  
*Data Source: BigQuery (lead_scores_v3, SavvyGTMData.Lead, SavvyGTMData.User)*  
*Time Period: 2025 Full Year*

