# Quick Start: Run Full Pipeline Now

**Date**: January 8, 2026  
**Versions**: V3.6.0 + V4.3.0

---

## Option 1: Manual Execution (Recommended for First Time)

### SQL Steps (Run in BigQuery Console)

1. **STEP 1**: Open `pipeline/sql/create_ma_eligible_advisors.sql` → Copy → Paste in BigQuery → Run
2. **STEP 2**: Open `pipeline/sql/v4_prospect_features.sql` → Copy → Paste in BigQuery → Run
3. **STEP 4**: Open `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` → Copy → Paste in BigQuery → Run
4. **STEP 5**: Open `pipeline/sql/Insert_MA_Leads.sql` → Copy → Paste in BigQuery → Run

### Python Steps (Run in Terminal)

```powershell
# Navigate to pipeline directory
cd c:\Users\russe\Documents\lead_scoring_production\pipeline

# STEP 3: Score all prospects (takes 10-15 minutes)
python scripts/score_prospects_v43.py

# STEP 6: Export to CSV (takes 30 seconds)
python scripts/export_lead_list.py
```

---

## Option 2: Using execute_sql.py Helper Script

If you prefer command-line execution for SQL files:

```powershell
cd c:\Users\russe\Documents\lead_scoring_production

# STEP 1: M&A Advisors
python execute_sql.py pipeline/sql/create_ma_eligible_advisors.sql

# STEP 2: V4 Features
python execute_sql.py pipeline/sql/v4_prospect_features.sql

# STEP 3: Score Prospects
cd pipeline
python scripts/score_prospects_v43.py

# STEP 4: Base Lead List
cd ..
python execute_sql.py pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql

# STEP 5: Insert M&A Leads
python execute_sql.py pipeline/sql/Insert_MA_Leads.sql

# STEP 6: Export CSV
cd pipeline
python scripts/export_lead_list.py
```

---

## Execution Order (CRITICAL)

```
1. create_ma_eligible_advisors.sql          (SQL - 30 sec)
2. v4_prospect_features.sql                 (SQL - 2-3 min)
3. score_prospects_v43.py                   (Python - 10-15 min) ⏱️ LONGEST STEP
4. January_2026_Lead_List_V3_V4_Hybrid.sql  (SQL - 1-2 min)
5. Insert_MA_Leads.sql                      (SQL - 30 sec) ⚠️ MUST RUN AFTER STEP 4
6. export_lead_list.py                      (Python - 30 sec)
```

**Total Time**: ~15-20 minutes

---

## Quick Verification After Each Step

### After Step 1:
```sql
SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`;
-- Expected: ~2,225
```

### After Step 2:
```sql
SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`;
-- Expected: ~285,690
```

### After Step 3:
```sql
SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
WHERE model_version = 'V4.3.0';
-- Expected: ~285,690
```

### After Step 4:
```sql
SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
-- Expected: ~2,800
```

### After Step 5:
```sql
SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
-- Expected: ~3,100 (2,800 + 300 M&A)
```

### After Step 6:
- Check `pipeline/exports/` folder for CSV file
- File name: `[month]_2026_lead_list_YYYYMMDD.csv`
- Expected rows: ~3,100

---

## Troubleshooting

**"Table not found" errors**: Make sure previous steps completed successfully.

**"Model file not found"**: Ensure you're in the `pipeline/` directory when running Python scripts.

**"Feature mismatch"**: Re-run Step 2 to regenerate features table.

**Step 5 fails**: Make sure Step 4 completed first (base lead list must exist).

---

**Ready to start? Begin with Step 1!**
