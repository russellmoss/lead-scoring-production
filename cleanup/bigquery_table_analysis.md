# BigQuery Table Analysis - Production vs. Historical

**Date**: December 30, 2025  
**Dataset**: `savvy-gtm-analytics.ml_features`  
**Purpose**: Identify which tables are needed for production vs. which can be cleaned up

---

## Executive Summary

**Total Tables**: 39 tables + views  
**Production Tables**: 13 tables (actively used)  
**Training Tables**: 3 tables (needed for retraining)  
**Production Views**: 3 views  
**Historical/Analysis Tables**: 20+ tables (candidates for cleanup)

**Recommendation**: Archive or delete 20+ historical/analysis tables to reduce clutter and storage costs.

---

## Production Tables (KEEP ✅)

### Core Production Pipeline (10 tables)

| Table | Used By | Purpose | Status |
|-------|---------|---------|--------|
| `v4_prospect_features` | `pipeline/sql/v4_prospect_features.sql` | V4.1 features for all prospects | ✅ Production |
| `v4_prospect_scores` | `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | V4.1 scores and percentiles | ✅ Production |
| `january_2026_lead_list` | `pipeline/scripts/export_lead_list.py` | Final lead list output | ✅ Production |
| `excluded_firms` | `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | Firm exclusion patterns | ✅ Production |
| `excluded_firm_crds` | `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | CRD-based exclusions | ✅ Production |
| `recent_movers_v41` | `pipeline/sql/v4_prospect_features.sql` | Recent mover features | ✅ Production |
| `firm_bleeding_velocity_v41` | `pipeline/sql/v4_prospect_features.sql` | Bleeding velocity features | ✅ Production |
| `firm_rep_type_features_v41` | `pipeline/sql/v4_prospect_features.sql` | Firm/rep type features | ✅ Production |
| `inferred_departures_analysis` | `pipeline/sql/v4_prospect_features.sql` | Inferred departure data | ✅ Production |
| `firm_bleeding_corrected` | `pipeline/sql/v4_prospect_features.sql` | Corrected bleeding metrics | ✅ Production |

### V3 Production Tables (3 tables)

| Table | Used By | Purpose | Status |
|-------|---------|---------|--------|
| `lead_scoring_features_pit` | `v3/sql/phase_4_v3_tiered_scoring.sql` | V3 PIT features | ✅ Production |
| `lead_scores_v3` | `v3/sql/phase_7_production_view.sql` | V3 tier scores | ✅ Production |
| `tier_calibration_v3` | V3 validation | Tier conversion rates | ✅ Production |

### Production Views (3 views)

| View | Used By | Purpose | Status |
|------|---------|---------|--------|
| `v4_production_features_v41` | `v4/sql/production_scoring_v41.sql` | V4.1 production features view | ✅ Production |
| `lead_scores_v3_current` | V3 dashboards | Current priority leads | ✅ Production |
| `sga_priority_leads_v3` | `v3/sql/phase_7_sga_dashboard.sql` | SGA dashboard view | ✅ Production |

**Note**: `lead_scores_v3_2_12212025` is used by `v3/sql/phase_7_sga_dashboard.sql` but is historical. Should update dashboard to use `lead_scores_v3` instead.

---

## Training/Validation Tables (KEEP ✅)

These tables are needed for model retraining and validation:

| Table | Purpose | Status |
|-------|---------|--------|
| `v4_features_pit_v41` | V4.1 training features | ✅ Keep (retraining) |
| `v4_splits_v41` | V4.1 train/test splits | ✅ Keep (validation) |
| `v4_target_variable` | Conversion target variable | ✅ Keep (training) |

---

## Historical Tables (ARCHIVE/DELETE ❌)

### V3 Historical Tables (5 tables)

| Table | Status | Reason | Action |
|-------|--------|--------|--------|
| `lead_scores_v3_2_12212025` | ❌ Historical | Old V3.2 consolidated scores | **DELETE** (update dashboard first) |
| `lead_scores_v3_final` | ❌ Historical | Old V3 final scores | **DELETE** |
| `lead_scoring_features_pit_v2` | ❌ Historical | Old V2 features | **DELETE** |
| `lead_scoring_splits_v2` | ❌ Historical | Old V2 splits | **DELETE** |
| `lead_scoring_features` | ❌ Historical | Old features (non-PIT) | **DELETE** |

### V4 Historical Tables (2 tables)

| Table | Status | Reason | Action |
|-------|--------|--------|--------|
| `v4_features_pit` | ❌ Historical | V4.0 training features | **DELETE** |
| `v4_splits` | ❌ Historical | V4.0 train/test splits | **DELETE** |

### Analysis Tables (5 tables)

| Table | Status | Reason | Action |
|-------|--------|--------|--------|
| `historical_leads_v4_features` | ❌ Analysis | One-time V4 analysis | **DELETE** |
| `historical_leads_v4_scores` | ❌ Analysis | One-time V4 analysis | **DELETE** |
| `historical_leads_with_outcomes` | ❌ Analysis | One-time conversion analysis | **DELETE** |
| `historical_leads_with_tiers` | ❌ Analysis | One-time tier analysis | **DELETE** |
| `lead_optimization_analysis` | ❌ Analysis | One-time optimization analysis | **DELETE** |

### Other Historical/Analysis Tables (8+ tables)

| Table | Status | Reason | Action |
|-------|--------|--------|--------|
| `lead_scores_daily` | ❌ Review | Daily scores (purpose unclear) | **REVIEW** |
| `lead_scores_production` | ❌ Review | Production scores (duplicate?) | **REVIEW** |
| `lead_scoring_splits` | ❌ Historical | Old splits (non-v2) | **DELETE** |
| `lead_target_variable` | ❌ Review | Target variable (duplicate of v4_target_variable?) | **REVIEW** |
| `lead_velocity_features` | ❌ Review | Velocity features (purpose unclear) | **REVIEW** |
| `firm_rep_counts_pit` | ❌ Review | Firm rep counts (used by production?) | **REVIEW** |
| `sga_priority_list` | ❌ Review | SGA priority list (duplicate?) | **REVIEW** |
| `wine_interested_ria_advisors` | ❌ Review | Special list (purpose unclear) | **REVIEW** |

---

## Production Pipeline Dependencies

### Monthly Lead List Generation Pipeline

**Step 1: Calculate V4 Features**
- Uses: `firm_bleeding_corrected`, `firm_bleeding_velocity_v41`, `inferred_departures_analysis`, `firm_rep_type_features_v41`
- Creates: `v4_prospect_features`

**Step 2: Score Prospects**
- Uses: `v4_prospect_features`
- Creates: `v4_prospect_scores`

**Step 3: Generate Lead List**
- Uses: `v4_prospect_scores`, `v4_prospect_features`, `excluded_firms`, `excluded_firm_crds`
- Creates: `january_2026_lead_list`

**Step 4: Export**
- Uses: `january_2026_lead_list`

### V3 Tier Scoring (If Used)

- Uses: `lead_scoring_features_pit`
- Creates: `lead_scores_v3`
- Views: `lead_scores_v3_current`, `sga_priority_leads_v3`

---

## Recommended Cleanup Actions

### Phase 1: Safe Deletions (10 tables)

**Historical V3/V4 Tables**:
```sql
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scores_v3_final`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scoring_features_pit_v2`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scoring_splits_v2`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scoring_features`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scoring_splits`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.v4_features_pit`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.v4_splits`;
```

**Analysis Tables**:
```sql
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.historical_leads_v4_features`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.historical_leads_v4_scores`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.historical_leads_with_outcomes`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.historical_leads_with_tiers`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_optimization_analysis`;
```

### Phase 2: After Dashboard Update (1 table)

**Update Dashboard First**:
- Update `v3/sql/phase_7_sga_dashboard.sql` to use `lead_scores_v3` instead of `lead_scores_v3_2_12212025`
- Then delete: `lead_scores_v3_2_12212025`

### Phase 3: Review Tables (8 tables)

**Need Investigation**:
- `lead_scores_daily` - Check if used by any production process
- `lead_scores_production` - Check if duplicate of `lead_scores_v3`
- `lead_target_variable` - Check if duplicate of `v4_target_variable`
- `lead_velocity_features` - Check purpose and usage
- `firm_rep_counts_pit` - Check if used by production
- `sga_priority_list` - Check if duplicate of view
- `wine_interested_ria_advisors` - Check purpose

---

## Storage Impact

**Estimated Storage Freed**:
- Historical tables: ~5-10 GB
- Analysis tables: ~2-5 GB
- **Total**: ~7-15 GB

**Cost Savings**: ~$0.02-0.05 per month per GB (BigQuery storage pricing)

---

## Validation Before Deletion

### Checklist

- [ ] **Dashboard Updated**: `v3/sql/phase_7_sga_dashboard.sql` updated to use `lead_scores_v3`
- [ ] **Dependencies Checked**: No views/queries reference tables marked for deletion
- [ ] **Production Verified**: All production queries use correct table names
- [ ] **Backup Created**: Export historical tables to Cloud Storage (if needed)

### Verification Queries

**1. Check for Dependencies**:
```sql
-- Check views that reference historical tables
SELECT 
    table_name as view_name,
    view_definition
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.VIEWS`
WHERE view_definition LIKE '%lead_scores_v3_2%'
   OR view_definition LIKE '%lead_scoring_features_pit_v2%'
   OR view_definition LIKE '%v4_features_pit%'
   OR view_definition LIKE '%historical_leads%';
```

**2. Verify Production Tables Still Exist**:
```sql
SELECT table_name
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
WHERE table_name IN (
    'v4_prospect_features',
    'v4_prospect_scores',
    'january_2026_lead_list',
    'excluded_firms',
    'excluded_firm_crds',
    'lead_scoring_features_pit',
    'lead_scores_v3'
)
ORDER BY table_name;
```

---

## Summary

### Production Tables (13 tables + 3 views)
- ✅ All critical for monthly lead list generation
- ✅ Keep all

### Training Tables (3 tables)
- ✅ Needed for model retraining
- ✅ Keep all

### Historical/Analysis Tables (20+ tables)
- ❌ Not used in production pipeline
- ❌ Safe to delete after verification
- ❌ Estimated 7-15 GB storage freed

### Review Tables (8 tables)
- ⚠️ Need investigation to determine purpose
- ⚠️ Review before deletion

---

**Next Steps**:
1. Update `v3/sql/phase_7_sga_dashboard.sql` to remove dependency on `lead_scores_v3_2_12212025`
2. Execute Phase 1 deletions (10 tables)
3. Execute Phase 2 deletion (1 table after dashboard update)
4. Investigate Phase 3 review tables

