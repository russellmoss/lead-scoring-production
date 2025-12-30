# ✅ READY TO EXECUTE: January 2026 Lead List

**Status**: ✅ **READY**  
**Date**: 2025-12-30

---

## What's Changed

### ✅ Updated SQL Files

1. **`pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`**
   - ✅ Now creates: `ml_features.january_2026_lead_list` (single new table)
   - ✅ Uses V4.1-R3 pipeline (22 features)
   - ✅ Includes all V4.1 features and scores

2. **`pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql`** (duplicate)
   - ✅ Updated to match

### ✅ Cleanup Script Created

**`pipeline/sql/cleanup_old_january_tables.sql`**
- Drops old tables after verification
- Safe to run after confirming new table is correct

### ✅ Documentation Created

- **`pipeline/sql/EXECUTE_JANUARY_2026_LEAD_LIST.md`** - Step-by-step execution guide
- **`pipeline/sql/generate_january_2026_lead_list.sql`** - Execution instructions

---

## What You Need to Do

### Step 1: Execute the Lead List SQL

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**In BigQuery Console**:
1. Open the file
2. Copy the entire SQL
3. Paste into BigQuery Console
4. Execute

**Result**: Creates `ml_features.january_2026_lead_list` with ~2,800 leads

### Step 2: Verify the New Table

Run this query to verify:
```sql
SELECT 
    COUNT(*) as total_leads,
    COUNT(DISTINCT sga_id) as sgas,
    AVG(v4_score) as avg_v4_score,
    MIN(v4_score) as min_score,
    MAX(v4_score) as max_score
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
```

**Expected**:
- total_leads: ~2,800
- sgas: 14
- avg_v4_score: ~0.40
- Score range: 0.15 - 0.70

### Step 3: Clean Up Old Tables (After Verification)

**File**: `pipeline/sql/cleanup_old_january_tables.sql`

**⚠️ Only run this AFTER verifying the new table is correct!**

This will drop:
- `ml_features.january_2026_lead_list_v4`
- `ml_features.january_2026_lead_list` (old version)
- `ml_features.january_2026_excluded_v3_v4_disagreement`

---

## What Gets Created

### New Table: `ml_features.january_2026_lead_list`

**Columns Include**:
- All V3 tier information (score_tier, tier_narrative, etc.)
- V4.1 scores (v4_score, v4_percentile, v4_deprioritize)
- V4.1 features (is_recent_mover, bleeding_velocity_encoded, etc.)
- SGA assignments (sga_name, sga_id)
- Lead information (crd, name, email, firm, etc.)
- SHAP narratives (shap_top1_feature, etc.)

**Row Count**: ~2,800 (200 per SGA × 14 SGAs)

---

## What Gets Removed

After cleanup, these old tables will be dropped:
- ❌ `ml_features.january_2026_lead_list_v4`
- ❌ `ml_features.january_2026_lead_list` (old version)
- ❌ `ml_features.january_2026_excluded_v3_v4_disagreement`

**Result**: Single clean table: `ml_features.january_2026_lead_list`

---

## Quick Reference

| Action | File | Result |
|--------|------|--------|
| **Generate Lead List** | `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | Creates new table |
| **Verify** | Run verification queries | Confirms data quality |
| **Cleanup** | `pipeline/sql/cleanup_old_january_tables.sql` | Drops old tables |

---

## Ready to Execute? ✅ YES

All files are updated and ready. You can now:
1. Execute the lead list SQL in BigQuery
2. Verify the results
3. Clean up old tables

See `pipeline/sql/EXECUTE_JANUARY_2026_LEAD_LIST.md` for detailed step-by-step instructions.

