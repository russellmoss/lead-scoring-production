# V4.1.0 Deployment Execution Guide

**Date**: 2025-12-30  
**Model Version**: V4.1.0 R3  
**Status**: Ready for Production Deployment

---

## Pre-Deployment Checklist ✅

All pre-deployment items are complete:
- [x] Model trained and validated (R3)
- [x] Test AUC > baseline (0.620 > 0.599 V4.0.0)
- [x] Top decile lift > 1.5x (2.03x achieved)
- [x] Overfitting controlled (AUC gap: 0.075)
- [x] SHAP interpretability complete
- [x] Registry updated
- [x] Production model directory created
- [x] Inference script updated
- [x] Feature list validated (22 features)

---

## Deployment Steps

### Step 1: Update BigQuery Feature Engineering SQL ✅

**File Created**: `v4/sql/production_scoring_v41.sql`

**Action Required**:
1. Execute the SQL in BigQuery to create:
   - View: `ml_features.v4_production_features_v41`
   - Table: `ml_features.v4_daily_scores_v41`

**SQL Location**: `v4/sql/production_scoring_v41.sql`

**Key Changes**:
- Added V4.1.0 bleeding features (is_recent_mover, days_since_last_move, firm_departures_corrected, bleeding_velocity_encoded)
- Added V4.1.0 firm/rep type features (is_independent_ria, is_ia_rep_type, is_dual_registered)
- Removed 4 redundant features (industry_tenure_months, tenure_bucket_x_mobility, independent_ria_x_ia_rep, recent_mover_x_bleeding)
- Updated model_version to 'v4.1.0'

**Execution Command**:
```bash
# In BigQuery Console or via bq command-line tool
bq query --use_legacy_sql=false < v4/sql/production_scoring_v41.sql
```

**Validation**:
- [ ] Verify view `v4_production_features_v41` created successfully
- [ ] Verify table `v4_daily_scores_v41` created successfully
- [ ] Check feature count matches 22 features
- [ ] Test query on sample data

---

### Step 2: Update Monthly Scoring Script ✅

**File Updated**: `pipeline/scripts/score_prospects_monthly.py`

**Changes Made**:
- Updated `V4_MODEL_DIR` to point to `v4/models/v4.1.0`
- Updated `V4_FEATURES_FILE` to point to `v4/data/v4.1.0/final_features.json`

**Action Required**:
- [ ] Test the script on a small sample to verify it loads V4.1.0 model correctly
- [ ] Verify feature count matches (22 features)

**Test Command**:
```bash
cd pipeline
python scripts/score_prospects_monthly.py --test  # If test mode exists
```

---

### Step 3: Update Production Pipeline References

**Action Required**:
1. Update any scheduled jobs/scripts that reference:
   - Old view: `ml_features.v4_production_features` → New: `ml_features.v4_production_features_v41`
   - Old table: `ml_features.v4_daily_scores` → New: `ml_features.v4_daily_scores_v41`
   - Old model path: `v4/models/v4.0.0` → New: `v4/models/v4.1.0`

2. Update any BigQuery scheduled queries or Cloud Functions that use V4 scoring

**Checklist**:
- [ ] Identify all scripts/jobs that use V4 scoring
- [ ] Update references to new view/table names
- [ ] Update model path references
- [ ] Test each updated script/job

---

### Step 4: Salesforce Integration Update

**Action Required**:
1. Verify Salesforce fields exist:
   - `V4_Score__c` (Number, 18, 2)
   - `V4_Score_Percentile__c` (Number, 18, 0)
   - `V4_Deprioritize__c` (Checkbox)

2. Update any Salesforce sync scripts to:
   - Use new BigQuery table: `ml_features.v4_daily_scores_v41`
   - Use new model version identifier: 'v4.1.0'

**Checklist**:
- [ ] Verify Salesforce fields exist
- [ ] Update sync scripts to use new table
- [ ] Test sync on sandbox environment
- [ ] Verify score distribution matches expected

---

### Step 5: Parallel Scoring Validation (1 Week)

**Action Required**:
1. Run both V4.0.0 and V4.1.0 in parallel for 1 week
2. Compare metrics:
   - Top decile lift
   - Conversion rates by decile
   - Overall conversion rate

**Implementation**:
- Keep `v4_daily_scores` (V4.0.0) running
- Add `v4_daily_scores_v41` (V4.1.0) in parallel
- Compare results daily

**Checklist**:
- [ ] Set up parallel scoring
- [ ] Monitor metrics daily for 1 week
- [ ] Document any differences or anomalies
- [ ] Verify V4.1.0 performs as expected (≥ 2.0x lift)

---

### Step 6: Production Rollout

**Action Required**:
1. After 1 week validation, switch production to V4.1.0:
   - Update production queries to use `v4_production_features_v41`
   - Update production scoring to use `v4_daily_scores_v41`
   - Update model path to `v4/models/v4.1.0`

2. Monitor performance:
   - Daily: Top decile lift, conversion rates
   - Weekly: Full lift by decile analysis

**Checklist**:
- [ ] Switch production to V4.1.0
- [ ] Monitor performance metrics daily
- [ ] Track conversion rates and lift
- [ ] Document any issues or improvements

---

### Step 7: V4.0.0 Sunset

**Action Required**:
1. After successful V4.1.0 deployment (2+ weeks):
   - Archive V4.0.0 model artifacts
   - Update documentation
   - Remove V4.0.0 from active pipeline

**Checklist**:
- [ ] Archive V4.0.0 model to backup location
- [ ] Update documentation to reflect V4.1.0 as current
- [ ] Remove V4.0.0 references from production pipeline
- [ ] Update README and model reports

---

## Rollback Plan

### Rollback Criteria

If V4.1.0 underperforms, revert to V4.0.0 if:
- Top decile lift drops below 1.5x for 2 consecutive weeks
- Test AUC drops below 0.59 (below V4.0.0 baseline)
- Conversion rate in top decile drops below 5%

### Rollback Steps

1. Revert BigQuery pipeline to use:
   - View: `ml_features.v4_production_features`
   - Table: `ml_features.v4_daily_scores`
   - Model: `v4/models/v4.0.0/model.pkl`

2. Revert Salesforce integration to V4.0.0

3. Update registry to mark V4.1.0 as "deprecated"

4. Document rollback reason and metrics

---

## Files Created/Updated

### New Files
- `v4/sql/production_scoring_v41.sql` - V4.1.0 production feature engineering SQL
- `v4/DEPLOYMENT_EXECUTION.md` - This file

### Updated Files
- `pipeline/scripts/score_prospects_monthly.py` - Updated model paths to V4.1.0
- `v4/inference/lead_scorer_v4.py` - Updated default paths to V4.1.0
- `v4/models/registry.json` - V4.1.0 marked as production

---

## Next Actions

1. **Execute Step 1**: Run `production_scoring_v41.sql` in BigQuery
2. **Test Step 2**: Verify monthly scoring script works with V4.1.0
3. **Identify Step 3**: Find all production pipeline references
4. **Plan Step 4**: Coordinate Salesforce integration update
5. **Schedule Step 5**: Set up parallel scoring validation period

---

## Support

For questions or issues during deployment:
- **Model Questions**: See `v4/reports/v4.1/V4.1_Final_Summary.md`
- **Feature Engineering**: See `v4/sql/production_scoring_v41.sql`
- **Inference**: See `v4/inference/lead_scorer_v4.py`
- **Deployment Checklist**: See `v4/DEPLOYMENT_CHECKLIST_V4.1.md`

---

**Deployment Status**: Ready to begin Step 1  
**Last Updated**: 2025-12-30

