-- ============================================================================
-- SCORE A LIST OF ADVISOR CRDs (Lookup from staging table)
-- ============================================================================
-- Use when you have a Google Sheet (or CSV) of CRDs and want V3 tier + V4 score.
--
-- SETUP:
-- 1. Put your CRDs in BigQuery as a table with at least one column: crd (INT64).
--    Option A: Load CSV in BQ Console → Create table → Upload → column name "crd", type INTEGER.
--    Option B: Use a linked Google Sheet and create a view/table from it; ensure column is INT64.
-- 2. Create the staging table (one-time), e.g.:
--      CREATE TABLE `savvy-gtm-analytics.ml_features.crd_list_staging` (crd INT64);
--    Then load/overwrite with your CRDs (e.g. LOAD DATA or MERGE from Sheet).
-- 3. Run this query. Result can be exported to CSV or back to Sheets.
--
-- OUTPUT: One row per input CRD with score_tier (V3), v4_score, v4_percentile.
-- - V4 fields: Populated for any CRD in the V4 prospect universe (most FinTrx RIA advisors).
-- - V3 score_tier: Populated only for CRDs that were previously scored as leads (Salesforce).
--   If you need current V3 tier for advisors never in Salesforce, use the full lead list
--   pipeline filtered to your CRDs (see pipeline/docs/SCORE_GOOGLE_SHEET_CRDS.md).
--
-- Replace the table name below if your staging table is different.
-- ============================================================================

WITH your_crd_list AS (
  SELECT DISTINCT SAFE_CAST(crd AS INT64) AS crd
  FROM `savvy-gtm-analytics.ml_features.crd_list_staging`
  WHERE crd IS NOT NULL AND SAFE_CAST(crd AS INT64) IS NOT NULL
),

-- Latest V3 tier per advisor (lead_scores_v3_6 has historical rows; take most recent)
v3_latest AS (
  SELECT
    advisor_crd AS crd,
    score_tier,
    expected_conversion_rate,
    ROW_NUMBER() OVER (PARTITION BY advisor_crd ORDER BY contacted_date DESC) AS rn
  FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_6`
),

v3_one AS (
  SELECT crd, score_tier, expected_conversion_rate
  FROM v3_latest
  WHERE rn = 1
)

SELECT
  l.crd,
  v3.score_tier          AS score_tier,
  v3.expected_conversion_rate AS v3_expected_rate_pct,
  v4.v4_score            AS v4_score,
  v4.v4_percentile       AS v4_percentile
FROM your_crd_list l
LEFT JOIN v3_one v3       ON l.crd = v3.crd
LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 ON l.crd = v4.crd
ORDER BY v4.v4_percentile DESC, v3.score_tier;
