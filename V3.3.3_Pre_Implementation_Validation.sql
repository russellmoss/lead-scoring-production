-- =============================================================================
-- V3.3.3 PRE-IMPLEMENTATION VALIDATION
-- =============================================================================
-- 
-- PURPOSE:
-- 1. Validate T1B_PRIME overlap with existing T1A/T1B tiers
-- 2. Check if FIRM_START_DATE can be sourced for Succession Gap analysis
--
-- These validations must PASS before implementing V3.3.3 tiers.
--
-- =============================================================================


-- =============================================================================
-- SECTION 1: T1B_PRIME OVERLAP VALIDATION
-- =============================================================================
-- Question: Does T1B_PRIME overlap with T1A (CFP + Bleeding) or T1B (S65 + Bleeding)?
-- 
-- T1B_PRIME criteria:
-- - Series 65 Only (no Series 7)
-- - Portable Custodian (Schwab/Fidelity/Pershing)
-- - Small Firm (≤10 reps)
-- - Firm Bleeding (net_change ≤ -3)
--
-- T1A criteria:
-- - CFP credential
-- - Firm Bleeding (net_change ≤ -3)
--
-- T1B criteria:
-- - Series 65 Only (no Series 7)
-- - Firm Bleeding (net_change ≤ -3)
--
-- EXPECTED: T1B_PRIME should be a SUBSET of T1B (adds custodian + small firm filters)
-- =============================================================================

-- 1.1: CHECK TIER OVERLAP - HOW MANY LEADS QUALIFY FOR MULTIPLE TIERS?
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.CONTACT_BIO,
        c.TITLE_NAME,
        c.REP_LICENSES
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.firm_rep_count_at_contact
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        CASE WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
             THEN 1 ELSE 0 END as has_portable_custodian
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.firm_rep_count_at_contact,
        fd.has_portable_custodian,
        -- T1A: CFP + Bleeding
        CASE WHEN (hl.CONTACT_BIO LIKE '%CFP%' 
                   OR hl.CONTACT_BIO LIKE '%Certified Financial Planner%'
                   OR hl.TITLE_NAME LIKE '%CFP%')
                  AND lf.firm_net_change_12mo <= -3
             THEN 1 ELSE 0 END as qualifies_t1a,
        -- T1B: Series 65 Only + Bleeding
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' 
                  AND hl.REP_LICENSES NOT LIKE '%Series 7%'
                  AND lf.firm_net_change_12mo <= -3
             THEN 1 ELSE 0 END as qualifies_t1b,
        -- T1B_PRIME: S65 + Custodian + Small + Bleeding
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' 
                  AND hl.REP_LICENSES NOT LIKE '%Series 7%'
                  AND fd.has_portable_custodian = 1
                  AND lf.firm_rep_count_at_contact <= 10
                  AND lf.firm_net_change_12mo <= -3
             THEN 1 ELSE 0 END as qualifies_t1b_prime
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '1.1 TIER OVERLAP ANALYSIS' as query_name,
    -- T1A counts
    SUM(qualifies_t1a) as t1a_leads,
    -- T1B counts
    SUM(qualifies_t1b) as t1b_leads,
    -- T1B_PRIME counts
    SUM(qualifies_t1b_prime) as t1b_prime_leads,
    -- Overlap: T1A AND T1B_PRIME
    SUM(CASE WHEN qualifies_t1a = 1 AND qualifies_t1b_prime = 1 THEN 1 ELSE 0 END) as t1a_AND_t1b_prime,
    -- Overlap: T1B AND T1B_PRIME (expected: T1B_PRIME should be subset of T1B)
    SUM(CASE WHEN qualifies_t1b = 1 AND qualifies_t1b_prime = 1 THEN 1 ELSE 0 END) as t1b_AND_t1b_prime,
    -- T1B_PRIME exclusive (not in T1A or T1B) - should be 0 since T1B_PRIME requires S65 which is T1B base
    SUM(CASE WHEN qualifies_t1b_prime = 1 AND qualifies_t1a = 0 AND qualifies_t1b = 0 THEN 1 ELSE 0 END) as t1b_prime_exclusive
FROM analysis_base;


-- 1.2: DETAILED OVERLAP BREAKDOWN
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.CONTACT_BIO,
        c.TITLE_NAME,
        c.REP_LICENSES
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.firm_rep_count_at_contact
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        CASE WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
             THEN 1 ELSE 0 END as has_portable_custodian
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.firm_rep_count_at_contact,
        fd.has_portable_custodian,
        -- Has CFP
        CASE WHEN hl.CONTACT_BIO LIKE '%CFP%' 
                  OR hl.CONTACT_BIO LIKE '%Certified Financial Planner%'
                  OR hl.TITLE_NAME LIKE '%CFP%'
             THEN 1 ELSE 0 END as has_cfp,
        -- Has Series 65 Only
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' 
                  AND hl.REP_LICENSES NOT LIKE '%Series 7%'
             THEN 1 ELSE 0 END as has_series_65_only,
        -- Is Bleeding
        CASE WHEN lf.firm_net_change_12mo <= -3 THEN 1 ELSE 0 END as is_bleeding,
        -- Is Small Firm
        CASE WHEN lf.firm_rep_count_at_contact <= 10 THEN 1 ELSE 0 END as is_small_firm
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '1.2 DETAILED OVERLAP' as query_name,
    CASE 
        -- T1A only (CFP + Bleeding, no S65 only)
        WHEN has_cfp = 1 AND is_bleeding = 1 AND has_series_65_only = 0 
            THEN 'T1A Only (CFP + Bleeding)'
        -- T1A + T1B_PRIME (CFP + S65 + Custodian + Small + Bleeding)
        WHEN has_cfp = 1 AND has_series_65_only = 1 AND has_portable_custodian = 1 
             AND is_small_firm = 1 AND is_bleeding = 1
            THEN 'T1A + T1B_PRIME (Both)'
        -- T1A + T1B (CFP + S65 + Bleeding, missing custodian or small)
        WHEN has_cfp = 1 AND has_series_65_only = 1 AND is_bleeding = 1
            THEN 'T1A + T1B (CFP with S65)'
        -- T1B_PRIME only (S65 + Custodian + Small + Bleeding, no CFP)
        WHEN has_cfp = 0 AND has_series_65_only = 1 AND has_portable_custodian = 1 
             AND is_small_firm = 1 AND is_bleeding = 1
            THEN 'T1B_PRIME Only (no CFP)'
        -- T1B only (S65 + Bleeding, missing custodian or small)
        WHEN has_cfp = 0 AND has_series_65_only = 1 AND is_bleeding = 1
            THEN 'T1B Only (S65 + Bleeding)'
        ELSE 'Other'
    END as tier_assignment,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
WHERE is_bleeding = 1  -- Focus on bleeding firms only
  AND (has_cfp = 1 OR has_series_65_only = 1)  -- Must have at least one credential
GROUP BY tier_assignment
HAVING COUNT(*) >= 5
ORDER BY conv_rate_pct DESC;


-- 1.3: T1B_PRIME CONVERSION BY OVERLAP STATUS
-- This shows if T1B_PRIME leads that ALSO qualify for T1A convert differently
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.CONTACT_BIO,
        c.TITLE_NAME,
        c.REP_LICENSES
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.firm_rep_count_at_contact
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        CASE WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
             THEN 1 ELSE 0 END as has_portable_custodian
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.firm_rep_count_at_contact,
        fd.has_portable_custodian,
        -- Has CFP
        CASE WHEN hl.CONTACT_BIO LIKE '%CFP%' 
                  OR hl.CONTACT_BIO LIKE '%Certified Financial Planner%'
                  OR hl.TITLE_NAME LIKE '%CFP%'
             THEN 1 ELSE 0 END as has_cfp,
        -- Has Series 65 Only
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' 
                  AND hl.REP_LICENSES NOT LIKE '%Series 7%'
             THEN 1 ELSE 0 END as has_series_65_only,
        -- Is Bleeding
        CASE WHEN lf.firm_net_change_12mo <= -3 THEN 1 ELSE 0 END as is_bleeding,
        -- Is Small Firm
        CASE WHEN lf.firm_rep_count_at_contact <= 10 THEN 1 ELSE 0 END as is_small_firm,
        -- Qualifies for T1B_PRIME
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' 
                  AND hl.REP_LICENSES NOT LIKE '%Series 7%'
                  AND fd.has_portable_custodian = 1
                  AND lf.firm_rep_count_at_contact <= 10
                  AND lf.firm_net_change_12mo <= -3
             THEN 1 ELSE 0 END as is_t1b_prime
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '1.3 T1B_PRIME OVERLAP IMPACT' as query_name,
    CASE 
        WHEN is_t1b_prime = 1 AND has_cfp = 1 THEN 'T1B_PRIME + CFP (would go to T1A first)'
        WHEN is_t1b_prime = 1 AND has_cfp = 0 THEN 'T1B_PRIME Only (unique segment)'
        ELSE 'Not T1B_PRIME'
    END as segment,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
WHERE is_t1b_prime = 1 OR (has_cfp = 1 AND is_bleeding = 1)
GROUP BY segment
ORDER BY conv_rate_pct DESC;


-- 1.4: RECOMMENDED TIER PRIORITY ORDER
-- If lead qualifies for multiple tiers, which tier should win?
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.CONTACT_BIO,
        c.TITLE_NAME,
        c.REP_LICENSES
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.firm_rep_count_at_contact
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        CASE WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
             THEN 1 ELSE 0 END as has_portable_custodian
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.firm_rep_count_at_contact,
        fd.has_portable_custodian,
        -- Has CFP
        CASE WHEN hl.CONTACT_BIO LIKE '%CFP%' 
                  OR hl.CONTACT_BIO LIKE '%Certified Financial Planner%'
                  OR hl.TITLE_NAME LIKE '%CFP%'
             THEN 1 ELSE 0 END as has_cfp,
        -- Has Series 65 Only
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' 
                  AND hl.REP_LICENSES NOT LIKE '%Series 7%'
             THEN 1 ELSE 0 END as has_series_65_only,
        -- Is Bleeding
        CASE WHEN lf.firm_net_change_12mo <= -3 THEN 1 ELSE 0 END as is_bleeding,
        -- Is Small Firm
        CASE WHEN lf.firm_rep_count_at_contact <= 10 THEN 1 ELSE 0 END as is_small_firm
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '1.4 TIER PRIORITY SIMULATION' as query_name,
    -- Assign tier based on priority order (highest conversion first)
    CASE 
        -- OPTION A: T1B_PRIME first (13.04% > 9.80%)
        WHEN has_series_65_only = 1 AND has_portable_custodian = 1 
             AND is_small_firm = 1 AND is_bleeding = 1
            THEN 'TIER_1B_PRIME_ZERO_FRICTION'
        -- Then T1A (CFP + Bleeding)
        WHEN has_cfp = 1 AND is_bleeding = 1
            THEN 'TIER_1A_CFP_BLEEDING'
        -- Then T1B (S65 + Bleeding)
        WHEN has_series_65_only = 1 AND is_bleeding = 1
            THEN 'TIER_1B_S65_BLEEDING'
        ELSE 'OTHER'
    END as assigned_tier,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY assigned_tier
HAVING COUNT(*) >= 5
ORDER BY conv_rate_pct DESC;


-- =============================================================================
-- SECTION 2: FIRM_START_DATE AVAILABILITY CHECK
-- =============================================================================
-- Question: Can we source FIRM_START_DATE for Succession Gap analysis?
-- We need to identify "aging firms" where principal has 20+ years tenure.
-- =============================================================================

-- 2.1: CHECK FIRM_START_DATE IN RIA_FIRMS_CURRENT
SELECT 
    '2.1 FIRM_START_DATE in ria_firms_current' as query_name,
    COUNT(*) as total_firms,
    COUNTIF(FIRM_START_DATE IS NOT NULL) as has_firm_start_date,
    ROUND(COUNTIF(FIRM_START_DATE IS NOT NULL) / COUNT(*) * 100, 2) as coverage_pct,
    MIN(FIRM_START_DATE) as earliest_date,
    MAX(FIRM_START_DATE) as latest_date
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`;


-- 2.2: CHECK ALTERNATIVE FIELDS FOR FIRM AGE
SELECT 
    '2.2 ALTERNATIVE FIRM AGE FIELDS' as query_name,
    COUNT(*) as total_firms,
    -- Check various date fields
    COUNTIF(FIRM_START_DATE IS NOT NULL) as has_firm_start_date,
    COUNTIF(SEC_REGISTRATION_DATE IS NOT NULL) as has_sec_reg_date,
    COUNTIF(STATE_REGISTRATION_DATE IS NOT NULL) as has_state_reg_date,
    COUNTIF(CREATED_AT IS NOT NULL) as has_created_at,
    COUNTIF(UPDATED_AT IS NOT NULL) as has_updated_at
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`;


-- 2.3: CHECK COLUMN NAMES FOR ANY DATE-RELATED FIELDS
-- This will help us find alternative sources for firm age
SELECT 
    '2.3 ALL COLUMN NAMES' as query_name,
    column_name,
    data_type
FROM `savvy-gtm-analytics.FinTrx_data_CA.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'ria_firms_current'
  AND (LOWER(column_name) LIKE '%date%' 
       OR LOWER(column_name) LIKE '%start%'
       OR LOWER(column_name) LIKE '%found%'
       OR LOWER(column_name) LIKE '%age%'
       OR LOWER(column_name) LIKE '%year%'
       OR LOWER(column_name) LIKE '%tenure%'
       OR LOWER(column_name) LIKE '%regist%')
ORDER BY column_name;


-- 2.4: IF SEC_REGISTRATION_DATE EXISTS, TEST IT AS PROXY FOR FIRM AGE
-- SEC registration date is often close to firm founding date for RIAs
SELECT 
    '2.4 SEC_REGISTRATION_DATE AS FIRM AGE PROXY' as query_name,
    CASE 
        WHEN SEC_REGISTRATION_DATE IS NULL THEN '0. Unknown'
        WHEN DATE_DIFF(CURRENT_DATE(), PARSE_DATE('%Y-%m-%d', SEC_REGISTRATION_DATE), MONTH) < 60 THEN '1. Young (<5yr)'
        WHEN DATE_DIFF(CURRENT_DATE(), PARSE_DATE('%Y-%m-%d', SEC_REGISTRATION_DATE), MONTH) < 120 THEN '2. Established (5-10yr)'
        WHEN DATE_DIFF(CURRENT_DATE(), PARSE_DATE('%Y-%m-%d', SEC_REGISTRATION_DATE), MONTH) < 180 THEN '3. Mature (10-15yr)'
        WHEN DATE_DIFF(CURRENT_DATE(), PARSE_DATE('%Y-%m-%d', SEC_REGISTRATION_DATE), MONTH) < 240 THEN '4. Senior (15-20yr)'
        WHEN DATE_DIFF(CURRENT_DATE(), PARSE_DATE('%Y-%m-%d', SEC_REGISTRATION_DATE), MONTH) < 300 THEN '5. Aging (20-25yr) ⭐'
        ELSE '6. Legacy (25+yr) ⭐'
    END as firm_age_bucket,
    COUNT(*) as firms,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct_of_total
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
GROUP BY firm_age_bucket
ORDER BY firm_age_bucket;


-- 2.5: IF SEC_REGISTRATION_DATE IS AVAILABLE, RUN SUCCESSION GAP VALIDATION
-- Test the T1G + Aging Firm hypothesis using SEC registration date
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.industry_tenure_months
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size,
        -- Use SEC registration date as proxy for firm age
        DATE_DIFF(CURRENT_DATE(), SAFE.PARSE_DATE('%Y-%m-%d', SEC_REGISTRATION_DATE), MONTH) as firm_age_months
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.industry_tenure_months,
        fd.avg_account_size,
        fd.firm_age_months,
        -- T1G criteria
        CASE WHEN lf.industry_tenure_months BETWEEN 60 AND 180
                  AND fd.avg_account_size >= 250000
                  AND lf.firm_net_change_12mo > -3
             THEN 1 ELSE 0 END as is_t1g,
        -- Aging firm (20+ years SEC registration)
        CASE WHEN fd.firm_age_months >= 240 THEN 1 ELSE 0 END as is_aging_firm
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '2.5 SUCCESSION GAP VALIDATION (SEC Date)' as query_name,
    CASE 
        WHEN is_t1g = 1 AND is_aging_firm = 1 THEN 'T1G + Aging Firm (SUCCESSION BLOCKED)'
        WHEN is_t1g = 1 AND is_aging_firm = 0 THEN 'T1G + Young/Mid Firm'
        WHEN is_t1g = 0 AND is_aging_firm = 1 THEN 'Non-T1G + Aging Firm'
        ELSE 'Non-T1G + Young/Mid Firm'
    END as segment,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY segment
HAVING COUNT(*) >= 10
ORDER BY conv_rate_pct DESC;


-- 2.6: ALTERNATIVE - USE PRINCIPAL'S INDUSTRY TENURE AS PROXY
-- If firm date unavailable, we can look at the longest-tenured person at the firm
-- as a proxy for "aging principal"
WITH firm_principals AS (
    SELECT 
        PRIMARY_FIRM as firm_crd,
        MAX(
            DATE_DIFF(CURRENT_DATE(), SAFE.PARSE_DATE('%Y-%m-%d', FIRST_REGISTRATION_DATE), MONTH)
        ) as max_tenure_at_firm_months
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRODUCING_ADVISOR = TRUE
    GROUP BY PRIMARY_FIRM
),
historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.industry_tenure_months
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.industry_tenure_months,
        fd.avg_account_size,
        fp.max_tenure_at_firm_months,
        -- T1G criteria
        CASE WHEN lf.industry_tenure_months BETWEEN 60 AND 180
                  AND fd.avg_account_size >= 250000
                  AND lf.firm_net_change_12mo > -3
             THEN 1 ELSE 0 END as is_t1g,
        -- Firm has aging principal (20+ years)
        CASE WHEN fp.max_tenure_at_firm_months >= 240 THEN 1 ELSE 0 END as has_aging_principal
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
    LEFT JOIN firm_principals fp ON hl.firm_crd = fp.firm_crd
)
SELECT 
    '2.6 SUCCESSION GAP (Principal Tenure Proxy)' as query_name,
    CASE 
        WHEN is_t1g = 1 AND has_aging_principal = 1 THEN 'T1G + Aging Principal (SUCCESSION BLOCKED)'
        WHEN is_t1g = 1 AND has_aging_principal = 0 THEN 'T1G + Younger Principal'
        WHEN is_t1g = 0 AND has_aging_principal = 1 THEN 'Non-T1G + Aging Principal'
        ELSE 'Non-T1G + Younger Principal'
    END as segment,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY segment
HAVING COUNT(*) >= 10
ORDER BY conv_rate_pct DESC;


-- =============================================================================
-- SECTION 3: T1G_ENHANCED OVERLAP CHECK
-- =============================================================================
-- Question: Does T1G_ENHANCED ($500K-$2M) overlap with T1G ($250K+)?
-- Expected: T1G_ENHANCED should be a SUBSET of T1G leads
-- =============================================================================

-- 3.1: T1G vs T1G_ENHANCED COMPARISON
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.industry_tenure_months
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.industry_tenure_months,
        fd.avg_account_size,
        -- T1G criteria (original: $250K+)
        CASE WHEN lf.industry_tenure_months BETWEEN 60 AND 180
                  AND fd.avg_account_size >= 250000
                  AND lf.firm_net_change_12mo > -3
             THEN 1 ELSE 0 END as is_t1g_original,
        -- T1G_ENHANCED criteria ($500K-$2M)
        CASE WHEN lf.industry_tenure_months BETWEEN 60 AND 180
                  AND fd.avg_account_size BETWEEN 500000 AND 2000000
                  AND lf.firm_net_change_12mo > -3
             THEN 1 ELSE 0 END as is_t1g_enhanced
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '3.1 T1G vs T1G_ENHANCED COMPARISON' as query_name,
    CASE 
        WHEN is_t1g_enhanced = 1 THEN 'T1G_ENHANCED ($500K-$2M)'
        WHEN is_t1g_original = 1 THEN 'T1G Original (outside $500K-$2M)'
        ELSE 'Neither'
    END as segment,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY segment
HAVING COUNT(*) >= 10
ORDER BY conv_rate_pct DESC;


-- =============================================================================
-- SUMMARY: VALIDATION CHECKLIST
-- =============================================================================
-- 
-- CHECKLIST ITEMS:
-- 
-- 1. T1B_PRIME Overlap:
--    [ ] How many T1B_PRIME leads also qualify for T1A? → Assign to T1A first (higher CFP value)
--    [ ] How many T1B_PRIME leads are exclusive (no CFP)? → These go to T1B_PRIME
--    [ ] Recommended tier order: T1B_PRIME → T1A → T1B (or T1A → T1B_PRIME → T1B)
--
-- 2. FIRM_START_DATE Availability:
--    [ ] Is FIRM_START_DATE available? Coverage %?
--    [ ] Is SEC_REGISTRATION_DATE available as alternative? Coverage %?
--    [ ] Can we use max principal tenure as proxy?
--    [ ] Does Succession Gap hypothesis validate with available data?
--
-- 3. T1G_ENHANCED Overlap:
--    [ ] T1G_ENHANCED is subset of T1G (confirmed - just refined AUM range)
--    [ ] Conversion improvement from T1G to T1G_ENHANCED
--
-- =============================================================================
