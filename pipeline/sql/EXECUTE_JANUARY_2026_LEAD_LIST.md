# Execute January 2026 Lead List Generation

**Date**: 2025-12-30  
**Purpose**: Generate the final January 2026 lead list using V4.1-R3 pipeline

---

## Overview

This process will:
1. ✅ Generate a new single table: `ml_features.january_2026_lead_list`
2. ✅ Use the V4.1-R3 pipeline (22 features, improved scoring)
3. ✅ Replace old tables (will be dropped after verification)

---

## Step-by-Step Execution

### Step 1: Generate the New Lead List

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Action**: Execute this SQL in BigQuery Console

**What it does**:
- Creates `ml_features.january_2026_lead_list` with ~2,800 leads
- Uses V3.2.5 rules + V4.1-R3 ML scores
- Includes all V4.1 features (is_recent_mover, bleeding_velocity_encoded, etc.)
- Assigns leads to SGAs (200 per SGA)

**Expected Output**:
- Table: `ml_features.january_2026_lead_list`
- Rows: ~2,800 (200 per SGA × 14 SGAs)
- Columns: All V3 tiers, V4.1 scores, V4.1 features, SGA assignments

**Verification Query** (run after execution):
```sql
SELECT 
    COUNT(*) as total_leads,
    COUNT(DISTINCT sga_id) as sgas,
    AVG(v4_score) as avg_v4_score,
    COUNT(DISTINCT score_tier) as tier_count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
```

**Expected Results**:
- total_leads: ~2,800
- sgas: 14
- avg_v4_score: ~0.40
- tier_count: 6-8 (various tiers)

---

### Step 2: Verify the New Table

**Action**: Run verification queries to ensure data quality

**Query 1: Row Count and Distribution**
```sql
SELECT 
    score_tier,
    COUNT(*) as leads,
    AVG(v4_score) as avg_score,
    AVG(v4_percentile) as avg_percentile
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY score_tier
ORDER BY leads DESC;
```

**Query 2: SGA Distribution**
```sql
SELECT 
    sga_name,
    COUNT(*) as leads,
    AVG(v4_score) as avg_score
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY sga_name
ORDER BY sga_name;
```

**Query 3: V4.1 Features Check**
```sql
SELECT 
    COUNT(*) as total,
    SUM(v4_is_recent_mover) as recent_movers,
    AVG(v4_firm_departures_corrected) as avg_departures,
    COUNT(DISTINCT v4_bleeding_velocity_encoded) as velocity_categories
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
```

**Validation Checklist**:
- [ ] Total leads = ~2,800
- [ ] All 14 SGAs have ~200 leads each
- [ ] V4.1 scores present (v4_score, v4_percentile)
- [ ] V4.1 features present (is_recent_mover, bleeding_velocity_encoded, etc.)
- [ ] Tier distribution looks reasonable
- [ ] No NULL values in critical columns

---

### Step 3: Clean Up Old Tables (AFTER VERIFICATION)

**⚠️ IMPORTANT**: Only run this AFTER verifying the new table is correct!

**File**: `pipeline/sql/cleanup_old_january_tables.sql`

**Action**: Execute this SQL in BigQuery Console

**What it does**:
- Drops `ml_features.january_2026_lead_list_v4`
- Drops `ml_features.january_2026_lead_list` (old version)
- Drops `ml_features.january_2026_excluded_v3_v4_disagreement`

**Verification Query** (run after cleanup):
```sql
SELECT table_name 
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
WHERE table_name LIKE '%january_2026%'
ORDER BY table_name;
```

**Expected Result**: Only `january_2026_lead_list` should exist

---

## Quick Execution Commands

### Option 1: BigQuery Console
1. Open BigQuery Console
2. Navigate to `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
3. Copy and paste into BigQuery Console
4. Execute
5. Verify results
6. Execute `cleanup_old_january_tables.sql` (after verification)

### Option 2: bq CLI
```bash
# Generate lead list
bq query --use_legacy_sql=false < pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql

# Verify (run manually)
bq query --use_legacy_sql=false "SELECT COUNT(*) FROM ml_features.january_2026_lead_list"

# Cleanup (after verification)
bq query --use_legacy_sql=false < pipeline/sql/cleanup_old_january_tables.sql
```

---

## Rollback Plan

If something goes wrong:

1. **If new table has issues**: The old tables still exist (until cleanup)
2. **If cleanup was run prematurely**: 
   - Re-run `January_2026_Lead_List_V3_V4_Hybrid.sql` to regenerate
   - Or restore from backup if available

---

## Expected Results Summary

| Metric | Expected Value |
|--------|---------------|
| **Total Leads** | ~2,800 |
| **SGAs** | 14 |
| **Leads per SGA** | ~200 |
| **Average V4 Score** | ~0.40 |
| **Tiers** | 6-8 different tiers |
| **V4.1 Features** | All present (is_recent_mover, bleeding_velocity_encoded, etc.) |

---

## Files Reference

- **Main SQL**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
- **Cleanup SQL**: `pipeline/sql/cleanup_old_january_tables.sql`
- **Execution Guide**: This file

---

**Ready to Execute**: ✅ Yes  
**Last Updated**: 2025-12-30

