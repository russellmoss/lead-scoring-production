# Scoring a Google Sheet of Advisor CRDs

You have a sheet (or CSV) of advisor CRDs and want to get **score tiers** and **V4 scores**. Here are the best options.

---

## Option 1: BigQuery (recommended)

**Best when:** You’re fine loading the list into BQ once and running a query. No local scripts.

1. **Get CRDs into BigQuery**
   - **From CSV:** In BigQuery Console → your dataset (e.g. `ml_features`) → Create table → Upload CSV. Ensure one column is named `crd` and is integer (or cast in SQL).
   - **From Google Sheet:** Use a connected sheet (BigQuery Data Transfer / Connected Sheet) or export to CSV and load as above. If you use a Sheet-linked table, ensure the CRD column is `INT64` (or cast in the query).

2. **Staging table**
   - Create a table for your list, e.g. `ml_features.crd_list_staging` with column `crd` (INT64).
   - Load/overwrite it with your CRDs (from CSV or from a view over the Sheet).

3. **Run the lookup SQL**
   - Use: **`pipeline/sql/Score_CRD_List_Lookup.sql`**
   - It reads from `ml_features.crd_list_staging` (change the table name in the SQL if you use another).
   - Result: one row per CRD with `score_tier` (V3), `v4_score`, `v4_percentile`.

4. **Use the result**
   - Export the query result to CSV, or connect it to Looker Studio / Sheets for ongoing use.

**Caveat:**  
- **V4:** Filled for any CRD in the V4 prospect universe (most FinTrx RIA advisors).  
- **V3 `score_tier`:** Filled only for CRDs that already exist in the V3 scoring table (historically scored leads). Advisors who were never leads will have `score_tier` NULL. For “current” V3 tier for everyone on your list (including never-contacted), you’d need the full lead-list pipeline restricted to your CRDs (heavier; ask if you need this).

---

## Option 2: CSV + local Python script

**Best when:** You prefer not to create BQ tables, or you want a one-off “export sheet → get back scored CSV” workflow.

1. Export the sheet to CSV (one column with CRDs, or multiple columns with a `crd` column).
2. Run the script (see below). It will:
   - Read the CSV,
   - Query BigQuery with `WHERE crd IN (...)` against the same lookup logic as the SQL,
   - Write a new CSV with original columns plus `score_tier`, `v4_score`, `v4_percentile`.

Use: **`pipeline/scripts/score_crd_list.py`** (see script for usage and required env/auth).

Same caveat as above: V3 tier only for CRDs that exist in the V3 scoring table.

---

## Summary

| Approach        | Pros                          | Cons                               |
|----------------|-------------------------------|------------------------------------|
| **BQ (Option 1)** | No local code; reuse BQ/Sheets | Need to load list into BQ once     |
| **CSV + script (Option 2)** | No BQ staging table; run locally | Requires Python + `google-cloud-bigquery` and auth |

**Recommendation:** Use **Option 1** (BQ) if you can load the sheet/CSV into a BQ table; use **Option 2** if you prefer a local script and CSV in/out.
