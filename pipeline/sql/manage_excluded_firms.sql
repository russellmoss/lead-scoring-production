-- ============================================================================
-- EXCLUDED FIRMS MANAGEMENT QUERIES
-- ============================================================================
-- Use these queries to add, remove, or view exclusions
-- ============================================================================

-- ============================================================================
-- VIEW ALL EXCLUSIONS
-- ============================================================================
SELECT * FROM `savvy-gtm-analytics.ml_features.excluded_firms`
ORDER BY category, pattern;

SELECT * FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
ORDER BY firm_name;

-- ============================================================================
-- ADD A NEW PATTERN EXCLUSION
-- ============================================================================
-- Example: Add a new wirehouse
-- INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firms` 
-- VALUES ('%NEW FIRM NAME%', 'Wirehouse', CURRENT_DATE(), 'Reason for exclusion');

-- ============================================================================
-- ADD A NEW CRD EXCLUSION
-- ============================================================================
-- Example: Add a specific firm by CRD
-- INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firm_crds`
-- VALUES (123456, 'Firm Name', 'Category', CURRENT_DATE(), 'Reason for exclusion');

-- ============================================================================
-- REMOVE AN EXCLUSION
-- ============================================================================
-- Example: Remove a pattern exclusion
-- DELETE FROM `savvy-gtm-analytics.ml_features.excluded_firms`
-- WHERE pattern = '%PATTERN_TO_REMOVE%';

-- Example: Remove a CRD exclusion
-- DELETE FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
-- WHERE firm_crd = 123456;

-- ============================================================================
-- CHECK IF A FIRM WOULD BE EXCLUDED
-- ============================================================================
-- Replace 'FIRM NAME TO CHECK' with the firm you want to test
DECLARE test_firm STRING DEFAULT 'PRUCO SECURITIES LLC';

SELECT 
    test_firm as firm_name,
    ef.pattern,
    ef.category,
    ef.reason
FROM `savvy-gtm-analytics.ml_features.excluded_firms` ef
WHERE UPPER(test_firm) LIKE ef.pattern;

-- ============================================================================
-- FIND POTENTIAL EXCLUSIONS IN PROSPECT DATA
-- ============================================================================
-- Find firms with "Securities" in name that might need review
SELECT 
    PRIMARY_FIRM_NAME as firm_name,
    COUNT(*) as advisor_count
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
WHERE UPPER(PRIMARY_FIRM_NAME) LIKE '%SECURITIES%'
  AND PRODUCING_ADVISOR = TRUE
  AND ACTIVE = TRUE
  AND NOT EXISTS (
      SELECT 1 FROM `savvy-gtm-analytics.ml_features.excluded_firms` ef
      WHERE UPPER(PRIMARY_FIRM_NAME) LIKE ef.pattern
  )
GROUP BY PRIMARY_FIRM_NAME
HAVING COUNT(*) >= 3
ORDER BY advisor_count DESC
LIMIT 20;

