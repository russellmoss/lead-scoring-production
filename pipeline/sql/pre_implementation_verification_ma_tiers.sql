-- ============================================================================
-- V3.5.0 M&A TIERS - PRE-IMPLEMENTATION VERIFICATION
-- ============================================================================
-- Run these queries BEFORE creating any new tables to confirm the data pipeline is healthy.
-- All checks must pass before proceeding with implementation.
-- ============================================================================

-- ============================================================
-- QUERY 6.1: Verify M&A Target Firms Exist
-- ============================================================
-- Expected: 
-- HOT: 30-50 firms, 60-180 days since news
-- ACTIVE: 20-40 firms, 181-365 days since news
-- ============================================================

SELECT 
    '=== CHECK 6.1: M&A Target Firms ===' as check_name,
    ma_status,
    COUNT(*) as firm_count,
    SUM(firm_employees) as total_employees,
    AVG(firm_employees) as avg_employees,
    MIN(days_since_first_news) as min_days,
    MAX(days_since_first_news) as max_days
FROM `savvy-gtm-analytics.ml_features.active_ma_target_firms`
WHERE ma_status IN ('HOT', 'ACTIVE')
GROUP BY ma_status
ORDER BY ma_status;

-- ============================================================
-- QUERY 6.2: Verify Advisors Exist at M&A Firms
-- ============================================================
-- Expected: 1,000-5,000 advisors at M&A target firms
-- ============================================================

SELECT 
    '=== CHECK 6.2: Advisors at M&A Firms ===' as check_name,
    ma.ma_status,
    COUNT(DISTINCT c.RIA_CONTACT_CRD_ID) as advisor_count,
    COUNT(DISTINCT ma.firm_crd) as firm_count
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
JOIN `savvy-gtm-analytics.ml_features.active_ma_target_firms` ma 
    ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = SAFE_CAST(ma.firm_crd AS INT64)
WHERE ma.ma_status IN ('HOT', 'ACTIVE')
  AND c.PRODUCING_ADVISOR = TRUE
  AND c.CONTACT_FIRST_NAME IS NOT NULL
  AND c.CONTACT_LAST_NAME IS NOT NULL
GROUP BY ma.ma_status;

-- ============================================================
-- QUERY 6.3: Verify Data Type Compatibility
-- ============================================================
-- Expected: Both INT64 or castable
-- If types differ, we need SAFE_CAST in JOINs
-- ============================================================

SELECT 
    '=== CHECK 6.3: Data Type Compatibility ===' as check_name,
    'active_ma_target_firms.firm_crd' as column_source,
    (SELECT data_type 
     FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.COLUMNS`
     WHERE table_name = 'active_ma_target_firms' AND column_name = 'firm_crd') as data_type
UNION ALL
SELECT 
    '=== CHECK 6.3: Data Type Compatibility ===' as check_name,
    'ria_contacts_current.PRIMARY_FIRM' as column_source,
    (SELECT data_type 
     FROM `savvy-gtm-analytics.FinTrx_data_CA.INFORMATION_SCHEMA.COLUMNS`
     WHERE table_name = 'ria_contacts_current' AND column_name = 'PRIMARY_FIRM') as data_type;

-- ============================================================
-- QUERY 6.4: Verify JOIN Works (Critical Test)
-- ============================================================
-- Expected: 1,000-5,000 matches
-- If 0: There's a JOIN issue (data type or data mismatch)
-- ============================================================

SELECT 
    '=== CHECK 6.4: JOIN Test (CRITICAL) ===' as check_name,
    COUNT(*) as total_matches,
    COUNT(DISTINCT c.RIA_CONTACT_CRD_ID) as unique_advisors,
    COUNT(DISTINCT ma.firm_crd) as unique_firms
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
JOIN `savvy-gtm-analytics.ml_features.active_ma_target_firms` ma 
    ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = SAFE_CAST(ma.firm_crd AS INT64)
WHERE ma.ma_status IN ('HOT', 'ACTIVE')
  AND ma.firm_employees >= 10
  AND c.PRODUCING_ADVISOR = TRUE;

-- ============================================================
-- QUERY 6.5: Verify Tier Assignment Logic
-- ============================================================
-- Expected: Mix of PRIME and standard tiers
-- ============================================================

SELECT 
    '=== CHECK 6.5: Tier Assignment Preview ===' as check_name,
    CASE 
        WHEN UPPER(c.TITLE_NAME) LIKE '%PRESIDENT%' 
          OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%'
          OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%OWNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
          OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%MANAGING%'
        THEN 'TIER_MA_ACTIVE_PRIME (Senior Title)'
        WHEN DATE_DIFF(CURRENT_DATE(), 
             (SELECT MIN(h.PREVIOUS_REGISTRATION_COMPANY_START_DATE) 
              FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` h 
              WHERE h.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID), MONTH) BETWEEN 120 AND 240
        THEN 'TIER_MA_ACTIVE_PRIME (Mid-Career)'
        ELSE 'TIER_MA_ACTIVE'
    END as expected_tier,
    COUNT(*) as advisor_count
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
JOIN `savvy-gtm-analytics.ml_features.active_ma_target_firms` ma 
    ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = SAFE_CAST(ma.firm_crd AS INT64)
WHERE ma.ma_status IN ('HOT', 'ACTIVE')
  AND ma.firm_employees >= 10
  AND c.PRODUCING_ADVISOR = TRUE
GROUP BY 1
ORDER BY 2 DESC;

-- ============================================================
-- BONUS CHECK: Commonwealth Exclusion Conflict
-- ============================================================
-- This confirms Commonwealth is on exclusion list but should be exempted
-- ============================================================

SELECT 
    '=== BONUS: Commonwealth Exclusion Check ===' as check_name,
    COUNT(*) as commonwealth_advisors_at_ma_firms
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
JOIN `savvy-gtm-analytics.ml_features.active_ma_target_firms` ma 
    ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = SAFE_CAST(ma.firm_crd AS INT64)
WHERE ma.ma_status IN ('HOT', 'ACTIVE')
  AND c.PRODUCING_ADVISOR = TRUE
  AND UPPER(c.PRIMARY_FIRM_NAME) LIKE '%COMMONWEALTH%';

-- ============================================================================
-- VERIFICATION CHECKLIST
-- ============================================================================
-- 
-- Check | Query | Expected | Pass?
-- ------|-------|----------|-------
-- M&A firms exist | 6.1 | 50-90 firms | [ ]
-- Advisors at M&A firms | 6.2 | 1,000-5,000 | [ ]
-- Data types compatible | 6.3 | Both INT64 or castable | [ ]
-- JOIN works | 6.4 | >0 matches | [ ]
-- Tier logic works | 6.5 | Both tiers populated | [ ]
-- Commonwealth present | Bonus | >0 advisors | [ ]
--
-- ⚠️ DO NOT PROCEED if any check fails. Debug the issue first.
-- ============================================================================
