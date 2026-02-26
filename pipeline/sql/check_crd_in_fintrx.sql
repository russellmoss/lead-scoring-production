-- ============================================================================
-- Check if CRDs 12345678 and 8765432 exist in FinTrx ria_contacts_current
-- Run in BigQuery console. Inspect RIA_CONTACT_CRD_ID type and value.
-- ============================================================================

-- 1) Exact match (any type)
-- Returns rows if these CRDs exist in any common form (int, float, string).
SELECT
  RIA_CONTACT_CRD_ID,
  CAST(RIA_CONTACT_CRD_ID AS STRING) AS id_as_string,
  SAFE_CAST(RIA_CONTACT_CRD_ID AS FLOAT64) AS id_as_float,
  SAFE_CAST(ROUND(SAFE_CAST(RIA_CONTACT_CRD_ID AS FLOAT64), 0) AS INT64) AS id_normalized_int,
  CONTACT_FIRST_NAME,
  CONTACT_LAST_NAME,
  PRIMARY_FIRM_NAME
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
WHERE SAFE_CAST(ROUND(SAFE_CAST(RIA_CONTACT_CRD_ID AS FLOAT64), 0) AS INT64) IN (12345678, 8765432)
   OR REGEXP_REPLACE(CAST(RIA_CONTACT_CRD_ID AS STRING), r'[^0-9]', '') IN ('12345678', '8765432');
