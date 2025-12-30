# BigQuery Table Cleanup Plan

**Date**: December 30, 2025  
**Purpose**: Document BigQuery table cleanup strategy for `ml_features` dataset  
**Status**: Documentation Only (Execute After Phase 5 Validation)

---

## Executive Summary

This document outlines which BigQuery tables in the `savvy-gtm-analytics.ml_features` dataset should be:
- **KEPT** (Production tables actively used)
- **ARCHIVED** (Historical reference - keep for analysis)
- **DELETED** (Deprecated/test tables - safe to remove)

**⚠️ IMPORTANT**: Do NOT execute table deletions until Phase 5 validation is complete and production systems are verified working.

---

## Production Tables (KEEP ✅)

### V3 Rules-Based Model Tables

| Table | Purpose | Created By | Usage | Status |
|-------|---------|------------|-------|--------|
| `ml_features.lead_scoring_features_pit` | V3 PIT features for tier assignment | `v3/sql/lead_scoring_features_pit.sql` | V3 tier scoring | ✅ Production |
| `ml_features.lead_scores_v3` | V3 tier assignments and scores | `v3/sql/phase_4_v3_tiered_scoring.sql` | Lead prioritization | ✅ Production |
| `ml_features.tier_calibration_v3` | Calibrated conversion rates by tier | Manual/validation queries | Tier performance tracking | ✅ Production |

### V3 Views (Production)

| View | Purpose | Created By | Usage | Status |
|------|---------|------------|-------|--------|
| `ml_features.lead_scores_v3_current` | Current priority leads (excludes STANDARD) | `v3/sql/phase_7_production_view.sql` | Dashboards | ✅ Production |
| `ml_features.sga_priority_leads_v3` | SGA-friendly dashboard view | `v3/sql/phase_7_sga_dashboard.sql` | SGA dashboards | ✅ Production |

### V4 ML Model Tables

| Table | Purpose | Created By | Usage | Status |
|-------|---------|------------|-------|--------|
| `ml_features.v4_prospect_features` | V4.1 features (22 features) for all prospects | `pipeline/sql/v4_prospect_features.sql` | V4 model scoring | ✅ Production |
| `ml_features.v4_prospect_scores` | V4.1 scores, percentiles, SHAP features | `pipeline/scripts/score_prospects_monthly.py` | Lead deprioritization | ✅ Production |

### V4 Supporting Tables (V4.1 Features)

| Table | Purpose | Created By | Usage | Status |
|-------|---------|------------|-------|--------|
| `ml_features.recent_movers_v41` | Recent movers (inferred departures) | `v4/sql/v4.1/create_recent_movers_table.sql` | V4.1 feature: `is_recent_mover` | ✅ Production |
| `ml_features.firm_bleeding_velocity_v41` | Bleeding velocity (ACCELERATING/STEADY/DECELERATING) | `v4/sql/v4.1/create_bleeding_velocity_table.sql` | V4.1 feature: `bleeding_velocity_encoded` | ✅ Production |
| `ml_features.firm_rep_type_features_v41` | Firm/rep type features | `v4/sql/v4.1/create_firm_rep_type_features.sql` | V4.1 features: `is_independent_ria`, `is_ia_rep_type`, `is_dual_registered` | ✅ Production |
| `ml_features.inferred_departures_analysis` | Inferred departures (START_DATE at new firm) | Historical analysis | V4.1 feature: `firm_departures_corrected` | ✅ Production |
| `ml_features.firm_bleeding_corrected` | Corrected bleeding metrics | Historical analysis | V4.1 feature: `firm_departures_corrected` | ✅ Production |

### Hybrid Pipeline Tables

| Table | Purpose | Created By | Usage | Status |
|-------|---------|------------|-------|--------|
| `ml_features.january_2026_lead_list` | Final hybrid lead list (V3 + V4) | `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | Monthly lead list | ✅ Production |
| `ml_features.excluded_firms` | Pattern-based firm exclusions | `pipeline/sql/create_excluded_firms_table.sql` | Lead list filtering | ✅ Production |
| `ml_features.excluded_firm_crds` | CRD-based firm exclusions | `pipeline/sql/create_excluded_firm_crds_table.sql` | Lead list filtering | ✅ Production |

### V4 Training/Validation Tables

| Table | Purpose | Created By | Usage | Status |
|-------|---------|------------|-------|--------|
| `ml_features.v4_features_pit_v41` | V4.1 PIT features for training | `v4/sql/v4.1/phase_2_feature_engineering_v41.sql` | Model training | ✅ Keep (training reference) |
| `ml_features.v4_splits_v41` | Train/test/gap splits for V4.1 | `v4/sql/v4.1/phase_6_train_test_split.sql` | Model validation | ✅ Keep (validation reference) |
| `ml_features.v4_target_variable` | Target variable (conversion) | Historical analysis | Model training | ✅ Keep (training reference) |

---

## Historical Reference Tables (ARCHIVE 📦)

**Action**: Keep for historical analysis, but document as archived

| Table | Purpose | Status | Notes |
|-------|---------|--------|-------|
| `ml_features.lead_scores_v3_2_12212025` | V3.2 consolidated scores (historical) | 📦 Archive | Superseded by `lead_scores_v3` |
| `ml_features.january_2026_lead_list_v4` | Old versioned lead list | 📦 Archive | Superseded by `january_2026_lead_list` |
| `ml_features.january_2026_excluded_v3_v4_disagreement` | Disagreement analysis table | 📦 Archive | One-time analysis, no longer needed |

**Note**: These tables may be referenced in historical queries or reports. Keep for reference but mark as archived.

---

## Deprecated/Test Tables (DELETE ❌)

**Action**: Safe to delete after validation

| Table | Purpose | Reason to Delete | Validation |
|-------|---------|-------------------|------------|
| `ml_features.v4_production_features` | V4.0 production features (old) | Superseded by `v4_prospect_features` | Check no queries reference it |
| `ml_features.v4_daily_scores_v41` | V4.1 daily scores (if exists) | Superseded by `v4_prospect_scores` | Check no queries reference it |
| `ml_features.v4_lead_scores_v41` | V4.1 lead scores (if exists) | Superseded by `v4_prospect_scores` | Check no queries reference it |
| `ml_features.test_*` | Test tables | Temporary test data | Verify no production dependencies |
| `ml_features.temp_*` | Temporary tables | Temporary data | Verify no production dependencies |

**⚠️ Before Deleting**: Run validation queries below to ensure no production queries reference these tables.

---

## Cleanup SQL

### Step 1: Inventory All Tables

```sql
-- List all tables in ml_features dataset
SELECT 
    table_name,
    table_type,
    creation_time,
    last_modified_time,
    row_count,
    size_bytes,
    CASE 
        WHEN table_name LIKE '%v4.0%' OR table_name LIKE '%v4_0%' THEN 'DELETE'
        WHEN table_name LIKE '%test%' OR table_name LIKE '%temp%' THEN 'DELETE'
        WHEN table_name LIKE '%january_2026_lead_list_v4%' THEN 'ARCHIVE'
        WHEN table_name LIKE '%excluded_v3_v4_disagreement%' THEN 'ARCHIVE'
        WHEN table_name IN (
            'lead_scoring_features_pit',
            'lead_scores_v3',
            'tier_calibration_v3',
            'v4_prospect_features',
            'v4_prospect_scores',
            'january_2026_lead_list',
            'excluded_firms',
            'excluded_firm_crds',
            'recent_movers_v41',
            'firm_bleeding_velocity_v41',
            'firm_rep_type_features_v41',
            'inferred_departures_analysis',
            'firm_bleeding_corrected',
            'v4_features_pit_v41',
            'v4_splits_v41',
            'v4_target_variable'
        ) THEN 'KEEP'
        ELSE 'REVIEW'
    END as cleanup_action
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
WHERE table_type = 'BASE TABLE'
ORDER BY cleanup_action, table_name;
```

### Step 2: Find Table Dependencies

```sql
-- Find all queries that reference deprecated tables
-- Run this in BigQuery to find dependent queries/views
-- Note: This requires access to BigQuery query history or INFORMATION_SCHEMA

-- Check for views that depend on deprecated tables
SELECT 
    table_name as view_name,
    view_definition
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.VIEWS`
WHERE view_definition LIKE '%v4_production_features%'
   OR view_definition LIKE '%v4_daily_scores_v41%'
   OR view_definition LIKE '%v4_lead_scores_v41%'
   OR view_definition LIKE '%january_2026_lead_list_v4%';
```

### Step 3: Archive Historical Tables (Optional)

```sql
-- Option 1: Copy to archive dataset (if archive dataset exists)
-- CREATE TABLE `savvy-gtm-analytics.ml_features_archive.january_2026_lead_list_v4` AS
-- SELECT * FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`;

-- Option 2: Export to Cloud Storage (recommended for large tables)
-- EXPORT DATA OPTIONS(
--   uri='gs://your-bucket/archive/january_2026_lead_list_v4/*',
--   format='PARQUET'
-- ) AS
-- SELECT * FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`;

-- Option 3: Keep in ml_features but document as archived (current approach)
-- No SQL needed - just document in this plan
```

### Step 4: Delete Deprecated Tables (After Validation)

```sql
-- ⚠️ ONLY RUN AFTER VALIDATION COMPLETE

-- Delete deprecated V4.0 tables
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.v4_production_features`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.v4_daily_scores_v41`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.v4_lead_scores_v41`;

-- Delete test/temp tables
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.test_*`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.temp_*`;

-- Note: Use specific table names, not wildcards (wildcards shown for documentation)
```

---

## Validation Before Cleanup

### Checklist

**Before deleting any tables**:

- [ ] **Inventory Complete**: All tables in `ml_features` dataset inventoried
- [ ] **Dependencies Checked**: No views or queries reference tables marked for deletion
- [ ] **Production Verified**: All production queries use correct table names
- [ ] **Backup Created**: Historical tables exported to Cloud Storage (if needed)
- [ ] **Documentation Updated**: All table references in code/docs updated
- [ ] **Team Notified**: Data team aware of cleanup plan

### Validation Queries

**1. Check Production Table Usage**:
```sql
-- Verify production tables exist and have data
SELECT 
    'lead_scoring_features_pit' as table_name,
    COUNT(*) as row_count,
    MAX(_PARTITIONTIME) as last_partition
FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`
UNION ALL
SELECT 'lead_scores_v3', COUNT(*), NULL
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
UNION ALL
SELECT 'v4_prospect_features', COUNT(*), NULL
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`
UNION ALL
SELECT 'v4_prospect_scores', COUNT(*), NULL
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
UNION ALL
SELECT 'january_2026_lead_list', COUNT(*), NULL
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
UNION ALL
SELECT 'excluded_firms', COUNT(*), NULL
FROM `savvy-gtm-analytics.ml_features.excluded_firms`
UNION ALL
SELECT 'excluded_firm_crds', COUNT(*), NULL
FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`;
```

**2. Check for Deprecated Table References**:
```sql
-- Search for deprecated table names in views
SELECT 
    table_name,
    view_definition
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.VIEWS`
WHERE view_definition LIKE '%v4_production_features%'
   OR view_definition LIKE '%v4_daily_scores_v41%'
   OR view_definition LIKE '%january_2026_lead_list_v4%';
```

**3. Verify Exclusion Tables**:
```sql
-- Verify exclusion tables have data
SELECT 
    'excluded_firms' as table_name,
    COUNT(*) as pattern_count,
    COUNT(DISTINCT category) as category_count
FROM `savvy-gtm-analytics.ml_features.excluded_firms`
UNION ALL
SELECT 
    'excluded_firm_crds',
    COUNT(*),
    COUNT(DISTINCT category)
FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`;
```

---

## Table Size Estimates

**Note**: Run actual queries to get current sizes

| Table Category | Estimated Size | Notes |
|----------------|---------------|-------|
| Production Tables | ~50-100 GB | V4 features/scores for ~285K prospects |
| Historical Tables | ~5-10 GB | Old lead lists, deprecated scores |
| Test/Temp Tables | ~1-5 GB | Temporary test data |

**Total Estimated Cleanup**: ~5-15 GB (if deleting deprecated tables)

---

## Execution Timeline

**Phase 3.5** (Current): Documentation only - **DO NOT EXECUTE**

**Phase 5+** (After Validation):
1. Run inventory query
2. Check dependencies
3. Export historical tables to Cloud Storage (optional)
4. Delete deprecated tables
5. Verify production systems still work

---

## Rollback Plan

**If Production Issues After Cleanup**:

1. **Restore from Cloud Storage** (if exported):
   ```sql
   -- Restore from exported Parquet files
   CREATE TABLE `savvy-gtm-analytics.ml_features.v4_production_features` AS
   SELECT * FROM `savvy-gtm-analytics.ml_features_restore.v4_production_features`;
   ```

2. **Recreate from SQL** (if SQL files exist):
   - Run original SQL files to recreate tables
   - SQL files preserved in repository

3. **Contact**: Data Science team for assistance

---

## Related Documentation

- **Production Tables**: See `README.md` "BigQuery Tables" section
- **Table Creation SQL**: See individual SQL files in `v3/sql/`, `v4/sql/`, `pipeline/sql/`
- **Model Evolution**: See `MODEL_EVOLUTION_HISTORY.md` for table evolution

---

**Document Status**: Complete  
**Execution Status**: ⏳ Pending (After Phase 5 Validation)  
**Risk Level**: Medium (table deletion is irreversible without backups)  
**Recommended**: Export historical tables to Cloud Storage before deletion

