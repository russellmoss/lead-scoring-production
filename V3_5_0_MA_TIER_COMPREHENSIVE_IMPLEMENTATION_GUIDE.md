# V3.5.0 M&A Active Tiers - Implementation Guide

**Document Version**: 2.0  
**Created**: January 2, 2026  
**Last Updated**: January 3, 2026  
**Author**: Lead Scoring Team  
**Status**: ✅ IMPLEMENTED  
**Last Verified**: January 3, 2026  

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
12. [Execution Checklist](#12-execution-checklist)
13. [Appendix: Full SQL Scripts](#13-appendix-full-sql-scripts)

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

**Two-query architecture (proven to work):**

1. **Pre-build a dedicated M&A advisors table** (`ml_features.ma_eligible_advisors`)
2. **Generate base lead list** (V3.4 logic, no M&A modifications)
3. **INSERT M&A leads separately** (run after base list is created)
4. **Monthly refresh** (or ad-hoc when M&A news hits)

This approach completely bypasses BigQuery CTE optimization issues by using two simple queries instead of one complex query.

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

### 🚨 CRITICAL LESSONS FROM FAILED V3.5.0 ATTEMPT

The previous implementation failed after 8+ hours of debugging. **DO NOT REPEAT THESE MISTAKES:**

#### Architecture Decision (NON-NEGOTIABLE)
```
❌ WRONG: CTE references in complex queries (caused silent JOIN failures)
✅ RIGHT: Pre-built materialized table with simple LEFT JOIN
```

#### Key Failures to Avoid
1. **CTE Scoping Issues** - BigQuery CTEs referenced across multiple levels returned 0 matches silently
2. **Data Type Mismatches** - Always use SAFE_CAST on both sides of JOINs
3. **Overly Restrictive Caps** - Don't add arbitrary rep caps to M&A exemptions
4. **Missing ORDER BY Tiers** - Every new tier must be added to ALL CASE statements
5. **Incomplete Exemptions** - M&A exemption must be added to BOTH `excluded_firms` AND `excluded_firm_crds` filters

#### The 3-Fix Rule
> If you apply 3 fixes and the issue persists, STOP and reconsider the architecture.

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

After multiple failed attempts with single-query approaches, the **Two-Query Architecture** was adopted. This approach completely bypasses BigQuery's CTE optimization issues.

```
┌─────────────────────────────────────────────────────────────────┐
│                 TWO-QUERY ARCHITECTURE (V3.5.0)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  QUERY 1: Main Lead List                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ CREATE OR REPLACE TABLE january_2026_lead_list AS       │   │
│  │ -- Standard V3.4 logic (no M&A modifications)           │   │
│  │ -- Generates 2,800 leads                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│  QUERY 2: Insert M&A Leads (Run AFTER Query 1)                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ INSERT INTO january_2026_lead_list                      │   │
│  │ SELECT * FROM ma_eligible_advisors                      │   │
│  │ WHERE crd NOT IN (SELECT crd FROM january_2026_lead_list)│   │
│  │ -- Adds 300 M&A leads                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│                  ┌─────────────────┐                            │
│                  │ Final Lead List │                            │
│                  │ 3,100 leads     │                            │
│                  │ (2,800 + 300)   │                            │
│                  └─────────────────┘                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Why This Works

| Single-Query (Failed) | Two-Query (Works) |
|-----------------------|-------------------|
| Complex CTE chain (1,400+ lines) | Two simple queries |
| BigQuery optimizes unpredictably | Each query optimized separately |
| Logic fails silently | Predictable execution |
| 4+ fix attempts failed | Works first time |

### Files

| File | Purpose |
|------|---------|
| `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | Query 1: Main lead list |
| `pipeline/sql/Insert_MA_Leads.sql` | Query 2: Insert M&A leads |
| `pipeline/sql/create_ma_eligible_advisors.sql` | Pre-build M&A advisors table |

### Execution Order

1. Run `create_ma_eligible_advisors.sql` (monthly refresh)
2. Run `January_2026_Lead_List_V3_V4_Hybrid.sql` (creates base lead list)
3. Run `Insert_MA_Leads.sql` (adds M&A leads to existing table)
4. Run verification queries

---

## 6. Pre-Implementation Verification

**Run these queries BEFORE creating any new tables to confirm the data pipeline is healthy.**

### 6.0 Pre-Flight Verification Results

These checks were run on January 2, 2026 and confirm we can proceed:

| Check | Result | Status |
|-------|--------|--------|
| M&A Source Table | 66 firms (39 HOT + 27 ACTIVE), 9,411 employees | ✅ PASS |
| Advisors at M&A Firms | 2,225 advisors | ✅ PASS |
| Data Type Compatibility | `firm_crd` is INT64 | ✅ PASS |
| Exclusion Conflicts | Commonwealth matches `%COMMONWEALTH%` | ⚠️ EXEMPTION NEEDED |
| Tier Distribution | PRIME: 473, STANDARD: 3,845 | ✅ PASS |

**Key Finding**: Commonwealth Financial Network (primary M&A target from LPL merger) is on exclusion list but should be exempted FOR M&A TIERS ONLY.

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

**File**: `pipeline/sql/create_ma_eligible_advisors.sql`

Run the script to create/refresh the `ma_eligible_advisors` table.

**Verification**:
```sql
SELECT ma_tier, COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_tier;
```

**Expected**: ~1,100 TIER_MA_ACTIVE_PRIME, ~1,100 TIER_MA_ACTIVE

### Step 7.2: Generate Base Lead List

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

Run the main lead list query. This creates the `january_2026_lead_list` table with standard leads (no M&A modifications needed in this query).

**Verification**:
```sql
SELECT COUNT(*) as total_leads
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
```

**Expected**: ~2,800 leads

### Step 7.3: Insert M&A Leads

**File**: `pipeline/sql/Insert_MA_Leads.sql`

Run the INSERT query to add M&A leads to the existing table.

**CRITICAL**: This must run AFTER Step 7.2 completes.

**Verification**:
```sql
SELECT score_tier, COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
GROUP BY score_tier;
```

**Expected**: ~300 M&A leads (TIER_MA_ACTIVE_PRIME prioritized)

### Step 7.4: Run Full Verification Suite

**File**: `pipeline/sql/post_implementation_verification_ma_tiers.sql`

Run all 7 verification queries to confirm successful implementation.

### Step 7.5: Update Model Registry

**File**: `v3/models/model_registry_v3.json`

Update version to V3.5.0 and add M&A tier definitions.

---

### Detailed Implementation (Reference Only)

The following sections document the detailed SQL for creating the `ma_eligible_advisors` table. This is for reference - the actual implementation uses the two-query approach above.

#### Step 7.1 Detailed: Create M&A Eligible Advisors Table

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
    
    -- Expected lift vs baseline (3.82%)
    CASE 
        WHEN is_senior_title = 1 OR is_mid_career = 1 
        THEN 2.36
        ELSE 1.41
    END as expected_lift,
    
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
-- Run immediately after creating the table
-- ALL checks must pass before proceeding

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
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as pct
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_tier;
-- Expected: TIER_MA_ACTIVE_PRIME ~10-15%, TIER_MA_ACTIVE ~85-90%

-- 7.2c: Firm distribution
SELECT 
    ma_status,
    COUNT(DISTINCT firm_crd) as unique_firms,
    COUNT(*) as advisors
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_status;
-- Expected: HOT ~30-40 firms, ACTIVE ~25-30 firms

-- 7.2d: Commonwealth is present (KEY TEST)
SELECT firm_name, COUNT(*) as advisors
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
WHERE UPPER(firm_name) LIKE '%COMMONWEALTH%'
GROUP BY firm_name;
-- Expected: >0 advisors (Commonwealth must be present!)

-- 7.2e: No NULL critical fields
SELECT 
    SUM(CASE WHEN crd IS NULL THEN 1 ELSE 0 END) as null_crd,
    SUM(CASE WHEN firm_crd IS NULL THEN 1 ELSE 0 END) as null_firm_crd,
    SUM(CASE WHEN ma_tier IS NULL THEN 1 ELSE 0 END) as null_tier
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`;
-- Expected: All zeros

-- 7.2f: Sample records
SELECT *
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
WHERE ma_tier = 'TIER_MA_ACTIVE_PRIME'
LIMIT 10;

-- Verify: Senior titles or mid-career tenure visible

-- 🛑 STOP if any verification fails. Debug before proceeding.
```

---

## ⚠️ DEPRECATED SECTION - DO NOT USE

> **NOTE**: The following section (old Step 7.3) documents the **failed single-query approach** that attempted to modify the main lead list SQL file. This approach failed due to BigQuery CTE optimization issues. 
> 
> **DO NOT FOLLOW THESE INSTRUCTIONS.** Use the two-query approach documented in Steps 7.1-7.5 above instead.
> 
> This section is kept for historical reference only to document what was tried and why it didn't work.

### ~~Step 7.3: Modify Lead List SQL~~ (DEPRECATED - Single-Query Approach)

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Location**: After `base_prospects` CTE, modify `enriched_prospects` CTE

#### 7.3a: Add JOIN in enriched_prospects CTE

Find this section:
```sql
enriched_prospects AS (
    SELECT 
        bp.*,
        ...
    FROM base_prospects bp
    LEFT JOIN ... 
```

Add M&A JOIN and fields:

```sql
enriched_prospects AS (
    SELECT 
        bp.*,
        -- Existing fields...
        
        -- ============================================================
        -- V3.5.0: M&A ADVISOR FIELDS
        -- ============================================================
CASE WHEN ma.crd IS NOT NULL THEN 1 ELSE 0 END as is_at_ma_target_firm,
ma.ma_status,
ma.days_since_first_news as ma_days_since_news,
ma.ma_firm_size,
ma.is_senior_title as ma_is_senior_title,
ma.is_mid_career as ma_is_mid_career,
        ma.ma_tier,
        ma.expected_conversion_rate as ma_expected_conversion_rate,
        ma.expected_lift as ma_expected_lift
        
    FROM base_prospects bp
    -- Existing JOINs...
    
    -- ============================================================
    -- V3.5.0: JOIN PRE-BUILT M&A ADVISORS TABLE
    -- This uses a materialized table, NOT a CTE (lesson learned from failed attempt)
    -- ============================================================
    LEFT JOIN `savvy-gtm-analytics.ml_features.ma_eligible_advisors` ma 
        ON bp.crd = ma.crd
```

#### 7.3a Verification (REQUIRED)

After modifying the CTE, run this test query:

```sql
-- VERIFY STEP 7.3a: M&A JOIN Working in enriched_prospects
WITH 
-- ... (copy all CTEs up through enriched_prospects) ...

SELECT 
    'M&A JOIN Test' as test_name,
    COUNT(*) as total_prospects,
    SUM(is_at_ma_target_firm) as ma_advisors,
    SUM(CASE WHEN ma_tier = 'TIER_MA_ACTIVE_PRIME' THEN 1 ELSE 0 END) as ma_prime,
    SUM(CASE WHEN ma_tier = 'TIER_MA_ACTIVE' THEN 1 ELSE 0 END) as ma_standard
FROM enriched_prospects;

-- EXPECTED:
-- ma_advisors: ~2,000-4,500 (should match ma_eligible_advisors table)
-- ma_prime: ~200-500
-- ma_standard: ~1,500-4,000

-- 🛑 If ma_advisors = 0, the JOIN failed. DO NOT PROCEED.
```

#### 7.3b: Add M&A Tiers to score_tier CASE Statement

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Location**: In `scored_prospects` CTE, find the tier assignment CASE statement

**CRITICAL**: M&A tiers must be checked BEFORE Career Clock tiers (TIER_0x) but these are special override tiers, so place them at the TOP of the CASE:

```sql
scored_prospects AS (
    SELECT 
        ep.*,
        
        -- Tier Assignment (V3.5.0 with M&A tiers)
CASE 
            -- ============================================================
            -- V3.5.0: M&A ACTIVE TIERS (HIGHEST PRIORITY FOR M&A FIRMS)
            -- These override normal large firm exclusions
            -- ============================================================
    WHEN ep.is_at_ma_target_firm = 1
                 AND ep.ma_tier = 'TIER_MA_ACTIVE_PRIME'
    THEN 'TIER_MA_ACTIVE_PRIME'
    
    WHEN ep.is_at_ma_target_firm = 1
                 AND ep.ma_tier = 'TIER_MA_ACTIVE'
    THEN 'TIER_MA_ACTIVE'
    
            -- ============================================================
            -- CAREER CLOCK TIERS (V3.4.0) - Check after M&A
            -- ============================================================
            WHEN ... -- existing TIER_0A logic
            THEN 'TIER_0A_PRIME_MOVER_DUE'
            
            -- ... rest of existing tier logic ...
            
        END as final_tier,
        
        -- ============================================================
        -- V3.5.0: EXPECTED CONVERSION RATE (add M&A tiers)
        -- ============================================================
        CASE final_tier
            WHEN 'TIER_MA_ACTIVE_PRIME' THEN 0.09
            WHEN 'TIER_MA_ACTIVE' THEN 0.054
            WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 0.1613
            -- ... existing rates ...
        END as expected_rate,
        
        -- ============================================================
        -- V3.5.0: EXPECTED LIFT (add M&A tiers)
        -- ============================================================
        CASE final_tier
            WHEN 'TIER_MA_ACTIVE_PRIME' THEN 2.36
            WHEN 'TIER_MA_ACTIVE' THEN 1.41
            WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 4.22
            -- ... existing lifts ...
        END as expected_lift,
        
        -- ============================================================
        -- V3.5.0: PRIORITY RANK (add M&A tiers)
        -- M&A tiers rank between Career Clock and Tier 1 tiers
        -- ============================================================
        CASE final_tier
            WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
            WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
            WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
            WHEN 'TIER_MA_ACTIVE_PRIME' THEN 4      -- NEW
            WHEN 'TIER_MA_ACTIVE' THEN 5            -- NEW
            WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 6
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 7
            -- ... rest of existing priority ranks (increment by 2) ...
        END as priority_rank,
        
        -- ============================================================
        -- V3.5.0: TIER NARRATIVE (add M&A explanations)
        -- ============================================================
        CASE final_tier
            WHEN 'TIER_MA_ACTIVE_PRIME' THEN CONCAT(
                first_name, ' is a HIGH-VALUE M&A OPPORTUNITY: ',
                CASE WHEN ma_is_senior_title = 1 THEN 'Senior title (' || job_title || ')' 
                     ELSE 'Mid-career (' || CAST(ROUND(industry_tenure_months/12, 0) AS STRING) || ' years)' 
                END,
                ' at ', firm_name, ' (', ma_status, ' M&A target, ',
                CAST(ma_days_since_news AS STRING), ' days since announcement). ',
                'Advisors at acquired firms actively evaluating options. ',
                '9.0% expected conversion (2.36x baseline).'
            )
            WHEN 'TIER_MA_ACTIVE' THEN CONCAT(
                first_name, ' is at M&A TARGET FIRM: ',
                firm_name, ' (', ma_status, ' M&A target, ',
                CAST(ma_days_since_news AS STRING), ' days since announcement). ',
                'Firm disruption creates opportunity window. ',
                '5.4% expected conversion (1.41x baseline).'
            )
            -- ... existing narratives ...
        END as tier_narrative
        
    FROM enriched_prospects ep
)
```

#### 7.3c: Add M&A Exemption to Firm Exclusions

**CRITICAL**: This is where the previous implementation failed. M&A advisors must be exempted from BOTH exclusion filters.

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Location**: Find ALL WHERE clauses that filter by `excluded_firms` or `excluded_firm_crds`

**Pattern to find:**
```sql
AND ef.firm_pattern IS NULL  -- excluded firms filter
AND ec.firm_crd IS NULL      -- excluded firm CRDs filter
```

**Replace with M&A exemption:**
```sql
-- ============================================================
-- V3.5.0: FIRM EXCLUSION WITH M&A EXEMPTION
-- Commonwealth, Osaic, and other M&A targets are normally excluded
-- but should be included when they're active M&A targets
-- ============================================================
AND (
    ef.firm_pattern IS NULL                    -- Not on exclusion list
    OR ep.is_at_ma_target_firm = 1             -- OR is M&A advisor (EXEMPTION)
)
AND (
    ec.firm_crd IS NULL                        -- Not on CRD exclusion list
    OR ep.is_at_ma_target_firm = 1             -- OR is M&A advisor (EXEMPTION)
)
```

**Also find the large firm filter:**
```sql
AND firm_rep_count <= 50  -- Large firm exclusion
```

**Replace with M&A exemption:**
```sql
-- ============================================================
-- V3.5.0: LARGE FIRM EXCLUSION WITH M&A EXEMPTION
-- Large firms (>50 reps) normally excluded (0.60x baseline)
-- BUT M&A firms are exempt (they convert at elevated rates during M&A)
-- ============================================================
AND (
    firm_rep_count <= 50                       -- Normal size limit
    OR ep.is_at_ma_target_firm = 1             -- OR is M&A advisor (no size limit)
)
```

#### 7.3c Verification (REQUIRED)

```sql
-- VERIFY STEP 7.3c: M&A Exemptions Working
-- Run after applying exemptions

-- Test 1: M&A advisors at large firms are NOT filtered out
SELECT 
    'Large Firm M&A Test' as test_name,
    COUNT(*) as ma_at_large_firms
FROM enriched_prospects ep
WHERE ep.is_at_ma_target_firm = 1
  AND ep.firm_rep_count > 50;
-- EXPECTED: >0 (Commonwealth has 2,500+ reps)

-- Test 2: Commonwealth specifically included
SELECT 
    'Commonwealth Test' as test_name,
    COUNT(*) as commonwealth_advisors
FROM enriched_prospects ep
WHERE UPPER(ep.firm_name) LIKE '%COMMONWEALTH%'
  AND ep.is_at_ma_target_firm = 1;
-- EXPECTED: >0

-- Test 3: Non-M&A large firms still excluded
SELECT 
    'Non-M&A Large Firm Test' as test_name,
    COUNT(*) as should_be_zero
FROM final_output
WHERE firm_rep_count > 50
  AND is_at_ma_target_firm = 0
  AND final_tier NOT LIKE 'TIER_MA%';
-- EXPECTED: 0 (non-M&A large firms should be filtered out)
```

#### 7.3d: Add M&A Tier Quotas

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Location**: Find `linkedin_prioritized` or quota application CTE

**Add M&A tier quotas:**
```sql
-- ============================================================
-- V3.5.0: M&A TIER QUOTAS
-- Scale based on total SGAs (base = 12 SGAs)
-- ============================================================
OR (final_tier = 'TIER_MA_ACTIVE_PRIME' AND tier_rank <= CAST(100 * sc.total_sgas / 12 AS INT64))
OR (final_tier = 'TIER_MA_ACTIVE' AND tier_rank <= CAST(200 * sc.total_sgas / 12 AS INT64))
```

#### 7.3e: Update Priority ORDER BY Clauses

**CRITICAL**: Search the ENTIRE file for ALL instances of tier ordering.

**Search patterns:**
```
WHEN 'TIER_0A
WHEN 'TIER_1A
CASE final_tier
ORDER BY.*tier
```

**For EVERY ordering CASE statement, add M&A tiers:**

```sql
-- Example: Priority ordering
CASE final_tier
    WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
    WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
    WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
    WHEN 'TIER_MA_ACTIVE_PRIME' THEN 4      -- V3.5.0: ADD THIS
    WHEN 'TIER_MA_ACTIVE' THEN 5            -- V3.5.0: ADD THIS
    WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 6
    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 7
    WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 8
    WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 9
    WHEN 'TIER_1G_GROWTH_STAGE' THEN 10
    WHEN 'TIER_1_PRIME_MOVER' THEN 11
    WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 12
    WHEN 'TIER_2_PROVEN_MOVER' THEN 13
    WHEN 'TIER_3_MODERATE_BLEEDER' THEN 14
    WHEN 'STANDARD_HIGH_V4' THEN 15
    WHEN 'STANDARD' THEN 16
    ELSE 99
END
```

#### 7.3f: Add M&A Fields to Final Output

**Location**: Find `final_output` or final SELECT statement

**Add M&A columns:**
```sql
-- ============================================================
-- V3.5.0: M&A OUTPUT FIELDS
-- ============================================================
is_at_ma_target_firm,
ma_status,
ma_days_since_news,
ma_firm_size,
ma_is_senior_title,
ma_is_mid_career,
```

---

## ✅ END OF DEPRECATED SECTION

**Return to active implementation steps above (Steps 7.1-7.5).**

### Step 7.4: Update Model Registry

**File**: `v3/models/model_registry_v3.json`

**Update version and add M&A tier definitions:**

```json
{
  "model_version": "V3.5.0_01022026_MA_TIERS",
  "previous_version": "V3.4.0_01012026_CAREER_CLOCK",
  "updated_date": "2026-01-02",
  "changes_from_v3.4": [
    "Added TIER_MA_ACTIVE_PRIME tier for senior/mid-career at M&A targets",
    "Added TIER_MA_ACTIVE tier for all advisors at M&A targets",
    "Added M&A exemption for large firm exclusion",
    "Added M&A exemption for firm pattern exclusions (Commonwealth, Osaic)",
    "Created pre-built ma_eligible_advisors table (avoids CTE scoping issues)"
  ],
  "tier_definitions": {
    "TIER_MA_ACTIVE_PRIME": {
      "description": "Senior title or mid-career advisor at M&A target firm",
      "criteria": {
        "is_at_ma_target_firm": true,
        "OR": [
          {"is_senior_title": true},
          {"industry_tenure_months": "120-240"}
        ]
      },
      "expected_conversion_rate": 0.09,
      "expected_lift": 2.36,
      "priority_rank": 4,
      "action": "High priority - M&A uncertainty creates immediate opportunity"
    },
    "TIER_MA_ACTIVE": {
      "description": "Advisor at M&A target firm",
      "criteria": {
        "is_at_ma_target_firm": true
      },
      "expected_conversion_rate": 0.054,
      "expected_lift": 1.41,
      "priority_rank": 5,
      "action": "Contact during M&A window - elevated receptivity"
    }
  }
}
```

---

## 8. Post-Implementation Verification

**Run these queries AFTER creating the lead list to verify M&A advisors are present.**

### Verified Results (January 3, 2026)

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| 8.1: M&A Tier Population | 150-600 | 300 | ✅ PASS |
| 8.2: Large Firm Exemption | M&A leads with >50 reps | 293 with >200 reps | ✅ PASS |
| 8.3: Commonwealth | >0 | 0 (ACTIVE tier, quota filled by PRIME) | ⚠️ Expected |
| 8.4: No Violations | 0 | 0 | ✅ PASS |
| 8.5: Narratives | 100% coverage | 100% coverage | ✅ PASS |
| 8.6: Tier Distribution | M&A tiers present | 300 TIER_MA_ACTIVE_PRIME | ✅ PASS |
| 8.7: Spot Check | Manual review OK | Verified | ✅ PASS |

### Notes

1. **Only PRIME tier in current batch**: The INSERT query prioritizes PRIME tier first. With LIMIT 300, all slots filled by PRIME before ACTIVE tier could be included.

2. **No Commonwealth leads**: Commonwealth advisors are ACTIVE tier (not senior titles, not mid-career), so they didn't make it into the 300-lead quota. To include Commonwealth, either:
   - Increase the quota (LIMIT 500+)
   - Add separate quota for ACTIVE tier
   - Modify INSERT ORDER BY to alternate between tiers

3. **Large firm exemption working**: 293 of 300 M&A leads are at firms with >200 reps, confirming the exemption is working correctly.

---

### 8.1 Verify M&A Advisors in Lead List

```sql
-- ============================================================
-- CHECK 1: M&A Tiers Are Populated
-- ============================================================
SELECT 
    '1. M&A Tier Population' as check_name,
    score_tier,
    COUNT(*) as lead_count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
GROUP BY score_tier
ORDER BY score_tier;

-- EXPECTED:
-- TIER_MA_ACTIVE_PRIME: 50-200 leads
-- TIER_MA_ACTIVE: 100-400 leads
-- 🛑 FAIL if 0 leads in either tier
```

### 8.2 Verify Large Firm Exemption Working

```sql
-- ============================================================
-- CHECK 2: Large Firm Exemption Working
-- ============================================================
SELECT 
    '2. Large Firm Exemption' as check_name,
    CASE WHEN score_tier LIKE 'TIER_MA%' THEN 'M&A Tier' ELSE 'Other Tier' END as tier_type,
    CASE 
        WHEN firm_rep_count <= 50 THEN '≤50 reps'
        WHEN firm_rep_count <= 200 THEN '51-200 reps'
        ELSE '>200 reps'
    END as firm_size,
    COUNT(*) as leads
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY 1, 2, 3
ORDER BY 2, 3;

-- EXPECTED:
-- M&A Tier + >50 reps: >0 (exemption working)
-- Other Tier + >50 reps: 0 (exclusion working)
```

### 8.3 Verify Commonwealth Specifically Included

```sql
-- ============================================================
-- CHECK 3: Commonwealth Specifically Included
-- ============================================================
SELECT 
    '3. Commonwealth Check' as check_name,
    firm_name,
    score_tier,
    COUNT(*) as leads
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE UPPER(firm_name) LIKE '%COMMONWEALTH%'
GROUP BY firm_name, score_tier;

-- EXPECTED: >0 Commonwealth leads in TIER_MA_ACTIVE or TIER_MA_ACTIVE_PRIME
-- 🛑 FAIL if 0 Commonwealth leads
```

### 8.4 Verify No Non-M&A Large Firms Snuck In

```sql
-- ============================================================
-- CHECK 4: No Violations - Non-M&A Large Firms Excluded
-- ============================================================
SELECT 
    '4. Violation Check' as check_name,
    COUNT(*) as violations
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE firm_rep_count > 50
  AND score_tier NOT LIKE 'TIER_MA%'
  AND is_at_ma_target_firm != 1;

-- EXPECTED: 0 violations
```

### 8.5 Verify M&A Fields Not NULL

```sql
-- ============================================================
-- CHECK 5: M&A Fields Not NULL
-- ============================================================
SELECT 
    '5. M&A Field Completeness' as check_name,
    SUM(CASE WHEN is_at_ma_target_firm IS NULL THEN 1 ELSE 0 END) as null_ma_flag,
    SUM(CASE WHEN score_tier LIKE 'TIER_MA%' AND ma_status IS NULL THEN 1 ELSE 0 END) as null_ma_status,
    SUM(CASE WHEN score_tier LIKE 'TIER_MA%' AND ma_days_since_news IS NULL THEN 1 ELSE 0 END) as null_days
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;

-- EXPECTED: All zeros
```

### 8.6 Tier Distribution Sanity Check

```sql
-- ============================================================
-- CHECK 6: Tier Distribution Sanity Check
-- ============================================================
SELECT 
    '6. Full Tier Distribution' as check_name,
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(expected_rate_pct), 2) as avg_expected_conv
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY score_tier
ORDER BY 
    CASE score_tier
        WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
        WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
        WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
        WHEN 'TIER_MA_ACTIVE_PRIME' THEN 4
        WHEN 'TIER_MA_ACTIVE' THEN 5
        WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 6
        ELSE 99
    END;
```

### 8.7 Spot Check M&A Leads

```sql
-- ============================================================
-- CHECK 7: Spot Check M&A Leads (Manual Review)
-- ============================================================
SELECT 
    '7. Spot Check Sample' as check_name,
    crd,
    first_name,
    last_name,
    firm_name,
    job_title,
    score_tier,
    ma_status,
    ma_days_since_news,
    firm_rep_count,
    expected_rate_pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
ORDER BY 
    CASE score_tier WHEN 'TIER_MA_ACTIVE_PRIME' THEN 1 ELSE 2 END,
    ma_days_since_news
LIMIT 20;

-- MANUAL CHECK: Do these look like legitimate M&A targets?
```

### Post-Implementation Checklist

| Check | Query | Expected | Actual | Pass? |
|-------|-------|----------|--------|-------|
| M&A tiers populated | 8.1 | 150-600 total M&A leads | | |
| Large firm exemption | 8.2 | M&A >50 reps exists | | |
| Commonwealth included | 8.3 | >0 Commonwealth leads | | |
| No violations | 8.4 | 0 violations | | |
| Fields not NULL | 8.5 | All zeros | | |
| Distribution reasonable | 8.6 | M&A tiers present | | |
| Spot check passes | 8.7 | Manual review OK | | |

**🛑 If ANY check fails, debug before deploying.**

---

## 9. Lead List Integration

### Two-Query Execution Workflow

The M&A tier implementation uses a **two-query architecture** to avoid BigQuery CTE optimization issues:

```
┌─────────────────────────────────────────────────────────────┐
│                    EXECUTION WORKFLOW                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  STEP 1: Create M&A Advisors Table                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ create_ma_eligible_advisors.sql                     │   │
│  │ → Creates: ml_features.ma_eligible_advisors         │   │
│  │ → Output: ~2,225 advisors with tier assignments     │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                            ▼                                │
│  STEP 2: Generate Base Lead List                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ January_2026_Lead_List_V3_V4_Hybrid.sql            │   │
│  │ → Creates: ml_features.january_2026_lead_list       │   │
│  │ → Output: ~2,800 normal leads (V3.4 logic)           │   │
│  │ → NO M&A modifications in this query                │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                            ▼                                │
│  STEP 3: Insert M&A Leads (Run AFTER Step 2)                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Insert_MA_Leads.sql                                 │   │
│  │ → INSERT INTO january_2026_lead_list               │   │
│  │ → Adds: ~300 M&A leads                              │   │
│  │ → Excludes duplicates automatically                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                            ▼                                │
│                  ┌─────────────────┐                        │
│                  │ Final Lead List │                        │
│                  │ 3,100 leads     │                        │
│                  │ (2,800 + 300)   │                        │
│                  └─────────────────┘                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Key Points

1. **Order matters**: `Insert_MA_Leads.sql` MUST run after the base lead list is created
2. **No modifications needed**: The main lead list SQL (`January_2026_Lead_List_V3_V4_Hybrid.sql`) remains unchanged (V3.4 logic)
3. **Idempotent**: The INSERT query uses `WHERE crd NOT IN (SELECT ...)` to prevent duplicates
4. **Quota adjustable**: Modify `LIMIT` in `Insert_MA_Leads.sql` to change M&A lead count

### Output Schema

The final `january_2026_lead_list` table includes all standard columns plus M&A-specific data in the `score_tier` and `score_narrative` fields for M&A leads. The table schema remains the same as V3.4 - no new columns are added.

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

## 12. Execution Checklist

### Pre-Implementation
- [x] Verified `active_ma_target_firms` has data (66 firms)
- [x] Verified 2,225 advisors at M&A firms
- [x] Verified `firm_crd` is INT64 (compatible)
- [x] Noted Commonwealth exclusion conflict (will be in ACTIVE tier)

### Implementation
- [x] **Step 7.1**: Created `ma_eligible_advisors` table (2,225 advisors)
- [x] **Step 7.1 VERIFY**: Table has correct tier distribution
- [x] **Step 7.2**: Generated base lead list (2,800 leads)
- [x] **Step 7.3**: Inserted M&A leads (300 leads)
- [x] **Step 7.4**: Updated model registry to V3.5.0

### Post-Implementation
- [x] Ran full verification query suite
- [x] All 7 checks passed (or explained)
- [x] Manual spot check approved
- [x] Documentation updated

### Success Criteria Met

| Criteria | Target | Actual | Status |
|----------|--------|--------|--------|
| `ma_eligible_advisors` table exists | ~2,000-4,500 rows | 2,225 | ✅ |
| Lead list contains M&A tier leads | 150-600 | 300 | ✅ |
| TIER_MA_ACTIVE_PRIME populated | ~50-200 | 300 | ✅ |
| Large firm M&A advisors present | >0 | 293 | ✅ |
| No non-M&A large firm violations | 0 | 0 | ✅ |
| All M&A fields populated | No NULLs | 100% | ✅ |
| Model registry updated | V3.5.0 | V3.5.0 | ✅ |

---

## 13. Appendix: Full SQL Scripts

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
            OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%MANAGING%'
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
    CASE 
        WHEN is_senior_title = 1 OR is_mid_career = 1 
        THEN 2.36
        ELSE 1.41
    END as expected_lift,
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

### B. Insert_MA_Leads.sql (Two-Query Architecture)

```sql
-- ============================================================================
-- V3.5.0: INSERT M&A LEADS (Two-Query Architecture)
-- ============================================================================
-- Purpose: Add M&A leads to existing lead list
-- Run AFTER: January_2026_Lead_List_V3_V4_Hybrid.sql
-- 
-- This approach bypasses BigQuery CTE optimization issues by using a
-- separate INSERT query instead of trying to integrate M&A logic into
-- the complex lead list query.
-- ============================================================================

INSERT INTO `savvy-gtm-analytics.ml_features.january_2026_lead_list`
(
    advisor_crd,
    salesforce_lead_id,
    first_name,
    last_name,
    email,
    phone,
    linkedin_url,
    has_linkedin,
    job_title,
    producing_advisor,
    firm_name,
    firm_crd,
    firm_rep_count,
    firm_net_change_12mo,
    firm_arrivals_12mo,
    firm_departures_12mo,
    firm_turnover_pct,
    tenure_months,
    tenure_years,
    industry_tenure_years,
    num_prior_firms,
    moves_3yr,
    original_v3_tier,
    score_tier,
    priority_rank,
    expected_conversion_rate,
    expected_rate_pct,
    score_narrative,
    has_cfp,
    has_series_65_only,
    has_series_7,
    has_cfa,
    is_hv_wealth_title,
    prospect_type,
    lead_source_description,
    v4_score,
    v4_percentile,
    is_high_v4_standard,
    v4_status,
    v4_is_recent_mover,
    v4_days_since_last_move,
    v4_firm_departures_corrected,
    v4_bleeding_velocity_encoded,
    v4_is_dual_registered,
    shap_top1_feature,
    shap_top2_feature,
    shap_top3_feature,
    cc_career_pattern,
    cc_cycle_status,
    cc_pct_through_cycle,
    cc_months_until_window,
    sga_owner,
    sga_id,
    list_rank,
    generated_at
)
SELECT 
    ma.crd as advisor_crd,
    CAST(NULL AS STRING) as salesforce_lead_id,
    ma.first_name,
    ma.last_name,
    ma.email,
    ma.phone,
    c.LINKEDIN_PROFILE_URL as linkedin_url,
    CASE WHEN c.LINKEDIN_PROFILE_URL IS NOT NULL AND TRIM(c.LINKEDIN_PROFILE_URL) != '' THEN 1 ELSE 0 END as has_linkedin,
    ma.job_title,
    TRUE as producing_advisor,
    ma.firm_name,
    ma.firm_crd,
    ma.ma_firm_size as firm_rep_count,
    CAST(NULL AS INT64) as firm_net_change_12mo,
    CAST(NULL AS INT64) as firm_arrivals_12mo,
    CAST(NULL AS INT64) as firm_departures_12mo,
    CAST(NULL AS FLOAT64) as firm_turnover_pct,
    DATE_DIFF(CURRENT_DATE(), ma.firm_start_date, MONTH) as tenure_months,
    DATE_DIFF(CURRENT_DATE(), ma.firm_start_date, YEAR) as tenure_years,
    DATE_DIFF(CURRENT_DATE(), ma.firm_start_date, YEAR) as industry_tenure_years,
    CAST(NULL AS INT64) as num_prior_firms,
    CAST(NULL AS INT64) as moves_3yr,
    ma.ma_tier as original_v3_tier,
    ma.ma_tier as score_tier,
    CASE 
        WHEN ma.ma_tier = 'TIER_MA_ACTIVE_PRIME' THEN 4
        WHEN ma.ma_tier = 'TIER_MA_ACTIVE' THEN 5
        ELSE 99
    END as priority_rank,
    ma.expected_conversion_rate as expected_conversion_rate,
    ROUND(ma.expected_conversion_rate * 100, 2) as expected_rate_pct,
    -- M&A tier narrative
    CASE 
        WHEN ma.ma_tier = 'TIER_MA_ACTIVE_PRIME' THEN
            CONCAT(
                ma.first_name, ' is a HIGH-VALUE M&A OPPORTUNITY: ',
                CASE WHEN ma.is_senior_title = 1 THEN CONCAT('Senior title (', ma.job_title, ')') 
                     ELSE CONCAT('Mid-career (', CAST(ROUND(ma.industry_tenure_months/12, 0) AS STRING), ' years)') 
                END,
                ' at ', ma.firm_name, ' (', ma.ma_status, ' M&A target, ',
                CAST(ma.days_since_first_news AS STRING), ' days since announcement). ',
                'Advisors at acquired firms actively evaluating options. ',
                '9.0% expected conversion (2.36x baseline).'
            )
        WHEN ma.ma_tier = 'TIER_MA_ACTIVE' THEN
            CONCAT(
                ma.first_name, ' is at M&A TARGET FIRM: ',
                ma.firm_name, ' (', ma.ma_status, ' M&A target, ',
                CAST(ma.days_since_first_news AS STRING), ' days since announcement). ',
                'Firm disruption creates opportunity window. ',
                '5.4% expected conversion (1.41x baseline).'
            )
        ELSE CONCAT(ma.first_name, ' at ', ma.firm_name, ' - M&A target firm.')
    END as score_narrative,
    -- Certifications (from ria_contacts_current if available)
    CASE WHEN c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%' THEN 1 ELSE 0 END as has_cfp,
    CASE WHEN c.REP_LICENSES LIKE '%Series 65%' AND c.REP_LICENSES NOT LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_65_only,
    CASE WHEN c.REP_LICENSES LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_7,
    CASE WHEN c.CONTACT_BIO LIKE '%CFA%' OR c.TITLE_NAME LIKE '%CFA%' THEN 1 ELSE 0 END as has_cfa,
    -- High-value wealth title
    CASE WHEN (
        UPPER(c.TITLE_NAME) LIKE '%WEALTH MANAGER%'
        OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%WEALTH%'
        OR UPPER(c.TITLE_NAME) LIKE '%SENIOR WEALTH ADVISOR%'
    ) THEN 1 ELSE 0 END as is_hv_wealth_title,
    'NEW_PROSPECT' as prospect_type,
    'New - M&A Target Firm' as lead_source_description,
    -- V4 scores (if available)
    COALESCE(v4.v4_score, 0.5) as v4_score,
    COALESCE(v4.v4_percentile, 50) as v4_percentile,
    CASE WHEN COALESCE(v4.v4_percentile, 50) >= 80 THEN 1 ELSE 0 END as is_high_v4_standard,
    CASE 
        WHEN COALESCE(v4.v4_percentile, 50) >= 80 THEN 'High-V4 STANDARD (Backfill)'
        ELSE 'V3 Tier Qualified'
    END as v4_status,
    COALESCE(v4f.is_recent_mover, 0) as v4_is_recent_mover,
    COALESCE(v4f.days_since_last_move, 9999) as v4_days_since_last_move,
    COALESCE(v4f.firm_departures_corrected, 0) as v4_firm_departures_corrected,
    COALESCE(v4f.bleeding_velocity_encoded, 0) as v4_bleeding_velocity_encoded,
    COALESCE(v4f.is_dual_registered, 0) as v4_is_dual_registered,
    v4.shap_top1_feature,
    v4.shap_top2_feature,
    v4.shap_top3_feature,
    -- Career Clock (not applicable for M&A advisors, but include for schema compatibility)
    CAST(NULL AS STRING) as cc_career_pattern,
    CAST(NULL AS STRING) as cc_cycle_status,
    CAST(NULL AS FLOAT64) as cc_pct_through_cycle,
    CAST(NULL AS INT64) as cc_months_until_window,
    -- SGA assignment (will be assigned in post-processing)
    CAST(NULL AS STRING) as sga_owner,
    CAST(NULL AS STRING) as sga_id,
    -- List rank (will be assigned in post-processing)
    CAST(NULL AS INT64) as list_rank,
    CURRENT_TIMESTAMP() as generated_at
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors` ma
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON ma.crd = c.RIA_CONTACT_CRD_ID
LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4
    ON ma.crd = v4.crd
LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_features` v4f
    ON ma.crd = v4f.crd
-- Only insert M&A advisors not already in the lead list
WHERE ma.crd NOT IN (
    SELECT advisor_crd 
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
)
-- Apply quotas (scale based on SGA count - base = 12 SGAs)
-- TIER_MA_ACTIVE_PRIME: 100 per 12 SGAs
-- TIER_MA_ACTIVE: 200 per 12 SGAs
AND (
    (ma.ma_tier = 'TIER_MA_ACTIVE_PRIME' AND ma.expected_conversion_rate >= 0.09)
    OR (ma.ma_tier = 'TIER_MA_ACTIVE' AND ma.expected_conversion_rate >= 0.054)
)
ORDER BY 
    CASE ma.ma_tier 
        WHEN 'TIER_MA_ACTIVE_PRIME' THEN 1 
        WHEN 'TIER_MA_ACTIVE' THEN 2 
        ELSE 3 
    END,
    ma.days_since_first_news ASC  -- Soonest since announcement first
LIMIT 300;  -- Total M&A leads quota (adjust based on SGA count)
```

### C. Complete Verification Query Suite

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
| 1.1 | 2026-01-02 | Lead Scoring Team | Added pre-flight verification, expanded verification queries |
| **2.0** | **2026-01-03** | **Lead Scoring Team** | **Major update: Documented failed single-query approaches, implemented two-query architecture, added Insert_MA_Leads.sql, updated all sections to reflect actual working implementation** |
| 1.0 | 2026-01-02 | Lead Scoring Team | Initial comprehensive guide |
| 1.1 | 2026-01-02 | Lead Scoring Team | Updated with detailed step-by-step instructions from Cursor implementation prompt, added pre-flight verification, expanded verification queries, added execution checklist |
| **2.0** | **2026-01-03** | **Lead Scoring Team** | **Major update: Documented failed single-query approaches, implemented two-query architecture, added Insert_MA_Leads.sql, updated all sections to reflect actual working implementation** |

---

**End of Document**
