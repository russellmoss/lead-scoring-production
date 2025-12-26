# SGA Assignment Feature - Automatic Lead Distribution

**Version**: 1.0  
**Date**: December 2025  
**Status**: ✅ Integrated into Lead List Generation Pipeline

---

## Overview

The lead list generation pipeline now **automatically assigns leads to active SGAs** using an equitable conversion-based distribution strategy. This ensures each SGA receives a similar expected conversion value, not just an equal number of leads.

---

## How It Works

### 1. Dynamic SGA Discovery

The pipeline automatically:
- Queries `savvy-gtm-analytics.SavvyGTMData.User` table
- Finds all users where `IsActive = true` AND `IsSGA__c = true`
- Excludes specified users:
  - Jacqueline Tully
  - GinaRose
  - Savvy Marketing
  - Savvy Operations
  - Anett Davis
  - Anett Diaz

### 2. Equitable Distribution Strategy

**Conversion Rate Buckets**:
- **HIGH_CONV** (8%+): T1A, T1B leads
- **MED_HIGH_CONV** (6-8%): T1, T1F leads
- **MED_CONV** (5-6%): T2 leads
- **MED_LOW_CONV** (4-5%): T3, T4, V4_UPGRADE leads
- **LOW_CONV** (<4%): T5, STANDARD leads

**Distribution Method**: Stratified Round-Robin
1. Leads are grouped by conversion rate bucket AND tier
2. Within each bucket/tier combination, leads are assigned round-robin to SGAs
3. This ensures each SGA gets similar mix of high/medium/low conversion leads

**Example**:
- 50 T1A leads (8.7% conversion) → Distributed round-robin to 14 SGAs
- Each SGA gets ~3-4 T1A leads
- Each SGA gets ~125 T2 leads (5.2% conversion)
- Result: Each SGA has similar expected conversion value

### 3. Output Columns

Two new columns are added to the lead list:

- **`sga_owner`**: SGA name (e.g., "Amy Waller")
- **`sga_id`**: Salesforce User ID (e.g., "005VS000006CwUbYAK")

These columns can be used to:
- Update Salesforce Lead Owner fields
- Track performance by SGA
- Generate per-SGA reports

---

## Current Active SGAs

**Total Active SGAs (after exclusions)**: 14 SGAs

**Expected Distribution**: ~171 leads per SGA (2,400 total / 14 SGAs = 171.4)

**Current Active SGAs** (as of December 2025):
1. Amy Waller
2. Brian O'Hara
3. Channing Guyer
4. Chris Morgan
5. Craig Suchodolski
6. Eleni Stefanopoulos
7. Helen Kamens
8. Holly Huffman
9. Jason Ainsworth
10. Lauren George
11. Marisa Saucedo
12. Perry Kalmeta
13. Russell Armitage
14. Ryan Crandall

**Note**: The list is automatically pulled from Salesforce User table each time the pipeline runs, so it will always reflect current active SGAs.

---

## Updating Exclusions

To add/remove SGA exclusions, edit the SQL query:

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Location**: CTE `active_sgas` (around line 560)

```sql
active_sgas AS (
    SELECT 
        Id as sga_id,
        Name as sga_name,
        ROW_NUMBER() OVER (ORDER BY Name) as sga_number,
        COUNT(*) OVER () as total_sgas
    FROM `savvy-gtm-analytics.SavvyGTMData.User`
    WHERE IsActive = true
      AND IsSGA__c = true
      AND Name NOT IN (
          'Jacqueline Tully', 
          'GinaRose', 
          'Savvy Marketing', 
          'Savvy Operations', 
          'Anett Davis', 
          'Anett Diaz'
          -- Add new exclusions here
      )
),
```

**To add exclusion**: Add name to the `NOT IN` list  
**To remove exclusion**: Remove name from the `NOT IN` list

---

## Validation Queries

### Check SGA Distribution Balance

```sql
SELECT 
    sga_owner,
    COUNT(*) as lead_count,
    ROUND(AVG(expected_rate_pct), 2) as avg_expected_conv_pct,
    ROUND(SUM(expected_rate_pct) / 100, 1) as expected_conversions
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY sga_owner
ORDER BY sga_owner;
```

**Expected Results**:
- Each SGA should have ~171 leads (2,400 / 14 SGAs)
- Average expected conversion rate should be similar across SGAs (~4.2-4.5%)
- Expected conversions should be balanced

### Check Tier Distribution per SGA

```sql
SELECT 
    sga_owner,
    score_tier,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY sga_owner), 1) as pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY sga_owner, score_tier
ORDER BY sga_owner, score_tier;
```

**Expected Results**:
- Each SGA should have similar tier distribution percentages
- Example: Each SGA should have ~2-3% T1A leads, ~12-13% T2 leads, etc.

---

## Benefits

1. **Automatic**: No manual distribution needed
2. **Equitable**: Each SGA gets similar conversion value, not just lead count
3. **Dynamic**: Automatically adjusts to number of active SGAs
4. **Maintainable**: Easy to update exclusions
5. **Transparent**: Distribution logic is visible in SQL
6. **Salesforce-Ready**: Includes SGA IDs for direct Salesforce updates

---

## Integration Points

### In SQL Query
- **CTE**: `active_sgas` - Pulls active SGAs from Salesforce
- **CTE**: `leads_with_conv_bucket` - Creates conversion buckets
- **CTE**: `leads_assigned` - Calculates SGA assignment
- **CTE**: `leads_with_sga` - Joins SGA details
- **Output**: Adds `sga_owner` and `sga_id` columns

### In Export Script
- **Columns**: `sga_owner` and `sga_id` included in export
- **Validation**: Checks SGA distribution balance
- **Reports**: Shows tier distribution per SGA

---

## Future Enhancements

Potential improvements:
1. **Geographic Distribution**: Assign leads based on advisor location
2. **Workload Balancing**: Consider existing SGA workload
3. **Performance-Based**: Weight distribution by SGA historical performance
4. **Time-Based**: Rotate high-value leads across SGAs monthly

---

**Last Updated**: December 2025  
**Maintainer**: Data Science Team

