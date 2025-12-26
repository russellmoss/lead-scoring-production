# V3/V4 Disagreement Filter - Implementation

## 🎯 **PURPOSE**

Exclude Tier 1 leads where V3 assigns a high tier but V4 scores them below the 70th percentile. Historical analysis shows these leads have **0% conversion rate**.

## 📊 **INVESTIGATION FINDINGS**

- **Tier 1 leads with V4 < 70th percentile**: 0% conversion rate
- **January 2026 list had**: 8 such leads (including 2 of 4 Tier 1A leads: Kurt Durrwachter, Penny Frank)
- **Expected impact**: Remove low-confidence leads, improve overall conversion rate

## ✅ **IMPLEMENTATION**

### 1. SQL Query Changes

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Added CTEs**:
- `v3_v4_disagreement_leads`: Identifies leads to exclude
- `final_lead_list`: Filters out disagreement leads

**Filter Logic**:
```sql
WHERE NOT (
    score_tier IN (
        'TIER_1A_PRIME_MOVER_CFP',
        'TIER_1B_PRIME_MOVER_SERIES65',
        'TIER_1_PRIME_MOVER',
        'TIER_1F_HV_WEALTH_BLEEDER'
    )
    AND v4_percentile < 70
)
```

**Excluded Leads Table**:
- Creates `january_2026_excluded_v3_v4_disagreement` table
- Includes: advisor_crd, name, firm, score_tier, v4_score, v4_percentile, exclusion_reason

### 2. Export Script Changes

**File**: `pipeline/scripts/export_lead_list.py`

**New Features**:
- Fetches excluded leads from BigQuery
- Exports to `excluded_v3_v4_disagreement_leads_YYYYMMDD.csv`
- Adds validation checks for disagreement leads
- Logs exclusion summary in execution log

## 🔍 **VALIDATION QUERIES**

### Check Final List (Should be 0)
```sql
SELECT 
    COUNT(*) as disagreement_leads_in_final_list
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
WHERE score_tier IN (
    'TIER_1A_PRIME_MOVER_CFP',
    'TIER_1B_PRIME_MOVER_SERIES65',
    'TIER_1_PRIME_MOVER',
    'TIER_1F_HV_WEALTH_BLEEDER'
)
AND v4_percentile < 70;
-- Expected: 0
```

### Check Excluded Leads Table
```sql
SELECT 
    score_tier,
    COUNT(*) as count,
    ROUND(AVG(v4_percentile), 1) as avg_v4_percentile,
    ROUND(AVG(v4_score), 3) as avg_v4_score
FROM `savvy-gtm-analytics.ml_features.january_2026_excluded_v3_v4_disagreement`
GROUP BY score_tier
ORDER BY score_tier;
-- Expected: ~10 leads total
```

### Verify Specific Leads
```sql
SELECT 
    name,
    firm_name,
    score_tier,
    v4_percentile,
    v4_score
FROM `savvy-gtm-analytics.ml_features.january_2026_excluded_v3_v4_disagreement`
WHERE name IN ('Kurt Durrwachter', 'Penny Frank')
ORDER BY name;
-- Expected: Both should be in excluded table
```

## 📈 **EXPECTED RESULTS**

### Before Filter:
- Total leads: 2,794
- Tier 1A: 4 leads
- Tier 1 with V4 < 70: 8 leads (Kurt Durrwachter, Penny Frank, 6 Tier 1F)

### After Filter:
- Total leads: ~2,786 (8 fewer)
- Tier 1A: ~2 leads (2 excluded: Kurt Durrwachter, Penny Frank)
- Tier 1 with V4 < 70: **0 leads** ✅

## 🚀 **NEXT STEPS**

1. **Re-run Step 3** (Lead list generation) to apply filter
2. **Re-run Step 4** (Export) to generate new CSV with exclusions
3. **Validate** using queries above
4. **Review excluded leads** to confirm they match expectations

## 📝 **FILES MODIFIED**

1. `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
   - Added `v3_v4_disagreement_leads` CTE
   - Added `final_lead_list` CTE with filter
   - Created excluded leads table

2. `pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql`
   - Same changes as above (kept in sync)

3. `pipeline/scripts/export_lead_list.py`
   - Added `fetch_excluded_leads()` function
   - Added excluded leads export to CSV
   - Added validation checks for disagreement leads
   - Updated logging to include exclusion summary

