# Run Full Pipeline - Step-by-Step Instructions

**Date**: January 8, 2026  
**Versions**: V3.6.1 + V4.3.2  
**Estimated Time**: 15-20 minutes

---

## Prerequisites Check

Before starting, verify you have:
- ✅ BigQuery access to `savvy-gtm-analytics` project
- ✅ Python environment with packages: `xgboost`, `pandas`, `google-cloud-bigquery`, `numpy`
- ✅ V4.3.0 model files in `v4/models/v4.3.0/`:
  - `v4.3.0_model.json`
  - `v4.3.0_feature_importance.csv`
  - `v4.3.0_metadata.json`

---

## Execution Steps

### STEP 1: Refresh M&A Advisors Table

**File**: `pipeline/sql/create_ma_eligible_advisors.sql`  
**Output**: `ml_features.ma_eligible_advisors` (~2,225 advisors)

**How to Run**:
1. Open BigQuery Console: https://console.cloud.google.com/bigquery
2. Select project: `savvy-gtm-analytics`
3. Open SQL editor
4. Copy and paste contents of `pipeline/sql/create_ma_eligible_advisors.sql`
5. Click "Run"
6. Wait for completion (~30 seconds)

**Verify**:
```sql
SELECT 
    ma_tier,
    COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_tier;
```
Expected: ~1,100 TIER_MA_ACTIVE_PRIME, ~1,100 TIER_MA_ACTIVE

---

### STEP 2: Calculate V4.3.2 Features

**File**: `pipeline/sql/v4_prospect_features.sql`  
**Output**: `ml_features.v4_prospect_features` (~285,690 prospects)  
**Note**: V4.3.2 includes fuzzy firm name matching fix for Career Clock features

**How to Run**:
1. In BigQuery SQL editor
2. Copy and paste contents of `pipeline/sql/v4_prospect_features.sql`
3. Click "Run"
4. Wait for completion (~2-3 minutes)

**Verify**:
```sql
SELECT 
    COUNT(*) as total_prospects,
    COUNT(DISTINCT crd) as unique_crds,
    COUNTIF(cc_is_in_move_window = 1) as in_move_window,
    COUNTIF(cc_is_too_early = 1) as too_early,
    feature_version
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`
GROUP BY feature_version;
```
Expected: ~285,690 prospects, feature_version = 'v4.3.2', ~13,000 in move window (reduced from ~85,000 after fuzzy matching fix), ~1,300 too early

---

### STEP 3: Score Prospects with V4.3.1 Model

**File**: `pipeline/scripts/score_prospects_v43.py`  
**Output**: `ml_features.v4_prospect_scores` (~285,690 scores)

**How to Run**:
```bash
cd c:\Users\russe\Documents\lead_scoring_production\pipeline
python scripts/score_prospects_v43.py
```

**What It Does**:
- Loads V4.3.1 model from `v4/models/v4.3.1/v4.3.1_model.json`
- Loads feature importance from `v4/models/v4.3.1/v4.3.1_feature_importance.csv`
- Fetches features from `ml_features.v4_prospect_features` (V4.3.2 with fuzzy firm matching)
- Scores all ~285,690 prospects
- Generates gain-based narratives
- Uploads to `ml_features.v4_prospect_scores`

**Expected Runtime**: 10-15 minutes (processing ~285K prospects)

**Verify**:
```sql
SELECT 
    COUNT(*) as total_scores,
    COUNTIF(model_version = 'V4.3.1') as v43_scores,
    COUNTIF(cc_is_in_move_window = 1) as in_move_window,
    AVG(v4_score) as avg_score
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
WHERE scored_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);
```
Expected: ~285,690 scores, all V4.3.1, ~13,000 in move window (after V4.3.2 fuzzy matching fix)

---

### STEP 4: Generate Base Lead List (Query 1)

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`  
**Output**: `ml_features.january_2026_lead_list` (~2,800 leads)

**How to Run**:
1. In BigQuery SQL editor
2. Copy and paste contents of `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
3. Click "Run"
4. Wait for completion (~1-2 minutes)

**Verify**:
```sql
SELECT 
    COUNT(*) as total_leads,
    COUNTIF(score_tier LIKE 'TIER_MA%') as ma_leads,
    COUNT(DISTINCT sga_owner) as sgas_assigned
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
```
Expected: ~2,800 leads, 0 M&A leads (added in Step 5), ~14 SGAs

---

### STEP 5: Insert M&A Leads (Query 2) ⚠️ MUST RUN AFTER STEP 4

**File**: `pipeline/sql/Insert_MA_Leads.sql`  
**Output**: Adds ~300 M&A leads to existing `ml_features.january_2026_lead_list`

**How to Run**:
1. In BigQuery SQL editor
2. Copy and paste contents of `pipeline/sql/Insert_MA_Leads.sql`
3. Click "Run"
4. Wait for completion (~30 seconds)

**⚠️ CRITICAL**: This MUST run AFTER Step 4. The base lead list table must exist first.

**Verify**:
```sql
SELECT 
    COUNT(*) as total_leads,
    COUNTIF(score_tier LIKE 'TIER_MA%') as ma_leads
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
```
Expected: ~3,100 total leads, ~300 M&A leads

---

### STEP 6: Export to CSV

**File**: `pipeline/scripts/export_lead_list.py`  
**Output**: `pipeline/exports/[month]_2026_lead_list_YYYYMMDD.csv`

**How to Run**:
```bash
cd c:\Users\russe\Documents\lead_scoring_production\pipeline
python scripts/export_lead_list.py
```

**What It Does**:
- Fetches lead list from `ml_features.january_2026_lead_list`
- Validates data quality
- Exports to CSV with all required columns
- Saves to `pipeline/exports/` directory

**Expected Runtime**: ~30 seconds

**Verify**:
- Check `pipeline/exports/` directory for CSV file
- File name format: `[month]_2026_lead_list_YYYYMMDD.csv`
- Expected rows: ~3,100 (2,800 base + 300 M&A)

---

## Quick Execution Script

If you want to run Steps 3 and 6 (Python scripts) in sequence:

```bash
cd c:\Users\russe\Documents\lead_scoring_production\pipeline

# Step 3: Score prospects
python scripts/score_prospects_v43.py

# Step 6: Export to CSV
python scripts/export_lead_list.py
```

**Note**: Steps 1, 2, 4, and 5 must be run in BigQuery SQL editor (not command line).

---

## Troubleshooting

### Step 3 Fails: "Model file not found"
- **Check**: `v4/models/v4.3.1/v4.3.1_model.json` exists
- **Fix**: Ensure you're in the `pipeline/` directory when running the script

### Step 3 Fails: "Feature mismatch"
- **Check**: `ml_features.v4_prospect_features` has all 26 features
- **Fix**: Re-run Step 2 to regenerate features table

### Step 4 Fails: "Table not found: lead_scores_v3_6"
- **Check**: V3.6.0 tier scoring has been run
- **Fix**: Run `v3/sql/phase_4_v3_tiered_scoring.sql` first (if not already done)

### Step 5 Fails: "Table not found: january_2026_lead_list"
- **Check**: Step 4 completed successfully
- **Fix**: Run Step 4 first, then Step 5

### Step 6 Fails: "No leads found"
- **Check**: Step 5 completed successfully
- **Fix**: Verify `ml_features.january_2026_lead_list` has ~3,100 rows

---

## Expected Final Output

**CSV File**: `pipeline/exports/january_2026_lead_list_YYYYMMDD.csv`

**Contents**:
- ~3,100 leads total
- ~2,800 standard leads (V3.6.1 tiers + V4.3.2 upgrades)
- ~300 M&A leads (TIER_MA_ACTIVE_PRIME, TIER_MA_ACTIVE) with recent promotee exclusion
- All leads assigned to SGAs (~200 leads per SGA)
- Includes V4.3.1 scores, percentiles, and gain-based narratives
- Includes Career Clock features (cc_is_in_move_window, cc_is_too_early) with V4.3.2 fuzzy firm matching fix

**Ready for**: Salesforce import

---

## Execution Time Estimate

| Step | Action | Estimated Time |
|------|--------|----------------|
| 1 | M&A Advisors SQL | 30 seconds |
| 2 | V4 Features SQL | 2-3 minutes |
| 3 | Score Prospects Python | 10-15 minutes |
| 4 | Base Lead List SQL | 1-2 minutes |
| 5 | Insert M&A Leads SQL | 30 seconds |
| 6 | Export CSV Python | 30 seconds |
| **Total** | | **15-20 minutes** |

---

**Last Updated**: January 8, 2026  
**Status**: ✅ Ready for execution
