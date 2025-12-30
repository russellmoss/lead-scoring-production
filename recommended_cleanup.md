# Repository Cleanup Recommendations

**Date**: December 30, 2025  
**Current Production**: V3.3 (Rules-Based) + V4.1.0 R3 (XGBoost) Hybrid Pipeline  
**Status**: Comprehensive Analysis & Recommendations

---

## Executive Summary

This document provides a comprehensive cleanup plan for the lead scoring production repository. The repo has accumulated significant technical debt from iterative model development (V1 → V2 → V3 → V4 → V4.1), and now that we have a stable hybrid production pipeline, it's time to clean up while preserving institutional knowledge.

**Recommendation**: **YES, proceed with cleanup** using a phased approach that preserves historical lessons learned while removing deprecated code and redundant documentation.

**⚠️ CRITICAL**: Before executing any cleanup phases, **MUST complete Phase 0.5 (Pre-Flight Verification)** to ensure all production-critical files are identified and preserved. Several critical production files were missing from the initial KEEP list and have been added in this update.

---

## Current State Assessment

### Production Assets (KEEP)

| Component | Location | Status | Notes |
|-----------|----------|--------|-------|
| **V3.3 Rules Model** | `v3/sql/generate_lead_list_v3.3.0.sql` (OR v3.2.1 if rename not done) | ✅ Production | Core tier logic for prioritization - **VERIFY which exists in Phase 0.5** |
| **V4.1.0 R3 ML Model** | `v4/models/v4.1.0_r3/` | ✅ Production | XGBoost model for deprioritization |
| **Hybrid Pipeline** | `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | ✅ Production | Monthly lead list generation |
| **Feature Engineering** | `pipeline/sql/v4_prospect_features.sql` | ✅ Production | V4.1 feature calculation |
| **Scoring Script** | `pipeline/scripts/score_prospects_monthly.py` | ✅ Production | Monthly ML scoring |
| **Exclusion Tables** | `pipeline/sql/create_excluded_firms_table.sql` | ✅ Production | Centralized firm exclusions |
| **Core Documentation** | `README.md`, `Lead_Scoring_Methodology_Final.md` | ✅ Production | Essential reference docs |

### Deprecated Assets (ARCHIVE/REMOVE)

| Component | Location | Reason | Action |
|-----------|----------|--------|--------|
| **V4.0.0 Model** | `v4/models/v4.0.0/` | Superseded by V4.1.0 R3 | Archive |
| **V4.1.0 R1/R2** | `v4/models/v4.1.0_r2/` | Superseded by R3 | Archive |
| **V3.2.1 SQL** | `v3/sql/generate_lead_list_v3.2.1.sql` | Superseded by V3.3.0 | Archive |
| **Old Execution Logs** | Multiple `EXECUTION_LOG*.md` files | Historical only | Archive |
| **Phase Development Scripts** | `v3/scripts/run_phase_*.py` | One-time training | Archive |
| **V4 Training Scripts** | `v4/scripts/v4.1/phase_*.py` | One-time training | Archive |
| **Redundant Docs** | Multiple guide duplicates | Consolidated in README | Remove |
| **Test/Backup Files** | `*.bak`, `test_*.sql` | Temporary files | Remove |
| **SHAP Fix Scripts** | Multiple `fix_*.py` files | One-time fixes | Archive |

---

## Detailed File-by-File Recommendations

### 1. Root Directory

#### KEEP ✅
- `README.md` - Main documentation (update structure references)
- `Lead_Scoring_Methodology_Final.md` - Core methodology document
- `recommended_cleanup.md` - This document

#### ARCHIVE 📦
- `bleeding_exploration.md` + `bleeding_exploration_cursor_prompt.md` - Historical analysis
- `final_bleed_analysis.md` + `final_bleed_analysis_cursor_prompt.md` - Historical analysis
- `v3_to_v3.3_update_guide.md` - Historical upgrade guide
- `Update_V41_Guide_Cursor_Prompt.md` - Historical upgrade guide
- `V4_1_R3_Simulation_Backtest.md` - Historical backtest framework
- `V4.1_R3_Pipeline_Integration_Cursor_Guide.md` - Historical integration guide

#### REMOVE ❌
- `series_65_ria_advisors_with_salesforce.sql` - Appears to be a one-off query

---

### 2. v3/ Directory

#### KEEP ✅
```
v3/
├── sql/
│   ├── generate_lead_list_v3.3.0.sql  # Production SQL (OR v3.2.1 if rename not done - verify first)
│   ├── phase_4_v3_tiered_scoring.sql  # Core tier logic
│   ├── phase_7_production_view.sql    # Production view
│   ├── lead_scoring_features_pit.sql  # ⚠️ CRITICAL - Feature engineering (feeds V3 tier logic)
│   ├── phase_7_salesforce_sync.sql    # ⚠️ CRITICAL - Production Salesforce sync
│   └── phase_7_sga_dashboard.sql      # ⚠️ CRITICAL - Production dashboard view
├── models/
│   └── model_registry_v3.json         # Model registry
├── VERSION_3_MODEL_REPORT.md          # Model documentation
├── PRODUCTION_MODEL_UPDATE_CHECKLIST.md  # ⚠️ KEEP - needed for ongoing production updates
└── docs/
    └── LEAD_LIST_GENERATION_GUIDE.md  # User guide
```

#### ARCHIVE 📦
```
v3/
├── sql/
│   ├── generate_lead_list_v3.2.1.sql  # Old version
│   ├── generate_lead_list_v3.2.1.sql.bak
│   ├── test_v3.3_*.sql                # Test files
│   └── v3.3_verification_results.md
├── scripts/
│   ├── run_phase_4.py                  # One-time training
│   ├── run_phase_7.py                  # One-time training
│   ├── run_backtest_v3.py              # Historical backtest
│   ├── backtest_v3.py
│   └── compile_backtest_results.py
├── reports/
│   ├── v3_backtest_summary.md
│   └── v3.2_validation_results.md
├── data/                               # Historical data
├── EXECUTION_LOG.md                    # Historical log
├── January_2026_Lead_List_Query_V3.2.sql  # Old version
├── January_2026_Lead_List_Query_V3.2.sql.bak
├── January_2026_Lead_List_Query_V3.3.sql  # Duplicate (in pipeline/)
└── V3_Lead_Scoring_Model_Complete_Guide.md  # Superseded by VERSION_3_MODEL_REPORT.md
```
```

#### REMOVE ❌
- `v3/utils/` - Utility functions not used in production
- `v3/date_config.json` - Configuration file (if not used)

---

### 3. v4/ Directory

#### KEEP ✅
```
v4/
├── models/
│   ├── registry.json                   # Model registry
│   └── v4.1.0_r3/                      # Production model
│       ├── model.pkl
│       ├── model.json
│       ├── feature_importance.csv
│       ├── hyperparameters.json
│       ├── training_metrics.json
│       └── removed_features.json
├── data/
│   └── v4.1.0_r3/
│       └── final_features.json        # Production features
├── sql/
│   ├── v4.1/
│   │   ├── create_recent_movers_table.sql
│   │   ├── create_bleeding_velocity_table.sql
│   │   ├── create_firm_rep_type_features.sql
│   │   └── phase_2_feature_engineering_v41.sql
│   └── production_scoring_v41.sql
├── inference/
│   └── lead_scorer_v4.py              # Production inference
├── VERSION_4_MODEL_REPORT.md          # Model documentation
└── reports/
    └── v4.1/
        ├── V4.1_Final_Summary.md
        ├── model_validation_report_r3.md
        ├── shap_summary_r3.png
        └── shap_bar_r3.png
```

#### ARCHIVE 📦
```
v4/
├── models/
│   ├── v4.0.0/                         # Deprecated model
│   ├── v4.1.0/                         # Superseded by R3
│   └── v4.1.0_r2/                      # Superseded by R3
├── data/
│   ├── processed/                      # Old processed data
│   ├── v4.1.0/                         # Old version data
│   └── v4.1.0_r2/                      # Old version data
├── scripts/
│   ├── v4.1/
│   │   ├── phase_3_export_data.py      # One-time training
│   │   ├── phase_4_pit_audit.py        # One-time training
│   │   ├── phase_5_multicollinearity_v41.py
│   │   ├── phase_7_model_training_v41*.py  # Training scripts
│   │   ├── phase_8_overfitting_check_v41*.py
│   │   ├── phase_9_validation_v41_r3.py
│   │   ├── phase_10_shap_analysis_v41*.py  # Multiple SHAP attempts
│   │   ├── phase_10_shap_fix.py
│   │   ├── test_monthly_scoring_v41.py
│   │   ├── verify_salesforce_fields.py
│   │   ├── score_and_sync_v41.py
│   │   └── salesforce_sync_v41.py
│   ├── phase_2_feature_engineering.py
│   ├── phase_6_model_training.py
│   ├── phase_10_deployment.py
│   └── verify_final_features.py
├── sql/
│   ├── phase_1_target_definition.sql   # Old phase SQL
│   ├── phase_2_feature_engineering.sql
│   └── production_scoring.sql          # ⚠️ V4.0 version - ARCHIVE (superseded by production_scoring_v41.sql)
├── reports/
│   ├── deprioritization_analysis.md
│   ├── validation_report.md
│   ├── shap_analysis_report.md
│   └── v4.1/
│       ├── overfitting_report*.md     # Multiple versions
│       ├── overfitting_results*.json
│       ├── multicollinearity_report.md
│       ├── multicollinearity_results.json
│       ├── pit_audit_report.md
│       ├── pit_audit_results.json
│       └── pit_audit_spot_check.csv
├── config/                             # Old config files
├── EXECUTION_LOG*.md                   # Historical logs
├── DEPLOYMENT_*.md                     # Historical deployment docs
├── DEPLOYMENT_EXECUTION.md
├── DEPLOYMENT_PREPARATION_V4.1_R3.md
├── DEPLOYMENT_READINESS_SUMMARY.md
├── SHAP_Investigation.md
├── V4_1_Retraining_Cursor_Guide.md    # Historical guide
├── XGBoost_ML_Lead_Scoring_V4_Development_Plan.md
└── README.md                           # Duplicate (main README exists)
```

#### REMOVE ❌
- `v4/v4/` - Appears to be a duplicate nested directory
- `v4/data/v4.1.0/` - Old version data (keep only R3)

---

### 4. pipeline/ Directory

#### KEEP ✅
```
pipeline/
├── sql/
│   ├── January_2026_Lead_List_V3_V4_Hybrid.sql  # Production: Monthly lead list
│   ├── v4_prospect_features.sql                 # Production: V4.1 feature calculation
│   ├── create_excluded_firms_table.sql           # Production: Pattern exclusions
│   ├── create_excluded_firm_crds_table.sql       # Production: CRD exclusions
│   ├── manage_excluded_firms.sql                 # Production: Exclusion management
│   └── recycling/
│       └── recyclable_pool_master_v2.1.sql       # Production: Recyclable leads
├── scripts/
│   ├── score_prospects_monthly.py                # Production: Monthly ML scoring
│   ├── execute_january_lead_list.py              # Production: Lead list execution
│   └── export_lead_list.py                       # Production: CSV export
└── Monthly_Lead_List_Generation_V3_V4_Hybrid.md  # User guide: Primary pipeline
```

#### 4.1 Recyclable Lead Pipeline (KEEP - Production)

**Status**: ✅ Production system for monthly recyclable lead generation

**Production Files**:
```
pipeline/
├── sql/
│   └── recycling/
│       └── recyclable_pool_master_v2.1.sql  # Production SQL
└── Monthly_Recyclable_Lead_List_Generation_Guide_V2.md  # User guide
```

**Key Logic (V2 - Corrected)**:
- **EXCLUDE** people who changed firms < 2 years ago (just settled in)
- **INCLUDE** people who changed firms 2-3 years ago (may be restless)
- **HIGHEST PRIORITY**: High V4 score + long tenure + no recent move
- **P1 Priority**: "Timing" disposition + 6-12 months passed (7% expected conversion)

**Monthly Output**:
- Target: 600 recyclable leads
- Output: `exports/{month}_{year}_recyclable_leads.csv`
- Report: `reports/recycling_analysis/{month}_{year}_recyclable_list_report.md`

**Note**: This is a separate production pipeline from the primary monthly lead list. Both run monthly.

#### 4.2 Firm Exclusions System (KEEP - Production)

**Status**: ✅ Production-critical centralized exclusion system

**Production Files**:
```
pipeline/
├── sql/
│   ├── create_excluded_firms_table.sql      # Pattern-based exclusions
│   ├── create_excluded_firm_crds_table.sql  # CRD-based exclusions
│   └── manage_excluded_firms.sql            # Management queries
└── sql/
    └── CENTRALIZED_EXCLUSIONS_SUMMARY.md    # Documentation
```

**BigQuery Tables**:
- `ml_features.excluded_firms` - 42 pattern-based exclusions
- `ml_features.excluded_firm_crds` - 2 CRD-based exclusions

**Documentation**: See `docs/FIRM_EXCLUSIONS_GUIDE.md` (to be created in Phase 2)

#### ARCHIVE 📦
```
pipeline/
├── sql/
│   ├── ADDITIONAL_EXCLUSIONS_FIX.md
│   ├── CENTRALIZED_EXCLUSIONS_SUMMARY.md
│   ├── DATA_QUALITY_VERIFICATION.md
│   ├── DUPLICATE_FIX_RESULTS.md
│   ├── EXECUTE_JANUARY_2026_LEAD_LIST.md
│   ├── JANUARY_2026_LEAD_LIST_EXECUTION_RESULTS.md
│   ├── PRUCO_EXCLUSION_FIX.md
│   ├── READY_TO_EXECUTE.md
│   ├── SHAP_NARRATIVE_UPDATE_RESULTS.md
│   ├── TIER_DISTRIBUTION_FIX_SUMMARY.md
│   ├── cleanup_old_january_tables.sql
│   ├── create_excluded_v3_v4_disagreement_table.sql
│   ├── generate_january_2026_lead_list.sql
│   └── recycling/
│       └── recyclable_pool_master_v2.1.sql
├── scripts/
│   ├── analyze_v4_percentile_distribution.py
│   ├── calculate_expected_conversion_rate.py
│   ├── check_alpha_zero.py
│   ├── check_shap_status.py
│   ├── execute_v4_features.py
│   ├── fix_model_base_score.py
│   ├── fix_model_for_shap.py
│   ├── fix_model_json_base_score.py
│   ├── run_lead_list_sql.py
│   ├── test_shap_with_fixed_model.py
│   ├── v41_backtest_simulation.py
│   ├── validate_partner_founder_grouping.py
│   └── verify_shap_diversity.py
├── logs/
│   ├── EXECUTION_LOG.md
│   └── V4.1_INTEGRATION_LOG.md
├── reports/
│   └── V4.1_Backtest_Results.md
├── Create_Excluded_Firms_Table_Cursor_Prompt.md
├── January_2026_Lead_List_Final_Upgrades_Guide.md
├── Monthly_Recyclable_Lead_List_Generation_Guide_V2.md
├── PARTNER_FOUNDER_SGA_ASSIGNMENT.md
├── SGA_ASSIGNMENT_FEATURE.md
├── SHAP_BASE_SCORE_ISSUE.md
├── SHAP_BUG_FIX.md
├── SHAP_HOMOGENEITY_FIX.md
└── V3_V4_DISAGREEMENT_FILTER.md
```

#### REMOVE ❌
- `pipeline/exports/*.csv` - Old export files (regenerate as needed)
- `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` - Duplicate (keep root version)

---

### 5. docs/ Directory (CRITICAL - Preserve)

#### KEEP ✅ (Critical Reference Documentation)
```
docs/
├── FINTRX_Data_Dictionary.md        # Field-level documentation for all 25 FINTRX tables
├── FINTRX_Architecture_Overview.md  # Dataset architecture and PIT limitations
├── FINTRX_Lead_Scoring_Features.md  # Feature engineering documentation
├── How_To_Get_Scores_For_CRD_List.md  # Utility guide
├── SAVVY_PIRATE_DATA_GUIDE.md      # Data access guide
└── FIRM_EXCLUSIONS_GUIDE.md         # Firm exclusion system (NEW - to be created)
```

#### Why These Are Critical
- **Data Dictionary**: Essential for any new feature engineering
- **Architecture Overview**: Documents PIT limitations (what CAN'T be done)
- **Lead Scoring Features**: Maps features to source tables
- **Firm Exclusions**: Production-critical exclusion logic

#### DO NOT ARCHIVE
These documents represent months of data exploration and are essential for:
- Onboarding new team members
- Future model development
- Debugging data issues
- Understanding FINTRX data structure

---

### 6. validation/ Directory

#### KEEP ✅
```
validation/
├── LEAD_SCORING_KEY_FINDINGS.md              # Critical validation findings
├── mobility_and_stability_and_conversion.md   # Key insights
└── backtest_optimized_january_list.py        # Backtest validation script (may be reused)
```

#### ARCHIVE 📦
- `january-lead-list-conversion-estimate.*` - Historical estimates
- `lead_list_optimization_analysis.*` - Historical analysis
- `v4_upgrade_impact_analysis.json` - Historical analysis

---

### 7. archive/ Directory

#### KEEP ✅
- Keep existing archive structure - this is where we'll move deprecated files

---

## PHASE 0: Pre-Cleanup Audit (NEW)

### 0.1 Complete File Inventory

**Action**: Create comprehensive inventory of all files before cleanup begins.

**Deliverable**: `cleanup/pre_cleanup_inventory.md`

**Contents**:
- Total file count by extension (.md, .sql, .py, .json, .pkl, etc.)
- Total file count by directory
- File size summary
- Complete file listing (recursive)

**Purpose**: 
- "Before" snapshot for validation
- Ensures nothing is lost during cleanup
- Reference for rollback if needed

**Timeline**: 30 minutes  
**Risk**: None

---

### 0.2 BigQuery Table Inventory

**Action**: Inventory all BigQuery tables in `ml_features` dataset.

**Deliverable**: `cleanup/bigquery_table_inventory.md`

**Query**:
```sql
SELECT 
    table_name,
    ROUND(size_bytes / 1024 / 1024, 2) as size_mb,
    row_count,
    creation_time,
    CASE 
        WHEN table_name LIKE '%v4.0%' THEN 'DEPRECATED'
        WHEN table_name LIKE '%v4.1.0%' AND table_name NOT LIKE '%r3%' THEN 'DEPRECATED'
        WHEN table_name LIKE '%old%' OR table_name LIKE '%backup%' THEN 'DEPRECATED'
        WHEN table_name LIKE '%test%' THEN 'TEST'
        ELSE 'ACTIVE'
    END as status
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
ORDER BY creation_time DESC;
```

**Purpose**:
- Identify tables for KEEP (production)
- Identify tables for ARCHIVE (historical reference)
- Identify tables for DELETE (deprecated/test)

**Timeline**: 30 minutes  
**Risk**: None

**See Also**: `cleanup/BIGQUERY_CLEANUP_PLAN.md` (to be created in Phase 4)

---

## Additional Sections (Added During Enhancement)

### 8. BigQuery Cleanup

**Status**: ⚠️ **CRITICAL** - Deprecated tables consuming resources

**Deliverable**: `cleanup/BIGQUERY_CLEANUP_PLAN.md`

**Tables to DELETE**:
- `january_2026_lead_list_v4` (replaced by hybrid list)
- `january_2026_excluded_v3_v4_disagreement` (temporary analysis)
- `*_test_*` tables
- `*_backup_*` tables
- `*_old_*` tables

**Tables to ARCHIVE**:
- `lead_scores_v3_1_*` (superseded by V3.2)
- `v4_prospect_features_v40` (superseded by V4.1)

**Tables to KEEP**:
- `ml_features.lead_scores_v3` (V3 production)
- `ml_features.v4_prospect_features` (V4.1 features)
- `ml_features.v4_prospect_scores` (V4.1 scores)
- `ml_features.january_2026_lead_list` (current lead list)
- `ml_features.excluded_firms` (pattern exclusions)
- `ml_features.excluded_firm_crds` (CRD exclusions)

**See**: Phase 3.5 for detailed cleanup plan

---

### 9. Future Development Structure

**New Directory**: `predictive_movement/`

**Purpose**: Predictive RIA Advisor Movement Model (correlates movement with economic metrics)

**Status**: Planning / Development placeholder

**Structure**:
```
predictive_movement/
├── README.md                    # Overview, hypotheses, data sources
├── docs/
│   └── MODEL_DESIGN.md          # Detailed model design (TBD)
└── [placeholder directories]
```

**See**: Phase 4.5 for structure creation

---

### 10. Unified Model Registry

**New File**: `models/UNIFIED_MODEL_REGISTRY.json`

**Purpose**: Consolidated registry referencing both V3 and V4 registries

**Structure**:
```json
{
  "production_models": {
    "prioritization": { "model": "v3.3", "registry": "v3/models/model_registry_v3.json" },
    "deprioritization": { "model": "v4.1.0_r3", "registry": "v4/models/registry.json" }
  },
  "hybrid_pipeline": { "location": "pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql" },
  "deprecated_models": [...]
}
```

**Note**: Individual registries (v3/v4) are kept but referenced by unified registry

**See**: Phase 3 for consolidation

---

### 11. Salesforce Integration Documentation

**Status**: ⚠️ **MISSING** - Production-critical but not documented

**Action Required**: Document Salesforce sync process

**Files to Review**:
- `v4/scripts/v4.1/score_and_sync_v41.py`
- `v4/scripts/v4.1/salesforce_sync_v41.py`
- `v4/scripts/v4.1/verify_salesforce_fields.py`
- `v4/sql/v4.1/salesforce_sync_v41.sql`

**Deliverable**: `docs/SALESFORCE_INTEGRATION_GUIDE.md` (to be created)

---

## Proposed Clean Repository Structure

```
lead_scoring_production/
├── README.md                           # Main documentation
├── Lead_Scoring_Methodology_Final.md    # Core methodology
├── MODEL_EVOLUTION_HISTORY.md          # NEW: Historical lessons learned
├── recommended_cleanup.md              # This document
│
├── v3/                                 # V3.3 Rules-Based Model
│   ├── sql/
│   │   ├── generate_lead_list_v3.3.0.sql
│   │   ├── phase_4_v3_tiered_scoring.sql
│   │   └── phase_7_production_view.sql
│   ├── models/
│   │   └── model_registry_v3.json
│   ├── docs/
│   │   └── LEAD_LIST_GENERATION_GUIDE.md
│   └── VERSION_3_MODEL_REPORT.md
│
├── v4/                                 # V4.1.0 R3 XGBoost Model
│   ├── models/
│   │   ├── registry.json
│   │   └── v4.1.0_r3/                  # Production model only
│   ├── data/
│   │   └── v4.1.0_r3/
│   │       └── final_features.json
│   ├── sql/
│   │   ├── v4.1/
│   │   │   ├── create_recent_movers_table.sql
│   │   │   ├── create_bleeding_velocity_table.sql
│   │   │   ├── create_firm_rep_type_features.sql
│   │   │   └── phase_2_feature_engineering_v41.sql
│   │   └── production_scoring_v41.sql
│   ├── inference/
│   │   └── lead_scorer_v4.py
│   ├── reports/
│   │   └── v4.1/
│   │       ├── V4.1_Final_Summary.md
│   │       ├── model_validation_report_r3.md
│   │       ├── shap_summary_r3.png
│   │       └── shap_bar_r3.png
│   └── VERSION_4_MODEL_REPORT.md
│
├── pipeline/                           # Monthly Operations
│   ├── sql/
│   │   ├── January_2026_Lead_List_V3_V4_Hybrid.sql
│   │   ├── v4_prospect_features.sql
│   │   ├── create_excluded_firms_table.sql
│   │   ├── create_excluded_firm_crds_table.sql
│   │   └── manage_excluded_firms.sql
│   ├── scripts/
│   │   ├── score_prospects_monthly.py
│   │   ├── execute_january_lead_list.py
│   │   └── export_lead_list.py
│   └── Monthly_Lead_List_Generation_V3_V4_Hybrid.md
│
├── docs/                               # Core Documentation
│   ├── FINTRX_Architecture_Overview.md
│   ├── FINTRX_Data_Dictionary.md
│   ├── FINTRX_Lead_Scoring_Features.md
│   ├── How_To_Get_Scores_For_CRD_List.md
│   ├── SAVVY_PIRATE_DATA_GUIDE.md
│   ├── FIRM_EXCLUSIONS_GUIDE.md      # NEW: Exclusion system
│   ├── RECYCLABLE_LEADS_GUIDE.md      # NEW: Recyclable pipeline
│   └── SALESFORCE_INTEGRATION_GUIDE.md # NEW: Salesforce sync
│
├── validation/                         # Key Validation Findings
│   ├── LEAD_SCORING_KEY_FINDINGS.md
│   ├── mobility_and_stability_and_conversion.md
│   └── backtest_optimized_january_list.py  # Validation script
│
├── models/                             # NEW: Unified Model Registry
│   └── UNIFIED_MODEL_REGISTRY.json     # References v3 and v4 registries
│
├── predictive_movement/                # NEW: Future Development
│   ├── README.md
│   ├── docs/
│   │   └── MODEL_DESIGN.md
│   └── [placeholder directories]
│
├── cleanup/                            # NEW: Cleanup Documentation
│   ├── pre_cleanup_inventory.md
│   ├── bigquery_table_inventory.md
│   └── BIGQUERY_CLEANUP_PLAN.md
│
└── archive/                            # Historical Reference
    ├── v3_development/
    │   ├── scripts/                    # All phase scripts
    │   ├── reports/                    # Historical reports
    │   ├── data/                       # Historical data
    │   └── execution_logs/             # Historical logs
    ├── v4_development/
    │   ├── models/                     # v4.0.0, v4.1.0, v4.1.0_r2
    │   ├── scripts/                    # All training scripts
    │   ├── reports/                    # Historical reports
    │   ├── data/                       # Historical data
    │   └── execution_logs/             # Historical logs
    ├── pipeline_development/
    │   ├── integration_guides/         # Historical guides
    │   ├── fix_documentation/         # Historical fixes
    │   └── execution_logs/            # Historical logs
    └── root_analysis/
        ├── bleeding_exploration/
        ├── final_bleed_analysis/
        └── upgrade_guides/
```

---

## Enhanced Phased Cleanup Plan

### Phase 0: Pre-Cleanup Audit (NEW)

**Action**: Complete file and BigQuery table inventory before cleanup begins.

**Deliverables**:
- `cleanup/pre_cleanup_inventory.md` - Complete file inventory
- `cleanup/bigquery_table_inventory.md` - BigQuery table inventory

**Timeline**: 1 hour  
**Risk**: None

**See**: Phase 0.1 and 0.2 above for details

---

### Phase 0.5: Pre-Flight Verification (CRITICAL - DO FIRST)

**Action**: Verify all production-critical files exist before any cleanup operations.

**Purpose**: Prevent accidental archiving of production files by confirming they exist first.

**Required Files Checklist**:

**V3 Production Files**:
- [ ] `v3/sql/generate_lead_list_v3.3.0.sql` OR `v3/sql/generate_lead_list_v3.2.1.sql` (verify which exists)
- [ ] `v3/sql/phase_4_v3_tiered_scoring.sql`
- [ ] `v3/sql/lead_scoring_features_pit.sql` ⚠️ CRITICAL
- [ ] `v3/sql/phase_7_production_view.sql`
- [ ] `v3/sql/phase_7_salesforce_sync.sql` ⚠️ CRITICAL
- [ ] `v3/sql/phase_7_sga_dashboard.sql` ⚠️ CRITICAL
- [ ] `v3/models/model_registry_v3.json`
- [ ] `v3/VERSION_3_MODEL_REPORT.md`
- [ ] `v3/PRODUCTION_MODEL_UPDATE_CHECKLIST.md` ⚠️ CRITICAL

**V4 Production Files**:
- [ ] `v4/models/v4.1.0_r3/model.pkl`
- [ ] `v4/models/v4.1.0_r3/model.json`
- [ ] `v4/models/registry.json`
- [ ] `v4/data/v4.1.0_r3/final_features.json`
- [ ] `v4/sql/production_scoring_v41.sql` (NOT production_scoring.sql)
- [ ] `v4/inference/lead_scorer_v4.py`

**Pipeline Production Files**:
- [ ] `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
- [ ] `pipeline/sql/v4_prospect_features.sql`
- [ ] `pipeline/sql/create_excluded_firms_table.sql`
- [ ] `pipeline/sql/create_excluded_firm_crds_table.sql`
- [ ] `pipeline/scripts/score_prospects_monthly.py`
- [ ] `pipeline/scripts/execute_january_lead_list.py`
- [ ] `pipeline/scripts/export_lead_list.py`
- [ ] `pipeline/sql/recycling/recyclable_pool_master_v2.1.sql`

**Documentation**:
- [ ] `docs/FINTRX_Data_Dictionary.md`
- [ ] `docs/FINTRX_Architecture_Overview.md`
- [ ] `docs/FINTRX_Lead_Scoring_Features.md`
- [ ] `README.md`
- [ ] `Lead_Scoring_Methodology_Final.md`

**Verification Command** (PowerShell):
```powershell
# Verify critical production files exist
$critical_files = @(
    "v3/sql/phase_4_v3_tiered_scoring.sql",
    "v3/sql/lead_scoring_features_pit.sql",
    "v3/sql/phase_7_salesforce_sync.sql",
    "v3/sql/phase_7_sga_dashboard.sql",
    "v3/models/model_registry_v3.json",
    "v4/models/v4.1.0_r3/model.pkl",
    "v4/inference/lead_scorer_v4.py",
    "pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql",
    "pipeline/sql/v4_prospect_features.sql"
)

foreach ($file in $critical_files) {
    if (Test-Path $file) {
        Write-Host "✅ $file" -ForegroundColor Green
    } else {
        Write-Host "❌ MISSING: $file" -ForegroundColor Red
    }
}

# Verify V3 production SQL (check both possible names)
if (Test-Path "v3/sql/generate_lead_list_v3.3.0.sql") {
    Write-Host "✅ v3/sql/generate_lead_list_v3.3.0.sql exists" -ForegroundColor Green
} elseif (Test-Path "v3/sql/generate_lead_list_v3.2.1.sql") {
    Write-Host "⚠️  v3/sql/generate_lead_list_v3.2.1.sql exists (v3.3.0 rename may not be done)" -ForegroundColor Yellow
} else {
    Write-Host "❌ MISSING: V3 production SQL file" -ForegroundColor Red
}

# Verify V4 production SQL (should be v41, not v4.0)
if (Test-Path "v4/sql/production_scoring_v41.sql") {
    Write-Host "✅ v4/sql/production_scoring_v41.sql exists" -ForegroundColor Green
} else {
    Write-Host "❌ MISSING: v4/sql/production_scoring_v41.sql" -ForegroundColor Red
}

if (Test-Path "v4/sql/production_scoring.sql") {
    Write-Host "⚠️  v4/sql/production_scoring.sql exists (V4.0 - should be archived)" -ForegroundColor Yellow
}
```

**Verification Command** (Bash/Linux):
```bash
# Verify critical production files exist
for file in \
  "v3/sql/phase_4_v3_tiered_scoring.sql" \
  "v3/sql/lead_scoring_features_pit.sql" \
  "v3/sql/phase_7_salesforce_sync.sql" \
  "v3/sql/phase_7_sga_dashboard.sql" \
  "v3/models/model_registry_v3.json" \
  "v4/models/v4.1.0_r3/model.pkl" \
  "v4/inference/lead_scorer_v4.py" \
  "pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql" \
  "pipeline/sql/v4_prospect_features.sql"; do
  if [ -f "$file" ]; then
    echo "✅ $file"
  else
    echo "❌ MISSING: $file"
  fi
done

# Verify V3 production SQL (check both possible names)
if [ -f "v3/sql/generate_lead_list_v3.3.0.sql" ]; then
  echo "✅ v3/sql/generate_lead_list_v3.3.0.sql exists"
elif [ -f "v3/sql/generate_lead_list_v3.2.1.sql" ]; then
  echo "⚠️  v3/sql/generate_lead_list_v3.2.1.sql exists (v3.3.0 rename may not be done)"
else
  echo "❌ MISSING: V3 production SQL file"
fi

# Verify V4 production SQL (should be v41, not v4.0)
if [ -f "v4/sql/production_scoring_v41.sql" ]; then
  echo "✅ v4/sql/production_scoring_v41.sql exists"
else
  echo "❌ MISSING: v4/sql/production_scoring_v41.sql"
fi

if [ -f "v4/sql/production_scoring.sql" ]; then
  echo "⚠️  v4/sql/production_scoring.sql exists (V4.0 - should be archived)"
fi
```

**Action if Files Missing**:
- **STOP** cleanup process
- Investigate missing files
- Verify if files were moved or renamed
- Update cleanup plan with correct paths
- **DO NOT PROCEED** until all critical files are verified

**Timeline**: 15-30 minutes  
**Risk**: None (verification only)  
**Priority**: **CRITICAL** - Must complete before Phase 1

---

### Phase 1: Create Historical Documentation (NO RISK)

**Action**: Create comprehensive `MODEL_EVOLUTION_HISTORY.md` documenting:
- V1 → V2 → V3 → V4 → V4.1 evolution (complete timeline)
- Key lessons learned (data leakage, overfitting, feature selection, SHAP issues)
- Why each version was superseded
- Critical insights that led to current hybrid approach
- Technical decisions registry
- Feature engineering insights
- SHAP analysis journey (TreeExplainer → KernelExplainer)
- Data leakage prevention rules
- Archived files reference guide

**Deliverable**: `MODEL_EVOLUTION_HISTORY.md` (comprehensive institutional knowledge document)

**Template Sections**:
1. Executive Summary
2. Version Timeline
3. V1: Initial Attempt
4. V2: First ML Model (Data Leakage Disaster)
5. V3: Rules-Based Success
6. V4: ML Redemption
7. Hybrid Strategy
8. Key Lessons Learned
9. Technical Decisions Registry
10. Feature Engineering Insights
11. Data Leakage Prevention
12. SHAP Analysis Journey
13. Archived Files Reference

**Timeline**: 2-3 hours  
**Risk**: None (additive only)

**See**: `cleanup_enhancement_cursor_prompt.md` Prompt 1.1 for detailed template

---

### Phase 1.5: Document Missing Pipeline Components (NO RISK)

**Action**: Create documentation for production systems not yet fully documented:
1. **Recyclable Lead Pipeline**: Document in `docs/RECYCLABLE_LEADS_GUIDE.md`
2. **Firm Exclusions System**: Create `docs/FIRM_EXCLUSIONS_GUIDE.md`
3. **Salesforce Integration**: Document sync scripts and process

**Timeline**: 1 hour  
**Risk**: None

---

### Phase 2: Archive Deprecated Files (LOW RISK)

**Action**: Move (don't delete) deprecated files to `archive/` directory:
1. Create archive subdirectories
2. Move deprecated model versions
3. Move historical scripts and logs
4. Move redundant documentation

**Timeline**: 2-3 hours  
**Risk**: Low (files preserved, can restore if needed)

**Commands**:
```bash
# Create archive structure
mkdir -p archive/v3_development/{scripts,reports,data,execution_logs}
mkdir -p archive/v4_development/{models,scripts,reports,data,execution_logs}
mkdir -p archive/pipeline_development/{integration_guides,fix_documentation,execution_logs}
mkdir -p archive/root_analysis/{bleeding_exploration,final_bleed_analysis,upgrade_guides}

# Move deprecated V3 files
mv v3/scripts/run_phase_*.py archive/v3_development/scripts/
mv v3/reports/* archive/v3_development/reports/
mv v3/data/* archive/v3_development/data/
mv v3/EXECUTION_LOG.md archive/v3_development/execution_logs/

# Move deprecated V4 files
mv v4/models/v4.0.0 archive/v4_development/models/
mv v4/models/v4.1.0 archive/v4_development/models/
mv v4/models/v4.1.0_r2 archive/v4_development/models/
mv v4/scripts/v4.1/phase_*.py archive/v4_development/scripts/
mv v4/EXECUTION_LOG*.md archive/v4_development/execution_logs/

# Move root analysis files
mv bleeding_exploration*.md archive/root_analysis/bleeding_exploration/
mv final_bleed_analysis*.md archive/root_analysis/final_bleed_analysis/
mv *update_guide*.md archive/root_analysis/upgrade_guides/
```

---

### Phase 3: Consolidate Documentation (LOW RISK)

**Action**: 
1. Review and merge redundant documentation
2. Update README.md with new structure
3. Remove duplicate files
4. Update all file references
5. Preserve Quick Start guides (user-facing documentation)
6. Consolidate model registries (create unified registry)

**Timeline**: 2-3 hours  
**Risk**: Low (documentation only)

**Key Consolidations**:
- Merge `V3_Lead_Scoring_Model_Complete_Guide.md` into `VERSION_3_MODEL_REPORT.md`
- Remove duplicate `v4/README.md` (main README exists)
- Consolidate pipeline guides into single `Monthly_Lead_List_Generation_V3_V4_Hybrid.md`
- Preserve `v3/docs/QUICK_START_LEAD_LISTS.md` and `v3/docs/LEAD_LIST_GENERATION_GUIDE.md`
- Create unified model registry: `models/UNIFIED_MODEL_REGISTRY.json` (references v3 and v4 registries)

---

### Phase 3.5: BigQuery Cleanup Plan (NO RISK)

**Action**: Create BigQuery table cleanup documentation.

**Deliverable**: `cleanup/BIGQUERY_CLEANUP_PLAN.md`

**Contents**:
- Tables to KEEP (production)
- Tables to ARCHIVE (historical reference)
- Tables to DELETE (deprecated/test)
- Cleanup SQL (with validation queries)
- Validation before cleanup checklist

**Timeline**: 30 minutes  
**Risk**: None (documentation only)

**Note**: Execute BigQuery cleanup AFTER file cleanup is validated (Phase 5+)

---

### Phase 4: Remove Temporary Files (MEDIUM RISK)

**Action**: Delete clearly temporary files:
- `*.bak` backup files
- `test_*.sql` test queries
- Old CSV exports (regenerate as needed)
- One-time fix scripts (documented in MODEL_EVOLUTION_HISTORY.md)

**Timeline**: 1 hour  
**Risk**: Medium (ensure backups exist)

**Files to Remove**:
```
v3/sql/*.bak
v3/sql/test_*.sql
pipeline/exports/*.csv  # (regenerate as needed)
pipeline/scripts/fix_*.py
pipeline/scripts/test_*.py
```

---

### Phase 4.5: Future Development Structure (NO RISK)

**Action**: Create placeholder structure for Predictive RIA Movement Model.

**Deliverable**: `predictive_movement/` directory structure

**Structure**:
```
predictive_movement/
├── README.md                    # Overview and hypotheses
├── docs/
│   └── MODEL_DESIGN.md          # Detailed model design (TBD)
├── data/
│   └── .gitkeep
├── sql/
│   └── .gitkeep
├── scripts/
│   └── .gitkeep
└── models/
    └── .gitkeep
```

**Purpose**: 
- Placeholder for future development
- Documents planned approach
- Preserves hypotheses and data sources

**Timeline**: 30 minutes  
**Risk**: None

---

### Phase 4.5: Future Development Structure (NO RISK) ✅ COMPLETE

**Action**: Create placeholder structure for Predictive RIA Movement Model.

**Deliverable**: `predictive_movement/` directory structure

**Status**: ✅ Complete

**Created Files**:
- `predictive_movement/README.md` - Overview, hypotheses, data sources, planned approach
- `predictive_movement/docs/MODEL_DESIGN.md` - Detailed model design (target variable, features, architecture)
- `predictive_movement/data/.gitkeep` - Placeholder for data files
- `predictive_movement/sql/.gitkeep` - Placeholder for SQL queries
- `predictive_movement/scripts/.gitkeep` - Placeholder for Python scripts
- `predictive_movement/models/.gitkeep` - Placeholder for model artifacts

**Purpose**: 
- Placeholder for future development
- Documents planned approach
- Preserves hypotheses and data sources

**Timeline**: 30 minutes  
**Risk**: None

---

### Phase 5: Validation & Final Cleanup (MEDIUM RISK)

**Action**:
1. Run full pipeline validation
2. Verify all production scripts work
3. Update .gitignore if needed
4. Final commit with cleanup summary

**Timeline**: 2-3 hours  
**Risk**: Medium (ensure production pipeline still works)

**Validation Checklist**:
- [ ] V3.3 SQL generates lead list correctly
- [ ] V4.1.0 R3 model loads and scores correctly
- [ ] Hybrid pipeline generates final lead list
- [ ] All production scripts execute without errors
- [ ] README.md references are correct
- [ ] No broken file links

---

## Estimated Impact

### Before Cleanup
- **Total Files**: ~200+ files
- **Repository Size**: ~50-100 MB (with data files)
- **Documentation Files**: 70+ markdown files
- **Python Scripts**: 50+ scripts
- **SQL Files**: 36 files

### After Cleanup (Enhanced)
- **Production Files**: ~50 files (including docs, validation, new structure)
- **Archive Files**: ~100-150 files (moved, not deleted)
- **Documentation Files**: ~20-25 essential files (including new guides)
- **New Documentation**: ~5-10 files (MODEL_EVOLUTION_HISTORY.md, guides, cleanup docs)
- **Repository Size**: ~20-30 MB (production only)

### Benefits
1. ✅ **Clarity**: Clear separation of production vs. historical
2. ✅ **Maintainability**: Easier to find production code
3. ✅ **Onboarding**: New team members can focus on production
4. ✅ **Knowledge Preservation**: Historical lessons documented
5. ✅ **Reduced Confusion**: No deprecated code in production paths

---

## Risk Mitigation

### Before Starting
1. **Create Git Branch**: `git checkout -b cleanup/repository-consolidation`
2. **Full Backup**: Ensure all files are committed to Git
3. **Document Current State**: List all files before cleanup

### During Cleanup
1. **Move, Don't Delete**: Archive files first, delete later if needed
2. **Test After Each Phase**: Verify production pipeline after each phase
3. **Incremental Commits**: Commit after each phase for easy rollback

### After Cleanup
1. **30-Day Validation Period**: Keep archive accessible for 30 days
2. **Team Review**: Have team review cleaned structure
3. **Documentation Update**: Update all documentation references

---

## Recommended Timeline (Enhanced)

| Phase | Duration | Risk | Priority |
|-------|----------|------|----------|
| Phase 0: Pre-Cleanup Audit | 1 hour | None | High |
| **Phase 0.5: Pre-Flight Verification** | **15-30 min** | **None** | **CRITICAL** |
| Phase 1: Historical Doc | 2-3 hours | None | High |
| Phase 1.5: Pipeline Docs | 1 hour | None | High |
| Phase 2: Archive Files | 2-3 hours | Low | High |
| Phase 3: Consolidate Docs | 2-3 hours | Low | Medium |
| Phase 3.5: BigQuery Plan | 30 min | None | Medium |
| Phase 4: Remove Temp Files | 1 hour | Medium | Medium |
| Phase 4.5: Future Structure | 30 min | None | Low |
| Phase 5: Validation | 2-3 hours | Medium | High |
| **Total** | **11.5-15.5 hours** | **Low-Medium** | **High** |

---

## Key Decisions Needed

1. **Archive Location**: Keep in repo (larger) or external storage (smaller)?
   - **Recommendation**: Keep in repo under `archive/` for full Git history

2. **Model Versions**: Keep all model versions or only final?
   - **Recommendation**: Archive v4.0.0, v4.1.0, v4.1.0_r2; keep only v4.1.0_r3

3. **Execution Logs**: Keep or remove?
   - **Recommendation**: Archive (valuable for debugging historical issues)

4. **CSV Exports**: Keep or remove?
   - **Recommendation**: Remove (regenerate as needed, not version-controlled)

5. **Test Files**: Keep or remove?
   - **Recommendation**: Archive (may be useful for future testing)

---

## Next Steps (Enhanced)

1. **Review This Document**: Team review and approval
2. **Execute Phase 0**: Complete pre-cleanup audit (file and BigQuery inventory)
3. **⚠️ Execute Phase 0.5**: **CRITICAL** - Pre-flight verification (verify all production files exist)
4. **Execute Phase 1**: Create `MODEL_EVOLUTION_HISTORY.md` (comprehensive institutional knowledge)
5. **Execute Phase 1.5**: Document missing pipeline components (recyclable, exclusions, Salesforce)
6. **Execute Phase 2**: Archive deprecated files
7. **Execute Phase 3**: Consolidate documentation and create unified model registry
8. **Execute Phase 3.5**: Create BigQuery cleanup plan
9. **Execute Phase 4**: Remove temporary files
10. **Execute Phase 4.5**: Create future development structure (`predictive_movement/`)
11. **Execute Phase 5**: Validate and finalize (including BigQuery cleanup)

**⚠️ IMPORTANT**: Do NOT proceed past Phase 0.5 if any critical production files are missing. Investigate and resolve before continuing.

---

## Questions or Concerns?

If you have questions about specific files or recommendations, please document them here before proceeding with cleanup.

---

---

## Gaps Addressed in This Enhancement

This document has been enhanced to address the following gaps identified in `cleanup_enhancement_cursor_prompt.md`:

| Gap | Status | Section |
|-----|--------|---------|
| 1. Recyclable Lead Pipeline not documented | ✅ Addressed | Section 4.1 |
| 2. docs/ folder preservation unclear | ✅ Addressed | Section 5 (enhanced) |
| 3. BigQuery table cleanup not addressed | ✅ Addressed | Phase 0.2, Phase 3.5, Section 8 |
| 4. Predictive RIA Movement Model structure | ✅ Addressed | Phase 4.5, Section 9 |
| 5. MODEL_EVOLUTION_HISTORY.md content | ✅ Addressed | Phase 1 (enhanced template) |
| 6. Salesforce integration documentation | ✅ Addressed | Phase 1.5, Section 11 |
| 7. validation/ folder not addressed | ✅ Addressed | Section 6 (enhanced) |
| 8. SHAP analysis lessons learned | ✅ Addressed | Phase 1 (in MODEL_EVOLUTION_HISTORY.md) |
| 9. Model registry consolidation | ✅ Addressed | Phase 3, Section 10 |
| 10. Quick Start guides preservation | ✅ Addressed | Phase 3 (explicit preservation) |
| 11. Firm exclusions documentation | ✅ Addressed | Section 4.2, Phase 1.5 |
| 12. Cursor prompt methodology preservation | ✅ Addressed | Phase 1 (in MODEL_EVOLUTION_HISTORY.md) |

---

## Critical Fixes Applied (December 30, 2025)

This document has been updated to address critical production file identification issues discovered during pre-execution verification.

### ✅ Fixes Applied

1. **Added Missing V3 Production Files to KEEP**:
   - `v3/sql/lead_scoring_features_pit.sql` - Feature engineering (feeds V3 tier logic)
   - `v3/sql/phase_7_salesforce_sync.sql` - Production Salesforce sync
   - `v3/sql/phase_7_sga_dashboard.sql` - Production dashboard view

2. **Moved PRODUCTION_MODEL_UPDATE_CHECKLIST.md to KEEP**:
   - Changed from ARCHIVE to KEEP (needed for ongoing production updates)

3. **Clarified V3 Production SQL Path**:
   - Added note to verify which file exists (v3.3.0 OR v3.2.1)
   - Both files currently exist in repository (verify which is active)

4. **Explicitly Marked V4.0 SQL for Archiving**:
   - `v4/sql/production_scoring.sql` (V4.0) → ARCHIVE
   - `v4/sql/production_scoring_v41.sql` (V4.1) → KEEP

5. **Added Phase 0.5: Pre-Flight Verification**:
   - Critical verification step before any cleanup
   - Verifies all production files exist
   - Includes PowerShell and Bash verification scripts
   - **MUST complete before proceeding to Phase 1**

### ⚠️ Before Execution

**REQUIRED**: Run Phase 0.5 verification scripts to confirm all production files exist. If any files are missing, STOP and investigate before proceeding.

**Verification Status**: 
- ✅ Both `v3/sql/generate_lead_list_v3.3.0.sql` and `v3/sql/generate_lead_list_v3.2.1.sql` exist
- ⚠️ Need to verify which is the active production file

---

**Document Status**: Enhanced Draft for Review (Critical Fixes Applied)  
**Last Updated**: December 30, 2025  
**Enhancement Source**: `cleanup_enhancement_cursor_prompt.md`  
**Critical Fixes**: Production file identification corrections  
**Next Review**: After team feedback

