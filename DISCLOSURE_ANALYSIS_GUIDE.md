# Disclosure Fields Conversion Analysis

**Version**: 1.0  
**Created**: January 7, 2026  
**Purpose**: Determine if FINTRX disclosure fields impact lead conversion (Contacted → MQL) and whether to exclude leads with disclosures  
**Status**: 🔬 Ready for Agentic Analysis

---

## Executive Summary

### Current State
- FINTRX provides 9 boolean disclosure fields for each advisor
- These disclosures indicate regulatory/legal events: bankruptcies, customer disputes, terminations, criminal records, etc.
- **Currently NOT used** in V3 tier logic or V4 feature engineering
- **No exclusion** based on disclosures exists in lead list generation
- **Hypothesis**: Advisors with disclosures may convert at different rates (likely lower)

### Disclosure Fields Available

| Field | Description |
|-------|-------------|
| `CONTACT_HAS_DISCLOSED_BANKRUPT` | Advisor has disclosed bankruptcy |
| `CONTACT_HAS_DISCLOSED_BOND` | Advisor has disclosed bond-related issue |
| `CONTACT_HAS_DISCLOSED_CIVIL_EVENT` | Advisor has disclosed civil litigation |
| `CONTACT_HAS_DISCLOSED_CRIMINAL` | Advisor has disclosed criminal record |
| `CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE` | Advisor has disclosed customer complaint |
| `CONTACT_HAS_DISCLOSED_INVESTIGATION` | Advisor has disclosed regulatory investigation |
| `CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN` | Advisor has disclosed judgment/lien |
| `CONTACT_HAS_DISCLOSED_REGULATORY_EVENT` | Advisor has disclosed regulatory action |
| `CONTACT_HAS_DISCLOSED_TERMINATION` | Advisor has disclosed termination |

### Research Questions
1. What is the overall conversion rate for advisors WITH vs WITHOUT any disclosure?
2. Which specific disclosure types have the strongest negative (or positive) impact on conversion?
3. Do disclosures interact with V3 tiers? (e.g., does a T1 lead with disclosures still convert well?)
4. Do disclosures interact with V4 scores? (e.g., does V4 already capture disclosure signal?)
5. **Decision**: Should we EXCLUDE all leads with disclosures, or add disclosure as a V4 feature?

---

## Data Sources

### Primary Tables

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `savvy-gtm-analytics.SavvyGTMData.Lead` | Lead outcomes | `FA_CRD__c`, `stage_entered_contacting__c`, `Stage_Entered_Call_Scheduled__c` |
| `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` | Disclosure data | `RIA_CONTACT_CRD_ID`, `CONTACT_HAS_DISCLOSED_*` |
| `savvy-gtm-analytics.ml_features.v4_prospect_scores` | V4 scores | `crd`, `v4_score`, `v4_percentile` |

### PIT (Point-in-Time) Adherence

**CRITICAL**: All analysis uses a 43-day maturity window from contacting to MQL conversion, matching our V3 validation methodology. We only analyze leads that have had at least 43 days to mature.

---

## Analysis Instructions for Cursor.ai

> **IMPORTANT**: Execute these SQL queries in order using your BigQuery MCP integration.
> After each query, record the results.
> At the end, export all findings to `disclosure_analysis_results.md` in the root directory.

---

## Phase 1: Disclosure Distribution & Coverage

### Query 1.1: Disclosure Coverage in FINTRX

**Purpose**: Check data quality and coverage of disclosure fields

```sql
-- Query 1.1: Disclosure Coverage Check
-- How many contacts have disclosure data available?

SELECT 
    COUNT(*) as total_contacts,
    -- Individual disclosure coverage
    COUNTIF(CONTACT_HAS_DISCLOSED_BANKRUPT IS NOT NULL) as has_bankrupt_data,
    COUNTIF(CONTACT_HAS_DISCLOSED_BOND IS NOT NULL) as has_bond_data,
    COUNTIF(CONTACT_HAS_DISCLOSED_CIVIL_EVENT IS NOT NULL) as has_civil_data,
    COUNTIF(CONTACT_HAS_DISCLOSED_CRIMINAL IS NOT NULL) as has_criminal_data,
    COUNTIF(CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE IS NOT NULL) as has_dispute_data,
    COUNTIF(CONTACT_HAS_DISCLOSED_INVESTIGATION IS NOT NULL) as has_investigation_data,
    COUNTIF(CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN IS NOT NULL) as has_judgment_data,
    COUNTIF(CONTACT_HAS_DISCLOSED_REGULATORY_EVENT IS NOT NULL) as has_regulatory_data,
    COUNTIF(CONTACT_HAS_DISCLOSED_TERMINATION IS NOT NULL) as has_termination_data,
    -- Any disclosure = TRUE counts
    COUNTIF(CONTACT_HAS_DISCLOSED_BANKRUPT = TRUE) as count_bankrupt,
    COUNTIF(CONTACT_HAS_DISCLOSED_BOND = TRUE) as count_bond,
    COUNTIF(CONTACT_HAS_DISCLOSED_CIVIL_EVENT = TRUE) as count_civil,
    COUNTIF(CONTACT_HAS_DISCLOSED_CRIMINAL = TRUE) as count_criminal,
    COUNTIF(CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE = TRUE) as count_dispute,
    COUNTIF(CONTACT_HAS_DISCLOSED_INVESTIGATION = TRUE) as count_investigation,
    COUNTIF(CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN = TRUE) as count_judgment,
    COUNTIF(CONTACT_HAS_DISCLOSED_REGULATORY_EVENT = TRUE) as count_regulatory,
    COUNTIF(CONTACT_HAS_DISCLOSED_TERMINATION = TRUE) as count_termination
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`;
```

**Record**: Coverage percentages and raw counts for each disclosure type.

---

### Query 1.2: Composite Disclosure Indicator

**Purpose**: Create a summary of advisors with ANY disclosure vs CLEAN record

```sql
-- Query 1.2: Composite Disclosure Indicator
-- How many advisors have at least one disclosure?

SELECT 
    CASE 
        WHEN COALESCE(CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) = TRUE
          OR COALESCE(CONTACT_HAS_DISCLOSED_BOND, FALSE) = TRUE
          OR COALESCE(CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = TRUE
          OR COALESCE(CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = TRUE
          OR COALESCE(CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = TRUE
          OR COALESCE(CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = TRUE
          OR COALESCE(CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) = TRUE
          OR COALESCE(CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = TRUE
          OR COALESCE(CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = TRUE
        THEN 'HAS_DISCLOSURE'
        ELSE 'CLEAN_RECORD'
    END as disclosure_status,
    COUNT(*) as advisor_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct_of_total
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
GROUP BY 1
ORDER BY 1;
```

---

## Phase 2: Disclosure Impact on Conversion Rate

### Query 2.1: Overall Conversion by Disclosure Status

**Purpose**: The key question - do advisors with disclosures convert differently?

```sql
-- Query 2.1: Conversion Rate by Disclosure Status (ANY Disclosure)
-- PIT-compliant: 43-day maturity window

WITH lead_disclosure AS (
    SELECT 
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        -- Composite disclosure indicator
        CASE 
            WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = TRUE
            THEN 'HAS_DISCLOSURE'
            ELSE 'CLEAN_RECORD'
        END as disclosure_status,
        -- Count of disclosures
        (CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) THEN 1 ELSE 0 END) as disclosure_count
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      -- PIT: 43-day maturity window
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
)

SELECT 
    disclosure_status,
    COUNT(*) as contacted,
    SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as converted_to_mql,
    ROUND(
        SAFE_DIVIDE(
            SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            COUNT(*)
        ) * 100, 2
    ) as conversion_rate_pct,
    -- 95% CI
    ROUND(
        (SAFE_DIVIDE(
            SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            COUNT(*)
        ) - 1.96 * SQRT(
            SAFE_DIVIDE(
                SAFE_DIVIDE(
                    SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
                    COUNT(*)
                ) * (1 - SAFE_DIVIDE(
                    SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
                    COUNT(*)
                )),
                COUNT(*)
            )
        )) * 100, 2
    ) as ci_lower_95_pct,
    ROUND(
        (SAFE_DIVIDE(
            SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            COUNT(*)
        ) + 1.96 * SQRT(
            SAFE_DIVIDE(
                SAFE_DIVIDE(
                    SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
                    COUNT(*)
                ) * (1 - SAFE_DIVIDE(
                    SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
                    COUNT(*)
                )),
                COUNT(*)
            )
        )) * 100, 2
    ) as ci_upper_95_pct
FROM lead_disclosure
GROUP BY disclosure_status
ORDER BY disclosure_status;
```

**Expected Output Format**:
```markdown
| Disclosure Status | Contacted | MQLs | Conv Rate | 95% CI Lower | 95% CI Upper |
|-------------------|-----------|------|-----------|--------------|--------------|
| CLEAN_RECORD      | X         | X    | X.XX%     | X.XX%        | X.XX%        |
| HAS_DISCLOSURE    | X         | X    | X.XX%     | X.XX%        | X.XX%        |
```

---

### Query 2.2: Conversion by Disclosure Count

**Purpose**: Does having MORE disclosures make conversion worse?

```sql
-- Query 2.2: Conversion by Number of Disclosures
-- Check if more disclosures = worse conversion

WITH lead_disclosure AS (
    SELECT 
        l.Id as lead_id,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        -- Count of disclosures
        (CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) THEN 1 ELSE 0 END +
         CASE WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) THEN 1 ELSE 0 END) as disclosure_count
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
)

SELECT 
    CASE 
        WHEN disclosure_count = 0 THEN '0_NONE'
        WHEN disclosure_count = 1 THEN '1_SINGLE'
        WHEN disclosure_count = 2 THEN '2_TWO'
        WHEN disclosure_count >= 3 THEN '3_PLUS_MULTIPLE'
    END as disclosure_bucket,
    COUNT(*) as contacted,
    SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as converted,
    ROUND(
        SAFE_DIVIDE(
            SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            COUNT(*)
        ) * 100, 2
    ) as conversion_rate_pct
FROM lead_disclosure
GROUP BY 1
ORDER BY 1;
```

---

### Query 2.3: Conversion by Individual Disclosure Type

**Purpose**: Which specific disclosures have the biggest impact?

```sql
-- Query 2.3: Conversion by Individual Disclosure Type
-- Which disclosures matter most?

WITH lead_disclosure AS (
    SELECT 
        l.Id as lead_id,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) as has_bankrupt,
        COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) as has_bond,
        COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) as has_civil,
        COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) as has_criminal,
        COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) as has_dispute,
        COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) as has_investigation,
        COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) as has_judgment,
        COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) as has_regulatory,
        COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) as has_termination
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
),

baseline AS (
    SELECT 
        SAFE_DIVIDE(
            SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            COUNT(*)
        ) as baseline_rate
    FROM lead_disclosure
)

SELECT 
    disclosure_type,
    contacted,
    converted,
    conversion_rate_pct,
    ROUND(conversion_rate_pct / (SELECT baseline_rate * 100 FROM baseline), 2) as lift_vs_baseline
FROM (
    SELECT 'BANKRUPT' as disclosure_type,
           COUNTIF(has_bankrupt) as contacted,
           SUM(CASE WHEN has_bankrupt AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as converted,
           ROUND(SAFE_DIVIDE(
               SUM(CASE WHEN has_bankrupt AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
               COUNTIF(has_bankrupt)
           ) * 100, 2) as conversion_rate_pct
    FROM lead_disclosure
    
    UNION ALL
    
    SELECT 'BOND',
           COUNTIF(has_bond),
           SUM(CASE WHEN has_bond AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
           ROUND(SAFE_DIVIDE(
               SUM(CASE WHEN has_bond AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
               COUNTIF(has_bond)
           ) * 100, 2)
    FROM lead_disclosure
    
    UNION ALL
    
    SELECT 'CIVIL_EVENT',
           COUNTIF(has_civil),
           SUM(CASE WHEN has_civil AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
           ROUND(SAFE_DIVIDE(
               SUM(CASE WHEN has_civil AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
               COUNTIF(has_civil)
           ) * 100, 2)
    FROM lead_disclosure
    
    UNION ALL
    
    SELECT 'CRIMINAL',
           COUNTIF(has_criminal),
           SUM(CASE WHEN has_criminal AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
           ROUND(SAFE_DIVIDE(
               SUM(CASE WHEN has_criminal AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
               COUNTIF(has_criminal)
           ) * 100, 2)
    FROM lead_disclosure
    
    UNION ALL
    
    SELECT 'CUSTOMER_DISPUTE',
           COUNTIF(has_dispute),
           SUM(CASE WHEN has_dispute AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
           ROUND(SAFE_DIVIDE(
               SUM(CASE WHEN has_dispute AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
               COUNTIF(has_dispute)
           ) * 100, 2)
    FROM lead_disclosure
    
    UNION ALL
    
    SELECT 'INVESTIGATION',
           COUNTIF(has_investigation),
           SUM(CASE WHEN has_investigation AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
           ROUND(SAFE_DIVIDE(
               SUM(CASE WHEN has_investigation AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
               COUNTIF(has_investigation)
           ) * 100, 2)
    FROM lead_disclosure
    
    UNION ALL
    
    SELECT 'JUDGMENT_OR_LIEN',
           COUNTIF(has_judgment),
           SUM(CASE WHEN has_judgment AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
           ROUND(SAFE_DIVIDE(
               SUM(CASE WHEN has_judgment AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
               COUNTIF(has_judgment)
           ) * 100, 2)
    FROM lead_disclosure
    
    UNION ALL
    
    SELECT 'REGULATORY_EVENT',
           COUNTIF(has_regulatory),
           SUM(CASE WHEN has_regulatory AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
           ROUND(SAFE_DIVIDE(
               SUM(CASE WHEN has_regulatory AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
               COUNTIF(has_regulatory)
           ) * 100, 2)
    FROM lead_disclosure
    
    UNION ALL
    
    SELECT 'TERMINATION',
           COUNTIF(has_termination),
           SUM(CASE WHEN has_termination AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
           ROUND(SAFE_DIVIDE(
               SUM(CASE WHEN has_termination AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
               COUNTIF(has_termination)
           ) * 100, 2)
    FROM lead_disclosure
    
    UNION ALL
    
    -- Baseline: NO disclosures
    SELECT 'BASELINE_NO_DISCLOSURE',
           COUNTIF(NOT has_bankrupt AND NOT has_bond AND NOT has_civil AND NOT has_criminal 
                   AND NOT has_dispute AND NOT has_investigation AND NOT has_judgment 
                   AND NOT has_regulatory AND NOT has_termination),
           SUM(CASE WHEN NOT has_bankrupt AND NOT has_bond AND NOT has_civil AND NOT has_criminal 
                        AND NOT has_dispute AND NOT has_investigation AND NOT has_judgment 
                        AND NOT has_regulatory AND NOT has_termination
                        AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 
                   THEN 1 ELSE 0 END),
           ROUND(SAFE_DIVIDE(
               SUM(CASE WHEN NOT has_bankrupt AND NOT has_bond AND NOT has_civil AND NOT has_criminal 
                            AND NOT has_dispute AND NOT has_investigation AND NOT has_judgment 
                            AND NOT has_regulatory AND NOT has_termination
                            AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 
                       THEN 1 ELSE 0 END),
               COUNTIF(NOT has_bankrupt AND NOT has_bond AND NOT has_civil AND NOT has_criminal 
                       AND NOT has_dispute AND NOT has_investigation AND NOT has_judgment 
                       AND NOT has_regulatory AND NOT has_termination)
           ) * 100, 2)
    FROM lead_disclosure
)
WHERE contacted > 0
ORDER BY lift_vs_baseline ASC;
```

**Expected Output**: Table showing each disclosure type's conversion rate and lift vs baseline

---

## Phase 3: Disclosure × V3 Tier Interaction

### Query 3.1: Disclosure Impact Within V3 Tiers

**Purpose**: Do disclosures hurt conversion even in high-converting tiers?

```sql
-- Query 3.1: Disclosure Impact by V3 Tier
-- Does disclosure status matter within each tier?

WITH lead_data AS (
    SELECT 
        l.Id as lead_id,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        -- Get V3 tier from the lead narrative or existing scoring
        COALESCE(l.Lead_Score_Tier__c, 'STANDARD') as v3_tier,
        -- Composite disclosure indicator
        CASE 
            WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = TRUE
            THEN 'HAS_DISCLOSURE'
            ELSE 'CLEAN_RECORD'
        END as disclosure_status
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
)

SELECT 
    v3_tier,
    disclosure_status,
    COUNT(*) as contacted,
    SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as converted,
    ROUND(
        SAFE_DIVIDE(
            SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            COUNT(*)
        ) * 100, 2
    ) as conversion_rate_pct
FROM lead_data
WHERE v3_tier IS NOT NULL
GROUP BY v3_tier, disclosure_status
ORDER BY v3_tier, disclosure_status;
```

---

### Query 3.2: Disclosure Impact on Top Tiers Specifically

**Purpose**: Should we exclude disclosures even from T1A/T1B/T1 leads?

```sql
-- Query 3.2: Disclosure Impact on Top V3 Tiers (T1A, T1B, T1, T2)
-- Critical question: Do T1 leads with disclosures still convert well?

WITH lead_data AS (
    SELECT 
        l.Id as lead_id,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        COALESCE(l.Lead_Score_Tier__c, 'STANDARD') as v3_tier,
        CASE 
            WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = TRUE
            THEN 1 ELSE 0
        END as has_disclosure
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
      AND COALESCE(l.Lead_Score_Tier__c, 'STANDARD') IN ('TIER_1A_PRIME_MOVER_CFP', 'TIER_1B_PRIME_MOVER_SERIES65', 
                                                          'TIER_1_PRIME_MOVER', 'TIER_2_PROVEN_MOVER')
)

SELECT 
    v3_tier,
    -- Clean record stats
    SUM(CASE WHEN has_disclosure = 0 THEN 1 ELSE 0 END) as clean_contacted,
    SUM(CASE WHEN has_disclosure = 0 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as clean_converted,
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN has_disclosure = 0 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        SUM(CASE WHEN has_disclosure = 0 THEN 1 ELSE 0 END)
    ) * 100, 2) as clean_conv_rate,
    -- Disclosure stats
    SUM(CASE WHEN has_disclosure = 1 THEN 1 ELSE 0 END) as disclosure_contacted,
    SUM(CASE WHEN has_disclosure = 1 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as disclosure_converted,
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN has_disclosure = 1 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        SUM(CASE WHEN has_disclosure = 1 THEN 1 ELSE 0 END)
    ) * 100, 2) as disclosure_conv_rate,
    -- Difference
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN has_disclosure = 0 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        SUM(CASE WHEN has_disclosure = 0 THEN 1 ELSE 0 END)
    ) * 100 - SAFE_DIVIDE(
        SUM(CASE WHEN has_disclosure = 1 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        SUM(CASE WHEN has_disclosure = 1 THEN 1 ELSE 0 END)
    ) * 100, 2) as conv_rate_difference_pct
FROM lead_data
GROUP BY v3_tier
ORDER BY v3_tier;
```

---

## Phase 4: Disclosure × V4 Score Interaction

### Query 4.1: Disclosure Impact Across V4 Score Deciles

**Purpose**: Does V4 already capture disclosure signal, or is it additive?

```sql
-- Query 4.1: Disclosure Impact by V4 Score Decile
-- Does disclosure hurt conversion even among high V4 scores?

WITH lead_data AS (
    SELECT 
        l.Id as lead_id,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        v4.v4_percentile,
        NTILE(10) OVER (ORDER BY v4.v4_percentile) as v4_decile,
        CASE 
            WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = TRUE
            THEN 1 ELSE 0
        END as has_disclosure
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = v4.crd
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
      AND v4.v4_percentile IS NOT NULL
)

SELECT 
    v4_decile,
    -- Clean record stats
    SUM(CASE WHEN has_disclosure = 0 THEN 1 ELSE 0 END) as clean_contacted,
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN has_disclosure = 0 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        SUM(CASE WHEN has_disclosure = 0 THEN 1 ELSE 0 END)
    ) * 100, 2) as clean_conv_rate,
    -- Disclosure stats
    SUM(CASE WHEN has_disclosure = 1 THEN 1 ELSE 0 END) as disclosure_contacted,
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN has_disclosure = 1 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        SUM(CASE WHEN has_disclosure = 1 THEN 1 ELSE 0 END)
    ) * 100, 2) as disclosure_conv_rate,
    -- Is disclosure additive signal?
    ROUND(SAFE_DIVIDE(
        SAFE_DIVIDE(
            SUM(CASE WHEN has_disclosure = 0 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            SUM(CASE WHEN has_disclosure = 0 THEN 1 ELSE 0 END)
        ),
        SAFE_DIVIDE(
            SUM(CASE WHEN has_disclosure = 1 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            SUM(CASE WHEN has_disclosure = 1 THEN 1 ELSE 0 END)
        )
    ), 2) as clean_vs_disclosure_lift
FROM lead_data
GROUP BY v4_decile
ORDER BY v4_decile;
```

---

### Query 4.2: V4 Score Distribution by Disclosure Status

**Purpose**: Do advisors with disclosures already have lower V4 scores?

```sql
-- Query 4.2: V4 Score Distribution by Disclosure Status
-- Does V4 already penalize disclosures?

WITH lead_data AS (
    SELECT 
        v4.v4_score,
        v4.v4_percentile,
        CASE 
            WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = TRUE
            THEN 'HAS_DISCLOSURE'
            ELSE 'CLEAN_RECORD'
        END as disclosure_status
    FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON v4.crd = c.RIA_CONTACT_CRD_ID
)

SELECT 
    disclosure_status,
    COUNT(*) as prospect_count,
    ROUND(AVG(v4_score), 4) as avg_v4_score,
    ROUND(AVG(v4_percentile), 1) as avg_v4_percentile,
    ROUND(STDDEV(v4_percentile), 1) as stddev_percentile,
    APPROX_QUANTILES(v4_percentile, 4)[OFFSET(1)] as percentile_25th,
    APPROX_QUANTILES(v4_percentile, 4)[OFFSET(2)] as percentile_50th,
    APPROX_QUANTILES(v4_percentile, 4)[OFFSET(3)] as percentile_75th
FROM lead_data
GROUP BY disclosure_status
ORDER BY disclosure_status;
```

---

## Phase 5: Impact Analysis for Exclusion Decision

### Query 5.1: Lost Conversions if We Exclude All Disclosures

**Purpose**: How many MQLs would we lose by excluding everyone with disclosures?

```sql
-- Query 5.1: Impact of Excluding All Disclosures
-- How many MQLs would we lose?

WITH lead_data AS (
    SELECT 
        l.Id as lead_id,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        CASE 
            WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = TRUE
            THEN 1 ELSE 0
        END as has_disclosure
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
)

SELECT 
    -- Total stats
    COUNT(*) as total_contacted,
    SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as total_converted,
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        COUNT(*)
    ) * 100, 2) as total_conv_rate,
    
    -- If we EXCLUDE disclosures
    SUM(CASE WHEN has_disclosure = 0 THEN 1 ELSE 0 END) as clean_contacted,
    SUM(CASE WHEN has_disclosure = 0 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as clean_converted,
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN has_disclosure = 0 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        SUM(CASE WHEN has_disclosure = 0 THEN 1 ELSE 0 END)
    ) * 100, 2) as clean_conv_rate,
    
    -- What we would LOSE
    SUM(CASE WHEN has_disclosure = 1 THEN 1 ELSE 0 END) as excluded_contacts,
    SUM(CASE WHEN has_disclosure = 1 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as lost_conversions,
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN has_disclosure = 1 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        SUM(CASE WHEN has_disclosure = 1 THEN 1 ELSE 0 END)
    ) * 100, 2) as excluded_conv_rate,
    
    -- Efficiency improvement
    ROUND(SAFE_DIVIDE(
        SAFE_DIVIDE(
            SUM(CASE WHEN has_disclosure = 0 AND mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            SUM(CASE WHEN has_disclosure = 0 THEN 1 ELSE 0 END)
        ),
        SAFE_DIVIDE(
            SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            COUNT(*)
        )
    ), 3) as efficiency_gain_factor
FROM lead_data;
```

---

### Query 5.2: Disclosure Prevalence in Current Lead List Universe

**Purpose**: How many leads in our typical pool have disclosures?

```sql
-- Query 5.2: Disclosure Prevalence in Lead List Universe
-- How many of our potential leads have disclosures?

SELECT 
    CASE 
        WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) = TRUE
          OR COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = TRUE
          OR COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = TRUE
          OR COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = TRUE
          OR COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = TRUE
          OR COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = TRUE
          OR COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) = TRUE
          OR COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = TRUE
          OR COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = TRUE
        THEN 'HAS_DISCLOSURE'
        ELSE 'CLEAN_RECORD'
    END as disclosure_status,
    COUNT(*) as prospect_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct_of_universe
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features` f
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON f.advisor_crd = c.RIA_CONTACT_CRD_ID
GROUP BY 1
ORDER BY 1;
```

---

## Phase 6: Disclosure as V4 Feature Candidate

### Query 6.1: Disclosure Correlation with Existing Features

**Purpose**: Is disclosure signal already captured by other features?

```sql
-- Query 6.1: Disclosure vs Existing Feature Correlation
-- Check if disclosure is captured by mobility, tenure, etc.

WITH feature_data AS (
    SELECT 
        f.advisor_crd,
        f.mobility_3yr,
        f.tenure_months,
        f.experience_years,
        f.firm_net_change_12mo,
        CASE 
            WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = TRUE
              OR COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = TRUE
            THEN 1 ELSE 0
        END as has_disclosure
    FROM `savvy-gtm-analytics.ml_features.v4_prospect_features` f
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON f.advisor_crd = c.RIA_CONTACT_CRD_ID
)

SELECT 
    'Disclosure vs Mobility 3yr' as correlation_pair,
    ROUND(CORR(has_disclosure, mobility_3yr), 4) as correlation
FROM feature_data

UNION ALL

SELECT 
    'Disclosure vs Tenure Months',
    ROUND(CORR(has_disclosure, tenure_months), 4)
FROM feature_data

UNION ALL

SELECT 
    'Disclosure vs Experience Years',
    ROUND(CORR(has_disclosure, experience_years), 4)
FROM feature_data

UNION ALL

SELECT 
    'Disclosure vs Firm Net Change',
    ROUND(CORR(has_disclosure, firm_net_change_12mo), 4)
FROM feature_data;
```

---

## Results Documentation Instructions

After running all queries, create `disclosure_analysis_results.md` in the root directory with the following structure:

```markdown
# Disclosure Analysis Results

**Analysis Date**: [DATE]
**Executed By**: Cursor.ai Agentic Analysis
**BigQuery Project**: savvy-gtm-analytics

---

## Executive Summary

### Key Findings
1. [Overall disclosure impact on conversion rate]
2. [Most impactful disclosure type]
3. [Interaction with V3 tiers]
4. [Interaction with V4 scores]
5. [Lost conversions if excluded]

### Recommendation
**[ ] EXCLUDE** all leads with disclosures from lead lists
**[ ] ADD** disclosure as V4 feature (do not exclude)
**[ ] IGNORE** disclosure (no significant impact)

### Rationale
[Explain the recommendation based on data]

---

## Detailed Results

### Phase 1: Disclosure Distribution

#### Query 1.1: Coverage Check
[Results table]

#### Query 1.2: Composite Indicator
[Results table]

### Phase 2: Conversion Impact

#### Query 2.1: Overall Conversion by Disclosure
| Disclosure Status | Contacted | MQLs | Conv Rate | 95% CI | Lift vs Baseline |
|-------------------|-----------|------|-----------|--------|------------------|
| CLEAN_RECORD      | X         | X    | X.XX%     | X.XX%  | X.XXx            |
| HAS_DISCLOSURE    | X         | X    | X.XX%     | X.XX%  | X.XXx            |

#### Query 2.2: Conversion by Disclosure Count
[Results table]

#### Query 2.3: Conversion by Individual Disclosure Type
[Results table - sorted by lift]

### Phase 3: V3 Tier Interaction

#### Query 3.1: Disclosure by Tier
[Results table]

#### Query 3.2: Top Tier Impact
[Results table]

**Key Finding**: [Do T1 leads with disclosures still convert well?]

### Phase 4: V4 Score Interaction

#### Query 4.1: Disclosure by V4 Decile
[Results table]

#### Query 4.2: V4 Score Distribution
[Results table]

**Key Finding**: [Does V4 already penalize disclosures?]

### Phase 5: Exclusion Impact Analysis

#### Query 5.1: Lost Conversions
- Total Contacted: [X]
- Would Exclude: [X] ([X]%)
- Lost MQLs: [X]
- Efficiency Gain: [X]x

#### Query 5.2: Universe Prevalence
[Results table]

### Phase 6: Feature Candidate Analysis

#### Query 6.1: Feature Correlation
[Results table]

**Key Finding**: [Is disclosure signal independent or redundant?]

---

## Statistical Conclusions

### Is Disclosure a Significant Signal?
- Conversion rate difference: [X]%
- 95% CI overlap: [Yes/No]
- Statistically significant: [Yes/No]

### Does Disclosure Interact with V3 Tiers?
[Answer]

### Does V4 Already Capture Disclosure Signal?
[Answer based on Query 4.2 - if V4 scores are similar regardless of disclosure, V4 doesn't capture it]

### Is Disclosure Redundant with Existing Features?
[Answer based on Query 6.1 - if correlation < 0.1, it's independent]

---

## Recommendations

### Option A: EXCLUDE All Disclosures
**Implement if:**
- Disclosure conversion rate significantly lower (>1% absolute difference)
- Lost MQLs are minimal (<5% of total)
- Efficiency gain is meaningful (>1.05x)

**Implementation:**
- Add to `base_prospects` CTE in lead list SQL
- Filter: `WHERE NOT (has_any_disclosure = TRUE)`

### Option B: Add as V4 Feature
**Implement if:**
- Disclosure is independent signal (correlation < 0.1 with existing features)
- Would improve model AUC
- Some disclosure leads still convert well (worth keeping in pool)

**Implementation:**
- Add `has_any_disclosure` as 24th feature
- Retrain V4.3.0 model

### Option C: No Action
**Implement if:**
- No significant conversion rate difference
- V4 already captures the signal
- Excluding would lose too many MQLs

---

## Appendix: SQL Queries Used

[Include all queries for reproducibility]
```

---

## Success Criteria

The analysis is considered successful if:

1. **Sample Size**: At least 500 leads with disclosures for statistical validity
2. **Clear Signal**: Conversion rate difference > 0.5% between clean vs disclosure
3. **Actionable Recommendation**: Clear yes/no on exclusion vs feature vs ignore
4. **Cost-Benefit**: Clear understanding of MQLs lost vs efficiency gained

---

## Decision Framework

| Condition | Recommendation |
|-----------|----------------|
| Disclosure conv rate < 50% of baseline | **EXCLUDE** |
| Disclosure conv rate 50-80% of baseline | **Consider V4 feature or deprioritize** |
| Disclosure conv rate > 80% of baseline | **IGNORE** |
| V4 already scores disclosure leads lower | **No action needed** |
| Disclosure is correlated with mobility/tenure | **Redundant - no action** |
