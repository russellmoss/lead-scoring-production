# January 2026 Lead List Retrospective Analysis
**Run Date:** January 23, 2026  
**Purpose:** Validate January performance and optimize February lead list generation  
**Output File:** `january_retro.md`

---

## Overview

This analysis evaluates the January 2026 lead list performance to inform February lead list generation decisions. We'll analyze:

1. **Overall January Performance** - Contact rates, MQL rates by tier
2. **Tier Validation** - Which tiers are converting Contact → MQL?
3. **Tenure Analysis** - Are 1-year tenure advisors actually converting?
4. **SGA Performance** - Are leads being worked properly?
5. **V4 Score Validation** - Does V4 score correlate with MQL conversion?
6. **February Recommendations** - Volume, tier mix, criteria adjustments

**Important Note:** As of January 23rd, we have ~20 days of data. MQL conversion typically takes 15-30 days, so we're seeing early signals only. We'll use Contact → MQL rate as our primary metric.

---

## Pre-Requisites

Before running this analysis, ensure:
- January leads have been uploaded to Salesforce
- SGAs have been working the leads for at least 2 weeks
- You have access to BigQuery MCP connection

---

## Step 1: Load January Lead List Baseline

### Prompt 1.1: Get January Lead List Summary from Our Source Data

```
Using BigQuery MCP, run this query to get the January lead list baseline from our generated list:

[Run the SQL below]

This establishes our baseline - how many leads we gave each SGA by tier.
Save the results for comparison with Salesforce data.
```

```sql
-- Query 1.1: January Lead List Baseline (from our generated list)
-- This shows what we GAVE to SGAs
SELECT 
    score_tier,
    COUNT(*) as leads_provided,
    COUNT(DISTINCT sga_owner) as sgas_assigned,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_rate_pct,
    ROUND(AVG(tenure_years), 1) as avg_tenure_years,
    SUM(CASE WHEN tenure_years <= 1 THEN 1 ELSE 0 END) as leads_1yr_or_less,
    SUM(CASE WHEN tenure_years > 1 AND tenure_years <= 3 THEN 1 ELSE 0 END) as leads_1_to_3yr,
    SUM(CASE WHEN tenure_years > 3 THEN 1 ELSE 0 END) as leads_over_3yr,
    ROUND(AVG(v4_percentile), 1) as avg_v4_percentile
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY score_tier
ORDER BY 
    CASE 
        WHEN score_tier LIKE 'TIER_1%' THEN 1
        WHEN score_tier LIKE 'TIER_2%' THEN 2
        WHEN score_tier LIKE 'TIER_3%' THEN 3
        WHEN score_tier LIKE 'TIER_4%' THEN 4
        ELSE 5
    END,
    score_tier;
```

**Expected Output:**
- Tier distribution showing how many leads per tier
- Tenure breakdown per tier
- V4 percentile distribution

---

### Prompt 1.2: Get January Lead List by SGA

```
Run this query to see how leads were distributed across SGAs:

[Run the SQL below]

This shows lead distribution per SGA. We want roughly equal distribution.
```

```sql
-- Query 1.2: January Leads by SGA
SELECT 
    sga_owner,
    COUNT(*) as total_leads,
    SUM(CASE WHEN score_tier LIKE 'TIER_1%' THEN 1 ELSE 0 END) as tier_1_leads,
    SUM(CASE WHEN score_tier LIKE 'TIER_2%' THEN 1 ELSE 0 END) as tier_2_leads,
    SUM(CASE WHEN score_tier IN ('TIER_3_EXPERIENCED_MOVER', 'TIER_4_HEAVY_BLEEDER') THEN 1 ELSE 0 END) as tier_3_4_leads,
    SUM(CASE WHEN score_tier = 'STANDARD_HIGH_V4' THEN 1 ELSE 0 END) as high_v4_leads,
    SUM(CASE WHEN score_tier = 'STANDARD' THEN 1 ELSE 0 END) as standard_leads,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_rate
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY sga_owner
ORDER BY total_leads DESC;
```

---

## Step 2: Match January Leads to Salesforce Activity

### Prompt 2.1: Find January Leads in Salesforce

```
Run this query to match our January lead list to Salesforce leads and see their current status:

[Run the SQL below]

This is the CRITICAL query - it shows us what actually happened to the leads we provided.
```

```sql
-- Query 2.1: January Leads Matched to Salesforce
-- Matches by CRD to see current status
WITH january_leads AS (
    SELECT 
        advisor_crd,
        first_name,
        last_name,
        score_tier,
        expected_conversion_rate,
        tenure_years,
        v4_percentile,
        sga_owner as assigned_sga
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
),
salesforce_leads AS (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id,
        Status,
        Disposition__c,
        Stage_Entered_Contacting__c,
        Stage_Entered_Call_Scheduled__c,
        IsConverted,
        Owner.Name as current_owner,
        CreatedDate,
        LastActivityDate
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.User` u ON l.OwnerId = u.Id
    WHERE l.IsDeleted = false
      AND l.CreatedDate >= '2026-01-01'
)
SELECT 
    jl.score_tier,
    COUNT(DISTINCT jl.advisor_crd) as leads_provided,
    COUNT(DISTINCT CASE WHEN sl.lead_id IS NOT NULL THEN jl.advisor_crd END) as found_in_sf,
    COUNT(DISTINCT CASE WHEN sl.Stage_Entered_Contacting__c IS NOT NULL THEN jl.advisor_crd END) as contacted,
    COUNT(DISTINCT CASE WHEN sl.Stage_Entered_Call_Scheduled__c IS NOT NULL THEN jl.advisor_crd END) as mql,
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sl.Stage_Entered_Contacting__c IS NOT NULL THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sl.lead_id IS NOT NULL THEN jl.advisor_crd END)
    ) * 100, 2) as contact_rate_pct,
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sl.Stage_Entered_Call_Scheduled__c IS NOT NULL THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sl.Stage_Entered_Contacting__c IS NOT NULL THEN jl.advisor_crd END)
    ) * 100, 2) as contact_to_mql_rate_pct,
    ROUND(AVG(jl.expected_conversion_rate) * 100, 2) as expected_rate_pct
FROM january_leads jl
LEFT JOIN salesforce_leads sl ON jl.advisor_crd = sl.crd
GROUP BY jl.score_tier
ORDER BY 
    CASE 
        WHEN jl.score_tier LIKE 'TIER_1%' THEN 1
        WHEN jl.score_tier LIKE 'TIER_2%' THEN 2
        WHEN jl.score_tier LIKE 'TIER_3%' THEN 3
        WHEN jl.score_tier LIKE 'TIER_4%' THEN 4
        ELSE 5
    END,
    jl.score_tier;
```

**Key Metrics to Evaluate:**
- `found_in_sf`: Were leads uploaded to Salesforce?
- `contacted`: Were leads actually contacted?
- `contact_to_mql_rate_pct`: **PRIMARY METRIC** - Are leads converting to MQLs?

---

### Prompt 2.2: Detailed Tier Performance with Funnel

```
Run this query for a detailed funnel view by tier:

[Run the SQL below]

This shows the full funnel: Provided → Uploaded → Contacted → MQL
```

```sql
-- Query 2.2: Detailed Tier Funnel Performance
WITH january_leads AS (
    SELECT 
        advisor_crd,
        score_tier,
        expected_conversion_rate,
        tenure_years,
        tenure_months,
        v4_percentile,
        sga_owner as assigned_sga
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
),
sf_status AS (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id,
        Status,
        Disposition__c,
        CASE WHEN Stage_Entered_Contacting__c IS NOT NULL THEN 1 ELSE 0 END as is_contacted,
        CASE WHEN Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END as is_mql,
        CASE WHEN IsConverted = true THEN 1 ELSE 0 END as is_converted,
        Owner.Name as owner_name
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.User` u ON l.OwnerId = u.Id
    WHERE l.IsDeleted = false
      AND l.CreatedDate >= '2026-01-01'
)
SELECT 
    jl.score_tier,
    
    -- Volume
    COUNT(DISTINCT jl.advisor_crd) as provided,
    COUNT(DISTINCT CASE WHEN sf.lead_id IS NOT NULL THEN jl.advisor_crd END) as in_salesforce,
    COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END) as contacted,
    COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END) as mql,
    
    -- Rates
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sf.lead_id IS NOT NULL THEN jl.advisor_crd END),
        COUNT(DISTINCT jl.advisor_crd)
    ) * 100, 1) as upload_rate_pct,
    
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sf.lead_id IS NOT NULL THEN jl.advisor_crd END)
    ) * 100, 1) as contact_rate_pct,
    
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END)
    ) * 100, 2) as contacted_to_mql_pct,
    
    -- Expected vs Actual
    ROUND(AVG(jl.expected_conversion_rate) * 100, 2) as expected_conv_pct,
    
    -- Performance Ratio (Actual MQL Rate / Expected Rate)
    ROUND(SAFE_DIVIDE(
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END),
            COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END)
        ),
        AVG(jl.expected_conversion_rate)
    ), 2) as performance_ratio

FROM january_leads jl
LEFT JOIN sf_status sf ON jl.advisor_crd = sf.crd
GROUP BY jl.score_tier
ORDER BY 
    CASE 
        WHEN jl.score_tier LIKE 'TIER_1%' THEN 1
        WHEN jl.score_tier LIKE 'TIER_2%' THEN 2
        WHEN jl.score_tier LIKE 'TIER_3%' THEN 3
        WHEN jl.score_tier LIKE 'TIER_4%' THEN 4
        ELSE 5
    END;
```

**Key Columns:**
- `performance_ratio`: >1.0 means tier is outperforming expected, <1.0 means underperforming
- `contacted_to_mql_pct`: The primary conversion metric we can measure in 20 days

---

## Step 3: Tenure Analysis (1-Year at Current Firm)

### Prompt 3.1: Tenure Cohort Performance

```
Run this query to analyze whether advisors with only 1 year at current firm are converting:

[Run the SQL below]

This is a KEY QUESTION - we're concerned that 1-year tenure advisors might be too new/unstable.
```

```sql
-- Query 3.1: Tenure Cohort Analysis
-- Key Question: Are 1-year tenure advisors actually converting?
WITH january_leads AS (
    SELECT 
        advisor_crd,
        score_tier,
        expected_conversion_rate,
        tenure_years,
        tenure_months,
        v4_percentile,
        CASE 
            WHEN tenure_years < 1 THEN '0: Under 1 Year'
            WHEN tenure_years = 1 THEN '1: Exactly 1 Year'
            WHEN tenure_years = 2 THEN '2: 2 Years'
            WHEN tenure_years = 3 THEN '3: 3 Years'
            WHEN tenure_years <= 5 THEN '4: 4-5 Years'
            ELSE '5: 6+ Years'
        END as tenure_cohort
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
),
sf_status AS (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id,
        CASE WHEN Stage_Entered_Contacting__c IS NOT NULL THEN 1 ELSE 0 END as is_contacted,
        CASE WHEN Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END as is_mql
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE IsDeleted = false
      AND CreatedDate >= '2026-01-01'
)
SELECT 
    jl.tenure_cohort,
    
    -- Volume
    COUNT(DISTINCT jl.advisor_crd) as leads_provided,
    COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END) as contacted,
    COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END) as mql,
    
    -- Rates
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sf.lead_id IS NOT NULL THEN jl.advisor_crd END)
    ) * 100, 1) as contact_rate_pct,
    
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END)
    ) * 100, 2) as contacted_to_mql_pct,
    
    -- Expected
    ROUND(AVG(jl.expected_conversion_rate) * 100, 2) as avg_expected_rate_pct,
    
    -- V4 Score
    ROUND(AVG(jl.v4_percentile), 1) as avg_v4_percentile

FROM january_leads jl
LEFT JOIN sf_status sf ON jl.advisor_crd = sf.crd
GROUP BY jl.tenure_cohort
ORDER BY jl.tenure_cohort;
```

**Key Question:** Is the `contacted_to_mql_pct` for "1: Exactly 1 Year" significantly lower than other cohorts?

---

### Prompt 3.2: Tenure Analysis by Tier

```
Run this query to see if 1-year tenure affects specific tiers differently:

[Run the SQL below]

This helps us understand if we should adjust tenure requirements for certain tiers.
```

```sql
-- Query 3.2: Tenure Analysis by Tier
WITH january_leads AS (
    SELECT 
        advisor_crd,
        score_tier,
        expected_conversion_rate,
        tenure_years,
        CASE WHEN tenure_years <= 1 THEN '1yr_or_less' ELSE 'over_1yr' END as tenure_group
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
),
sf_status AS (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        CASE WHEN Stage_Entered_Contacting__c IS NOT NULL THEN 1 ELSE 0 END as is_contacted,
        CASE WHEN Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END as is_mql
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE IsDeleted = false AND CreatedDate >= '2026-01-01'
)
SELECT 
    jl.score_tier,
    jl.tenure_group,
    
    COUNT(DISTINCT jl.advisor_crd) as leads,
    COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END) as contacted,
    COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END) as mql,
    
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END)
    ) * 100, 2) as contacted_to_mql_pct

FROM january_leads jl
LEFT JOIN sf_status sf ON jl.advisor_crd = sf.crd
WHERE jl.score_tier LIKE 'TIER_1%' OR jl.score_tier LIKE 'TIER_2%'
GROUP BY jl.score_tier, jl.tenure_group
ORDER BY jl.score_tier, jl.tenure_group;
```

**Decision Point:** If `1yr_or_less` has significantly lower MQL rates for Tier 1, we may want to increase minimum tenure for February.

---

## Step 4: SGA Performance Analysis

### Prompt 4.1: SGA Contact and MQL Rates

```
Run this query to see how each SGA is performing with January leads:

[Run the SQL below]

This identifies SGAs who may need support or who are top performers.
```

```sql
-- Query 4.1: SGA Performance on January Leads
WITH january_leads AS (
    SELECT 
        advisor_crd,
        score_tier,
        expected_conversion_rate,
        sga_owner as assigned_sga
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
),
sf_status AS (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id,
        Owner.Name as current_owner,
        CASE WHEN Stage_Entered_Contacting__c IS NOT NULL THEN 1 ELSE 0 END as is_contacted,
        CASE WHEN Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END as is_mql
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.User` u ON l.OwnerId = u.Id
    WHERE l.IsDeleted = false AND l.CreatedDate >= '2026-01-01'
)
SELECT 
    jl.assigned_sga,
    
    -- Volume
    COUNT(DISTINCT jl.advisor_crd) as leads_assigned,
    COUNT(DISTINCT CASE WHEN sf.lead_id IS NOT NULL THEN jl.advisor_crd END) as in_salesforce,
    COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END) as contacted,
    COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END) as mql,
    
    -- Tier 1 specific
    COUNT(DISTINCT CASE WHEN jl.score_tier LIKE 'TIER_1%' AND sf.is_contacted = 1 THEN jl.advisor_crd END) as tier1_contacted,
    COUNT(DISTINCT CASE WHEN jl.score_tier LIKE 'TIER_1%' AND sf.is_mql = 1 THEN jl.advisor_crd END) as tier1_mql,
    
    -- Rates
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sf.lead_id IS NOT NULL THEN jl.advisor_crd END)
    ) * 100, 1) as contact_rate_pct,
    
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END)
    ) * 100, 2) as contacted_to_mql_pct,
    
    -- Owner Match (are leads still with assigned SGA?)
    COUNT(DISTINCT CASE WHEN sf.current_owner = jl.assigned_sga THEN jl.advisor_crd END) as still_with_assigned_sga

FROM january_leads jl
LEFT JOIN sf_status sf ON jl.advisor_crd = sf.crd
GROUP BY jl.assigned_sga
ORDER BY contacted DESC;
```

**Watch For:**
- Low `contact_rate_pct`: SGA not working their leads
- Low `tier1_contacted`: SGA not prioritizing Tier 1
- Low `still_with_assigned_sga`: Leads being reassigned (could indicate issue)

---

### Prompt 4.2: Check for Assignment Issues (T1B_PRIME Problem)

```
Run this query to check if any Tier 1 leads were assigned to non-SGAs:

[Run the SQL below]

This catches the T1B_PRIME issue we found earlier where leads went to "Savvy Operations".
```

```sql
-- Query 4.2: Tier 1 Assignment Audit
WITH january_tier1 AS (
    SELECT 
        advisor_crd,
        score_tier,
        sga_owner as assigned_sga
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
    WHERE score_tier LIKE 'TIER_1%'
),
sf_leads AS (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id,
        Owner.Name as current_owner,
        Status,
        Disposition__c,
        Stage_Entered_Contacting__c,
        Stage_Entered_Call_Scheduled__c
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.User` u ON l.OwnerId = u.Id
    WHERE l.IsDeleted = false AND l.CreatedDate >= '2026-01-01'
)
SELECT 
    sf.current_owner,
    COUNT(DISTINCT jl.advisor_crd) as tier1_leads,
    COUNT(DISTINCT CASE WHEN sf.Stage_Entered_Contacting__c IS NOT NULL THEN jl.advisor_crd END) as contacted,
    COUNT(DISTINCT CASE WHEN sf.Stage_Entered_Call_Scheduled__c IS NOT NULL THEN jl.advisor_crd END) as mql,
    STRING_AGG(DISTINCT sf.Status, ', ') as statuses,
    STRING_AGG(DISTINCT sf.Disposition__c, ', ') as dispositions,
    
    -- Flag problematic owners
    CASE 
        WHEN sf.current_owner IN ('Savvy Operations', 'Savvy Marketing', 'Jacqueline Tully', 'GinaRose') 
        THEN '🔴 NON-SGA OWNER'
        ELSE '✅ Active SGA'
    END as owner_status

FROM january_tier1 jl
LEFT JOIN sf_leads sf ON jl.advisor_crd = sf.crd
WHERE sf.lead_id IS NOT NULL
GROUP BY sf.current_owner
ORDER BY tier1_leads DESC;
```

**Critical Check:** Any `🔴 NON-SGA OWNER` rows indicate Tier 1 leads that were misassigned and likely won't convert.

---

## Step 5: V4 Score Validation

### Prompt 5.1: V4 Percentile vs MQL Conversion

```
Run this query to validate if V4 score predicts MQL conversion:

[Run the SQL below]

This helps us decide if we should weight V4 more heavily in February.
```

```sql
-- Query 5.1: V4 Percentile vs MQL Conversion
WITH january_leads AS (
    SELECT 
        advisor_crd,
        score_tier,
        v4_percentile,
        CASE 
            WHEN v4_percentile >= 95 THEN '95-100 (Top 5%)'
            WHEN v4_percentile >= 90 THEN '90-94'
            WHEN v4_percentile >= 80 THEN '80-89'
            WHEN v4_percentile >= 70 THEN '70-79'
            WHEN v4_percentile >= 60 THEN '60-69'
            ELSE 'Under 60'
        END as v4_bucket
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
),
sf_status AS (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        CASE WHEN Stage_Entered_Contacting__c IS NOT NULL THEN 1 ELSE 0 END as is_contacted,
        CASE WHEN Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END as is_mql
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE IsDeleted = false AND CreatedDate >= '2026-01-01'
)
SELECT 
    jl.v4_bucket,
    
    COUNT(DISTINCT jl.advisor_crd) as leads,
    COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END) as contacted,
    COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END) as mql,
    
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END)
    ) * 100, 2) as contacted_to_mql_pct

FROM january_leads jl
LEFT JOIN sf_status sf ON jl.advisor_crd = sf.crd
GROUP BY jl.v4_bucket
ORDER BY 
    CASE jl.v4_bucket
        WHEN '95-100 (Top 5%)' THEN 1
        WHEN '90-94' THEN 2
        WHEN '80-89' THEN 3
        WHEN '70-79' THEN 4
        WHEN '60-69' THEN 5
        ELSE 6
    END;
```

**Expected Result:** Higher V4 buckets should have higher `contacted_to_mql_pct`. If not, V4 may need recalibration.

---

### Prompt 5.2: V4 vs V3 Tier Agreement Analysis

```
Run this query to see if V4 high-scorers within Standard tier outperform regular Standard:

[Run the SQL below]

This validates our STANDARD_HIGH_V4 tier backfill strategy.
```

```sql
-- Query 5.2: Standard vs Standard_High_V4 Performance
WITH january_leads AS (
    SELECT 
        advisor_crd,
        score_tier,
        original_v3_tier,
        v4_percentile,
        is_high_v4_standard
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
    WHERE score_tier IN ('STANDARD', 'STANDARD_HIGH_V4')
),
sf_status AS (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        CASE WHEN Stage_Entered_Contacting__c IS NOT NULL THEN 1 ELSE 0 END as is_contacted,
        CASE WHEN Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END as is_mql
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE IsDeleted = false AND CreatedDate >= '2026-01-01'
)
SELECT 
    jl.score_tier,
    
    COUNT(DISTINCT jl.advisor_crd) as leads,
    COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END) as contacted,
    COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END) as mql,
    
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN sf.is_mql = 1 THEN jl.advisor_crd END),
        COUNT(DISTINCT CASE WHEN sf.is_contacted = 1 THEN jl.advisor_crd END)
    ) * 100, 2) as contacted_to_mql_pct,
    
    ROUND(AVG(jl.v4_percentile), 1) as avg_v4_percentile

FROM january_leads jl
LEFT JOIN sf_status sf ON jl.advisor_crd = sf.crd
GROUP BY jl.score_tier
ORDER BY jl.score_tier;
```

**Expected Result:** `STANDARD_HIGH_V4` should have higher `contacted_to_mql_pct` than regular `STANDARD`.

---

## Step 6: Generate January Retrospective Report

### Prompt 6.1: Create Summary Report

```
Now compile all the results into a markdown report. Create a file called january_retro.md with:

1. Executive Summary
   - Total leads provided vs contacted vs MQL'd
   - Overall Contact-to-MQL rate
   - Performance vs expected

2. Tier Performance Table
   - Each tier's Contact-to-MQL rate
   - Performance ratio (actual vs expected)
   - Recommendation (Keep, Adjust, Investigate)

3. Tenure Analysis
   - 1-year tenure performance
   - Recommendation on tenure thresholds

4. SGA Performance
   - Top performers
   - Underperformers needing support
   - Assignment issues found

5. V4 Validation
   - Does V4 score predict MQL?
   - Standard_High_V4 vs Standard comparison

6. February Recommendations
   - Volume per SGA
   - Tier mix adjustments
   - Tenure threshold changes
   - Any tier criteria changes

Use this template:
```

```markdown
# January 2026 Lead List Retrospective
**Analysis Date:** January 23, 2026  
**Data Period:** January 1-23, 2026 (20 days of activity)

---

## Executive Summary

| Metric | Value | Notes |
|--------|-------|-------|
| **Leads Provided** | [X] | From January lead list |
| **Leads in Salesforce** | [X] | Successfully uploaded |
| **Leads Contacted** | [X] | Entered Contacting stage |
| **Leads MQL'd** | [X] | Scheduled a call |
| **Contact Rate** | [X]% | In SF → Contacted |
| **Contact-to-MQL Rate** | [X]% | **Primary Metric** |

### Key Findings
1. [Finding 1]
2. [Finding 2]
3. [Finding 3]

---

## Tier Performance

| Tier | Provided | Contacted | MQL | Contact-to-MQL % | Expected % | Status |
|------|----------|-----------|-----|------------------|------------|--------|
| TIER_1A_PRIME_MOVER_CFP | | | | | 10.0% | |
| TIER_1B_PRIME_MOVER_SERIES65 | | | | | 11.76% | |
| TIER_1B_PRIME_ZERO_FRICTION | | | | | 13.64% | |
| TIER_1_PRIME_MOVER | | | | | 4.76% | |
| ... | | | | | | |

### Tier Recommendations
- **Keep:** [Tiers performing at or above expected]
- **Investigate:** [Tiers significantly underperforming]
- **Adjust:** [Tiers needing criteria changes]

---

## Tenure Analysis

| Tenure Cohort | Leads | Contacted | MQL | Contact-to-MQL % |
|---------------|-------|-----------|-----|------------------|
| Under 1 Year | | | | |
| Exactly 1 Year | | | | |
| 2 Years | | | | |
| 3 Years | | | | |
| 4-5 Years | | | | |
| 6+ Years | | | | |

### Tenure Finding
[Are 1-year tenure advisors converting? Should we adjust minimum tenure?]

---

## SGA Performance

### Top Performers (by Contact-to-MQL Rate)
| SGA | Leads | Contacted | MQL | MQL Rate |
|-----|-------|-----------|-----|----------|
| | | | | |

### Needs Support (Low Contact Rate or MQL Rate)
| SGA | Leads | Contacted | MQL | Issue |
|-----|-------|-----------|-----|-------|
| | | | | |

### Assignment Issues
[Any Tier 1 leads assigned to non-SGAs?]

---

## V4 Score Validation

| V4 Percentile | Leads | MQL | MQL Rate |
|---------------|-------|-----|----------|
| 95-100 | | | |
| 90-94 | | | |
| 80-89 | | | |
| 70-79 | | | |
| 60-69 | | | |
| Under 60 | | | |

### V4 Finding
[Does higher V4 = higher MQL rate? Is STANDARD_HIGH_V4 outperforming STANDARD?]

---

## February Lead List Recommendations

### 1. Volume Recommendation
| Current | Recommended | Rationale |
|---------|-------------|-----------|
| 200 leads/SGA | [X] leads/SGA | [Why] |

### 2. Tier Mix Adjustments
| Tier | Jan Volume | Feb Volume | Change | Rationale |
|------|------------|------------|--------|-----------|
| Tier 1 | | | | |
| Tier 2 | | | | |
| Tier 3-4 | | | | |
| Standard High-V4 | | | | |
| Standard | | | | |

### 3. Criteria Adjustments
- [ ] **Tenure Minimum:** Change from [X] to [Y] years because [reason]
- [ ] **V4 Threshold:** Change from [X] to [Y] percentile because [reason]
- [ ] **[Other adjustment]:** [Details]

### 4. Process Improvements
- [ ] [Improvement 1]
- [ ] [Improvement 2]

---

## SQL Changes for February

Based on this analysis, update `January_2026_Lead_List_V3_V4_Hybrid.sql` with:

```sql
-- Change 1: [Description]
-- Line [X]: Change FROM [old] TO [new]

-- Change 2: [Description]
-- Line [X]: Change FROM [old] TO [new]
```

---

*Report Generated: January 23, 2026*
```

---

## Step 7: Decision Framework for February

### Prompt 7.1: Apply Decision Rules

```
Based on the data collected, apply these decision rules to determine February adjustments:

TIER DECISIONS:
- If Tier Contact-to-MQL < 50% of Expected → Flag for investigation
- If Tier Contact-to-MQL > 150% of Expected → Consider increasing volume
- If Tier has 0 MQLs from 10+ contacts → Urgent investigation needed

TENURE DECISIONS:
- If 1-year tenure MQL rate < 70% of 2-3 year rate → Consider increasing minimum tenure
- If 1-year tenure MQL rate >= 2-3 year rate → Keep current tenure threshold

VOLUME DECISIONS:
- If overall Contact-to-MQL > 5% → Consider reducing volume (quality over quantity)
- If overall Contact-to-MQL < 3% → Investigate lead quality or SGA issues
- If SGAs contacted < 60% of leads → Volume may be too high

V4 DECISIONS:
- If V4 95+ percentile has 2x MQL rate of 70-79 → V4 is predictive, weight more
- If V4 buckets show no pattern → V4 may need recalibration

Document your decisions and rationale in the final report.
```

---

## Appendix: Quick Reference Queries

### A1: Quick MQL Count by Day (for tracking momentum)

```sql
SELECT 
    DATE(Stage_Entered_Call_Scheduled__c) as mql_date,
    COUNT(DISTINCT Id) as mqls
FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
WHERE CreatedDate >= '2026-01-01'
  AND Stage_Entered_Call_Scheduled__c IS NOT NULL
GROUP BY mql_date
ORDER BY mql_date;
```

### A2: Tier 1 Lead Detail (for manual review)

```sql
SELECT 
    jl.advisor_crd,
    jl.first_name,
    jl.last_name,
    jl.score_tier,
    jl.tenure_years,
    jl.sga_owner,
    sf.Status,
    sf.Disposition__c,
    sf.Stage_Entered_Contacting__c,
    sf.Stage_Entered_Call_Scheduled__c
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` jl
LEFT JOIN (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Status, Disposition__c, Stage_Entered_Contacting__c, Stage_Entered_Call_Scheduled__c
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE IsDeleted = false AND CreatedDate >= '2026-01-01'
) sf ON jl.advisor_crd = sf.crd
WHERE jl.score_tier LIKE 'TIER_1%'
ORDER BY jl.score_tier, jl.advisor_crd;
```

### A3: Compare January List Distribution vs What Was Actually Worked

```sql
SELECT 
    'Provided' as source,
    score_tier,
    COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY score_tier

UNION ALL

SELECT 
    'Contacted' as source,
    jl.score_tier,
    COUNT(DISTINCT jl.advisor_crd) as count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` jl
INNER JOIN (
    SELECT SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE IsDeleted = false AND CreatedDate >= '2026-01-01'
      AND Stage_Entered_Contacting__c IS NOT NULL
) sf ON jl.advisor_crd = sf.crd
GROUP BY jl.score_tier

ORDER BY source, score_tier;
```

---

## Checklist Before Generating February List

- [ ] Ran all Step 1-5 queries
- [ ] Created january_retro.md with findings
- [ ] Identified any tier issues (0 conversions, underperformance)
- [ ] Analyzed tenure impact (1-year advisors)
- [ ] Checked for assignment issues (leads to non-SGAs)
- [ ] Validated V4 score predictiveness
- [ ] Made volume decision (keep 200 or reduce)
- [ ] Made tier mix decision (quota adjustments)
- [ ] Made criteria decision (tenure, V4 thresholds)
- [ ] Updated SQL file with February changes
- [ ] Communicated findings to team

---

*Analysis Framework Version: 1.0*  
*Created: January 2026*  
*For use with BigQuery MCP in Cursor.ai*
