# Create Centralized Excluded Firms Table

**Date**: 2025-12-30  
**Purpose**: Create a centralized BigQuery table for firm exclusions and update lead list SQL to use it

---

## Cursor.ai Prompt

```
@workspace Create a centralized excluded firms table in BigQuery and update the lead list SQL to use it.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

OVERVIEW:
We currently have firm exclusion patterns hardcoded in the lead list SQL. We want to:
1. Create a centralized reference table: ml_features.excluded_firms
2. Update the lead list SQL to reference this table
3. Verify everything works correctly

This makes exclusions easier to maintain - add/remove firms without editing complex SQL.

---

TASK 1: Create the excluded firms reference table

Create file: pipeline/sql/create_excluded_firms_table.sql

```sql
-- ============================================================================
-- EXCLUDED FIRMS REFERENCE TABLE
-- ============================================================================
-- Purpose: Centralized table of firm exclusion patterns for lead list generation
-- Usage: Referenced by January_2026_Lead_List_V3_V4_Hybrid.sql and future lead lists
-- 
-- To add a new exclusion:
--   INSERT INTO ml_features.excluded_firms VALUES ('%PATTERN%', 'Category', CURRENT_DATE(), 'Reason');
-- 
-- To remove an exclusion:
--   DELETE FROM ml_features.excluded_firms WHERE pattern = '%PATTERN%';
--
-- Created: 2025-12-30
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.excluded_firms` AS

SELECT * FROM UNNEST([
    -- ============================================================================
    -- WIREHOUSES (Major broker-dealers with captive advisors)
    -- ============================================================================
    STRUCT('%J.P. MORGAN%' as pattern, 'Wirehouse' as category, DATE('2025-12-30') as added_date, 'Major wirehouse - captive advisors' as reason),
    STRUCT('%MORGAN STANLEY%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors'),
    STRUCT('%MERRILL%', 'Wirehouse', DATE('2025-12-30'), 'Bank of America subsidiary - captive advisors'),
    STRUCT('%WELLS FARGO%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors'),
    STRUCT('%UBS %', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors'),
    STRUCT('%UBS,%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors (comma variant)'),
    STRUCT('%EDWARD JONES%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors'),
    STRUCT('%AMERIPRISE%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors'),
    STRUCT('%RAYMOND JAMES%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - semi-captive advisors'),
    STRUCT('%GOLDMAN SACHS%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse/bank - captive advisors'),
    STRUCT('%CITIGROUP%', 'Wirehouse', DATE('2025-12-30'), 'Major bank - captive advisors'),
    
    -- ============================================================================
    -- LARGE INDEPENDENT BROKER-DEALERS (High volume, low conversion)
    -- ============================================================================
    STRUCT('%LPL FINANCIAL%', 'Large IBD', DATE('2025-12-30'), 'Largest IBD - high volume, low conversion'),
    STRUCT('%COMMONWEALTH%', 'Large IBD', DATE('2025-12-30'), 'Large IBD - low conversion historically'),
    STRUCT('%CETERA%', 'Large IBD', DATE('2025-12-30'), 'Large IBD network - low conversion'),
    STRUCT('%CAMBRIDGE%', 'Large IBD', DATE('2025-12-30'), 'Large IBD - low conversion historically'),
    STRUCT('%OSAIC%', 'Large IBD', DATE('2025-12-30'), 'Large IBD (formerly Advisor Group)'),
    STRUCT('%PRIMERICA%', 'Large IBD', DATE('2025-12-30'), 'MLM-style BD - not target market'),
    
    -- ============================================================================
    -- CUSTODIANS (Not advisory firms)
    -- ============================================================================
    STRUCT('%FIDELITY%', 'Custodian', DATE('2025-12-30'), 'Custodian/retail - not target market'),
    STRUCT('%SCHWAB%', 'Custodian', DATE('2025-12-30'), 'Custodian/retail - not target market'),
    STRUCT('%VANGUARD%', 'Custodian', DATE('2025-12-30'), 'Custodian/retail - not target market'),
    
    -- ============================================================================
    -- INSURANCE COMPANIES & THEIR BROKER-DEALERS
    -- ============================================================================
    STRUCT('%NORTHWESTERN MUTUAL%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%PRUDENTIAL%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%PRUCO%', 'Insurance BD', DATE('2025-12-30'), 'Prudential broker-dealer subsidiary'),
    STRUCT('%STATE FARM%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%ALLSTATE%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%NEW YORK LIFE%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%NYLIFE%', 'Insurance BD', DATE('2025-12-30'), 'New York Life broker-dealer subsidiary'),
    STRUCT('%TRANSAMERICA%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%FARM BUREAU%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%NATIONWIDE%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%LINCOLN FINANCIAL%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%MASS MUTUAL%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%MASSMUTUAL%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents (no space)'),
    STRUCT('%ONEAMERICA%', 'Insurance BD', DATE('2025-12-30'), 'OneAmerica Financial - insurance BD'),
    STRUCT('%M HOLDINGS SECURITIES%', 'Insurance BD', DATE('2025-12-30'), 'M Financial Group - insurance distribution'),
    STRUCT('%NUVEEN SECURITIES%', 'Insurance BD', DATE('2025-12-30'), 'TIAA subsidiary - retirement focused'),
    STRUCT('%INSURANCE%', 'Insurance', DATE('2025-12-30'), 'Generic insurance pattern - catches remaining'),
    
    -- ============================================================================
    -- BANK BROKER-DEALERS
    -- ============================================================================
    STRUCT('%BMO NESBITT%', 'Bank BD', DATE('2025-12-30'), 'Bank of Montreal broker-dealer'),
    STRUCT('%NESBITT BURNS%', 'Bank BD', DATE('2025-12-30'), 'BMO Nesbitt Burns variant'),
    
    -- ============================================================================
    -- INTERNAL / PARTNER FIRMS (Do not contact)
    -- ============================================================================
    STRUCT('%SAVVY WEALTH%', 'Internal', DATE('2025-12-30'), 'Internal firm - do not contact'),
    STRUCT('%SAVVY ADVISORS%', 'Internal', DATE('2025-12-30'), 'Internal firm - do not contact'),
    STRUCT('%RITHOLTZ%', 'Partner', DATE('2025-12-30'), 'Partner firm - do not contact')
]);

-- Add primary key comment (BigQuery doesn't enforce PKs but good for documentation)
-- Primary Key: pattern (each pattern should be unique)

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- 1. Count by category
SELECT category, COUNT(*) as patterns
FROM `savvy-gtm-analytics.ml_features.excluded_firms`
GROUP BY category
ORDER BY patterns DESC;

-- 2. Full list
SELECT * FROM `savvy-gtm-analytics.ml_features.excluded_firms`
ORDER BY category, pattern;
```

Execute this SQL in BigQuery to create the table.

---

TASK 2: Create the excluded firm CRDs table (for specific CRD exclusions)

Create file: pipeline/sql/create_excluded_firm_crds_table.sql

```sql
-- ============================================================================
-- EXCLUDED FIRM CRDs TABLE
-- ============================================================================
-- Purpose: Specific firm CRD exclusions (more precise than pattern matching)
-- Usage: For firms we want to exclude by exact CRD, not pattern
-- 
-- Created: 2025-12-30
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.excluded_firm_crds` AS

SELECT * FROM UNNEST([
    STRUCT(318493 as firm_crd, 'Savvy Advisors, Inc.' as firm_name, 'Internal' as category, DATE('2025-12-30') as added_date, 'Internal firm - do not contact' as reason),
    STRUCT(168652, 'Ritholtz Wealth Management', 'Partner', DATE('2025-12-30'), 'Partner firm - do not contact')
]);

-- Verification
SELECT * FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`;
```

Execute this SQL in BigQuery to create the table.

---

TASK 3: Update the lead list SQL to reference the new tables

File to modify: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
(Also: pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql if duplicate exists)

FIND this section (around lines 63-91):

```sql
-- ============================================================================
-- B. EXCLUSIONS (Wirehouses + Insurance + Specific Firms)
-- ============================================================================
excluded_firms AS (
    SELECT firm_pattern FROM UNNEST([
        -- Wirehouses
        '%J.P. MORGAN%', '%MORGAN STANLEY%', '%MERRILL%', '%WELLS FARGO%', 
        '%UBS %', '%UBS,%', '%EDWARD JONES%', '%AMERIPRISE%', 
        '%NORTHWESTERN MUTUAL%', '%PRUDENTIAL%', '%PRUCO%', '%RAYMOND JAMES%',
        '%FIDELITY%', '%SCHWAB%', '%VANGUARD%', '%GOLDMAN SACHS%', '%CITIGROUP%',
        '%LPL FINANCIAL%', '%COMMONWEALTH%', '%CETERA%', '%CAMBRIDGE%',
        '%OSAIC%', '%PRIMERICA%',
        '%BMO NESBITT%', '%NESBITT BURNS%',
        -- Insurance
        '%STATE FARM%', '%ALLSTATE%', '%NEW YORK LIFE%', '%NYLIFE%',
        '%TRANSAMERICA%', '%FARM BUREAU%', '%NATIONWIDE%',
        '%LINCOLN FINANCIAL%', '%MASS MUTUAL%', '%MASSMUTUAL%',
        '%ONEAMERICA%', '%M HOLDINGS SECURITIES%', '%NUVEEN SECURITIES%',
        '%INSURANCE%',
        -- Specific firm name exclusions (backup for CRD exclusion)
        '%SAVVY WEALTH%', '%SAVVY ADVISORS%',
        '%RITHOLTZ%'
    ]) as firm_pattern
),

-- NEW: Specific CRD exclusions for Savvy and Ritholtz
excluded_firm_crds AS (
    SELECT firm_crd FROM UNNEST([
        318493,  -- Savvy Advisors, Inc.
        168652   -- Ritholtz Wealth Management
    ]) as firm_crd
),
```

REPLACE WITH:

```sql
-- ============================================================================
-- B. EXCLUSIONS (Reference centralized tables)
-- ============================================================================
-- Firm exclusions now managed in: ml_features.excluded_firms
-- To add/remove exclusions, update that table instead of this SQL
-- ============================================================================
excluded_firms AS (
    SELECT pattern as firm_pattern
    FROM `savvy-gtm-analytics.ml_features.excluded_firms`
),

-- Specific CRD exclusions managed in: ml_features.excluded_firm_crds
excluded_firm_crds AS (
    SELECT firm_crd
    FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
),
```

Also update the header comment (around line 22-27) to document the change:

FROM:
```sql
-- FEATURES:
-- - V3 Rules: Tier assignment with rich human-readable narratives
-- - V4.1 XGBoost: Upgrade path with SHAP-based narratives
-- - Job Titles: Included in output for SDR context
-- - Firm Exclusions: Savvy Wealth and Ritholtz excluded
```

TO:
```sql
-- FEATURES:
-- - V3 Rules: Tier assignment with rich human-readable narratives
-- - V4.1 XGBoost: Upgrade path with SHAP-based narratives
-- - Job Titles: Included in output for SDR context
-- - Firm Exclusions: Managed in ml_features.excluded_firms table
--                    (easier to maintain - no SQL edits needed)
```

---

TASK 4: Verify the tables were created correctly

Run these verification queries in BigQuery:

```sql
-- 1. Check excluded_firms table exists and has data
SELECT 
    'excluded_firms' as table_name,
    COUNT(*) as total_patterns,
    COUNT(DISTINCT category) as categories
FROM `savvy-gtm-analytics.ml_features.excluded_firms`;

-- Expected: ~40 patterns, 7-8 categories

-- 2. Check excluded_firm_crds table exists
SELECT 
    'excluded_firm_crds' as table_name,
    COUNT(*) as total_crds
FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`;

-- Expected: 2 CRDs (Savvy, Ritholtz)

-- 3. Check category breakdown
SELECT category, COUNT(*) as patterns
FROM `savvy-gtm-analytics.ml_features.excluded_firms`
GROUP BY category
ORDER BY patterns DESC;

-- 4. Verify patterns are accessible (test query)
SELECT pattern, category, reason
FROM `savvy-gtm-analytics.ml_features.excluded_firms`
WHERE category = 'Wirehouse'
ORDER BY pattern;
```

---

TASK 5: Regenerate the lead list and verify exclusions work

After updating the SQL, regenerate the lead list:

Execute: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql

Then verify exclusions are working:

```sql
-- Check no excluded firms slipped through
SELECT 
    jl.firm_name,
    ef.pattern as matched_pattern,
    ef.category
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` jl
INNER JOIN `savvy-gtm-analytics.ml_features.excluded_firms` ef
    ON UPPER(jl.firm_name) LIKE ef.pattern
LIMIT 10;

-- Expected: 0 rows (no matches means exclusions are working)

-- Check no excluded CRDs slipped through
SELECT jl.firm_name, jl.firm_crd
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` jl
INNER JOIN `savvy-gtm-analytics.ml_features.excluded_firm_crds` ec
    ON jl.firm_crd = ec.firm_crd;

-- Expected: 0 rows

-- Verify lead count is still correct
SELECT COUNT(*) as total_leads FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;

-- Expected: ~2,800
```

---

TASK 6: Create a helper script for managing exclusions

Create file: pipeline/sql/manage_excluded_firms.sql

```sql
-- ============================================================================
-- EXCLUDED FIRMS MANAGEMENT QUERIES
-- ============================================================================
-- Use these queries to add, remove, or view exclusions
-- ============================================================================

-- ============================================================================
-- VIEW ALL EXCLUSIONS
-- ============================================================================
SELECT * FROM `savvy-gtm-analytics.ml_features.excluded_firms`
ORDER BY category, pattern;

SELECT * FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
ORDER BY firm_name;

-- ============================================================================
-- ADD A NEW PATTERN EXCLUSION
-- ============================================================================
-- Example: Add a new wirehouse
-- INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firms` 
-- VALUES ('%NEW FIRM NAME%', 'Wirehouse', CURRENT_DATE(), 'Reason for exclusion');

-- ============================================================================
-- ADD A NEW CRD EXCLUSION
-- ============================================================================
-- Example: Add a specific firm by CRD
-- INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firm_crds`
-- VALUES (123456, 'Firm Name', 'Category', CURRENT_DATE(), 'Reason for exclusion');

-- ============================================================================
-- REMOVE AN EXCLUSION
-- ============================================================================
-- Example: Remove a pattern exclusion
-- DELETE FROM `savvy-gtm-analytics.ml_features.excluded_firms`
-- WHERE pattern = '%PATTERN_TO_REMOVE%';

-- Example: Remove a CRD exclusion
-- DELETE FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
-- WHERE firm_crd = 123456;

-- ============================================================================
-- CHECK IF A FIRM WOULD BE EXCLUDED
-- ============================================================================
-- Replace 'FIRM NAME TO CHECK' with the firm you want to test
DECLARE test_firm STRING DEFAULT 'PRUCO SECURITIES LLC';

SELECT 
    test_firm as firm_name,
    ef.pattern,
    ef.category,
    ef.reason
FROM `savvy-gtm-analytics.ml_features.excluded_firms` ef
WHERE UPPER(test_firm) LIKE ef.pattern;

-- ============================================================================
-- FIND POTENTIAL EXCLUSIONS IN PROSPECT DATA
-- ============================================================================
-- Find firms with "Securities" in name that might need review
SELECT 
    PRIMARY_FIRM_NAME as firm_name,
    COUNT(*) as advisor_count
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
WHERE UPPER(PRIMARY_FIRM_NAME) LIKE '%SECURITIES%'
  AND PRODUCING_ADVISOR = TRUE
  AND ACTIVE = TRUE
  AND NOT EXISTS (
      SELECT 1 FROM `savvy-gtm-analytics.ml_features.excluded_firms` ef
      WHERE UPPER(PRIMARY_FIRM_NAME) LIKE ef.pattern
  )
GROUP BY PRIMARY_FIRM_NAME
HAVING COUNT(*) >= 3
ORDER BY advisor_count DESC
LIMIT 20;
```

---

TASK 7: Update documentation

Update README.md or create a new doc section explaining the exclusion system:

```markdown
## Firm Exclusions

### Overview
Firm exclusions are managed in two BigQuery tables:
- `ml_features.excluded_firms` - Pattern-based exclusions (e.g., '%MERRILL%')
- `ml_features.excluded_firm_crds` - Specific CRD exclusions (e.g., 318493)

### How to Add a New Exclusion

**Pattern-based (recommended for firm name matching):**
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firms` 
VALUES ('%FIRM_NAME_PATTERN%', 'Category', CURRENT_DATE(), 'Reason');
```

**CRD-based (for specific firms):**
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firm_crds`
VALUES (123456, 'Firm Name', 'Category', CURRENT_DATE(), 'Reason');
```

### Categories
- Wirehouse: Major broker-dealers (Morgan Stanley, Merrill, etc.)
- Large IBD: Large independent BDs (LPL, Commonwealth, etc.)
- Custodian: Custodians (Fidelity, Schwab, Vanguard)
- Insurance: Insurance companies and their BDs
- Insurance BD: Insurance company broker-dealer subsidiaries
- Bank BD: Bank-owned broker-dealers
- Internal: Our own firms (Savvy)
- Partner: Partner firms (Ritholtz)

### Verification
After adding exclusions, regenerate the lead list and run:
```sql
SELECT firm_name, COUNT(*)
FROM ml_features.january_2026_lead_list
WHERE UPPER(firm_name) LIKE '%NEW_PATTERN%'
GROUP BY firm_name;
```
Expected: 0 rows
```

---

SUMMARY OF CHANGES:

1. Created: pipeline/sql/create_excluded_firms_table.sql
2. Created: pipeline/sql/create_excluded_firm_crds_table.sql
3. Created: pipeline/sql/manage_excluded_firms.sql
4. Modified: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
5. Modified: pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql (if exists)
6. Created BigQuery tables:
   - ml_features.excluded_firms (~40 patterns)
   - ml_features.excluded_firm_crds (2 CRDs)

VERIFICATION CHECKLIST:
- [ ] excluded_firms table created with ~40 patterns
- [ ] excluded_firm_crds table created with 2 CRDs
- [ ] Lead list SQL updated to reference tables
- [ ] Lead list regenerated successfully
- [ ] No excluded firms in final lead list
- [ ] Lead count still ~2,800

Execute now.
```

---

## Quick Reference: Files Created

| File | Purpose |
|------|---------|
| `pipeline/sql/create_excluded_firms_table.sql` | Creates the main exclusion patterns table |
| `pipeline/sql/create_excluded_firm_crds_table.sql` | Creates the CRD exclusions table |
| `pipeline/sql/manage_excluded_firms.sql` | Helper queries for managing exclusions |

## Benefits of This Approach

1. **Easier maintenance** - Add/remove exclusions without editing complex SQL
2. **Audit trail** - `added_date` tracks when exclusions were added
3. **Documentation** - `reason` explains why each firm is excluded
4. **Reusable** - Same tables can be used by future lead lists
5. **Queryable** - Easy to see all exclusions and their categories
