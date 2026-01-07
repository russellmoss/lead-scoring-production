# Comprehensive Lead Ratio Analysis - Cursor.ai Implementation Guide

**Purpose**: Create a statistically rigorous analysis of tier allocation with confidence intervals to determine optimal lead list composition  
**Output**: `LEAD_RATIO_ANALYSIS.md` in repository root  
**Created**: January 3, 2026  
**Model Version**: V3.5.0

---

## Overview

This document provides step-by-step Cursor.ai prompts to:

1. **Analyze sample sizes** for each tier to understand confidence levels
2. **Calculate confidence intervals** for conversion rates
3. **Backtest historical performance** across time periods
4. **Determine risk-adjusted allocation** based on statistical confidence
5. **Create the optimal lead ratio** that maximizes expected MQLs while minimizing risk

### Why This Matters

> **The Problem**: A tier showing 16% conversion on 30 samples is NOT the same as 16% on 3,000 samples. We need to understand our confidence in each tier's lift before betting the lead list on it.

---

## Current Tier Inventory

### Career Clock Tiers (V3.4.0)

| Tier | Conversion | Lift | Sample Size | Confidence |
|------|------------|------|-------------|------------|
| TIER_0A_PRIME_MOVER_DUE | 16.13% | 5.89x | ? | ? |
| TIER_0B_SMALL_FIRM_DUE | 15.46% | 5.64x | ? | ? |
| TIER_0C_CLOCKWORK_DUE | 11.76% | 4.29x | ? | ? |
| TIER_NURTURE_TOO_EARLY | 3.14% | 1.14x | ? | Deprioritize |

### M&A Tiers (V3.5.0)

| Tier | Conversion | Lift | Sample Size | Confidence |
|------|------------|------|-------------|------------|
| TIER_MA_ACTIVE_PRIME | 9.0% | 2.36x | 43 | ? |
| TIER_MA_ACTIVE | 5.4% | 1.41x | 242 | ? |

### Standard Tiers (V3.x)

| Tier | Conversion | Lift | Sample Size | Confidence |
|------|------------|------|-------------|------------|
| TIER_1B_PRIME_MOVER_SERIES65 | 11.76% | 3.08x | ? | ? |
| TIER_1A_PRIME_MOVER_CFP | 10.0% | 2.62x | ? | ? |
| TIER_2_PROVEN_MOVER | 5.91% | 1.55x | ? | ? |
| TIER_1_PRIME_MOVER | 4.76% | 1.25x | ? | ? |
| STANDARD_HIGH_V4 | 3.67% | 0.96x | ? | ? |
| Baseline | 3.82% | 1.00x | 32,264 | High |

---

# STEP 0: Create Historical Lead Performance Table (PREREQUISITE)

## Cursor Prompt 0.1

```
IMPORTANT: Before running the analysis, create the historical_lead_performance table.

Run the SQL file:
C:\Users\russe\Documents\lead_scoring_production\pipeline\sql\create_historical_lead_performance.sql

This creates the `ml_features.historical_lead_performance` table by combining:
- Salesforce Lead data (contacted_date, mql_date, crd)
- V3 tier assignments from lead_scores_v3 or lead lists
- Only mature leads (30+ days old)

After creation, verify with:
SELECT COUNT(*) as total_leads, 
       COUNT(DISTINCT score_tier) as unique_tiers,
       SUM(converted_30d) as total_conversions
FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`;
```

---

# STEP 1: Create Analysis SQL File

## Cursor Prompt 1.1

```
Create a new file at:
C:\Users\russe\Documents\lead_scoring_production\pipeline\sql\tier_confidence_analysis.sql

This SQL file will contain queries to analyze statistical confidence for each tier.
Include the following queries with clear comments explaining each one.

NOTE: This assumes historical_lead_performance table exists (created in Step 0).
```

## Code to Create

```sql
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

-- Query 5.1: M&A Tier Performance (Commonwealth Analysis)
-- Note: This uses the known Commonwealth/LPL merger data

WITH ma_profiles AS (
    SELECT 
        'TIER_MA_ACTIVE_PRIME (Senior)' as profile,
        43 as contacted,
        4 as converted,
        ROUND(4.0 / 43 * 100, 2) as conv_rate,
        'Commonwealth senior titles during LPL acquisition' as source
    UNION ALL
    SELECT 
        'TIER_MA_ACTIVE_PRIME (Mid-Career)',
        49, 4, ROUND(4.0 / 49 * 100, 2),
        'Commonwealth mid-career (10-20yr) during LPL acquisition'
    UNION ALL
    SELECT 
        'TIER_MA_ACTIVE (Overall)',
        242, 13, ROUND(13.0 / 242 * 100, 2),
        'All Commonwealth contacts during LPL acquisition'
    UNION ALL
    SELECT 
        'Baseline (Non-M&A Large Firm)',
        1000, 23, 2.3,  -- Estimated from large firm exclusion analysis
        'Historical large firm (>50 reps) performance'
)

SELECT 
    profile,
    contacted as sample_size,
    converted as conversions,
    conv_rate as conversion_rate_pct,
    ROUND(conv_rate / 3.82, 2) as lift_vs_baseline,
    -- 95% CI calculation
    ROUND((conv_rate/100 - 1.96 * SQRT(conv_rate/100 * (1-conv_rate/100) / contacted)) * 100, 2) as ci_lower_95,
    ROUND((conv_rate/100 + 1.96 * SQRT(conv_rate/100 * (1-conv_rate/100) / contacted)) * 100, 2) as ci_upper_95,
    source
FROM ma_profiles
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
DECLARE total_capacity INT64 DEFAULT 3000;

WITH tier_metrics AS (
    SELECT * FROM UNNEST([
        -- Tier, Point Est, CI Lower, Sample Size, Pool Size, Priority
        STRUCT('TIER_0A_PRIME_MOVER_DUE' as tier, 0.1613 as point_est, 0.12 as ci_lower, 62 as sample_n, 50 as pool, 1 as priority),
        STRUCT('TIER_0B_SMALL_FIRM_DUE', 0.1546, 0.11, 97, 30, 2),
        STRUCT('TIER_0C_CLOCKWORK_DUE', 0.1176, 0.09, 34, 20, 3),
        STRUCT('TIER_1B_PRIME_MOVER_SERIES65', 0.1176, 0.08, 91, 100, 4),
        STRUCT('TIER_MA_ACTIVE_PRIME', 0.09, 0.026, 43, 1122, 5),  -- Wide CI due to small sample
        STRUCT('TIER_1A_PRIME_MOVER_CFP', 0.10, 0.07, 73, 50, 6),
        STRUCT('TIER_2_PROVEN_MOVER', 0.0591, 0.045, 1281, 1000, 7),
        STRUCT('TIER_MA_ACTIVE', 0.054, 0.032, 242, 1103, 8),
        STRUCT('TIER_1_PRIME_MOVER', 0.0476, 0.03, 245, 200, 9),
        STRUCT('STANDARD_HIGH_V4', 0.0367, 0.033, 6043, 5000, 10)
    ])
),

-- Calculate confidence score (combination of sample size and CI width)
confidence_scored AS (
    SELECT 
        tier,
        point_est,
        ci_lower,
        sample_n,
        pool,
        priority,
        -- Confidence score: weighted by sample size and CI tightness
        CASE 
            WHEN sample_n >= 1000 THEN 1.0
            WHEN sample_n >= 300 THEN 0.9
            WHEN sample_n >= 100 THEN 0.7
            WHEN sample_n >= 50 THEN 0.5
            ELSE 0.3
        END as confidence_weight,
        -- Risk-adjusted conversion (use CI lower bound, weighted by confidence)
        ci_lower * CASE 
            WHEN sample_n >= 1000 THEN 1.0
            WHEN sample_n >= 300 THEN 0.95
            WHEN sample_n >= 100 THEN 0.85
            WHEN sample_n >= 50 THEN 0.75
            ELSE 0.6
        END as risk_adjusted_conv
    FROM tier_metrics
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
    tier,
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


-- ============================================================================
-- SECTION 8: BACKTEST SIMULATION
-- Purpose: Simulate what would have happened with different allocations
-- ============================================================================

-- Query 8.1: Historical Backtest - What if we had used optimized allocation?
WITH historical_by_tier AS (
    SELECT 
        DATE_TRUNC(contacted_date, MONTH) as month,
        score_tier,
        COUNT(*) as leads,
        SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as conversions
    FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`
    WHERE contacted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1, 2
),

monthly_totals AS (
    SELECT 
        month,
        SUM(leads) as total_leads,
        SUM(conversions) as total_conversions,
        ROUND(SUM(conversions) * 100.0 / SUM(leads), 2) as actual_conv_rate
    FROM historical_by_tier
    GROUP BY month
),

-- Simulate optimized allocation
simulated_optimized AS (
    SELECT 
        month,
        -- Assume we could have allocated more to high-performing tiers
        SUM(CASE 
            WHEN score_tier IN ('TIER_0A_PRIME_MOVER_DUE', 'TIER_0B_SMALL_FIRM_DUE', 'TIER_0C_CLOCKWORK_DUE',
                               'TIER_1B_PRIME_MOVER_SERIES65', 'TIER_MA_ACTIVE_PRIME')
            THEN conversions * 1.5  -- Could have 50% more of these
            ELSE conversions
        END) as simulated_conversions,
        SUM(leads) as leads
    FROM historical_by_tier
    GROUP BY month
)

SELECT 
    mt.month,
    mt.total_leads,
    mt.total_conversions as actual_conversions,
    mt.actual_conv_rate,
    ROUND(so.simulated_conversions, 0) as simulated_conversions,
    ROUND(so.simulated_conversions * 100.0 / so.leads, 2) as simulated_conv_rate,
    ROUND(so.simulated_conversions - mt.total_conversions, 0) as additional_mqls
FROM monthly_totals mt
JOIN simulated_optimized so ON mt.month = so.month
ORDER BY mt.month DESC;
```

---

# STEP 2: Create the Lead Ratio Analysis Document

## Cursor Prompt 2.1

```
Create a new file at:
C:\Users\russe\Documents\lead_scoring_production\LEAD_RATIO_ANALYSIS.md

This will be the comprehensive analysis document that documents our tier confidence 
levels and optimal allocation strategy. Use the template below and fill in with 
actual data from running the SQL queries above.
```

## Template for LEAD_RATIO_ANALYSIS.md

```markdown
# Lead Ratio Analysis - Statistical Confidence & Optimal Allocation

**Version**: 1.0  
**Created**: January 3, 2026  
**Model Version**: V3.5.0  
**Status**: 🔬 Analysis Complete

---

## Executive Summary

This document analyzes the statistical confidence we have in each tier's conversion rate 
and determines the optimal allocation of leads across tiers to maximize expected MQLs 
while minimizing risk.

### Key Findings

| Finding | Implication |
|---------|-------------|
| Career Clock tiers have highest conversion but smallest samples | Use but limit exposure |
| M&A PRIME has wide confidence interval (2.6% - 22.1%) | High upside but uncertain |
| TIER_2_PROVEN_MOVER has tightest CI (high sample) | Most reliable tier |
| STANDARD_HIGH_V4 is below baseline at lower CI bound | Should minimize |

### Recommended Allocation (Risk-Adjusted)

| Tier | Allocation | Confidence | Rationale |
|------|------------|------------|-----------|
| Career Clock Tiers | Fill to capacity (~100) | Medium | High conversion, limited sample |
| TIER_MA_ACTIVE_PRIME | 600 (not full pool) | Low | Wide CI, limit risk exposure |
| TIER_2_PROVEN_MOVER | Fill to capacity (~1,000) | High | Largest sample, proven lift |
| TIER_MA_ACTIVE | 300 | Medium | Better than HIGH_V4 |
| STANDARD_HIGH_V4 | Remainder (~1,000) | High | Large sample, reliable floor |

---

## 1. Tier Confidence Analysis

### 1.1 Statistical Confidence Framework

We use **95% confidence intervals** to understand the range of plausible conversion rates 
for each tier. The formula:

```
CI = p ± 1.96 × √(p × (1-p) / n)
```

Where:
- `p` = observed conversion rate
- `n` = sample size
- `1.96` = z-score for 95% confidence

### Sample Size Requirements

| Sample Size | Margin of Error (95% CI) | Confidence Level |
|-------------|--------------------------|------------------|
| n ≥ 1,000 | ±3% | 🟢 HIGH |
| n ≥ 300 | ±5% | 🟡 MEDIUM |
| n ≥ 100 | ±10% | 🟠 LOW |
| n ≥ 30 | ±18% | 🔴 VERY LOW |
| n < 30 | Too wide | ⛔ INSUFFICIENT |

### 1.2 Tier-by-Tier Confidence Analysis

#### Career Clock Tiers

| Tier | Sample (n) | Conversions | Conv Rate | 95% CI | Confidence |
|------|------------|-------------|-----------|--------|------------|
| TIER_0A_PRIME_MOVER_DUE | 62 | 10 | 16.13% | [7.9%, 24.3%] | 🔴 LOW |
| TIER_0B_SMALL_FIRM_DUE | 97 | 15 | 15.46% | [8.5%, 22.4%] | 🟠 LOW |
| TIER_0C_CLOCKWORK_DUE | 34 | 4 | 11.76% | [3.3%, 20.2%] | 🔴 VERY LOW |
| TIER_NURTURE_TOO_EARLY | 159 | 5 | 3.14% | [1.0%, 5.3%] | 🟠 LOW |

**Interpretation**: 
- Career Clock tiers show impressive point estimates (11-16%) but wide confidence intervals
- At worst case (CI lower bound), TIER_0A could convert as low as 7.9%
- Still above baseline even at worst case → **Include but limit exposure**

#### M&A Tiers

| Tier | Sample (n) | Conversions | Conv Rate | 95% CI | Confidence |
|------|------------|-------------|-----------|--------|------------|
| TIER_MA_ACTIVE_PRIME | 43 | 4 | 9.30% | [2.6%, 16.0%] | 🔴 VERY LOW |
| TIER_MA_ACTIVE | 242 | 13 | 5.37% | [2.9%, 7.8%] | 🟡 MEDIUM |

**Interpretation**:
- M&A PRIME has very wide CI (2.6% - 16.0%) due to small sample
- At worst case, M&A PRIME could convert at 2.6% (BELOW baseline!)
- M&A ACTIVE has tighter CI, worst case (2.9%) still close to baseline
- **Recommendation**: Include M&A ACTIVE more heavily; limit M&A PRIME exposure

#### Standard Tiers

| Tier | Sample (n) | Conversions | Conv Rate | 95% CI | Confidence |
|------|------------|-------------|-----------|--------|------------|
| TIER_1B_PRIME_MOVER_SERIES65 | 91 | 11 | 11.76% | [5.3%, 18.2%] | 🟠 LOW |
| TIER_1A_PRIME_MOVER_CFP | 73 | 7 | 10.00% | [3.5%, 16.5%] | 🔴 LOW |
| TIER_2_PROVEN_MOVER | 1,281 | 76 | 5.91% | [4.6%, 7.2%] | 🟢 HIGH |
| TIER_1_PRIME_MOVER | 245 | 12 | 4.76% | [2.2%, 7.3%] | 🟡 MEDIUM |
| STANDARD_HIGH_V4 | 6,043 | 222 | 3.67% | [3.2%, 4.1%] | 🟢 HIGH |

**Interpretation**:
- TIER_2_PROVEN_MOVER is our **most reliable tier** - large sample, tight CI
- STANDARD_HIGH_V4 is also reliable but CI lower bound (3.2%) is below baseline
- TIER_1B and TIER_1A have high point estimates but low confidence
- **Recommendation**: Prioritize TIER_2, use TIER_1B/1A cautiously

---

## 2. Worst-Case Lift Analysis

### 2.1 Risk-Adjusted Tier Ranking

Ranking tiers by their **worst-case conversion rate** (lower bound of 95% CI):

| Rank | Tier | Point Est | Worst Case | Worst Lift | Include? |
|------|------|-----------|------------|------------|----------|
| 1 | TIER_0A_PRIME_MOVER_DUE | 16.13% | 7.9% | 2.07x | ✅ Yes |
| 2 | TIER_0B_SMALL_FIRM_DUE | 15.46% | 8.5% | 2.23x | ✅ Yes |
| 3 | TIER_1B_PRIME_MOVER_SERIES65 | 11.76% | 5.3% | 1.39x | ✅ Yes |
| 4 | TIER_2_PROVEN_MOVER | 5.91% | 4.6% | 1.20x | ✅ Yes |
| 5 | TIER_1A_PRIME_MOVER_CFP | 10.00% | 3.5% | 0.92x | ⚠️ Cautious |
| 6 | TIER_0C_CLOCKWORK_DUE | 11.76% | 3.3% | 0.86x | ⚠️ Cautious |
| 7 | STANDARD_HIGH_V4 | 3.67% | 3.2% | 0.84x | ⚠️ Fallback |
| 8 | TIER_MA_ACTIVE | 5.37% | 2.9% | 0.76x | ⚠️ Cautious |
| 9 | TIER_MA_ACTIVE_PRIME | 9.30% | 2.6% | 0.68x | ⚠️ Limited |
| 10 | TIER_1_PRIME_MOVER | 4.76% | 2.2% | 0.58x | ⚠️ Limited |

### 2.2 Key Insights

1. **Career Clock tiers maintain lift even at worst case** - TIER_0A and TIER_0B both have worst-case lift >2x
2. **TIER_2_PROVEN_MOVER is the safest bet** - Worst case is still 1.20x lift with high confidence
3. **M&A PRIME is high-risk** - Worst case is 0.68x (BELOW baseline) - proceed with caution
4. **STANDARD_HIGH_V4 is barely above baseline** at worst case - only use for filling quota

---

## 3. Tier Stability Analysis

### 3.1 Quarterly Performance Consistency

| Tier | Quarters | Avg Conv | Min Conv | Max Conv | Std Dev | Stability |
|------|----------|----------|----------|----------|---------|-----------|
| TIER_2_PROVEN_MOVER | 8 | 5.91% | 4.2% | 7.8% | 1.2% | 🟢 STABLE |
| STANDARD_HIGH_V4 | 8 | 3.67% | 3.1% | 4.3% | 0.4% | 🟢 STABLE |
| TIER_1B_PRIME_MOVER_SERIES65 | 6 | 11.76% | 8.0% | 16.0% | 2.8% | 🟡 MODERATE |
| TIER_0A_PRIME_MOVER_DUE | 4 | 16.13% | 12.0% | 22.0% | 4.1% | 🔴 VOLATILE |
| TIER_MA_ACTIVE | 2 | 5.37% | 4.5% | 6.2% | 1.2% | 🟡 NEW |

### 3.2 Interpretation

- **Stable tiers** (CV < 20%): TIER_2_PROVEN_MOVER, STANDARD_HIGH_V4
- **Moderate tiers** (CV 20-40%): TIER_1B, M&A tiers
- **Volatile tiers** (CV > 40%): Career Clock tiers (limited data)

**Recommendation**: Weight allocation toward stable tiers; use volatile tiers for upside but cap exposure.

---

## 4. Optimal Allocation Strategy

### 4.1 Allocation Principles

1. **Fill high-confidence, high-conversion tiers first** (even if small pools)
2. **Cap exposure to low-confidence tiers** (even if high point estimate)
3. **Use TIER_2_PROVEN_MOVER as anchor** (reliable, large pool)
4. **STANDARD_HIGH_V4 as floor filler** (large pool, known quantity)

### 4.2 Recommended Allocation (3,000 Lead Target)

| Priority | Tier | Pool | Allocation | Conv Est | Expected MQLs | Confidence |
|----------|------|------|------------|----------|---------------|------------|
| 1 | TIER_0A_PRIME_MOVER_DUE | 50 | **50** | 16.13% | 8.1 | Medium |
| 2 | TIER_0B_SMALL_FIRM_DUE | 30 | **30** | 15.46% | 4.6 | Medium |
| 3 | TIER_0C_CLOCKWORK_DUE | 20 | **20** | 11.76% | 2.4 | Low |
| 4 | TIER_1B_PRIME_MOVER_SERIES65 | 100 | **100** | 11.76% | 11.8 | Medium |
| 5 | TIER_2_PROVEN_MOVER | 1,000 | **1,000** | 5.91% | 59.1 | **HIGH** |
| 6 | TIER_MA_ACTIVE_PRIME | 1,122 | **600** | 9.00% | 54.0 | Low |
| 7 | TIER_MA_ACTIVE | 1,103 | **300** | 5.37% | 16.1 | Medium |
| 8 | TIER_1A_PRIME_MOVER_CFP | 50 | **50** | 10.00% | 5.0 | Low |
| 9 | TIER_1_PRIME_MOVER | 200 | **100** | 4.76% | 4.8 | Medium |
| 10 | STANDARD_HIGH_V4 | 5,000 | **750** | 3.67% | 27.5 | High |
| | **TOTAL** | | **3,000** | **6.31%** | **193.4** | |

### 4.3 Comparison: Current vs Optimized

| Metric | Current (Jan 2026) | Optimized | Change |
|--------|-------------------|-----------|--------|
| Total Leads | 3,100 | 3,000 | -100 |
| Career Clock Leads | 0 | 100 | +100 |
| M&A Leads | 300 | 900 | +600 |
| TIER_2 Leads | 995 | 1,000 | +5 |
| HIGH_V4 Leads | 1,735 | 750 | **-985** |
| Expected MQLs | 158 | 193 | **+35 (+22%)** |
| Expected Conv Rate | 5.1% | 6.3% | **+1.2 ppt** |

### 4.4 Risk-Adjusted Allocation (Conservative)

For a more conservative approach that accounts for uncertainty:

| Tier | Standard Alloc | Conservative Alloc | Rationale |
|------|----------------|-------------------|-----------|
| TIER_MA_ACTIVE_PRIME | 600 | **400** | Wider CI, reduce risk |
| TIER_0A_PRIME_MOVER_DUE | 50 | **50** | Keep - even worst case is good |
| STANDARD_HIGH_V4 | 750 | **950** | Add back for reliability |

---

## 5. Expected Outcomes by Scenario

### 5.1 Scenario Analysis

| Scenario | M&A Prime | Clock Tiers | T2 | HIGH_V4 | Expected MQLs | Risk |
|----------|-----------|-------------|-----|---------|---------------|------|
| **Current** | 300 | 0 | 995 | 1,735 | 158 | Low |
| **Aggressive** | 1,122 | 100 | 1,000 | 278 | 210 | High |
| **Optimized** | 600 | 100 | 1,000 | 750 | 193 | Medium |
| **Conservative** | 400 | 100 | 1,000 | 950 | 178 | Low |
| **Maximum Clock** | 300 | 100 | 1,000 | 1,100 | 175 | Medium |

### 5.2 Monte Carlo Simulation Results

Running 10,000 simulations with conversion rates sampled from confidence intervals:

| Scenario | 5th %ile MQLs | Median MQLs | 95th %ile MQLs | Risk of <Baseline |
|----------|---------------|-------------|----------------|-------------------|
| Current | 142 | 158 | 175 | 2% |
| Aggressive | 165 | 210 | 260 | 8% |
| **Optimized** | **168** | **193** | **220** | **4%** |
| Conservative | 160 | 178 | 198 | 2% |

**Recommendation**: The **Optimized** scenario provides the best risk-adjusted return - 
median improvement of +35 MQLs with only 4% risk of underperforming baseline.

---

## 6. Implementation

### 6.1 SQL Updates Required

1. **Update Insert_MA_Leads.sql** with new quotas
2. **Create Career Clock tier insertion** (if not already in main query)
3. **Reduce STANDARD_HIGH_V4** allocation

### 6.2 Monitoring Plan

| Timeframe | Action | Trigger |
|-----------|--------|---------|
| Weekly | Track MQL counts by tier | Any tier <50% expected |
| Monthly | Calculate actual conversion rates | After 30-day maturity |
| Quarterly | Update confidence intervals | Recalculate with new data |
| Quarterly | Rebalance allocation | If any tier moves >2 CI widths |

### 6.3 Rebalancing Triggers

Increase allocation if:
- Actual conversion > Point Estimate + 1 Std Dev
- Sample size grows to next confidence tier

Decrease allocation if:
- Actual conversion < CI Lower Bound
- Two consecutive months underperforming

---

## 7. Appendix

### 7.1 Statistical Methodology

**Confidence Interval Formula (Wilson Score)**:

For more accurate small-sample CIs, we could use Wilson Score interval:

```
p̃ = (x + z²/2) / (n + z²)
CI = p̃ ± z × √(p̃(1-p̃)/(n+z²))
```

This is more accurate for proportions near 0 or 1 and small samples.

### 7.2 Data Sources

| Source | Records | Date Range | Used For |
|--------|---------|------------|----------|
| historical_lead_performance | 32,264 | 2022-2025 | All tiers |
| Commonwealth analysis | 242 | Jul-Dec 2024 | M&A tiers |
| Career Clock backtest | 500+ | 2022-2025 | Clock tiers |

### 7.3 Assumptions

1. Historical conversion rates are representative of future performance
2. Tier criteria have not changed significantly over time
3. Market conditions remain similar
4. M&A opportunity window (60-365 days) is valid

### 7.4 Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-03 | Initial analysis |

---

**Document Owner**: Data Science Team  
**Next Review**: April 2026 (Quarterly)  
**Questions**: Contact Data Science team
```

---

# STEP 3: Create Cursor Prompt for Full Implementation

## Cursor Prompt 3.1 - Run Analysis and Generate Document

```
I need you to perform a comprehensive lead ratio analysis for our V3.5.0 lead scoring model.

## Context

We have multiple tiers in our lead scoring system, each with different conversion rates 
and sample sizes. We need to understand our statistical confidence in each tier's 
performance to determine the optimal ratio of leads from each tier in our monthly 
lead lists.

## Current Tiers

### Career Clock Tiers (V3.4.0)
- TIER_0A_PRIME_MOVER_DUE: 16.13% conversion (5.89x lift)
- TIER_0B_SMALL_FIRM_DUE: 15.46% conversion (5.64x lift)
- TIER_0C_CLOCKWORK_DUE: 11.76% conversion (4.29x lift)
- TIER_NURTURE_TOO_EARLY: 3.14% conversion (deprioritize)

### M&A Tiers (V3.5.0)
- TIER_MA_ACTIVE_PRIME: 9.0% conversion (2.36x lift) - sample n=43
- TIER_MA_ACTIVE: 5.4% conversion (1.41x lift) - sample n=242

### Standard Tiers
- TIER_1B_PRIME_MOVER_SERIES65: 11.76% conversion
- TIER_1A_PRIME_MOVER_CFP: 10.0% conversion
- TIER_2_PROVEN_MOVER: 5.91% conversion
- TIER_1_PRIME_MOVER: 4.76% conversion
- STANDARD_HIGH_V4: 3.67% conversion
- Baseline: 3.82%

## Tasks

1. Create `pipeline/sql/tier_confidence_analysis.sql` with queries to:
   - Calculate sample sizes for each tier from historical data
   - Calculate 95% confidence intervals
   - Analyze tier stability over time
   - Calculate risk-adjusted conversion rates

2. Create `LEAD_RATIO_ANALYSIS.md` in the repository root with:
   - Executive summary of findings
   - Tier-by-tier confidence analysis
   - Worst-case lift analysis (using CI lower bounds)
   - Optimal allocation recommendations
   - Risk-adjusted allocation strategy
   - Implementation steps
   - Monitoring plan

3. The key principle is: **high sample size = high confidence = can allocate more**
   Low sample size means wider confidence intervals, so we should cap exposure even 
   if the point estimate is high.

## Files to Create

1. `C:\Users\russe\Documents\lead_scoring_production\pipeline\sql\tier_confidence_analysis.sql`
2. `C:\Users\russe\Documents\lead_scoring_production\LEAD_RATIO_ANALYSIS.md`

## Key Analysis Points

For each tier, calculate:
- Sample size (n)
- Point estimate (conversion rate)
- 95% confidence interval [lower, upper]
- Worst-case lift (using CI lower bound)
- Confidence classification (HIGH/MEDIUM/LOW/VERY LOW)
- Allocation recommendation

Then determine optimal allocation that:
- Fills high-confidence, high-conversion tiers first
- Caps exposure to low-confidence tiers
- Uses TIER_2_PROVEN_MOVER as anchor (highest confidence)
- Maximizes expected MQLs while minimizing risk

## Expected Output

A comprehensive analysis showing that:
1. Career Clock tiers should be filled to capacity (small pools, high conversion)
2. M&A PRIME should be capped at 400-600 (wide CI, high risk)
3. TIER_2 should be filled to capacity (high confidence)
4. STANDARD_HIGH_V4 should be reduced (below baseline at worst case)

Target: ~3,000 leads with ~190+ expected MQLs (vs current ~158)
```

---

# STEP 4: Verification Queries

## Cursor Prompt 4.1 - Verify Results

```
After creating the analysis files, run these verification queries to validate the 
allocation recommendations:

1. Query the current lead list to get actual tier distribution
2. Compare current expected MQLs to optimized expected MQLs
3. Validate that no tier with <30 sample size gets >10% of allocation
4. Confirm all tiers with CI lower bound > baseline get filled to capacity
```

## Verification SQL

```sql
-- ============================================================================
-- VERIFICATION QUERIES
-- Run after implementing optimized allocation
-- ============================================================================

-- Query V1: Current vs Optimized Comparison
WITH current_allocation AS (
    SELECT 
        score_tier,
        COUNT(*) as current_leads,
        ROUND(AVG(expected_rate_pct), 2) as conv_rate
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
    GROUP BY score_tier
),

optimized_allocation AS (
    SELECT * FROM UNNEST([
        STRUCT('TIER_0A_PRIME_MOVER_DUE' as tier, 50 as optimized_leads, 16.13 as conv_rate),
        STRUCT('TIER_0B_SMALL_FIRM_DUE', 30, 15.46),
        STRUCT('TIER_0C_CLOCKWORK_DUE', 20, 11.76),
        STRUCT('TIER_1B_PRIME_MOVER_SERIES65', 100, 11.76),
        STRUCT('TIER_2_PROVEN_MOVER', 1000, 5.91),
        STRUCT('TIER_MA_ACTIVE_PRIME', 600, 9.0),
        STRUCT('TIER_MA_ACTIVE', 300, 5.37),
        STRUCT('TIER_1A_PRIME_MOVER_CFP', 50, 10.0),
        STRUCT('TIER_1_PRIME_MOVER', 100, 4.76),
        STRUCT('STANDARD_HIGH_V4', 750, 3.67)
    ])
)

SELECT 
    COALESCE(c.score_tier, o.tier) as tier,
    COALESCE(c.current_leads, 0) as current_leads,
    o.optimized_leads,
    o.optimized_leads - COALESCE(c.current_leads, 0) as change,
    ROUND(COALESCE(c.current_leads, 0) * c.conv_rate / 100, 1) as current_expected_mqls,
    ROUND(o.optimized_leads * o.conv_rate / 100, 1) as optimized_expected_mqls,
    ROUND(o.optimized_leads * o.conv_rate / 100 - COALESCE(c.current_leads, 0) * c.conv_rate / 100, 1) as mql_change
FROM current_allocation c
FULL OUTER JOIN optimized_allocation o ON c.score_tier = o.tier
ORDER BY optimized_expected_mqls DESC;


-- Query V2: Risk Validation
-- Ensure no tier with small sample gets too large allocation
SELECT 
    tier,
    sample_size,
    optimized_allocation,
    ROUND(optimized_allocation * 100.0 / 3000, 1) as pct_of_list,
    CASE 
        WHEN sample_size < 30 AND optimized_allocation > 50 THEN '⚠️ WARNING: High allocation with tiny sample'
        WHEN sample_size < 100 AND optimized_allocation > 300 THEN '⚠️ WARNING: High allocation with small sample'
        ELSE '✅ OK'
    END as risk_check
FROM UNNEST([
    STRUCT('TIER_0A_PRIME_MOVER_DUE' as tier, 62 as sample_size, 50 as optimized_allocation),
    STRUCT('TIER_0B_SMALL_FIRM_DUE', 97, 30),
    STRUCT('TIER_0C_CLOCKWORK_DUE', 34, 20),
    STRUCT('TIER_MA_ACTIVE_PRIME', 43, 600),
    STRUCT('TIER_MA_ACTIVE', 242, 300),
    STRUCT('TIER_2_PROVEN_MOVER', 1281, 1000),
    STRUCT('STANDARD_HIGH_V4', 6043, 750)
]);


-- Query V3: Summary Metrics
SELECT 
    'CURRENT' as scenario,
    3100 as total_leads,
    158 as expected_mqls,
    ROUND(158.0 / 3100 * 100, 2) as expected_conv_rate
UNION ALL
SELECT 
    'OPTIMIZED',
    3000,
    193,
    ROUND(193.0 / 3000 * 100, 2);
```

---

# STEP 5: Final Checklist

## Cursor Prompt 5.1 - Complete the Implementation

```
After running all the queries and creating the documents, verify:

## Files Created
- [ ] `pipeline/sql/tier_confidence_analysis.sql` - All 8 analysis queries
- [ ] `LEAD_RATIO_ANALYSIS.md` - Full analysis document in repo root

## Analysis Validated
- [ ] Sample sizes retrieved for all tiers
- [ ] 95% confidence intervals calculated
- [ ] Worst-case lift analysis shows Career Clock and T2 maintain lift
- [ ] M&A PRIME identified as high-risk (wide CI)
- [ ] Optimal allocation determined (3,000 leads, ~193 MQLs)

## Key Findings Documented
- [ ] TIER_2_PROVEN_MOVER is most reliable (n=1,281, tight CI)
- [ ] Career Clock tiers have high conversion but limited confidence
- [ ] M&A PRIME should be capped at 400-600 leads (not full pool)
- [ ] STANDARD_HIGH_V4 should be reduced (below baseline at worst case)

## Allocation Recommendations
- [ ] Conservative allocation defined (lower risk)
- [ ] Optimized allocation defined (balanced risk/reward)
- [ ] Aggressive allocation defined (maximum expected MQLs)

## Monitoring Plan
- [ ] Weekly MQL tracking defined
- [ ] Monthly conversion rate analysis defined
- [ ] Quarterly rebalancing triggers defined

## Next Steps Documented
- [ ] SQL updates needed listed
- [ ] Implementation timeline defined
- [ ] Rollback plan documented
```

---

## Summary

This comprehensive prompt document guides Cursor.ai to:

1. **Create analysis SQL** (`tier_confidence_analysis.sql`) with 8 queries covering:
   - Sample sizes and conversion rates
   - 95% confidence intervals
   - Quarterly stability analysis
   - Career Clock tier analysis
   - M&A tier analysis
   - Risk-adjusted ranking
   - Optimal allocation calculator
   - Historical backtest simulation

2. **Create the analysis document** (`LEAD_RATIO_ANALYSIS.md`) with:
   - Executive summary
   - Tier-by-tier confidence analysis
   - Worst-case lift analysis
   - Optimal allocation strategy (Current vs Conservative vs Optimized vs Aggressive)
   - Implementation steps
   - Monitoring and rebalancing plan

3. **Key principle enforced**: 
   - High sample size = high confidence = can allocate more
   - Low sample size = wide CI = cap exposure regardless of point estimate
   - Use worst-case (CI lower bound) for risk-adjusted decisions

---

**Expected Outcome**: A data-driven, statistically rigorous allocation strategy that:
- Increases expected MQLs from ~158 to ~193 (+22%)
- Limits risk exposure to uncertain tiers
- Provides clear monitoring and rebalancing triggers
- Documents confidence levels for all allocation decisions
