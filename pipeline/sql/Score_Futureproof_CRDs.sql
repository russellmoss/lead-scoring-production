-- ============================================================================
-- Add score_tier + V4 scores to LeadScoring.futureproof
-- ============================================================================
-- Reads from savvy-gtm-analytics.LeadScoring.futureproof, joins V3 tier and V4
-- scores, returns all original columns plus score_tier, v4_score, v4_percentile.
--
-- If your CRD column in futureproof has a different name (e.g. CRD, advisor_crd),
-- replace fp.crd below with that column in the JOINs and in the SELECT.
-- ============================================================================

-- Uses lead_scores_v3_4 (lead_scores_v3_6 not present in this project)
WITH v3_latest AS (
  SELECT
    SAFE_CAST(REGEXP_REPLACE(CAST(advisor_crd AS STRING), r'[^0-9]', '') AS INT64) AS crd,
    score_tier,
    expected_conversion_rate,
    ROW_NUMBER() OVER (
      PARTITION BY advisor_crd
      ORDER BY COALESCE(expected_conversion_rate, 0) DESC
    ) AS rn
  FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_4`
),
v3_one AS (
  SELECT crd, score_tier, expected_conversion_rate
  FROM v3_latest
  WHERE rn = 1 AND crd IS NOT NULL
)

SELECT
  fp.*,
  v3.score_tier          AS score_tier,
  v3.expected_conversion_rate AS v3_expected_rate_pct,
  v4.v4_score            AS v4_score,
  v4.v4_percentile       AS v4_percentile
FROM `savvy-gtm-analytics.LeadScoring.futureproof` fp
LEFT JOIN v3_one v3
  ON SAFE_CAST(REGEXP_REPLACE(CAST(fp.crd AS STRING), r'[^0-9]', '') AS INT64) = v3.crd
LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4
  ON SAFE_CAST(REGEXP_REPLACE(CAST(fp.crd AS STRING), r'[^0-9]', '') AS INT64) = v4.crd
ORDER BY v4.v4_percentile DESC, v3.score_tier;
