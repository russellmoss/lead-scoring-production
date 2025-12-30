# Pre-Cleanup File Inventory

**Generated**: December 30, 2025  
**Purpose**: Complete snapshot of repository before cleanup operations  
**Branch**: `cleanup/repository-consolidation`

---

## Summary Statistics

- **Total Files**: 221
- **Total Directories**: 48
- **Total Size**: 10.04 MB
- **Git Branch**: `cleanup/repository-consolidation` (created for cleanup)

---

## Files by Extension

| Extension | Count | Total Size (MB) |
|-----------|-------|----------------|
| .md | 74 | 1.53 |
| .py | 51 | 0.57 |
| .sql | 36 | 0.56 |
| .json | 35 | 2.56 |
| .csv | 12 | 1.59 |
| .pkl | 4 | 1.87 |
| .yaml | 2 | 0.00 |
| .png | 2 | 0.24 |
| .bak | 2 | 0.08 |
| .parquet | 1 | 1.03 |
| .pyc | 1 | 0.01 |
| .gitignore | 1 | 0.00 |
| **(no extension)** | 0 | 0.00 |

---

## Files by Directory

### Root (/)

**Markdown Files**:
- `README.md`
- `Lead_Scoring_Methodology_Final.md`
- `recommended_cleanup.md`
- `bleeding_exploration_cursor_prompt.md`
- `bleeding_exploration.md`
- `final_bleed_analysis_cursor_prompt.md`
- `final_bleed_analysis.md`
- `v3_to_v3.3_update_guide.md`
- `Update_V41_Guide_Cursor_Prompt.md`
- `V4_1_R3_Simulation_Backtest.md`
- `V4.1_R3_Pipeline_Integration_Cursor_Guide.md`
- `cleanup_enhancement_cursor_prompt.md`

**SQL Files**:
- `series_65_ria_advisors_with_salesforce.sql`

**Directories**:
- `archive/` (existing archive structure)
- `cleanup/` (created for cleanup documentation)
- `docs/`
- `pipeline/`
- `validation/`
- `v3/`
- `v4/`

---

### v3/ Directory

**Total Files**: ~30 files

**SQL Files** (12 files):
- `sql/generate_lead_list_v3.2.1.sql` ⚠️ (verify if active or superseded by v3.3.0)
- `sql/generate_lead_list_v3.2.1.sql.bak`
- `sql/generate_lead_list_v3.3.0.sql` ✅ Production
- `sql/lead_scoring_features_pit.sql` ✅ Production (CRITICAL)
- `sql/lead_target_variable_view.sql`
- `sql/phase_2_temporal_split.sql`
- `sql/phase_4_v3_tiered_scoring.sql` ✅ Production
- `sql/phase_7_production_view.sql` ✅ Production
- `sql/phase_7_salesforce_sync.sql` ✅ Production (CRITICAL)
- `sql/phase_7_sga_dashboard.sql` ✅ Production (CRITICAL)
- `sql/test_v3.3_syntax_verification.sql`
- `sql/test_v3.3_tier_distribution.sql`
- `sql/v3.3_verification_results.md`

**Python Scripts** (7 files):
- `scripts/backtest_v3.py`
- `scripts/compile_backtest_results.py`
- `scripts/generate_lead_list.py`
- `scripts/run_backtest_v3.py`
- `scripts/run_phase_4.py`
- `scripts/run_phase_7.py`
- `scripts/run_preflight_validation.py`

**Python Utils** (3 files):
- `utils/__init__.py`
- `utils/date_configuration.py`
- `utils/execution_logger.py`

**Documentation** (5 files):
- `VERSION_3_MODEL_REPORT.md` ✅ Production
- `V3_Lead_Scoring_Model_Complete_Guide.md` (superseded)
- `PRODUCTION_MODEL_UPDATE_CHECKLIST.md` ✅ Production (CRITICAL)
- `EXECUTION_LOG.md` (historical)
- `docs/LEAD_LIST_GENERATION_GUIDE.md` ✅ Production
- `docs/QUICK_START_LEAD_LISTS.md` ✅ Production

**Data Files** (3 files):
- `data/raw/backtest_config.json`
- `data/raw/tier_statistics.json`
- `data/raw/v3_backtest_results.csv`

**Reports** (2 files):
- `reports/v3_backtest_summary.md`
- `reports/v3.2_validation_results.md`

**Models** (1 file):
- `models/model_registry_v3.json` ✅ Production

**Config** (1 file):
- `date_config.json`

**Root SQL Files** (3 files):
- `January_2026_Lead_List_Query_V3.2.sql` (old version)
- `January_2026_Lead_List_Query_V3.2.sql.bak`
- `January_2026_Lead_List_Query_V3.3.sql` (duplicate - in pipeline/)

---

### v4/ Directory

**Total Files**: ~80+ files

**Model Files** (15 JSON files in models/):
- `models/registry.json` ✅ Production
- `models/v4.0.0/` (5 files) - ⚠️ DEPRECATED (archive)
- `models/v4.1.0/` (5 files) - ⚠️ SUPERSEDED (archive)
- `models/v4.1.0_r2/` (5 files) - ⚠️ SUPERSEDED (archive)
- `models/v4.1.0_r3/` (7 files) ✅ Production

**Python Scripts** (22 files):
- `scripts/phase_10_deployment.py`
- `scripts/phase_2_feature_engineering.py`
- `scripts/phase_6_model_training.py`
- `scripts/verify_final_features.py`
- `scripts/v4.1/` (18 phase training scripts) - ⚠️ ARCHIVE (one-time training)

**SQL Files** (12 files):
- `sql/phase_1_target_definition.sql` - ⚠️ ARCHIVE (old phase)
- `sql/phase_2_feature_engineering.sql` - ⚠️ ARCHIVE (old phase)
- `sql/production_scoring.sql` - ⚠️ ARCHIVE (V4.0 version)
- `sql/production_scoring_v41.sql` ✅ Production (V4.1)
- `sql/v4.1/` (8 files) ✅ Production

**Data Files** (6 JSON files):
- `data/processed/` (2 files) - ⚠️ ARCHIVE (old processed)
- `data/v4.1.0/` (5 files) - ⚠️ ARCHIVE (old version)
- `data/v4.1.0_r2/` (1 file) - ⚠️ ARCHIVE (old version)
- `data/v4.1.0_r3/` (1 file) ✅ Production

**Documentation** (10+ files):
- `VERSION_4_MODEL_REPORT.md` ✅ Production
- `README.md` - ⚠️ DUPLICATE (main README exists)
- `EXECUTION_LOG.md` - ⚠️ ARCHIVE (historical)
- `EXECUTION_LOG_V4.1.md` - ⚠️ ARCHIVE (historical)
- `DEPLOYMENT_*.md` (4 files) - ⚠️ ARCHIVE (historical deployment docs)
- `SHAP_Investigation.md` - ⚠️ ARCHIVE (historical)
- `V4_1_Retraining_Cursor_Guide.md` - ⚠️ ARCHIVE (historical guide)
- `XGBoost_ML_Lead_Scoring_V4_Development_Plan.md` - ⚠️ ARCHIVE (historical)

**Reports** (18 files):
- `reports/deprioritization_analysis.md` - ⚠️ ARCHIVE
- `reports/validation_report.md` - ⚠️ ARCHIVE
- `reports/shap_analysis_report.md` - ⚠️ ARCHIVE
- `reports/v4.1/` (15 files) - Mixed: Keep final summary and validation, archive training reports

**Inference** (1 file):
- `inference/lead_scorer_v4.py` ✅ Production

**Config** (3 files):
- `config/constants.py`
- `config/feature_config.yaml`
- `config/model_config.yaml`

**Nested Directory**:
- `v4/v4/` - ⚠️ DUPLICATE NESTED (remove)

---

### pipeline/ Directory

**Total Files**: ~50+ files

**SQL Files** (9 files):
- `sql/January_2026_Lead_List_V3_V4_Hybrid.sql` ✅ Production
- `sql/v4_prospect_features.sql` ✅ Production
- `sql/create_excluded_firms_table.sql` ✅ Production
- `sql/create_excluded_firm_crds_table.sql` ✅ Production
- `sql/manage_excluded_firms.sql` ✅ Production
- `sql/recycling/recyclable_pool_master_v2.1.sql` ✅ Production
- `sql/cleanup_old_january_tables.sql` - ⚠️ ARCHIVE (one-time cleanup)
- `sql/create_excluded_v3_v4_disagreement_table.sql` - ⚠️ ARCHIVE (temporary analysis)
- `sql/generate_january_2026_lead_list.sql` - ⚠️ ARCHIVE (superseded)

**Python Scripts** (15 files):
- `scripts/score_prospects_monthly.py` ✅ Production
- `scripts/execute_january_lead_list.py` ✅ Production
- `scripts/export_lead_list.py` ✅ Production
- `scripts/execute_v4_features.py` - ⚠️ ARCHIVE (one-time execution)
- `scripts/analyze_v4_percentile_distribution.py` - ⚠️ ARCHIVE
- `scripts/calculate_expected_conversion_rate.py` - ⚠️ ARCHIVE
- `scripts/check_alpha_zero.py` - ⚠️ ARCHIVE
- `scripts/check_shap_status.py` - ⚠️ ARCHIVE
- `scripts/fix_model_base_score.py` - ⚠️ ARCHIVE (one-time fix)
- `scripts/fix_model_for_shap.py` - ⚠️ ARCHIVE (one-time fix)
- `scripts/fix_model_json_base_score.py` - ⚠️ ARCHIVE (one-time fix)
- `scripts/run_lead_list_sql.py` - ⚠️ ARCHIVE
- `scripts/test_shap_with_fixed_model.py` - ⚠️ ARCHIVE
- `scripts/v41_backtest_simulation.py` - ⚠️ ARCHIVE (historical backtest)
- `scripts/validate_partner_founder_grouping.py` - ⚠️ ARCHIVE
- `scripts/verify_shap_diversity.py` - ⚠️ ARCHIVE

**Documentation** (10+ markdown files):
- `Monthly_Lead_List_Generation_V3_V4_Hybrid.md` ✅ Production
- `Monthly_Recyclable_Lead_List_Generation_Guide_V2.md` ✅ Production
- `sql/` directory (10 markdown files) - ⚠️ ARCHIVE (execution results, fix documentation)
- Various feature/issue documentation - ⚠️ ARCHIVE (historical fixes)

**Logs** (2 files):
- `logs/EXECUTION_LOG.md` - ⚠️ ARCHIVE (historical)
- `logs/V4.1_INTEGRATION_LOG.md` - ⚠️ ARCHIVE (historical)

**Reports** (1 file):
- `reports/V4.1_Backtest_Results.md` - ⚠️ ARCHIVE (historical)

**Exports** (2 CSV files):
- `exports/excluded_v3_v4_disagreement_leads_20251226.csv` - ⚠️ REMOVE (regenerate as needed)
- `exports/january_2026_lead_list_20251226.csv` - ⚠️ REMOVE (regenerate as needed)

**Root SQL** (1 file):
- `January_2026_Lead_List_V3_V4_Hybrid.sql` - ⚠️ DUPLICATE (keep sql/ version)

---

### docs/ Directory

**Total Files**: 5 files (ALL KEEP - Critical Documentation)

- `FINTRX_Architecture_Overview.md` ✅ Production
- `FINTRX_Data_Dictionary.md` ✅ Production
- `FINTRX_Lead_Scoring_Features.md` ✅ Production
- `How_To_Get_Scores_For_CRD_List.md` ✅ Production
- `SAVVY_PIRATE_DATA_GUIDE.md` ✅ Production

---

### validation/ Directory

**Total Files**: ~8 files

**Keep**:
- `LEAD_SCORING_KEY_FINDINGS.md` ✅ Production
- `mobility_and_stability_and_conversion.md` ✅ Production
- `backtest_optimized_january_list.py` ✅ Production (may be reused)

**Archive**:
- `january-lead-list-conversion-estimate.json` - ⚠️ ARCHIVE
- `january-lead-list-conversion-estimate.md` - ⚠️ ARCHIVE
- `lead_list_optimization_analysis.json` - ⚠️ ARCHIVE
- `lead_list_optimization_analysis.md` - ⚠️ ARCHIVE
- `v4_upgrade_impact_analysis.json` - ⚠️ ARCHIVE
- `sql/` directory - ⚠️ ARCHIVE (historical validation queries)

---

### archive/ Directory

**Total Files**: Unknown (existing archive structure)

**Structure**:
- `archive/test_results/`
- `archive/V3+V4_testing/`

**Note**: This is where we'll move deprecated files during cleanup.

---

## Production Files Summary

### Critical Production Files (MUST VERIFY IN PHASE 0.5)

**V3 Production**:
- ✅ `v3/sql/generate_lead_list_v3.3.0.sql` OR `v3/sql/generate_lead_list_v3.2.1.sql`
- ✅ `v3/sql/phase_4_v3_tiered_scoring.sql`
- ✅ `v3/sql/lead_scoring_features_pit.sql` ⚠️ CRITICAL
- ✅ `v3/sql/phase_7_production_view.sql`
- ✅ `v3/sql/phase_7_salesforce_sync.sql` ⚠️ CRITICAL
- ✅ `v3/sql/phase_7_sga_dashboard.sql` ⚠️ CRITICAL
- ✅ `v3/models/model_registry_v3.json`
- ✅ `v3/VERSION_3_MODEL_REPORT.md`
- ✅ `v3/PRODUCTION_MODEL_UPDATE_CHECKLIST.md` ⚠️ CRITICAL

**V4 Production**:
- ✅ `v4/models/v4.1.0_r3/model.pkl`
- ✅ `v4/models/v4.1.0_r3/model.json`
- ✅ `v4/models/registry.json`
- ✅ `v4/data/v4.1.0_r3/final_features.json`
- ✅ `v4/sql/production_scoring_v41.sql` (NOT production_scoring.sql)
- ✅ `v4/inference/lead_scorer_v4.py`

**Pipeline Production**:
- ✅ `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
- ✅ `pipeline/sql/v4_prospect_features.sql`
- ✅ `pipeline/sql/create_excluded_firms_table.sql`
- ✅ `pipeline/sql/create_excluded_firm_crds_table.sql`
- ✅ `pipeline/sql/recycling/recyclable_pool_master_v2.1.sql`
- ✅ `pipeline/scripts/score_prospects_monthly.py`
- ✅ `pipeline/scripts/execute_january_lead_list.py`
- ✅ `pipeline/scripts/export_lead_list.py`

**Documentation**:
- ✅ `README.md`
- ✅ `Lead_Scoring_Methodology_Final.md`
- ✅ All files in `docs/` directory

---

## Archive Candidates Summary

### Estimated Archive Count: ~100-150 files

**Categories**:
- Deprecated model versions (v4.0.0, v4.1.0, v4.1.0_r2)
- Historical training scripts (all phase_*.py files)
- Historical execution logs
- Historical analysis and exploration documents
- Historical fix documentation
- Test and backup files
- Old CSV exports

---

## Next Steps

1. ✅ **Phase 0 Complete**: Inventory created
2. ⏭️ **Phase 0.5**: Run pre-flight verification (CRITICAL)
3. ⏭️ **Phase 1**: Create MODEL_EVOLUTION_HISTORY.md
4. ⏭️ **Phase 2+**: Continue with cleanup phases

---

**Inventory Status**: Complete  
**Generated**: December 30, 2025  
**Next Action**: Phase 0.5 Pre-Flight Verification

