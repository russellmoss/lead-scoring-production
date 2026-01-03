# V3.5.0 M&A Tier Implementation - Cursor Agent Prompt

**Purpose**: Agentic implementation of M&A Active Tiers for lead scoring  
**Model Version**: V3.4.0 → V3.5.0  
**Date**: January 2, 2026  
**Status**: 🚀 READY FOR EXECUTION (All pre-flight checks passed)

---

## 🎯 MISSION

Add two new M&A (Mergers & Acquisitions) priority tiers to the V3 lead scoring system. These tiers capture advisors at firms undergoing M&A activity - a time-sensitive opportunity window where normally-excluded large firms convert at elevated rates.

### New Tiers to Implement

| Tier | Expected Conversion | Expected Lift | Criteria |
|------|---------------------|---------------|----------|
| **TIER_MA_ACTIVE_PRIME** | ~9.0% | 2.36x | Senior titles OR mid-career (10-20yr) at M&A target |
| **TIER_MA_ACTIVE** | ~5.4% | 1.41x | All other advisors at M&A targets |

---

## ✅ PRE-FLIGHT VERIFICATION RESULTS (ALL PASSED)

These checks were run on January 2, 2026 and confirm we can proceed:

| Check | Result | Status |
|-------|--------|--------|
| M&A Source Table | 66 firms (39 HOT + 27 ACTIVE), 9,411 employees | ✅ PASS |
| Advisors at M&A Firms | 2,225 advisors | ✅ PASS |
| Data Type Compatibility | `firm_crd` is INT64 | ✅ PASS |
| Exclusion Conflicts | Commonwealth matches `%COMMONWEALTH%` | ⚠️ EXEMPTION NEEDED |
| Tier Distribution | PRIME: 473, STANDARD: 3,845 | ✅ PASS |

**Key Finding**: Commonwealth Financial Network (primary M&A target from LPL merger) is on exclusion list but should be exempted FOR M&A TIERS ONLY.

---

## 🚨 CRITICAL LESSONS FROM FAILED V3.5.0 ATTEMPT

The previous implementation failed after 8+ hours of debugging. **DO NOT REPEAT THESE MISTAKES:**

### Architecture Decision (NON-NEGOTIABLE)
```
❌ WRONG: CTE references in complex queries (caused silent JOIN failures)
✅ RIGHT: Pre-built materialized table with simple LEFT JOIN
```

### Key Failures to Avoid
1. **CTE Scoping Issues** - BigQuery CTEs referenced across multiple levels returned 0 matches silently
2. **Data Type Mismatches** - Always use SAFE_CAST on both sides of JOINs
3. **Overly Restrictive Caps** - Don't add arbitrary rep caps to M&A exemptions
4. **Missing ORDER BY Tiers** - Every new tier must be added to ALL CASE statements
5. **Incomplete Exemptions** - M&A exemption must be added to BOTH `excluded_firms` AND `excluded_firm_crds` filters

### The 3-Fix Rule
> If you apply 3 fixes and the issue persists, STOP and reconsider the architecture.

---

## 📁 FILES TO MODIFY

### Primary Files (MUST UPDATE)

| File | Purpose | Changes Required |
|------|---------|------------------|
| `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | Main lead list generator | Add M&A JOIN, tier logic, exemptions, quotas |
| `v3/sql/phase_4_v3_tiered_scoring.sql` | V3 tier scoring logic | Add M&A tier definitions |
| `v3/models/model_registry_v3.json` | Model metadata | Update to V3.5.0, add M&A tier definitions |

### New Files to Create

| File | Purpose |
|------|---------|
| `pipeline/sql/create_ma_eligible_advisors.sql` | Pre-built M&A advisors table |
| `pipeline/sql/verify_ma_implementation.sql` | Verification query suite |

### Documentation to Update

| File | Purpose |
|------|---------|
| `v3/VERSION_3_MODEL_REPORT.md` | Add V3.5.0 section |
| `README.md` | Update current version |

---

## 📋 STEP-BY-STEP IMPLEMENTATION

### STEP 1: Create M&A Eligible Advisors Table

**File**: `pipeline/sql/create_ma_eligible_advisors.sql`

```sql
-- ============================================================================
-- V3.5.0: CREATE M&A ELIGIBLE ADVISORS TABLE
-- ============================================================================
-- Purpose: Pre-build list of advisors at M&A target firms with tier assignments
-- This avoids CTE scoping issues that caused the previous implementation to fail
-- 
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
        -- Senior title detection
        CASE WHEN (
            UPPER(c.TITLE_NAME) LIKE '%PRESIDENT%'
            OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%'
            OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%OWNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
            OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%MANAGING%'
        ) THEN 1 ELSE 0 END as is_senior_title,
        -- Mid-career detection (10-20 years = 120-240 months)
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
        THEN 0.09
        ELSE 0.054
    END as expected_conversion_rate,
    -- Expected lift vs baseline (3.82%)
    CASE 
        WHEN is_senior_title = 1 OR is_mid_career = 1 
        THEN 2.36
        ELSE 1.41
    END as expected_lift,
    CURRENT_TIMESTAMP() as created_at,
    'V3.5.0' as model_version
FROM ma_advisors;
```

### STEP 1 VERIFICATION (REQUIRED)

**Run immediately after creating the table:**

```sql
-- VERIFY STEP 1: M&A Eligible Advisors Table Created
SELECT 
    '=== MA_ELIGIBLE_ADVISORS TABLE VERIFICATION ===' as section;

-- Check 1: Total row count
SELECT 'Total Advisors' as metric, COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`;
-- EXPECTED: ~2,000-4,500 rows

-- Check 2: Tier distribution
SELECT ma_tier, COUNT(*) as count, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as pct
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_tier;
-- EXPECTED: TIER_MA_ACTIVE_PRIME ~10-15%, TIER_MA_ACTIVE ~85-90%

-- Check 3: Firm distribution
SELECT ma_status, COUNT(DISTINCT firm_crd) as unique_firms, COUNT(*) as advisors
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_status;
-- EXPECTED: HOT ~30-40 firms, ACTIVE ~25-30 firms

-- Check 4: Commonwealth is present (KEY TEST)
SELECT firm_name, COUNT(*) as advisors
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
WHERE UPPER(firm_name) LIKE '%COMMONWEALTH%'
GROUP BY firm_name;
-- EXPECTED: >0 advisors (Commonwealth must be present!)

-- Check 5: No NULL critical fields
SELECT 
    SUM(CASE WHEN crd IS NULL THEN 1 ELSE 0 END) as null_crd,
    SUM(CASE WHEN firm_crd IS NULL THEN 1 ELSE 0 END) as null_firm_crd,
    SUM(CASE WHEN ma_tier IS NULL THEN 1 ELSE 0 END) as null_tier
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`;
-- EXPECTED: All zeros
```

**🛑 STOP if any verification fails. Debug before proceeding.**

---

### STEP 2: Modify Lead List SQL - Add M&A JOIN

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Location**: After `base_prospects` CTE, modify `enriched_prospects` CTE

**Find this section:**
```sql
enriched_prospects AS (
    SELECT 
        bp.*,
        ...
    FROM base_prospects bp
    LEFT JOIN ... 
```

**Add M&A JOIN:**
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

### STEP 2 VERIFICATION (REQUIRED)

**After modifying the CTE, run this test query:**

```sql
-- VERIFY STEP 2: M&A JOIN Working in enriched_prospects
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

---

### STEP 3: Modify Tier Logic - Add M&A Tiers

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

---

### STEP 4: Add M&A Exemption to Firm Exclusions

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

### STEP 4 VERIFICATION (REQUIRED)

```sql
-- VERIFY STEP 4: M&A Exemptions Working
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

---

### STEP 5: Add M&A Tiers to ORDER BY Clauses

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

---

### STEP 6: Add M&A Tier Quotas

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

---

### STEP 7: Add M&A Fields to Final Output

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

### STEP 8: Update Model Registry

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

## 🔍 POST-IMPLEMENTATION VERIFICATION (REQUIRED)

**Run ALL these queries after implementation:**

### Verification Query Suite

```sql
-- ============================================================================
-- V3.5.0 POST-IMPLEMENTATION VERIFICATION SUITE
-- ============================================================================
-- Run after generating the lead list
-- ALL checks must pass before considering implementation complete
-- ============================================================================

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

### Verification Checklist

| Check | Query | Expected | Actual | Pass? |
|-------|-------|----------|--------|-------|
| M&A tiers populated | 1 | 150-600 total M&A leads | | |
| Large firm exemption | 2 | M&A >50 reps exists | | |
| Commonwealth included | 3 | >0 Commonwealth leads | | |
| No violations | 4 | 0 violations | | |
| Fields not NULL | 5 | All zeros | | |
| Distribution reasonable | 6 | M&A tiers present | | |
| Spot check passes | 7 | Manual review OK | | |

**🛑 If ANY check fails, debug before deploying.**

---

## 🔄 ROLLBACK PLAN

If issues are discovered after deployment:

### Quick Rollback (5 minutes)
```sql
-- Remove M&A leads from current list
DELETE FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%';
```

### Full Rollback (30 minutes)
1. Restore `January_2026_Lead_List_V3_V4_Hybrid.sql` from git
2. Regenerate lead list without M&A modifications
3. Verify M&A leads not present

### Rollback Triggers
- M&A tier conversion < 3% after 60 days
- Data quality issues discovered
- Excessive false positives

---

## 📝 EXECUTION CHECKLIST

Use this checklist during implementation:

### Pre-Implementation
- [ ] Verified `active_ma_target_firms` has data (66 firms confirmed)
- [ ] Verified 2,225 advisors at M&A firms
- [ ] Verified `firm_crd` is INT64
- [ ] Noted Commonwealth exclusion conflict (needs exemption)

### Implementation
- [ ] **STEP 1**: Created `ma_eligible_advisors` table
- [ ] **STEP 1 VERIFY**: Table has ~2,000-4,500 rows
- [ ] **STEP 2**: Added M&A JOIN to `enriched_prospects`
- [ ] **STEP 2 VERIFY**: JOIN returns >0 M&A advisors
- [ ] **STEP 3**: Added M&A tier logic to `scored_prospects`
- [ ] **STEP 4**: Added M&A exemptions to ALL exclusion filters
- [ ] **STEP 4 VERIFY**: Commonwealth included, large firms exempt
- [ ] **STEP 5**: Added M&A tiers to ALL ORDER BY clauses
- [ ] **STEP 6**: Added M&A tier quotas
- [ ] **STEP 7**: Added M&A fields to final output
- [ ] **STEP 8**: Updated model registry to V3.5.0

### Post-Implementation
- [ ] Ran full verification query suite
- [ ] All 7 checks passed
- [ ] Manual spot check approved
- [ ] Documentation updated

---

## 🎯 SUCCESS CRITERIA

Implementation is complete when:

1. ✅ `ma_eligible_advisors` table exists with ~2,000-4,500 rows
2. ✅ Lead list contains 150-600 M&A tier leads
3. ✅ TIER_MA_ACTIVE_PRIME has ~50-200 leads
4. ✅ TIER_MA_ACTIVE has ~100-400 leads
5. ✅ Commonwealth advisors are present
6. ✅ Large firm (>50 rep) M&A advisors are present
7. ✅ No non-M&A large firm violations
8. ✅ All M&A fields populated (no NULLs)
9. ✅ Model registry updated to V3.5.0

---

## 📚 REFERENCE DOCUMENTS

- `V3_5_0_POST_MORTEM_LESSONS_LEARNED.md` - What went wrong in failed attempt
- `V3_5_0_MA_TIER_COMPREHENSIVE_IMPLEMENTATION_GUIDE.md` - Full technical guide
- `v3/VERSION_3_MODEL_REPORT.md` - V3 model documentation
- `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` - Current lead list SQL

---

**END OF CURSOR IMPLEMENTATION PROMPT**
