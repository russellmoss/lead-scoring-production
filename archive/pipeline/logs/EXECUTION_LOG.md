# V4 Prospect Features - Execution Log

**Started**: 2025-12-24  
**Purpose**: Create V4 feature table for all FINTRX prospects  
**Status**: In Progress

---

## Step 1.1: Create V4 Feature Table

### SQL File Created
- **File**: `sql/v4_prospect_features.sql`
- **Target Table**: `ml_features.v4_prospect_features`
- **Optimization**: Pre-aggregated CTEs to avoid correlated subqueries

### Performance Optimizations Applied

1. **Firm Stability** (MAJOR OPTIMIZATION):
   - ❌ **Before**: 3 correlated subqueries per row (500K+ executions)
   - ✅ **After**: 3 pre-aggregated CTEs + simple JOINs
   - **Expected Speedup**: 100-1000x faster

2. **Industry Tenure** (SIMPLIFIED):
   - ❌ **Before**: Correlated subquery per row
   - ✅ **After**: Use `INDUSTRY_TENURE_MONTHS` from `ria_contacts_current` (pre-calculated)
   - **Expected Speedup**: 10-100x faster

### Estimated Runtime
- **Before optimization**: 1-3 hours (500K prospects)
- **After optimization**: 2-5 minutes (500K prospects)

### Execution Results

**Timestamp**: 2025-12-24  
**Status**: ✅ **SUCCESS**

#### Table Created
- **Table**: `ml_features.v4_prospect_features`
- **Total Prospects**: **285,690**
- **Execution Time**: ~3-5 minutes (optimized query)

#### Validation Results

**Basic Metrics:**
- ✅ Total Prospects: **285,690**
- ✅ With Known Tenure: **215,773** (75.5% coverage)
- ✅ High Mobility: **3,073** (1.1% of total)
- ✅ Heavy Bleeding Firms: **169,820** (59.5% of total)
- ✅ Interaction Feature (mobility_x_heavy_bleeding): **2,372** (0.8% of total)

**Feature Coverage:**
- ✅ `tenure_bucket`: **75.5%** coverage (215,773 / 285,690)
- ✅ `experience_bucket`: **84.1%** coverage (240,246 / 285,690)
- ✅ `has_firm_data`: **75.5%** coverage (215,763 / 285,690)
- ✅ `has_email`: **81.9%** coverage (233,880 / 285,690)
- ✅ `has_linkedin`: **76.5%** coverage (218,554 / 285,690)

**Anomaly Checks:**
- ✅ No null `tenure_bucket` values
- ✅ No null `mobility_tier` values
- ✅ No null `firm_stability_tier` values
- ✅ No duplicate CRDs (all unique)

#### Observations

1. **Tenure Coverage (75.5%)**: Good coverage, similar to training data (~78.6%)
2. **Heavy Bleeding Firms (59.5%)**: High percentage - this is expected as many firms have net negative rep change
3. **Interaction Features**: Low sample sizes (2,372 for mobility_x_heavy_bleeding) - consistent with training data
4. **Data Quality**: All required features present, no nulls in categorical features

#### Performance

- **Query executed successfully** in ~3-5 minutes
- **Optimizations effective**: Pre-aggregated CTEs prevented correlated subquery performance issues
- **Table ready** for Step 2 (V4 scoring)

---

## Step 1.2: Validation Complete ✅

**Status**: All validation checks passed  
**Next Step**: Proceed to Step 2 (Score Prospects with V4 Model)

---


## Step 2: V4 Scoring - 2025-12-24 15:47:42

**Status**: ✅ SUCCESS

**Results:**
- Total scored: 285,690
- Deprioritize (bottom 20%): 59,995
- Prioritize (top 80%): 225,695
- Score range: 0.1062 - 0.8440
- Average score: 0.4332
- Average percentile: 49.1

**Table Created**: `savvy-gtm-analytics.ml_features.v4_prospect_scores`

### Validation Results (Step 2.2)

**Score Distribution:**
- ✅ Total Scored: **285,690**
- ✅ Score Range: **0.1062 - 0.8440**
- ✅ Average Score: **0.4332**
- ✅ Median Score: **0.4319**

**Percentile Distribution:**
- ✅ Percentile Range: **0 - 99**
- ✅ Average Percentile: **49.1**
- ✅ Distribution: Roughly uniform across deciles (8.7% - 11.0% per decile)

**Deprioritization Flags:**
- ✅ Deprioritize (bottom 20%): **59,995** (21.0% of total)
- ✅ Prioritize (top 80%): **225,695** (79.0% of total)
- ✅ Average Score (Deprioritize): **0.2819** (vs 0.4735 for prioritize)
- ✅ Average Percentile (Deprioritize): **9.9** (vs 59.6 for prioritize)

**Validation Checks:**
- ✅ Percentile distribution is uniform (expected ~10% per decile, actual 8.7-11.0%)
- ✅ Deprioritize flag correctly set for bottom 20% (21.0% actual, close to 20% target)
- ✅ Score range is reasonable (0.1062 - 0.8440)
- ✅ Clear separation between deprioritize and prioritize groups (0.28 vs 0.47 avg score)

### Observations

1. **Deprioritize Group**: 59,995 prospects (21.0%) with average score 0.2819 - significantly lower than prioritize group
2. **Score Distribution**: Healthy range (0.11 - 0.84) with good separation
3. **Percentile Distribution**: Uniform distribution confirms ranking is working correctly
4. **Ready for Step 3**: Scores table ready for hybrid lead list query

---

## Step 3: V3 + V4 Hybrid Lead List Query - 2025-12-24

**Status**: ✅ SUCCESS

**Table Created**: `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`

### Query Execution

**SQL File**: `sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Key Modifications from V3.2:**
1. ✅ Added `v4_enriched` CTE to join V4 scores after `enriched_prospects`
2. ✅ Modified `scored_prospects` to use `v4_enriched` instead of `enriched_prospects`
3. ✅ Added `v4_deprioritize = FALSE` filter in `diversity_filtered` CTE
4. ✅ Added `v4_percentile DESC` to ORDER BY clauses for tie-breaking
5. ✅ Added V4 columns to final output: `v4_score`, `v4_percentile`, `v4_deprioritize`

### Validation Results

**Basic Metrics:**
- ✅ Total Leads: **2,400** (exactly as expected)
- ✅ LinkedIn Coverage: **99.9%** (2,397 leads with LinkedIn)
- ✅ V4 Deprioritize Count: **0** (no bottom 20% leads included)
- ✅ Average V4 Percentile: **95.6** (very high, as expected)
- ✅ Minimum V4 Percentile: **66** (no leads below 20% threshold)

**Tier Distribution:**
- ✅ TIER_1A_PRIME_MOVER_CFP: **12** (0.5%)
- ✅ TIER_1B_PRIME_MOVER_SERIES65: **60** (2.5%)
- ✅ TIER_1_PRIME_MOVER: **300** (12.5%)
- ✅ TIER_1F_HV_WEALTH_BLEEDER: **50** (2.1%)
- ✅ TIER_2_PROVEN_MOVER: **1,500** (62.5%)
- ✅ TIER_3_MODERATE_BLEEDER: **300** (12.5%)
- ✅ TIER_4_EXPERIENCED_MOVER: **178** (7.4%)
- ✅ TIER_5_HEAVY_BLEEDER: **0** (0.0%)

**V4 Percentile Distribution:**
- ✅ **0-19 (Bottom 20%)**: **0 leads** (0.0%) - CORRECTLY EXCLUDED
- ✅ **20-39**: **0 leads** (0.0%)
- ✅ **40-59**: **0 leads** (0.0%)
- ✅ **60-79**: **173 leads** (7.2%, avg score: 0.5066)
- ✅ **80-99 (Top 20%)**: **2,227 leads** (92.8%, avg score: 0.6638)

**Prospect Type:**
- ✅ All leads are **NEW_PROSPECT** (100%) - no recyclable leads in final list

### Observations

1. **V4 Deprioritization Working**: Zero leads with `v4_deprioritize = TRUE` in final list, confirming the filter is working correctly
2. **High V4 Scores**: Average percentile of 95.6 indicates the hybrid approach is selecting high-quality leads
3. **Tier Distribution**: Good mix across priority tiers, with TIER_2_PROVEN_MOVER being the largest (62.5%)
4. **LinkedIn Coverage**: Excellent coverage (99.9%) ensures SDRs have LinkedIn profiles for outreach
5. **No Bottom 20%**: All leads are above the 20th percentile threshold, confirming V4 filter effectiveness

### Efficiency Analysis

**Expected Impact:**
- V4 deprioritization filters out bottom 20% of leads
- These leads have ~1.33% conversion rate (0.42x lift)
- By skipping them, we improve efficiency by ~11.7%

**Actual Results:**
- All 2,400 leads have V4 percentile >= 66
- Average V4 percentile: 95.6 (top 5% of prospects)
- This suggests the hybrid approach is selecting the highest-quality leads

### Next Steps

✅ **Step 3 Complete** - Hybrid lead list generated successfully  
⏳ **Step 4**: Export lead list to CSV for SDR use

---


## Step 4: Export Lead List to CSV - 2025-12-24 16:12:25

**Status**: ✅ SUCCESS

**Export File**: `january_2026_lead_list_20251224.csv`  
**Location**: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation\exports\january_2026_lead_list_20251224.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,400** (expected: 2,400)
- File Size: **503.5 KB**

**Validation Results:**
- Row Count Match: **PASS**
- Duplicate CRDs: **0** (should be 0)
- Missing Required Fields: **PASS**
  - Missing First Name: 0
  - Missing Last Name: 0
  - Missing Email: 264
  - Missing Firm Name: 0
  - Missing Score Tier: 0
  - Missing V4 Score: 0
  - Missing V4 Percentile: 0

**Data Quality:**
- ✅ LinkedIn Coverage: **2,398** (99.9%)
- ✅ V4 Score Range: **0.4836 - 0.8440**
- ✅ V4 Percentile Range: **66 - 99**
- ✅ Average V4 Percentile: **95.6**

**Tier Distribution:**
- ✅ TIER_1A_PRIME_MOVER_CFP: **12** (0.5%)
- ✅ TIER_1B_PRIME_MOVER_SERIES65: **60** (2.5%)
- ✅ TIER_1F_HV_WEALTH_BLEEDER: **50** (2.1%)
- ✅ TIER_1_PRIME_MOVER: **300** (12.5%)
- ✅ TIER_2_PROVEN_MOVER: **1,500** (62.5%)
- ✅ TIER_3_MODERATE_BLEEDER: **300** (12.5%)
- ✅ TIER_4_EXPERIENCED_MOVER: **178** (7.4%)

### Export Columns

The CSV includes the following columns (in order):
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `email` - Email address
6. `phone` - Phone number
7. `linkedin_url` - LinkedIn profile URL
8. `firm_name` - Firm name
9. `firm_crd` - Firm CRD ID
10. `score_tier` - V3 tier assignment
11. `expected_rate_pct` - Expected conversion rate (%)
12. `v4_score` - V4 XGBoost score
13. `v4_percentile` - V4 percentile rank (1-100)
14. `prospect_type` - NEW_PROSPECT or recyclable
15. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV  
**Ready for**: Salesforce import and SDR outreach

---

## Step 3 (REVISED): V3 + V4 Hybrid Lead List with V4 Upgrade Path - 2025-12-24

**Status**: ✅ SUCCESS

**SQL File**: `sql/January_2026_Lead_List_V3_V4_Hybrid.sql`  
**Target Table**: `ml_features.january_2026_lead_list_v4`  
**Model**: V3.2.5 + V4 XGBoost Hybrid v2 (Upgrade Path)

### Key Changes from Previous Version

1. ✅ **REMOVED**: V4 deprioritization filter (`v4_deprioritize = FALSE` filter removed)
2. ✅ **ADDED**: V4 upgrade path (STANDARD leads with V4 >= 80th percentile → V4_UPGRADE tier)
3. ✅ **ADDED**: `is_v4_upgrade` flag for tracking performance
4. ✅ **ADDED**: `v4_status` column for reporting

### Investigation Findings (Applied)

- T1 converts at 7.41% vs T2 at 3.20% (V3 tier ordering validated)
- V4 AUC-ROC (0.6141) > V3 AUC-ROC (0.5095) - V4 better at prediction
- STANDARD leads with V4 >= 80% convert at 4.60% (1.42x baseline)
- V4 deprioritization was NOT adding value (90% of V3 leads scored in top 10%)

### Execution Results

**Table Created**: `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`  
**Execution Time**: Query executed successfully

### Validation Results

**Basic Metrics:**
- ✅ Total Leads: **2,400** (exactly as expected)
- ✅ LinkedIn Coverage: **99.92%** (2,398 leads with LinkedIn)
- ✅ Average V4 Percentile: **98.3** (very high quality selection)

**Tier Distribution:**
- ✅ TIER_1A_PRIME_MOVER_CFP: **4** (0.17%)
- ✅ TIER_1B_PRIME_MOVER_SERIES65: **60** (2.5%)
- ✅ TIER_1_PRIME_MOVER: **300** (12.5%)
- ✅ TIER_1F_HV_WEALTH_BLEEDER: **50** (2.08%)
- ✅ TIER_2_PROVEN_MOVER: **1,500** (62.5%)
- ✅ **V4_UPGRADE: 486 (20.25%)** ← NEW TIER
- ✅ TIER_3_MODERATE_BLEEDER: **0** (0%)
- ✅ TIER_4_EXPERIENCED_MOVER: **0** (0%)
- ✅ TIER_5_HEAVY_BLEEDER: **0** (0%)

**V4 Upgrade Details:**
- ✅ **V4_UPGRADE Count**: **486 leads** (20.25% of total list)
- ✅ **Average V4 Percentile**: **99.0** (all V4_UPGRADE leads are in top 1%)
- ✅ **V4 Percentile Range**: **99 - 99** (all exactly at 99th percentile)
- ✅ **Expected Conversion Rate**: **4.60%** (based on historical data)
- ✅ **Original V3 Tier**: All were STANDARD tier before upgrade

**V4 Upgrade Flag (`is_v4_upgrade`):**
- ✅ `is_v4_upgrade = 1`: **486 leads** (20.25%)
  - Average V4 Percentile: **99.0**
  - Expected Rate: **4.60%**
- ✅ `is_v4_upgrade = 0`: **1,914 leads** (79.75%)
  - Average V4 Percentile: **97.9**
  - Expected Rate: **5.62%**

**V4 Percentile Distribution:**
- ✅ **90-100 (Top 10%)**: **2,382 leads** (99.25%, avg: 98.3)
- ✅ **80-89**: **8 leads** (0.33%, avg: 81.1)
- ✅ **70-79**: **8 leads** (0.33%, avg: 77.5)
- ✅ **60-69**: **2 leads** (0.08%, avg: 67.5)
- ✅ **<60**: **0 leads** (0%)

### Observations

1. **V4 Upgrade Path Working**: 486 STANDARD tier leads were upgraded to V4_UPGRADE tier (20.25% of list)
2. **High V4 Scores**: All V4_UPGRADE leads have V4 percentile = 99 (top 1% of prospects)
3. **Expected Conversion Rate**: V4_UPGRADE leads have 4.60% expected rate (1.42x baseline of 3.23%)
4. **Tier Mix**: Good distribution with TIER_2_PROVEN_MOVER (62.5%) and V4_UPGRADE (20.25%) as largest groups
5. **LinkedIn Coverage**: Excellent (99.92%) for SDR outreach
6. **No Deprioritization**: Removed deprioritization filter as investigation showed it wasn't adding value

### Expected Impact

**Conversion Rate Improvement:**
- V4_UPGRADE leads: 486 leads × 4.60% = ~22 expected conversions
- Without V4 upgrade: 486 STANDARD leads × 2.50% = ~12 expected conversions
- **Net Gain**: ~10 additional expected conversions (+83% improvement for this segment)

**Overall List Quality:**
- Average expected conversion rate: **5.62%** (weighted average across all tiers)
- V4_UPGRADE tier adds high-quality leads that would have been excluded as STANDARD

### Next Steps

✅ **Step 3 (Revised) Complete** - Hybrid lead list with V4 upgrade path generated successfully  
⏳ **Step 4**: Export lead list to CSV for SDR use (if needed)

---


## Step 4: Export Lead List to CSV - 2025-12-24 17:07:56

**Status**: ✅ SUCCESS

**Export File**: `january_2026_lead_list_20251224.csv`  
**Location**: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation\exports\january_2026_lead_list_20251224.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,400**
- File Size: **561.4 KB**

**V4 Upgrade Path Analysis:**
- V4 Upgraded Leads: **486** (20.2%)
- V3 Tier Leads: **1,914** (79.8%)

**Expected Impact:**
- V4 Upgraded leads convert at **4.60%** (vs 3.20% for T2)
- This represents a **44% improvement** over T2 leads
- Expected overall lift: **+6-12%** in conversion rate

**Validation Results:**
- Row Count: **2,400**
- Duplicate CRDs: **0** (should be 0)
- LinkedIn Coverage: **2,398** (99.9%)

**V4 Score Statistics:**
- V4 Score Range: **0.4853 - 0.8440**
- V4 Percentile Range: **67 - 99**
- Average V4 Percentile: **98.2**

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **4** (0.2%)
- TIER_1B_PRIME_MOVER_SERIES65: **60** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **50** (2.1%)
- TIER_1_PRIME_MOVER: **300** (12.5%)
- TIER_2_PROVEN_MOVER: **1,500** (62.5%)
- V4_UPGRADE: **486** (20.2%) ⬆️ V4 UPGRADE

### Tracking V4 Upgrades

To measure V4 upgrade performance:
1. Filter by `is_v4_upgrade = 1` in reports
2. Compare conversion rate to V3 tier leads
3. Expected: V4 upgrades should convert at ~4.60%

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `email` - Email address
6. `phone` - Phone number
7. `linkedin_url` - LinkedIn profile URL
8. `firm_name` - Firm name
9. `firm_crd` - Firm CRD ID
10. `score_tier` - Final tier (V3 tier or V4_UPGRADE)
11. `original_v3_tier` - Original V3 tier before upgrade
12. `expected_rate_pct` - Expected conversion rate (%)
13. `v4_score` - V4 XGBoost score
14. `v4_percentile` - V4 percentile rank (1-100)
15. `is_v4_upgrade` - **1 = V4 upgraded lead, 0 = V3 tier lead**
16. `v4_status` - Description of V4 status
17. `prospect_type` - NEW_PROSPECT or recyclable
18. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV  
**Ready for**: Salesforce import and SDR outreach

**IMPORTANT**: Track `is_v4_upgrade` leads separately to validate 4.60% conversion rate!

---


## Step 2: V4 Scoring with SHAP Narratives - 2025-12-24 17:36:50

**Status**: ✅ SUCCESS

**Results:**
- Total scored: 285,690
- V4 upgrade candidates: 56,418
- V4 narratives generated: 56,418
- Score range: 0.1062 - 0.8440

**New Columns:**
- `shap_top1/2/3_feature`: Top 3 SHAP features
- `shap_top1/2/3_value`: SHAP values for those features
- `v4_narrative`: Human-readable narrative for V4 upgrades

**Table Updated**: `savvy-gtm-analytics.ml_features.v4_prospect_scores`

---


## Step 4: Export Lead List to CSV - 2025-12-24 17:38:30

**Status**: ✅ SUCCESS

**Export File**: `january_2026_lead_list_20251224.csv`  
**Location**: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation\exports\january_2026_lead_list_20251224.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,400**
- File Size: **1174.0 KB**

**New Features:**
- Job Title Coverage: **2,400** (100.0%)
- Narrative Coverage: **2,400** (100.0%)
- LinkedIn Coverage: **2,398** (99.9%)

**V4 Upgrade Path:**
- V4 Upgraded Leads: **486** (20.2%)

**Firm Exclusions:**
- Savvy (CRD 318493): **0** ✅ EXCLUDED
- Ritholtz (CRD 168652): **0** ✅ EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **4** (0.2%)
- TIER_1B_PRIME_MOVER_SERIES65: **60** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **50** (2.1%)
- TIER_1_PRIME_MOVER: **300** (12.5%)
- TIER_2_PROVEN_MOVER: **1,500** (62.5%)
- V4_UPGRADE: **486** (20.2%) ⬆️ V4 UPGRADE

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or V4_UPGRADE)
12. `original_v3_tier` - Original V3 tier before upgrade
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_v4_upgrade` - **1 = V4 upgraded lead, 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 2: V4 Scoring with SHAP Narratives - 2025-12-24 17:44:50

**Status**: ✅ SUCCESS

**Results:**
- Total scored: 285,690
- V4 upgrade candidates: 56,418
- V4 narratives generated: 56,418
- Score range: 0.1062 - 0.8440

**New Columns:**
- `shap_top1/2/3_feature`: Top 3 SHAP features
- `shap_top1/2/3_value`: SHAP values for those features
- `v4_narrative`: Human-readable narrative for V4 upgrades

**Table Updated**: `savvy-gtm-analytics.ml_features.v4_prospect_scores`

---


## Step 4: Export Lead List to CSV - 2025-12-24 17:45:14

**Status**: ✅ SUCCESS

**Export File**: `january_2026_lead_list_20251224.csv`  
**Location**: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation\exports\january_2026_lead_list_20251224.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,400**
- File Size: **1174.0 KB**

**New Features:**
- Job Title Coverage: **2,400** (100.0%)
- Narrative Coverage: **2,400** (100.0%)
- LinkedIn Coverage: **2,398** (99.9%)

**V4 Upgrade Path:**
- V4 Upgraded Leads: **486** (20.2%)

**Firm Exclusions:**
- Savvy (CRD 318493): **0** ✅ EXCLUDED
- Ritholtz (CRD 168652): **0** ✅ EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **4** (0.2%)
- TIER_1B_PRIME_MOVER_SERIES65: **60** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **50** (2.1%)
- TIER_1_PRIME_MOVER: **300** (12.5%)
- TIER_2_PROVEN_MOVER: **1,500** (62.5%)
- V4_UPGRADE: **486** (20.2%) ⬆️ V4 UPGRADE

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or V4_UPGRADE)
12. `original_v3_tier` - Original V3 tier before upgrade
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_v4_upgrade` - **1 = V4 upgraded lead, 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 2: V4 Scoring with SHAP Narratives - 2025-12-24 17:46:04

**Status**: ✅ SUCCESS

**Results:**
- Total scored: 285,690
- V4 upgrade candidates: 56,418
- V4 narratives generated: 56,418
- Score range: 0.1062 - 0.8440

**New Columns:**
- `shap_top1/2/3_feature`: Top 3 SHAP features
- `shap_top1/2/3_value`: SHAP values for those features
- `v4_narrative`: Human-readable narrative for V4 upgrades

**Table Updated**: `savvy-gtm-analytics.ml_features.v4_prospect_scores`

---


## Step 4: Export Lead List to CSV - 2025-12-24 17:46:28

**Status**: ✅ SUCCESS

**Export File**: `january_2026_lead_list_20251224.csv`  
**Location**: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation\exports\january_2026_lead_list_20251224.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,400**
- File Size: **1194.9 KB**

**New Features:**
- Job Title Coverage: **2,400** (100.0%)
- Narrative Coverage: **2,400** (100.0%)
- LinkedIn Coverage: **2,398** (99.9%)

**V4 Upgrade Path:**
- V4 Upgraded Leads: **486** (20.2%)

**Firm Exclusions:**
- Savvy (CRD 318493): **0** ✅ EXCLUDED
- Ritholtz (CRD 168652): **0** ✅ EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **4** (0.2%)
- TIER_1B_PRIME_MOVER_SERIES65: **60** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **50** (2.1%)
- TIER_1_PRIME_MOVER: **300** (12.5%)
- TIER_2_PROVEN_MOVER: **1,500** (62.5%)
- V4_UPGRADE: **486** (20.2%) ⬆️ V4 UPGRADE

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or V4_UPGRADE)
12. `original_v3_tier` - Original V3 tier before upgrade
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_v4_upgrade` - **1 = V4 upgraded lead, 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 4: Export Lead List to CSV - 2025-12-24 17:47:04

**Status**: ✅ SUCCESS

**Export File**: `january_2026_lead_list_20251224.csv`  
**Location**: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation\exports\january_2026_lead_list_20251224.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,400**
- File Size: **1226.7 KB**

**New Features:**
- Job Title Coverage: **2,400** (100.0%)
- Narrative Coverage: **2,400** (100.0%)
- LinkedIn Coverage: **2,398** (99.9%)

**V4 Upgrade Path:**
- V4 Upgraded Leads: **486** (20.2%)

**Firm Exclusions:**
- Savvy (CRD 318493): **0** ✅ EXCLUDED
- Ritholtz (CRD 168652): **0** ✅ EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **4** (0.2%)
- TIER_1B_PRIME_MOVER_SERIES65: **60** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **50** (2.1%)
- TIER_1_PRIME_MOVER: **300** (12.5%)
- TIER_2_PROVEN_MOVER: **1,500** (62.5%)
- V4_UPGRADE: **486** (20.2%) ⬆️ V4 UPGRADE

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or V4_UPGRADE)
12. `original_v3_tier` - Original V3 tier before upgrade
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_v4_upgrade` - **1 = V4 upgraded lead, 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 2: V4 Scoring with SHAP Narratives - 2025-12-25 23:51:37

**Status**: ✅ SUCCESS

**Results:**
- Total scored: 285,690
- V4 upgrade candidates: 56,356
- V4 narratives generated: 56,356
- Score range: 0.1062 - 0.8440

**New Columns:**
- `shap_top1/2/3_feature`: Top 3 SHAP features
- `shap_top1/2/3_value`: SHAP values for those features
- `v4_narrative`: Human-readable narrative for V4 upgrades

**Table Updated**: `savvy-gtm-analytics.ml_features.v4_prospect_scores`

---


## Step 4: Export Lead List to CSV - 2025-12-25 23:52:50

**Status**: ✅ SUCCESS

**Export File**: `january_2026_lead_list_20251225.csv`  
**Location**: `C:\Users\russe\Documents\lead_scoring_production\pipeline\exports\january_2026_lead_list_20251225.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,794**
- File Size: **1519.3 KB**

**New Features:**
- Job Title Coverage: **2,794** (100.0%)
- Narrative Coverage: **2,794** (100.0%)
- LinkedIn Coverage: **2,792** (99.9%)

**V4 Upgrade Path:**
- V4 Upgraded Leads: **562** (20.1%)

**Firm Exclusions:**
- Savvy (CRD 318493): **0** ✅ EXCLUDED
- Ritholtz (CRD 168652): **0** ✅ EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **4** (0.1%)
- TIER_1B_PRIME_MOVER_SERIES65: **70** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **58** (2.1%)
- TIER_1_PRIME_MOVER: **350** (12.5%)
- TIER_2_PROVEN_MOVER: **1,750** (62.6%)
- V4_UPGRADE: **562** (20.1%) ⬆️ V4 UPGRADE

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or V4_UPGRADE)
12. `original_v3_tier` - Original V3 tier before upgrade
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_v4_upgrade` - **1 = V4 upgraded lead, 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 4: Export Lead List to CSV - 2025-12-26 00:15:04

**Status**: SUCCESS

**Export File**: `january_2026_lead_list_20251226.csv`  
**Location**: `C:\Users\russe\Documents\lead_scoring_production\pipeline\exports\january_2026_lead_list_20251226.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,794**
- File Size: **1519.3 KB**

**New Features:**
- Job Title Coverage: **2,794** (100.0%)
- Narrative Coverage: **2,794** (100.0%)
- LinkedIn Coverage: **2,792** (99.9%)

**V4 Upgrade Path:**
- V4 Upgraded Leads: **562** (20.1%)

**Firm Exclusions:**
- Savvy (CRD 318493): **0** EXCLUDED
- Ritholtz (CRD 168652): **0** EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **4** (0.1%)
- TIER_1B_PRIME_MOVER_SERIES65: **70** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **58** (2.1%)
- TIER_1_PRIME_MOVER: **350** (12.5%)
- TIER_2_PROVEN_MOVER: **1,750** (62.6%)
- V4_UPGRADE: **562** (20.1%) ⬆️ V4 UPGRADE

**V3/V4 Disagreement Exclusions:**
- Excluded Leads: **111** (Tier 1 with V4 < 50th percentile)
- Exclusion File: **excluded_v3_v4_disagreement_leads_20251226.csv**

**Excluded by Tier:**
- TIER_1A_PRIME_MOVER_CFP: **2**
- TIER_1B_PRIME_MOVER_SERIES65: **5**
- TIER_1F_HV_WEALTH_BLEEDER: **52**
- TIER_1_PRIME_MOVER: **52**

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or V4_UPGRADE)
12. `original_v3_tier` - Original V3 tier before upgrade
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_v4_upgrade` - **1 = V4 upgraded lead, 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 4: Export Lead List to CSV - 2025-12-26 00:20:58

**Status**: SUCCESS

**Export File**: `january_2026_lead_list_20251226.csv`  
**Location**: `C:\Users\russe\Documents\lead_scoring_production\pipeline\exports\january_2026_lead_list_20251226.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,786**
- File Size: **1515.0 KB**

**New Features:**
- Job Title Coverage: **2,786** (100.0%)
- Narrative Coverage: **2,786** (100.0%)
- LinkedIn Coverage: **2,785** (100.0%)

**V4 Upgrade Path:**
- V4 Upgraded Leads: **562** (20.2%)

**Firm Exclusions:**
- Savvy (CRD 318493): **0** EXCLUDED
- Ritholtz (CRD 168652): **0** EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **2** (0.1%)
- TIER_1B_PRIME_MOVER_SERIES65: **70** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **52** (1.9%)
- TIER_1_PRIME_MOVER: **350** (12.6%)
- TIER_2_PROVEN_MOVER: **1,750** (62.8%)
- V4_UPGRADE: **562** (20.2%) ⬆️ V4 UPGRADE

**V3/V4 Disagreement Exclusions:**
- Excluded Leads: **255** (Tier 1 with V4 < 70th percentile)
- Exclusion File: **excluded_v3_v4_disagreement_leads_20251226.csv**

**Excluded by Tier:**
- TIER_1A_PRIME_MOVER_CFP: **5**
- TIER_1B_PRIME_MOVER_SERIES65: **14**
- TIER_1F_HV_WEALTH_BLEEDER: **106**
- TIER_1_PRIME_MOVER: **130**

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or V4_UPGRADE)
12. `original_v3_tier` - Original V3 tier before upgrade
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_v4_upgrade` - **1 = V4 upgraded lead, 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 2: V4 Scoring with SHAP Narratives - 2025-12-26 01:01:11

**Status**: ✅ SUCCESS

**Results:**
- Total scored: 285,690
- V4 upgrade candidates: 56,356
- V4 narratives generated: 56,356
- Score range: 0.1062 - 0.8440

**New Columns:**
- `shap_top1/2/3_feature`: Top 3 SHAP features
- `shap_top1/2/3_value`: SHAP values for those features
- `v4_narrative`: Human-readable narrative for V4 upgrades

**Table Updated**: `savvy-gtm-analytics.ml_features.v4_prospect_scores`

---


## Step 4: Export Lead List to CSV - 2025-12-26 01:02:04

**Status**: SUCCESS

**Export File**: `january_2026_lead_list_20251226.csv`  
**Location**: `C:\Users\russe\Documents\lead_scoring_production\pipeline\exports\january_2026_lead_list_20251226.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,786**
- File Size: **1450.5 KB**

**New Features:**
- Job Title Coverage: **2,786** (100.0%)
- Narrative Coverage: **2,786** (100.0%)
- LinkedIn Coverage: **2,785** (100.0%)

**V4 Upgrade Path:**
- V4 Upgraded Leads: **562** (20.2%)

**Firm Exclusions:**
- Savvy (CRD 318493): **0** EXCLUDED
- Ritholtz (CRD 168652): **0** EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **2** (0.1%)
- TIER_1B_PRIME_MOVER_SERIES65: **70** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **52** (1.9%)
- TIER_1_PRIME_MOVER: **350** (12.6%)
- TIER_2_PROVEN_MOVER: **1,750** (62.8%)
- V4_UPGRADE: **562** (20.2%) ⬆️ V4 UPGRADE

**V3/V4 Disagreement Exclusions:**
- Excluded Leads: **255** (Tier 1 with V4 < 70th percentile)
- Exclusion File: **excluded_v3_v4_disagreement_leads_20251226.csv**

**Excluded by Tier:**
- TIER_1A_PRIME_MOVER_CFP: **5**
- TIER_1B_PRIME_MOVER_SERIES65: **14**
- TIER_1F_HV_WEALTH_BLEEDER: **106**
- TIER_1_PRIME_MOVER: **130**

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or V4_UPGRADE)
12. `original_v3_tier` - Original V3 tier before upgrade
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_v4_upgrade` - **1 = V4 upgraded lead, 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 4: Export Lead List to CSV - 2025-12-26 01:22:18

**Status**: SUCCESS

**Export File**: `january_2026_lead_list_20251226.csv`  
**Location**: `C:\Users\russe\Documents\lead_scoring_production\pipeline\exports\january_2026_lead_list_20251226.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,765**
- File Size: **1437.3 KB**

**New Features:**
- Job Title Coverage: **2,765** (100.0%)
- Narrative Coverage: **2,765** (100.0%)
- LinkedIn Coverage: **2,764** (100.0%)

**V4 Upgrade Path:**
- V4 Upgraded Leads: **541** (19.6%)

**Firm Exclusions:**
- Savvy (CRD 318493): **0** EXCLUDED
- Ritholtz (CRD 168652): **0** EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **2** (0.1%)
- TIER_1B_PRIME_MOVER_SERIES65: **70** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **52** (1.9%)
- TIER_1_PRIME_MOVER: **350** (12.7%)
- TIER_2_PROVEN_MOVER: **1,750** (63.3%)
- V4_UPGRADE: **541** (19.6%) ⬆️ V4 UPGRADE

**V3/V4 Disagreement Exclusions:**
- Excluded Leads: **255** (Tier 1 with V4 < 70th percentile)
- Exclusion File: **excluded_v3_v4_disagreement_leads_20251226.csv**

**Excluded by Tier:**
- TIER_1A_PRIME_MOVER_CFP: **5**
- TIER_1B_PRIME_MOVER_SERIES65: **14**
- TIER_1F_HV_WEALTH_BLEEDER: **106**
- TIER_1_PRIME_MOVER: **130**

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or V4_UPGRADE)
12. `original_v3_tier` - Original V3 tier before upgrade
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_v4_upgrade` - **1 = V4 upgraded lead, 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 4: Export Lead List to CSV - 2025-12-26 15:57:00

**Status**: SUCCESS

**Export File**: `january_2026_lead_list_20251226.csv`  
**Location**: `C:\Users\russe\Documents\lead_scoring_production\pipeline\exports\january_2026_lead_list_20251226.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,765**
- File Size: **1431.9 KB**

**New Features:**
- Job Title Coverage: **2,765** (100.0%)
- Narrative Coverage: **2,765** (100.0%)
- LinkedIn Coverage: **2,764** (100.0%)

**V4 Upgrade Path:**
- High-V4 STANDARD (Backfill): **0** (0.0%)
- Legacy V4 Upgrades: **541** (19.6%) [Note: V4_UPGRADE tier removed in optimization]

**Firm Exclusions:**
- Savvy (CRD 318493): **0** EXCLUDED
- Ritholtz (CRD 168652): **0** EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **2** (0.1%)
- TIER_1B_PRIME_MOVER_SERIES65: **70** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **52** (1.9%)
- TIER_1_PRIME_MOVER: **350** (12.7%)
- TIER_2_PROVEN_MOVER: **1,750** (63.3%)
- V4_UPGRADE: **541** (19.6%) [LEGACY]

**V3/V4 Disagreement Exclusions:**
- Excluded Leads: **255** (Tier 1 with V4 < 70th percentile)
- Exclusion File: **excluded_v3_v4_disagreement_leads_20251226.csv**

**Excluded by Tier:**
- TIER_1A_PRIME_MOVER_CFP: **5**
- TIER_1B_PRIME_MOVER_SERIES65: **14**
- TIER_1F_HV_WEALTH_BLEEDER: **106**
- TIER_1_PRIME_MOVER: **130**

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or STANDARD_HIGH_V4 for backfill)
12. `original_v3_tier` - Original V3 tier (STANDARD for backfill leads)
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_high_v4_standard` - **1 = High-V4 STANDARD (backfill), 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 4: Export Lead List to CSV - 2025-12-26 15:57:52

**Status**: SUCCESS

**Export File**: `january_2026_lead_list_20251226.csv`  
**Location**: `C:\Users\russe\Documents\lead_scoring_production\pipeline\exports\january_2026_lead_list_20251226.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,763**
- File Size: **1399.9 KB**

**New Features:**
- Job Title Coverage: **2,763** (100.0%)
- Narrative Coverage: **2,763** (100.0%)
- LinkedIn Coverage: **2,730** (98.8%)

**V4 Upgrade Path:**
- High-V4 STANDARD (Backfill): **0** (0.0%)
- Legacy V4 Upgrades: **0** (0.0%) [Note: V4_UPGRADE tier removed in optimization]

**Firm Exclusions:**
- Savvy (CRD 318493): **0** EXCLUDED
- Ritholtz (CRD 168652): **0** EXCLUDED

**Tier Distribution:**
- TIER_1A_PRIME_MOVER_CFP: **1** (0.0%)
- TIER_1B_PRIME_MOVER_SERIES65: **70** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **52** (1.9%)
- TIER_1_PRIME_MOVER: **350** (12.7%)
- TIER_2_PROVEN_MOVER: **1,750** (63.3%)
- TIER_3_MODERATE_BLEEDER: **350** (12.7%)
- TIER_4_EXPERIENCED_MOVER: **190** (6.9%)

**V3/V4 Disagreement Exclusions:**
- Excluded Leads: **255** (Tier 1 with V4 < 70th percentile)
- Exclusion File: **excluded_v3_v4_disagreement_leads_20251226.csv**

**Excluded by Tier:**
- TIER_1A_PRIME_MOVER_CFP: **5**
- TIER_1B_PRIME_MOVER_SERIES65: **14**
- TIER_1F_HV_WEALTH_BLEEDER: **106**
- TIER_1_PRIME_MOVER: **130**

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or STANDARD_HIGH_V4 for backfill)
12. `original_v3_tier` - Original V3 tier (STANDARD for backfill leads)
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_high_v4_standard` - **1 = High-V4 STANDARD (backfill), 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 4: Export Lead List to CSV - 2025-12-26 16:29:36

**Status**: SUCCESS

**Export File**: `january_2026_lead_list_20251226.csv`  
**Location**: `C:\Users\russe\Documents\lead_scoring_production\pipeline\exports\january_2026_lead_list_20251226.csv`

### Export Summary

**Basic Metrics:**
- Total Rows: **2,768**
- File Size: **1409.3 KB**

**New Features:**
- Job Title Coverage: **2,768** (100.0%)
- Narrative Coverage: **2,768** (100.0%)
- LinkedIn Coverage: **2,747** (99.2%)

**V4 Upgrade Path:**
- High-V4 STANDARD (Backfill): **218** (7.9%)
- Legacy V4 Upgrades: **0** (0.0%) [Note: V4_UPGRADE tier removed in optimization]

**Firm Exclusions:**
- Savvy (CRD 318493): **0** EXCLUDED
- Ritholtz (CRD 168652): **0** EXCLUDED

**Tier Distribution:**
- STANDARD_HIGH_V4: **218** (7.9%) [BACKFILL]
- TIER_1A_PRIME_MOVER_CFP: **1** (0.0%)
- TIER_1B_PRIME_MOVER_SERIES65: **70** (2.5%)
- TIER_1F_HV_WEALTH_BLEEDER: **52** (1.9%)
- TIER_1_PRIME_MOVER: **350** (12.6%)
- TIER_2_PROVEN_MOVER: **1,750** (63.2%)
- TIER_3_MODERATE_BLEEDER: **327** (11.8%)

**V3/V4 Disagreement Exclusions:**
- Excluded Leads: **255** (Tier 1 with V4 < 70th percentile)
- Exclusion File: **excluded_v3_v4_disagreement_leads_20251226.csv**

**Excluded by Tier:**
- TIER_1A_PRIME_MOVER_CFP: **5**
- TIER_1B_PRIME_MOVER_SERIES65: **14**
- TIER_1F_HV_WEALTH_BLEEDER: **106**
- TIER_1_PRIME_MOVER: **130**

### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or STANDARD_HIGH_V4 for backfill)
12. `original_v3_tier` - Original V3 tier (STANDARD for backfill leads)
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_high_v4_standard` - **1 = High-V4 STANDARD (backfill), 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---


## Step 2: V4 Scoring with SHAP Narratives - 2025-12-30 15:42:56

**Status**: ✅ SUCCESS

**Results:**
- Total scored: 1,571,776
- V4 upgrade candidates: 314,349
- V4 narratives generated: 314,349
- Score range: 0.1550 - 0.7038

**New Columns:**
- `shap_top1/2/3_feature`: Top 3 SHAP features
- `shap_top1/2/3_value`: SHAP values for those features
- `v4_narrative`: Human-readable narrative for V4 upgrades

**Table Updated**: `savvy-gtm-analytics.ml_features.v4_prospect_scores`

---

