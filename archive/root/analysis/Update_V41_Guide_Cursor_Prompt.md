# Cursor.ai Prompt: Update V4.1_R3_Pipeline_Integration_Cursor_Guide.md

**Copy and paste this entire prompt into Cursor.ai:**

---

```
@workspace Update the V4.1 integration guide to UPDATE EXISTING FILES IN-PLACE rather than creating new files.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

FILE TO UPDATE: V4.1_R3_Pipeline_Integration_Cursor_Guide.md

## CONTEXT

The current guide creates new files (v4_1_prospect_features.sql, February_2026_Lead_List_V3_V4_1_Hybrid.sql, etc.) but we want to UPDATE EXISTING FILES instead:

### Files to UPDATE (not create new):
1. `pipeline/sql/v4_prospect_features.sql` → Add 8 new V4.1 features (total 22)
2. `pipeline/scripts/score_prospects_monthly.py` → Update model paths to V4.1.0
3. `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` → Update to use V4.1 features/scores
4. `pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql` → Same updates (duplicate file location)
5. `README.md` → Add V4.1.0 R3 documentation section

### Files that already exist with V4.1 model (reference these):
- `v4/models/v4.1.0/model.pkl` ✅ Already exists
- `v4/data/v4.1.0/final_features.json` ✅ Already exists (22 features)
- `v4/sql/production_scoring_v41.sql` ✅ Already exists (reference for feature SQL)
- `v4/EXECUTION_LOG_V4.1.md` ✅ Already exists
- `v4/reports/v4.1/V4.1_Final_Summary.md` ✅ Already exists

### Key changes from V4.0.0 to V4.1.0:
- Features: 14 → 22 (+8 new, -4 removed for multicollinearity)
- Test AUC: 0.599 → 0.620 (+3.5%)
- Top Decile Lift: 1.51x → 2.03x (+34%)
- SHAP: Limited → Full KernelExplainer

### NEW V4.1 Features to ADD:
1. is_recent_mover (moved in last 12 months)
2. days_since_last_move (days since joining current firm)
3. firm_departures_corrected (from inferred_departures_analysis)
4. bleeding_velocity_encoded (0=STABLE, 1=DECELERATING, 2=STEADY, 3=ACCELERATING)
5. is_independent_ria (SEC registered, state notice filed)
6. is_ia_rep_type (IA rep type)
7. is_dual_registered (broker-dealer + IA ties)

### REMOVED Features (multicollinearity r>0.90):
- industry_tenure_months (redundant with experience_years)
- tenure_bucket_x_mobility (redundant with mobility_3yr)
- independent_ria_x_ia_rep (redundant with is_ia_rep_type)
- recent_mover_x_bleeding (redundant with is_recent_mover)

## TASK

Rewrite V4.1_R3_Pipeline_Integration_Cursor_Guide.md with these changes:

### 1. Update Step 0 (Overview)
- Keep the context about why V4.1 is better
- Clarify we're UPDATING existing files, not creating new ones
- Reference existing V4.1 model files in v4/models/v4.1.0/

### 2. Rewrite Step 2 (Feature Engineering SQL)
**Change from:** Create pipeline/sql/v4_1_prospect_features.sql
**Change to:** Update pipeline/sql/v4_prospect_features.sql

Cursor prompt should:
- Add the 8 new V4.1 features to the existing SQL
- Add JOINs to: ml_features.inferred_departures_analysis, ml_features.firm_bleeding_velocity_v41
- Update header comments to note V4.1 upgrade
- Keep output table as ml_features.v4_prospect_features (same name)
- Provide the specific SQL additions to make (the 7 new feature calculations)

### 3. Rewrite Step 3 (Scoring Script)
**File:** pipeline/scripts/score_prospects_monthly.py

Update paths from V4.0.0 to V4.1.0:
```python
# FROM:
V4_MODEL_DIR = Path(r"...\v4\models\v4.0.0")
V4_FEATURES_FILE = Path(r"...\v4\data\processed\final_features.json")

# TO:
V4_MODEL_DIR = Path(r"...\v4\models\v4.1.0")
V4_FEATURES_FILE = Path(r"...\v4\data\v4.1.0\final_features.json")
```

Keep FEATURES_TABLE = "v4_prospect_features" (same table, just updated)
Keep SCORES_TABLE = "v4_prospect_scores" (same table, just updated)

### 4. Rewrite Step 4 (Lead List SQL)
**Change from:** Create February_2026_Lead_List_V3_V4_1_Hybrid.sql
**Change to:** Update pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql AND pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql

Updates needed in v4_enriched CTE:
- Add columns for new V4.1 features from v4_prospect_scores
- Keep joining to ml_features.v4_prospect_scores (same table name)
- Optionally update disagreement threshold from 70th to 60th percentile
- Add new V4.1 columns to final output
- Update header to document V4.1 integration
- Keep output table as ml_features.january_2026_lead_list_v4 (same name)

### 5. Update Step 5 (README)
Keep as-is: Update README.md with V4.1 documentation

### 6. Rewrite Step 6 (Validation)
**Change from:** Create v4_1_validation_queries.sql
**Change to:** Update validation queries to check existing tables with V4.1 features

Validation should check:
- v4_prospect_features has 22 features (including 7 new V4.1 features)
- v4_prospect_scores has scores from V4.1 model
- january_2026_lead_list_v4 has new V4.1 columns

### 7. Update File Reference Tables
Update all file paths to reflect UPDATING existing files, not creating new ones:

| File | Action | Purpose |
|------|--------|---------|
| pipeline/sql/v4_prospect_features.sql | UPDATE | Add 8 new V4.1 features |
| pipeline/scripts/score_prospects_monthly.py | UPDATE | Point to V4.1.0 model |
| pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql | UPDATE | Use V4.1 features |
| pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql | UPDATE | Same (duplicate location) |
| README.md | UPDATE | Add V4.1 documentation |

### 8. Update BigQuery Table Names
Keep all table names the SAME (just updated contents):
- ml_features.v4_prospect_features (same, with 22 features now)
- ml_features.v4_prospect_scores (same, with V4.1 scores now)
- ml_features.january_2026_lead_list_v4 (same, with V4.1 columns now)

### 9. Include Specific Code Changes

For v4_prospect_features.sql, provide the EXACT SQL to ADD after the existing features:
```sql
-- ================================================================
-- NEW V4.1 FEATURES (Add these after existing features)
-- ================================================================

-- FEATURE 16: is_recent_mover (NEW in V4.1)
CASE 
    WHEN cf.tenure_months IS NOT NULL AND cf.tenure_months <= 12 
    THEN 1 ELSE 0 
END as is_recent_mover,

-- FEATURE 17: days_since_last_move (NEW in V4.1)
COALESCE(DATE_DIFF(CURRENT_DATE(), bp.firm_start_date, DAY), 9999) as days_since_last_move,

-- FEATURE 18: firm_departures_corrected (NEW in V4.1)
COALESCE(ida.departures_12mo_inferred, 0) as firm_departures_corrected,

-- FEATURE 19: bleeding_velocity_encoded (NEW in V4.1)
CASE 
    WHEN bv.bleeding_velocity = 'ACCELERATING' THEN 3
    WHEN bv.bleeding_velocity = 'STEADY' THEN 2
    WHEN bv.bleeding_velocity = 'DECELERATING' THEN 1
    ELSE 0
END as bleeding_velocity_encoded,

-- FEATURE 20: is_independent_ria (NEW in V4.1)
CASE 
    WHEN fm.sec_registration_status = 'Registered' 
         AND fm.state_registration_status IN ('Notice Filed', 'Not Required') 
    THEN 1 ELSE 0 
END as is_independent_ria,

-- FEATURE 21: is_ia_rep_type (NEW in V4.1)
CASE WHEN bp.rep_type = 'IA' THEN 1 ELSE 0 END as is_ia_rep_type,

-- FEATURE 22: is_dual_registered (NEW in V4.1)
CASE 
    WHEN bp.rep_type = 'Dual' 
         OR (bp.rep_licenses LIKE '%Series 7%' AND bp.rep_licenses LIKE '%Series 65%') 
    THEN 1 ELSE 0 
END as is_dual_registered,
```

And the JOINs to ADD:
```sql
-- Add these JOINs to the main query:
LEFT JOIN `savvy-gtm-analytics.ml_features.inferred_departures_analysis` ida 
    ON bp.firm_crd = ida.firm_crd
LEFT JOIN `savvy-gtm-analytics.ml_features.firm_bleeding_velocity_v41` bv 
    ON bp.firm_crd = bv.firm_crd
```

### 10. Keep Rollback Instructions
Update rollback to note we're reverting MODEL PATHS (not deleting files):
- Revert V4_MODEL_DIR back to v4/models/v4.0.0
- Revert V4_FEATURES_FILE back to v4/data/processed/final_features.json
- Note: Feature SQL can stay at 22 features (V4.0 model will just ignore extras)

## OUTPUT

Rewrite the entire V4.1_R3_Pipeline_Integration_Cursor_Guide.md with:
1. All steps updated to EDIT existing files
2. Correct file paths (no new _v41 or _v4_1 suffixes)
3. Same BigQuery table names (just updated contents)
4. January 2026 lead list (not February)
5. Specific code snippets showing WHAT TO ADD/CHANGE in each file
6. Clear verification steps for each change

Make sure each Cursor prompt in the guide:
- Specifies the EXACT file to update
- Shows the BEFORE and AFTER for changed sections
- Includes verification queries/checks

Execute now and save the updated guide.
```

---

## Summary of Key Changes

| Original Guide | Updated Guide |
|----------------|---------------|
| Creates `v4_1_prospect_features.sql` | Updates `v4_prospect_features.sql` |
| Creates `February_2026_Lead_List_V3_V4_1_Hybrid.sql` | Updates `January_2026_Lead_List_V3_V4_Hybrid.sql` |
| Creates `v4_1_validation_queries.sql` | Updates validation for existing tables |
| New table: `v4_1_prospect_features` | Same table: `v4_prospect_features` (with 22 features) |
| New table: `v4_1_prospect_scores` | Same table: `v4_prospect_scores` (with V4.1 scores) |
| New table: `february_2026_lead_list_v41` | Same table: `january_2026_lead_list_v4` |

This approach is cleaner because:
1. No proliferation of versioned file names
2. Existing automation/scripts don't need path updates
3. January 2026 list gets V4.1 improvements immediately
4. Easier to track what changed vs. creating parallel files
