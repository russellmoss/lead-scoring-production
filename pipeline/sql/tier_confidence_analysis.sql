-- ============================================================================
-- TIER CONFIDENCE ANALYSIS
-- Version: 1.0
-- Created: January 3, 2026
-- Purpose: Calculate sample sizes, confidence intervals, and statistical
--          significance for each tier to determine allocation confidence
-- ============================================================================

-- ============================================================================
-- SECTION 1: SAMPLE SIZE AND CONVERSION BY TIER
-- Purpose: Get the raw numbers for each tier
-- ============================================================================

-- Query 1.1: Historical Performance by Tier (All Time)
WITH historical_leads AS (
    SELECT 
        crd,
        score_tier,
        contacted_date,
        mql_date,
        CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END as converted
    FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`
    -- Include all historical data for maximum sample sizes
),

tier_stats AS (
    SELECT 
        score_tier,
        COUNT(*) as sample_size,
        SUM(converted) as conversions,
        ROUND(SUM(converted) * 100.0 / COUNT(*), 2) as conversion_rate,
        ROUND(SUM(converted) * 100.0 / COUNT(*) / 3.82, 2) as lift_vs_baseline
    FROM historical_leads
    GROUP BY score_tier
)

SELECT 
    score_tier,
    sample_size,
    conversions,
    conversion_rate,
    lift_vs_baseline,
    -- Confidence classification based on sample size
    CASE 
        WHEN sample_size >= 1000 THEN 'HIGH (n≥1000)'
        WHEN sample_size >= 300 THEN 'MEDIUM (n≥300)'
        WHEN sample_size >= 100 THEN 'LOW (n≥100)'
        WHEN sample_size >= 30 THEN 'VERY LOW (n≥30)'
        ELSE 'INSUFFICIENT (n<30)'
    END as confidence_level,
    -- Statistical power indicator
    CASE 
        WHEN sample_size >= 385 THEN '95% CI ±5%'
        WHEN sample_size >= 97 THEN '95% CI ±10%'
        WHEN sample_size >= 30 THEN '95% CI ±18%'
        ELSE 'Too wide to be useful'
    END as margin_of_error
FROM tier_stats
ORDER BY conversion_rate DESC;


-- ============================================================================
-- SECTION 2: CONFIDENCE INTERVAL CALCULATIONS
-- Purpose: Calculate 95% confidence intervals for each tier's conversion rate
-- Formula: p ± z * sqrt(p*(1-p)/n) where z=1.96 for 95% CI
-- ============================================================================

-- Query 2.1: 95% Confidence Intervals
WITH tier_data AS (
    SELECT 
        score_tier,
        COUNT(*) as n,
        SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as x,
        SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) as p
    FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`
    GROUP BY score_tier
    HAVING COUNT(*) >= 30  -- Minimum for CI calculation
)

SELECT 
    score_tier,
    n as sample_size,
    x as conversions,
    ROUND(p * 100, 2) as conversion_rate_pct,
    
    -- 95% Confidence Interval
    ROUND((p - 1.96 * SQRT(p * (1-p) / n)) * 100, 2) as ci_lower_95,
    ROUND((p + 1.96 * SQRT(p * (1-p) / n)) * 100, 2) as ci_upper_95,
    ROUND(1.96 * SQRT(p * (1-p) / n) * 100, 2) as margin_of_error,
    
    -- Does the CI exclude baseline (3.82%)?
    CASE 
        WHEN (p - 1.96 * SQRT(p * (1-p) / n)) > 0.0382 THEN '✅ SIGNIFICANTLY ABOVE BASELINE'
        WHEN (p + 1.96 * SQRT(p * (1-p) / n)) < 0.0382 THEN '⬇️ SIGNIFICANTLY BELOW BASELINE'
        ELSE '⚠️ NOT STATISTICALLY DIFFERENT FROM BASELINE'
    END as statistical_significance,
    
    -- Worst-case lift (using lower bound of CI)
    ROUND((p - 1.96 * SQRT(p * (1-p) / n)) / 0.0382, 2) as worst_case_lift,
    
    -- Best-case lift (using upper bound of CI)
    ROUND((p + 1.96 * SQRT(p * (1-p) / n)) / 0.0382, 2) as best_case_lift

FROM tier_data
ORDER BY conversion_rate_pct DESC;


-- ============================================================================
-- SECTION 3: TIER STABILITY ACROSS TIME PERIODS
-- Purpose: Check if tier performance is consistent or volatile
-- ============================================================================

-- Query 3.1: Quarterly Performance Stability
WITH quarterly_performance AS (
    SELECT 
        score_tier,
        DATE_TRUNC(contacted_date, QUARTER) as quarter,
        COUNT(*) as leads,
        SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as conversions,
        ROUND(SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) as conv_rate
    FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`
    WHERE contacted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 2 YEAR)
    GROUP BY score_tier, DATE_TRUNC(contacted_date, QUARTER)
    HAVING COUNT(*) >= 20  -- Minimum per quarter
)

SELECT 
    score_tier,
    COUNT(DISTINCT quarter) as quarters_with_data,
    SUM(leads) as total_leads,
    ROUND(AVG(conv_rate), 2) as avg_conv_rate,
    ROUND(MIN(conv_rate), 2) as min_conv_rate,
    ROUND(MAX(conv_rate), 2) as max_conv_rate,
    ROUND(STDDEV(conv_rate), 2) as stddev_conv_rate,
    -- Coefficient of Variation (lower = more stable)
    ROUND(STDDEV(conv_rate) / AVG(conv_rate) * 100, 1) as cv_pct,
    CASE 
        WHEN STDDEV(conv_rate) / AVG(conv_rate) < 0.2 THEN '🟢 STABLE'
        WHEN STDDEV(conv_rate) / AVG(conv_rate) < 0.4 THEN '🟡 MODERATE'
        ELSE '🔴 VOLATILE'
    END as stability
FROM quarterly_performance
GROUP BY score_tier
HAVING COUNT(DISTINCT quarter) >= 4  -- At least 4 quarters of data
ORDER BY avg_conv_rate DESC;


-- ============================================================================
-- SECTION 4: CAREER CLOCK TIER ANALYSIS
-- Purpose: Specific analysis for the new Career Clock tiers
-- ============================================================================

-- Query 4.1: Career Clock Tier Performance
SELECT 
    score_tier,
    COUNT(*) as sample_size,
    SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as conversions,
    ROUND(SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) as conv_rate,
    ROUND(SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) / 3.82, 2) as lift,
    -- 95% CI
    ROUND((SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
           - 1.96 * SQRT(SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
           * (1 - SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) / COUNT(*))) * 100, 2) as ci_lower,
    ROUND((SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
           + 1.96 * SQRT(SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
           * (1 - SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) / COUNT(*))) * 100, 2) as ci_upper
FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`
WHERE score_tier IN (
    'TIER_0A_PRIME_MOVER_DUE',
    'TIER_0B_SMALL_FIRM_DUE', 
    'TIER_0C_CLOCKWORK_DUE',
    'TIER_NURTURE_TOO_EARLY'
)
GROUP BY score_tier
ORDER BY conv_rate DESC;


-- ============================================================================
-- SECTION 5: M&A TIER ANALYSIS
-- Purpose: Specific analysis for M&A tiers with Commonwealth data
-- ============================================================================

-- Query 5.1: M&A Tier Performance (from historical_lead_performance)
SELECT 
    score_tier,
    COUNT(*) as sample_size,
    SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as conversions,
    ROUND(SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) as conv_rate,
    ROUND(SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) / 3.82, 2) as lift_vs_baseline,
    -- 95% CI calculation
    ROUND((SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
           - 1.96 * SQRT(SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
           * (1 - SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) / COUNT(*))) * 100, 2) as ci_lower_95,
    ROUND((SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
           + 1.96 * SQRT(SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
           * (1 - SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) / COUNT(*))) * 100, 2) as ci_upper_95
FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`
WHERE score_tier IN ('TIER_MA_ACTIVE_PRIME', 'TIER_MA_ACTIVE')
GROUP BY score_tier
ORDER BY conv_rate DESC;


-- ============================================================================
-- SECTION 6: RISK-ADJUSTED TIER RANKING
-- Purpose: Rank tiers by worst-case (lower CI bound) conversion rate
-- This is the conservative approach - "what's the minimum we can expect?"
-- ============================================================================

-- Query 6.1: Risk-Adjusted Tier Ranking
WITH all_tiers AS (
    SELECT 
        score_tier,
        COUNT(*) as n,
        SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as x,
        SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) as p
    FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`
    GROUP BY score_tier
    HAVING COUNT(*) >= 30
)

SELECT 
    score_tier,
    n as sample_size,
    ROUND(p * 100, 2) as point_estimate_pct,
    -- Worst-case (lower bound of 95% CI)
    ROUND((p - 1.96 * SQRT(p * (1-p) / n)) * 100, 2) as worst_case_pct,
    -- Risk-adjusted lift (using worst case)
    ROUND((p - 1.96 * SQRT(p * (1-p) / n)) / 0.0382, 2) as worst_case_lift,
    -- Confidence rating
    CASE 
        WHEN n >= 1000 AND (p - 1.96 * SQRT(p * (1-p) / n)) > 0.0382 THEN '🟢 HIGH CONFIDENCE - INCLUDE'
        WHEN n >= 300 AND (p - 1.96 * SQRT(p * (1-p) / n)) > 0.0382 THEN '🟡 MEDIUM CONFIDENCE - INCLUDE'
        WHEN n >= 100 AND (p - 1.96 * SQRT(p * (1-p) / n)) > 0.0382 THEN '🟠 LOW CONFIDENCE - INCLUDE CAUTIOUSLY'
        WHEN (p - 1.96 * SQRT(p * (1-p) / n)) > 0.0382 THEN '🔴 VERY LOW CONFIDENCE - LIMIT EXPOSURE'
        ELSE '⛔ EXCLUDE - NO PROVEN LIFT'
    END as allocation_recommendation
FROM all_tiers
ORDER BY worst_case_pct DESC;


-- ============================================================================
-- SECTION 7: OPTIMAL ALLOCATION CALCULATOR
-- Purpose: Calculate optimal allocation based on confidence-weighted conversion
-- ============================================================================

-- Query 7.1: Confidence-Weighted Optimal Allocation
-- Note: This uses placeholder pool sizes - adjust based on actual available pools
DECLARE total_capacity INT64 DEFAULT 3000;

WITH tier_metrics AS (
    SELECT 
        score_tier,
        COUNT(*) as sample_n,
        SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) as point_est,
        -- CI lower bound
        SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
        - 1.96 * SQRT(SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
        * (1 - SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) / COUNT(*)) as ci_lower
    FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`
    WHERE score_tier != 'STANDARD'  -- Exclude baseline
    GROUP BY score_tier
    HAVING COUNT(*) >= 30
),

-- Get actual pool sizes from current lead list (if available)
pool_sizes AS (
    SELECT 
        score_tier,
        COUNT(*) as pool_size
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
    GROUP BY score_tier
),

-- Calculate confidence score (combination of sample size and CI width)
confidence_scored AS (
    SELECT 
        tm.score_tier,
        tm.point_est,
        tm.ci_lower,
        tm.sample_n,
        COALESCE(ps.pool_size, 0) as pool,
        -- Confidence score: weighted by sample size
        CASE 
            WHEN tm.sample_n >= 1000 THEN 1.0
            WHEN tm.sample_n >= 300 THEN 0.9
            WHEN tm.sample_n >= 100 THEN 0.7
            WHEN tm.sample_n >= 50 THEN 0.5
            ELSE 0.3
        END as confidence_weight,
        -- Risk-adjusted conversion (use CI lower bound, weighted by confidence)
        tm.ci_lower * CASE 
            WHEN tm.sample_n >= 1000 THEN 1.0
            WHEN tm.sample_n >= 300 THEN 0.95
            WHEN tm.sample_n >= 100 THEN 0.85
            WHEN tm.sample_n >= 50 THEN 0.75
            ELSE 0.6
        END as risk_adjusted_conv
    FROM tier_metrics tm
    LEFT JOIN pool_sizes ps ON tm.score_tier = ps.score_tier
),

-- Rank by risk-adjusted conversion
ranked_tiers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY risk_adjusted_conv DESC) as risk_rank,
        SUM(pool) OVER (ORDER BY risk_adjusted_conv DESC) as cumulative_pool
    FROM confidence_scored
)

SELECT 
    score_tier,
    ROUND(point_est * 100, 2) as point_est_pct,
    ROUND(ci_lower * 100, 2) as ci_lower_pct,
    sample_n,
    ROUND(confidence_weight, 2) as confidence_weight,
    ROUND(risk_adjusted_conv * 100, 2) as risk_adj_conv_pct,
    pool as available_pool,
    risk_rank,
    -- Allocation recommendation
    CASE 
        WHEN cumulative_pool <= total_capacity THEN pool
        WHEN cumulative_pool - pool < total_capacity THEN total_capacity - (cumulative_pool - pool)
        ELSE 0
    END as recommended_allocation,
    -- Expected MQLs from this tier
    ROUND(CASE 
        WHEN cumulative_pool <= total_capacity THEN pool * ci_lower  -- Use conservative estimate
        WHEN cumulative_pool - pool < total_capacity THEN (total_capacity - (cumulative_pool - pool)) * ci_lower
        ELSE 0
    END, 1) as expected_mqls_conservative
FROM ranked_tiers
ORDER BY risk_rank;
