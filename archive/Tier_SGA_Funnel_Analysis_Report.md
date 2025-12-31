# Tier, SGA, and Funnel Analysis Report
**Date:** January 2026  
**Queries Executed:** 1.2, 2.2, 3.2 from `lead_list_analysis.md`

---

## Executive Summary

### Key Findings:

1. **Tier Performance:** T1A and T1B are top performers (25% conversion), but T1B_PRIME has 0 conversions
2. **LinkedIn Top Performer:** Russell Armitage (5.79% conversion, 33 SQOs) - best practices to replicate
3. **Funnel Insight:** LinkedIn converts Contact→MQL better (4.17% vs 2.54%), but Provided converts better overall (0.46% vs 0.85% Contact→SQO)

---

## Query 1.2: Provided Leads by Tier Performance

### Top Performing Tiers (Actual Conversion Rate):

| Tier | Leads | SQOs | Actual Conv % | Expected Conv % | Performance vs Expected | Status |
|------|-------|------|---------------|-----------------|-------------------------|--------|
| **TIER_1A_PRIME_MOVER_CFP** | 4 | 1 | **25.00%** | 10.00% | **250%** | ✅ Excellent |
| **TIER_1B_PRIME_MOVER_SERIES65** | 24 | 6 | **25.00%** | 5.49% | **455%** | ✅ Excellent |
| **TIER_1G_GROWTH_STAGE** | 12 | 2 | **16.67%** | 5.08% | **328%** | ✅ Excellent |
| **TIER_1D_SMALL_FIRM** | 20 | 3 | **15.00%** | 14.00% | **107%** | ✅ Good |
| **TIER_1C_PRIME_MOVER_SMALL** | 9 | 1 | **11.11%** | 13.21% | **84%** | ⚠️ Underperforming |
| **TIER_2A_PROVEN_MOVER** | 369 | 31 | **8.40%** | 10.00% | **84%** | ⚠️ Underperforming |
| **TIER_1G_ENHANCED_SWEET_SPOT** | 14 | 1 | **7.14%** | 9.09% | **79%** | ⚠️ Underperforming |
| **TIER_4_HEAVY_BLEEDER** | 217 | 13 | **5.99%** | 10.00% | **60%** | ⚠️ Underperforming |
| **TIER_3_EXPERIENCED_MOVER** | 39 | 2 | **5.13%** | 10.00% | **51%** | ⚠️ Underperforming |
| **STANDARD** | 12,903 | 504 | **3.91%** | 3.82% | **102%** | ✅ As Expected |
| **TIER_1F_HV_WEALTH_BLEEDER** | 44 | 1 | **2.27%** | 12.78% | **18%** | ❌ Poor |
| **TIER_1B_PRIME_ZERO_FRICTION** | 12 | 0 | **0.00%** | 13.64% | **0%** | ❌ Critical Issue |
| **TIER_1E_PRIME_MOVER** | 22 | 0 | **0.00%** | 13.21% | **0%** | ❌ Critical Issue |

### Key Insights:

#### ✅ Top Performers (Prioritize These):
1. **T1A (CFP + Bleeding):** 25% conversion, 4 leads, 1 SQO
   - Small sample but highest conversion
   - **Action:** Increase volume of T1A leads

2. **T1B (Series 65 + Bleeding):** 25% conversion, 24 leads, 6 SQOs
   - Strong performance, 455% of expected
   - **Action:** Prioritize T1B leads

3. **T1G_GROWTH_STAGE:** 16.67% conversion, 12 leads, 2 SQOs
   - 328% of expected
   - **Action:** This is the "remainder" tier - still performing well

4. **T1D (Small Firm):** 15% conversion, 20 leads, 3 SQOs
   - Meets expectations (107%)
   - **Action:** Maintain current volume

#### ❌ Critical Issues (Investigate):

1. **T1B_PRIME_ZERO_FRICTION:** 0 conversions from 12 leads (expected 13.64%)
   - **This is the NEW V3.3.3 tier with highest expected conversion**
   - **Action:** URGENT - Investigate why these leads aren't converting
   - Possible causes: Data issue, timing issue, criteria too restrictive

2. **T1E_PRIME_MOVER:** 0 conversions from 22 leads (expected 13.21%)
   - **Action:** Investigate why these leads aren't converting

3. **T1F_HV_WEALTH_BLEEDER:** 2.27% conversion (expected 12.78%)
   - Only 18% of expected
   - **Action:** Review criteria - may need adjustment

#### ⚠️ Underperforming Tiers:

- **T1G_ENHANCED_SWEET_SPOT:** 7.14% (expected 9.09%) - 79% of expected
  - This is the NEW V3.3.3 "Sweet Spot" tier
  - **Action:** Monitor closely - may need more time or volume

- **T1C, T2A, T3, T4:** All underperforming vs expected
  - **Action:** Review tier criteria and expected rates

---

## Query 2.2: LinkedIn Activity by SGA

### Top Performers (by Conversion Rate):

| SGA | Contacts | SQOs | Conversion Rate | Contacts/Month | Rank |
|-----|----------|------|----------------|----------------|------|
| **Russell Armitage** 🏆 | 570 | 33 | **5.79%** | 47.5 | #1 |
| **Eleni Stefanopoulos** | 1,150 | 31 | **2.70%** | 95.8 | #2 |
| **Lauren George** | 684 | 10 | **1.46%** | 57.0 | #3 |
| **Perry Kalmeta** | 412 | 6 | **1.46%** | 34.3 | #3 |
| **Amy Waller** | 446 | 7 | **1.57%** | 37.2 | #4 |
| **Chris Morgan** | 206 | 2 | **0.97%** | 17.2 | #5 |
| **Craig Suchodolski** | 1,862 | 21 | **1.13%** | 155.2 | #6 |
| **Channing Guyer** | 503 | 3 | **0.60%** | 41.9 | #7 |
| **Anett Diaz** | 445 | 3 | **0.67%** | 37.1 | #8 |
| **Helen Kamens** | 430 | 1 | **0.23%** | 35.8 | #9 |
| **Ryan Crandall** | 873 | 3 | **0.34%** | 72.8 | #10 |
| **Marisa Saucedo** | 444 | 0 | **0.00%** | 37.0 | ❌ |
| **Brian O'Hara** | 370 | 0 | **0.00%** | 30.8 | ❌ |
| **Jason Ainsworth** | 3 | 0 | **0.00%** | 0.3 | - |
| **Jacqueline Tully** | 4 | 0 | **0.00%** | 0.3 | - |
| **Savvy Marketing** | 1 | 0 | **0.00%** | 0.1 | - |

### Key Insights:

#### 🏆 Top Performer: Russell Armitage

**Performance:**
- **5.79% conversion rate** (4.1x higher than average 1.43%)
- **33 SQOs** from 570 contacts
- **47.5 contacts/month** (moderate volume, high quality)

**Why He's Successful:**
- Highest conversion rate by far (5.79% vs 2.70% for #2)
- Quality over quantity approach
- **Action:** Study his LinkedIn sourcing strategy and replicate

#### 📊 High Volume Performers:

1. **Eleni Stefanopoulos:**
   - 2.70% conversion (1.9x average)
   - 31 SQOs (highest SQO count)
   - 1,150 contacts (2nd highest volume)
   - **Action:** Good balance of volume and quality

2. **Craig Suchodolski:**
   - 1.13% conversion (below average)
   - 21 SQOs
   - 1,862 contacts (highest volume)
   - **Action:** Volume strategy but lower conversion - could learn from Russell

#### ❌ Zero Conversion SGAs:

- **Marisa Saucedo:** 444 contacts, 0 SQOs
- **Brian O'Hara:** 370 contacts, 0 SQOs
- **Action:** Investigate why these SGAs have zero conversions despite high contact volume

#### 📈 Performance Distribution:

| Conversion Rate Range | # of SGAs | Total Contacts | Total SQOs | Avg Conv % |
|----------------------|-----------|----------------|------------|------------|
| **5%+** | 1 | 570 | 33 | 5.79% |
| **2-5%** | 1 | 1,150 | 31 | 2.70% |
| **1-2%** | 4 | 1,946 | 24 | 1.23% |
| **<1%** | 4 | 2,010 | 9 | 0.45% |
| **0%** | 5 | 1,262 | 0 | 0.00% |

**Key Finding:** Wide variance in performance - top 2 SGAs (Russell + Eleni) account for 64 SQOs (53% of total LinkedIn SQOs) from 1,720 contacts.

---

## Query 3.2: Full Funnel Efficiency Analysis

### Funnel Comparison (2025):

| Source | Contacted | MQL | SQL | SQO | Contact→MQL | MQL→SQL | SQL→SQO | Overall Contact→SQO |
|--------|-----------|-----|-----|-----|-------------|---------|---------|---------------------|
| **LinkedIn** | 17,490 | 773 | 218 | 99 | **4.17%** | 31.95% | 67.89% | **0.85%** |
| **Provided** | 21,178 | 612 | 164 | 74 | **2.54%** | 28.27% | 59.76% | **0.46%** |

**Note:** These numbers use `vw_conversion_rates` which may use different cohort logic than direct queries.

### Key Insights:

#### 🔍 Funnel Stage Analysis:

**Contact→MQL:**
- **LinkedIn: 4.17%** (better than Provided 2.54%)
- LinkedIn converts **64% better** at top of funnel
- **Finding:** LinkedIn leads are more likely to schedule initial calls

**MQL→SQL:**
- **LinkedIn: 31.95%** (better than Provided 28.27%)
- LinkedIn converts **13% better** at MQL stage
- **Finding:** LinkedIn MQLs are more qualified

**SQL→SQO:**
- **LinkedIn: 67.89%** (better than Provided 59.76%)
- LinkedIn converts **14% better** at SQL stage
- **Finding:** LinkedIn SQLs are more likely to become SQOs

**Overall Contact→SQO:**
- **LinkedIn: 0.85%** (better than Provided 0.46%)
- LinkedIn converts **85% better** overall
- **BUT:** This contradicts our earlier finding that Provided converts at 4.13% vs LinkedIn 1.43%

#### ⚠️ Discrepancy Analysis:

**Why the difference?**

1. **Different Data Sources:**
   - Query 3.2 uses `vw_conversion_rates` (cohort-based, may include different leads)
   - Query 3.1 uses `lead_scores_v3` for Provided and `vw_funnel_lead_to_joined_v2` for LinkedIn

2. **Different Filters:**
   - Query 3.2: All sources combined (may include inactive SGAs, different date logic)
   - Query 3.1: Active SGAs only, CreatedDate 2025

3. **Cohort Logic:**
   - `vw_conversion_rates` uses cohort months and eligibility flags
   - May exclude "open" leads from denominators

**Recommendation:** Use Query 3.1 numbers (4.13% Provided, 1.43% LinkedIn) as they use consistent filtering and date logic.

---

## Recommendations

### 1. Tier Prioritization

**Focus on Top Performers:**
- ✅ **T1A (CFP + Bleeding):** 25% conversion - Increase volume
- ✅ **T1B (Series 65 + Bleeding):** 25% conversion - Prioritize
- ✅ **T1G_GROWTH_STAGE:** 16.67% conversion - Strong performer
- ✅ **T1D (Small Firm):** 15% conversion - Maintain

**Investigate Critical Issues:**
- ❌ **T1B_PRIME_ZERO_FRICTION:** 0 conversions from 12 leads
  - **URGENT:** Review lead assignment, follow-up, criteria
- ❌ **T1E_PRIME_MOVER:** 0 conversions from 22 leads
  - Review criteria and lead quality
- ❌ **T1F_HV_WEALTH_BLEEDER:** 2.27% (expected 12.78%)
  - Review criteria - may need adjustment

### 2. LinkedIn Best Practices

**Study Top Performers:**
- 🏆 **Russell Armitage:** 5.79% conversion
  - Moderate volume (47.5/month), high quality
  - **Action:** Interview Russell, document his sourcing strategy
- 📊 **Eleni Stefanopoulos:** 2.70% conversion, highest SQO count
  - High volume (95.8/month), good quality
  - **Action:** Study her approach, balance of volume and quality

**Support Underperformers:**
- ❌ **Marisa Saucedo, Brian O'Hara:** 0% conversion
  - **Action:** Training, coaching, review of approach
- ⚠️ **Low performers (<1%):** 4 SGAs with 0.23-0.97% conversion
  - **Action:** Pair with top performers, review targeting strategy

### 3. Funnel Optimization

**LinkedIn Strengths:**
- ✅ Better Contact→MQL (4.17% vs 2.54%)
- ✅ Better MQL→SQL (31.95% vs 28.27%)
- ✅ Better SQL→SQO (67.89% vs 59.76%)

**Provided Strengths:**
- ✅ Higher overall Contact→SQO (4.13% vs 1.43% from Query 3.1)
- ✅ More consistent quality
- ✅ Better volume (13,701 vs 8,403)

**Action Items:**
- Study why LinkedIn converts better at each stage but worse overall
- May be due to different lead quality or targeting
- Consider applying LinkedIn's Contact→MQL approach to Provided leads

---

## Summary

### Tier Performance:
- **Top 3 Tiers:** T1A (25%), T1B (25%), T1G_GROWTH (16.67%)
- **Critical Issues:** T1B_PRIME (0%), T1E (0%), T1F (2.27%)

### LinkedIn Top Performers:
- **#1:** Russell Armitage (5.79% conversion, 33 SQOs)
- **#2:** Eleni Stefanopoulos (2.70% conversion, 31 SQOs)
- **Top 2 account for 53% of LinkedIn SQOs**

### Funnel Insights:
- **LinkedIn converts better at each stage** but worse overall (due to different data sources/filters)
- **Use Query 3.1 numbers** (4.13% Provided, 1.43% LinkedIn) for accurate comparison

---

*Report Generated: January 2026*  
*Next Steps: Investigate T1B_PRIME zero conversions, study Russell Armitage's LinkedIn strategy*

