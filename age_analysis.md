# Age Bucket Conversion Analysis

**Version**: 1.0  
**Created**: January 7, 2026  
**Purpose**: Determine if AGE_RANGE from FINTRX is a signal for lead conversion (Contacted → MQL)  
**Status**: 🔬 Ready for Agentic Analysis

---

## Executive Summary

### Current State
- V3 and V4 pipelines **arbitrarily exclude** advisors over 65 years old
- Age filtering occurs in `base_prospects` CTE (line 230-233 of `January_2026_Lead_List_V3_V4_Hybrid.sql`)
- Current exclusion: `AGE_RANGE NOT IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99')`
- **No analysis has been done** to validate if this exclusion is optimal

### Research Questions
1. Does age bucket correlate with contacted → MQL conversion rate?
2. Should we include age buckets as a tier modifier in V3?
3. Should age be a feature in V4's XGBoost model?
4. Is the 65+ exclusion optimal, or should we adjust the cutoff?
5. Are there specific age × tier interactions (e.g., older advisors in bleeding firms convert better)?

---

## Data Sources

### Primary Tables

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `savvy-gtm-analytics.SavvyGTMData.Lead` | Lead outcomes | `FA_CRD__c`, `stage_entered_contacting__c`, `Stage_Entered_Call_Scheduled__c` |
| `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` | Age data | `RIA_CONTACT_CRD_ID`, `AGE_RANGE` |
| `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` | V3/V4 features | `advisor_crd`, `contacted_date`, features |
| `savvy-gtm-analytics.ml_features.lead_scores_v3` | V3 tier assignments | `advisor_crd`, `score_tier`, `contacted_date` |
| `savvy-gtm-analytics.ml_features.v4_prospect_scores` | V4 scores | `crd`, `v4_score`, `v4_percentile` |
| `savvy-gtm-analytics.ml_features.historical_lead_performance` | Historical conversion data | `crd`, `score_tier`, `converted_30d` |

### AGE_RANGE Values (from FINTRX)
```
'18-24', '25-29', '30-34', '35-39', '40-44', '45-49', 
'50-54', '55-59', '60-64', '65-69', '70-74', '75-79', 
'80-84', '85-89', '90-94', '95-99', NULL
```

---

## Analysis Instructions for Cursor.ai

> **IMPORTANT**: Execute these SQL queries in order using your BigQuery MCP integration.
> After each query, record the results in `age_analysis_results.md` in the root directory.
> Use the exact format specified in each section.

---

## Phase 1: Age Distribution in Historical Leads

### Query 1.1: Overall Age Distribution (Contacted Leads)

**Purpose**: Understand the age distribution of historically contacted leads

```sql
-- Query 1.1: Age Distribution in Historical Contacted Leads
-- Run this FIRST to understand sample sizes per age bucket

SELECT 
    COALESCE(c.AGE_RANGE, 'UNKNOWN') as age_range,
    COUNT(DISTINCT l.Id) as total_contacted,
    COUNT(DISTINCT CASE 
        WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL 
             AND DATE_DIFF(DATE(l.Stage_Entered_Call_Scheduled__c), DATE(l.stage_entered_contacting__c), DAY) <= 43
        THEN l.Id 
    END) as converted_to_mql,
    ROUND(
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE 
                WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL 
                     AND DATE_DIFF(DATE(l.Stage_Entered_Call_Scheduled__c), DATE(l.stage_entered_contacting__c), DAY) <= 43
                THEN l.Id 
            END),
            COUNT(DISTINCT l.Id)
        ) * 100, 2
    ) as conversion_rate_pct,
    -- Statistical significance helpers
    ROUND(
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE 
                WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL 
                     AND DATE_DIFF(DATE(l.Stage_Entered_Call_Scheduled__c), DATE(l.stage_entered_contacting__c), DAY) <= 43
                THEN l.Id 
            END),
            COUNT(DISTINCT l.Id)
        ), 4
    ) as p_hat,
    -- Calculate 95% CI width for each bucket
    ROUND(
        1.96 * SQRT(
            SAFE_DIVIDE(
                SAFE_DIVIDE(
                    COUNT(DISTINCT CASE 
                        WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL 
                             AND DATE_DIFF(DATE(l.Stage_Entered_Call_Scheduled__c), DATE(l.stage_entered_contacting__c), DAY) <= 43
                        THEN l.Id 
                    END),
                    COUNT(DISTINCT l.Id)
                ) * (1 - SAFE_DIVIDE(
                    COUNT(DISTINCT CASE 
                        WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL 
                             AND DATE_DIFF(DATE(l.Stage_Entered_Call_Scheduled__c), DATE(l.stage_entered_contacting__c), DAY) <= 43
                        THEN l.Id 
                    END),
                    COUNT(DISTINCT l.Id)
                )),
                COUNT(DISTINCT l.Id)
            )
        ) * 100, 2
    ) as ci_95_width_pct
FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
WHERE l.stage_entered_contacting__c IS NOT NULL
  AND l.IsDeleted = false
  -- Maturity filter: at least 43 days old (matches V3 maturity window)
  AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
GROUP BY c.AGE_RANGE
ORDER BY 
    CASE 
        WHEN c.AGE_RANGE IS NULL THEN 999
        ELSE SAFE_CAST(SPLIT(c.AGE_RANGE, '-')[OFFSET(0)] AS INT64)
    END;
```

**Expected Output Format** (record in results.md):
```markdown
| Age Range | Contacted | MQLs | Conv Rate | 95% CI Width | Lift vs Baseline |
|-----------|-----------|------|-----------|--------------|------------------|
| 25-29     | X         | X    | X.XX%     | ±X.XX%       | X.XXx            |
| ...       | ...       | ...  | ...       | ...          | ...              |
```

---

### Query 1.2: Age Group Aggregation (Simplified Buckets)

**Purpose**: Group ages into actionable buckets for potential tier logic

```sql
-- Query 1.2: Simplified Age Group Analysis
-- Groups ages into actionable buckets: YOUNG, MID_CAREER, SENIOR, VETERAN, UNKNOWN

WITH age_groups AS (
    SELECT 
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        c.AGE_RANGE,
        CASE 
            WHEN c.AGE_RANGE IN ('18-24', '25-29', '30-34') THEN 'A_YOUNG_UNDER_35'
            WHEN c.AGE_RANGE IN ('35-39', '40-44', '45-49') THEN 'B_PRIME_35_49'
            WHEN c.AGE_RANGE IN ('50-54', '55-59') THEN 'C_SENIOR_50_59'
            WHEN c.AGE_RANGE IN ('60-64') THEN 'D_VETERAN_60_64'
            WHEN c.AGE_RANGE IN ('65-69') THEN 'E_NEAR_RETIREMENT_65_69'
            WHEN c.AGE_RANGE IN ('70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 'F_RETIREMENT_70_PLUS'
            WHEN c.AGE_RANGE IS NULL THEN 'G_UNKNOWN'
            ELSE 'G_UNKNOWN'
        END as age_group
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
)

SELECT 
    age_group,
    COUNT(*) as contacted,
    SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as converted,
    ROUND(
        SAFE_DIVIDE(
            SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            COUNT(*)
        ) * 100, 2
    ) as conversion_rate_pct,
    -- Baseline comparison (will calculate in results)
    -- 95% CI Lower Bound
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
    -- 95% CI Upper Bound
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
FROM age_groups
GROUP BY age_group
ORDER BY age_group;
```

---

## Phase 2: Age × V3 Tier Interaction Analysis

### Query 2.1: Conversion by Age Group × V3 Tier

**Purpose**: Determine if age modifies V3 tier effectiveness

```sql
-- Query 2.1: Age × V3 Tier Interaction
-- This is CRITICAL for determining if age should be a tier modifier

WITH lead_data AS (
    SELECT 
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        c.AGE_RANGE,
        CASE 
            WHEN c.AGE_RANGE IN ('18-24', '25-29', '30-34', '35-39', '40-44', '45-49') THEN 'UNDER_50'
            WHEN c.AGE_RANGE IN ('50-54', '55-59', '60-64') THEN 'AGE_50_64'
            WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 'AGE_65_PLUS'
            ELSE 'UNKNOWN'
        END as age_bucket
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
),

tier_data AS (
    SELECT 
        SAFE_CAST(advisor_crd AS INT64) as crd,
        score_tier,
        contacted_date
    FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
    WHERE score_tier IS NOT NULL
)

SELECT 
    COALESCE(t.score_tier, 'NO_TIER_MATCH') as v3_tier,
    ld.age_bucket,
    COUNT(*) as contacted,
    SUM(CASE WHEN ld.mql_date IS NOT NULL AND DATE_DIFF(ld.mql_date, ld.contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as converted,
    ROUND(
        SAFE_DIVIDE(
            SUM(CASE WHEN ld.mql_date IS NOT NULL AND DATE_DIFF(ld.mql_date, ld.contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            COUNT(*)
        ) * 100, 2
    ) as conversion_rate_pct
FROM lead_data ld
LEFT JOIN tier_data t 
    ON ld.crd = t.crd 
    AND ABS(DATE_DIFF(t.contacted_date, ld.contacted_date, DAY)) <= 7
GROUP BY t.score_tier, ld.age_bucket
HAVING COUNT(*) >= 20  -- Minimum sample size for statistical validity
ORDER BY t.score_tier, ld.age_bucket;
```

**Key Analysis Questions**:
1. Does conversion rate vary by age WITHIN each tier?
2. Are older advisors in Tier 1 (bleeding firms) converting better/worse?
3. Should we create age-modified tiers (e.g., `TIER_1_PRIME_MOVER_UNDER_50`)?

---

### Query 2.2: Statistical Significance Test - Age Impact Within Tiers

**Purpose**: Chi-square style analysis to determine if age is statistically significant within each tier

```sql
-- Query 2.2: Age Impact Significance Within Top Tiers
-- Focus on high-value tiers to see if age modifies conversion

WITH lead_enriched AS (
    SELECT 
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        c.AGE_RANGE,
        -- Binary: Over 65 or not
        CASE WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 1 ELSE 0 END as is_over_65,
        -- Binary: Over 60 or not
        CASE WHEN c.AGE_RANGE IN ('60-64', '65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 1 ELSE 0 END as is_over_60,
        -- Binary: Over 55 or not
        CASE WHEN c.AGE_RANGE IN ('55-59', '60-64', '65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 1 ELSE 0 END as is_over_55
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
      AND c.AGE_RANGE IS NOT NULL  -- Exclude unknown age for this analysis
),

tier_data AS (
    SELECT 
        SAFE_CAST(advisor_crd AS INT64) as crd,
        score_tier,
        contacted_date
    FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
    WHERE score_tier IS NOT NULL
)

SELECT 
    COALESCE(t.score_tier, 'STANDARD') as v3_tier,
    
    -- Over 65 Analysis
    SUM(CASE WHEN le.is_over_65 = 1 THEN 1 ELSE 0 END) as over_65_contacted,
    SUM(CASE WHEN le.is_over_65 = 1 AND le.mql_date IS NOT NULL AND DATE_DIFF(le.mql_date, le.contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as over_65_converted,
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN le.is_over_65 = 1 AND le.mql_date IS NOT NULL AND DATE_DIFF(le.mql_date, le.contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        SUM(CASE WHEN le.is_over_65 = 1 THEN 1 ELSE 0 END)
    ) * 100, 2) as over_65_conv_rate,
    
    -- Under 65 Analysis
    SUM(CASE WHEN le.is_over_65 = 0 THEN 1 ELSE 0 END) as under_65_contacted,
    SUM(CASE WHEN le.is_over_65 = 0 AND le.mql_date IS NOT NULL AND DATE_DIFF(le.mql_date, le.contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as under_65_converted,
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN le.is_over_65 = 0 AND le.mql_date IS NOT NULL AND DATE_DIFF(le.mql_date, le.contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        SUM(CASE WHEN le.is_over_65 = 0 THEN 1 ELSE 0 END)
    ) * 100, 2) as under_65_conv_rate,
    
    -- Difference (positive = over 65 converts BETTER)
    ROUND(
        SAFE_DIVIDE(
            SUM(CASE WHEN le.is_over_65 = 1 AND le.mql_date IS NOT NULL AND DATE_DIFF(le.mql_date, le.contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            SUM(CASE WHEN le.is_over_65 = 1 THEN 1 ELSE 0 END)
        ) - SAFE_DIVIDE(
            SUM(CASE WHEN le.is_over_65 = 0 AND le.mql_date IS NOT NULL AND DATE_DIFF(le.mql_date, le.contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
            SUM(CASE WHEN le.is_over_65 = 0 THEN 1 ELSE 0 END)
        ), 4
    ) * 100 as rate_diff_pct_points
    
FROM lead_enriched le
LEFT JOIN tier_data t 
    ON le.crd = t.crd 
    AND ABS(DATE_DIFF(t.contacted_date, le.contacted_date, DAY)) <= 7
GROUP BY t.score_tier
HAVING SUM(CASE WHEN le.is_over_65 = 1 THEN 1 ELSE 0 END) >= 10  -- Need at least 10 in each group
ORDER BY t.score_tier;
```

---

## Phase 3: V4 Model Age Analysis

### Query 3.1: Age Distribution by V4 Score Percentile

**Purpose**: Determine if V4 model implicitly captures age signal

```sql
-- Query 3.1: V4 Score Distribution by Age
-- Check if V4 already captures age signal implicitly

WITH lead_v4 AS (
    SELECT 
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        c.AGE_RANGE,
        CASE 
            WHEN c.AGE_RANGE IN ('18-24', '25-29', '30-34', '35-39', '40-44', '45-49') THEN 'UNDER_50'
            WHEN c.AGE_RANGE IN ('50-54', '55-59', '60-64') THEN 'AGE_50_64'
            WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 'AGE_65_PLUS'
            ELSE 'UNKNOWN'
        END as age_bucket
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
)

SELECT 
    lv4.age_bucket,
    ROUND(AVG(v4.v4_percentile), 2) as avg_v4_percentile,
    ROUND(STDDEV(v4.v4_percentile), 2) as stddev_v4_percentile,
    COUNT(*) as sample_size,
    -- Conversion by age
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN lv4.mql_date IS NOT NULL AND DATE_DIFF(lv4.mql_date, lv4.contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        COUNT(*)
    ) * 100, 2) as actual_conv_rate
FROM lead_v4 lv4
LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 
    ON lv4.crd = v4.crd
WHERE v4.v4_percentile IS NOT NULL
  AND lv4.age_bucket != 'UNKNOWN'
GROUP BY lv4.age_bucket
ORDER BY lv4.age_bucket;
```

---

### Query 3.2: V4 Top Decile Performance by Age

**Purpose**: Does V4 top decile performance vary by age?

```sql
-- Query 3.2: V4 Top Decile Lift by Age
-- Critical for understanding if age modifies V4 effectiveness

WITH lead_v4_decile AS (
    SELECT 
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        c.AGE_RANGE,
        CASE 
            WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 'OVER_65'
            WHEN c.AGE_RANGE IS NULL THEN 'UNKNOWN'
            ELSE 'UNDER_65'
        END as age_category,
        v4.v4_percentile,
        NTILE(10) OVER (ORDER BY v4.v4_score DESC) as v4_decile
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = v4.crd
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
      AND v4.v4_score IS NOT NULL
)

SELECT 
    age_category,
    v4_decile,
    COUNT(*) as contacted,
    SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END) as converted,
    ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END),
        COUNT(*)
    ) * 100, 2) as conv_rate_pct
FROM lead_v4_decile
WHERE age_category IN ('OVER_65', 'UNDER_65')
GROUP BY age_category, v4_decile
HAVING COUNT(*) >= 10
ORDER BY age_category, v4_decile;
```

---

## Phase 4: Optimal Age Cutoff Analysis

### Query 4.1: Cumulative Conversion by Age Threshold

**Purpose**: Find the optimal age cutoff for exclusion

```sql
-- Query 4.1: Optimal Age Cutoff Analysis
-- Tests different age thresholds to find optimal exclusion point

WITH age_ordered AS (
    SELECT 
        l.Id as lead_id,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        c.AGE_RANGE,
        CASE 
            WHEN c.AGE_RANGE = '18-24' THEN 1
            WHEN c.AGE_RANGE = '25-29' THEN 2
            WHEN c.AGE_RANGE = '30-34' THEN 3
            WHEN c.AGE_RANGE = '35-39' THEN 4
            WHEN c.AGE_RANGE = '40-44' THEN 5
            WHEN c.AGE_RANGE = '45-49' THEN 6
            WHEN c.AGE_RANGE = '50-54' THEN 7
            WHEN c.AGE_RANGE = '55-59' THEN 8
            WHEN c.AGE_RANGE = '60-64' THEN 9
            WHEN c.AGE_RANGE = '65-69' THEN 10
            WHEN c.AGE_RANGE = '70-74' THEN 11
            WHEN c.AGE_RANGE = '75-79' THEN 12
            WHEN c.AGE_RANGE IN ('80-84', '85-89', '90-94', '95-99') THEN 13
            ELSE NULL
        END as age_order,
        CASE WHEN mql_date IS NOT NULL AND DATE_DIFF(mql_date, contacted_date, DAY) <= 43 THEN 1 ELSE 0 END as converted
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.IsDeleted = false
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 43
      AND c.AGE_RANGE IS NOT NULL
),

cutoff_analysis AS (
    SELECT 
        cutoff.threshold_age,
        cutoff.threshold_name,
        SUM(CASE WHEN ao.age_order <= cutoff.threshold_age THEN 1 ELSE 0 END) as included_contacts,
        SUM(CASE WHEN ao.age_order <= cutoff.threshold_age AND ao.converted = 1 THEN 1 ELSE 0 END) as included_converts,
        SUM(CASE WHEN ao.age_order > cutoff.threshold_age THEN 1 ELSE 0 END) as excluded_contacts,
        SUM(CASE WHEN ao.age_order > cutoff.threshold_age AND ao.converted = 1 THEN 1 ELSE 0 END) as excluded_converts
    FROM age_ordered ao
    CROSS JOIN (
        SELECT 6 as threshold_age, 'Under 50' as threshold_name UNION ALL
        SELECT 7, 'Under 55' UNION ALL
        SELECT 8, 'Under 60' UNION ALL
        SELECT 9, 'Under 65 (CURRENT)' UNION ALL
        SELECT 10, 'Under 70' UNION ALL
        SELECT 11, 'Under 75' UNION ALL
        SELECT 12, 'Under 80' UNION ALL
        SELECT 13, 'All Ages (No Exclusion)'
    ) cutoff
    GROUP BY cutoff.threshold_age, cutoff.threshold_name
)

SELECT 
    threshold_name,
    included_contacts,
    included_converts,
    ROUND(SAFE_DIVIDE(included_converts, included_contacts) * 100, 2) as included_conv_rate,
    excluded_contacts,
    excluded_converts,
    ROUND(SAFE_DIVIDE(excluded_converts, excluded_contacts) * 100, 2) as excluded_conv_rate,
    -- Lost conversions by excluding
    excluded_converts as lost_conversions,
    -- Efficiency: included conv rate vs baseline
    ROUND(SAFE_DIVIDE(
        SAFE_DIVIDE(included_converts, included_contacts),
        SAFE_DIVIDE(included_converts + excluded_converts, included_contacts + excluded_contacts)
    ), 3) as efficiency_vs_baseline
FROM cutoff_analysis
ORDER BY threshold_age;
```

---

## Phase 5: Age as V4 Feature Candidate

### Query 5.1: Age Correlation with Existing V4 Features

**Purpose**: Check if age is redundant with existing features (especially experience_years)

```sql
-- Query 5.1: Age vs Experience Years Correlation
-- Check if age is redundant with industry_tenure/experience

WITH feature_comparison AS (
    SELECT 
        c.AGE_RANGE,
        CASE 
            WHEN c.AGE_RANGE = '18-24' THEN 21
            WHEN c.AGE_RANGE = '25-29' THEN 27
            WHEN c.AGE_RANGE = '30-34' THEN 32
            WHEN c.AGE_RANGE = '35-39' THEN 37
            WHEN c.AGE_RANGE = '40-44' THEN 42
            WHEN c.AGE_RANGE = '45-49' THEN 47
            WHEN c.AGE_RANGE = '50-54' THEN 52
            WHEN c.AGE_RANGE = '55-59' THEN 57
            WHEN c.AGE_RANGE = '60-64' THEN 62
            WHEN c.AGE_RANGE = '65-69' THEN 67
            WHEN c.AGE_RANGE = '70-74' THEN 72
            WHEN c.AGE_RANGE = '75-79' THEN 77
            WHEN c.AGE_RANGE IN ('80-84', '85-89', '90-94', '95-99') THEN 82
            ELSE NULL
        END as approx_age,
        f.experience_years,
        f.tenure_months / 12.0 as tenure_years,
        f.mobility_3yr,
        f.num_prior_firms
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON f.advisor_crd = c.RIA_CONTACT_CRD_ID
    WHERE c.AGE_RANGE IS NOT NULL
)

SELECT 
    'Age vs Experience Years' as correlation_pair,
    ROUND(CORR(approx_age, experience_years), 3) as correlation
FROM feature_comparison
WHERE approx_age IS NOT NULL AND experience_years IS NOT NULL

UNION ALL

SELECT 
    'Age vs Tenure Years',
    ROUND(CORR(approx_age, tenure_years), 3)
FROM feature_comparison
WHERE approx_age IS NOT NULL AND tenure_years IS NOT NULL

UNION ALL

SELECT 
    'Age vs Mobility 3yr',
    ROUND(CORR(approx_age, mobility_3yr), 3)
FROM feature_comparison
WHERE approx_age IS NOT NULL AND mobility_3yr IS NOT NULL

UNION ALL

SELECT 
    'Age vs Num Prior Firms',
    ROUND(CORR(approx_age, num_prior_firms), 3)
FROM feature_comparison
WHERE approx_age IS NOT NULL AND num_prior_firms IS NOT NULL;
```

---

## Results Documentation Instructions

After running all queries, create `age_analysis_results.md` in the root directory with the following structure:

```markdown
# Age Bucket Analysis Results

**Analysis Date**: [DATE]
**Executed By**: Cursor.ai Agentic Analysis
**BigQuery Project**: savvy-gtm-analytics

---

## Executive Summary

### Key Findings
1. [Finding 1 from Query 1.1]
2. [Finding 2 from Query 1.2]
3. [etc.]

### Recommendations
- [ ] Recommendation 1
- [ ] Recommendation 2

---

## Detailed Results

### Phase 1: Age Distribution

#### Query 1.1 Results
[Paste table here]

#### Query 1.2 Results
[Paste table here]

### Phase 2: Age × V3 Tier Interaction

#### Query 2.1 Results
[Paste table here]

#### Query 2.2 Results
[Paste table here]

[Continue for all phases...]

---

## Statistical Conclusions

### Is Age a Significant Signal?
[Answer based on Query 2.2 results]

### Recommended Age Cutoff
[Answer based on Query 4.1 results]

### Should Age Be Added to V4?
[Answer based on Query 5.1 - if correlation with experience_years > 0.8, age is redundant]

---

## Recommended Actions

### For V3 Tier Logic
1. [Specific recommendation]
2. [Specific recommendation]

### For V4 Model
1. [Specific recommendation]
2. [Specific recommendation]

### For Age Exclusion Threshold
1. [Specific recommendation based on optimal cutoff analysis]
```

---

## Success Criteria

The analysis is considered successful if:

1. **Sample Size**: At least 500 leads in each major age bucket
2. **Statistical Validity**: 95% CI widths < 5% for major age groups
3. **Clear Signal**: Conversion rate difference > 1 percentage point between age groups
4. **Actionable Recommendations**: Clear yes/no on:
   - Should age be a V3 tier modifier?
   - Should age be a V4 feature?
   - What is the optimal age exclusion cutoff?

---

## Appendix: AGE_RANGE Coverage Check

Run this query first to verify data quality:

```sql
-- AGE_RANGE Coverage Check
SELECT 
    COUNT(*) as total_contacts,
    COUNT(AGE_RANGE) as has_age_range,
    ROUND(COUNT(AGE_RANGE) * 100.0 / COUNT(*), 2) as coverage_pct
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`;
```

If coverage < 70%, results may not be representative.
