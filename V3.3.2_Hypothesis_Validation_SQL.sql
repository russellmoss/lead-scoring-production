-- =============================================================================
-- V3.3.2 PORTABLE BOOK HYPOTHESIS VALIDATION: PHASE 2
-- =============================================================================
-- 
-- PURPOSE:
-- This script validates 4 additional "portable book" signals identified after
-- the V3.3.1 analysis. These signals aim to identify advisors who are motivated
-- to move AND have books that can actually transfer with them.
--
-- BACKGROUND:
-- V3.3.1 validated that Low Discretionary (<50%) is a strong EXCLUSION signal (0.34x).
-- We also discovered that Rainmaker titles (Founders/Partners) convert WORSE (0.58x).
-- This Phase 2 analysis tests the INVERSE of the Rainmaker finding (low ownership)
-- plus 3 additional structural signals.
--
-- HYPOTHESES TO TEST:
-- 
-- 1. LOW OWNERSHIP PERCENTAGE (<5%)
--    Theory: Advisors with low/no equity stake are "producers without upside."
--    They do the work but don't share in firm equity - highly motivated to move.
--    This is the INVERSE of our failed Rainmaker hypothesis.
--    Expected: High producers with <5% ownership should convert BETTER.
--
-- 2. AVERAGE ACCOUNT SIZE (HNW PROXY)
--    Theory: High-net-worth clients ($1M+ avg) follow their advisor personally.
--    Mass affluent clients (<$250K avg) follow the brand/firm.
--    Since REP_AUM is 99% null, we use FIRM_AUM / TOTAL_ACCOUNTS as proxy.
--    Expected: Advisors at firms with higher avg account size convert better.
--
-- 3. SMA/INVESTMENT STYLE
--    Theory: Advisors who use Separately Managed Accounts (SMAs) or manage
--    individual securities have "unique IP" - their portfolio construction
--    expertise is portable. Advisors using only pooled vehicles (mutual funds,
--    ETFs) rely on firm model portfolios - less differentiated, less portable.
--    Expected: SMA/Direct Securities users convert better than pooled-only.
--
-- 4. CUSTODIAN ANALYSIS (Data Quality Fix)
--    Theory: Third-party custodians (Schwab, Fidelity, Pershing) = unbundled
--    assets. If advisor moves to another firm using same custodian, client
--    paperwork is minimal (negative consent). We had 0 matches in V3.3.1 due
--    to data quality issues - this diagnoses and fixes the pattern matching.
--    Expected: Advisors at firms with portable custodians convert better.
--
-- BASELINE CONVERSION RATE: 3.82%
--
-- VALIDATION CRITERIA:
-- - Lift >= 1.5x baseline to be considered significant
-- - Sample size >= 50 leads for statistical power
-- - 95% CI should not overlap with baseline
--
-- =============================================================================
-- INSTRUCTIONS FOR CURSOR.AI:
-- =============================================================================
-- 1. Run each section in order (diagnostics first, then validations)
-- 2. Record the results of each query
-- 3. Generate a summary report with:
--    - Conversion rate and lift for each signal
--    - Sample sizes and statistical significance
--    - Recommendations (IMPLEMENT / DO NOT IMPLEMENT / NEEDS MORE DATA)
-- 4. Flag any data quality issues discovered
-- 5. Identify the most promising signals for V3.3.2 implementation
-- =============================================================================


-- =============================================================================
-- SECTION 0: DATA QUALITY DIAGNOSTICS
-- =============================================================================
-- Run these FIRST to understand data coverage and quality before validation.
-- These queries check what data we actually have available.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- DIAGNOSTIC 0.1: OWNERSHIP PERCENTAGE DATA QUALITY
-- -----------------------------------------------------------------------------
-- Purpose: Understand what values exist in CONTACT_OWNERSHIP_PERCENTAGE field
-- Expected: String field with values like "0", "5", "10", "25-50", etc.
-- Coverage expectation: ~95% based on data dictionary
-- -----------------------------------------------------------------------------

SELECT 
    'DIAGNOSTIC 0.1: Ownership Percentage Distribution' as query_name,
    CONTACT_OWNERSHIP_PERCENTAGE as ownership_value,
    COUNT(*) as contact_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct_of_total
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
WHERE PRODUCING_ADVISOR = TRUE
GROUP BY CONTACT_OWNERSHIP_PERCENTAGE
ORDER BY contact_count DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- DIAGNOSTIC 0.2: AVERAGE ACCOUNT SIZE DATA QUALITY
-- -----------------------------------------------------------------------------
-- Purpose: Check coverage of TOTAL_AUM and TOTAL_ACCOUNTS fields
-- We need both to calculate avg account size = TOTAL_AUM / TOTAL_ACCOUNTS
-- -----------------------------------------------------------------------------

SELECT 
    'DIAGNOSTIC 0.2: Account Size Data Coverage' as query_name,
    COUNT(*) as total_firms,
    COUNTIF(TOTAL_AUM IS NOT NULL AND TOTAL_AUM > 0) as has_aum,
    COUNTIF(TOTAL_ACCOUNTS IS NOT NULL AND TOTAL_ACCOUNTS > 0) as has_accounts,
    COUNTIF(TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0) as has_both,
    ROUND(COUNTIF(TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0) / COUNT(*) * 100, 2) as both_coverage_pct
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`;


-- -----------------------------------------------------------------------------
-- DIAGNOSTIC 0.3: INVESTMENTS_UTILIZED DATA QUALITY
-- -----------------------------------------------------------------------------
-- Purpose: See what investment types are actually stored in this field
-- Field is STRING containing JSON array format per data dictionary
-- -----------------------------------------------------------------------------

SELECT 
    'DIAGNOSTIC 0.3: Investment Types Distribution' as query_name,
    CASE 
        WHEN INVESTMENTS_UTILIZED LIKE '%Separately Managed Accounts%' THEN 'Has SMAs'
        ELSE 'No SMAs'
    END as has_smas,
    CASE 
        WHEN INVESTMENTS_UTILIZED LIKE '%Individual Stocks%' 
             OR INVESTMENTS_UTILIZED LIKE '%Individual Bonds%' THEN 'Has Direct Securities'
        ELSE 'No Direct Securities'
    END as has_direct,
    CASE 
        WHEN INVESTMENTS_UTILIZED LIKE '%Mutual Funds%' THEN 'Has Mutual Funds'
        ELSE 'No Mutual Funds'
    END as has_mf,
    CASE 
        WHEN INVESTMENTS_UTILIZED LIKE '%ETF%' THEN 'Has ETFs'
        ELSE 'No ETFs'
    END as has_etfs,
    COUNT(*) as firm_count
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
WHERE INVESTMENTS_UTILIZED IS NOT NULL
GROUP BY 1, 2, 3, 4
ORDER BY firm_count DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- DIAGNOSTIC 0.4: CUSTODIAN DATA QUALITY (Critical - we had 0 matches before)
-- -----------------------------------------------------------------------------
-- Purpose: See ACTUAL custodian names stored in the field
-- This will help us fix the pattern matching that failed in V3.3.1
-- -----------------------------------------------------------------------------

SELECT 
    'DIAGNOSTIC 0.4: Custodian Names (Top 30)' as query_name,
    CUSTODIAN_PRIMARY_BUSINESS_NAME as custodian_name,
    COUNT(*) as firm_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct_of_total
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
WHERE CUSTODIAN_PRIMARY_BUSINESS_NAME IS NOT NULL
GROUP BY CUSTODIAN_PRIMARY_BUSINESS_NAME
ORDER BY firm_count DESC
LIMIT 30;


-- -----------------------------------------------------------------------------
-- DIAGNOSTIC 0.5: CUSTODIAN PORTABLE PATTERN SEARCH
-- -----------------------------------------------------------------------------
-- Purpose: Search for Schwab/Fidelity/Pershing with various patterns
-- This helps us understand why we got 0 matches in V3.3.1
-- -----------------------------------------------------------------------------

SELECT 
    'DIAGNOSTIC 0.5: Portable Custodian Pattern Search' as query_name,
    CASE 
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' THEN 'Schwab Match'
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%' THEN 'Charles Match'
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%' THEN 'Fidelity Match'
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%' THEN 'Pershing Match'
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%TD AMER%' THEN 'TD Ameritrade Match'
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%NATIONAL%' THEN 'National Match'
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%RAYMOND%' THEN 'Raymond James Match'
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%LPL%' THEN 'LPL Match'
        ELSE 'Other/No Match'
    END as custodian_pattern,
    COUNT(*) as firm_count
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
WHERE CUSTODIAN_PRIMARY_BUSINESS_NAME IS NOT NULL
GROUP BY 1
ORDER BY firm_count DESC;


-- =============================================================================
-- SECTION 1: HYPOTHESIS 1 - LOW OWNERSHIP PERCENTAGE
-- =============================================================================
-- 
-- THEORY:
-- Our V3.3.1 analysis found Rainmaker titles (Founders/Partners) convert WORSE
-- at 0.58x baseline. Why? They're equity-locked, already successful, planning
-- succession not growth.
--
-- The INVERSE should be true: Advisors with LOW or NO ownership stake are:
-- - "Producers without upside" - they generate revenue but don't share equity
-- - Highly motivated to move where they CAN get ownership/better payout
-- - Not locked by partnership agreements or golden handcuffs
--
-- EXPECTED OUTCOME:
-- - 0% ownership: Should convert BETTER than baseline
-- - <5% ownership: Should convert BETTER than baseline  
-- - 25%+ ownership: Should convert WORSE (confirms Rainmaker finding)
--
-- =============================================================================


-- -----------------------------------------------------------------------------
-- VALIDATION 1.1: OWNERSHIP PERCENTAGE VS CONVERSION
-- -----------------------------------------------------------------------------
-- Purpose: Test if low ownership correlates with higher conversion
-- This is the CORE validation for Hypothesis 1
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.CONTACT_OWNERSHIP_PERCENTAGE,
        c.TITLE_NAME
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
)
SELECT 
    'VALIDATION 1.1: Ownership Percentage vs Conversion' as query_name,
    CASE 
        WHEN CONTACT_OWNERSHIP_PERCENTAGE IS NULL THEN '1. Unknown/NULL'
        WHEN CONTACT_OWNERSHIP_PERCENTAGE IN ('0', '0%', 'None', '') THEN '2. No Ownership (0%)'
        WHEN CONTACT_OWNERSHIP_PERCENTAGE IN ('Less than 5%', '<5%', '1', '2', '3', '4', '5') THEN '3. Minimal (<5%)'
        WHEN CONTACT_OWNERSHIP_PERCENTAGE IN ('5-10%', '5', '6', '7', '8', '9', '10') THEN '4. Low (5-10%)'
        WHEN CONTACT_OWNERSHIP_PERCENTAGE IN ('10-25%', '11-25%', '15', '20', '25') THEN '5. Moderate (10-25%)'
        WHEN CONTACT_OWNERSHIP_PERCENTAGE IN ('25-50%', '26-50%', '30', '40', '50') THEN '6. Significant (25-50%)'
        WHEN CONTACT_OWNERSHIP_PERCENTAGE IN ('50-75%', '51-75%', '60', '70', '75') THEN '7. Majority (50-75%)'
        WHEN CONTACT_OWNERSHIP_PERCENTAGE IN ('75-100%', '>75%', '80', '90', '100', 'Over 75%') THEN '8. Owner (75%+)'
        ELSE '9. Other: ' || COALESCE(CONTACT_OWNERSHIP_PERCENTAGE, 'NULL')
    END as ownership_bucket,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline,
    ROUND(1.96 * SQRT(AVG(converted) * (1 - AVG(converted)) / COUNT(*)) * 100, 2) as margin_of_error_pct,
    -- 95% Confidence Interval
    ROUND((AVG(converted) - 1.96 * SQRT(AVG(converted) * (1 - AVG(converted)) / COUNT(*))) * 100, 2) as ci_lower_pct,
    ROUND((AVG(converted) + 1.96 * SQRT(AVG(converted) * (1 - AVG(converted)) / COUNT(*))) * 100, 2) as ci_upper_pct
FROM historical_leads
GROUP BY ownership_bucket
HAVING COUNT(*) >= 10  -- Minimum sample size for reporting
ORDER BY ownership_bucket;


-- -----------------------------------------------------------------------------
-- VALIDATION 1.2: SIMPLIFIED OWNERSHIP BUCKETS (For Implementation)
-- -----------------------------------------------------------------------------
-- Purpose: Simpler bucketing for potential V3.3.2 implementation
-- Groups into: No Ownership, Low (<25%), High (25%+)
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.CONTACT_OWNERSHIP_PERCENTAGE
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
parsed_ownership AS (
    SELECT 
        *,
        CASE 
            WHEN CONTACT_OWNERSHIP_PERCENTAGE IS NULL THEN -1  -- Unknown
            WHEN CONTACT_OWNERSHIP_PERCENTAGE IN ('0', '0%', 'None', '') THEN 0
            WHEN CONTACT_OWNERSHIP_PERCENTAGE LIKE '%Less than 5%' THEN 2.5
            WHEN CONTACT_OWNERSHIP_PERCENTAGE LIKE '%5-10%' THEN 7.5
            WHEN CONTACT_OWNERSHIP_PERCENTAGE LIKE '%10-25%' OR CONTACT_OWNERSHIP_PERCENTAGE LIKE '%11-25%' THEN 17.5
            WHEN CONTACT_OWNERSHIP_PERCENTAGE LIKE '%25-50%' OR CONTACT_OWNERSHIP_PERCENTAGE LIKE '%26-50%' THEN 37.5
            WHEN CONTACT_OWNERSHIP_PERCENTAGE LIKE '%50-75%' OR CONTACT_OWNERSHIP_PERCENTAGE LIKE '%51-75%' THEN 62.5
            WHEN CONTACT_OWNERSHIP_PERCENTAGE LIKE '%75-100%' OR CONTACT_OWNERSHIP_PERCENTAGE LIKE '%Over 75%' THEN 87.5
            ELSE -1  -- Unparseable
        END as ownership_pct_numeric
    FROM historical_leads
)
SELECT 
    'VALIDATION 1.2: Simplified Ownership Buckets' as query_name,
    CASE 
        WHEN ownership_pct_numeric < 0 THEN 'Unknown'
        WHEN ownership_pct_numeric = 0 THEN 'No Ownership (0%)'
        WHEN ownership_pct_numeric < 25 THEN 'Low Ownership (<25%)'
        ELSE 'High Ownership (25%+)'
    END as ownership_tier,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM parsed_ownership
GROUP BY 1
ORDER BY conversion_rate_pct DESC;


-- =============================================================================
-- SECTION 2: HYPOTHESIS 2 - AVERAGE ACCOUNT SIZE (HNW PROXY)
-- =============================================================================
--
-- THEORY:
-- High-net-worth clients ($1M+ average account) have personal relationships
-- with their advisor. They chose the PERSON, not the firm. When the advisor
-- moves, they follow.
--
-- Mass affluent clients (<$250K average) often chose the BRAND (Fidelity,
-- Schwab, etc.) and may not even know their advisor's name. They don't follow.
--
-- Since REP_AUM is 99% null, we use FIRM-LEVEL proxy:
-- Average Account Size = TOTAL_AUM / TOTAL_ACCOUNTS
--
-- EXPECTED OUTCOME:
-- - Ultra-HNW ($5M+ avg): Highest conversion - personal relationships
-- - HNW ($1-5M avg): High conversion
-- - Affluent ($250K-1M avg): Moderate conversion
-- - Mass Affluent (<$250K avg): Lower conversion - brand-loyal clients
--
-- =============================================================================


-- -----------------------------------------------------------------------------
-- VALIDATION 2.1: AVERAGE ACCOUNT SIZE VS CONVERSION
-- -----------------------------------------------------------------------------
-- Purpose: Test if firms with higher avg account size have better conversion
-- This uses firm-level data as proxy for advisor's client profile
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
firm_account_size AS (
    SELECT 
        CRD_ID as firm_crd,
        TOTAL_AUM,
        TOTAL_ACCOUNTS,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
)
SELECT 
    'VALIDATION 2.1: Average Account Size vs Conversion' as query_name,
    CASE 
        WHEN fas.avg_account_size IS NULL THEN '0. Unknown'
        WHEN fas.avg_account_size >= 5000000 THEN '1. Ultra-HNW ($5M+ avg)'
        WHEN fas.avg_account_size >= 1000000 THEN '2. HNW ($1-5M avg)'
        WHEN fas.avg_account_size >= 500000 THEN '3. High Affluent ($500K-1M avg)'
        WHEN fas.avg_account_size >= 250000 THEN '4. Affluent ($250-500K avg)'
        WHEN fas.avg_account_size >= 100000 THEN '5. Mass Affluent ($100-250K avg)'
        ELSE '6. Retail (<$100K avg)'
    END as client_tier,
    COUNT(*) as leads,
    SUM(hl.converted) as conversions,
    ROUND(AVG(hl.converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(hl.converted) / 0.0382, 2) as lift_vs_baseline,
    ROUND(AVG(fas.avg_account_size) / 1000000, 2) as avg_acct_size_millions,
    ROUND(1.96 * SQRT(AVG(hl.converted) * (1 - AVG(hl.converted)) / COUNT(*)) * 100, 2) as margin_of_error_pct
FROM historical_leads hl
LEFT JOIN firm_account_size fas ON hl.firm_crd = fas.firm_crd
GROUP BY 1
HAVING COUNT(*) >= 20
ORDER BY client_tier;


-- -----------------------------------------------------------------------------
-- VALIDATION 2.2: AVERAGE ACCOUNT SIZE - SIMPLIFIED FOR IMPLEMENTATION
-- -----------------------------------------------------------------------------
-- Purpose: Binary split for easier implementation
-- Above/Below $500K average account size
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
firm_account_size AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
)
SELECT 
    'VALIDATION 2.2: HNW Binary Split' as query_name,
    CASE 
        WHEN fas.avg_account_size IS NULL THEN 'Unknown'
        WHEN fas.avg_account_size >= 500000 THEN 'HNW Focused ($500K+ avg)'
        ELSE 'Mass Market (<$500K avg)'
    END as client_focus,
    COUNT(*) as leads,
    SUM(hl.converted) as conversions,
    ROUND(AVG(hl.converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(hl.converted) / 0.0382, 2) as lift_vs_baseline
FROM historical_leads hl
LEFT JOIN firm_account_size fas ON hl.firm_crd = fas.firm_crd
GROUP BY 1
ORDER BY conversion_rate_pct DESC;


-- =============================================================================
-- SECTION 3: HYPOTHESIS 3 - SMA/INVESTMENT STYLE
-- =============================================================================
--
-- THEORY:
-- Advisors who manage Separately Managed Accounts (SMAs) or individual
-- securities have "unique IP" - their portfolio construction methodology
-- is their intellectual property and is fully portable.
--
-- Advisors who only use pooled vehicles (mutual funds, ETFs) often rely on
-- the firm's model portfolios. The "secret sauce" belongs to the firm, not
-- the advisor. Less differentiated = less portable expertise.
--
-- EXPECTED OUTCOME:
-- - SMA/Direct Securities users: Higher conversion (portable expertise)
-- - Pooled-only users: Lower conversion (firm-dependent methodology)
--
-- DATA SOURCE: ria_firms_current.INVESTMENTS_UTILIZED
-- Note: This is a STRING field containing JSON array format
--
-- =============================================================================


-- -----------------------------------------------------------------------------
-- VALIDATION 3.1: INVESTMENT STYLE VS CONVERSION
-- -----------------------------------------------------------------------------
-- Purpose: Test if SMA/Direct Securities correlates with higher conversion
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
firm_investments AS (
    SELECT 
        CRD_ID as firm_crd,
        INVESTMENTS_UTILIZED,
        -- SMA flag
        CASE WHEN INVESTMENTS_UTILIZED LIKE '%Separately Managed Accounts%' 
             THEN 1 ELSE 0 END as uses_sma,
        -- Direct securities flag
        CASE WHEN INVESTMENTS_UTILIZED LIKE '%Individual Stocks%' 
             OR INVESTMENTS_UTILIZED LIKE '%Individual Bonds%' 
             THEN 1 ELSE 0 END as uses_direct_securities,
        -- Pooled only flag
        CASE WHEN (INVESTMENTS_UTILIZED LIKE '%Mutual Funds%' 
                   OR INVESTMENTS_UTILIZED LIKE '%ETF%')
             AND INVESTMENTS_UTILIZED NOT LIKE '%Separately Managed%'
             AND INVESTMENTS_UTILIZED NOT LIKE '%Individual Stocks%'
             AND INVESTMENTS_UTILIZED NOT LIKE '%Individual Bonds%'
             THEN 1 ELSE 0 END as pooled_only
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE INVESTMENTS_UTILIZED IS NOT NULL
)
SELECT 
    'VALIDATION 3.1: Investment Style vs Conversion' as query_name,
    CASE 
        WHEN fi.INVESTMENTS_UTILIZED IS NULL THEN '0. Unknown'
        WHEN fi.uses_sma = 1 THEN '1. Uses SMAs (Portable IP)'
        WHEN fi.uses_direct_securities = 1 THEN '2. Direct Securities (Portable IP)'
        WHEN fi.pooled_only = 1 THEN '3. Pooled Vehicles Only (Firm Dependent)'
        ELSE '4. Other/Mixed'
    END as investment_style,
    COUNT(*) as leads,
    SUM(hl.converted) as conversions,
    ROUND(AVG(hl.converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(hl.converted) / 0.0382, 2) as lift_vs_baseline,
    ROUND(1.96 * SQRT(AVG(hl.converted) * (1 - AVG(hl.converted)) / COUNT(*)) * 100, 2) as margin_of_error_pct
FROM historical_leads hl
LEFT JOIN firm_investments fi ON hl.firm_crd = fi.firm_crd
GROUP BY 1
HAVING COUNT(*) >= 20
ORDER BY investment_style;


-- -----------------------------------------------------------------------------
-- VALIDATION 3.2: SMA BINARY SIGNAL
-- -----------------------------------------------------------------------------
-- Purpose: Simple binary test - does firm use SMAs or not?
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
firm_sma AS (
    SELECT 
        CRD_ID as firm_crd,
        CASE WHEN INVESTMENTS_UTILIZED LIKE '%Separately Managed Accounts%' 
             THEN 'Uses SMAs' ELSE 'No SMAs' END as sma_status
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
)
SELECT 
    'VALIDATION 3.2: SMA Binary Signal' as query_name,
    COALESCE(fs.sma_status, 'Unknown') as sma_usage,
    COUNT(*) as leads,
    SUM(hl.converted) as conversions,
    ROUND(AVG(hl.converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(hl.converted) / 0.0382, 2) as lift_vs_baseline
FROM historical_leads hl
LEFT JOIN firm_sma fs ON hl.firm_crd = fs.firm_crd
GROUP BY 1
ORDER BY conversion_rate_pct DESC;


-- =============================================================================
-- SECTION 4: HYPOTHESIS 4 - CUSTODIAN ANALYSIS (Data Quality Fix)
-- =============================================================================
--
-- THEORY:
-- Advisors at firms using third-party custodians (Schwab, Fidelity, Pershing)
-- have "unbundled" assets. If they move to another firm using the SAME
-- custodian, client transfer is simple (often just a "negative consent" letter).
--
-- Advisors at wirehouses where the bank IS the custodian face much higher
-- friction - full account transfers, new paperwork, potential tax events.
--
-- V3.3.1 ISSUE: We got 0 matches for portable custodians. This section
-- first diagnoses the data, then attempts proper pattern matching.
--
-- EXPECTED OUTCOME:
-- - Third-party custodian (Schwab/Fidelity/Pershing): Higher conversion
-- - Self-custodied/Wirehouse: Lower conversion (higher friction)
--
-- =============================================================================


-- -----------------------------------------------------------------------------
-- VALIDATION 4.1: CUSTODIAN CONVERSION ANALYSIS (With Fixed Patterns)
-- -----------------------------------------------------------------------------
-- Purpose: Test custodian signal with improved pattern matching
-- Uses UPPER() and broader patterns based on Diagnostic 0.4 results
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
firm_custodian AS (
    SELECT 
        CRD_ID as firm_crd,
        CUSTODIAN_PRIMARY_BUSINESS_NAME as custodian,
        CASE 
            -- Portable custodians (third-party, RIA-friendly)
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' THEN 'Portable: Schwab'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%' THEN 'Portable: Schwab'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%' THEN 'Portable: Fidelity'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%' THEN 'Portable: Pershing'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%TD AMER%' THEN 'Portable: TD Ameritrade'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%NATIONAL FINANCIAL%' THEN 'Portable: NFS (Fidelity)'
            -- Wirehouse/Bank custodians (self-custodied, high friction)
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%MERRILL%' THEN 'Wirehouse: Merrill'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%MORGAN STANLEY%' THEN 'Wirehouse: Morgan Stanley'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%UBS%' THEN 'Wirehouse: UBS'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%WELLS FARGO%' THEN 'Wirehouse: Wells Fargo'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%RAYMOND JAMES%' THEN 'IBD: Raymond James'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%LPL%' THEN 'IBD: LPL'
            WHEN CUSTODIAN_PRIMARY_BUSINESS_NAME IS NULL THEN 'Unknown'
            ELSE 'Other'
        END as custodian_type
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
)
SELECT 
    'VALIDATION 4.1: Custodian Type vs Conversion' as query_name,
    fc.custodian_type,
    COUNT(*) as leads,
    SUM(hl.converted) as conversions,
    ROUND(AVG(hl.converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(hl.converted) / 0.0382, 2) as lift_vs_baseline,
    ROUND(1.96 * SQRT(AVG(hl.converted) * (1 - AVG(hl.converted)) / COUNT(*)) * 100, 2) as margin_of_error_pct
FROM historical_leads hl
LEFT JOIN firm_custodian fc ON hl.firm_crd = fc.firm_crd
GROUP BY fc.custodian_type
HAVING COUNT(*) >= 10
ORDER BY conversion_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- VALIDATION 4.2: PORTABLE VS NON-PORTABLE CUSTODIAN (Binary)
-- -----------------------------------------------------------------------------
-- Purpose: Simplified binary split for implementation
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
firm_custodian AS (
    SELECT 
        CRD_ID as firm_crd,
        CASE 
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                 OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%'
                 OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
                 OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
                 OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%TD AMER%'
                 OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%NATIONAL FINANCIAL%'
            THEN 'Portable Custodian'
            WHEN CUSTODIAN_PRIMARY_BUSINESS_NAME IS NULL THEN 'Unknown'
            ELSE 'Other/Non-Portable'
        END as custodian_portability
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
)
SELECT 
    'VALIDATION 4.2: Custodian Portability Binary' as query_name,
    fc.custodian_portability,
    COUNT(*) as leads,
    SUM(hl.converted) as conversions,
    ROUND(AVG(hl.converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(hl.converted) / 0.0382, 2) as lift_vs_baseline
FROM historical_leads hl
LEFT JOIN firm_custodian fc ON hl.firm_crd = fc.firm_crd
GROUP BY 1
ORDER BY conversion_rate_pct DESC;


-- =============================================================================
-- SECTION 5: INTERACTION EFFECTS
-- =============================================================================
--
-- PURPOSE:
-- Test combinations of signals to find "super-segments" with highest conversion.
-- The most powerful predictions often come from combining multiple signals.
--
-- COMBINATIONS TO TEST:
-- 5.1: Low Ownership + Low Discretionary exclusion (should AMPLIFY)
-- 5.2: Low Ownership + HNW Focus (motivated producer + portable clients)
-- 5.3: Low Ownership + Portable Custodian (motivated + easy mechanics)
-- 5.4: Ultimate Portability Score (all signals combined)
--
-- =============================================================================


-- -----------------------------------------------------------------------------
-- VALIDATION 5.1: LOW OWNERSHIP + HIGH DISCRETIONARY
-- -----------------------------------------------------------------------------
-- Purpose: Test if low ownership at high-discretionary firms is extra predictive
-- Logic: Motivated producer (low ownership) + portable book (high discretionary)
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.CONTACT_OWNERSHIP_PERCENTAGE
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
firm_disc AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) as disc_ratio
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),
combined AS (
    SELECT 
        hl.*,
        fd.disc_ratio,
        CASE 
            WHEN hl.CONTACT_OWNERSHIP_PERCENTAGE IN ('0', '0%', 'None', '', 'Less than 5%', '<5%') 
            THEN 'Low Ownership'
            ELSE 'Has Ownership'
        END as ownership_status,
        CASE 
            WHEN fd.disc_ratio >= 0.80 THEN 'High Discretionary'
            WHEN fd.disc_ratio < 0.50 THEN 'Low Discretionary'
            ELSE 'Moderate/Unknown'
        END as disc_status
    FROM historical_leads hl
    LEFT JOIN firm_disc fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    'VALIDATION 5.1: Low Ownership + High Discretionary' as query_name,
    CONCAT(ownership_status, ' + ', disc_status) as combination,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM combined
GROUP BY ownership_status, disc_status
HAVING COUNT(*) >= 20
ORDER BY conversion_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- VALIDATION 5.2: LOW OWNERSHIP + HNW FOCUS
-- -----------------------------------------------------------------------------
-- Purpose: Test if low ownership at HNW-focused firms is extra predictive
-- Logic: Motivated producer + clients who follow advisor (not brand)
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.CONTACT_OWNERSHIP_PERCENTAGE
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
firm_hnw AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_ACCOUNTS > 0
),
combined AS (
    SELECT 
        hl.*,
        fh.avg_account_size,
        CASE 
            WHEN hl.CONTACT_OWNERSHIP_PERCENTAGE IN ('0', '0%', 'None', '', 'Less than 5%', '<5%') 
            THEN 'Low Ownership'
            ELSE 'Has Ownership'
        END as ownership_status,
        CASE 
            WHEN fh.avg_account_size >= 500000 THEN 'HNW Focus'
            WHEN fh.avg_account_size IS NULL THEN 'Unknown'
            ELSE 'Mass Market'
        END as client_focus
    FROM historical_leads hl
    LEFT JOIN firm_hnw fh ON hl.firm_crd = fh.firm_crd
)
SELECT 
    'VALIDATION 5.2: Low Ownership + HNW Focus' as query_name,
    CONCAT(ownership_status, ' + ', client_focus) as combination,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM combined
GROUP BY ownership_status, client_focus
HAVING COUNT(*) >= 20
ORDER BY conversion_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- VALIDATION 5.3: ULTIMATE PORTABILITY SCORE
-- -----------------------------------------------------------------------------
-- Purpose: Combine all validated signals into a composite score
-- Count how many "portable book" signals each lead has
-- -----------------------------------------------------------------------------

WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.CONTACT_OWNERSHIP_PERCENTAGE,
        c.REP_LICENSES
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
firm_signals AS (
    SELECT 
        CRD_ID as firm_crd,
        -- Discretionary signal (V3.3.1 validated)
        CASE WHEN SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) >= 0.80 THEN 1 ELSE 0 END as is_high_disc,
        -- HNW focus signal
        CASE WHEN SAFE_DIVIDE(TOTAL_AUM, NULLIF(TOTAL_ACCOUNTS, 0)) >= 500000 THEN 1 ELSE 0 END as is_hnw_focus,
        -- SMA usage signal
        CASE WHEN INVESTMENTS_UTILIZED LIKE '%Separately Managed Accounts%' THEN 1 ELSE 0 END as uses_sma,
        -- Portable custodian signal
        CASE WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
             THEN 1 ELSE 0 END as portable_custodian
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),
scored_leads AS (
    SELECT 
        hl.*,
        fs.is_high_disc,
        fs.is_hnw_focus,
        fs.uses_sma,
        fs.portable_custodian,
        -- Ownership signal (from contact)
        CASE WHEN hl.CONTACT_OWNERSHIP_PERCENTAGE IN ('0', '0%', 'None', '', 'Less than 5%', '<5%') 
             THEN 1 ELSE 0 END as is_low_ownership,
        -- Series 65 only signal (V3.3.1 validated)
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' AND hl.REP_LICENSES NOT LIKE '%Series 7%'
             THEN 1 ELSE 0 END as is_series_65_only,
        -- Calculate portability score (0-6)
        (
            CASE WHEN SAFE_DIVIDE(fs.is_high_disc, 1) = 1 THEN 1 ELSE 0 END +
            COALESCE(fs.is_hnw_focus, 0) +
            COALESCE(fs.uses_sma, 0) +
            COALESCE(fs.portable_custodian, 0) +
            CASE WHEN hl.CONTACT_OWNERSHIP_PERCENTAGE IN ('0', '0%', 'None', '', 'Less than 5%', '<5%') THEN 1 ELSE 0 END +
            CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' AND hl.REP_LICENSES NOT LIKE '%Series 7%' THEN 1 ELSE 0 END
        ) as portability_score
    FROM historical_leads hl
    LEFT JOIN firm_signals fs ON hl.firm_crd = fs.firm_crd
)
SELECT 
    'VALIDATION 5.3: Ultimate Portability Score' as query_name,
    CASE 
        WHEN portability_score >= 4 THEN '4+ Signals (Ultra-Portable)'
        WHEN portability_score = 3 THEN '3 Signals (Highly Portable)'
        WHEN portability_score = 2 THEN '2 Signals (Moderately Portable)'
        WHEN portability_score = 1 THEN '1 Signal (Slightly Portable)'
        ELSE '0 Signals (Low Portability)'
    END as portability_tier,
    portability_score,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM scored_leads
GROUP BY portability_score
ORDER BY portability_score DESC;


-- =============================================================================
-- SECTION 6: DATA COVERAGE SUMMARY
-- =============================================================================
-- Purpose: Understand how many leads would be affected by each signal
-- This helps prioritize which signals to implement based on coverage
-- =============================================================================

SELECT 
    'COVERAGE SUMMARY' as query_name,
    COUNT(*) as total_leads,
    
    -- Ownership coverage
    COUNTIF(c.CONTACT_OWNERSHIP_PERCENTAGE IS NOT NULL) as has_ownership_data,
    ROUND(COUNTIF(c.CONTACT_OWNERSHIP_PERCENTAGE IS NOT NULL) / COUNT(*) * 100, 2) as ownership_coverage_pct,
    COUNTIF(c.CONTACT_OWNERSHIP_PERCENTAGE IN ('0', '0%', 'None', '', 'Less than 5%', '<5%')) as low_ownership_count,
    
    -- Account size coverage
    COUNTIF(f.TOTAL_AUM > 0 AND f.TOTAL_ACCOUNTS > 0) as has_account_size_data,
    ROUND(COUNTIF(f.TOTAL_AUM > 0 AND f.TOTAL_ACCOUNTS > 0) / COUNT(*) * 100, 2) as account_size_coverage_pct,
    COUNTIF(SAFE_DIVIDE(f.TOTAL_AUM, f.TOTAL_ACCOUNTS) >= 500000) as hnw_focus_count,
    
    -- Investment style coverage
    COUNTIF(f.INVESTMENTS_UTILIZED IS NOT NULL) as has_investment_data,
    ROUND(COUNTIF(f.INVESTMENTS_UTILIZED IS NOT NULL) / COUNT(*) * 100, 2) as investment_coverage_pct,
    COUNTIF(f.INVESTMENTS_UTILIZED LIKE '%Separately Managed Accounts%') as uses_sma_count,
    
    -- Custodian coverage
    COUNTIF(f.CUSTODIAN_PRIMARY_BUSINESS_NAME IS NOT NULL) as has_custodian_data,
    ROUND(COUNTIF(f.CUSTODIAN_PRIMARY_BUSINESS_NAME IS NOT NULL) / COUNT(*) * 100, 2) as custodian_coverage_pct,
    COUNTIF(
        UPPER(f.CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
        OR UPPER(f.CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
        OR UPPER(f.CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
    ) as portable_custodian_count
    
FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
    ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current` f 
    ON c.PRIMARY_FIRM = f.CRD_ID;


-- =============================================================================
-- END OF V3.3.2 HYPOTHESIS VALIDATION SCRIPT
-- =============================================================================
--
-- INSTRUCTIONS FOR CURSOR.AI REPORT GENERATION:
--
-- After running all queries, generate a report with these sections:
--
-- 1. EXECUTIVE SUMMARY
--    - Which hypotheses were VALIDATED (lift >= 1.5x, sample >= 50)
--    - Which hypotheses were INVALIDATED
--    - Recommended signals for V3.3.2 implementation
--
-- 2. HYPOTHESIS RESULTS TABLE
--    For each hypothesis, report:
--    - Best performing bucket
--    - Conversion rate and lift
--    - Sample size
--    - Statistical significance (CI doesn't overlap baseline)
--    - Recommendation: IMPLEMENT / DO NOT IMPLEMENT / NEEDS MORE DATA
--
-- 3. INTERACTION EFFECTS
--    - Which combinations showed strongest lift
--    - Recommended composite scoring approach
--
-- 4. DATA QUALITY FINDINGS
--    - Coverage percentages for each signal
--    - Any data quality issues discovered
--    - Custodian pattern matching results
--
-- 5. IMPLEMENTATION RECOMMENDATIONS
--    - Prioritized list of signals to add in V3.3.2
--    - SQL snippets for each signal
--    - Expected impact on lead pool
--
-- =============================================================================
