-- ============================================================================
-- RECYCLABLE POOL MASTER QUERY V2.2 (WITH V3 TIER SCORING)
-- 
-- KEY BUSINESS LOGIC:
-- 1. People who RECENTLY changed firms (< 2 years) are EXCLUDED
--    - They just settled in and won't move again soon
--    
-- 2. People who HAVEN'T changed firms + High V4 + Long tenure are PRIORITIZED
--    - Model predicts they're about to move
--    - They're still at the same firm (available to recruit)
--    
-- 3. People who changed firms 2-3 years ago are MEDIUM priority
--    - Proven movers, settling period is over
--    
-- 4. "Timing" dispositions are HIGH priority
--    - They literally told us timing was bad
--    - If 6-12 months passed, timing may be better now
--
-- PRIORITY ORDER:
--   P1: "Timing" disposition + 180-365 days passed (7% expected)
--   P2: High V4 + No firm change + Long tenure NOW (6% expected)
--   P3: "No Response" + High V4 (5% expected)
--   P4: Changed firms 2-3 years ago (4.5% expected)
--   P5: Changed firms 3+ years ago + V4≥60 (4% expected)
--   P6: Standard recycle (3% expected)
--
-- EXCLUSIONS:
--   - Changed firms < 2 years ago (just settled in)
--   - No-go dispositions (permanent DQ)
--   - DoNotCall = true
--   - Contacted < 90 days ago
--
-- SQL FIXES IN V2.1:
--   - Fixed date type mismatches (DATE() casting)
--   - Fixed tenure calculations (calculate to CloseDate, not CURRENT_DATE)
--   - Added PIT-compliant employment history join
--   - Added field validation with COALESCE
--   - Fixed priority logic to use correct tenure fields
-- ============================================================================

DECLARE target_count INT64 DEFAULT 600;
DECLARE min_days_since_contact INT64 DEFAULT 90;   -- Minimum days since last contact
DECLARE max_days_since_contact INT64 DEFAULT 730;  -- Maximum 2 years
DECLARE min_years_since_firm_change INT64 DEFAULT 2;  -- Must be 2+ years since firm change

-- ============================================================================
-- PART A: EXCLUSION LISTS
-- ============================================================================

-- A1. No-Go Dispositions (Leads) - Permanent disqualifications
CREATE TEMP TABLE nogo_lead_dispositions AS
SELECT disposition FROM UNNEST([
    'Not Interested in Moving',
    'Not a Fit',
    'No Book',
    'Book Not Transferable',
    'Restrictive Covenants',
    'Bad Lead Provided',
    'Wants Platform Only',
    'AUM / Revenue too Low'
]) AS disposition;

-- A2. No-Go Close Lost Reasons (Opportunities) - Permanent disqualifications
CREATE TEMP TABLE nogo_opp_reasons AS
SELECT reason FROM UNNEST([
    'Savvy Declined - No Book of Business',
    'Savvy Declined - Insufficient Revenue',
    'Savvy Declined – Book Not Transferable',
    'Savvy Declined - Poor Culture Fit',
    'Savvy Declined - Compliance',
    'Candidate Declined - Lost to Competitor'
]) AS reason;

-- A3. HIGH PRIORITY Recyclable Dispositions (Leads) - "Timing" related
CREATE TEMP TABLE timing_lead_dispositions AS
SELECT disposition FROM UNNEST([
    'Timing'
]) AS disposition;

-- A4. HIGH PRIORITY Recyclable Reasons (Opportunities) - "Timing" related
CREATE TEMP TABLE timing_opp_reasons AS
SELECT reason FROM UNNEST([
    'Candidate Declined - Timing',
    'Candidate Declined - Fear of Change'
]) AS reason;

-- A5. MEDIUM PRIORITY Recyclable - General re-engagement
CREATE TEMP TABLE general_recyclable_dispositions AS
SELECT disposition FROM UNNEST([
    'No Response',
    'Auto-Closed by Operations',
    'Other',
    'No Show / Ghosted'
]) AS disposition;

CREATE TEMP TABLE general_recyclable_reasons AS
SELECT reason FROM UNNEST([
    'No Longer Responsive',
    'No Show – Intro Call',
    'Other'
]) AS reason;

-- A6. Excluded firms (internal, wirehouses)
CREATE TEMP TABLE excluded_firms AS
SELECT firm_pattern FROM UNNEST([
    '%SAVVY WEALTH%', '%RITHOLTZ%',
    '%J.P. MORGAN%', '%MORGAN STANLEY%', '%MERRILL%', '%WELLS FARGO%',
    '%UBS %', '%EDWARD JONES%', '%AMERIPRISE%', '%NORTHWESTERN MUTUAL%',
    '%PRUDENTIAL%', '%RAYMOND JAMES%', '%FIDELITY%', '%SCHWAB%'
]) AS firm_pattern;

-- ============================================================================
-- PART B: LAST TASK ACTIVITY
-- ============================================================================

WITH lead_last_tasks AS (
    SELECT 
        t.WhoId as record_id,
        MAX(t.ActivityDate) as last_task_date,
        ARRAY_AGG(t.OwnerId ORDER BY t.ActivityDate DESC LIMIT 1)[OFFSET(0)] as last_task_owner_id,
        ARRAY_AGG(t.Subject ORDER BY t.ActivityDate DESC LIMIT 1)[OFFSET(0)] as last_task_subject
    FROM `savvy-gtm-analytics.SavvyGTMData.Task` t
    WHERE t.WhoId LIKE '00Q%'
      AND t.IsDeleted = false
    GROUP BY t.WhoId
),

opp_last_tasks AS (
    SELECT 
        t.WhatId as record_id,
        MAX(t.ActivityDate) as last_task_date,
        ARRAY_AGG(t.OwnerId ORDER BY t.ActivityDate DESC LIMIT 1)[OFFSET(0)] as last_task_owner_id,
        ARRAY_AGG(t.Subject ORDER BY t.ActivityDate DESC LIMIT 1)[OFFSET(0)] as last_task_subject
    FROM `savvy-gtm-analytics.SavvyGTMData.Task` t
    WHERE t.WhatId LIKE '006%'
      AND t.IsDeleted = false
    GROUP BY t.WhatId
),

users AS (
    SELECT Id, Name, Email
    FROM `savvy-gtm-analytics.SavvyGTMData.User`
    WHERE IsActive = true
),

-- ============================================================================
-- PART B.5: FIRM METRICS (for V3 tier calculation)
-- ============================================================================

-- Firm headcount (current reps per firm)
firm_headcount AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_reps
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

-- Firm departures (last 12 months)
firm_departures AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),

-- Firm arrivals (last 12 months)
firm_arrivals AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

-- Combined firm metrics
firm_metrics AS (
    SELECT
        h.firm_crd,
        h.current_reps as firm_rep_count,
        COALESCE(d.departures_12mo, 0) as departures_12mo,
        COALESCE(a.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(a.arrivals_12mo, 0) - COALESCE(d.departures_12mo, 0) as firm_net_change_12mo
    FROM firm_headcount h
    LEFT JOIN firm_departures d ON h.firm_crd = d.firm_crd
    LEFT JOIN firm_arrivals a ON h.firm_crd = a.firm_crd
    WHERE h.current_reps >= 20  -- Only firms with 20+ reps
),

-- ============================================================================
-- PART B.6: V3 TIER CALCULATION (Applied to CURRENT state)
-- Uses same logic as Provided Lead List V3.2.5
-- ============================================================================

v3_tier_calc AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as current_firm_crd,
        c.PRIMARY_FIRM_NAME as current_firm_name,
        c.PRIMARY_FIRM_START_DATE,
        
        -- Tenure at current firm (years)
        DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 as tenure_years,
        
        -- Industry tenure (years) - calculate from first registration
        DATE_DIFF(CURRENT_DATE(), 
            COALESCE((
                SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
            ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 as industry_tenure_years,
        
        -- Firm metrics
        COALESCE(fm.firm_net_change_12mo, 0) as firm_net_change_12mo,
        COALESCE(fm.firm_rep_count, 0) as firm_rep_count,
        
        -- Check if at bleeding firm (net change < 0)
        CASE WHEN COALESCE(fm.firm_net_change_12mo, 0) < 0 THEN TRUE ELSE FALSE END as at_bleeding_firm,
        
        -- Check for CFP credential
        CASE WHEN c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%' THEN TRUE ELSE FALSE END as has_cfp,
        
        -- Check for Series 65 only (has 65 but not 7)
        CASE 
            WHEN c.REP_LICENSES LIKE '%Series 65%' AND c.REP_LICENSES NOT LIKE '%Series 7%'
            THEN TRUE 
            ELSE FALSE 
        END as has_series_65_only,
        
        -- Count previous firms (movement history)
        (
            SELECT COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
            WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
        ) as previous_firm_count,
        
        -- High-value wealth title
        CASE 
            WHEN UPPER(c.TITLE_NAME) LIKE '%MANAGING DIRECTOR%'
                 OR UPPER(c.TITLE_NAME) LIKE '%SENIOR VICE PRESIDENT%'
                 OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
                 OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%'
            THEN TRUE 
            ELSE FALSE 
        END as is_hv_wealth_title,
        
        -- Check if wirehouse (using excluded_firms patterns)
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM excluded_firms ef
                WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
            ) THEN TRUE 
            ELSE FALSE 
        END as is_wirehouse,
        
        -- Calculate V3 tier (matches January 2026 logic)
        CASE
            -- TIER 1A: CFP + Bleeding Firm + 1-4yr tenure + 5+yr experience
            WHEN (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 4
                  AND DATE_DIFF(CURRENT_DATE(), 
                      COALESCE((
                          SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                          FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                          WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                      ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 >= 5
                  AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                  AND (c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%')
                  AND NOT EXISTS (
                      SELECT 1 FROM excluded_firms ef
                      WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                  ))
            THEN 'TIER_1A_PRIME_MOVER_CFP'
            
            -- TIER 1B: Series 65 only + Bleeding Firm + 1-3yr tenure + small firm OR standard Tier 1 criteria
            WHEN (
                (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 3
                    AND DATE_DIFF(CURRENT_DATE(), 
                        COALESCE((
                            SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                            WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                        ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 BETWEEN 5 AND 15
                    AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                    AND COALESCE(fm.firm_rep_count, 0) <= 50
                    AND NOT EXISTS (
                        SELECT 1 FROM excluded_firms ef
                        WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                    ))
                   OR (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 3
                       AND COALESCE(fm.firm_rep_count, 0) <= 10
                       AND NOT EXISTS (
                           SELECT 1 FROM excluded_firms ef
                           WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                       ))
                   OR (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 4
                       AND DATE_DIFF(CURRENT_DATE(), 
                           COALESCE((
                               SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                               FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                               WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                           ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 BETWEEN 5 AND 15
                       AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                       AND NOT EXISTS (
                           SELECT 1 FROM excluded_firms ef
                           WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                       ))
            )
            AND c.REP_LICENSES LIKE '%Series 65%'
            AND c.REP_LICENSES NOT LIKE '%Series 7%'
            THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            
            -- TIER 1: Standard Prime Mover
            WHEN ((DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 3
                   AND DATE_DIFF(CURRENT_DATE(), 
                       COALESCE((
                           SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                           FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                           WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                       ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 BETWEEN 5 AND 15
                   AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                   AND COALESCE(fm.firm_rep_count, 0) <= 50
                   AND NOT EXISTS (
                       SELECT 1 FROM excluded_firms ef
                       WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                   ))
                  OR (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 3
                      AND COALESCE(fm.firm_rep_count, 0) <= 10
                      AND NOT EXISTS (
                          SELECT 1 FROM excluded_firms ef
                          WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                      ))
                  OR (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 4
                      AND DATE_DIFF(CURRENT_DATE(), 
                          COALESCE((
                              SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                              FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                              WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                          ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 BETWEEN 5 AND 15
                      AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                      AND NOT EXISTS (
                          SELECT 1 FROM excluded_firms ef
                          WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                      )))
            THEN 'TIER_1_PRIME_MOVER'
            
            -- TIER 1F: HV Wealth Title + Bleeding Firm
            WHEN ((UPPER(c.TITLE_NAME) LIKE '%MANAGING DIRECTOR%'
                   OR UPPER(c.TITLE_NAME) LIKE '%SENIOR VICE PRESIDENT%'
                   OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
                   OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%')
                  AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                  AND NOT EXISTS (
                      SELECT 1 FROM excluded_firms ef
                      WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                  ))
            THEN 'TIER_1F_HV_WEALTH_BLEEDER'
            
            -- TIER 2: Proven Mover (3+ previous firms)
            WHEN (
                SELECT COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID)
                FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
            ) >= 3
                 AND DATE_DIFF(CURRENT_DATE(), 
                     COALESCE((
                         SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                         WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                     ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 >= 5
            THEN 'TIER_2_PROVEN_MOVER'
            
            -- TIER 3: Moderate Bleeder
            WHEN COALESCE(fm.firm_net_change_12mo, 0) BETWEEN -10 AND -1
                 AND DATE_DIFF(CURRENT_DATE(), 
                     COALESCE((
                         SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                         WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                     ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 >= 5
            THEN 'TIER_3_MODERATE_BLEEDER'
            
            -- TIER 4: Experienced Mover
            WHEN DATE_DIFF(CURRENT_DATE(), 
                     COALESCE((
                         SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                         WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                     ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 >= 20
                 AND DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 4
            THEN 'TIER_4_EXPERIENCED_MOVER'
            
            -- TIER 5: Heavy Bleeder
            WHEN COALESCE(fm.firm_net_change_12mo, 0) <= -10
                 AND DATE_DIFF(CURRENT_DATE(), 
                     COALESCE((
                         SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                         WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                     ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 >= 5
            THEN 'TIER_5_HEAVY_BLEEDER'
            
            -- STANDARD: Everything else
            ELSE 'STANDARD'
        END as v3_tier,
        
        -- V3 tier numeric rank for sorting (lower = better)
        CASE
            WHEN (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 4
                  AND DATE_DIFF(CURRENT_DATE(), 
                      COALESCE((
                          SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                          FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                          WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                      ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 >= 5
                  AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                  AND (c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%')
                  AND NOT EXISTS (
                      SELECT 1 FROM excluded_firms ef
                      WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                  )) THEN 1  -- T1A
            WHEN (
                (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 3
                    AND DATE_DIFF(CURRENT_DATE(), 
                        COALESCE((
                            SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                            WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                        ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 BETWEEN 5 AND 15
                    AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                    AND COALESCE(fm.firm_rep_count, 0) <= 50
                    AND NOT EXISTS (
                        SELECT 1 FROM excluded_firms ef
                        WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                    ))
                   OR (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 3
                       AND COALESCE(fm.firm_rep_count, 0) <= 10
                       AND NOT EXISTS (
                           SELECT 1 FROM excluded_firms ef
                           WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                       ))
                   OR (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 4
                       AND DATE_DIFF(CURRENT_DATE(), 
                           COALESCE((
                               SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                               FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                               WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                           ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 BETWEEN 5 AND 15
                       AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                       AND NOT EXISTS (
                           SELECT 1 FROM excluded_firms ef
                           WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                       ))
            )
            AND c.REP_LICENSES LIKE '%Series 65%'
            AND c.REP_LICENSES NOT LIKE '%Series 7%' THEN 2  -- T1B
            WHEN ((DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 3
                   AND DATE_DIFF(CURRENT_DATE(), 
                       COALESCE((
                           SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                           FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                           WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                       ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 BETWEEN 5 AND 15
                   AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                   AND COALESCE(fm.firm_rep_count, 0) <= 50
                   AND NOT EXISTS (
                       SELECT 1 FROM excluded_firms ef
                       WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                   ))
                  OR (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 3
                      AND COALESCE(fm.firm_rep_count, 0) <= 10
                      AND NOT EXISTS (
                          SELECT 1 FROM excluded_firms ef
                          WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                      ))
                  OR (DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 4
                      AND DATE_DIFF(CURRENT_DATE(), 
                          COALESCE((
                              SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                              FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                              WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                          ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 BETWEEN 5 AND 15
                      AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                      AND NOT EXISTS (
                          SELECT 1 FROM excluded_firms ef
                          WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                      ))) THEN 3  -- T1
            WHEN ((UPPER(c.TITLE_NAME) LIKE '%MANAGING DIRECTOR%'
                   OR UPPER(c.TITLE_NAME) LIKE '%SENIOR VICE PRESIDENT%'
                   OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
                   OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%')
                  AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                  AND NOT EXISTS (
                      SELECT 1 FROM excluded_firms ef
                      WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
                  )) THEN 4  -- T1F
            WHEN (
                SELECT COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID)
                FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
            ) >= 3
                 AND DATE_DIFF(CURRENT_DATE(), 
                     COALESCE((
                         SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                         WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                     ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 >= 5 THEN 5  -- T2
            WHEN COALESCE(fm.firm_net_change_12mo, 0) BETWEEN -10 AND -1
                 AND DATE_DIFF(CURRENT_DATE(), 
                     COALESCE((
                         SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                         WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                     ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 >= 5 THEN 6  -- T3
            WHEN DATE_DIFF(CURRENT_DATE(), 
                     COALESCE((
                         SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                         WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                     ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 >= 20
                 AND DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0 BETWEEN 1 AND 4 THEN 7  -- T4
            WHEN COALESCE(fm.firm_net_change_12mo, 0) <= -10
                 AND DATE_DIFF(CURRENT_DATE(), 
                     COALESCE((
                         SELECT MIN(DATE(PREVIOUS_REGISTRATION_COMPANY_START_DATE))
                         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
                         WHERE eh.RIA_CONTACT_CRD_ID = c.RIA_CONTACT_CRD_ID
                     ), DATE(c.PRIMARY_FIRM_START_DATE)), DAY) / 365.0 >= 5 THEN 8  -- T5
            ELSE 9  -- STANDARD
        END as v3_tier_rank
        
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN firm_metrics fm ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = fm.firm_crd
),

-- ============================================================================
-- PART C: RECYCLABLE OPPORTUNITIES (Priority over Leads)
-- ============================================================================

recyclable_opportunities AS (
    SELECT 
        o.Id as record_id,
        'OPPORTUNITY' as record_type,
        o.Name as record_name,
        o.FA_CRD__c as fa_crd,
        -- Field validation with COALESCE
        COALESCE(c.CONTACT_FIRST_NAME, 'Unknown') as first_name,
        COALESCE(c.CONTACT_LAST_NAME, 'Unknown') as last_name,
        COALESCE(c.EMAIL, NULL) as email,
        COALESCE(c.MOBILE_PHONE_NUMBER, c.OFFICE_PHONE_NUMBER, NULL) as phone,
        COALESCE(c.LINKEDIN_PROFILE_URL, NULL) as linkedin_url,
        COALESCE(c.PRIMARY_FIRM_NAME, NULL) as firm_name,
        o.OwnerId as owner_id,
        sgm.Name as owner_name,
        
        -- Stage and disposition info
        o.StageName as last_stage,
        o.Closed_Lost_Reason__c as close_reason,
        o.Closed_Lost_Details__c as close_details,
        DATE(o.CloseDate) as close_date,
        
        -- Task activity
        ot.last_task_date,
        ot.last_task_subject,
        tu.Name as last_contacted_by,
        DATE_DIFF(CURRENT_DATE(), COALESCE(ot.last_task_date, DATE(o.CloseDate)), DAY) as days_since_last_contact,
        
        -- FINTRX enrichment
        c.PRIMARY_FIRM_NAME as current_firm_name,
        c.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        c.LINKEDIN_PROFILE_URL as fintrx_linkedin,
        
        -- Firm change analysis (CRITICAL FOR PRIORITY) - FIXED: Date type casting
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
                 AND DATE(c.PRIMARY_FIRM_START_DATE) > DATE(o.CloseDate) 
            THEN TRUE
            ELSE FALSE
        END as changed_firms_since_close,
        
        -- YEARS since firm change (key metric) - Current tenure at their current firm
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
            THEN DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_current_firm,
        
        -- Current tenure at firm NOW (for people who haven't changed firms)
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL
            THEN DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_current_firm_now,
        
        -- Tenure at firm WHEN WE CLOSED THEM (using PIT employment history)
        CASE 
            WHEN eh_pit.firm_start_at_close IS NOT NULL
            THEN DATE_DIFF(DATE(o.CloseDate), DATE(eh_pit.firm_start_at_close), DAY) / 365.0
            -- Fallback: if no employment history, use current firm start if it was before close
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
                 AND DATE(c.PRIMARY_FIRM_START_DATE) <= DATE(o.CloseDate)
            THEN DATE_DIFF(DATE(o.CloseDate), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_firm_when_closed,
        
        -- V4 scoring
        vs.v4_score,
        vs.v4_percentile,
        vs.shap_top1_feature,
        vs.shap_top1_value,
        vs.shap_top2_feature,
        vs.shap_top2_value,
        vs.shap_top3_feature,
        vs.shap_top3_value,
        vs.v4_narrative as v4_shap_narrative,
        
        -- Is this a "Timing" close reason? (HIGH PRIORITY)
        CASE WHEN o.Closed_Lost_Reason__c IN (SELECT reason FROM timing_opp_reasons) THEN TRUE ELSE FALSE END as is_timing_reason,
        
        -- Is this a general recyclable reason?
        CASE WHEN o.Closed_Lost_Reason__c IN (SELECT reason FROM general_recyclable_reasons) THEN TRUE ELSE FALSE END as is_general_recyclable,
        
        -- V3 tier columns (NEW)
        v3.v3_tier,
        v3.v3_tier_rank,
        v3.at_bleeding_firm,
        v3.has_cfp,
        v3.previous_firm_count
        
    FROM `savvy-gtm-analytics.SavvyGTMData.Opportunity` o
    LEFT JOIN opp_last_tasks ot ON o.Id = ot.record_id
    LEFT JOIN users tu ON ot.last_task_owner_id = tu.Id
    LEFT JOIN users sgm ON o.OwnerId = sgm.Id
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(o.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    -- PIT-compliant employment history join to find firm at time of close
    LEFT JOIN (
        SELECT 
            crd,
            firm_name_at_close,
            firm_crd_at_close,
            firm_start_at_close,
            firm_end_at_close
        FROM (
            SELECT 
                RIA_CONTACT_CRD_ID as crd,
                PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name_at_close,
                PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd_at_close,
                PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_at_close,
                PREVIOUS_REGISTRATION_COMPANY_END_DATE as firm_end_at_close,
                ROW_NUMBER() OVER (
                    PARTITION BY RIA_CONTACT_CRD_ID 
                    ORDER BY PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
                ) as rn
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
            WHERE PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
        )
        WHERE rn = 1
    ) eh_pit ON SAFE_CAST(REGEXP_REPLACE(CAST(o.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = eh_pit.crd
        AND DATE(eh_pit.firm_start_at_close) <= DATE(o.CloseDate)
        AND (eh_pit.firm_end_at_close IS NULL OR DATE(eh_pit.firm_end_at_close) >= DATE(o.CloseDate))
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` vs 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(o.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = vs.crd
    LEFT JOIN excluded_firms ef_exclude 
        ON UPPER(COALESCE(c.PRIMARY_FIRM_NAME, '')) LIKE ef_exclude.firm_pattern
    LEFT JOIN v3_tier_calc v3 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(o.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = v3.crd
    WHERE 
        -- Closed Lost only
        o.IsClosed = true
        AND o.IsWon = false
        AND o.IsDeleted = false
        -- NOT no-go reasons
        AND o.Closed_Lost_Reason__c NOT IN (SELECT reason FROM nogo_opp_reasons)
        -- Time window for last contact
        AND DATE_DIFF(CURRENT_DATE(), COALESCE(ot.last_task_date, o.CloseDate), DAY) >= min_days_since_contact
        AND DATE_DIFF(CURRENT_DATE(), COALESCE(ot.last_task_date, o.CloseDate), DAY) <= max_days_since_contact
        -- Has CRD
        AND o.FA_CRD__c IS NOT NULL
        -- CRITICAL: Exclude people who changed firms RECENTLY (< 2 years) - FIXED: Date type casting
        AND (
            -- No firm data available
            c.PRIMARY_FIRM_START_DATE IS NULL 
            -- OR they didn't change firms after we closed them
            OR DATE(c.PRIMARY_FIRM_START_DATE) <= DATE(o.CloseDate)
            -- OR they changed firms 2+ years ago (enough time to be restless again)
            OR DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) >= (min_years_since_firm_change * 365)
        )
        -- Not at excluded firms
        AND ef_exclude.firm_pattern IS NULL
),

-- ============================================================================
-- PART D: RECYCLABLE LEADS
-- ============================================================================

recyclable_leads AS (
    SELECT 
        l.Id as record_id,
        'LEAD' as record_type,
        CONCAT(COALESCE(l.FirstName, ''), ' ', COALESCE(l.LastName, '')) as record_name,
        l.FA_CRD__c as fa_crd,
        -- Field validation with COALESCE
        COALESCE(l.FirstName, c.CONTACT_FIRST_NAME, 'Unknown') as first_name,
        COALESCE(l.LastName, c.CONTACT_LAST_NAME, 'Unknown') as last_name,
        COALESCE(l.Email, c.EMAIL, NULL) as email,
        COALESCE(l.Phone, c.MOBILE_PHONE_NUMBER, c.OFFICE_PHONE_NUMBER, NULL) as phone,
        COALESCE(c.LINKEDIN_PROFILE_URL, NULL) as linkedin_url,
        COALESCE(c.PRIMARY_FIRM_NAME, l.Company, NULL) as firm_name,
        l.OwnerId as owner_id,
        sga.Name as owner_name,
        
        -- Stage and disposition info
        l.Status as last_stage,
        l.Disposition__c as close_reason,
        CAST(NULL AS STRING) as close_details,
        DATE(l.Stage_Entered_Closed__c) as close_date,
        
        -- Task activity
        lt.last_task_date,
        lt.last_task_subject,
        tu.Name as last_contacted_by,
        DATE_DIFF(CURRENT_DATE(), COALESCE(lt.last_task_date, DATE(l.Stage_Entered_Closed__c)), DAY) as days_since_last_contact,
        
        -- FINTRX enrichment
        c.PRIMARY_FIRM_NAME as current_firm_name,
        c.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        c.LINKEDIN_PROFILE_URL as fintrx_linkedin,
        
        -- Firm change analysis - FIXED: Date type casting (Stage_Entered_Closed__c is TIMESTAMP)
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
                 AND DATE(c.PRIMARY_FIRM_START_DATE) > DATE(l.Stage_Entered_Closed__c) 
            THEN TRUE
            ELSE FALSE
        END as changed_firms_since_close,
        
        -- YEARS since firm change - Current tenure at their current firm
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
            THEN DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_current_firm,
        
        -- Current tenure at firm NOW (for people who haven't changed firms)
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL
            THEN DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_current_firm_now,
        
        -- Tenure at firm WHEN WE CLOSED THEM (using PIT employment history)
        CASE 
            WHEN eh_pit.firm_start_at_close IS NOT NULL
            THEN DATE_DIFF(DATE(l.Stage_Entered_Closed__c), DATE(eh_pit.firm_start_at_close), DAY) / 365.0
            -- Fallback: if no employment history, use current firm start if it was before close
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
                 AND DATE(c.PRIMARY_FIRM_START_DATE) <= DATE(l.Stage_Entered_Closed__c)
            THEN DATE_DIFF(DATE(l.Stage_Entered_Closed__c), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_firm_when_closed,
        
        -- V4 scoring
        vs.v4_score,
        vs.v4_percentile,
        vs.shap_top1_feature,
        vs.shap_top1_value,
        vs.shap_top2_feature,
        vs.shap_top2_value,
        vs.shap_top3_feature,
        vs.shap_top3_value,
        vs.v4_narrative as v4_shap_narrative,
        
        -- Is this a "Timing" disposition? (HIGH PRIORITY)
        CASE WHEN l.Disposition__c IN (SELECT disposition FROM timing_lead_dispositions) THEN TRUE ELSE FALSE END as is_timing_reason,
        
        -- Is this a general recyclable?
        CASE WHEN l.Disposition__c IN (SELECT disposition FROM general_recyclable_dispositions) THEN TRUE ELSE FALSE END as is_general_recyclable,
        
        -- V3 tier columns (NEW)
        v3.v3_tier,
        v3.v3_tier_rank,
        v3.at_bleeding_firm,
        v3.has_cfp,
        v3.previous_firm_count
        
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN lead_last_tasks lt ON l.Id = lt.record_id
    LEFT JOIN users tu ON lt.last_task_owner_id = tu.Id
    LEFT JOIN users sga ON l.OwnerId = sga.Id
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    -- PIT-compliant employment history join to find firm at time of close
    LEFT JOIN (
        SELECT 
            crd,
            firm_name_at_close,
            firm_crd_at_close,
            firm_start_at_close,
            firm_end_at_close
        FROM (
            SELECT 
                RIA_CONTACT_CRD_ID as crd,
                PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name_at_close,
                PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd_at_close,
                PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_at_close,
                PREVIOUS_REGISTRATION_COMPANY_END_DATE as firm_end_at_close,
                ROW_NUMBER() OVER (
                    PARTITION BY RIA_CONTACT_CRD_ID 
                    ORDER BY PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
                ) as rn
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
            WHERE PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
        )
        WHERE rn = 1
    ) eh_pit ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = eh_pit.crd
        AND DATE(eh_pit.firm_start_at_close) <= DATE(l.Stage_Entered_Closed__c)
        AND (eh_pit.firm_end_at_close IS NULL OR DATE(eh_pit.firm_end_at_close) >= DATE(l.Stage_Entered_Closed__c))
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` vs 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = vs.crd
    LEFT JOIN excluded_firms ef_exclude_lead 
        ON UPPER(COALESCE(c.PRIMARY_FIRM_NAME, l.Company)) LIKE ef_exclude_lead.firm_pattern
    LEFT JOIN recyclable_opportunities ro_dedup
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = 
           SAFE_CAST(REGEXP_REPLACE(CAST(ro_dedup.fa_crd AS STRING), r'[^0-9]', '') AS INT64)
    LEFT JOIN v3_tier_calc v3 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = v3.crd
    WHERE 
        -- Closed leads only
        l.Status = 'Closed'
        AND l.IsConverted = false
        AND l.DoNotCall = false
        AND l.IsDeleted = false
        -- NOT no-go dispositions
        AND l.Disposition__c NOT IN (SELECT disposition FROM nogo_lead_dispositions)
        -- Time window
        AND DATE_DIFF(CURRENT_DATE(), COALESCE(lt.last_task_date, DATE(l.Stage_Entered_Closed__c)), DAY) >= min_days_since_contact
        AND DATE_DIFF(CURRENT_DATE(), COALESCE(lt.last_task_date, DATE(l.Stage_Entered_Closed__c)), DAY) <= max_days_since_contact
        -- Has CRD
        AND l.FA_CRD__c IS NOT NULL
        -- Not converted to Opportunity
        AND l.ConvertedOpportunityId IS NULL
        -- CRITICAL: Exclude people who changed firms RECENTLY (< 2 years) - FIXED: Date type casting
        AND (
            c.PRIMARY_FIRM_START_DATE IS NULL 
            OR DATE(c.PRIMARY_FIRM_START_DATE) <= DATE(l.Stage_Entered_Closed__c)
            OR DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) >= (min_years_since_firm_change * 365)
        )
        -- Not at excluded firms
        AND ef_exclude_lead.firm_pattern IS NULL
        -- Not already in recyclable opportunities (dedupe by CRD)
        AND ro_dedup.fa_crd IS NULL
),

-- ============================================================================
-- PART E: COMBINE AND APPLY PRIORITY LOGIC
-- ============================================================================

combined_recyclable AS (
    SELECT * FROM recyclable_opportunities
    UNION ALL
    SELECT * FROM recyclable_leads
),

-- Apply unified scoring
with_score AS (
    SELECT 
        cr.*,
        
        -- ========================================
        -- UNIFIED RECYCLABLE SCORE
        -- Combines V4 ML, V3 tier signals, timing, and other factors
        -- ========================================
        (
            -- Base: V4 Percentile (0-100)
            COALESCE(cr.v4_percentile, 50)
            
            -- V3 Tier Boost (based on historical conversion rates)
            + CASE cr.v3_tier
                WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 35
                WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 35
                WHEN 'TIER_1_PRIME_MOVER' THEN 30
                WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 28
                WHEN 'TIER_4_EXPERIENCED_MOVER' THEN 22
                WHEN 'TIER_2_PROVEN_MOVER' THEN 20
                WHEN 'TIER_3_MODERATE_BLEEDER' THEN 18
                WHEN 'TIER_5_HEAVY_BLEEDER' THEN 12
                ELSE 0
              END
            
            -- "Timing" disposition boost
            + CASE 
                WHEN cr.close_reason IN (
                    'Timing', 
                    'Candidate Declined - Timing', 
                    'Candidate Declined - Fear of Change'
                ) THEN 15 
                ELSE 0 
              END
            
            -- Opportunity vs Lead boost
            + CASE WHEN cr.record_type = 'OPPORTUNITY' THEN 10 ELSE 0 END
            
            -- Optimal re-engagement window
            + CASE 
                WHEN cr.days_since_last_contact BETWEEN 180 AND 365 THEN 10
                WHEN cr.days_since_last_contact BETWEEN 90 AND 180 THEN 5
                ELSE 0 
              END
            
            -- Currently at bleeding firm
            + CASE WHEN cr.at_bleeding_firm = TRUE THEN 8 ELSE 0 END
            
        ) as recyclable_score,
        
        -- V3 Tier Narrative (comprehensive explanation of V3 tier assignment)
        CASE 
            -- TIER 1A: CFP + Bleeding Firm
            WHEN cr.v3_tier = 'TIER_1A_PRIME_MOVER_CFP' THEN
                CONCAT(cr.first_name, ' is a CFP holder at ', COALESCE(cr.current_firm_name, cr.firm_name, 'their firm'), 
                       ', which has lost ', CAST(ABS(COALESCE(v3.firm_net_change_12mo, 0)) AS STRING), 
                       ' advisors (net) in the past year. CFP designation indicates book ownership and client relationships. ',
                       'With ', CAST(ROUND(COALESCE(v3.tenure_years, 0), 1) AS STRING), ' years at the firm and ', 
                       CAST(ROUND(COALESCE(v3.industry_tenure_years, 0), 1) AS STRING), 
                       ' years of experience, this is an ULTRA-PRIORITY lead. Tier 1A: 8.7% expected conversion.')
            
            -- TIER 1B: Series 65 only
            WHEN cr.v3_tier = 'TIER_1B_PRIME_MOVER_SERIES65' THEN
                CONCAT(cr.first_name, ' is a fee-only RIA advisor (Series 65 only) at ', 
                       COALESCE(cr.current_firm_name, cr.firm_name, 'their firm'), 
                       '. Pure RIA advisors have no broker-dealer ties, making transitions easier. ',
                       'Tier 1B: Prime Mover (Pure RIA) with 7.9% expected conversion.')
            
            -- TIER 1: Standard Prime Mover
            WHEN cr.v3_tier = 'TIER_1_PRIME_MOVER' THEN
                CONCAT(cr.first_name, ' has been at ', COALESCE(cr.current_firm_name, cr.firm_name, 'their firm'), 
                       ' for ', CAST(ROUND(COALESCE(v3.tenure_years, 0), 1) AS STRING), ' years with ', 
                       CAST(ROUND(COALESCE(v3.industry_tenure_years, 0), 1) AS STRING), ' years of experience. ',
                       CASE WHEN COALESCE(v3.firm_net_change_12mo, 0) < 0 THEN 
                           CONCAT('The firm has lost ', CAST(ABS(COALESCE(v3.firm_net_change_12mo, 0)) AS STRING), ' advisors. ') 
                       ELSE '' END,
                       'Prime Mover tier with 7.1% expected conversion.')
            
            -- TIER 1F: HV Wealth Title + Bleeding
            WHEN cr.v3_tier = 'TIER_1F_HV_WEALTH_BLEEDER' THEN
                CONCAT(cr.first_name, ' holds a High-Value Wealth title at ', 
                       COALESCE(cr.current_firm_name, cr.firm_name, 'their firm'), 
                       ', which has lost ', CAST(ABS(COALESCE(v3.firm_net_change_12mo, 0)) AS STRING), 
                       ' advisors. Tier 1F: HV Wealth (Bleeding) with 6.5% expected conversion.')
            
            -- TIER 2: Proven Mover
            WHEN cr.v3_tier = 'TIER_2_PROVEN_MOVER' THEN
                CONCAT(cr.first_name, ' has worked at ', CAST(COALESCE(cr.previous_firm_count, 0) + 1 AS STRING), 
                       ' different firms over ', CAST(ROUND(COALESCE(v3.industry_tenure_years, 0), 1) AS STRING), 
                       ' years. History of mobility demonstrates willingness to change. ',
                       'Proven Mover tier with 5.2% expected conversion.')
            
            -- TIER 3: Moderate Bleeder
            WHEN cr.v3_tier = 'TIER_3_MODERATE_BLEEDER' THEN
                CONCAT(COALESCE(cr.current_firm_name, cr.firm_name, 'their firm'), 
                       ' has experienced moderate advisor departures (net change: ', 
                       CAST(COALESCE(v3.firm_net_change_12mo, 0) AS STRING), '). ', cr.first_name, 
                       ' is likely hearing about opportunities from departing colleagues. ',
                       'Moderate Bleeder tier: 4.4% expected conversion.')
            
            -- TIER 4: Experienced Mover
            WHEN cr.v3_tier = 'TIER_4_EXPERIENCED_MOVER' THEN
                CONCAT(cr.first_name, ' is a ', CAST(ROUND(COALESCE(v3.industry_tenure_years, 0), 1) AS STRING), 
                       '-year veteran who recently moved to ', COALESCE(cr.current_firm_name, cr.firm_name, 'their firm'), 
                       '. A veteran who recently changed firms will move for the right opportunity. ',
                       'Experienced Mover: 4.1% expected conversion.')
            
            -- TIER 5: Heavy Bleeder
            WHEN cr.v3_tier = 'TIER_5_HEAVY_BLEEDER' THEN
                CONCAT(COALESCE(cr.current_firm_name, cr.firm_name, 'their firm'), 
                       ' is losing ', CAST(ABS(COALESCE(v3.firm_net_change_12mo, 0)) AS STRING), 
                       ' advisors (net). ', cr.first_name, 
                       ' is watching the workplace destabilize. Heavy Bleeder tier: 3.8% expected conversion.')
            
            -- STANDARD
            ELSE
                CONCAT(cr.first_name, ' at ', COALESCE(cr.current_firm_name, cr.firm_name, 'their firm'), 
                       ' - Standard tier prospect.')
        END as v3_tier_narrative
        
    FROM combined_recyclable cr
    LEFT JOIN v3_tier_calc v3 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(cr.fa_crd AS STRING), r'[^0-9]', '') AS INT64) = v3.crd
),

-- Final ranking
ranked_recyclable AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            ORDER BY 
                -- Primary: Unified recyclable score (higher is better)
                recyclable_score DESC,
                -- Tiebreakers
                CASE record_type WHEN 'OPPORTUNITY' THEN 0 ELSE 1 END,
                v4_percentile DESC NULLS LAST,
                record_id
        ) as recycle_rank
    FROM with_score
)

-- ============================================================================
-- FINAL OUTPUT
-- ============================================================================

SELECT 
    recycle_rank as list_rank,
    record_id,
    record_type,
    fa_crd,
    first_name,
    last_name,
    email,
    phone,
    COALESCE(fintrx_linkedin, linkedin_url) as linkedin_url,
    COALESCE(current_firm_name, firm_name) as current_firm,
    firm_name as firm_at_close,
    owner_id,
    owner_name,
    
    -- Unified recyclable score
    recyclable_score,
    
    -- History
    last_stage,
    close_reason,
    close_details,
    close_date,
    last_task_date,
    last_task_subject,
    last_contacted_by,
    days_since_last_contact,
    
    -- Firm change analysis
    changed_firms_since_close,
    ROUND(years_at_current_firm, 1) as years_at_current_firm,
    ROUND(years_at_current_firm_now, 1) as years_at_current_firm_now,
    ROUND(years_at_firm_when_closed, 1) as years_at_firm_when_closed,
    
    -- Scoring
    ROUND(v4_score, 4) as v4_score,
    v4_percentile,
    
    -- V3 tier columns (NEW)
    COALESCE(v3_tier, 'STANDARD') as v3_tier,
    COALESCE(v3_tier_rank, 9) as v3_tier_rank,
    COALESCE(at_bleeding_firm, FALSE) as at_bleeding_firm,
    COALESCE(has_cfp, FALSE) as has_cfp,
    COALESCE(previous_firm_count, 0) as previous_firm_count,
    v3_tier_narrative,
    
    -- V4 SHAP columns (NEW)
    shap_top1_feature,
    shap_top1_value,
    shap_top2_feature,
    shap_top2_value,
    shap_top3_feature,
    shap_top3_value,
    v4_shap_narrative,
    
    -- Flags
    is_timing_reason,
    is_general_recyclable,
    
    CURRENT_TIMESTAMP() as generated_at

FROM ranked_recyclable
WHERE recycle_rank <= target_count
ORDER BY recycle_rank;

-- ============================================================================
-- VALIDATION QUERIES - Run after generating list to verify data quality
-- ============================================================================

-- V1: Check for date type issues (should return 0 rows)
-- SELECT 
--     record_id,
--     record_type,
--     'DATE_ISSUE' as issue,
--     close_date,
--     years_at_current_firm
-- FROM [GENERATED_TABLE]
-- WHERE years_at_current_firm < 0 
--    OR years_at_current_firm > 50;

-- V2: Check for recent firm changers that slipped through (should return 0 rows)
-- SELECT 
--     record_id,
--     record_type,
--     'RECENT_MOVER' as issue,
--     changed_firms_since_close,
--     years_at_current_firm
-- FROM [GENERATED_TABLE]
-- WHERE changed_firms_since_close = TRUE 
--   AND years_at_current_firm < 2;

-- V3: Check priority distribution
-- SELECT 
--     recycle_priority,
--     COUNT(*) as count,
--     ROUND(AVG(expected_conv_rate_pct), 2) as avg_conv
-- FROM [GENERATED_TABLE]
-- GROUP BY recycle_priority
-- ORDER BY 1;
