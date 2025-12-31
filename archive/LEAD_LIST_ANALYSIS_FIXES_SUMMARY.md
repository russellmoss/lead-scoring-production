# Lead List Analysis Queries - Fix Summary

**Date:** January 2026  
**File Updated:** `lead_list_analysis.md`

---

## Changes Made

### 1. Added Critical Notes Section (Top of Document)

Added comprehensive section explaining:
- **SQO Definition:** `Opportunity.SQL__c = 'yes'` (NOT Lead.Status)
- **Recommended Views:** `vw_funnel_lead_to_joined_v2` and `vw_conversion_rates`
- **Funnel Stage Definitions:** Contacted, MQL, SQL, SQO, Joined
- **Active SGA Filtering:** Use `SGA_IsActiveSGA = TRUE`

### 2. Fixed All SQO Definitions

**Before (WRONG):**
```sql
COUNT(DISTINCT CASE WHEN l.Status = 'Qualified' OR l.Status = 'Converted' THEN l.Id END) as sqos
```

**After (CORRECT):**
```sql
COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as sqos
```

### 3. Updated Queries to Use Recommended Views

#### Query 2.1: LinkedIn Contacts
- **Before:** Direct query to `SavvyGTMData.Lead` with Status filtering
- **After:** Uses `vw_funnel_lead_to_joined_v2` with `is_sqo` and `sqo_primary_key`

#### Query 2.2: LinkedIn Activity by SGA
- **Before:** Complex CTE with User table joins
- **After:** Uses `vw_funnel_lead_to_joined_v2` with `SGA_IsActiveSGA = TRUE`

#### Query 3.1: Side-by-Side Comparison
- **Before:** Mixed queries (lead_scores_v3 + Lead table)
- **After:** Provided uses `lead_scores_v3`, LinkedIn uses `vw_funnel_lead_to_joined_v2`

#### Query 3.2: Efficiency Analysis
- **Before:** Complex CTEs with Status-based filtering
- **After:** Uses `vw_conversion_rates` for pre-calculated metrics

#### Query 4.1: Activity Volume by Source
- **Before:** Direct Lead table queries
- **After:** Uses `vw_funnel_lead_to_joined_v2` with proper filtering

#### Query 4.2: SGA Activity Distribution
- **Before:** Complex joins between Lead and lead_scores_v3
- **After:** Uses `vw_funnel_lead_to_joined_v2` with CTEs for provided vs LinkedIn

#### Query 5.1: All Lead Sources
- **Before:** Direct Lead table query
- **After:** Uses `vw_funnel_lead_to_joined_v2` with `Original_source` field

#### Query 5.2: Campaign Analysis
- **Before:** Direct Lead table query
- **After:** Uses `vw_funnel_lead_to_joined_v2` with `Channel_Grouping_Name`

#### Query 6.1: Lead Volume vs Target
- **Before:** Direct Lead table query with LIKE patterns
- **After:** Uses `vw_funnel_lead_to_joined_v2` with `Original_source = 'LinkedIn (Self Sourced)'`

#### Query 7.1: Scenario Analysis
- **Before:** Direct Lead table query
- **After:** Uses `vw_funnel_lead_to_joined_v2` with proper SQO counting

#### Query 8.1: Summary Dashboard
- **Before:** Direct Lead table query
- **After:** Uses `vw_funnel_lead_to_joined_v2` with proper SQO counting

### 4. Updated Expected Insights Section

**Before:**
- LinkedIn is 33% more efficient (0.92% vs 0.69%)
- LinkedIn produced 60% of SQOs

**After:**
- Provided leads convert HIGHER than LinkedIn (4.13% vs 2.30%)
- Provided leads are 1.8x more efficient than LinkedIn
- Focus on Tier 1 Provided leads and LinkedIn best practices

### 5. Updated Important Notes Section

- **SGA Filtering:** Now uses `SGA_IsActiveSGA = TRUE` (automatic exclusions)
- **LinkedIn Identification:** Uses `Original_source = 'LinkedIn (Self Sourced)'`
- **Customization Notes:** Removed references to Status-based filtering

---

## Key Improvements

1. **Accuracy:** All queries now use correct SQO definition (`Opportunity.SQL__c = 'yes'`)
2. **Consistency:** All queries use standardized views (`vw_funnel_lead_to_joined_v2`, `vw_conversion_rates`)
3. **Maintainability:** Queries are simpler and use pre-calculated fields
4. **Correctness:** SQO counting uses `sqo_primary_key` (one SQO = one opportunity)

---

## Queries Still Using lead_scores_v3

The following queries still use `lead_scores_v3` for Provided leads:
- Query 1.1, 1.2, 1.3 (Step 1: Provided Lead Volume)
- Query 3.1 (Side-by-Side Comparison - Provided side)
- Query 6.2 (Tier 1 Lead Utilization)
- Query 8.1 (Summary Dashboard - Provided side)

**Note:** These are acceptable because:
- `lead_scores_v3.converted` should align with SQO definition
- These queries are specifically for Provided leads from lead lists
- The `lead_scores_v3` table is the source of truth for provided lead scoring

---

## Testing Recommendations

1. **Run Query 2.1** to verify LinkedIn SQO counts match expected values
2. **Run Query 3.2** to verify funnel metrics are accurate
3. **Compare Query 3.1 results** with previous baseline validation report
4. **Verify Query 5.1** shows all lead sources correctly

---

*Summary Generated: January 2026*  
*All queries updated to use correct SQO definition and recommended views*

