-- ============================================================================
-- V3.3 SYNTAX VERIFICATION TEST
-- ============================================================================
-- This query tests the V3.3 SQL for syntax errors by running a limited version
-- Replace placeholders and wrap in SELECT to verify compilation
-- ============================================================================

-- Syntax verification - limit to 100 rows
WITH full_query AS (
    -- Replace {TABLE_NAME}, {LEAD_LIMIT}, {RECYCLABLE_DAYS} with test values
    -- We'll use a CTE approach instead of CREATE TABLE for testing
    
WITH 
-- ============================================================================
-- A. EXCLUSIONS (Wirehouses)
-- ============================================================================
excluded_firms AS (
    SELECT firm_pattern FROM UNNEST([
        '%J.P. MORGAN%', '%MORGAN STANLEY%', '%MERRILL%', '%WELLS FARGO%', 
        '%UBS %', '%UBS,%', '%EDWARD JONES%', '%AMERIPRISE%', 
        '%NORTHWESTERN MUTUAL%', '%PRUDENTIAL%', '%RAYMOND JAMES%',
        '%FIDELITY%', '%SCHWAB%', '%VANGUARD%', '%GOLDMAN SACHS%', '%CITIGROUP%',
        '%LPL FINANCIAL%', '%COMMONWEALTH%', '%CETERA%', '%CAMBRIDGE%',
        '%OSAIC%', '%PRIMERICA%',
        '%STATE FARM%', '%ALLSTATE%', '%NEW YORK LIFE%', '%NYLIFE%',
        '%TRANSAMERICA%', '%FARM BUREAU%', '%NATIONWIDE%',
        '%LINCOLN FINANCIAL%', '%MASS MUTUAL%', '%MASSMUTUAL%'
    ]) as firm_pattern
),

-- ============================================================================
-- B. EXISTING SALESFORCE CRDs
-- ============================================================================
salesforce_crds AS (
    SELECT DISTINCT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE FA_CRD__c IS NOT NULL AND IsDeleted = false
),

-- ============================================================================
-- C. RECYCLABLE LEADS (180+ days no contact)
-- ============================================================================
lead_task_activity AS (
    SELECT 
        t.WhoId as lead_id,
        MAX(GREATEST(
            COALESCE(DATE(t.ActivityDate), DATE('1900-01-01')),
            COALESCE(DATE(t.CompletedDateTime), DATE('1900-01-01')),
            COALESCE(DATE(t.CreatedDate), DATE('1900-01-01'))
        )) as last_activity_date
    FROM `savvy-gtm-analytics.SavvyGTMData.Task` t
    WHERE t.IsDeleted = false AND t.WhoId IS NOT NULL
      AND (t.Type IN ('Outgoing SMS', 'Incoming SMS')
           OR UPPER(t.Subject) LIKE '%SMS%' OR UPPER(t.Subject) LIKE '%TEXT%'
           OR t.TaskSubtype = 'Call' OR t.Type = 'Call'
           OR UPPER(t.Subject) LIKE '%CALL%' OR t.CallType IS NOT NULL)
    GROUP BY t.WhoId
),

recyclable_lead_ids AS (
    SELECT l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN lead_task_activity la ON l.Id = la.lead_id
    WHERE l.IsDeleted = false AND l.FA_CRD__c IS NOT NULL
      AND (la.last_activity_date IS NULL OR DATE_DIFF(CURRENT_DATE(), la.last_activity_date, DAY) > 180)
      AND (l.DoNotCall IS NULL OR l.DoNotCall = false)
      AND l.Status NOT IN ('Closed', 'Converted', 'Dead', 'Unqualified', 'Disqualified', 
                           'Do Not Contact', 'Not Qualified', 'Bad Data', 'Duplicate')
),

-- ============================================================================
-- D. ADVISOR EMPLOYMENT HISTORY (For mobility metrics)
-- ============================================================================
advisor_moves AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID) as total_firms,
        COUNT(DISTINCT CASE 
            WHEN PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 YEAR)
            THEN PREVIOUS_REGISTRATION_COMPANY_CRD_ID END) as moves_3yr,
        MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE) as career_start_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    GROUP BY RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- E. FIRM HEADCOUNT (from ria_contacts_current)
-- ============================================================================
firm_headcount AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_reps
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY PRIMARY_FIRM
),

-- ============================================================================
-- F. FIRM DEPARTURES (12 months) - INFERRED from START_DATE at new firm
-- V3.3 UPDATE: Use PRIMARY_FIRM_START_DATE to infer departures 60-90 days faster
-- ============================================================================
firm_departures AS (
    SELECT
        SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT c.RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON c.RIA_CONTACT_CRD_ID = eh.RIA_CONTACT_CRD_ID
        AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != SAFE_CAST(c.PRIMARY_FIRM AS INT64)
    WHERE c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND c.PRIMARY_FIRM IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.RIA_CONTACT_CRD_ID 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
    GROUP BY 1
),

-- ============================================================================
-- F2. FIRM DEPARTURES - 90 DAY WINDOWS FOR VELOCITY CALCULATION
-- V3.3 UPDATE: Detect ACCELERATING bleeding
-- ============================================================================
firm_departures_velocity AS (
    SELECT
        SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT CASE 
            WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN c.RIA_CONTACT_CRD_ID 
        END) as departures_90d,
        COUNT(DISTINCT CASE 
            WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
                 AND c.PRIMARY_FIRM_START_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN c.RIA_CONTACT_CRD_ID 
        END) as departures_prior_90d
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON c.RIA_CONTACT_CRD_ID = eh.RIA_CONTACT_CRD_ID
        AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != SAFE_CAST(c.PRIMARY_FIRM AS INT64)
    WHERE c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
      AND c.PRIMARY_FIRM IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.RIA_CONTACT_CRD_ID 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
    GROUP BY 1
),

firm_arrivals AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

firm_metrics AS (
    SELECT
        h.firm_crd,
        h.current_reps as firm_rep_count,
        COALESCE(d.departures_12mo, 0) as departures_12mo,
        COALESCE(a.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(a.arrivals_12mo, 0) - COALESCE(d.departures_12mo, 0) as firm_net_change_12mo,
        CASE WHEN h.current_reps > 0 
             THEN COALESCE(d.departures_12mo, 0) * 100.0 / h.current_reps 
             ELSE 0 END as turnover_pct,
        COALESCE(dv.departures_90d, 0) as departures_90d,
        COALESCE(dv.departures_prior_90d, 0) as departures_prior_90d,
        CASE 
            WHEN COALESCE(dv.departures_prior_90d, 0) = 0 
                 AND COALESCE(dv.departures_90d, 0) >= 3 
            THEN 'ACCELERATING'
            WHEN COALESCE(dv.departures_90d, 0) > COALESCE(dv.departures_prior_90d, 0) * 1.5 
            THEN 'ACCELERATING'
            WHEN COALESCE(dv.departures_90d, 0) < COALESCE(dv.departures_prior_90d, 0) * 0.5 
            THEN 'DECELERATING'
            ELSE 'STEADY'
        END as bleeding_velocity
    FROM firm_headcount h
    LEFT JOIN firm_departures d ON h.firm_crd = d.firm_crd
    LEFT JOIN firm_departures_velocity dv ON h.firm_crd = dv.firm_crd
    LEFT JOIN firm_arrivals a ON h.firm_crd = a.firm_crd
    WHERE h.current_reps >= 20
),

base_prospects AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        c.CONTACT_FIRST_NAME as first_name,
        c.CONTACT_LAST_NAME as last_name,
        c.PRIMARY_FIRM_NAME as firm_name,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
        c.EMAIL as email,
        COALESCE(c.MOBILE_PHONE_NUMBER, c.OFFICE_PHONE_NUMBER) as phone,
        c.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        c.PRIMARY_FIRM_EMPLOYEE_COUNT as firm_employee_count,
        DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, MONTH) as tenure_months,
        DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, YEAR) as tenure_years,
        CASE WHEN sf.crd IS NULL THEN 'NEW_PROSPECT' ELSE 'IN_SALESFORCE' END as prospect_type,
        sf.lead_id as existing_lead_id
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN salesforce_crds sf ON c.RIA_CONTACT_CRD_ID = sf.crd
    WHERE c.CONTACT_FIRST_NAME IS NOT NULL AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM_START_DATE IS NOT NULL AND c.PRIMARY_FIRM_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern)
),

enriched_prospects AS (
    SELECT 
        bp.*,
        COALESCE(am.total_firms, 1) as total_firms,
        COALESCE(am.total_firms, 1) - 1 as num_prior_firms,
        COALESCE(am.moves_3yr, 0) as moves_3yr,
        DATE_DIFF(CURRENT_DATE(), am.career_start_date, YEAR) as industry_tenure_years,
        DATE_DIFF(CURRENT_DATE(), am.career_start_date, MONTH) as industry_tenure_months,
        COALESCE(fm.firm_rep_count, bp.firm_employee_count, 1) as firm_rep_count,
        COALESCE(fm.arrivals_12mo, 0) as firm_arrivals_12mo,
        COALESCE(fm.departures_12mo, 0) as firm_departures_12mo,
        COALESCE(fm.firm_net_change_12mo, 0) as firm_net_change_12mo,
        COALESCE(fm.turnover_pct, 0) as firm_turnover_pct,
        fm.departures_90d,
        fm.departures_prior_90d,
        fm.bleeding_velocity,
        CASE WHEN EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(bp.firm_name) LIKE ef.firm_pattern) THEN 1 ELSE 0 END as is_wirehouse,
        CASE WHEN c.CONTACT_BIO LIKE '%CFP%' 
             OR c.CONTACT_BIO LIKE '%Certified Financial Planner%'
             OR c.TITLE_NAME LIKE '%CFP%'
             THEN 1 ELSE 0 END as has_cfp,
        CASE WHEN c.REP_LICENSES LIKE '%Series 65%' 
             AND c.REP_LICENSES NOT LIKE '%Series 7%' 
             THEN 1 ELSE 0 END as has_series_65_only,
        CASE WHEN c.REP_LICENSES LIKE '%Series 7%' 
             THEN 1 ELSE 0 END as has_series_7,
        CASE WHEN c.CONTACT_BIO LIKE '%CFA%' 
             OR c.CONTACT_BIO LIKE '%Chartered Financial Analyst%'
             OR c.TITLE_NAME LIKE '%CFA%'
             THEN 1 ELSE 0 END as has_cfa
    FROM base_prospects bp
    LEFT JOIN advisor_moves am ON bp.crd = am.crd
    LEFT JOIN firm_metrics fm ON bp.firm_crd = fm.firm_crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c ON bp.crd = c.RIA_CONTACT_CRD_ID
    WHERE COALESCE(fm.turnover_pct, 0) < 100
),

scored_prospects AS (
    SELECT 
        ep.*,
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4
                  AND industry_tenure_years >= 5
                  AND firm_net_change_12mo < 0
                  AND has_cfp = 1
                  AND is_wirehouse = 0) THEN 'TIER_1A_PRIME_MOVER_CFP'
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 'TIER_1_PRIME_MOVER'
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 'TIER_2_PROVEN_MOVER'
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND bleeding_velocity = 'ACCELERATING'
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 'TIER_3A_ACCELERATING_BLEEDER'
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 'TIER_3_MODERATE_BLEEDER'
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 'TIER_4_EXPERIENCED_MOVER'
            ELSE 'STANDARD'
        END as score_tier,
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4
                  AND industry_tenure_years >= 5
                  AND firm_net_change_12mo < 0
                  AND has_cfp = 1
                  AND is_wirehouse = 0) THEN 1
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 2
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 3
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 4
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND bleeding_velocity = 'ACCELERATING'
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 5
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 6
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 7
            ELSE 8
        END as priority_rank,
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4
                  AND industry_tenure_years >= 5
                  AND firm_net_change_12mo < 0
                  AND has_cfp = 1
                  AND is_wirehouse = 0) THEN 0.1644
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 0.1648
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 0.1321
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 0.0859
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND bleeding_velocity = 'ACCELERATING'
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 0.0600
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN 0.0543
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 0.1154
            ELSE 0.0382
        END as expected_conversion_rate
    FROM enriched_prospects ep
),

ranked_prospects AS (
    SELECT 
        sp.*,
        CASE 
            WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 1
            WHEN sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids) THEN 2
            ELSE 99
        END as source_priority,
        (CASE WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 0 
              WHEN sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids) THEN 1000
              ELSE 9999 END)
        + (sp.priority_rank * 100)
        + (CASE WHEN sp.firm_net_change_12mo < 0 THEN ABS(sp.firm_net_change_12mo) ELSE 0 END * -1)
        as sort_score,
        ROW_NUMBER() OVER (
            PARTITION BY sp.firm_crd 
            ORDER BY 
                CASE WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 0 ELSE 1 END,
                sp.priority_rank,
                sp.crd
        ) as rank_within_firm
    FROM scored_prospects sp
    WHERE sp.prospect_type = 'NEW_PROSPECT'
       OR sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids)
),

diversity_filtered AS (
    SELECT * FROM ranked_prospects
    WHERE rank_within_firm <= 50 AND source_priority < 99
)

SELECT 
    crd as advisor_crd,
    score_tier,
    priority_rank,
    expected_conversion_rate,
    ROUND(expected_conversion_rate * 100, 2) as expected_rate_pct,
    bleeding_velocity,
    firm_net_change_12mo,
    departures_90d,
    departures_prior_90d
FROM diversity_filtered
ORDER BY sort_score, crd
LIMIT 100
)

SELECT * FROM full_query;

