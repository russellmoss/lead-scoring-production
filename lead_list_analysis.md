# Lead List Performance Analysis Guide
**Using BigQuery MCP Connection**

**Purpose:** Comprehensive analysis to determine optimal lead mix between Provided Lead Lists and LinkedIn Self-Sourcing

**Context (Original Hypothesis):**
- 2025 SQOs: 268 total (108 from Provided = 40%, 160 from LinkedIn = 60%)
- LinkedIn conversion: 0.92% Contact-to-SQO (hypothesized)
- Provided conversion: 0.69% Contact-to-SQO (hypothesized)

**Actual Findings (from Baseline Validation with correct SQO definition and CreatedDate):**
- 2025 SQOs: **686 total** (566 from Provided = **82.5%**, 120 from LinkedIn = **17.5%**)
- **Provided conversion: 4.13%** Contact-to-SQO ✅ (2.9x more efficient)
- **LinkedIn conversion: 1.43%** Contact-to-SQO (active SGAs, new leads only)
- Target: 150 SQOs/quarter = 600/year (achieved **114%** with 686 SQOs)

**Key Insight:** Provided leads are **2.9x more efficient** than LinkedIn, representing 82.5% of all SQOs.

---

## ⚠️ Critical Notes on Data Accuracy

### SQO Definition
- **SQO is NOT Lead.Status** - SQO is defined by `Opportunity.SQL__c = 'yes'`
- Always use `is_sqo` from `vw_funnel_lead_to_joined_v2` or join to Opportunity
- Use `sqo_primary_key` (not `primary_key`) for accurate SQO counting
- **Never use:** `l.Status = 'Qualified' OR l.Status = 'Converted'` ❌

### Recommended Views
For consistent metrics, use these existing views:
1. **`savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`**
   - Has `is_sqo` field (correctly defined as `Opportunity.SQL__c = 'yes'`)
   - Has `sqo_primary_key` for accurate SQO counting (one SQO = one opportunity)
   - Has `is_contacted`, `is_mql`, `is_sql`, `is_joined` flags
   - Has `SGA_IsActiveSGA` for filtering active SGAs
   - Has `Original_source` for filtering by lead source

2. **`savvy-gtm-analytics.savvy_analytics.vw_conversion_rates`**
   - Has pre-calculated conversion numerators/denominators
   - **Conversion rate calculation (matches Looker Studio):**
     - Contact→MQL: `SUM(contacted_to_mql_numerator) / SUM(contacted_denominator)`
     - MQL→SQL: `SUM(mql_to_sql_numerator) / SUM(mql_denominator)`
     - SQL→SQO: `SUM(sql_to_sqo_numerator) / SUM(sql_to_sqo_denominator)`
   - Has `contacted_volume`, `mql_volume`, `sql_volume`, `sqo_volume` for volume metrics
   - Aggregated by cohort month and source

### Funnel Stage Definitions

| Stage | Source Field | Definition |
|-------|-------------|------------|
| **Contacted** | `is_contacted` | `stage_entered_contacting__c IS NOT NULL` |
| **MQL** | `is_mql` | `Stage_Entered_Call_Scheduled__c IS NOT NULL` |
| **SQL** | `is_sql` | `IsConverted = TRUE` (Lead converted to Opportunity) |
| **SQO** | `is_sqo` | `Opportunity.SQL__c = 'yes'` |
| **Joined** | `is_joined` | `advisor_join_date__c IS NOT NULL` |

### Active SGA Filtering
- Use `SGA_IsActiveSGA = TRUE` from `vw_funnel_lead_to_joined_v2`
- This automatically filters for active SGAs (excludes: Jacqueline Tully, GinaRose, Savvy Marketing, Savvy Operations, Anett Davis, Anett Diaz)

### Date Field Selection
- **Use `CreatedDate`** (not `FilterDate`) for "new leads" analysis
- `CreatedDate` = When lead was first created (true 2025 leads only)
- `FilterDate` = When lead re-entered funnel (includes recycled leads from previous years)
- **All queries use `CreatedDate`** to count only new leads created in 2025, excluding recycled leads

---

## Analysis Framework

### Key Questions to Answer

1. **Time Period & Targets** - Are SQOs annual or quarterly? What was the target?
2. **LinkedIn Capacity** - How many contacts per SGA? What are the limits?
3. **Time Allocation** - % time on Provided vs LinkedIn? Time per lead type?
4. **Other Lead Sources** - Any other sources? Volumes and conversion rates?
5. **Capacity Constraints** - What's the bottleneck?
6. **Lead Quality by Source** - Do LinkedIn leads have V3/V4 scoring?
7. **2025 Breakdown** - Total provided leads? Total LinkedIn contacts? Actual conversion rates?

---

## Step 1: Understand 2025 Lead Volume & Conversion Rates

### Query 1.1: Total Provided Leads in 2025

```sql
-- Count total provided leads from lead_scores_v3 table
-- These are leads that entered "Contacting" stage in 2025
SELECT 
    '2025 Provided Leads' as metric,
    COUNT(DISTINCT lead_id) as total_leads,
    COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) as converted_leads,
    ROUND(COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) * 100.0 / COUNT(DISTINCT lead_id), 2) as conversion_rate_pct,
    COUNT(DISTINCT advisor_crd) as unique_advisors
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE EXTRACT(YEAR FROM contacted_date) = 2025
  AND contacted_date IS NOT NULL;
```

**Expected Output:**
- Total leads provided in 2025
- Conversion rate (should match ~3.82% baseline if all leads)
- Unique advisors contacted

---

### Query 1.2: Provided Leads by Tier (2025)

```sql
-- Breakdown of provided leads by tier to understand quality distribution
SELECT 
    score_tier,
    COUNT(DISTINCT lead_id) as lead_count,
    COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) as converted_count,
    ROUND(COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) * 100.0 / COUNT(DISTINCT lead_id), 2) as actual_conv_rate_pct,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_rate_pct,
    ROUND(COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) * 100.0 / COUNT(DISTINCT lead_id) / AVG(expected_conversion_rate), 2) as performance_vs_expected
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE EXTRACT(YEAR FROM contacted_date) = 2025
  AND contacted_date IS NOT NULL
GROUP BY score_tier
ORDER BY actual_conv_rate_pct DESC;
```

**Expected Output:**
- Lead count and conversion rate by tier
- Performance vs expected conversion rates
- Identifies which tiers are over/under-performing

---

### Query 1.3: Provided Leads by Quarter (2025)

```sql
-- Quarterly breakdown to understand seasonality and trends
SELECT 
    EXTRACT(QUARTER FROM contacted_date) as quarter,
    COUNT(DISTINCT lead_id) as leads_provided,
    COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) as sqos,
    ROUND(COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) * 100.0 / COUNT(DISTINCT lead_id), 2) as conversion_rate_pct,
    ROUND(COUNT(DISTINCT lead_id) / 14.0, 1) as leads_per_sga  -- 14 active SGAs
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE EXTRACT(YEAR FROM contacted_date) = 2025
  AND contacted_date IS NOT NULL
GROUP BY quarter
ORDER BY quarter;
```

**Expected Output:**
- Quarterly lead volume and SQO count
- Conversion rates by quarter
- Leads per SGA per quarter

---

## Step 2: Analyze LinkedIn Self-Sourcing Activity

### Query 2.1: LinkedIn Contacts in Salesforce (2025)

```sql
-- Count LinkedIn-sourced leads using correct SQO definition
-- Uses vw_funnel_lead_to_joined_v2 with is_sqo field (Opportunity.SQL__c = 'yes')
SELECT 
    'LinkedIn Self-Sourced' as source,
    COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as total_contacts,
    COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as sqos,
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END),
        COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END)
    ) * 100, 2) as conversion_rate_pct,
    COUNT(DISTINCT CASE WHEN is_contacted = 1 AND SGA_IsActiveSGA = TRUE THEN primary_key END) as contacts_by_active_sgas,
    COUNT(DISTINCT CASE WHEN is_sqo = 1 AND SGA_IsActiveSGA = TRUE THEN sqo_primary_key END) as sqos_by_active_sgas
FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
  AND Original_source = 'LinkedIn (Self Sourced)';
```

**Note:** 
- Uses `is_sqo` field (correctly defined as `Opportunity.SQL__c = 'yes'`)
- Uses `sqo_primary_key` for accurate SQO counting (one SQO = one opportunity)
- Uses `SGA_IsActiveSGA = TRUE` for filtering active SGAs
- Uses `CreatedDate` (not `FilterDate`) to count only new leads created in 2025, excluding recycled leads from previous years

**Expected Output:**
- Total LinkedIn contacts made in 2025
- SQOs from LinkedIn (using correct definition)
- LinkedIn conversion rate (Contact-to-SQO)

---

### Query 2.2: LinkedIn Activity by SGA (2025)

```sql
-- LinkedIn activity per active SGA using correct SQO definition
SELECT 
    SGA_Owner_Name__c as sga_name,
    COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as linkedin_contacts,
    COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as sqos,
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END),
        COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END)
    ) * 100, 2) as conversion_rate_pct,
    ROUND(COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) / 12.0, 1) as contacts_per_month
FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
  AND Original_source = 'LinkedIn (Self Sourced)'
  AND SGA_IsActiveSGA = TRUE
GROUP BY SGA_Owner_Name__c
ORDER BY linkedin_contacts DESC;
```

**Note:** 
- Uses `is_sqo` and `sqo_primary_key` for accurate SQO counting
- Uses `SGA_IsActiveSGA = TRUE` for filtering active SGAs (14 total)

**Expected Output:**
- LinkedIn contacts per SGA
- SQOs per SGA from LinkedIn (using correct definition)
- Monthly contact rate per SGA

---

### Query 2.3: LinkedIn Lead Quality (If V3/V4 Scored)

```sql
-- Check if LinkedIn leads have V3/V4 scores
-- This requires joining LinkedIn leads to lead_scores_v3 or v4_prospect_scores
WITH linkedin_leads AS (
    SELECT DISTINCT
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as advisor_crd,
        Id as lead_id,
        Status,
        CreatedDate
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
      AND (
          LeadSource = 'LinkedIn (Self Sourced)'
      )
      AND IsDeleted = false
      AND FA_CRD__c IS NOT NULL
)
SELECT 
    'LinkedIn Leads with V3 Scores' as metric,
    COUNT(DISTINCT ll.lead_id) as linkedin_leads,
    COUNT(DISTINCT ls.lead_id) as with_v3_score,
    ROUND(COUNT(DISTINCT ls.lead_id) * 100.0 / COUNT(DISTINCT ll.lead_id), 2) as pct_with_v3_score,
    COUNT(DISTINCT CASE WHEN ls.score_tier LIKE 'TIER_1%' THEN ll.lead_id END) as tier1_linkedin_leads,
    ROUND(COUNT(DISTINCT CASE WHEN ls.score_tier LIKE 'TIER_1%' THEN ll.lead_id END) * 100.0 / COUNT(DISTINCT ll.lead_id), 2) as pct_tier1
FROM linkedin_leads ll
LEFT JOIN `savvy-gtm-analytics.ml_features.lead_scores_v3` ls
    ON ll.advisor_crd = ls.advisor_crd
GROUP BY metric;
```

**Expected Output:**
- How many LinkedIn leads have V3 scores
- What % are Tier 1 quality
- Quality comparison between LinkedIn and Provided leads

---

## Step 3: Compare Provided vs LinkedIn Performance

### Query 3.1: Side-by-Side Comparison (2025)

```sql
-- Compare Provided vs LinkedIn performance using correct SQO definition
WITH provided_leads AS (
    SELECT 
        COUNT(DISTINCT lead_id) as total_leads,
        COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) as sqos,
        ROUND(COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) * 100.0 / COUNT(DISTINCT lead_id), 2) as conv_rate_pct
    FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
    WHERE EXTRACT(YEAR FROM contacted_date) = 2025
      AND contacted_date IS NOT NULL
),
linkedin_leads AS (
    SELECT 
        COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as total_leads,
        COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as sqos,
        ROUND(SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END),
            COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END)
        ) * 100, 2) as conv_rate_pct
    FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
    WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
      AND Original_source = 'LinkedIn (Self Sourced)'
      AND SGA_IsActiveSGA = TRUE
)
SELECT 
    'Provided Lead List' as source,
    pl.total_leads,
    pl.sqos,
    pl.conv_rate_pct,
    ROUND(pl.total_leads / 14.0 / 12.0, 1) as leads_per_sga_per_month  -- 14 active SGAs
FROM provided_leads pl
UNION ALL
SELECT 
    'LinkedIn Self-Sourced' as source,
    ll.total_leads,
    ll.sqos,
    ll.conv_rate_pct,
    ROUND(ll.total_leads / 14.0 / 12.0, 1) as leads_per_sga_per_month  -- 14 active SGAs
FROM linkedin_leads ll;
```

**Note:** 
- Provided leads use `lead_scores_v3.converted` (which should align with SQO definition)
- LinkedIn uses `is_sqo` and `sqo_primary_key` from funnel view (correct SQO definition)

**Expected Output:**
- Direct comparison of volumes, SQOs, and conversion rates
- Leads per SGA per month for each source

---

### Query 3.2: Efficiency Analysis (Contact-to-SQO Funnel)

```sql
-- Calculate full funnel: Contact → MQL → SQL → SQO
-- Uses vw_conversion_rates for accurate pre-calculated metrics
SELECT 
    CASE 
        WHEN Original_source = 'LinkedIn (Self Sourced)' THEN 'LinkedIn Self-Sourced'
        WHEN Original_source IN ('Provided Lead List', 'FinTrx Data', 'Provided Lead List - Recycled') 
            THEN 'Provided Lead List'
        ELSE 'Other'
    END as source_group,
    SUM(contacted_volume) as contacted,
    SUM(mql_volume) as mql,
    SUM(sql_volume) as sql,
    SUM(sqo_volume) as sqos,
    -- Conversion rates match Looker Studio calculation method
    ROUND(SAFE_DIVIDE(SUM(contacted_to_mql_numerator), SUM(contacted_denominator)) * 100, 2) as contacted_to_mql_pct,
    ROUND(SAFE_DIVIDE(SUM(mql_to_sql_numerator), SUM(mql_denominator)) * 100, 2) as mql_to_sql_pct,
    ROUND(SAFE_DIVIDE(SUM(sql_to_sqo_numerator), SUM(sql_to_sqo_denominator)) * 100, 2) as sql_to_sqo_pct,
    ROUND(SAFE_DIVIDE(SUM(sql_to_sqo_numerator), SUM(contacted_denominator)) * 100, 2) as overall_contacted_to_sqo_pct
FROM `savvy-gtm-analytics.savvy_analytics.vw_conversion_rates`
WHERE EXTRACT(YEAR FROM cohort_month) = 2025
  AND Original_source IN ('LinkedIn (Self Sourced)', 'Provided Lead List', 'FinTrx Data', 'Provided Lead List - Recycled')
GROUP BY source_group
ORDER BY sqos DESC;
```

**Note:** 
- Uses `vw_conversion_rates` which has pre-calculated conversion metrics
- **Conversion rates match Looker Studio calculation method:**
  - Contact→MQL: `SUM(contacted_to_mql_numerator) / SUM(contacted_denominator)`
  - MQL→SQL: `SUM(mql_to_sql_numerator) / SUM(mql_denominator)`
  - SQL→SQO: `SUM(sql_to_sqo_numerator) / SUM(sql_to_sqo_denominator)`
- All metrics use correct SQO definition (`Opportunity.SQL__c = 'yes'`)
- Shows full funnel: Contacted → MQL → SQL → SQO

**Expected Output:**
- Full funnel metrics for both sources
- Contact-to-MQL, MQL-to-SQL, SQL-to-SQO conversion rates
- Overall Contact-to-SQO rate for comparison

---

## Step 4: Analyze Time Allocation & Capacity

### Query 4.1: Activity Volume by Source (Monthly)

```sql
-- Monthly activity breakdown to understand capacity
WITH provided_monthly AS (
    SELECT 
        EXTRACT(MONTH FROM contacted_date) as month_num,
        COUNT(DISTINCT lead_id) as provided_leads,
        COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) as provided_sqos
    FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
    WHERE EXTRACT(YEAR FROM contacted_date) = 2025
      AND contacted_date IS NOT NULL
    GROUP BY month_num
),
active_sgas_monthly AS (
    SELECT Id as sga_id
    FROM `savvy-gtm-analytics.SavvyGTMData.User`
    WHERE IsActive = true
      AND IsSGA__c = true
      AND Name NOT IN ('Jacqueline Tully', 'GinaRose', 'Savvy Marketing', 'Savvy Operations', 'Anett Davis', 'Anett Diaz')
),
linkedin_monthly AS (
    SELECT 
        EXTRACT(MONTH FROM CreatedDate) as month_num,
        COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as linkedin_contacts,
        COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as linkedin_sqos
    FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
    WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
      AND Original_source = 'LinkedIn (Self Sourced)'
      AND SGA_IsActiveSGA = TRUE
    GROUP BY month_num
)
SELECT 
    pm.month_num,
    pm.provided_leads,
    pm.provided_sqos,
    lm.linkedin_contacts,
    lm.linkedin_sqos,
    pm.provided_leads + lm.linkedin_contacts as total_activity,
    ROUND(pm.provided_leads * 100.0 / (pm.provided_leads + lm.linkedin_contacts), 1) as pct_provided,
    ROUND(lm.linkedin_contacts * 100.0 / (pm.provided_leads + lm.linkedin_contacts), 1) as pct_linkedin,
    ROUND((pm.provided_leads + lm.linkedin_contacts) / 14.0, 1) as total_per_sga  -- 14 active SGAs
FROM provided_monthly pm
FULL OUTER JOIN linkedin_monthly lm ON pm.month_num = lm.month_num
ORDER BY pm.month_num;
```

**Expected Output:**
- Monthly breakdown of activity
- % time spent on each source
- Total activity per SGA per month

---

### Query 4.2: SGA Activity Distribution

```sql
-- Activity distribution per SGA using funnel view
WITH provided_leads_by_sga AS (
    SELECT 
        SGA_Owner_Name__c as sga_name,
        COUNT(DISTINCT CASE WHEN is_contacted = 1 AND Original_source IN ('Provided Lead List', 'FinTrx Data', 'Provided Lead List - Recycled') THEN primary_key END) as provided_leads,
        COUNT(DISTINCT CASE WHEN is_sqo = 1 AND Original_source IN ('Provided Lead List', 'FinTrx Data', 'Provided Lead List - Recycled') THEN sqo_primary_key END) as provided_sqos
    FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
    WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
      AND Original_source IN ('Provided Lead List', 'FinTrx Data', 'Provided Lead List - Recycled')
      AND SGA_IsActiveSGA = TRUE
    GROUP BY SGA_Owner_Name__c
),
linkedin_leads_by_sga AS (
    SELECT 
        SGA_Owner_Name__c as sga_name,
        COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as linkedin_contacts,
        COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as linkedin_sqos
    FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
    WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
      AND Original_source = 'LinkedIn (Self Sourced)'
      AND SGA_IsActiveSGA = TRUE
    GROUP BY SGA_Owner_Name__c
)
SELECT 
    COALESCE(p.sga_name, l.sga_name) as sga_name,
    COALESCE(p.provided_leads, 0) as provided_leads,
    COALESCE(l.linkedin_contacts, 0) as linkedin_contacts,
    COALESCE(p.provided_sqos, 0) as provided_sqos,
    COALESCE(l.linkedin_sqos, 0) as linkedin_sqos,
    COALESCE(p.provided_leads, 0) + COALESCE(l.linkedin_contacts, 0) as total_activity,
    ROUND(SAFE_DIVIDE(COALESCE(p.provided_leads, 0), 
          COALESCE(p.provided_leads, 0) + COALESCE(l.linkedin_contacts, 0)) * 100, 1) as pct_provided,
    ROUND(SAFE_DIVIDE(COALESCE(p.provided_sqos, 0) + COALESCE(l.linkedin_sqos, 0),
          COALESCE(p.provided_leads, 0) + COALESCE(l.linkedin_contacts, 0)) * 100, 2) as overall_conv_rate
FROM provided_leads_by_sga p
FULL OUTER JOIN linkedin_leads_by_sga l ON p.sga_name = l.sga_name
ORDER BY total_activity DESC;
```

**Expected Output:**
- Activity breakdown per SGA
- Shows if some SGAs focus more on LinkedIn vs Provided

---

## Step 5: Identify Other Lead Sources

### Query 5.1: All Lead Sources (2025)

```sql
-- Comprehensive view of all lead sources using funnel view
SELECT 
    COALESCE(Original_source, 'Unknown') as lead_source,
    COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as total_contacts,
    COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as sqos,
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END),
        COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END)
    ) * 100, 2) as conversion_rate_pct,
    ROUND(COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) * 100.0 / 
          SUM(COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END)) OVER (), 1) as pct_of_total
FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
GROUP BY Original_source
ORDER BY total_contacts DESC;
```

**Expected Output:**
- All lead sources and their volumes
- Conversion rates by source
- % of total leads from each source

---

### Query 5.2: Campaign Analysis (2025)

```sql
-- Campaign analysis using funnel view (if Campaign__c is available)
-- Note: Campaign may not be in funnel view - may need to join to Lead table
SELECT 
    COALESCE(Channel_Grouping_Name, 'Other') as channel_group,
    COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as total_contacts,
    COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as sqos,
    ROUND(SAFE_DIVIDE(
        COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END),
        COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END)
    ) * 100, 2) as conversion_rate_pct
FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
  AND SGA_IsActiveSGA = TRUE
GROUP BY Channel_Grouping_Name
ORDER BY total_contacts DESC
LIMIT 20;
```

**Expected Output:**
- Top campaigns and their performance
- Identifies other high-performing sources

---

## Step 6: Analyze Capacity Constraints

### Query 6.1: Lead Volume vs Target (2025)

```sql
-- Compare actual lead volume to what's needed for target
WITH provided_leads AS (
    SELECT COUNT(DISTINCT lead_id) as total
    FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
    WHERE EXTRACT(YEAR FROM contacted_date) = 2025
),
linkedin_leads AS (
    SELECT COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as total
    FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
    WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
      AND Original_source = 'LinkedIn (Self Sourced)'
      AND SGA_IsActiveSGA = TRUE
),
target_analysis AS (
    SELECT 
        600 as annual_target_sqos,
        150 as quarterly_target_sqos,
        10 as sqos_per_sga_per_quarter,
        15 as num_sgas
)
SELECT 
    '2025 Actual' as period,
    pl.total + ll.total as total_leads,
    268 as actual_sqos,
    600 as target_sqos,
    ROUND(268 * 100.0 / 600, 1) as achievement_pct,
    ROUND((pl.total + ll.total) / 14.0 / 12.0, 1) as leads_per_sga_per_month,  -- 14 active SGAs
    ROUND(268 / 14.0 / 4.0, 1) as sqos_per_sga_per_quarter  -- 14 active SGAs
FROM provided_leads pl, linkedin_leads ll, target_analysis ta
UNION ALL
SELECT 
    '2025 Target' as period,
    NULL as total_leads,
    600 as actual_sqos,
    600 as target_sqos,
    100.0 as achievement_pct,
    NULL as leads_per_sga_per_month,
    10.0 as sqos_per_sga_per_quarter
FROM target_analysis ta;
```

**Expected Output:**
- Actual vs target comparison
- Identifies if volume or conversion is the issue

---

### Query 6.2: Tier 1 Lead Utilization

```sql
-- Check if we're fully utilizing Tier 1 leads
SELECT 
    'Tier 1 Leads' as metric,
    COUNT(DISTINCT lead_id) as total_tier1_leads,
    COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) as tier1_sqos,
    ROUND(COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) * 100.0 / 
          COUNT(DISTINCT lead_id), 2) as tier1_conv_rate,
    ROUND(COUNT(DISTINCT lead_id) / 14.0 / 12.0, 1) as tier1_per_sga_per_month,  -- 14 active SGAs
    -- Calculate how many Tier 1 leads we'd need for 150 SQOs/quarter
    ROUND(150 * 4 / (AVG(expected_conversion_rate) * 100), 0) as tier1_needed_for_target,
    ROUND((150 * 4 / (AVG(expected_conversion_rate) * 100)) / 14.0 / 12.0, 1) as tier1_per_sga_per_month_needed  -- 14 active SGAs
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE EXTRACT(YEAR FROM contacted_date) = 2025
  AND score_tier LIKE 'TIER_1%'
  AND contacted_date IS NOT NULL;
```

**Expected Output:**
- Tier 1 lead utilization
- Gap analysis: Are we providing enough Tier 1 leads?

---

## Step 7: Optimal Lead Mix Recommendation

### Query 7.1: Scenario Analysis

```sql
-- Calculate optimal mix based on ACTUAL conversion rates from 2025 data
WITH provided_metrics AS (
    SELECT 
        COUNT(DISTINCT lead_id) as total_2025,
        COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) as sqos_2025,
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END),
            COUNT(DISTINCT lead_id)
        ) as contact_to_sqo_rate  -- Calculate actual rate
    FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
    WHERE EXTRACT(YEAR FROM contacted_date) = 2025
),
linkedin_metrics AS (
    SELECT 
        COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as total_2025,
        COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as sqos_2025,
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END),
            COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END)
        ) as contact_to_sqo_rate  -- Calculate actual rate
    FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
    WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
      AND Original_source = 'LinkedIn (Self Sourced)'
      AND SGA_IsActiveSGA = TRUE
),
scenarios AS (
    SELECT 
        'Current Mix (Provided Heavy - based on actual 2025 data)' as scenario,
        600 as target_sqos,
        ROUND(600 * 0.74, 0) as provided_sqos_needed,  -- 74% from Provided (actual 2025)
        ROUND(600 * 0.26, 0) as linkedin_sqos_needed,   -- 26% from LinkedIn (actual 2025)
        ROUND(600 * 0.74 / pm.contact_to_sqo_rate, 0) as provided_contacts_needed,
        ROUND(600 * 0.26 / lm.contact_to_sqo_rate, 0) as linkedin_contacts_needed,
        pm.contact_to_sqo_rate as provided_rate,
        lm.contact_to_sqo_rate as linkedin_rate
    FROM provided_metrics pm, linkedin_metrics lm
    UNION ALL
    SELECT 
        'Increase LinkedIn (50/50 Mix)' as scenario,
        600 as target_sqos,
        300 as provided_sqos_needed,
        300 as linkedin_sqos_needed,
        ROUND(300 / pm.contact_to_sqo_rate, 0) as provided_contacts_needed,
        ROUND(300 / lm.contact_to_sqo_rate, 0) as linkedin_contacts_needed,
        pm.contact_to_sqo_rate as provided_rate,
        lm.contact_to_sqo_rate as linkedin_rate
    FROM provided_metrics pm, linkedin_metrics lm
    UNION ALL
    SELECT 
        'Maximize Efficiency (All Provided - Higher Conversion)' as scenario,
        600 as target_sqos,
        600 as provided_sqos_needed,
        0 as linkedin_sqos_needed,
        ROUND(600 / pm.contact_to_sqo_rate, 0) as provided_contacts_needed,
        0 as linkedin_contacts_needed,
        pm.contact_to_sqo_rate as provided_rate,
        lm.contact_to_sqo_rate as linkedin_rate
    FROM provided_metrics pm, linkedin_metrics lm
)
SELECT 
    scenario,
    target_sqos,
    provided_sqos_needed,
    linkedin_sqos_needed,
    provided_contacts_needed,
    linkedin_contacts_needed,
    provided_contacts_needed + linkedin_contacts_needed as total_contacts_needed,
    ROUND((provided_contacts_needed + linkedin_contacts_needed) / 14.0 / 12.0, 1) as per_sga_per_month,
    ROUND(provided_rate * 100, 2) as provided_conv_pct,
    ROUND(linkedin_rate * 100, 2) as linkedin_conv_pct
FROM scenarios;
```

**Note:** 
- Calculates actual conversion rates dynamically from 2025 data
- Updated scenarios reflect actual finding that Provided converts HIGHER (4.13%) than LinkedIn (2.30%)
- Scenarios include: Current mix (74/26), 50/50 mix, and all Provided (maximize efficiency)

**Expected Output:**
- Different mix scenarios with actual conversion rates
- Contact volumes needed for each scenario to achieve 600 SQOs/year
- Contacts per SGA per month for capacity planning
- Conversion rate percentages for each source

---

## Step 8: Generate Final Recommendations

### Query 8.1: Summary Dashboard

```sql
-- Comprehensive summary for decision-making
WITH provided_summary AS (
    SELECT 
        COUNT(DISTINCT lead_id) as total_leads,
        COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) as sqos,
        ROUND(COUNT(DISTINCT CASE WHEN converted = 1 THEN lead_id END) * 100.0 / 
              COUNT(DISTINCT lead_id), 2) as conv_rate_pct,
        COUNT(DISTINCT CASE WHEN score_tier LIKE 'TIER_1%' THEN lead_id END) as tier1_leads,
        ROUND(COUNT(DISTINCT CASE WHEN score_tier LIKE 'TIER_1%' THEN lead_id END) * 100.0 / 
              COUNT(DISTINCT lead_id), 1) as pct_tier1
    FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
    WHERE EXTRACT(YEAR FROM contacted_date) = 2025
),
linkedin_summary AS (
    SELECT 
        COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END) as total_leads,
        COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END) as sqos,
        ROUND(SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN is_sqo = 1 THEN sqo_primary_key END),
            COUNT(DISTINCT CASE WHEN is_contacted = 1 THEN primary_key END)
        ) * 100, 2) as conv_rate_pct
    FROM `savvy-gtm-analytics.savvy_analytics.vw_funnel_lead_to_joined_v2`
    WHERE EXTRACT(YEAR FROM CreatedDate) = 2025
      AND Original_source = 'LinkedIn (Self Sourced)'
      AND SGA_IsActiveSGA = TRUE
)
SELECT 
    'Provided Lead List' as source,
    ps.total_leads,
    ps.sqos,
    ps.conv_rate_pct,
    ps.tier1_leads,
    ps.pct_tier1,
    ROUND(ps.total_leads / 14.0 / 12.0, 1) as leads_per_sga_per_month,  -- 14 active SGAs
    ROUND(ps.sqos / 14.0 / 4.0, 1) as sqos_per_sga_per_quarter  -- 14 active SGAs
FROM provided_summary ps
UNION ALL
SELECT 
    'LinkedIn Self-Sourced' as source,
    ls.total_leads,
    ls.sqos,
    ls.conv_rate_pct,
    NULL as tier1_leads,
    NULL as pct_tier1,
    ROUND(ls.total_leads / 14.0 / 12.0, 1) as leads_per_sga_per_month,  -- 14 active SGAs
    ROUND(ls.sqos / 14.0 / 4.0, 1) as sqos_per_sga_per_quarter  -- 14 active SGAs
FROM linkedin_summary ls;
```

**Expected Output:**
- Complete summary for both sources
- Key metrics for decision-making

---

## How to Execute This Analysis

### Using BigQuery MCP Tools

1. **For each query section:**
   - Use `mcp_bigquery_execute_sql` tool
   - Copy the SQL query
   - Execute and review results
   - Document findings

2. **Recommended execution order:**
   - Step 1: Understand baseline (Queries 1.1-1.3)
   - Step 2: Analyze LinkedIn (Queries 2.1-2.3)
   - Step 3: Compare sources (Queries 3.1-3.2)
   - Step 4: Capacity analysis (Queries 4.1-4.2)
   - Step 5: Other sources (Queries 5.1-5.2)
   - Step 6: Constraints (Queries 6.1-6.2)
   - Step 7: Scenarios (Query 7.1)
   - Step 8: Summary (Query 8.1)

3. **Customization needed:**
   - All queries now use correct SQO definition (`is_sqo` from `vw_funnel_lead_to_joined_v2`)
   - LinkedIn identification uses `Original_source = 'LinkedIn (Self Sourced)'`
   - SGA filtering uses `SGA_IsActiveSGA = TRUE` (automatically excludes inactive SGAs)
   - Adjust target SQOs (currently 600/year, 150/quarter)

---

## Important Notes

### SGA Filtering
- **Active SGAs:** 14 (not 15)
- **Filter:** Use `SGA_IsActiveSGA = TRUE` from `vw_funnel_lead_to_joined_v2`
- **Automatic Exclusions:** The view automatically excludes: 'Jacqueline Tully', 'GinaRose', 'Savvy Marketing', 'Savvy Operations', 'Anett Davis', 'Anett Diaz'
- All queries use `SGA_IsActiveSGA = TRUE` for consistent filtering

### LinkedIn Identification
- **Use:** `Original_source = 'LinkedIn (Self Sourced)'` from `vw_funnel_lead_to_joined_v2`
- **Note:** This is the standardized source field in the funnel view
- All LinkedIn queries use `Original_source = 'LinkedIn (Self Sourced)'`

### Provided Leads
- **Source:** `lead_scores_v3` table (leads that entered "Contacting" stage)
- **Filter:** `contacted_date` in 2025
- These are leads from the monthly provided lead lists

## Key Questions to Answer After Running Queries

1. **What's the actual 2025 breakdown?**
   - Total provided leads vs LinkedIn contacts
   - Actual conversion rates vs expected
   - Activity per active SGA

2. **What's the capacity?**
   - How many leads can 14 SGAs handle per month?
   - What's the bottleneck?

3. **What's the optimal mix?**
   - Should we increase LinkedIn (better conversion)?
   - Should we focus on Tier 1 provided leads only?

4. **What are we missing?**
   - Other lead sources?
   - Untapped opportunities?

---

## Revised Findings (from Baseline Validation)

Based on correct SQO definition using `vw_funnel_lead_to_joined_v2`:

| Source | Contacted | SQOs | Contact-to-SQO % |
|--------|-----------|------|------------------|
| Provided Lead List | 13,701 | 566 | 4.13% |
| LinkedIn Self-Sourced | 8,474 | 195 | 2.30% |

**Key Finding:** Provided leads convert HIGHER than LinkedIn (4.13% vs 2.30%)
- This contradicts the initial hypothesis
- Provided leads are **1.8x more efficient** than LinkedIn
- However, top LinkedIn performers (Russell: 7.74%) exceed Provided average

**Implication:** Focus should be on:
1. **Maximizing Tier 1 Provided leads** (highest conversion: 15-25%)
2. **Training SGAs on LinkedIn best practices** from top performers
3. **Quality > Quantity** for both sources

The queries above will validate these findings and provide data-driven recommendations.

---

*Analysis Guide Created: January 2026*  
*Use BigQuery MCP tools to execute queries and generate insights*

