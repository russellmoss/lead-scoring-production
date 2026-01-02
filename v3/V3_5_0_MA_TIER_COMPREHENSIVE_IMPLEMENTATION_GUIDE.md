# V3.5.0 M&A Active Tiers - Implementation Guide

**Document Version**: 1.0  
**Created**: January 2, 2026  
**Author**: Lead Scoring Team  
**Status**: 📋 READY FOR IMPLEMENTATION  

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Business Case](#2-business-case)
3. [Empirical Evidence](#3-empirical-evidence)
4. [What Went Wrong (V3.5.0 Attempt)](#4-what-went-wrong-v350-attempt)
5. [Recommended Architecture](#5-recommended-architecture)
6. [Pre-Implementation Verification](#6-pre-implementation-verification)
7. [Step-by-Step Implementation](#7-step-by-step-implementation)
8. [Post-Implementation Verification](#8-post-implementation-verification)
9. [Lead List Integration](#9-lead-list-integration)
10. [Maintenance & Refresh Schedule](#10-maintenance--refresh-schedule)
11. [Rollback Plan](#11-rollback-plan)
12. [Appendix: Full SQL Scripts](#12-appendix-full-sql-scripts)

---

## 1. Executive Summary

### What We Want

Add two new priority tiers to V3 lead scoring that capture advisors at firms undergoing M&A activity:

| Tier | Expected Conversion | Expected Lift | Target Population |
|------|---------------------|---------------|-------------------|
| **TIER_MA_ACTIVE_PRIME** | ~9.0% | 2.36x | Senior titles + mid-career at M&A targets |
| **TIER_MA_ACTIVE** | ~5.4% | 1.41x | All other advisors at M&A targets |

### Why We Want It

- **Large firms normally convert poorly** (0.60x baseline) → we exclude them
- **But M&A changes everything** → Commonwealth (2,500 reps) converted at 5.37% during LPL acquisition
- **Without M&A tiers, we miss these opportunities** → filters would have excluded Commonwealth advisors
- **Time-sensitive signal** → 60-365 day window after announcement

### How We'll Build It

**Simple, reliable architecture:**

1. **Pre-build a dedicated M&A advisors table** (`ml_features.ma_eligible_advisors`)
2. **Verify the table before lead list generation** (confirmation queries)
3. **Simple LEFT JOIN in lead list SQL** (no complex CTEs)
4. **Monthly refresh** (or ad-hoc when M&A news hits)

This approach avoids the BigQuery CTE scoping issues that caused the previous implementation to fail.

---

## 2. Business Case

### The Problem: Large Firm Exclusion

Our data shows that large firms (>50 reps) convert at 0.60x baseline:

| Firm Size | Conversion Rate | Lift vs Baseline |
|-----------|-----------------|------------------|
| ≤10 reps | 6.2% | 1.62x |
| 11-50 reps | 4.1% | 1.07x |
| **>50 reps** | **2.3%** | **0.60x** |

Based on this, we exclude firms >50 reps from lead lists. This is correct for normal circumstances.

### The Exception: M&A Creates Disruption

When a firm is being acquired, the dynamics change:

- **Uncertainty** about future platform, compensation, culture
- **Senior advisors** have the most at stake (equity, control, reputation)
- **Advisors actively evaluate options** during transition period
- **"Best advisors leave first"** phenomenon accelerates

### The Opportunity We're Missing

Without M&A tiers:
- Commonwealth (2,500 reps) would be **excluded** by >50 rep filter
- We would miss **5.37% conversion** opportunity
- Estimated **100-500 MQLs per major M&A event** lost

### Business Impact

| Scenario | M&A Events/Year | Advisors/Event | Conv Rate | MQLs Lost |
|----------|-----------------|----------------|-----------|-----------|
| Conservative | 2 | 1,000 | 5.4% | 108 |
| Moderate | 4 | 2,000 | 5.4% | 432 |
| Aggressive | 6 | 3,000 | 5.4% | 972 |

**Conclusion**: M&A tiers could generate 100-1,000 additional MQLs per year from a population we currently exclude.

---

## 3. Empirical Evidence

### Commonwealth/LPL Merger Analysis

**Event**: LPL Financial announced acquisition of Commonwealth Financial Network  
**Announcement Date**: July 2024  
**Analysis Period**: July 2024 - January 2026  

#### Overall Results

| Metric | Value |
|--------|-------|
| Total advisors at Commonwealth | ~2,500 |
| Advisors contacted | 242 |
| Conversions (MQLs) | 13 |
| **Conversion Rate** | **5.37%** |
| **Lift vs Baseline (3.82%)** | **1.41x** |

#### Profile Analysis

We analyzed which Commonwealth advisors converted best:

| Profile Factor | Contacted | Converted | Conv Rate | Lift | Action |
|----------------|-----------|-----------|-----------|------|--------|
| **Senior Titles** | 43 | 4 | 9.30% | 2.06x | ✅ Include in PRIME |
| **Mid-Career (10-20yr)** | 49 | 4 | 8.16% | 1.75x | ✅ Include in PRIME |
| Serial Movers (3+ firms) | 175 | 9 | 5.14% | 0.86x | ❌ Does NOT help |
| Newer to Firm (<5yr) | 86 | 4 | 4.65% | 0.81x | ❌ Does NOT help |
| Series 65 Only | 29 | 1 | 3.45% | 0.56x | ❌ Does NOT help |
| CFP Holders | 1 | 0 | 0% | - | ⚠️ Insufficient data |

#### Key Insights

1. **Senior titles convert best** (9.3%) - they have most at stake
2. **Mid-career advisors convert well** (8.2%) - established but not entrenched
3. **Serial movers do NOT convert better** (0.86x) - they're always in-market anyway
4. **Newer employees do NOT convert better** (0.81x) - less culturally invested

#### Timing Window Analysis

| Days Since Announcement | Status | Rationale |
|-------------------------|--------|-----------|
| 0-60 days | WATCH | Too early - advisors still processing news |
| **60-180 days** | **HOT** | **Optimal - uncertainty is peak** |
| **181-365 days** | **ACTIVE** | **Still elevated - deal in progress** |
| 365+ days | STALE | Deal closed, dust settled |

**Critical Insight**: Contact advisors WHILE they're still at the firm. Once they leave, conversion drops to ~1.2%.

### Statistical Caveats

⚠️ **Small Sample Warning**:
- Only 242 contacts, 13 conversions from ONE M&A event
- Profile findings have wide confidence intervals
- Results should be validated with future M&A events

Despite small sample, the signal is strong enough to deploy and track.

---

## 4. What Went Wrong (V3.5.0 Attempt)

### The Implementation

We attempted to add M&A tiers directly into the lead list SQL using CTEs:

```sql
-- What we tried
ma_target_firms AS (
    SELECT firm_crd, ma_status, ...
    FROM `ml_features.active_ma_target_firms`
    WHERE ma_status IN ('HOT', 'ACTIVE')
),

base_prospects AS (
    ...
    LEFT JOIN ma_target_firms ma_check ON ... -- CTE reference
    ...
),

enriched_prospects AS (
    ...
    LEFT JOIN ma_target_firms ma ON ... -- Another CTE reference
    ...
)
```

### What Happened

| Diagnostic Query | Result |
|------------------|--------|
| M&A advisors in source | 4,318 ✅ |
| M&A advisors should pass filters | 2,198 ✅ |
| M&A JOIN works in isolation | 2,225 ✅ |
| **M&A advisors in final table** | **0 ❌** |

### Root Cause: BigQuery CTE Scoping Issues

When CTEs are referenced across multiple levels in a complex query:
1. BigQuery may evaluate them in unexpected order
2. JOINs can silently return 0 matches
3. No error is thrown - query completes with wrong results

**The CTE was defined correctly, but references to it failed silently.**

### Lesson Learned

**Complex CTE chains in BigQuery are unreliable for critical business logic.**

Solution: Pre-build the M&A advisor data as a **materialized table** that can be verified before use.

---

## 5. Recommended Architecture

### Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    M&A TIER ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐    ┌──────────────────┐                  │
│  │ active_ma_target │    │ ria_contacts_    │                  │
│  │ _firms           │    │ current          │                  │
│  │ (66 firms)       │    │ (500K+ advisors) │                  │
│  └────────┬─────────┘    └────────┬─────────┘                  │
│           │                       │                             │
│           └───────────┬───────────┘                             │
│                       │                                         │
│                       ▼                                         │
│           ┌──────────────────────┐                              │
│           │ STEP 1: CREATE       │                              │
│           │ ma_eligible_advisors │  ← Pre-built, verified table │
│           │ (~2,000-4,000 rows)  │                              │
│           └──────────┬───────────┘                              │
│                      │                                          │
│                      │ Simple LEFT JOIN                         │
│                      ▼                                          │
│           ┌──────────────────────┐                              │
│           │ STEP 2: LEAD LIST    │                              │
│           │ January_2026_Lead_   │  ← Uses pre-built table      │
│           │ List_Main.sql        │                              │
│           └──────────────────────┘                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Why This Approach Works

| Aspect | CTE Approach (Failed) | Pre-Built Table (Recommended) |
|--------|----------------------|------------------------------|
| Verification | Cannot verify before use | Can verify table contents |
| Debugging | Silent failures | Visible row counts |
| Complexity | Multiple CTE references | Single LEFT JOIN |
| BigQuery behavior | Unpredictable | Reliable |
| Maintenance | Embedded in 1,400-line SQL | Separate, simple SQL |

### Tables Involved

| Table | Purpose | Refresh Frequency |
|-------|---------|-------------------|
| `active_ma_target_firms` | M&A target firm identification | Weekly (news feed) |
| **`ma_eligible_advisors`** | **Pre-built M&A advisor list** | **Monthly (or ad-hoc)** |
| `january_2026_lead_list` | Final lead list | Monthly |

---

## 6. Pre-Implementation Verification

**Run these queries BEFORE creating any new tables to confirm the data pipeline is healthy.**

### 6.1 Verify M&A Target Firms Exist

```sql
-- Query 6.1: Check active_ma_target_firms table
SELECT 
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

-- Expected: 
-- HOT: 30-50 firms, 60-180 days since news
-- ACTIVE: 20-40 firms, 181-365 days since news
```

### 6.2 Verify Advisors Exist at M&A Firms

```sql
-- Query 6.2: Count advisors at M&A target firms
SELECT 
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

-- Expected: 1,000-5,000 advisors at M&A target firms
```

### 6.3 Verify Data Type Compatibility

```sql
-- Query 6.3: Check data types match for JOINs
SELECT 
    'active_ma_target_firms.firm_crd' as column_source,
    (SELECT data_type 
     FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.COLUMNS`
     WHERE table_name = 'active_ma_target_firms' AND column_name = 'firm_crd') as data_type
UNION ALL
SELECT 
    'ria_contacts_current.PRIMARY_FIRM',
    (SELECT data_type 
     FROM `savvy-gtm-analytics.FinTrx_data_CA.INFORMATION_SCHEMA.COLUMNS`
     WHERE table_name = 'ria_contacts_current' AND column_name = 'PRIMARY_FIRM');

-- If types differ, we need SAFE_CAST in JOINs
```

### 6.4 Verify JOIN Works (Critical Test)

```sql
-- Query 6.4: Test the exact JOIN logic we'll use
SELECT 
    COUNT(*) as total_matches,
    COUNT(DISTINCT c.RIA_CONTACT_CRD_ID) as unique_advisors,
    COUNT(DISTINCT ma.firm_crd) as unique_firms
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
JOIN `savvy-gtm-analytics.ml_features.active_ma_target_firms` ma 
    ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = SAFE_CAST(ma.firm_crd AS INT64)
WHERE ma.ma_status IN ('HOT', 'ACTIVE')
  AND ma.firm_employees >= 10
  AND c.PRODUCING_ADVISOR = TRUE;

-- Expected: 1,000-5,000 matches
-- If 0: There's a JOIN issue (data type or data mismatch)
```

### 6.5 Verify Tier Assignment Logic

```sql
-- Query 6.5: Preview tier assignments
SELECT 
    CASE 
        WHEN UPPER(c.TITLE_NAME) LIKE '%PRESIDENT%' 
          OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%'
          OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%OWNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
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

-- Expected: Mix of PRIME and standard tiers
```

### Verification Checklist

| Check | Query | Expected | Actual | Pass? |
|-------|-------|----------|--------|-------|
| M&A firms exist | 6.1 | 50-90 firms | | |
| Advisors at M&A firms | 6.2 | 1,000-5,000 | | |
| Data types compatible | 6.3 | Both INT64 or castable | | |
| JOIN works | 6.4 | >0 matches | | |
| Tier logic works | 6.5 | Both tiers populated | | |

**⚠️ DO NOT PROCEED if any check fails. Debug the issue first.**

---

## 7. Step-by-Step Implementation

### Step 7.1: Create M&A Eligible Advisors Table

This table pre-computes all M&A-eligible advisors with their tier assignments.

```sql
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
        COALESCE(at.industry_tenure_months, 0) as industry_tenure_months,
        
        -- Senior title flag
        CASE WHEN (
            UPPER(c.TITLE_NAME) LIKE '%PRESIDENT%'
            OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%'
            OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%OWNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
        ) THEN 1 ELSE 0 END as is_senior_title,
        
        -- Mid-career flag (10-20 years = 120-240 months)
        CASE WHEN COALESCE(at.industry_tenure_months, 0) BETWEEN 120 AND 240 
        THEN 1 ELSE 0 END as is_mid_career
        
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN ma_firms ma ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ma.firm_crd
    LEFT JOIN advisor_tenure at ON c.RIA_CONTACT_CRD_ID = at.crd
    WHERE c.PRODUCING_ADVISOR = TRUE
      AND c.CONTACT_FIRST_NAME IS NOT NULL
      AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
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
    
    -- Metadata
    CURRENT_TIMESTAMP() as created_at,
    'V3.5.0' as model_version
    
FROM ma_advisors;

-- Log results
SELECT 
    ma_tier,
    COUNT(*) as advisor_count,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_conv_pct,
    COUNT(DISTINCT firm_crd) as unique_firms
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_tier
ORDER BY ma_tier;
```

### Step 7.2: Verify Table Creation

```sql
-- ============================================================================
-- STEP 7.2: VERIFY ma_eligible_advisors TABLE
-- ============================================================================

-- 7.2a: Row counts
SELECT 
    'Total Rows' as metric,
    COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
UNION ALL
SELECT 
    'Unique Advisors',
    COUNT(DISTINCT crd)
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
UNION ALL
SELECT 
    'Unique Firms',
    COUNT(DISTINCT firm_crd)
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`;

-- Expected: 1,000-5,000 rows, matching unique advisors, 40-80 firms

-- 7.2b: Tier distribution
SELECT 
    ma_tier,
    ma_status,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as pct
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_tier, ma_status
ORDER BY ma_tier, ma_status;

-- Expected: Mix of PRIME (20-40%) and standard (60-80%)

-- 7.2c: Sample records
SELECT *
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
WHERE ma_tier = 'TIER_MA_ACTIVE_PRIME'
LIMIT 10;

-- Verify: Senior titles or mid-career tenure visible
```

### Step 7.3: Modify Lead List SQL

Add a simple LEFT JOIN to the pre-built table in the lead list SQL.

#### 7.3a: Add JOIN in enriched_prospects CTE

Find the `enriched_prospects` CTE and add:

```sql
-- In enriched_prospects CTE, add this JOIN:
LEFT JOIN `savvy-gtm-analytics.ml_features.ma_eligible_advisors` ma 
    ON bp.crd = ma.crd
```

Add these fields to the SELECT:

```sql
-- M&A fields (V3.5.0)
COALESCE(ma.ma_tier, 'NOT_MA') as ma_tier_lookup,
CASE WHEN ma.crd IS NOT NULL THEN 1 ELSE 0 END as is_at_ma_target_firm,
ma.ma_status,
ma.days_since_first_news as ma_days_since_news,
ma.ma_firm_size,
ma.is_senior_title as ma_is_senior_title,
ma.is_mid_career as ma_is_mid_career,
```

#### 7.3b: Add M&A Tiers to score_tier CASE Statement

In `scored_prospects` CTE, add M&A tiers BEFORE Career Clock tiers:

```sql
CASE 
    -- ================================================================
    -- M&A ACTIVE TIERS (V3.5.0) - CHECKED FIRST
    -- ================================================================
    -- Advisors at firms being acquired get priority regardless of other factors
    -- Based on Commonwealth/LPL analysis: 5.37% overall, 9%+ for senior/mid-career
    -- ================================================================
    
    -- TIER_MA_ACTIVE_PRIME: Senior/Mid-Career at M&A target firms (~9%)
    WHEN ep.is_at_ma_target_firm = 1
         AND ep.ma_status IN ('HOT', 'ACTIVE')
         AND (ep.ma_is_senior_title = 1 OR ep.ma_is_mid_career = 1)
    THEN 'TIER_MA_ACTIVE_PRIME'
    
    -- TIER_MA_ACTIVE: All other advisors at M&A target firms (~5.4%)
    WHEN ep.is_at_ma_target_firm = 1
         AND ep.ma_status IN ('HOT', 'ACTIVE')
    THEN 'TIER_MA_ACTIVE'
    
    -- TIER 0: Career Clock Priority Tiers (V3.4.0)
    WHEN ccs.tenure_cv < 0.5 
         AND SAFE_DIVIDE(ep.tenure_months, ccs.avg_tenure_months) BETWEEN 0.7 AND 1.3
         ...
```

#### 7.3c: Add Large Firm Exclusion with M&A Exemption

In `tier_limited` CTE WHERE clause:

```sql
WHERE (
    (df.score_tier != 'STANDARD' AND df.score_tier NOT IN ('TIER_4_EXPERIENCED_MOVER', 'TIER_5_HEAVY_BLEEDER', 'TIER_NURTURE_TOO_EARLY'))
    OR (df.score_tier = 'STANDARD' AND df.v4_percentile >= 80)
)
-- V3.5.0: Large firm exclusion with M&A exemption
AND (
    df.firm_rep_count <= 50                    -- Normal: exclude large firms
    OR df.is_at_ma_target_firm = 1             -- M&A exemption: include regardless of size
)
```

#### 7.3d: Add M&A Tier Quotas

In `linkedin_prioritized` CTE WHERE clause:

```sql
-- M&A Tiers (V3.5.0) - generous quota since time-sensitive
OR (final_tier = 'TIER_MA_ACTIVE_PRIME' AND tier_rank <= CAST(150 * sc.total_sgas / 12.0 AS INT64))
OR (final_tier = 'TIER_MA_ACTIVE' AND tier_rank <= CAST(500 * sc.total_sgas / 12.0 AS INT64))
```

#### 7.3e: Update Priority ORDER BY Clauses

Add M&A tiers to ALL priority ORDER BY statements:

```sql
CASE final_tier
    -- Career Clock (highest)
    WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
    WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
    WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
    -- M&A Tiers (V3.5.0)
    WHEN 'TIER_MA_ACTIVE_PRIME' THEN 4
    WHEN 'TIER_MA_ACTIVE' THEN 5
    -- Zero Friction & Priority
    WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 6
    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 7
    ...
END
```

---

## 8. Post-Implementation Verification

**Run these queries AFTER creating the lead list to verify M&A advisors are present.**

### 8.1 Verify M&A Advisors in Lead List

```sql
-- Query 8.1: Check M&A tier population
SELECT 
    score_tier,
    COUNT(*) as lead_count,
    COUNT(DISTINCT firm_crd) as unique_firms,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_conv_pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
GROUP BY score_tier
ORDER BY score_tier;

-- Expected:
-- TIER_MA_ACTIVE_PRIME: 50-200 leads
-- TIER_MA_ACTIVE: 100-500 leads
```

### 8.2 Verify Large Firm Exemption Working

```sql
-- Query 8.2: Check firm size distribution for M&A vs non-M&A
SELECT 
    CASE WHEN score_tier LIKE 'TIER_MA%' THEN 'M&A Tier' ELSE 'Other Tier' END as tier_category,
    CASE 
        WHEN firm_rep_count <= 50 THEN '≤50 reps'
        WHEN firm_rep_count <= 200 THEN '51-200 reps'
        ELSE '>200 reps'
    END as firm_size_bucket,
    COUNT(*) as lead_count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY 1, 2
ORDER BY 1, 2;

-- Expected:
-- M&A Tier + >50 reps: >0 (exemption working)
-- Other Tier + >50 reps: 0 (exclusion working)
```

### 8.3 Verify No Non-M&A Large Firms Snuck In

```sql
-- Query 8.3: Safety check - no large firms without M&A
SELECT COUNT(*) as violations
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE firm_rep_count > 50
  AND score_tier NOT LIKE 'TIER_MA%'
  AND is_at_ma_target_firm != 1;

-- Expected: 0 violations
```

### 8.4 Spot Check M&A Leads

```sql
-- Query 8.4: Sample M&A leads for manual review
SELECT 
    crd,
    first_name,
    last_name,
    firm_name,
    job_title,
    score_tier,
    ma_status,
    ma_days_since_news,
    firm_rep_count,
    expected_conversion_rate
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
ORDER BY 
    CASE score_tier WHEN 'TIER_MA_ACTIVE_PRIME' THEN 1 ELSE 2 END,
    ma_days_since_news
LIMIT 20;

-- Manual check: Do these look like real M&A targets?
```

### Post-Implementation Checklist

| Check | Query | Expected | Actual | Pass? |
|-------|-------|----------|--------|-------|
| M&A tiers populated | 8.1 | 150-700 leads | | |
| Large firm exemption works | 8.2 | M&A >50 reps exists | | |
| No violations | 8.3 | 0 | | |
| Spot check looks good | 8.4 | Manual review OK | | |

---

## 9. Lead List Integration

### Modified Lead List SQL Structure

```
January_2026_Lead_List_Main.sql
├── CTEs (unchanged)
│   ├── active_sgas
│   ├── excluded_firms
│   ├── salesforce_crds
│   ├── recyclable_lead_ids
│   ├── advisor_moves
│   ├── firm_headcount
│   ├── firm_departures
│   ├── firm_arrivals
│   └── firm_metrics
│
├── base_prospects (unchanged)
│
├── enriched_prospects (MODIFIED)
│   └── ADD: LEFT JOIN ma_eligible_advisors
│   └── ADD: M&A fields (is_at_ma_target_firm, ma_status, etc.)
│
├── v4_enriched (unchanged)
├── v4_filtered (unchanged)
├── career_clock_stats (unchanged)
│
├── scored_prospects (MODIFIED)
│   └── ADD: TIER_MA_ACTIVE_PRIME tier logic
│   └── ADD: TIER_MA_ACTIVE tier logic
│   └── ADD: M&A tier priority ranks
│   └── ADD: M&A conversion rates
│   └── ADD: M&A narratives
│
├── ranked_prospects (unchanged)
├── diversity_filtered (unchanged)
│
├── tier_limited (MODIFIED)
│   └── ADD: Large firm exclusion with M&A exemption
│
├── deduplicated_before_quotas (MODIFIED)
│   └── ADD: M&A tiers to ORDER BY
│
├── linkedin_prioritized (MODIFIED)
│   └── ADD: M&A tier quotas
│   └── ADD: M&A tiers to ORDER BY
│
└── final_output (MODIFIED)
    └── ADD: M&A fields to output columns
```

### Output Schema Additions

| Column | Type | Description |
|--------|------|-------------|
| `is_at_ma_target_firm` | INT64 | 1 if advisor is at M&A target firm |
| `ma_status` | STRING | 'HOT', 'ACTIVE', or NULL |
| `ma_days_since_news` | INT64 | Days since first M&A announcement |
| `ma_firm_size` | INT64 | Employee count at M&A firm |
| `ma_is_senior_title` | INT64 | 1 if has senior title |
| `ma_is_mid_career` | INT64 | 1 if 10-20 years experience |

---

## 10. Maintenance & Refresh Schedule

### Table Refresh Frequency

| Table | Refresh | Trigger | Owner |
|-------|---------|---------|-------|
| `active_ma_target_firms` | Weekly | Automated (FINTRX news feed) | Pipeline |
| **`ma_eligible_advisors`** | **Monthly** | **Manual (before lead list gen)** | **Data Team** |
| `january_2026_lead_list` | Monthly | Manual | Data Team |

### Refresh Procedure

1. **Check for new M&A activity**
   ```sql
   SELECT * FROM `ml_features.active_ma_target_firms`
   WHERE created_at >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
   ORDER BY created_at DESC;
   ```

2. **Refresh ma_eligible_advisors** (Step 7.1)

3. **Verify counts** (Step 7.2)

4. **Generate lead list**

5. **Verify M&A leads present** (Section 8)

### Ad-Hoc Refresh Triggers

Refresh `ma_eligible_advisors` immediately when:
- Major M&A announcement (top 50 firm)
- M&A deal closes (update status)
- Significant advisor departures from M&A firm
- Monthly lead list generation

---

## 11. Rollback Plan

If M&A tiers cause issues in production:

### Quick Rollback (Minutes)

Remove M&A advisors from lead list without regenerating:

```sql
-- Create backup
CREATE TABLE `ml_features.january_2026_lead_list_backup` AS
SELECT * FROM `ml_features.january_2026_lead_list`;

-- Remove M&A leads
DELETE FROM `ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%';
```

### Full Rollback (30 minutes)

1. Restore previous lead list SQL (without M&A modifications)
2. Regenerate lead list
3. Verify M&A leads not present

### Rollback Criteria

Consider rollback if:
- M&A tier conversion rate < 3% after 60 days
- Excessive complaints from M&A firm advisors
- Data quality issues in M&A identification

---

## 12. Appendix: Full SQL Scripts

### A. Complete ma_eligible_advisors Creation Script

```sql
-- ============================================================================
-- FULL SCRIPT: CREATE ma_eligible_advisors
-- ============================================================================
-- Run this script to create/refresh the M&A eligible advisors table
-- Execution time: ~30 seconds
-- Output: ml_features.ma_eligible_advisors
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.ma_eligible_advisors` AS

WITH 
advisor_tenure AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE) as career_start_date,
        DATE_DIFF(CURRENT_DATE(), MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE), MONTH) as industry_tenure_months
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
    GROUP BY RIA_CONTACT_CRD_ID
),

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
        COALESCE(at.industry_tenure_months, 0) as industry_tenure_months,
        CASE WHEN (
            UPPER(c.TITLE_NAME) LIKE '%PRESIDENT%'
            OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%'
            OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%OWNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
        ) THEN 1 ELSE 0 END as is_senior_title,
        CASE WHEN COALESCE(at.industry_tenure_months, 0) BETWEEN 120 AND 240 
        THEN 1 ELSE 0 END as is_mid_career
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN ma_firms ma ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ma.firm_crd
    LEFT JOIN advisor_tenure at ON c.RIA_CONTACT_CRD_ID = at.crd
    WHERE c.PRODUCING_ADVISOR = TRUE
      AND c.CONTACT_FIRST_NAME IS NOT NULL
      AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
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
    CASE 
        WHEN is_senior_title = 1 OR is_mid_career = 1 
        THEN 'TIER_MA_ACTIVE_PRIME'
        ELSE 'TIER_MA_ACTIVE'
    END as ma_tier,
    CASE 
        WHEN is_senior_title = 1 OR is_mid_career = 1 
        THEN 0.09
        ELSE 0.054
    END as expected_conversion_rate,
    CURRENT_TIMESTAMP() as created_at,
    'V3.5.0' as model_version
FROM ma_advisors;

-- Verification output
SELECT 
    ma_tier,
    ma_status,
    COUNT(*) as advisor_count,
    COUNT(DISTINCT firm_crd) as unique_firms,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_conv_pct
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_tier, ma_status
ORDER BY ma_tier, ma_status;
```

### B. Complete Verification Query Suite

```sql
-- ============================================================================
-- FULL VERIFICATION SUITE
-- ============================================================================
-- Run all queries in sequence to verify implementation
-- ============================================================================

-- 1. Pre-implementation checks
SELECT '=== PRE-IMPLEMENTATION CHECKS ===' as section;

SELECT 'M&A Target Firms' as check_name, COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.active_ma_target_firms`
WHERE ma_status IN ('HOT', 'ACTIVE');

SELECT 'Advisors at M&A Firms' as check_name, COUNT(DISTINCT c.RIA_CONTACT_CRD_ID) as value
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
JOIN `savvy-gtm-analytics.ml_features.active_ma_target_firms` ma 
    ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = SAFE_CAST(ma.firm_crd AS INT64)
WHERE ma.ma_status IN ('HOT', 'ACTIVE') AND c.PRODUCING_ADVISOR = TRUE;

-- 2. ma_eligible_advisors table checks
SELECT '=== MA_ELIGIBLE_ADVISORS TABLE ===' as section;

SELECT 'Total Rows' as metric, COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`;

SELECT ma_tier, COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_tier;

-- 3. Lead list checks
SELECT '=== LEAD LIST CHECKS ===' as section;

SELECT 'M&A Tier Leads' as metric, COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%';

SELECT score_tier, COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
GROUP BY score_tier;

-- 4. Large firm exemption check
SELECT '=== LARGE FIRM EXEMPTION ===' as section;

SELECT 
    CASE WHEN score_tier LIKE 'TIER_MA%' THEN 'M&A' ELSE 'Non-M&A' END as tier_type,
    CASE WHEN firm_rep_count > 50 THEN '>50 reps' ELSE '≤50 reps' END as size,
    COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY 1, 2
ORDER BY 1, 2;

-- 5. Violations check
SELECT '=== VIOLATIONS CHECK ===' as section;

SELECT 'Large Firm Violations' as check_name,
    COUNT(*) as violations
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE firm_rep_count > 50
  AND score_tier NOT LIKE 'TIER_MA%';
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-02 | Lead Scoring Team | Initial comprehensive guide |

---

**End of Document**
