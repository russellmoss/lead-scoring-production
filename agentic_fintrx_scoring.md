# Agentic FinTrx Re-Scoring Implementation Plan

**Purpose:** After refreshing advisor data in `savvy-gtm-analytics.FinTrx_data_CA` (e.g., Nov 2025 → Feb 2026), run a full re-score of V3 rules-based tiers and V4 ML scores so the next lead list (e.g., March) uses current data.

**Audience:** Cursor, Claude Code, or similar agent. Execute phases in order; complete all validation steps before proceeding.

**How to use:** Work through phases 1–8 in order. For each phase: run the specified SQL (in BigQuery) or Python script (from repo root), then run the validation query(s). Do not start the next phase until the current phase’s validation passes (or you document a known exception, e.g. optional M&A table missing).

**Project root:** Repository root (e.g. `lead_scoring_production/`). Run Python from repo root unless noted.

---

## Prerequisites (verify before starting)

- [ ] BigQuery project `savvy-gtm-analytics` is accessible.
- [ ] `gcloud auth application-default login` has been run (for Python scripts).
- [ ] Python env has: `xgboost`, `pandas`, `google-cloud-bigquery`, `numpy`.
- [ ] V4.3.1 model files exist under `v4/models/v4.3.1/`:
  - `v4.3.1_model.json`
  - `v4.3.1_feature_importance.csv`
  - `v4.3.1_metadata.json`
- [ ] Exclusion tables exist (optional but recommended): run `pipeline/sql/create_excluded_firms_table.sql` and `pipeline/sql/create_excluded_firm_crds_table.sql` if not already done.

---

## Phase 1: V3 feature table (FinTrx → PIT features)

**Goal:** Rebuild `ml_features.lead_scoring_features_pit` from current FinTrx so V3 tier logic has up-to-date inputs.

### 1.1 Locate and run SQL

- **File:** `v3/sql/lead_scoring_features_pit.sql`  
- If the file is missing, search the repo for `lead_scoring_features_pit` and use the path that creates table `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`.
- **Action:** Execute the full SQL in BigQuery (e.g. copy into BigQuery Console and run). The script must contain `CREATE OR REPLACE TABLE \`savvy-gtm-analytics.ml_features.lead_scoring_features_pit\``.

### 1.2 Validation

Run in BigQuery:

```sql
-- V1.1: Row count and freshness
SELECT
  COUNT(*) AS row_count,
  MIN(contacted_date) AS min_date,
  MAX(contacted_date) AS max_date
FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`;
```

- **Pass:** `row_count` > 0; dates are reasonable (e.g. max_date near current month).
- **Fail:** If table is empty or missing, do not proceed; fix the SQL or path and re-run Phase 1.

---

## Phase 2: V3 tier table (PIT features → tiers)

**Goal:** Rebuild `ml_features.lead_scores_v3_6` from `lead_scoring_features_pit` so V3 tiers reflect current data.

### 2.1 Run SQL

- **File:** `v3/sql/phase_4_v3_tiered_scoring.sql`
- **Action:** Execute the full SQL in BigQuery. It must create or replace `savvy-gtm-analytics.ml_features.lead_scores_v3_6`.

### 2.2 Validation

Run in BigQuery:

```sql
-- V2.1: Row count and tier distribution
SELECT
  score_tier,
  COUNT(*) AS cnt
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_6`
GROUP BY score_tier
ORDER BY cnt DESC;
```

```sql
-- V2.2: Total rows
SELECT COUNT(*) AS total FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_6`;
```

- **Pass:** Total rows > 0; at least one tier (e.g. TIER_1G_ENHANCED_SWEET_SPOT, TIER_2_PROVEN_MOVER) has non-zero count.
- **Fail:** If table is empty or tier counts look wrong (e.g. all NULL), do not proceed; fix Phase 1 or Phase 2 SQL and re-run.

---

## Phase 3: M&A eligible advisors

**Goal:** Rebuild `ml_features.ma_eligible_advisors` from current FinTrx and M&A target list so March M&A leads are correct.

### 3.1 Run SQL

- **File:** `pipeline/sql/create_ma_eligible_advisors.sql`
- **Action:** Execute the full SQL in BigQuery. It must create or replace `savvy-gtm-analytics.ml_features.ma_eligible_advisors`.

### 3.2 Validation

Run in BigQuery:

```sql
-- V3.1: Row count
SELECT COUNT(*) AS ma_eligible_count FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`;
```

- **Pass:** `ma_eligible_count` ≥ 0 (can be 0 if no M&A targets). Table exists and query runs.
- **Fail:** If table creation fails (e.g. missing dependency `ml_features.active_ma_target_firms`), note in report and either fix dependency or skip M&A in Phase 6/7 if acceptable.

---

## Phase 4: V4 features (FinTrx → ML features)

**Goal:** Rebuild `ml_features.v4_prospect_features` from current FinTrx so V4 model inputs are up to date.

### 4.1 Run SQL

- **File:** `pipeline/sql/v4_prospect_features.sql`
- **Action:** Execute the full SQL in BigQuery. It must create or replace `savvy-gtm-analytics.ml_features.v4_prospect_features`. This may take several minutes.

### 4.2 Validation

Run in BigQuery:

```sql
-- V4.1: Row count and feature column check
SELECT COUNT(*) AS prospect_count FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`;
```

```sql
-- V4.2: Expected V4.3.1 feature columns (26). Adjust list if your model uses different set.
SELECT column_name
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'v4_prospect_features'
  AND column_name IN ('crd', 'tenure_months', 'cc_is_in_move_window', 'is_likely_recent_promotee', 'age_bucket_encoded')
ORDER BY column_name;
```

- **Pass:** `prospect_count` > 0 (e.g. ~285k); at least `crd` and several feature columns (e.g. `tenure_months`, `cc_is_in_move_window`, `is_likely_recent_promotee`) exist.
- **Fail:** If table is empty or key columns are missing, do not proceed to Phase 5; fix SQL and re-run Phase 4.

---

## Phase 5: V4 scores (ML features → scores)

**Goal:** Populate `ml_features.v4_prospect_scores` by applying the V4.3.1 model to `v4_prospect_features`.

### 5.1 Run Python script

- **Script:** `pipeline/scripts/score_prospects_v43.py`
- **Action:** From repository root run:
  ```bash
  python pipeline/scripts/score_prospects_v43.py
  ```
  On Windows (PowerShell):
  ```powershell
  python pipeline/scripts/score_prospects_v43.py
  ```
- **Note:** Use `score_prospects_v43.py` only. Do not use `score_prospects_monthly.py` (V4.2.0).

### 5.2 Validation

Run in BigQuery:

```sql
-- V5.1: Row count and score stats
SELECT
  COUNT(*) AS score_count,
  COUNT(v4_score) AS with_score,
  MIN(v4_percentile) AS min_pct,
  MAX(v4_percentile) AS max_pct
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`;
```

- **Pass:** `score_count` matches order of magnitude of `v4_prospect_features` (e.g. ~285k); `with_score` = `score_count`; `min_pct` / `max_pct` in [0, 100].
- **Fail:** If counts are 0 or much lower than feature table, check script logs and model path (`v4/models/v4.3.1/`); fix and re-run Phase 5.

---

## Phase 6: Base lead list (V3 + V4 → lead list table)

**Goal:** Generate the base lead list table from current FinTrx, V3 logic (inline), and V4 scores.

### 6.1 Run SQL

- **File:** `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
- **Action:** Execute the full SQL in BigQuery. It creates or replaces `savvy-gtm-analytics.ml_features.january_2026_lead_list`. Execution may take several minutes.

### 6.2 Validation

Run in BigQuery:

```sql
-- V6.1: Lead count and tier distribution
SELECT score_tier, COUNT(*) AS cnt
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY score_tier
ORDER BY cnt DESC;
```

```sql
-- V6.2: Total base leads (before M&A insert)
SELECT COUNT(*) AS base_lead_count FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
```

- **Pass:** `base_lead_count` > 0 (e.g. ~2,800); multiple score_tier values present.
- **Fail:** If table is empty or tier distribution is clearly wrong, check Phase 4/5 and exclusion tables; fix and re-run Phase 6.

---

## Phase 7: M&A leads insert

**Goal:** Add M&A tier leads to the lead list table (two-query architecture).

### 7.1 Run SQL

- **File:** `pipeline/sql/Insert_MA_Leads.sql`
- **Action:** Execute the full SQL in BigQuery. It inserts rows into `savvy-gtm-analytics.ml_features.january_2026_lead_list`. Must run after Phase 6.

### 7.2 Validation

Run in BigQuery:

```sql
-- V7.1: Total leads after M&A insert
SELECT COUNT(*) AS total_leads FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;

-- V7.2: M&A tier count (if applicable)
SELECT score_tier, COUNT(*) AS cnt
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
GROUP BY score_tier;
```

- **Pass:** Total leads ≥ base lead count from Phase 6; if M&A logic is used, at least one `TIER_MA%` tier appears.
- **Fail:** If insert fails (e.g. "table not found"), run Phase 6 again then Phase 7.

---

## Phase 8: Export to CSV

**Goal:** Export the final lead list to a CSV for Salesforce or downstream use.

### 8.1 Run Python script

- **Script:** `pipeline/scripts/export_lead_list.py`
- **Action:** From repository root:
  ```bash
  python pipeline/scripts/export_lead_list.py
  ```
  (Script may read config for month/name; output is typically under `pipeline/exports/`.)

### 8.2 Validation

- **Pass:** A new CSV file appears in `pipeline/exports/` (e.g. `March_2026_lead_list_YYYYMMDD.csv` or similar). Open and confirm: column headers present, row count on same order as total leads from Phase 7.
- **Fail:** If no file is created or path is wrong, check script’s output path and BigQuery table name; fix and re-run Phase 8.

---

## Final checklist

Before considering the re-score complete:

| # | Item | Status |
|---|------|--------|
| 1 | Phase 1 validation passed | ☐ |
| 2 | Phase 2 validation passed | ☐ |
| 3 | Phase 3 validation passed (or skipped with note) | ☐ |
| 4 | Phase 4 validation passed | ☐ |
| 5 | Phase 5 validation passed | ☐ |
| 6 | Phase 6 validation passed | ☐ |
| 7 | Phase 7 validation passed | ☐ |
| 8 | Phase 8 export file exists and is sane | ☐ |

---

## Troubleshooting

- **Missing `lead_scoring_features_pit.sql`:** Search repo for `lead_scoring_features_pit`; use the SQL file that builds `ml_features.lead_scoring_features_pit`. If none exists, Phase 2 may depend on an alternate V3 feature source—check `phase_4_v3_tiered_scoring.sql` for its FROM clause.
- **V4 script "feature not found":** Ensure `v4_prospect_features` has the 26 columns expected by `score_prospects_v43.py` (see `FEATURE_COLUMNS_V43` in the script). If the feature set changed, update the script or the feature SQL to match the trained model.
- **Lead list empty or tiny:** Verify `ml_features.excluded_firms` and `ml_features.excluded_firm_crds` exist and are not over-excluding; confirm FinTrx tables are populated and referenced correctly in the lead list SQL.
- **BigQuery "table not found":** Run phases in order; later phases depend on earlier output tables.

---

## Summary: Execution order

1. **Phase 1** – `v3/sql/lead_scoring_features_pit.sql` → `lead_scoring_features_pit`
2. **Phase 2** – `v3/sql/phase_4_v3_tiered_scoring.sql` → `lead_scores_v3_6`
3. **Phase 3** – `pipeline/sql/create_ma_eligible_advisors.sql` → `ma_eligible_advisors`
4. **Phase 4** – `pipeline/sql/v4_prospect_features.sql` → `v4_prospect_features`
5. **Phase 5** – `pipeline/scripts/score_prospects_v43.py` → `v4_prospect_scores`
6. **Phase 6** – `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` → `january_2026_lead_list`
7. **Phase 7** – `pipeline/sql/Insert_MA_Leads.sql` → (insert into same table)
8. **Phase 8** – `pipeline/scripts/export_lead_list.py` → CSV in `pipeline/exports/`

After all phases and validations pass, the pipeline is re-scored on the updated FinTrx data and the new list is ready to use.
