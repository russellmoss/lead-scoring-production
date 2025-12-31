-- =============================================================================
-- PORTABLE BOOK HYPOTHESIS VALIDATION ANALYSIS
-- =============================================================================
-- Purpose: Validate 4 new hypotheses for portable book signals
-- Author: Data Science Team
-- Date: December 2025
-- 
-- Hypotheses:
--   1. Solo-Practitioner Proxy (firm_rep_count <= 3)
--   2. Discretionary AUM Ratio (>80% discretionary)
--   3. Custody Signal (Schwab, Fidelity, Pershing)
--   4. Advanced Title Filtering (Rainmaker vs Servicer)
--
-- Methodology: Join historical leads with outcomes, calculate conversion rates
-- =============================================================================

-- First, let's establish our baseline from historical data
-- Using your existing lead outcome data structure

-- =============================================================================
-- HYPOTHESIS 1: SOLO-PRACTITIONER PROXY
-- Theory: Advisors at firms with 1-3 reps OWN the book entirely
-- =============================================================================

WITH historical_leads AS (
    -- Replace with your actual historical leads table
    -- This assumes you have a table with lead_id, advisor_crd, firm_crd, contact_date, converted (0/1)
    SELECT 
        l.*,
        c.PRIMARY_FIRM,
        c.TITLE_NAME,
        c.REP_TYPE,
        c.PRODUCING_ADVISOR,
        c.CONTACT_BIO,
        c.REP_LICENSES
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON l.advisor_crd = c.RIA_CONTACT_CRD_ID
),

-- Get firm rep counts (point-in-time if possible, current state as fallback)
firm_rep_counts AS (
    SELECT 
        PRIMARY_FIRM as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_rep_count
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRODUCING_ADVISOR = TRUE
    GROUP BY PRIMARY_FIRM
),

-- Get firm-level AUM data for discretionary ratio
firm_aum AS (
    SELECT 
        CRD_ID as firm_crd,
        TOTAL_AUM,
        DISCRETIONARY_AUM,
        NON_DISCRETIONARY_AUM,
        SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) as discretionary_ratio,
        CUSTODIAN_PRIMARY_BUSINESS_NAME as primary_custodian
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0
),

-- Combine all data
analysis_base AS (
    SELECT 
        hl.*,
        frc.current_rep_count,
        fa.TOTAL_AUM,
        fa.DISCRETIONARY_AUM,
        fa.discretionary_ratio,
        fa.primary_custodian,
        
        -- HYPOTHESIS 1: Solo Practitioner Buckets
        CASE 
            WHEN frc.current_rep_count = 1 THEN 'Solo (1 rep)'
            WHEN frc.current_rep_count <= 3 THEN 'Micro (2-3 reps)'
            WHEN frc.current_rep_count <= 10 THEN 'Small (4-10 reps)'
            WHEN frc.current_rep_count <= 50 THEN 'Medium (11-50 reps)'
            ELSE 'Large (50+ reps)'
        END as firm_size_bucket,
        
        -- HYPOTHESIS 2: Discretionary Ratio Buckets
        CASE 
            WHEN fa.discretionary_ratio >= 0.95 THEN 'Ultra-High Discretionary (95%+)'
            WHEN fa.discretionary_ratio >= 0.80 THEN 'High Discretionary (80-95%)'
            WHEN fa.discretionary_ratio >= 0.50 THEN 'Moderate Discretionary (50-80%)'
            WHEN fa.discretionary_ratio > 0 THEN 'Low Discretionary (<50%)'
            ELSE 'Unknown/No AUM'
        END as discretionary_bucket,
        
        -- HYPOTHESIS 3: Custodian Signals
        CASE 
            WHEN fa.primary_custodian LIKE '%Schwab%' OR fa.primary_custodian LIKE '%TD Ameritrade%' THEN 'Schwab/TDA'
            WHEN fa.primary_custodian LIKE '%Fidelity%' THEN 'Fidelity'
            WHEN fa.primary_custodian LIKE '%Pershing%' THEN 'Pershing'
            WHEN fa.primary_custodian IS NOT NULL THEN 'Other Custodian'
            ELSE 'Unknown'
        END as custodian_bucket,
        
        -- HYPOTHESIS 4: Rainmaker vs Servicer Title Classification
        CASE 
            -- RAINMAKER Titles (ownership indicators)
            WHEN UPPER(hl.TITLE_NAME) LIKE '%FOUNDER%' THEN 'Rainmaker'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%PRINCIPAL%' THEN 'Rainmaker'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%PARTNER%' 
                 AND UPPER(hl.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%' THEN 'Rainmaker'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%PRESIDENT%' THEN 'Rainmaker'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%MANAGING DIRECTOR%' THEN 'Rainmaker'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%OWNER%' THEN 'Rainmaker'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%CEO%' THEN 'Rainmaker'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%CHIEF%' THEN 'Rainmaker'
            
            -- SERVICER Titles (employee indicators - EXCLUDE)
            WHEN UPPER(hl.TITLE_NAME) LIKE '%ASSOCIATE%' THEN 'Servicer'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%ANALYST%' THEN 'Servicer'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%JUNIOR%' THEN 'Servicer'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%ASSISTANT%' THEN 'Servicer'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%PARAPLANNER%' THEN 'Servicer'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%OPERATIONS%' THEN 'Servicer'
            WHEN UPPER(hl.TITLE_NAME) LIKE '%COMPLIANCE%' THEN 'Servicer'
            
            -- PRODUCER Titles (standard advisors)
            ELSE 'Producer'
        END as title_classification
        
    FROM historical_leads hl
    LEFT JOIN firm_rep_counts frc ON hl.PRIMARY_FIRM = frc.firm_crd
    LEFT JOIN firm_aum fa ON hl.PRIMARY_FIRM = fa.firm_crd
)

-- =============================================================================
-- ANALYSIS 1: SOLO-PRACTITIONER CONVERSION RATES
-- =============================================================================
SELECT 
    '1. SOLO-PRACTITIONER PROXY' as hypothesis,
    firm_size_bucket,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline,  -- Adjust baseline as needed
    ROUND(1.96 * SQRT(AVG(target) * (1 - AVG(target)) / COUNT(*)) * 100, 2) as margin_of_error_pct
FROM analysis_base
GROUP BY firm_size_bucket
ORDER BY conversion_rate_pct DESC;

-- =============================================================================
-- ANALYSIS 2: DISCRETIONARY AUM RATIO CONVERSION RATES
-- =============================================================================
SELECT 
    '2. DISCRETIONARY AUM RATIO' as hypothesis,
    discretionary_bucket,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline,
    ROUND(1.96 * SQRT(AVG(target) * (1 - AVG(target)) / COUNT(*)) * 100, 2) as margin_of_error_pct
FROM analysis_base
GROUP BY discretionary_bucket
ORDER BY conversion_rate_pct DESC;

-- =============================================================================
-- ANALYSIS 3: CUSTODIAN SIGNAL CONVERSION RATES
-- =============================================================================
SELECT 
    '3. CUSTODIAN SIGNAL' as hypothesis,
    custodian_bucket,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline,
    ROUND(1.96 * SQRT(AVG(target) * (1 - AVG(target)) / COUNT(*)) * 100, 2) as margin_of_error_pct
FROM analysis_base
GROUP BY custodian_bucket
ORDER BY conversion_rate_pct DESC;

-- =============================================================================
-- ANALYSIS 4: RAINMAKER VS SERVICER TITLE CONVERSION RATES
-- =============================================================================
SELECT 
    '4. RAINMAKER VS SERVICER' as hypothesis,
    title_classification,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline,
    ROUND(1.96 * SQRT(AVG(target) * (1 - AVG(target)) / COUNT(*)) * 100, 2) as margin_of_error_pct
FROM analysis_base
GROUP BY title_classification
ORDER BY conversion_rate_pct DESC;

-- =============================================================================
-- ANALYSIS 5: COMBINATION EFFECTS (INTERACTION ANALYSIS)
-- This is where the magic happens - combining signals
-- =============================================================================

-- 5A: Solo Practitioner + High Discretionary
SELECT 
    '5A. SOLO + HIGH DISCRETIONARY' as hypothesis,
    CASE 
        WHEN firm_size_bucket IN ('Solo (1 rep)', 'Micro (2-3 reps)') 
             AND discretionary_bucket IN ('Ultra-High Discretionary (95%+)', 'High Discretionary (80-95%)') 
        THEN 'Solo/Micro + High Discretionary'
        WHEN firm_size_bucket IN ('Solo (1 rep)', 'Micro (2-3 reps)') THEN 'Solo/Micro Only'
        WHEN discretionary_bucket IN ('Ultra-High Discretionary (95%+)', 'High Discretionary (80-95%)') THEN 'High Discretionary Only'
        ELSE 'Neither'
    END as combination,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY 2
ORDER BY conversion_rate_pct DESC;

-- 5B: Solo Practitioner + Portable Custodian
SELECT 
    '5B. SOLO + PORTABLE CUSTODIAN' as hypothesis,
    CASE 
        WHEN firm_size_bucket IN ('Solo (1 rep)', 'Micro (2-3 reps)') 
             AND custodian_bucket IN ('Schwab/TDA', 'Fidelity', 'Pershing') 
        THEN 'Solo/Micro + Portable Custodian'
        WHEN firm_size_bucket IN ('Solo (1 rep)', 'Micro (2-3 reps)') THEN 'Solo/Micro Only'
        WHEN custodian_bucket IN ('Schwab/TDA', 'Fidelity', 'Pershing') THEN 'Portable Custodian Only'
        ELSE 'Neither'
    END as combination,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY 2
ORDER BY conversion_rate_pct DESC;

-- 5C: Rainmaker + Bleeding Firm (similar to your HV Wealth analysis)
SELECT 
    '5C. RAINMAKER + BLEEDING FIRM' as hypothesis,
    CASE 
        WHEN title_classification = 'Rainmaker' 
             AND firm_size_bucket IN ('Solo (1 rep)', 'Micro (2-3 reps)', 'Small (4-10 reps)') 
        THEN 'Rainmaker at Small Firm'
        WHEN title_classification = 'Rainmaker' THEN 'Rainmaker at Larger Firm'
        WHEN title_classification = 'Servicer' THEN 'Servicer (Exclude)'
        ELSE 'Producer'
    END as combination,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY 2
ORDER BY conversion_rate_pct DESC;

-- 5D: THE ULTIMATE PORTABLE BOOK SIGNAL (All 4 Combined)
SELECT 
    '5D. ULTIMATE PORTABLE BOOK' as hypothesis,
    CASE 
        WHEN firm_size_bucket IN ('Solo (1 rep)', 'Micro (2-3 reps)')
             AND discretionary_bucket IN ('Ultra-High Discretionary (95%+)', 'High Discretionary (80-95%)')
             AND custodian_bucket IN ('Schwab/TDA', 'Fidelity', 'Pershing')
             AND title_classification = 'Rainmaker'
        THEN '🔥 ULTIMATE: Solo + Discretionary + Portable Custodian + Rainmaker'
        
        WHEN (firm_size_bucket IN ('Solo (1 rep)', 'Micro (2-3 reps)')
              OR discretionary_bucket IN ('Ultra-High Discretionary (95%+)', 'High Discretionary (80-95%)'))
             AND custodian_bucket IN ('Schwab/TDA', 'Fidelity', 'Pershing')
        THEN 'Strong: 2-3 Portable Signals'
        
        WHEN firm_size_bucket IN ('Solo (1 rep)', 'Micro (2-3 reps)')
             OR discretionary_bucket IN ('Ultra-High Discretionary (95%+)', 'High Discretionary (80-95%)')
             OR custodian_bucket IN ('Schwab/TDA', 'Fidelity', 'Pershing')
        THEN 'Moderate: 1 Portable Signal'
        
        ELSE 'Low: No Portable Signals'
    END as portability_score,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY 2
ORDER BY conversion_rate_pct DESC;

-- =============================================================================
-- ANALYSIS 6: FEATURE COVERAGE CHECK
-- Important: How much of our data has these signals?
-- =============================================================================
SELECT 
    '6. FEATURE COVERAGE' as analysis,
    COUNT(*) as total_leads,
    
    -- Solo Practitioner coverage
    COUNTIF(current_rep_count IS NOT NULL) as has_rep_count,
    ROUND(COUNTIF(current_rep_count IS NOT NULL) / COUNT(*) * 100, 2) as rep_count_coverage_pct,
    COUNTIF(firm_size_bucket IN ('Solo (1 rep)', 'Micro (2-3 reps)')) as solo_micro_count,
    
    -- Discretionary coverage
    COUNTIF(discretionary_ratio IS NOT NULL) as has_discretionary,
    ROUND(COUNTIF(discretionary_ratio IS NOT NULL) / COUNT(*) * 100, 2) as discretionary_coverage_pct,
    COUNTIF(discretionary_bucket IN ('Ultra-High Discretionary (95%+)', 'High Discretionary (80-95%)')) as high_discretionary_count,
    
    -- Custodian coverage
    COUNTIF(primary_custodian IS NOT NULL) as has_custodian,
    ROUND(COUNTIF(primary_custodian IS NOT NULL) / COUNT(*) * 100, 2) as custodian_coverage_pct,
    COUNTIF(custodian_bucket IN ('Schwab/TDA', 'Fidelity', 'Pershing')) as portable_custodian_count,
    
    -- Title coverage
    COUNTIF(TITLE_NAME IS NOT NULL) as has_title,
    COUNTIF(title_classification = 'Rainmaker') as rainmaker_count,
    COUNTIF(title_classification = 'Servicer') as servicer_count
    
FROM analysis_base;

-- =============================================================================
-- ANALYSIS 7: STATISTICAL SIGNIFICANCE TEST
-- Check if differences are significant using sample size requirements
-- =============================================================================
SELECT 
    '7. STATISTICAL POWER' as analysis,
    firm_size_bucket,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    
    -- Minimum sample size needed for 95% confidence (approximate)
    -- n = (z^2 * p * (1-p)) / E^2 where E = 0.02 (2% margin of error)
    CASE 
        WHEN COUNT(*) >= 100 THEN '✅ Sufficient (n>=100)'
        WHEN COUNT(*) >= 50 THEN '⚠️ Marginal (50<=n<100)'
        ELSE '❌ Insufficient (n<50)'
    END as sample_size_status,
    
    -- 95% Confidence Interval
    ROUND((AVG(target) - 1.96 * SQRT(AVG(target) * (1 - AVG(target)) / COUNT(*))) * 100, 2) as ci_lower_pct,
    ROUND((AVG(target) + 1.96 * SQRT(AVG(target) * (1 - AVG(target)) / COUNT(*))) * 100, 2) as ci_upper_pct
    
FROM analysis_base
GROUP BY firm_size_bucket
ORDER BY leads DESC;