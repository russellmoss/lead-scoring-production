# Advisor Movement (Bleeding/Gaining) Data Exploration

## Cursor.ai MCP BigQuery Exploration Prompts

**Purpose:** Systematically explore BigQuery data to understand the optimal approach for monitoring advisor movement (bleeding and gaining firms) with the most rapid and accurate signals.

**Background Context:**
- FINTRX employment data has a ~115-day backfill lag (recent months are incomplete)
- Amy at FINTRX mentioned they have a month-over-month aggregation table used internally for tracking rep movements
- Current approach using `contact_registered_employment_history` may be missing recent movement signals
- We need to determine the best method to monitor advisor movement for our lead scoring and predictive models

**Output:** After completing all phases, compile results into `bleeding_exploration.md`

---

## PHASE 0: Setup and Prerequisites

### Prompt 0.1: Connect to BigQuery and Verify Access

```
Connect to our BigQuery instance and verify access to the following tables in the `savvy-gtm-analytics.FinTrx_data_CA` dataset:

1. contact_registered_employment_history
2. ria_contacts_current
3. Firm_historicals
4. ria_firms_current

Also check if there are any NEW tables that might be named something like:
- rep_movements
- advisor_movements
- monthly_movements
- contact_movements
- employment_movements
- rep_transitions
- advisor_transitions

List all tables in the dataset and highlight any that look like they might contain aggregated movement data (this would be the new table Amy from FINTRX mentioned they use internally).

Run this SQL to list all tables:
```sql
SELECT table_name, creation_time, row_count
FROM `savvy-gtm-analytics.FinTrx_data_CA.INFORMATION_SCHEMA.TABLES`
ORDER BY creation_time DESC;
```

### Prompt 0.2: Document Schema of Movement-Related Tables

```
For each movement-related table found, document the full schema:

```sql
-- For contact_registered_employment_history
SELECT column_name, data_type, is_nullable
FROM `savvy-gtm-analytics.FinTrx_data_CA.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'contact_registered_employment_history'
ORDER BY ordinal_position;
```

Also run for any new movement tables discovered in 0.1.

Document:
- All date fields (START_DATE, END_DATE variants)
- All identifier fields (CRD IDs, firm IDs)
- Any status or type fields
- Any aggregation fields (counts, rates, etc.)
```

---

## PHASE 1: Data Freshness Analysis

### Prompt 1.1: Quantify the Data Lag Pattern

```
Run a comprehensive analysis of data freshness in contact_registered_employment_history to understand the backfill lag pattern. We need to know:

1. How complete is data for each month going back 12 months?
2. What is the actual lag (in days) for data to become ~90% complete?
3. Is the lag consistent across firm types/sizes?

Execute:

```sql
-- Monthly data completeness analysis
WITH monthly_counts AS (
    SELECT 
        DATE_TRUNC(PREVIOUS_REGISTRATION_COMPANY_END_DATE, MONTH) as end_month,
        COUNT(*) as record_count,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as unique_advisors,
        COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID) as unique_firms
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
),
avg_baseline AS (
    SELECT AVG(record_count) as avg_count
    FROM monthly_counts
    WHERE end_month <= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
)
SELECT 
    mc.end_month,
    mc.record_count,
    mc.unique_advisors,
    mc.unique_firms,
    ROUND(mc.record_count * 100.0 / ab.avg_count, 1) as pct_of_baseline,
    DATE_DIFF(CURRENT_DATE(), mc.end_month, DAY) as days_ago
FROM monthly_counts mc
CROSS JOIN avg_baseline ab
ORDER BY mc.end_month DESC;
```

Document the results in a table showing completeness by month.
```

### Prompt 1.2: Analyze Start Date vs End Date Reliability

```
Compare START_DATE and END_DATE patterns to understand which is more reliable for real-time detection:

```sql
-- Compare start dates vs end dates timing
WITH date_comparison AS (
    SELECT
        DATE_TRUNC(PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) as start_month,
        DATE_TRUNC(PREVIOUS_REGISTRATION_COMPANY_END_DATE, MONTH) as end_month,
        COUNT(*) as records,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as advisors
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH)
       OR PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH)
    GROUP BY 1, 2
)
SELECT 
    start_month,
    SUM(CASE WHEN start_month = end_month THEN records ELSE 0 END) as same_month_transitions,
    SUM(records) as total_with_start,
    COUNT(DISTINCT end_month) as distinct_end_months
FROM date_comparison
WHERE start_month IS NOT NULL
GROUP BY 1
ORDER BY 1 DESC
LIMIT 24;
```

Hypothesis: START_DATE may be more reliable for detecting arrivals (less backfill dependency) than END_DATE is for detecting departures.
```

### Prompt 1.3: Compare ria_contacts_current START_DATE Freshness

```
Check if PRIMARY_FIRM_START_DATE in ria_contacts_current has different freshness characteristics:

```sql
-- Freshness of current firm start dates
WITH start_date_freshness AS (
    SELECT
        DATE_TRUNC(PRIMARY_FIRM_START_DATE, MONTH) as start_month,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as new_arrivals,
        DATE_DIFF(CURRENT_DATE(), DATE_TRUNC(PRIMARY_FIRM_START_DATE, MONTH), DAY) as days_ago
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH)
      AND PRIMARY_FIRM_START_DATE IS NOT NULL
    GROUP BY 1
)
SELECT 
    start_month,
    new_arrivals,
    days_ago,
    -- Compare to baseline (6+ month avg)
    ROUND(new_arrivals * 100.0 / (
        SELECT AVG(new_arrivals) 
        FROM start_date_freshness 
        WHERE days_ago >= 180
    ), 1) as pct_of_baseline
FROM start_date_freshness
ORDER BY start_month DESC;
```

This tests whether "arrivals" data (START dates) is fresher than "departures" data (END dates).
```

---

## PHASE 2: Alternative Approaches to Movement Detection

### Prompt 2.1: Method A - Departure-Based (Current Approach)

```
Document the current approach using END_DATE for departures. Calculate firm bleeding using this method:

```sql
-- Method A: Departure-based bleeding (current approach)
WITH departures_by_firm AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        DATE_TRUNC(PREVIOUS_REGISTRATION_COMPANY_END_DATE, MONTH) as departure_month,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1, 2
),
firm_context AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_headcount
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
    HAVING COUNT(DISTINCT RIA_CONTACT_CRD_ID) >= 10  -- Minimum firm size
)
SELECT
    d.departure_month,
    COUNT(DISTINCT d.firm_crd) as firms_with_departures,
    SUM(d.departures) as total_departures,
    AVG(d.departures * 100.0 / fc.current_headcount) as avg_turnover_rate
FROM departures_by_firm d
JOIN firm_context fc ON d.firm_crd = fc.firm_crd
GROUP BY 1
ORDER BY 1 DESC;
```

Note the data completeness issue - recent months will be artificially low.
```

### Prompt 2.2: Method B - Arrival-Based Detection (Alternative Approach)

```
Test using START_DATE for arrivals to identify "gaining" firms (potentially fresher data):

```sql
-- Method B: Arrival-based gaining detection
WITH arrivals_by_firm AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        DATE_TRUNC(PRIMARY_FIRM_START_DATE, MONTH) as arrival_month,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1, 2
),
firm_context AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_headcount
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
    HAVING COUNT(DISTINCT RIA_CONTACT_CRD_ID) >= 10
)
SELECT
    a.arrival_month,
    COUNT(DISTINCT a.firm_crd) as firms_with_arrivals,
    SUM(a.arrivals) as total_arrivals,
    AVG(a.arrivals * 100.0 / fc.current_headcount) as avg_growth_rate
FROM arrivals_by_firm a
JOIN firm_context fc ON a.firm_crd = fc.firm_crd
GROUP BY 1
ORDER BY 1 DESC;
```

Compare data completeness to Method A (departures). Arrivals may be fresher.
```

### Prompt 2.3: Method C - Net Flow Calculation

```
Calculate net advisor flow (arrivals - departures) with lag adjustment:

```sql
-- Method C: Net flow with data lag adjustment
WITH firm_arrivals AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PRIMARY_FIRM_START_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 115 DAY)  -- 115-day lag buffer
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),
firm_departures AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 115 DAY)  -- 115-day lag buffer
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
),
firm_context AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_headcount,
        f.NAME as firm_name
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current` f
        ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = f.CRD_ID
    WHERE c.PRIMARY_FIRM IS NOT NULL
    GROUP BY 1, 3
    HAVING COUNT(DISTINCT RIA_CONTACT_CRD_ID) >= 20
)
SELECT
    fc.firm_crd,
    fc.firm_name,
    fc.current_headcount,
    COALESCE(fa.arrivals_12mo, 0) as arrivals,
    COALESCE(fd.departures_12mo, 0) as departures,
    COALESCE(fa.arrivals_12mo, 0) - COALESCE(fd.departures_12mo, 0) as net_change,
    CASE
        WHEN COALESCE(fa.arrivals_12mo, 0) - COALESCE(fd.departures_12mo, 0) <= -10 THEN 'HEAVY_BLEEDING'
        WHEN COALESCE(fa.arrivals_12mo, 0) - COALESCE(fd.departures_12mo, 0) < 0 THEN 'BLEEDING'
        WHEN COALESCE(fa.arrivals_12mo, 0) - COALESCE(fd.departures_12mo, 0) > 10 THEN 'HEAVY_GAINING'
        WHEN COALESCE(fa.arrivals_12mo, 0) - COALESCE(fd.departures_12mo, 0) > 0 THEN 'GAINING'
        ELSE 'STABLE'
    END as movement_status
FROM firm_context fc
LEFT JOIN firm_arrivals fa ON fc.firm_crd = fa.firm_crd
LEFT JOIN firm_departures fd ON fc.firm_crd = fd.firm_crd
ORDER BY net_change ASC
LIMIT 50;
```

This shows the top bleeding firms with lag adjustment.
```

### Prompt 2.4: Method D - Month-over-Month Headcount Delta

```
Test using Firm_historicals monthly snapshots for headcount changes:

```sql
-- Method D: Monthly headcount delta from Firm_historicals
WITH monthly_headcount AS (
    SELECT 
        RIA_INVESTOR_CRD_ID as firm_crd,
        NAME as firm_name,
        YEAR,
        MONTH,
        -- Use EMPLOYEE_COUNT or calculate from associated contacts
        EMPLOYEE_COUNT as headcount,
        DATE(YEAR, MONTH, 1) as snapshot_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.Firm_historicals`
    WHERE YEAR >= 2024
),
headcount_changes AS (
    SELECT
        curr.firm_crd,
        curr.firm_name,
        curr.snapshot_date as current_month,
        prev.snapshot_date as previous_month,
        curr.headcount as current_headcount,
        prev.headcount as previous_headcount,
        curr.headcount - prev.headcount as monthly_change,
        ROUND((curr.headcount - prev.headcount) * 100.0 / NULLIF(prev.headcount, 0), 2) as pct_change
    FROM monthly_headcount curr
    LEFT JOIN monthly_headcount prev
        ON curr.firm_crd = prev.firm_crd
        AND DATE_SUB(curr.snapshot_date, INTERVAL 1 MONTH) = prev.snapshot_date
    WHERE curr.headcount IS NOT NULL
      AND prev.headcount IS NOT NULL
)
SELECT 
    snapshot_date,
    COUNT(DISTINCT firm_crd) as firms_measured,
    AVG(monthly_change) as avg_monthly_change,
    SUM(CASE WHEN monthly_change < -5 THEN 1 ELSE 0 END) as bleeding_firms,
    SUM(CASE WHEN monthly_change > 5 THEN 1 ELSE 0 END) as gaining_firms
FROM (
    SELECT firm_crd, firm_name, current_month as snapshot_date, monthly_change
    FROM headcount_changes
)
GROUP BY 1
ORDER BY 1 DESC
LIMIT 12;
```

Compare this to employment_history-based methods. Which gives fresher/more reliable signals?
```

---

## PHASE 3: Exploring the New FINTRX Table (If Available)

### Prompt 3.1: Investigate New Movement Table

```
Amy at FINTRX mentioned they have a month-over-month aggregation table for rep movements. Search for this table:

```sql
-- Search for movement-related tables
SELECT 
    table_name,
    creation_time,
    last_modified_time,
    row_count,
    size_bytes / 1024 / 1024 as size_mb
FROM `savvy-gtm-analytics.FinTrx_data_CA.INFORMATION_SCHEMA.TABLES`
WHERE LOWER(table_name) LIKE '%move%'
   OR LOWER(table_name) LIKE '%transition%'
   OR LOWER(table_name) LIKE '%month%'
   OR LOWER(table_name) LIKE '%aggregat%'
   OR LOWER(table_name) LIKE '%rep_change%'
   OR LOWER(table_name) LIKE '%flow%'
ORDER BY creation_time DESC;
```

If found, document the full schema and sample data. This table should have:
- Month-over-month tracking
- Pre-aggregated movement counts
- Potentially fresher data than employment_history
```

### Prompt 3.2: Compare New Table to Employment History

```
If a new movement table was found, compare its data freshness and coverage:

```sql
-- Compare record counts by month between employment_history and new table
-- Replace NEW_TABLE_NAME with actual table name if found

-- First, get employment history monthly counts
WITH emp_history_counts AS (
    SELECT
        DATE_TRUNC(PREVIOUS_REGISTRATION_COMPANY_END_DATE, MONTH) as month,
        COUNT(*) as emp_history_records,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as emp_history_advisors
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= '2024-01-01'
    GROUP BY 1
)
SELECT *
FROM emp_history_counts
ORDER BY month DESC;

-- Run equivalent query on new table when found
```

Document:
- Does the new table have more recent data?
- Is it pre-aggregated at firm level?
- What additional fields does it provide?
```

---

## PHASE 4: Signal Timeliness Analysis

### Prompt 4.1: Time-to-Detection Analysis

```
For advisors who moved, how long does it take for the movement to appear in our data?

```sql
-- Time-to-detection analysis
-- Compares when movements happened vs when data was likely available

WITH recent_movements AS (
    SELECT
        RIA_CONTACT_CRD_ID,
        PREVIOUS_REGISTRATION_COMPANY_END_DATE as departure_date,
        PREVIOUS_REGISTRATION_COMPANY_START_DATE as new_role_start,
        -- Try to identify when this record was created/updated
        PREVIOUS_REGISTRATION_COMPANY_CRD_ID as old_firm,
        -- The gap between end of old role and start of new role
        DATE_DIFF(
            LEAD(PREVIOUS_REGISTRATION_COMPANY_START_DATE) OVER (
                PARTITION BY RIA_CONTACT_CRD_ID 
                ORDER BY PREVIOUS_REGISTRATION_COMPANY_START_DATE
            ),
            PREVIOUS_REGISTRATION_COMPANY_END_DATE,
            DAY
        ) as gap_days
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= '2024-01-01'
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
)
SELECT
    DATE_TRUNC(departure_date, MONTH) as departure_month,
    COUNT(*) as total_departures,
    COUNT(CASE WHEN gap_days IS NOT NULL THEN 1 END) as with_next_role,
    AVG(gap_days) as avg_gap_days,
    PERCENTILE_CONT(gap_days, 0.5) OVER (PARTITION BY DATE_TRUNC(departure_date, MONTH)) as median_gap_days
FROM recent_movements
GROUP BY 1
ORDER BY 1 DESC
LIMIT 12;
```

This helps understand the typical delay in detecting movements.
```

### Prompt 4.2: Arrival Signal Lead Time

```
Test if arrival signals (new firm START_DATE) appear faster than departure signals:

```sql
-- Compare timing of arrivals vs departures for same advisors
WITH advisor_transitions AS (
    SELECT
        c.RIA_CONTACT_CRD_ID as advisor_crd,
        c.PRIMARY_FIRM_START_DATE as current_firm_start,  -- Arrival at new firm
        eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE as old_firm_end,  -- Departure from old firm
        DATE_DIFF(
            c.PRIMARY_FIRM_START_DATE,
            eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
            DAY
        ) as transition_gap
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON c.RIA_CONTACT_CRD_ID = eh.RIA_CONTACT_CRD_ID
    WHERE c.PRIMARY_FIRM_START_DATE >= '2024-06-01'
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= '2024-01-01'
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < c.PRIMARY_FIRM_START_DATE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.RIA_CONTACT_CRD_ID 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE DESC
    ) = 1
)
SELECT
    DATE_TRUNC(current_firm_start, MONTH) as month,
    COUNT(*) as transitions,
    AVG(transition_gap) as avg_gap,
    COUNT(CASE WHEN transition_gap <= 30 THEN 1 END) as quick_transitions,
    COUNT(CASE WHEN transition_gap > 90 THEN 1 END) as delayed_detection
FROM advisor_transitions
GROUP BY 1
ORDER BY 1 DESC;
```

If arrival signals (PRIMARY_FIRM_START_DATE) appear before or simultaneously with departure signals, we should weight arrivals more heavily for real-time detection.
```

---

## PHASE 5: Optimal Time Window Analysis

### Prompt 5.1: Test Different Lookback Windows

```
Test which lookback window provides the best signal (accounting for data lag):

```sql
-- Compare different lookback windows for firm bleeding signal
WITH firm_base AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_headcount
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
    HAVING COUNT(DISTINCT RIA_CONTACT_CRD_ID) >= 20
),
departures_30d AS (
    SELECT firm_crd, COUNT(DISTINCT advisor_crd) as departures
    FROM (
        SELECT 
            SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
            RIA_CONTACT_CRD_ID as advisor_crd
        FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
        WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < CURRENT_DATE()
    )
    GROUP BY 1
),
departures_90d AS (
    SELECT firm_crd, COUNT(DISTINCT advisor_crd) as departures
    FROM (
        SELECT 
            SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
            RIA_CONTACT_CRD_ID as advisor_crd
        FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
        WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
          AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < CURRENT_DATE()
    )
    GROUP BY 1
),
departures_180d AS (
    SELECT firm_crd, COUNT(DISTINCT advisor_crd) as departures
    FROM (
        SELECT 
            SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
            RIA_CONTACT_CRD_ID as advisor_crd
        FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
        WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
          AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < CURRENT_DATE()
    )
    GROUP BY 1
),
departures_365d AS (
    SELECT firm_crd, COUNT(DISTINCT advisor_crd) as departures
    FROM (
        SELECT 
            SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
            RIA_CONTACT_CRD_ID as advisor_crd
        FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
        WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
          AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < CURRENT_DATE()
    )
    GROUP BY 1
)
SELECT
    fb.firm_crd,
    fb.current_headcount,
    COALESCE(d30.departures, 0) as departures_30d,
    COALESCE(d90.departures, 0) as departures_90d,
    COALESCE(d180.departures, 0) as departures_180d,
    COALESCE(d365.departures, 0) as departures_365d,
    -- Calculate rates
    ROUND(COALESCE(d30.departures, 0) * 100.0 / fb.current_headcount, 2) as rate_30d,
    ROUND(COALESCE(d90.departures, 0) * 100.0 / fb.current_headcount, 2) as rate_90d,
    ROUND(COALESCE(d180.departures, 0) * 100.0 / fb.current_headcount, 2) as rate_180d,
    ROUND(COALESCE(d365.departures, 0) * 100.0 / fb.current_headcount, 2) as rate_365d
FROM firm_base fb
LEFT JOIN departures_30d d30 ON fb.firm_crd = d30.firm_crd
LEFT JOIN departures_90d d90 ON fb.firm_crd = d90.firm_crd
LEFT JOIN departures_180d d180 ON fb.firm_crd = d180.firm_crd
LEFT JOIN departures_365d d365 ON fb.firm_crd = d365.firm_crd
ORDER BY COALESCE(d365.departures, 0) DESC
LIMIT 100;
```

Document which window provides the most reliable signal given data lag.
```

### Prompt 5.2: Lag-Adjusted Window Comparison

```
Compare windows WITH the 115-day lag adjustment vs WITHOUT:

```sql
-- Compare raw vs lag-adjusted window effectiveness
WITH firm_departures_raw AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_90d_raw
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
),
firm_departures_lagged AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_90d_lagged
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 205 DAY)  -- 90 + 115 day lag
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 115 DAY)   -- End 115 days ago
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
),
firm_context AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_headcount
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
    HAVING COUNT(DISTINCT RIA_CONTACT_CRD_ID) >= 20
)
SELECT
    fc.firm_crd,
    fc.current_headcount,
    COALESCE(raw.departures_90d_raw, 0) as departures_raw,
    COALESCE(lag.departures_90d_lagged, 0) as departures_lagged,
    COALESCE(lag.departures_90d_lagged, 0) - COALESCE(raw.departures_90d_raw, 0) as difference,
    CASE 
        WHEN COALESCE(lag.departures_90d_lagged, 0) >= 5 AND COALESCE(raw.departures_90d_raw, 0) <= 2 
        THEN 'SIGNAL_MISSED'
        ELSE 'OK'
    END as status
FROM firm_context fc
LEFT JOIN firm_departures_raw raw ON fc.firm_crd = raw.firm_crd
LEFT JOIN firm_departures_lagged lag ON fc.firm_crd = lag.firm_crd
WHERE COALESCE(raw.departures_90d_raw, 0) > 0 OR COALESCE(lag.departures_90d_lagged, 0) > 0
ORDER BY difference DESC
LIMIT 50;
```

This shows firms where the raw 90-day window misses bleeding signal that the lag-adjusted window catches.
```

---

## PHASE 6: Build Recommended Monitoring Approach

### Prompt 6.1: Create Composite Signal

```
Based on findings, create a composite signal using the best combination of methods:

```sql
-- Recommended composite movement signal
CREATE OR REPLACE VIEW `savvy-gtm-analytics.FinTrx_data_CA.v_firm_movement_signals` AS

WITH firm_arrivals_fresh AS (
    -- Arrivals from ria_contacts_current (fresher data, START dates)
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_90d
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),
firm_departures_lagged AS (
    -- Departures with 115-day lag adjustment (more complete data)
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_adjusted
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 205 DAY)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 115 DAY)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
),
firm_context AS (
    SELECT 
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
        f.NAME as firm_name,
        COUNT(DISTINCT c.RIA_CONTACT_CRD_ID) as current_headcount,
        f.TOTAL_AUM as firm_aum
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current` f
        ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = f.CRD_ID
    WHERE c.PRIMARY_FIRM IS NOT NULL
    GROUP BY 1, 2, 4
)
SELECT
    fc.firm_crd,
    fc.firm_name,
    fc.current_headcount,
    fc.firm_aum,
    
    -- Fresh arrival signal (90d, minimal lag)
    COALESCE(fa.arrivals_90d, 0) as arrivals_fresh_90d,
    
    -- Lag-adjusted departure signal (90d window, 115d lag)
    COALESCE(fd.departures_adjusted, 0) as departures_adjusted_90d,
    
    -- Net movement composite
    COALESCE(fa.arrivals_90d, 0) - COALESCE(fd.departures_adjusted, 0) as net_movement,
    
    -- Movement rates
    ROUND(COALESCE(fa.arrivals_90d, 0) * 100.0 / NULLIF(fc.current_headcount, 0), 2) as arrival_rate,
    ROUND(COALESCE(fd.departures_adjusted, 0) * 100.0 / NULLIF(fc.current_headcount, 0), 2) as departure_rate_adjusted,
    
    -- Categorical signals
    CASE
        WHEN COALESCE(fd.departures_adjusted, 0) >= 10 THEN 'HEAVY_BLEEDING'
        WHEN COALESCE(fd.departures_adjusted, 0) >= 5 THEN 'BLEEDING'
        WHEN COALESCE(fa.arrivals_90d, 0) >= 10 THEN 'HEAVY_GAINING'
        WHEN COALESCE(fa.arrivals_90d, 0) >= 5 THEN 'GAINING'
        ELSE 'STABLE'
    END as movement_status,
    
    -- Signal freshness indicator
    CASE
        WHEN COALESCE(fa.arrivals_90d, 0) > 0 THEN 'FRESH_SIGNAL'
        WHEN COALESCE(fd.departures_adjusted, 0) > 0 THEN 'LAGGED_SIGNAL'
        ELSE 'NO_SIGNAL'
    END as signal_freshness,
    
    CURRENT_DATE() as snapshot_date

FROM firm_context fc
LEFT JOIN firm_arrivals_fresh fa ON fc.firm_crd = fa.firm_crd
LEFT JOIN firm_departures_lagged fd ON fc.firm_crd = fd.firm_crd
WHERE fc.current_headcount >= 10;
```

This creates a view combining fresh arrival signals with lag-adjusted departure signals.
```

### Prompt 6.2: Create Monitoring Dashboard Query

```
Create a query for monitoring advisor movement trends over time:

```sql
-- Weekly movement monitoring dashboard
WITH weekly_stats AS (
    SELECT
        DATE_TRUNC(PREVIOUS_REGISTRATION_COMPANY_END_DATE, WEEK) as week,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures,
        COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID) as firms_affected
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 115 DAY)  -- Lag buffer
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
),
weekly_arrivals AS (
    SELECT
        DATE_TRUNC(PRIMARY_FIRM_START_DATE, WEEK) as week,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
)
SELECT
    ws.week,
    ws.departures,
    ws.firms_affected,
    COALESCE(wa.arrivals, 0) as arrivals,
    COALESCE(wa.arrivals, 0) - ws.departures as net_flow,
    -- Rolling 4-week average
    AVG(ws.departures) OVER (ORDER BY ws.week ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) as departures_4wk_avg,
    AVG(COALESCE(wa.arrivals, 0)) OVER (ORDER BY ws.week ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) as arrivals_4wk_avg
FROM weekly_stats ws
LEFT JOIN weekly_arrivals wa ON ws.week = wa.week
ORDER BY ws.week DESC;
```

Use this to track market-wide movement trends for the predictive model.
```

---

## PHASE 7: Correlation with Economic Metrics

### Prompt 7.1: Prepare Movement Data for Economic Correlation

```
Create a monthly time series of advisor movement for correlation with economic indicators:

```sql
-- Monthly advisor movement time series (for economic correlation)
WITH monthly_movements AS (
    SELECT
        DATE_TRUNC(PREVIOUS_REGISTRATION_COMPANY_END_DATE, MONTH) as month,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as total_moves,
        COUNT(DISTINCT CASE 
            WHEN PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL 
            THEN PREVIOUS_REGISTRATION_COMPANY_CRD_ID 
        END) as firms_losing_advisors
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= '2022-01-01'
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 115 DAY)
    GROUP BY 1
),
monthly_arrivals AS (
    SELECT
        DATE_TRUNC(PRIMARY_FIRM_START_DATE, MONTH) as month,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= '2022-01-01'
    GROUP BY 1
),
-- Calculate month-over-month changes
movement_series AS (
    SELECT
        mm.month,
        mm.total_moves as departures,
        COALESCE(ma.arrivals, 0) as arrivals,
        mm.firms_losing_advisors,
        LAG(mm.total_moves) OVER (ORDER BY mm.month) as prev_month_moves,
        LAG(COALESCE(ma.arrivals, 0)) OVER (ORDER BY mm.month) as prev_month_arrivals
    FROM monthly_movements mm
    LEFT JOIN monthly_arrivals ma ON mm.month = ma.month
)
SELECT
    month,
    departures,
    arrivals,
    departures - arrivals as net_outflow,
    firms_losing_advisors,
    ROUND((departures - prev_month_moves) * 100.0 / NULLIF(prev_month_moves, 0), 2) as departure_mom_change_pct,
    ROUND((arrivals - prev_month_arrivals) * 100.0 / NULLIF(prev_month_arrivals, 0), 2) as arrival_mom_change_pct,
    -- Seasonality indicators
    EXTRACT(MONTH FROM month) as month_of_year,
    EXTRACT(QUARTER FROM month) as quarter
FROM movement_series
WHERE month >= '2022-01-01'
ORDER BY month;
```

Export this data for correlation analysis with:
- S&P 500 performance
- Interest rate changes
- RIA industry AUM trends
- Unemployment rate
```

---

## PHASE 8: Compile Findings Document

### Prompt 8.1: Generate Final Report

```
Compile all findings from Phases 1-7 into a comprehensive markdown document called `bleeding_exploration.md`. The document should include:

1. **Executive Summary**
   - Key findings about data freshness
   - Recommended approach for monitoring bleeding/gaining
   - Critical caveats and limitations

2. **Data Freshness Analysis**
   - 115-day lag quantification
   - Comparison of START_DATE vs END_DATE reliability
   - Monthly data completeness charts

3. **Method Comparison**
   - Method A: Departure-based (current)
   - Method B: Arrival-based (alternative)
   - Method C: Net flow (hybrid)
   - Method D: Firm_historicals headcount delta
   - Winner and rationale

4. **New FINTRX Table Analysis**
   - If found: Schema, coverage, freshness comparison
   - If not found: Recommendation to request from Amy

5. **Optimal Configuration**
   - Recommended time window
   - Lag adjustment settings
   - Composite signal definition

6. **SQL Templates**
   - Production-ready queries for monitoring
   - View definitions for dashboards

7. **Economic Correlation Preparation**
   - Monthly time series data
   - Suggested economic indicators to correlate
   - Analysis approach for predictive model

8. **Action Items**
   - Follow up with FINTRX on month-over-month table
   - Update V3 lead scoring with new signals
   - Build predictive model for advisor movement

Save the document to the repository root directory.
```

---

## SQL Helper Functions

### Commonly Used CTEs

```sql
-- Firm headcount baseline
firm_headcount AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_reps
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
)

-- Firm departures (with optional lag adjustment)
firm_departures AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL {WINDOW} DAY)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL {LAG} DAY)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
)

-- Firm arrivals (fresher signal)
firm_arrivals AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL {WINDOW} DAY)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
)
```

---

## Variables to Configure

| Variable | Default | Description |
|----------|---------|-------------|
| `{WINDOW}` | 90 | Lookback window in days |
| `{LAG}` | 115 | Data lag buffer in days |
| `{MIN_FIRM_SIZE}` | 10 | Minimum firm headcount to include |
| `{BLEEDING_THRESHOLD}` | 5 | Departures to flag as "bleeding" |
| `{HEAVY_BLEEDING_THRESHOLD}` | 10 | Departures to flag as "heavy bleeding" |

---

## Expected Outputs

After running all prompts, you should have:

1. `bleeding_exploration.md` - Complete analysis document
2. Data freshness charts showing the 115-day lag pattern
3. Method comparison with winner recommendation
4. Production-ready SQL queries for monitoring
5. Time series data for economic correlation model
6. Recommendations for V3/V4 lead scoring updates
