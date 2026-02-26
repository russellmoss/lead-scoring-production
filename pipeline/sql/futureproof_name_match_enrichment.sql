-- Futureproof name-match enrichment (BigQuery)
-- Use when you have a table of (first_name, last_name, full_name) for advisors with no CRD.
-- Match to FinTrx_data_CA.ria_contacts_current on:
--   CONTACT_LAST_NAME, CONTACT_FIRST_NAME, RIA_CONTACT_PREFERRED_NAME, RIA_CONTACT_FIRST_NAME_OTHER
-- Only return rows where there is exactly one match per name (single match = safe to enrich).
--
-- Step 1: Create or load your no-CRD names table, e.g.:
--   CREATE OR REPLACE TABLE ml_features.futureproof_no_crd_names AS
--   SELECT
--     TRIM(SPLIT(name, ' ')[OFFSET(0)]) AS first_name,
--     TRIM(SUBSTR(name, STRPOS(name, ' ') + 1)) AS last_name,
--     TRIM(name) AS full_name
--   FROM UNNEST(['Wayne Anderman', 'Jane Smith']) AS name;
--
-- Step 2: Run this query; export results and merge back into CSV (column D = linkedin, E = CRD, F = PRIMARY_FIRM_TOTAL_AUM, G = REP_AUM, H = PRODUCING_ADVISOR; add I = matched on name, J = name_match_note).

WITH
no_crd_names AS (
  -- Replace with your table of (first_name, last_name, full_name) for rows without CRD
  SELECT first_name, last_name, full_name
  FROM `savvy-gtm-analytics.ml_features.futureproof_no_crd_names`
),
matches AS (
  SELECT
    n.first_name,
    n.last_name,
    n.full_name,
    c.RIA_CONTACT_CRD_ID AS crd,
    c.LINKEDIN_PROFILE_URL AS linkedin_profile_url,
    c.REP_AUM AS rep_aum,
    c.PRODUCING_ADVISOR AS producing_advisor,
    COALESCE(c.PRIMARY_FIRM_TOTAL_AUM, f.TOTAL_AUM) AS primary_firm_total_aum,
    COUNT(*) OVER (PARTITION BY n.first_name, n.last_name, n.full_name) AS match_cnt
  FROM no_crd_names n
  INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON LOWER(TRIM(c.CONTACT_LAST_NAME)) = LOWER(TRIM(n.last_name))
    AND (
      LOWER(TRIM(c.CONTACT_FIRST_NAME)) = LOWER(TRIM(n.first_name))
      OR LOWER(TRIM(COALESCE(c.RIA_CONTACT_FIRST_NAME_OTHER, c.CONTACT_FIRST_NAME))) = LOWER(TRIM(n.first_name))
      OR LOWER(TRIM(c.RIA_CONTACT_PREFERRED_NAME)) = LOWER(TRIM(n.full_name))
    )
  LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current` f
    ON c.PRIMARY_FIRM = f.CRD_ID
),
-- One row per (first, last, full): single match = data; multi = (multiple matches) note
enriched AS (
  SELECT
    first_name,
    last_name,
    full_name,
    CASE WHEN match_cnt = 1 THEN crd ELSE NULL END AS crd,
    CASE WHEN match_cnt = 1 THEN linkedin_profile_url ELSE NULL END AS linkedin_profile_url,
    CASE WHEN match_cnt = 1 THEN rep_aum ELSE NULL END AS rep_aum,
    CASE WHEN match_cnt = 1 THEN producing_advisor ELSE NULL END AS producing_advisor,
    CASE WHEN match_cnt = 1 THEN primary_firm_total_aum ELSE NULL END AS primary_firm_total_aum,
    match_cnt > 0 AS matched_on_name,
    CASE WHEN match_cnt > 1 THEN '(multiple matches)' ELSE '' END AS name_match_note
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY first_name, last_name, full_name ORDER BY crd) AS rn
    FROM matches
  )
  WHERE rn = 1
)
SELECT * FROM enriched ORDER BY full_name;
