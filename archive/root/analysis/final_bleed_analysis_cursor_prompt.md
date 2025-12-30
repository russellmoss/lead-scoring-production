# Final Bleeding Signal Analysis: Inferred Departures & Conversion Re-Validation

## Cursor.ai MCP BigQuery Analysis Prompts

**Purpose:** Test the "inferred departure" hypothesis and re-validate all conversion findings with corrected bleeding signals.

**Key Hypothesis:** By using `PRIMARY_FIRM_START_DATE` at the new firm to infer departure date from the old firm, we can detect firm bleeding 60-90 days faster than waiting for `PREVIOUS_REGISTRATION_COMPANY_END_DATE` to be backfilled.

**Dataset Context:** 
- FINTRX data is a flat dataset received in late November 2025
- Data through October 2025 should be considered complete
- November 2025 is partial (dataset cutoff, not backfill lag)
- For PIT (point-in-time) training, use data through October 2025

**Output:** Compile all findings into `final_bleed_analysis.md`

---

## PHASE 1: Validate the Inferred Departure Approach

### Prompt 1.1: Test Basic Inferred Departure Logic

```
Test whether we can reliably infer departures from START_DATE at new firm. For advisors who started at a new firm, look up their most recent prior employer.

Run this SQL to validate the approach:
```

```sql
-- Test: Can we reliably link new firm starts to prior employers?
WITH recent_starters AS (
    SELECT
        c.RIA_CONTACT_CRD_ID as advisor_crd,
        c.PRIMARY_FIRM_START_DATE as new_firm_start,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as new_firm_crd,
        c.FIRST_NAME,
        c.LAST_NAME
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    WHERE c.PRIMARY_FIRM_START_DATE >= '2025-01-01'
      AND c.PRIMARY_FIRM_START_DATE <= '2025-10-31'  -- Complete data window
      AND c.PRIMARY_FIRM IS NOT NULL
),

-- Find their most recent prior employer
prior_employers AS (
    SELECT
        rs.advisor_crd,
        rs.new_firm_start,
        rs.new_firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as prior_firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_NAME as prior_firm_name,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as prior_firm_start,
        eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE as prior_firm_end,
        ROW_NUMBER() OVER (
            PARTITION BY rs.advisor_crd 
            ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
        ) as rn
    FROM recent_starters rs
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON rs.advisor_crd = eh.RIA_CONTACT_CRD_ID
        AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != rs.new_firm_crd  -- Not same firm
        AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE < rs.new_firm_start  -- Started before current
)

SELECT
    COUNT(DISTINCT advisor_crd) as total_recent_starters,
    COUNT(DISTINCT CASE WHEN prior_firm_crd IS NOT NULL AND rn = 1 THEN advisor_crd END) as have_prior_employer,
    COUNT(DISTINCT CASE WHEN prior_firm_crd IS NULL THEN advisor_crd END) as no_prior_employer,
    ROUND(
        COUNT(DISTINCT CASE WHEN prior_firm_crd IS NOT NULL AND rn = 1 THEN advisor_crd END) * 100.0 / 
        COUNT(DISTINCT advisor_crd), 
        1
    ) as pct_with_prior_employer
FROM prior_employers;
```

**Expected Result:** We should be able to identify prior employers for 70-90% of recent starters. Document the match rate.

### Prompt 1.2: Compare Inferred vs Actual END_DATE Timing

```
For advisors where we have BOTH the actual END_DATE and the inferred departure (START_DATE at new firm), compare the timing. This validates whether the inference is accurate.
```

```sql
-- Compare inferred departure date vs actual END_DATE
WITH transitions AS (
    SELECT
        c.RIA_CONTACT_CRD_ID as advisor_crd,
        c.PRIMARY_FIRM_START_DATE as inferred_departure_date,  -- When they started NEW firm
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as new_firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as prior_firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE as actual_end_date,
        DATE_DIFF(
            c.PRIMARY_FIRM_START_DATE, 
            eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE, 
            DAY
        ) as gap_days
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON c.RIA_CONTACT_CRD_ID = eh.RIA_CONTACT_CRD_ID
    WHERE c.PRIMARY_FIRM_START_DATE >= '2024-01-01'
      AND c.PRIMARY_FIRM_START_DATE <= '2025-10-31'
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != SAFE_CAST(c.PRIMARY_FIRM AS INT64)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.RIA_CONTACT_CRD_ID 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
)

SELECT
    COUNT(*) as total_transitions,
    
    -- Gap analysis
    AVG(gap_days) as avg_gap_days,
    APPROX_QUANTILES(gap_days, 100)[OFFSET(50)] as median_gap_days,
    APPROX_QUANTILES(gap_days, 100)[OFFSET(25)] as p25_gap_days,
    APPROX_QUANTILES(gap_days, 100)[OFFSET(75)] as p75_gap_days,
    
    -- How many are within reasonable windows
    COUNTIF(gap_days BETWEEN -7 AND 7) as within_1_week,
    COUNTIF(gap_days BETWEEN -30 AND 30) as within_1_month,
    COUNTIF(gap_days BETWEEN -90 AND 90) as within_3_months,
    COUNTIF(gap_days > 90) as gap_over_90_days,
    COUNTIF(gap_days < -90) as started_before_ended_90plus,
    
    -- Percentages
    ROUND(COUNTIF(gap_days BETWEEN -7 AND 7) * 100.0 / COUNT(*), 1) as pct_within_1_week,
    ROUND(COUNTIF(gap_days BETWEEN -30 AND 30) * 100.0 / COUNT(*), 1) as pct_within_1_month
    
FROM transitions;
```

**Expected Result:** Most gaps should be within 0-30 days (advisor leaves and starts new job same week/month). Document the distribution.

### Prompt 1.3: Identify Coverage Gaps

```
Identify scenarios where the inferred approach won't work - advisors who left but we can't infer their departure because they don't have a new firm START_DATE.
```

```sql
-- Find advisors who ended employment but DON'T have a new PRIMARY_FIRM_START_DATE
-- These are likely retirees, industry leavers, or data gaps
WITH departed_advisors AS (
    SELECT
        eh.RIA_CONTACT_CRD_ID as advisor_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE as end_date,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as departed_firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_NAME as departed_firm_name
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
    WHERE eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= '2024-01-01'
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE <= '2025-10-31'
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY eh.RIA_CONTACT_CRD_ID 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE DESC
    ) = 1
),

current_status AS (
    SELECT
        da.advisor_crd,
        da.end_date,
        da.departed_firm_crd,
        da.departed_firm_name,
        c.PRIMARY_FIRM as current_firm,
        c.PRIMARY_FIRM_START_DATE as current_firm_start,
        CASE 
            WHEN c.PRIMARY_FIRM IS NULL THEN 'NO_CURRENT_FIRM'
            WHEN c.PRIMARY_FIRM_START_DATE > da.end_date THEN 'MOVED_TO_NEW_FIRM'
            WHEN c.PRIMARY_FIRM_START_DATE <= da.end_date THEN 'RETURNED_TO_PRIOR_OR_SAME'
            ELSE 'UNKNOWN'
        END as status
    FROM departed_advisors da
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON da.advisor_crd = c.RIA_CONTACT_CRD_ID
)

SELECT
    status,
    COUNT(*) as advisor_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) as pct
FROM current_status
GROUP BY 1
ORDER BY 2 DESC;
```

**Document:** What percentage of departures can be detected via inference vs requiring the actual END_DATE?

---

## PHASE 2: Build Corrected Bleeding Signal

### Prompt 2.1: Create Inferred Departures Dataset

```
Build a comprehensive inferred departures dataset using START_DATE at new firm. This becomes our "fresh" bleeding signal.
```

```sql
-- INFERRED DEPARTURES: Fresh bleeding signal using START_DATE inference
CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.inferred_departures_analysis` AS

WITH inferred_departures AS (
    SELECT
        c.RIA_CONTACT_CRD_ID as advisor_crd,
        c.PRIMARY_FIRM_START_DATE as inferred_departure_date,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as new_firm_crd,
        c.FIRM_NAME as new_firm_name,
        SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as departed_firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_NAME as departed_firm_name,
        eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE as actual_end_date,
        DATE_DIFF(c.PRIMARY_FIRM_START_DATE, eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE, DAY) as inference_gap_days
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON c.RIA_CONTACT_CRD_ID = eh.RIA_CONTACT_CRD_ID
    WHERE c.PRIMARY_FIRM_START_DATE >= '2023-01-01'
      AND c.PRIMARY_FIRM_START_DATE <= '2025-10-31'
      AND c.PRIMARY_FIRM IS NOT NULL
      AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != SAFE_CAST(c.PRIMARY_FIRM AS INT64)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.RIA_CONTACT_CRD_ID, c.PRIMARY_FIRM_START_DATE
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
)

SELECT 
    *,
    DATE_TRUNC(inferred_departure_date, MONTH) as departure_month,
    DATE_TRUNC(inferred_departure_date, QUARTER) as departure_quarter,
    EXTRACT(YEAR FROM inferred_departure_date) as departure_year
FROM inferred_departures;
```

```sql
-- Verify the table was created and check counts
SELECT 
    departure_year,
    COUNT(*) as departures,
    COUNT(DISTINCT departed_firm_crd) as firms_affected,
    COUNT(DISTINCT advisor_crd) as advisors
FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis`
GROUP BY 1
ORDER BY 1;
```

### Prompt 2.2: Create Firm Bleeding Metrics (Corrected)

```
Aggregate inferred departures at the firm level to create corrected bleeding metrics.
```

```sql
-- CORRECTED FIRM BLEEDING: Using inferred departures
CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.firm_bleeding_corrected` AS

WITH firm_departures_inferred AS (
    SELECT
        departed_firm_crd as firm_crd,
        departed_firm_name as firm_name,
        
        -- Rolling windows (using inferred departure date)
        COUNT(DISTINCT CASE 
            WHEN inferred_departure_date >= DATE_SUB(DATE('2025-10-31'), INTERVAL 90 DAY) 
            THEN advisor_crd END) as departures_90d,
        COUNT(DISTINCT CASE 
            WHEN inferred_departure_date >= DATE_SUB(DATE('2025-10-31'), INTERVAL 180 DAY) 
            THEN advisor_crd END) as departures_180d,
        COUNT(DISTINCT CASE 
            WHEN inferred_departure_date >= DATE_SUB(DATE('2025-10-31'), INTERVAL 365 DAY) 
            THEN advisor_crd END) as departures_12mo,
            
        -- Total departures in dataset
        COUNT(DISTINCT advisor_crd) as total_departures
        
    FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis`
    WHERE departed_firm_crd IS NOT NULL
    GROUP BY 1, 2
),

firm_arrivals AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT CASE 
            WHEN PRIMARY_FIRM_START_DATE >= DATE_SUB(DATE('2025-10-31'), INTERVAL 90 DAY) 
            THEN RIA_CONTACT_CRD_ID END) as arrivals_90d,
        COUNT(DISTINCT CASE 
            WHEN PRIMARY_FIRM_START_DATE >= DATE_SUB(DATE('2025-10-31'), INTERVAL 180 DAY) 
            THEN RIA_CONTACT_CRD_ID END) as arrivals_180d,
        COUNT(DISTINCT CASE 
            WHEN PRIMARY_FIRM_START_DATE >= DATE_SUB(DATE('2025-10-31'), INTERVAL 365 DAY) 
            THEN RIA_CONTACT_CRD_ID END) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= '2023-01-01'
      AND PRIMARY_FIRM_START_DATE <= '2025-10-31'
    GROUP BY 1
),

firm_headcount AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_headcount
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
)

SELECT
    fd.firm_crd,
    fd.firm_name,
    fh.current_headcount,
    
    -- Departures (inferred - FRESH signal)
    COALESCE(fd.departures_90d, 0) as departures_90d_inferred,
    COALESCE(fd.departures_180d, 0) as departures_180d_inferred,
    COALESCE(fd.departures_12mo, 0) as departures_12mo_inferred,
    
    -- Arrivals
    COALESCE(fa.arrivals_90d, 0) as arrivals_90d,
    COALESCE(fa.arrivals_180d, 0) as arrivals_180d,
    COALESCE(fa.arrivals_12mo, 0) as arrivals_12mo,
    
    -- Net change (inferred)
    COALESCE(fa.arrivals_12mo, 0) - COALESCE(fd.departures_12mo, 0) as net_change_12mo_inferred,
    
    -- Turnover rate (inferred)
    ROUND(COALESCE(fd.departures_12mo, 0) * 100.0 / NULLIF(fh.current_headcount, 0), 2) as turnover_rate_inferred,
    
    -- Bleeding categories (inferred)
    CASE
        WHEN COALESCE(fd.departures_12mo, 0) >= 20 THEN 'HEAVY_BLEEDING'
        WHEN COALESCE(fd.departures_12mo, 0) >= 10 THEN 'MODERATE_BLEEDING'
        WHEN COALESCE(fd.departures_12mo, 0) >= 5 THEN 'LOW_BLEEDING'
        ELSE 'STABLE'
    END as bleeding_category_inferred

FROM firm_departures_inferred fd
LEFT JOIN firm_arrivals fa ON fd.firm_crd = fa.firm_crd
LEFT JOIN firm_headcount fh ON fd.firm_crd = fh.firm_crd
WHERE fh.current_headcount >= 10;  -- Minimum firm size for meaningful signal
```

### Prompt 2.3: Compare Corrected vs Original Bleeding Signal

```
Compare the corrected (inferred) bleeding signal to the original (END_DATE) approach. Are different firms flagged?
```

```sql
-- Compare OLD vs NEW bleeding signals
WITH old_bleeding AS (
    -- Original approach using END_DATE
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo_old
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(DATE('2025-10-31'), INTERVAL 365 DAY)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE <= DATE('2025-10-31')
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
),

new_bleeding AS (
    -- New approach using inferred departures
    SELECT
        firm_crd,
        departures_12mo_inferred as departures_12mo_new
    FROM `savvy-gtm-analytics.ml_features.firm_bleeding_corrected`
),

comparison AS (
    SELECT
        COALESCE(o.firm_crd, n.firm_crd) as firm_crd,
        COALESCE(o.departures_12mo_old, 0) as departures_old,
        COALESCE(n.departures_12mo_new, 0) as departures_new,
        COALESCE(n.departures_12mo_new, 0) - COALESCE(o.departures_12mo_old, 0) as difference,
        CASE
            WHEN COALESCE(o.departures_12mo_old, 0) >= 10 AND COALESCE(n.departures_12mo_new, 0) >= 10 THEN 'BOTH_BLEEDING'
            WHEN COALESCE(o.departures_12mo_old, 0) >= 10 AND COALESCE(n.departures_12mo_new, 0) < 10 THEN 'OLD_ONLY'
            WHEN COALESCE(o.departures_12mo_old, 0) < 10 AND COALESCE(n.departures_12mo_new, 0) >= 10 THEN 'NEW_ONLY'
            ELSE 'NEITHER'
        END as signal_comparison
    FROM old_bleeding o
    FULL OUTER JOIN new_bleeding n ON o.firm_crd = n.firm_crd
)

SELECT
    signal_comparison,
    COUNT(*) as firm_count,
    AVG(departures_old) as avg_departures_old,
    AVG(departures_new) as avg_departures_new,
    AVG(difference) as avg_difference
FROM comparison
GROUP BY 1
ORDER BY 1;
```

**Document:** How many firms are flagged as bleeding by one method but not the other?

---

## PHASE 3: Re-Validate Conversion Analysis

### Prompt 3.1: Bleeding Category vs Conversion (CORRECTED)

```
This is the KEY analysis. Re-run the bleeding vs conversion analysis using the CORRECTED (inferred) bleeding signal. Does the inverse relationship still hold?
```

```sql
-- CRITICAL: Re-validate bleeding vs conversion with CORRECTED signal
WITH lead_base AS (
    SELECT
        l.Id as lead_id,
        SAFE_CAST(l.FA_CRD__c AS INT64) as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        CASE WHEN l.MQL_Date__c IS NOT NULL THEN 1 ELSE 0 END as converted
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.stage_entered_contacting__c >= '2023-01-01'
      AND l.stage_entered_contacting__c <= '2025-10-31'
      AND l.FA_CRD__c IS NOT NULL
),

-- Get advisor's firm at time of contact
advisor_firm AS (
    SELECT
        lb.lead_id,
        lb.advisor_crd,
        lb.contacted_date,
        lb.converted,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd
    FROM lead_base lb
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON lb.advisor_crd = c.RIA_CONTACT_CRD_ID
),

-- Calculate firm bleeding at PIT (using inferred departures)
firm_bleeding_pit AS (
    SELECT
        af.lead_id,
        af.advisor_crd,
        af.firm_crd,
        af.contacted_date,
        af.converted,
        
        -- Count inferred departures in 12 months BEFORE contact
        (SELECT COUNT(DISTINCT id.advisor_crd)
         FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis` id
         WHERE id.departed_firm_crd = af.firm_crd
           AND id.inferred_departure_date >= DATE_SUB(af.contacted_date, INTERVAL 365 DAY)
           AND id.inferred_departure_date < af.contacted_date
        ) as departures_12mo_pit_inferred,
        
        -- Count arrivals in 12 months BEFORE contact
        (SELECT COUNT(DISTINCT c2.RIA_CONTACT_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c2
         WHERE SAFE_CAST(c2.PRIMARY_FIRM AS INT64) = af.firm_crd
           AND c2.PRIMARY_FIRM_START_DATE >= DATE_SUB(af.contacted_date, INTERVAL 365 DAY)
           AND c2.PRIMARY_FIRM_START_DATE < af.contacted_date
        ) as arrivals_12mo_pit
        
    FROM advisor_firm af
),

-- Categorize bleeding
categorized AS (
    SELECT
        *,
        arrivals_12mo_pit - departures_12mo_pit_inferred as net_change_pit,
        CASE
            WHEN departures_12mo_pit_inferred >= 20 THEN 'HEAVY_BLEEDING'
            WHEN departures_12mo_pit_inferred >= 10 THEN 'MODERATE_BLEEDING'
            WHEN departures_12mo_pit_inferred >= 5 THEN 'LOW_BLEEDING'
            ELSE 'STABLE'
        END as bleeding_category_inferred
    FROM firm_bleeding_pit
)

SELECT
    bleeding_category_inferred,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate,
    AVG(departures_12mo_pit_inferred) as avg_departures,
    AVG(net_change_pit) as avg_net_change
FROM categorized
GROUP BY 1
ORDER BY conversion_rate DESC;
```

**CRITICAL QUESTION:** Does bleeding now correlate POSITIVELY with conversion once we use the corrected signal?

### Prompt 3.2: Compare Corrected vs Original Conversion Analysis

```
Run the SAME conversion analysis using the OLD (END_DATE) bleeding signal, then compare side-by-side.
```

```sql
-- ORIGINAL METHOD: Bleeding vs conversion using END_DATE
WITH lead_base AS (
    SELECT
        l.Id as lead_id,
        SAFE_CAST(l.FA_CRD__c AS INT64) as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        CASE WHEN l.MQL_Date__c IS NOT NULL THEN 1 ELSE 0 END as converted
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.stage_entered_contacting__c >= '2023-01-01'
      AND l.stage_entered_contacting__c <= '2025-10-31'
      AND l.FA_CRD__c IS NOT NULL
),

advisor_firm AS (
    SELECT
        lb.lead_id,
        lb.advisor_crd,
        lb.contacted_date,
        lb.converted,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd
    FROM lead_base lb
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON lb.advisor_crd = c.RIA_CONTACT_CRD_ID
),

-- OLD METHOD: Using END_DATE directly
firm_bleeding_old AS (
    SELECT
        af.lead_id,
        af.converted,
        (SELECT COUNT(DISTINCT eh.RIA_CONTACT_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
         WHERE SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) = af.firm_crd
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(af.contacted_date, INTERVAL 365 DAY)
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < af.contacted_date
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
        ) as departures_12mo_old
    FROM advisor_firm af
),

categorized_old AS (
    SELECT
        *,
        CASE
            WHEN departures_12mo_old >= 20 THEN 'HEAVY_BLEEDING'
            WHEN departures_12mo_old >= 10 THEN 'MODERATE_BLEEDING'
            WHEN departures_12mo_old >= 5 THEN 'LOW_BLEEDING'
            ELSE 'STABLE'
        END as bleeding_category_old
    FROM firm_bleeding_old
)

SELECT
    bleeding_category_old,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate_old
FROM categorized_old
GROUP BY 1
ORDER BY conversion_rate_old DESC;
```

**Create comparison table:**
| Bleeding Category | Conversion (OLD Method) | Conversion (NEW Method) | Delta |
|-------------------|------------------------|------------------------|-------|
| HEAVY_BLEEDING | X% | Y% | +/-Z% |
| MODERATE_BLEEDING | X% | Y% | +/-Z% |
| LOW_BLEEDING | X% | Y% | +/-Z% |
| STABLE | X% | Y% | +/-Z% |

### Prompt 3.3: Calculate Correlation Coefficients

```
Calculate the correlation between bleeding signal and conversion for BOTH methods.
```

```sql
-- Correlation comparison: OLD vs NEW bleeding signals
WITH lead_features AS (
    SELECT
        l.Id as lead_id,
        SAFE_CAST(l.FA_CRD__c AS INT64) as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        CASE WHEN l.MQL_Date__c IS NOT NULL THEN 1 ELSE 0 END as converted,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(l.FA_CRD__c AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c >= '2023-01-01'
      AND l.stage_entered_contacting__c <= '2025-10-31'
      AND l.FA_CRD__c IS NOT NULL
),

bleeding_signals AS (
    SELECT
        lf.lead_id,
        lf.converted,
        
        -- OLD signal (END_DATE)
        (SELECT COUNT(DISTINCT eh.RIA_CONTACT_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
         WHERE SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) = lf.firm_crd
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(lf.contacted_date, INTERVAL 365 DAY)
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < lf.contacted_date
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
        ) as departures_old,
        
        -- NEW signal (inferred from START_DATE)
        (SELECT COUNT(DISTINCT id.advisor_crd)
         FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis` id
         WHERE id.departed_firm_crd = lf.firm_crd
           AND id.inferred_departure_date >= DATE_SUB(lf.contacted_date, INTERVAL 365 DAY)
           AND id.inferred_departure_date < lf.contacted_date
        ) as departures_new
        
    FROM lead_features lf
)

SELECT
    'OLD (END_DATE)' as method,
    CORR(departures_old, converted) as correlation_with_conversion,
    COUNT(*) as sample_size
FROM bleeding_signals

UNION ALL

SELECT
    'NEW (Inferred)' as method,
    CORR(departures_new, converted) as correlation_with_conversion,
    COUNT(*) as sample_size
FROM bleeding_signals;
```

**Expected Result:** If our hypothesis is correct, the NEW (inferred) correlation should be MORE POSITIVE (or less negative) than the OLD correlation.

---

## PHASE 4: Advisor Mobility Re-Analysis

### Prompt 4.1: Recent Mover Detection (Corrected)

```
Test if the inferred approach helps us detect "recent movers" better. A recent mover's END_DATE may not be backfilled yet, but their START_DATE at the new firm is available.
```

```sql
-- Recent mover detection: Compare OLD vs NEW approach
WITH lead_base AS (
    SELECT
        l.Id as lead_id,
        SAFE_CAST(l.FA_CRD__c AS INT64) as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        CASE WHEN l.MQL_Date__c IS NOT NULL THEN 1 ELSE 0 END as converted
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.stage_entered_contacting__c >= '2023-01-01'
      AND l.stage_entered_contacting__c <= '2025-10-31'
      AND l.FA_CRD__c IS NOT NULL
),

advisor_mobility AS (
    SELECT
        lb.lead_id,
        lb.advisor_crd,
        lb.contacted_date,
        lb.converted,
        
        -- OLD: Days since last move (using END_DATE)
        (SELECT DATE_DIFF(lb.contacted_date, MAX(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE), DAY)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
         WHERE eh.RIA_CONTACT_CRD_ID = lb.advisor_crd
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < lb.contacted_date
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
        ) as days_since_move_old,
        
        -- NEW: Days since last move (using START_DATE at current firm)
        (SELECT DATE_DIFF(lb.contacted_date, c.PRIMARY_FIRM_START_DATE, DAY)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
         WHERE c.RIA_CONTACT_CRD_ID = lb.advisor_crd
           AND c.PRIMARY_FIRM_START_DATE < lb.contacted_date
        ) as days_since_move_new
        
    FROM lead_base lb
),

categorized AS (
    SELECT
        *,
        -- OLD classification
        CASE 
            WHEN days_since_move_old <= 365 THEN 'RECENT_MOVER_1YR'
            WHEN days_since_move_old <= 730 THEN 'MOVED_2YR'
            WHEN days_since_move_old <= 1095 THEN 'MOVED_3YR'
            ELSE 'STABLE_3PLUS'
        END as mobility_old,
        -- NEW classification
        CASE 
            WHEN days_since_move_new <= 365 THEN 'RECENT_MOVER_1YR'
            WHEN days_since_move_new <= 730 THEN 'MOVED_2YR'
            WHEN days_since_move_new <= 1095 THEN 'MOVED_3YR'
            ELSE 'STABLE_3PLUS'
        END as mobility_new
    FROM advisor_mobility
)

SELECT
    'OLD METHOD' as method,
    mobility_old as category,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate
FROM categorized
GROUP BY 1, 2

UNION ALL

SELECT
    'NEW METHOD' as method,
    mobility_new as category,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate
FROM categorized
GROUP BY 1, 2

ORDER BY method, category;
```

### Prompt 4.2: Identify Misclassified Recent Movers

```
How many advisors are classified as "stable" by the OLD method but "recent mover" by the NEW method?
```

```sql
-- Find advisors misclassified by old method
WITH advisor_mobility AS (
    SELECT
        l.Id as lead_id,
        SAFE_CAST(l.FA_CRD__c AS INT64) as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        CASE WHEN l.MQL_Date__c IS NOT NULL THEN 1 ELSE 0 END as converted,
        
        -- OLD: Days since last move (using END_DATE)
        (SELECT DATE_DIFF(DATE(l.stage_entered_contacting__c), MAX(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE), DAY)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
         WHERE eh.RIA_CONTACT_CRD_ID = SAFE_CAST(l.FA_CRD__c AS INT64)
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < DATE(l.stage_entered_contacting__c)
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
        ) as days_since_move_old,
        
        -- NEW: Days since last move (using START_DATE)
        c.PRIMARY_FIRM_START_DATE,
        DATE_DIFF(DATE(l.stage_entered_contacting__c), c.PRIMARY_FIRM_START_DATE, DAY) as days_since_move_new
        
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(l.FA_CRD__c AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c >= '2023-01-01'
      AND l.stage_entered_contacting__c <= '2025-10-31'
),

misclassified AS (
    SELECT
        *,
        CASE 
            WHEN days_since_move_old IS NULL OR days_since_move_old > 365 THEN 'STABLE_OLD'
            ELSE 'RECENT_OLD'
        END as old_class,
        CASE 
            WHEN days_since_move_new <= 365 THEN 'RECENT_NEW'
            ELSE 'STABLE_NEW'
        END as new_class
    FROM advisor_mobility
)

SELECT
    old_class,
    new_class,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate
FROM misclassified
GROUP BY 1, 2
ORDER BY 1, 2;
```

**Key metric:** How many leads classified as "STABLE" by old method are actually "RECENT" by new method? What's their conversion rate?

---

## PHASE 5: V3 Tier Impact Analysis

### Prompt 5.1: Re-Score Historical Leads with Corrected Signal

```
Apply V3 tier logic using the CORRECTED bleeding signal. How many leads change tiers?
```

```sql
-- Re-score with corrected bleeding signal
WITH lead_features AS (
    SELECT
        l.Id as lead_id,
        SAFE_CAST(l.FA_CRD__c AS INT64) as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        CASE WHEN l.MQL_Date__c IS NOT NULL THEN 1 ELSE 0 END as converted,
        c.FIRST_NAME,
        c.LAST_NAME,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
        c.FIRM_NAME,
        DATE_DIFF(DATE(l.stage_entered_contacting__c), c.PRIMARY_FIRM_START_DATE, DAY) / 365.0 as tenure_years,
        -- Industry tenure approximation
        (SELECT DATE_DIFF(DATE(l.stage_entered_contacting__c), MIN(eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE), DAY) / 365.0
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
         WHERE eh.RIA_CONTACT_CRD_ID = SAFE_CAST(l.FA_CRD__c AS INT64)
        ) as industry_tenure_years,
        -- Prior firms
        (SELECT COUNT(DISTINCT eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
         WHERE eh.RIA_CONTACT_CRD_ID = SAFE_CAST(l.FA_CRD__c AS INT64)
           AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE < DATE(l.stage_entered_contacting__c)
        ) as num_prior_firms
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(l.FA_CRD__c AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE l.stage_entered_contacting__c >= '2024-01-01'
      AND l.stage_entered_contacting__c <= '2025-10-31'
),

with_bleeding AS (
    SELECT
        lf.*,
        -- CORRECTED bleeding signal (inferred)
        (SELECT COUNT(DISTINCT id.advisor_crd)
         FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis` id
         WHERE id.departed_firm_crd = lf.firm_crd
           AND id.inferred_departure_date >= DATE_SUB(lf.contacted_date, INTERVAL 365 DAY)
           AND id.inferred_departure_date < lf.contacted_date
        ) as firm_net_change_12mo_corrected,
        
        -- OLD bleeding signal
        (SELECT COUNT(DISTINCT eh.RIA_CONTACT_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
         WHERE SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) = lf.firm_crd
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(lf.contacted_date, INTERVAL 365 DAY)
           AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < lf.contacted_date
        ) as firm_net_change_12mo_old
    FROM lead_features lf
),

-- Apply simplified tier logic (matching V3.2)
tiered AS (
    SELECT
        *,
        -- OLD tier
        CASE
            WHEN tenure_years BETWEEN 1 AND 4 
                 AND industry_tenure_years BETWEEN 5 AND 15 
                 AND firm_net_change_12mo_old > 5 THEN 'TIER_1_PRIME_MOVER'
            WHEN num_prior_firms >= 3 AND industry_tenure_years >= 5 THEN 'TIER_2_PROVEN_MOVER'
            WHEN firm_net_change_12mo_old BETWEEN 1 AND 10 AND industry_tenure_years >= 5 THEN 'TIER_3_MODERATE_BLEEDER'
            WHEN firm_net_change_12mo_old > 10 AND industry_tenure_years >= 5 THEN 'TIER_5_HEAVY_BLEEDER'
            ELSE 'STANDARD'
        END as tier_old,
        
        -- NEW tier (corrected)
        CASE
            WHEN tenure_years BETWEEN 1 AND 4 
                 AND industry_tenure_years BETWEEN 5 AND 15 
                 AND firm_net_change_12mo_corrected > 5 THEN 'TIER_1_PRIME_MOVER'
            WHEN num_prior_firms >= 3 AND industry_tenure_years >= 5 THEN 'TIER_2_PROVEN_MOVER'
            WHEN firm_net_change_12mo_corrected BETWEEN 1 AND 10 AND industry_tenure_years >= 5 THEN 'TIER_3_MODERATE_BLEEDER'
            WHEN firm_net_change_12mo_corrected > 10 AND industry_tenure_years >= 5 THEN 'TIER_5_HEAVY_BLEEDER'
            ELSE 'STANDARD'
        END as tier_new
    FROM with_bleeding
)

SELECT
    tier_old,
    tier_new,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate,
    CASE WHEN tier_old != tier_new THEN 'CHANGED' ELSE 'SAME' END as tier_change
FROM tiered
GROUP BY 1, 2
ORDER BY tier_old, tier_new;
```

### Prompt 5.2: Tier Performance Comparison

```
Calculate tier-level conversion rates for OLD vs NEW tier assignments.
```

```sql
-- Summarize tier performance: OLD vs NEW
WITH tiered_leads AS (
    -- (Use the tiered CTE from above)
    -- Simplified for this query:
    SELECT 
        lead_id,
        converted,
        tier_old,
        tier_new
    FROM (
        -- ... same logic as 5.1 ...
    )
)

SELECT
    'OLD TIERS' as method,
    tier_old as tier,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate
FROM tiered_leads
GROUP BY 1, 2

UNION ALL

SELECT
    'NEW TIERS' as method,
    tier_new as tier,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conversion_rate
FROM tiered_leads
GROUP BY 1, 2

ORDER BY method, tier;
```

---

## PHASE 6: Priority Advisor (ICP) Movement Patterns

### Prompt 6.1: Define and Identify Priority Advisors

```
Identify "priority advisors" who fit your ICP criteria and analyze their movement patterns.
```

```sql
-- Priority advisor definition (matching ICP)
WITH priority_advisors AS (
    SELECT
        c.RIA_CONTACT_CRD_ID as advisor_crd,
        c.FIRST_NAME,
        c.LAST_NAME,
        c.FIRM_NAME,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
        c.PRIMARY_FIRM_START_DATE,
        c.TITLE_NAME,
        c.PRODUCING_ADVISOR,
        
        -- ICP criteria flags
        CASE WHEN c.PRODUCING_ADVISOR = TRUE THEN 1 ELSE 0 END as is_producing,
        CASE WHEN UPPER(c.TITLE_NAME) NOT LIKE '%INSURANCE%' THEN 1 ELSE 0 END as not_insurance,
        CASE WHEN UPPER(c.FIRM_NAME) NOT LIKE '%WIREHOUSE%' 
              AND UPPER(c.FIRM_NAME) NOT LIKE '%MERRILL%'
              AND UPPER(c.FIRM_NAME) NOT LIKE '%MORGAN STANLEY%'
              AND UPPER(c.FIRM_NAME) NOT LIKE '%UBS%'
              AND UPPER(c.FIRM_NAME) NOT LIKE '%WELLS FARGO%'
         THEN 1 ELSE 0 END as not_wirehouse,
         
        -- Tenure
        DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, DAY) / 365.0 as tenure_years
        
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    WHERE c.PRODUCING_ADVISOR = TRUE
),

priority_with_history AS (
    SELECT
        pa.*,
        -- Count moves in last 3 years
        (SELECT COUNT(DISTINCT eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
         WHERE eh.RIA_CONTACT_CRD_ID = pa.advisor_crd
           AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 YEAR)
        ) as moves_3yr,
        
        -- Industry tenure
        (SELECT DATE_DIFF(CURRENT_DATE(), MIN(eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE), DAY) / 365.0
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
         WHERE eh.RIA_CONTACT_CRD_ID = pa.advisor_crd
        ) as industry_tenure_years
        
    FROM priority_advisors pa
    WHERE pa.is_producing = 1 
      AND pa.not_insurance = 1 
      AND pa.not_wirehouse = 1
)

SELECT
    CASE 
        WHEN moves_3yr >= 2 THEN 'HIGH_MOBILITY'
        WHEN moves_3yr = 1 THEN 'MODERATE_MOBILITY'
        ELSE 'STABLE'
    END as mobility_segment,
    CASE 
        WHEN tenure_years <= 2 THEN '0-2yr'
        WHEN tenure_years <= 5 THEN '2-5yr'
        WHEN tenure_years <= 10 THEN '5-10yr'
        ELSE '10+yr'
    END as tenure_segment,
    COUNT(*) as advisor_count,
    ROUND(AVG(industry_tenure_years), 1) as avg_industry_tenure
FROM priority_with_history
GROUP BY 1, 2
ORDER BY 1, 2;
```

### Prompt 6.2: Priority Advisor Movement by Month

```
Create monthly time series of priority advisor movement for economic correlation.
```

```sql
-- Monthly priority advisor movement time series
WITH priority_moves AS (
    SELECT
        id.advisor_crd,
        id.inferred_departure_date,
        id.departed_firm_crd,
        id.departed_firm_name,
        id.new_firm_crd,
        id.new_firm_name,
        c.PRODUCING_ADVISOR,
        c.TITLE_NAME
    FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis` id
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON id.advisor_crd = c.RIA_CONTACT_CRD_ID
    WHERE c.PRODUCING_ADVISOR = TRUE
      AND UPPER(c.TITLE_NAME) NOT LIKE '%INSURANCE%'
)

SELECT
    DATE_TRUNC(inferred_departure_date, MONTH) as month,
    COUNT(DISTINCT advisor_crd) as priority_advisor_moves,
    COUNT(DISTINCT departed_firm_crd) as firms_losing_priority,
    COUNT(DISTINCT new_firm_crd) as firms_gaining_priority
FROM priority_moves
GROUP BY 1
ORDER BY 1;
```

---

## PHASE 7: Seasonality and Economic Correlation Prep

### Prompt 7.1: Monthly Movement Seasonality

```
Analyze seasonality in advisor movement to inform the predictive model.
```

```sql
-- Seasonality analysis for advisor movement
WITH monthly_moves AS (
    SELECT
        DATE_TRUNC(inferred_departure_date, MONTH) as month,
        EXTRACT(MONTH FROM inferred_departure_date) as month_of_year,
        EXTRACT(QUARTER FROM inferred_departure_date) as quarter,
        EXTRACT(YEAR FROM inferred_departure_date) as year,
        COUNT(DISTINCT advisor_crd) as moves
    FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis`
    WHERE inferred_departure_date >= '2023-01-01'
      AND inferred_departure_date <= '2025-10-31'
    GROUP BY 1, 2, 3, 4
),

-- Calculate seasonal index
seasonal_avg AS (
    SELECT
        month_of_year,
        AVG(moves) as avg_moves_for_month,
        (SELECT AVG(moves) FROM monthly_moves) as overall_avg
    FROM monthly_moves
    GROUP BY 1
)

SELECT
    month_of_year,
    ROUND(avg_moves_for_month, 0) as avg_monthly_moves,
    ROUND(avg_moves_for_month * 100.0 / overall_avg, 1) as seasonal_index,
    CASE 
        WHEN avg_moves_for_month * 100.0 / overall_avg > 115 THEN '🔥 PEAK'
        WHEN avg_moves_for_month * 100.0 / overall_avg > 100 THEN '📈 ABOVE AVG'
        WHEN avg_moves_for_month * 100.0 / overall_avg > 85 THEN '📊 AVERAGE'
        ELSE '❄️ SLOW'
    END as classification
FROM seasonal_avg
ORDER BY month_of_year;
```

### Prompt 7.2: Export Economic Correlation Dataset

```
Create the final dataset for economic correlation analysis.
```

```sql
-- Final dataset for economic correlation (export this)
WITH monthly_metrics AS (
    SELECT
        DATE_TRUNC(inferred_departure_date, MONTH) as month,
        COUNT(DISTINCT advisor_crd) as total_moves,
        COUNT(DISTINCT departed_firm_crd) as firms_losing,
        COUNT(DISTINCT new_firm_crd) as firms_gaining
    FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis`
    WHERE inferred_departure_date >= '2023-01-01'
    GROUP BY 1
),

with_changes AS (
    SELECT
        month,
        total_moves,
        firms_losing,
        firms_gaining,
        LAG(total_moves) OVER (ORDER BY month) as prev_month_moves,
        LAG(firms_losing) OVER (ORDER BY month) as prev_month_losing
    FROM monthly_metrics
)

SELECT
    month,
    total_moves,
    firms_losing,
    firms_gaining,
    EXTRACT(MONTH FROM month) as month_of_year,
    EXTRACT(QUARTER FROM month) as quarter,
    EXTRACT(YEAR FROM month) as year,
    ROUND((total_moves - prev_month_moves) * 100.0 / NULLIF(prev_month_moves, 0), 2) as moves_mom_pct,
    -- Year-over-year change (lag 12 months)
    LAG(total_moves, 12) OVER (ORDER BY month) as yoy_moves,
    ROUND((total_moves - LAG(total_moves, 12) OVER (ORDER BY month)) * 100.0 / 
          NULLIF(LAG(total_moves, 12) OVER (ORDER BY month), 0), 2) as moves_yoy_pct
FROM with_changes
ORDER BY month;
```

---

## PHASE 8: Compile Final Report

### Prompt 8.1: Generate Comprehensive Report

```
Compile all findings into `final_bleed_analysis.md`. The report should include:

1. **Executive Summary**
   - Validation of inferred departure approach
   - Key finding: Does bleeding correlate with conversion once corrected?
   - Recommended changes to V3.2 and V4

2. **Inferred Departure Validation**
   - Match rate (% of starters with identifiable prior employer)
   - Accuracy (gap between inferred and actual END_DATE)
   - Coverage gaps (retirees, industry leavers)

3. **Conversion Analysis (Corrected)**
   - OLD method: Bleeding category conversion rates
   - NEW method: Bleeding category conversion rates (corrected)
   - COMPARISON: Side-by-side table
   - Correlation coefficients (OLD vs NEW)

4. **Tier Impact Analysis**
   - Leads that changed tiers with corrected signal
   - Tier performance comparison (OLD vs NEW)
   - Expected conversion lift from using corrected signal

5. **Priority Advisor Patterns**
   - ICP advisor mobility distribution
   - Monthly movement time series
   - Firms gaining/losing priority advisors

6. **Seasonality Findings**
   - Monthly seasonal index
   - Peak vs slow periods
   - Recommendations for outreach timing

7. **Recommendations**
   - V3.2 SQL updates required
   - V4 feature engineering changes
   - New views/tables to create in BigQuery
   - Follow-up with FINTRX (Amy's table)

8. **Appendix: Production SQL**
   - Inferred departures query
   - Corrected firm bleeding view
   - Priority advisor identification query

Save to repository root: `final_bleed_analysis.md`
```

---

## Summary: What This Analysis Will Answer

| Question | Phase |
|----------|-------|
| Can we reliably infer departures from START_DATE? | 1 |
| How accurate is the inference vs actual END_DATE? | 1 |
| Does corrected bleeding signal flip the conversion correlation? | 3 |
| How many leads were misclassified by old method? | 3, 4 |
| Which firms are bleeding that we previously missed? | 2 |
| How do V3 tiers change with corrected signal? | 5 |
| What are priority advisor movement patterns? | 6 |
| What's the seasonality pattern for movement? | 7 |

**Ultimate Goal:** Determine if firm bleeding SHOULD be a positive signal in lead scoring (when measured correctly), and provide production-ready SQL for V3.2 and V4 updates.
