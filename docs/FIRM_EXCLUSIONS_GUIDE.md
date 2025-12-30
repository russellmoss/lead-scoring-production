# Firm Exclusions System Guide

**Purpose**: Centralized system for managing firm exclusions in lead list generation  
**Status**: ✅ Production  
**Version**: 1.0  
**Last Updated**: December 30, 2025

---

## Executive Summary

The Firm Exclusions System provides a **centralized, maintainable approach** to excluding specific firms or firm patterns from lead lists. Instead of hardcoding exclusion patterns in SQL queries, exclusions are managed in dedicated BigQuery tables that can be updated without modifying production SQL.

**Key Benefits**:
- **Centralized Management**: All exclusions in one place
- **Easy Updates**: Add/remove exclusions without touching production SQL
- **Audit Trail**: Track when and why exclusions were added
- **Reusability**: Same exclusion tables used across all lead list queries

---

## Architecture

### BigQuery Tables

**1. Pattern-Based Exclusions**: `ml_features.excluded_firms`
- **Purpose**: Exclude firms matching specific patterns (e.g., '%WIREHOUSE%')
- **Columns**: `pattern`, `category`, `added_date`, `reason`
- **Usage**: `WHERE UPPER(firm_name) NOT LIKE pattern`

**2. CRD-Based Exclusions**: `ml_features.excluded_firm_crds`
- **Purpose**: Exclude specific firms by exact CRD (more precise than patterns)
- **Columns**: `firm_crd`, `firm_name`, `category`, `added_date`, `reason`
- **Usage**: `WHERE firm_crd NOT IN (SELECT firm_crd FROM excluded_firm_crds)`

### SQL Files

**1. Create Tables**: 
- `pipeline/sql/create_excluded_firms_table.sql` - Creates pattern-based exclusions table
- `pipeline/sql/create_excluded_firm_crds_table.sql` - Creates CRD-based exclusions table

**2. Management Queries**: 
- `pipeline/sql/manage_excluded_firms.sql` - Helper queries for adding/removing/viewing exclusions

**3. Usage in Lead Lists**: 
- `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` - References exclusion tables

---

## Exclusion Categories

### Wirehouses

**Pattern**: Major broker-dealers with captive advisors

**Examples**:
- '%J.P. MORGAN%'
- '%MORGAN STANLEY%'
- '%MERRILL%' (Bank of America)
- '%WELLS FARGO%'
- '%UBS %'
- '%EDWARD JONES%'
- '%AMERIPRISE%'
- '%RAYMOND JAMES%'
- '%GOLDMAN SACHS%'
- '%CITIGROUP%'
- '%BMO NESBITT%'
- '%NESBITT BURNS%'

**Reason**: Captive advisors cannot move their book of business

### Large Independent Broker-Dealers (IBDs)

**Pattern**: High volume, low conversion firms

**Examples**:
- '%LPL FINANCIAL%' (Largest IBD)
- '%COMMONWEALTH%'
- '%CETERA%'
- '%CAMBRIDGE%'
- '%OSAIC%' (formerly Advisor Group)
- '%PRIMERICA%' (MLM-style)

**Reason**: High volume but historically low conversion rates

### Custodians

**Pattern**: Not advisory firms (retail/custodial)

**Examples**:
- '%FIDELITY%'
- '%SCHWAB%'
- '%VANGUARD%'

**Reason**: Not target market (retail investors, not advisors)

### Insurance Companies & Broker-Dealers

**Pattern**: Insurance companies and their BD subsidiaries

**Examples**:
- '%NORTHWESTERN MUTUAL%'
- '%PRUDENTIAL%'
- '%PRUCO%' (Prudential BD)
- '%STATE FARM%'
- '%ALLSTATE%'
- '%NEW YORK LIFE%'
- '%NYLIFE%' (NYL BD)
- '%TRANSAMERICA%'
- '%FARM BUREAU%'
- '%NATIONWIDE%'
- '%LINCOLN FINANCIAL%'
- '%MASS MUTUAL%'
- '%MASSMUTUAL%'
- '%ONEAMERICA%'
- '%M HOLDINGS SECURITIES%' (M Financial)
- '%NUVEEN SECURITIES%' (TIAA)
- '%INSURANCE%' (Generic catch-all)

**Reason**: Captive insurance agents, not independent advisors

### Bank Broker-Dealers

**Pattern**: Bank-owned broker-dealers

**Examples**:
- '%BMO NESBITT%'
- '%NESBITT BURNS%'

**Reason**: Bank-owned, captive advisors

### Internal / Partner Firms

**Pattern**: Our own firms and partners (do not contact)

**Examples**:
- '%SAVVY WEALTH%'
- '%SAVVY ADVISORS%'
- '%RITHOLTZ%' (Partner firm)

**Reason**: Internal firms or partner firms - do not contact

**CRD Exclusions**:
- CRD 318493: Savvy Advisors, Inc. (Internal)
- CRD 168652: Ritholtz Wealth Management (Partner)

---

## Usage in Lead List SQL

### Pattern-Based Exclusions

```sql
-- Reference exclusion table
excluded_firms AS (
    SELECT pattern as firm_pattern
    FROM `savvy-gtm-analytics.ml_features.excluded_firms`
),

-- Apply exclusions
filtered_leads AS (
    SELECT *
    FROM leads l
    LEFT JOIN excluded_firms ef
        ON UPPER(l.firm_name) LIKE ef.firm_pattern
    WHERE ef.pattern IS NULL  -- Anti-join: exclude matches
)
```

### CRD-Based Exclusions

```sql
-- Reference exclusion table
excluded_firm_crds AS (
    SELECT firm_crd
    FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
),

-- Apply exclusions
filtered_leads AS (
    SELECT *
    FROM leads l
    WHERE l.firm_crd NOT IN (SELECT firm_crd FROM excluded_firm_crds)
)
```

---

## Managing Exclusions

### View All Exclusions

```sql
-- View pattern-based exclusions
SELECT * FROM `savvy-gtm-analytics.ml_features.excluded_firms`
ORDER BY category, pattern;

-- View CRD-based exclusions
SELECT * FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
ORDER BY firm_name;
```

### Add a New Pattern Exclusion

```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firms` 
VALUES ('%NEW FIRM NAME%', 'Category', CURRENT_DATE(), 'Reason for exclusion');
```

**Example**:
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firms` 
VALUES ('%NEW WIREHOUSE%', 'Wirehouse', CURRENT_DATE(), 'New wirehouse - captive advisors');
```

### Add a New CRD Exclusion

```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firm_crds`
VALUES (123456, 'Firm Name', 'Category', CURRENT_DATE(), 'Reason for exclusion');
```

**Example**:
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firm_crds`
VALUES (999999, 'Specific Firm LLC', 'Internal', CURRENT_DATE(), 'Internal firm - do not contact');
```

### Remove an Exclusion

```sql
-- Remove pattern exclusion
DELETE FROM `savvy-gtm-analytics.ml_features.excluded_firms`
WHERE pattern = '%PATTERN_TO_REMOVE%';

-- Remove CRD exclusion
DELETE FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
WHERE firm_crd = 123456;
```

### Check if a Firm Would Be Excluded

```sql
DECLARE test_firm STRING DEFAULT 'PRUCO SECURITIES LLC';

SELECT 
    test_firm as firm_name,
    ef.pattern,
    ef.category,
    ef.reason
FROM `savvy-gtm-analytics.ml_features.excluded_firms` ef
WHERE UPPER(test_firm) LIKE ef.pattern;
```

---

## Verification

### Verify Exclusions Are Working

```sql
-- Check if any excluded firms appear in lead list
SELECT 
    l.firm_name,
    COUNT(*) as advisor_count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` l
WHERE EXISTS (
    SELECT 1 
    FROM `savvy-gtm-analytics.ml_features.excluded_firms` ef
    WHERE UPPER(l.firm_name) LIKE ef.pattern
)
GROUP BY l.firm_name
ORDER BY advisor_count DESC;

-- Expected: 0 rows (all excluded firms should be filtered out)
```

### Find Potential New Exclusions

```sql
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

## Best Practices

### When to Use Pattern vs CRD

**Use Pattern**:
- Multiple firms with similar names (e.g., all Prudential subsidiaries)
- Generic categories (e.g., all insurance companies)
- Future-proofing (catches new firms with same pattern)

**Use CRD**:
- Specific firm that doesn't match any pattern
- Precise exclusion (no risk of false positives)
- One-off exclusions

### Pattern Design

**Good Patterns**:
- `'%WIREHOUSE%'` - Catches all variations
- `'%PRUDENTIAL%'` - Catches Prudential and subsidiaries
- `'%UBS %'` and `'%UBS,%'` - Catches space and comma variants

**Avoid Overly Broad Patterns**:
- `'%SECURITIES%'` - Too broad (would exclude legitimate firms)
- `'%FINANCIAL%'` - Too broad (most firms have "Financial" in name)

### Maintenance Schedule

**Monthly**: Review new exclusions based on lead list analysis  
**Quarterly**: Audit exclusion effectiveness (are excluded firms still appearing?)  
**Annually**: Review all exclusions for relevance

---

## Related Documentation

- `pipeline/sql/create_excluded_firms_table.sql` - Table creation SQL
- `pipeline/sql/create_excluded_firm_crds_table.sql` - CRD table creation SQL
- `pipeline/sql/manage_excluded_firms.sql` - Management queries
- `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` - Usage example
- `README.md` - Firm Exclusions section

---

**Document Status**: Production  
**Maintained By**: Data Science Team  
**Last Review**: December 30, 2025

