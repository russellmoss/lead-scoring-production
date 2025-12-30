# Phase 2: Archive Deprecated Files - Summary

**Date**: December 30, 2025  
**Status**: ✅ Complete  
**Files Archived**: ~100+ files moved to `archive/` directory

---

## Archive Structure Created

```
archive/
├── v3/
│   ├── sql/          # Old SQL versions, test files
│   ├── scripts/      # Historical training scripts
│   ├── reports/      # Historical reports
│   ├── data/         # Historical data
│   └── *.md          # Historical documentation
├── v4/
│   ├── models/       # Deprecated model versions (v4.0.0, v4.1.0, v4.1.0_r2)
│   ├── data/         # Old version data
│   ├── scripts/      # Training scripts (one-time use)
│   ├── sql/          # Old phase SQL
│   ├── reports/      # Training reports
│   ├── config/       # Old config files
│   └── *.md          # Historical documentation
├── pipeline/
│   ├── sql/          # One-time cleanup SQL, fix documentation
│   ├── scripts/      # Historical analysis scripts
│   ├── logs/         # Historical execution logs
│   ├── reports/      # Historical reports
│   └── exports/      # Old CSV exports
└── root/
    ├── analysis/     # Root-level analysis documents
    └── guides/       # Upgrade guides
```

---

## Files Archived by Category

### V3 Archived Files

**SQL Files**:
- `generate_lead_list_v3.2.1.sql` (old version)
- `generate_lead_list_v3.2.1.sql.bak`
- `test_v3.3_*.sql` (test files)
- `v3.3_verification_results.md`

**Scripts**:
- `run_phase_4.py` (one-time training)
- `run_phase_7.py` (one-time training)
- `run_backtest_v3.py` (historical backtest)
- `backtest_v3.py`
- `compile_backtest_results.py`

**Reports**:
- `v3_backtest_summary.md`
- `v3.2_validation_results.md`

**Data**:
- `data/raw/` (historical data)

**Documentation**:
- `EXECUTION_LOG.md` (historical log)
- `January_2026_Lead_List_Query_V3.2.sql` (old version)
- `January_2026_Lead_List_Query_V3.2.sql.bak`
- `January_2026_Lead_List_Query_V3.3.sql` (duplicate)
- `V3_Lead_Scoring_Model_Complete_Guide.md` (superseded)

### V4 Archived Files

**Models**:
- `models/v4.0.0/` (deprecated)
- `models/v4.1.0/` (superseded by R3)
- `models/v4.1.0_r2/` (superseded by R3)

**Data**:
- `data/processed/` (old processed data)
- `data/v4.1.0/` (old version data)
- `data/v4.1.0_r2/` (old version data)

**Scripts**:
- `scripts/v4.1/phase_*.py` (all training scripts)
- `scripts/phase_*.py` (old phase scripts)
- `scripts/verify_final_features.py`

**SQL**:
- `sql/phase_1_target_definition.sql` (old phase)
- `sql/phase_2_feature_engineering.sql` (old phase)
- `sql/production_scoring.sql` (V4.0 version)

**Reports**:
- `reports/deprioritization_analysis.md`
- `reports/validation_report.md`
- `reports/shap_analysis_report.md`
- `reports/v4.1/overfitting_report*.md` (training reports)
- `reports/v4.1/overfitting_results*.json`
- `reports/v4.1/multicollinearity_report.md`
- `reports/v4.1/multicollinearity_results.json`
- `reports/v4.1/pit_audit_report.md`
- `reports/v4.1/pit_audit_results.json`
- `reports/v4.1/pit_audit_spot_check.csv`

**Config**:
- `config/` (old config files)

**Documentation**:
- `EXECUTION_LOG*.md` (historical logs)
- `DEPLOYMENT_*.md` (historical deployment docs)
- `SHAP_Investigation.md` (historical investigation)
- `V4_1_Retraining_Cursor_Guide.md` (historical guide)
- `XGBoost_ML_Lead_Scoring_V4_Development_Plan.md` (historical plan)
- `README.md` (duplicate)

**Other**:
- `v4/v4/` (duplicate nested directory)

### Pipeline Archived Files

**SQL**:
- `sql/cleanup_old_january_tables.sql` (one-time cleanup)
- `sql/create_excluded_v3_v4_disagreement_table.sql` (temporary analysis)
- `sql/generate_january_2026_lead_list.sql` (superseded)
- `sql/*.md` (execution results, fix documentation)

**Scripts**:
- `scripts/execute_v4_features.py` (one-time execution)
- `scripts/analyze_v4_percentile_distribution.py`
- `scripts/calculate_expected_conversion_rate.py`
- `scripts/check_alpha_zero.py`
- `scripts/check_shap_status.py`
- `scripts/fix_model_*.py` (one-time fixes)
- `scripts/run_lead_list_sql.py`
- `scripts/test_shap_with_fixed_model.py`
- `scripts/v41_backtest_simulation.py` (historical backtest)
- `scripts/validate_partner_founder_grouping.py`
- `scripts/verify_shap_diversity.py`

**Logs**:
- `logs/EXECUTION_LOG.md` (historical)
- `logs/V4.1_INTEGRATION_LOG.md` (historical)

**Reports**:
- `reports/V4.1_Backtest_Results.md` (historical)

**Exports**:
- `exports/*.csv` (old CSV exports - regenerate as needed)

### Root Archived Files

**Analysis Documents**:
- `bleeding_exploration*.md`
- `final_bleed_analysis*.md`
- `*update_guide*.md`
- `Update_V41_Guide_Cursor_Prompt.md`
- `V4_1_R3_Simulation_Backtest.md`
- `V4.1_R3_Pipeline_Integration_Cursor_Guide.md`
- `cleanup_enhancement_cursor_prompt.md`

---

## Production Files Preserved

All production files remain in their original locations:

**V3 Production**:
- ✅ `v3/sql/generate_lead_list_v3.3.0.sql`
- ✅ `v3/sql/phase_4_v3_tiered_scoring.sql`
- ✅ `v3/sql/lead_scoring_features_pit.sql`
- ✅ `v3/sql/phase_7_production_view.sql`
- ✅ `v3/sql/phase_7_salesforce_sync.sql`
- ✅ `v3/sql/phase_7_sga_dashboard.sql`
- ✅ `v3/models/model_registry_v3.json`
- ✅ `v3/VERSION_3_MODEL_REPORT.md`
- ✅ `v3/PRODUCTION_MODEL_UPDATE_CHECKLIST.md`

**V4 Production**:
- ✅ `v4/models/v4.1.0_r3/` (production model)
- ✅ `v4/models/registry.json`
- ✅ `v4/data/v4.1.0_r3/` (production features)
- ✅ `v4/sql/production_scoring_v41.sql`
- ✅ `v4/inference/lead_scorer_v4.py`
- ✅ `v4/VERSION_4_MODEL_REPORT.md`
- ✅ `v4/reports/v4.1/V4.1_Final_Summary.md`
- ✅ `v4/reports/v4.1/model_validation_report_r3.md`
- ✅ `v4/reports/v4.1/shap_*.png` (SHAP visualizations)

**Pipeline Production**:
- ✅ `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
- ✅ `pipeline/sql/v4_prospect_features.sql`
- ✅ `pipeline/sql/create_excluded_firms_table.sql`
- ✅ `pipeline/sql/create_excluded_firm_crds_table.sql`
- ✅ `pipeline/sql/manage_excluded_firms.sql`
- ✅ `pipeline/sql/recycling/recyclable_pool_master_v2.1.sql`
- ✅ `pipeline/scripts/score_prospects_monthly.py`
- ✅ `pipeline/scripts/execute_january_lead_list.py`
- ✅ `pipeline/scripts/export_lead_list.py`

---

## Verification

**All files moved, not deleted** ✅  
**Production files preserved** ✅  
**Archive structure organized** ✅  
**Git tracking maintained** ✅

---

## Next Steps

- ⏭️ **Phase 3**: Consolidate documentation
- ⏭️ **Phase 3.5**: Create BigQuery cleanup plan
- ⏭️ **Phase 4**: Remove temporary files
- ⏭️ **Phase 4.5**: Create predictive_movement/ structure
- ⏭️ **Phase 5**: Final validation

---

**Archive Status**: Complete  
**Files Preserved**: All files moved (not deleted)  
**Rollback**: Files can be restored from `archive/` if needed

