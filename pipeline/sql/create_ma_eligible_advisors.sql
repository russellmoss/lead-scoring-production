-- ============================================================================
-- STEP 7.1: CREATE M&A ELIGIBLE ADVISORS TABLE
-- ============================================================================
-- Purpose: Pre-build list of advisors at M&A target firms with tier assignments
-- Refresh: Monthly (or ad-hoc when major M&A news hits)
-- Dependencies: active_ma_target_firms, ria_contacts_current, employment_history
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.ma_eligible_advisors` AS

WITH 
-- Get industry tenure for mid-career calculation
advisor_tenure AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE) as career_start_date,
        DATE_DIFF(CURRENT_DATE(), MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE), MONTH) as industry_tenure_months
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
    GROUP BY RIA_CONTACT_CRD_ID
),

-- Get M&A target firms with explicit casting
ma_firms AS (
    SELECT 
        SAFE_CAST(firm_crd AS INT64) as firm_crd,
        firm_name,
        ma_status,
        days_since_first_news,
        firm_employees
    FROM `savvy-gtm-analytics.ml_features.active_ma_target_firms`
    WHERE ma_status IN ('HOT', 'ACTIVE')
      AND firm_employees >= 10
),

-- Join advisors to M&A firms
ma_advisors AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        c.CONTACT_FIRST_NAME as first_name,
        c.CONTACT_LAST_NAME as last_name,
        c.EMAIL as email,
        COALESCE(c.MOBILE_PHONE_NUMBER, c.OFFICE_PHONE_NUMBER) as phone,
        c.PRIMARY_FIRM_NAME as firm_name,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
        c.TITLE_NAME as job_title,
        c.PRIMARY_FIRM_START_DATE as firm_start_date,
        ma.ma_status,
        ma.days_since_first_news,
        ma.firm_employees as ma_firm_size,
        COALESCE(adv_tenure.industry_tenure_months, 0) as industry_tenure_months,
        
        -- Senior title flag (expanded list)
        CASE WHEN (
            UPPER(c.TITLE_NAME) LIKE '%PRESIDENT%'
            OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%'
            OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%OWNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
            OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%MANAGING%'
        ) THEN 1 ELSE 0 END as is_senior_title,
        
        -- Mid-career flag (10-20 years = 120-240 months)
        CASE WHEN COALESCE(adv_tenure.industry_tenure_months, 0) BETWEEN 120 AND 240 
        THEN 1 ELSE 0 END as is_mid_career
        
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN ma_firms ma ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ma.firm_crd
    LEFT JOIN advisor_tenure adv_tenure ON c.RIA_CONTACT_CRD_ID = adv_tenure.crd
    WHERE COALESCE(LOWER(TRIM(CAST(c.PRODUCING_ADVISOR AS STRING))), '') = 'true'
      AND c.CONTACT_FIRST_NAME IS NOT NULL
      AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
      -- Title exclusions (same as main lead list)
      AND NOT (
          UPPER(c.TITLE_NAME) LIKE '%CHIEF FINANCIAL OFFICER%'
          OR UPPER(c.TITLE_NAME) LIKE '%CFO%'
          OR UPPER(c.TITLE_NAME) LIKE '%CHIEF INVESTMENT OFFICER%'
          OR UPPER(c.TITLE_NAME) LIKE '%CIO%'
          OR UPPER(c.TITLE_NAME) LIKE '%VICE PRESIDENT%'
          OR UPPER(c.TITLE_NAME) LIKE '%VP %'  -- VP with space to avoid false positives
      )
)

SELECT 
    crd,
    first_name,
    last_name,
    email,
    phone,
    firm_name,
    firm_crd,
    job_title,
    firm_start_date,
    ma_status,
    days_since_first_news,
    ma_firm_size,
    industry_tenure_months,
    is_senior_title,
    is_mid_career,
    
    -- Tier assignment
    CASE 
        WHEN is_senior_title = 1 OR is_mid_career = 1 
        THEN 'TIER_MA_ACTIVE_PRIME'
        ELSE 'TIER_MA_ACTIVE'
    END as ma_tier,
    
    -- Expected conversion rate
    CASE 
        WHEN is_senior_title = 1 OR is_mid_career = 1 
        THEN 0.09  -- ~9% for PRIME
        ELSE 0.054 -- ~5.4% for standard
    END as expected_conversion_rate,
    
    -- Expected lift vs baseline (3.82%)
    CASE 
        WHEN is_senior_title = 1 OR is_mid_career = 1 
        THEN 2.36
        ELSE 1.41
    END as expected_lift,
    
    -- Metadata
    CURRENT_TIMESTAMP as created_at,
    'V3.5.0' as model_version
    
FROM ma_advisors;

-- Log results
SELECT 
    '=== STEP 7.1 VERIFICATION: ma_eligible_advisors Table Created ===' as check_name,
    ma_tier,
    COUNT(*) as advisor_count,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_conv_pct,
    COUNT(DISTINCT firm_crd) as unique_firms
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_tier
ORDER BY ma_tier;
