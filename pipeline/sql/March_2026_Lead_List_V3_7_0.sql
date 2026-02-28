-- ============================================================================
-- MARCH 2026 LEAD LIST GENERATOR (V3.7.0 — Rules-Based Optimized)
-- ============================================================================
-- Version: 3.7.0 — March 2026 (Rules-Based Optimized, STANDARD_HIGH_V4 Eliminated)
-- NOTE: M&A tiers are added via separate INSERT query (Insert_MA_Leads.sql)
--
-- V3.7.0 CHANGES (March 2026):
-- - ELIMINATED: STANDARD_HIGH_V4 backfill tier entirely (0.8% conversion in Jan, 0.6x baseline)
-- - INCREASED: TIER_2_PROVEN_MOVER quota — take ALL addressable (~1,533)
-- - INCREASED: TIER_1_PRIME_MOVER quota from 300 to 380 (validate 1.9% Jan signal)
-- - INCREASED: TIER_1B_PRIME_MOVER_SERIES65 quota from 60 to 150 (need n>100 for evaluation)
-- - INCREASED: TIER_0B_SMALL_FIRM_DUE quota to 150
-- - MAINTAINED: TIER_0C_CLOCKWORK_DUE at 100
-- - ADDED TO ACTIVE LIST: TIER_1G_ENHANCED_SWEET_SPOT (75 leads) and TIER_1G_GROWTH_STAGE (75 leads)
-- - MAINTAINED: TIER_3_MODERATE_BLEEDER — take up to 50 (near full pool of 72)
-- - MAINTAINED: TIER_NURTURE_TOO_EARLY excluded from active list (kept in nurture)
-- - Rationale: Jan data proved rules-based tiers outperform ML. With 5,534 addressable
--   rules-based leads and only ~2,500 needed, ML backfill is unnecessary.
--
-- V3.7.0 RECYCLE & TITLE FIXES (March 2026):
-- - TITLE: Exclude "Branch Manager" from base prospects.
-- - RECYCLABLE: Only recycle (a) Status=Nurture with 300+ days no contact, or (b) Status=Closed with 180+ days no contact.
--   Excludes New, Contacting, Qualified (converted), Replied, etc. from recyclable pool.
-- - CLOSED 365/180 RULE: Exclude anyone who closed within last 365 days unless Disposition__c is one of:
--   Bad Lead Provided, Bad Contact Info - Uncontacted, Wrong Phone Number - Contacted, No Show/Ghosted.
--   Those four dispositions can be recycled within 180 days of closure; other Closed leads need 180+ days no contact.
--   (E.g. Andrew Creekmur 00QVS00000S4fdx2AB / CRD 5843339 closed with "Not Interested in Moving" — excluded by this rule.)
--
-- V3.6.1 CHANGES (January 8, 2026):
-- - ADDED: Recent promotee exclusion (<5yr tenure + mid/senior title)
-- - Impact: Excludes ~1,915 low-converting leads (0.29-0.45% conversion)
-- - Rationale: Recent promotees don't have portable books yet
--
-- V3.6.0 CHANGES (January 8, 2026):
-- - ADDED: Career Clock tiers for timing-aware prioritization
-- - TIER_0A_PRIME_MOVER_DUE: Prime Mover + In Move Window (5.59% conv, 2.43x lift)
-- - TIER_0B_SMALL_FIRM_DUE: Small Firm + In Move Window (validated)
-- - TIER_0C_CLOCKWORK_DUE: Any advisor in move window (5.07% conv, 1.33x lift)
-- - TIER_NURTURE_TOO_EARLY: Advisors too early in cycle (3.72% conv - deprioritize)
-- - Career Clock is INDEPENDENT from Age (correlation = 0.035)
-- - Analysis: career_clock_results.md (January 7, 2026)
--
-- CAREER CLOCK METHODOLOGY:
-- - Uses advisor employment history to detect predictable career patterns
-- - tenure_cv < 0.5 = Predictable pattern (Clockwork or Semi-Predictable)
-- - In_Window = 70-130% through typical tenure cycle
-- - Too_Early = < 70% through typical tenure cycle
-- - PIT-safe: Only uses employment records with END_DATE < prediction_date
--
-- V3.5.2 CHANGES (January 7, 2026):
-- - DISCLOSURE EXCLUSIONS: Exclude advisors with regulatory/legal disclosures
-- - Exclusions: CRIMINAL, REGULATORY_EVENT, TERMINATION, INVESTIGATION,
--               CUSTOMER_DISPUTE, CIVIL_EVENT, BOND
-- - Rationale: Compliance/reputational risk outweighs marginal conversion benefit
-- - Impact: ~10% of prospects excluded, protects against compliance failures
--
-- V4.2.0 INTEGRATION CHANGES (January 7, 2026):
-- - Model: V4.2.0 with age_bucket_encoded (23 features, was 22 in V4.1.0)
-- - V4 used to filter OUT bottom 20% only; no STANDARD_HIGH_V4 backfill in V3.7.0
--
-- OUTPUT: ml_features.march_2026_lead_list
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.march_2026_lead_list` AS

WITH 
-- ============================================================================
-- A. ACTIVE SGAs (Dynamic - pulls from Salesforce User table)
-- ============================================================================
-- Moved to beginning to calculate total leads needed (200 per SGA)
active_sgas AS (
    SELECT 
        Id as sga_id,
        Name as sga_name,
        ROW_NUMBER() OVER (ORDER BY Name) as sga_number,
        COUNT(*) OVER () as total_sgas,
        COUNT(*) OVER () * 200 as total_leads_needed
    FROM `savvy-gtm-analytics.SavvyGTMData.User`
    WHERE IsActive = true
      AND IsSGA__c = true
      AND Name NOT IN ('Jacqueline Tully', 'GinaRose', 'Savvy Marketing', 'Savvy Operations', 'Anett Davis', 'Anett Diaz')
),

-- Get SGA constants for use throughout query
sga_constants AS (
    SELECT 
        MAX(total_sgas) as total_sgas,
        MAX(total_leads_needed) as total_leads_needed,
        MAX(total_sgas) * 200 as leads_per_sga
    FROM active_sgas
),

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

-- CRDs to exclude based on Lead Disposition__c (do not re-contact these)
excluded_disposition_crds AS (
    SELECT DISTINCT SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE IsDeleted = false AND FA_CRD__c IS NOT NULL
      AND Disposition__c IN ('No Book', 'Book Not Transferable', 'Not a Fit')
),

-- CRDs to exclude: closed within last 365 days with any disposition OTHER than recyclable ones.
-- Recyclable dispositions (can be recycled within 180 days): Bad Lead Provided, Bad Contact Info - Uncontacted,
-- Wrong Phone Number - Contacted, No Show/Ghosted. All other closed leads excluded for 365 days.
excluded_closed_recent_crds AS (
    SELECT DISTINCT SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE IsDeleted = false AND FA_CRD__c IS NOT NULL AND Status = 'Closed'
      AND DATE(COALESCE(Stage_Entered_Closed__c, LastModifiedDate)) >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
      AND (Disposition__c IS NULL OR Disposition__c NOT IN (
          'Bad Lead Provided',
          'Bad Contact Info - Uncontacted',
          'Wrong Phone Number - Contacted',
          'No Show/Ghosted'
      ))
),

-- ============================================================================
-- C. EXISTING SALESFORCE CRDs
-- ============================================================================
salesforce_crds AS (
    SELECT DISTINCT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE FA_CRD__c IS NOT NULL AND IsDeleted = false
),

-- Lead fields for nurture flag, original SGA owner, and bad contact info
lead_salesforce_info AS (
    SELECT 
        Id as lead_id,
        Status,
        SGA_Owner_Name__c,
        OwnerId,
        Disposition__c
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE IsDeleted = false
),

-- ============================================================================
-- D. RECYCLABLE LEADS (Nurture 300+ days no contact; Closed per disposition + 180 days)
-- ============================================================================
-- Nurture: recycle if 300+ days no contact.
-- Closed: (1) Recyclable disposition (Bad Lead Provided, Bad Contact Info - Uncontacted,
--   Wrong Phone Number - Contacted, No Show/Ghosted) and closed within 180 days — recycle;
--   (2) Any other Closed lead — recycle only if 180+ days no contact.
-- Do NOT recycle: New, Contacting, Qualified, Replied, etc.
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
      AND (l.DoNotCall IS NULL OR l.DoNotCall = false)
      AND (
          (l.Status = 'Nurture' AND (la.last_activity_date IS NULL OR DATE_DIFF(CURRENT_DATE(), la.last_activity_date, DAY) >= 300))
          OR (l.Status = 'Closed' AND (
              -- Recyclable dispositions: can recycle within 180 days of closure
              (l.Disposition__c IN ('Bad Lead Provided', 'Bad Contact Info - Uncontacted', 'Wrong Phone Number - Contacted', 'No Show/Ghosted')
               AND DATE(COALESCE(l.Stage_Entered_Closed__c, l.LastModifiedDate)) >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY))
              OR (la.last_activity_date IS NULL OR DATE_DIFF(CURRENT_DATE(), la.last_activity_date, DAY) >= 180)
          ))
      )
),

-- ============================================================================
-- E. ADVISOR EMPLOYMENT HISTORY
-- ============================================================================
advisor_moves AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID) as total_firms,
        COUNT(DISTINCT CASE 
            WHEN SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_START_DATE AS DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 YEAR)
            THEN PREVIOUS_REGISTRATION_COMPANY_CRD_ID END) as moves_3yr,
        MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE) as career_start_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    GROUP BY RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- F. FIRM HEADCOUNT
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
-- G. FIRM DEPARTURES
-- ============================================================================
firm_departures AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_END_DATE AS DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),

-- ============================================================================
-- H. FIRM ARRIVALS
-- ============================================================================
firm_arrivals AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE SAFE_CAST(PRIMARY_FIRM_START_DATE AS DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

-- ============================================================================
-- H. COMBINED FIRM METRICS
-- ============================================================================
firm_metrics AS (
    SELECT
        h.firm_crd,
        h.current_reps as firm_rep_count,
        COALESCE(d.departures_12mo, 0) as departures_12mo,
        COALESCE(a.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(a.arrivals_12mo, 0) - COALESCE(d.departures_12mo, 0) as firm_net_change_12mo,
        CASE WHEN h.current_reps > 0 
             THEN COALESCE(d.departures_12mo, 0) * 100.0 / h.current_reps 
             ELSE 0 END as turnover_pct
    FROM firm_headcount h
    LEFT JOIN firm_departures d ON h.firm_crd = d.firm_crd
    LEFT JOIN firm_arrivals a ON h.firm_crd = a.firm_crd
    WHERE h.current_reps >= 20
),

-- ============================================================================
-- I. CAREER CLOCK STATS (V3.6.0)
-- ============================================================================
-- Calculates advisor career patterns from completed employment records
-- PIT-SAFE: Only uses jobs with END_DATE < CURRENT_DATE()
-- ============================================================================
career_clock_stats AS (
    SELECT
        eh.RIA_CONTACT_CRD_ID as advisor_crd,
        COUNT(*) as cc_completed_jobs,
        AVG(DATE_DIFF(
            SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE AS DATE),
            SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE AS DATE),
            MONTH
        )) as cc_avg_prior_tenure_months,
        SAFE_DIVIDE(
            STDDEV(DATE_DIFF(
                SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE AS DATE),
                SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE AS DATE),
                MONTH
            )),
            AVG(DATE_DIFF(
                SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE AS DATE),
                SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE AS DATE),
                MONTH
            ))
        ) as cc_tenure_cv
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
    WHERE eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
      -- ⚠️ PIT CRITICAL: Only completed jobs BEFORE CURRENT_DATE
      AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE AS DATE) < CURRENT_DATE()
      -- Valid tenure (positive months)
      AND DATE_DIFF(SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE AS DATE),
                    SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE AS DATE), MONTH) > 0
    GROUP BY eh.RIA_CONTACT_CRD_ID
    HAVING COUNT(*) >= 2  -- Need 2+ completed jobs to detect pattern
),

-- ============================================================================
-- J. BASE PROSPECT DATA (with firm CRD exclusions)
-- ============================================================================
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
        DATE_DIFF(CURRENT_DATE(), SAFE_CAST(c.PRIMARY_FIRM_START_DATE AS DATE), MONTH) as tenure_months,
        DATE_DIFF(CURRENT_DATE(), SAFE_CAST(c.PRIMARY_FIRM_START_DATE AS DATE), YEAR) as tenure_years,
        CASE WHEN sf.crd IS NULL THEN 'NEW_PROSPECT' ELSE 'IN_SALESFORCE' END as prospect_type,
        sf.lead_id as existing_lead_id,
        -- JOB TITLE (NEW!)
        c.TITLE_NAME as job_title,
        -- Nurture / Salesforce owner / bad contact info (from Lead when in Salesforce)
        COALESCE(li.Status = 'Nurture', false) as is_nurture,
        li.SGA_Owner_Name__c as original_sga_owner_name,
        li.OwnerId as original_sga_owner_id,
        COALESCE(li.Disposition__c IN ('Bad Contact Info - Uncontacted', 'Wrong Phone Number - Contacted'), false) as bad_contact_info
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN salesforce_crds sf ON c.RIA_CONTACT_CRD_ID = sf.crd
    LEFT JOIN lead_salesforce_info li ON sf.lead_id = li.lead_id
    -- Exclude by firm name pattern (LEFT JOIN approach for BigQuery compatibility)
    LEFT JOIN excluded_firms ef ON UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
    -- Exclude by firm CRD
    LEFT JOIN excluded_firm_crds ec ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ec.firm_crd
    -- Exclude CRDs with Lead disposition No Book / Book Not Transferable / Not a Fit
    LEFT JOIN excluded_disposition_crds ed ON c.RIA_CONTACT_CRD_ID = ed.crd
    -- Exclude CRDs closed in last 365 days with non-recyclable disposition
    LEFT JOIN excluded_closed_recent_crds ecl ON c.RIA_CONTACT_CRD_ID = ecl.crd
    WHERE c.CONTACT_FIRST_NAME IS NOT NULL AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM_START_DATE IS NOT NULL AND c.PRIMARY_FIRM_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
      AND COALESCE(LOWER(TRIM(CAST(c.PRODUCING_ADVISOR AS STRING))), '') = 'true'
      -- Firm exclusions (M&A firms will be added via separate INSERT query)
      AND ef.firm_pattern IS NULL                    -- Not on exclusion list
      AND ec.firm_crd IS NULL                        -- Not on CRD exclusion list
      AND ed.crd IS NULL                             -- Not excluded by Lead disposition (No Book, Book Not Transferable, Not a Fit)
      AND ecl.crd IS NULL                            -- Not closed in last 365 days with non-recyclable disposition
      
      -- Age exclusion: Exclude advisors over 70
      -- AGE_RANGE values over 70: '70-74', '75-79', '80-84', '85-89', '90-94', '95-99'
      -- NOTE: Age 65-69 is now INCLUDED (converts at 2.97%, below baseline but still converts)
      -- Based on age_analysis_results.md analysis (January 7, 2026)
      AND (c.AGE_RANGE IS NULL 
           OR c.AGE_RANGE NOT IN ('70-74', '75-79', '80-84', '85-89', '90-94', '95-99'))
      
      -- ========================================================================
      -- V3.5.2 DISCLOSURE EXCLUSIONS (January 7, 2026)
      -- ========================================================================
      -- Exclude advisors with regulatory/legal disclosures
      -- Based on disclosure_analysis_results.md analysis
      -- 
      -- Rationale: While disclosures only reduce conversion by 0.11% (not statistically
      -- significant), we exclude for compliance/reputational reasons:
      -- - Advisors with disclosures may fail compliance review
      -- - Regulatory risk for the RIA
      -- - E&O insurance considerations
      -- - Custodian (Schwab/Fidelity) may reject advisors with certain disclosures
      --
      -- Impact: Excludes ~10% of prospects, loses ~271 potential MQLs annually
      -- Benefit: Protects against compliance failures and reputational risk
      -- ========================================================================
      
      -- HARD EXCLUDE: Serious regulatory/legal issues
      AND (c.CONTACT_HAS_DISCLOSED_CRIMINAL IS NULL OR LOWER(TRIM(CAST(c.CONTACT_HAS_DISCLOSED_CRIMINAL AS STRING))) != 'true')
      AND (c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT IS NULL OR LOWER(TRIM(CAST(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT AS STRING))) != 'true')
      AND (c.CONTACT_HAS_DISCLOSED_TERMINATION IS NULL OR LOWER(TRIM(CAST(c.CONTACT_HAS_DISCLOSED_TERMINATION AS STRING))) != 'true')
      AND (c.CONTACT_HAS_DISCLOSED_INVESTIGATION IS NULL OR LOWER(TRIM(CAST(c.CONTACT_HAS_DISCLOSED_INVESTIGATION AS STRING))) != 'true')
      
      -- SOFT EXCLUDE: Client/business issues  
      AND (c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE IS NULL OR LOWER(TRIM(CAST(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE AS STRING))) != 'true')
      AND (c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT IS NULL OR LOWER(TRIM(CAST(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT AS STRING))) != 'true')
      AND (c.CONTACT_HAS_DISCLOSED_BOND IS NULL OR LOWER(TRIM(CAST(c.CONTACT_HAS_DISCLOSED_BOND AS STRING))) != 'true')
      
      -- NOTE: BANKRUPT and JUDGMENT_OR_LIEN are NOT excluded
      -- These are personal financial issues that may not affect practice quality
      -- Uncomment below to exclude if compliance requires:
      -- AND COALESCE(c.CONTACT_HAS_DISCLOSED_BANKRUPT, FALSE) = FALSE
      -- AND COALESCE(c.CONTACT_HAS_DISCLOSED_JUDGMENT_OR_LIEN, FALSE) = FALSE
      
      -- Title exclusions
      AND NOT (
          UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTIONS ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE FINANCIAL PLANNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE WEALTH ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS%'
          OR UPPER(c.TITLE_NAME) LIKE '%WHOLESALER%'
          OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSISTANT%'
          OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE AGENT%'
          OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE%'
          OR UPPER(c.TITLE_NAME) LIKE '%BRANCH MANAGER%'
          -- Executive/Senior title exclusions
          OR UPPER(c.TITLE_NAME) LIKE '%CHIEF FINANCIAL OFFICER%'
          OR UPPER(c.TITLE_NAME) LIKE '%CFO%'
          OR UPPER(c.TITLE_NAME) LIKE '%CHIEF INVESTMENT OFFICER%'
          OR UPPER(c.TITLE_NAME) LIKE '%CIO%'
          OR UPPER(c.TITLE_NAME) LIKE '%VICE PRESIDENT%'
          OR UPPER(c.TITLE_NAME) LIKE '%VP %'  -- VP with space to avoid false positives
      )
),

-- ============================================================================
-- J.1 RECENT PROMOTEE EXCLUSION (V3.6.1)
-- ============================================================================
-- Analysis (January 8, 2026) found advisors with <5 years industry tenure
-- holding mid/senior titles convert at 0.29-0.45% (0.10-0.16x baseline).
-- 
-- These "recent promotees" likely don't have portable books yet:
-- - Recently promoted from junior roles
-- - Still building client relationships
-- - May not have decision-making authority to move
--
-- Conversion by career stage:
--   LIKELY_RECENT_PROMOTEE (Senior): 0.29% (0.10x lift) - 348 leads
--   LIKELY_RECENT_PROMOTEE (Mid):    0.45% (0.16x lift) - 1,567 leads
--   ESTABLISHED_PRODUCER:            0.73% (0.27x lift) - baseline comparison
--   FOUNDER_OWNER:                   1.07% (0.39x lift) - DO NOT EXCLUDE
--
-- Impact: Excludes ~1,915 low-converting leads from pipeline
-- ============================================================================
recent_promotee_exclusions AS (
    SELECT DISTINCT bp.crd
    FROM base_prospects bp
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON bp.crd = c.RIA_CONTACT_CRD_ID
    WHERE 
        -- Less than 5 years industry tenure
        COALESCE(SAFE_CAST(c.INDUSTRY_TENURE_MONTHS AS INT64), 0) < 60
        -- Has mid-level or senior title (suggests promotion)
        AND (
            UPPER(c.TITLE_NAME) LIKE '%FINANCIAL ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%WEALTH ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%INVESTMENT ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%FINANCIAL PLANNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%PORTFOLIO MANAGER%'
            OR UPPER(c.TITLE_NAME) LIKE '%SENIOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%MANAGING%'
            OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%'
            OR UPPER(c.TITLE_NAME) LIKE '%VP %'
            OR UPPER(c.TITLE_NAME) LIKE '%VICE PRESIDENT%'
        )
        -- Exclude if they're clearly still junior (shouldn't be on list anyway)
        AND NOT (
            UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE%'
            OR UPPER(c.TITLE_NAME) LIKE '%ASSISTANT%'
            OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%JUNIOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%INTERN%'
            OR UPPER(c.TITLE_NAME) LIKE '%TRAINEE%'
        )
        -- DO NOT exclude founders/owners - they convert at 1.07%
        AND NOT (
            UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
            OR UPPER(c.TITLE_NAME) LIKE '%OWNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%CEO%'
            OR UPPER(c.TITLE_NAME) LIKE '% PRESIDENT%'  -- Space before to avoid VP
        )
),

-- ============================================================================
-- K. ENRICH WITH ADVISOR HISTORY, FIRM METRICS, AND CERTIFICATIONS
-- ============================================================================
enriched_prospects AS (
    SELECT 
        bp.*,
        -- Enrichment fields
        COALESCE(am.total_firms, 1) as total_firms,
        COALESCE(am.total_firms, 1) - 1 as num_prior_firms,
        COALESCE(am.moves_3yr, 0) as moves_3yr,
        DATE_DIFF(CURRENT_DATE(), am.career_start_date, YEAR) as industry_tenure_years,
        DATE_DIFF(CURRENT_DATE(), am.career_start_date, MONTH) as industry_tenure_months,
        COALESCE(fm.firm_rep_count, SAFE_CAST(bp.firm_employee_count AS INT64), 1) as firm_rep_count,
        COALESCE(fm.arrivals_12mo, 0) as firm_arrivals_12mo,
        COALESCE(fm.departures_12mo, 0) as firm_departures_12mo,
        COALESCE(fm.firm_net_change_12mo, 0) as firm_net_change_12mo,
        COALESCE(fm.turnover_pct, 0) as firm_turnover_pct,
        CASE WHEN EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(bp.firm_name) LIKE ef.firm_pattern) THEN 1 ELSE 0 END as is_wirehouse,
        
        -- Certifications
        CASE WHEN c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%' THEN 1 ELSE 0 END as has_cfp,
        CASE WHEN c.REP_LICENSES LIKE '%Series 65%' AND c.REP_LICENSES NOT LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_65_only,
        CASE WHEN c.REP_LICENSES LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_7,
        CASE WHEN c.CONTACT_BIO LIKE '%CFA%' OR c.TITLE_NAME LIKE '%CFA%' THEN 1 ELSE 0 END as has_cfa,
        
        -- High-value wealth title
        CASE WHEN (
            UPPER(c.TITLE_NAME) LIKE '%WEALTH MANAGER%'
            OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%SENIOR WEALTH ADVISOR%'
        ) THEN 1 ELSE 0 END as is_hv_wealth_title,
        
        -- LinkedIn (derive has_linkedin from linkedin_url; treat literal string 'NULL' and empty as no URL)
        CASE
            WHEN TRIM(COALESCE(c.LINKEDIN_PROFILE_URL, '')) = '' THEN NULL
            WHEN UPPER(TRIM(COALESCE(c.LINKEDIN_PROFILE_URL, ''))) = 'NULL' THEN NULL
            ELSE TRIM(c.LINKEDIN_PROFILE_URL)
        END as linkedin_url,
        CASE
            WHEN TRIM(COALESCE(c.LINKEDIN_PROFILE_URL, '')) = '' THEN 0
            WHEN UPPER(TRIM(COALESCE(c.LINKEDIN_PROFILE_URL, ''))) = 'NULL' THEN 0
            ELSE 1
        END as has_linkedin,
        c.PRODUCING_ADVISOR as producing_advisor,
        -- V3.3.2: Average account size for T1G Growth Stage tier
        COALESCE(fas.avg_account_size, 0) as avg_account_size,
        COALESCE(fas.practice_maturity, 'UNKNOWN') as practice_maturity,
        -- V3.3.3: Portable custodian flag for T1B_PRIME tier
        COALESCE(fc.has_portable_custodian, 0) as has_portable_custodian,
        
        -- V3.6.0: Career Clock features
        ccs.cc_completed_jobs,
        ccs.cc_avg_prior_tenure_months,
        ccs.cc_tenure_cv,
        
        -- Calculate percent through cycle
        SAFE_DIVIDE(SAFE_CAST(bp.tenure_months AS FLOAT64), SAFE_CAST(ccs.cc_avg_prior_tenure_months AS FLOAT64)) as cc_pct_through_cycle,
        
        -- Career pattern classification
        CASE
            WHEN ccs.cc_tenure_cv IS NULL THEN 'No_Pattern'
            WHEN ccs.cc_tenure_cv < 0.3 THEN 'Clockwork'
            WHEN ccs.cc_tenure_cv < 0.5 THEN 'Semi_Predictable'
            WHEN ccs.cc_tenure_cv < 0.8 THEN 'Variable'
            ELSE 'Chaotic'
        END as cc_career_pattern,
        
        -- Cycle status (key for tiering)
        CASE
            WHEN ccs.cc_tenure_cv IS NULL THEN 'No_Pattern'
            WHEN ccs.cc_tenure_cv >= 0.5 THEN 'Unpredictable'
            WHEN SAFE_DIVIDE(SAFE_CAST(bp.tenure_months AS FLOAT64), SAFE_CAST(ccs.cc_avg_prior_tenure_months AS FLOAT64)) < 0.7 THEN 'Too_Early'
            WHEN SAFE_DIVIDE(SAFE_CAST(bp.tenure_months AS FLOAT64), SAFE_CAST(ccs.cc_avg_prior_tenure_months AS FLOAT64)) BETWEEN 0.7 AND 1.3 THEN 'In_Window'
            ELSE 'Overdue'
        END as cc_cycle_status,
        
        -- Boolean flags for tier logic
        CASE WHEN ccs.cc_tenure_cv < 0.5 
             AND SAFE_DIVIDE(SAFE_CAST(bp.tenure_months AS FLOAT64), SAFE_CAST(ccs.cc_avg_prior_tenure_months AS FLOAT64)) BETWEEN 0.7 AND 1.3
        THEN 1 ELSE 0 END as cc_is_in_move_window,
        
        CASE WHEN ccs.cc_tenure_cv < 0.5 
             AND SAFE_DIVIDE(SAFE_CAST(bp.tenure_months AS FLOAT64), SAFE_CAST(ccs.cc_avg_prior_tenure_months AS FLOAT64)) < 0.7
        THEN 1 ELSE 0 END as cc_is_too_early,
        
        -- Months until move window (for nurture timing)
        CASE
            WHEN ccs.cc_tenure_cv < 0.5 AND ccs.cc_avg_prior_tenure_months IS NOT NULL
            THEN GREATEST(0, CAST(SAFE_CAST(ccs.cc_avg_prior_tenure_months AS FLOAT64) * 0.7 - SAFE_CAST(bp.tenure_months AS FLOAT64) AS INT64))
            ELSE NULL
        END as cc_months_until_window
        
    FROM base_prospects bp
    LEFT JOIN advisor_moves am ON bp.crd = am.crd
    LEFT JOIN firm_metrics fm ON bp.firm_crd = fm.firm_crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c ON bp.crd = c.RIA_CONTACT_CRD_ID
    -- V3.6.0: Career Clock stats
    LEFT JOIN career_clock_stats ccs ON bp.crd = ccs.advisor_crd
    -- V3.3.1: Add discretionary ratio for portable book exclusion
    LEFT JOIN (
        SELECT 
            CRD_ID as firm_crd,
            SAFE_DIVIDE(SAFE_CAST(DISCRETIONARY_AUM AS FLOAT64), SAFE_CAST(TOTAL_AUM AS FLOAT64)) as discretionary_ratio,
            CASE 
                WHEN TOTAL_AUM IS NULL OR SAFE_CAST(TOTAL_AUM AS FLOAT64) = 0 THEN 'UNKNOWN'
                WHEN SAFE_DIVIDE(SAFE_CAST(DISCRETIONARY_AUM AS FLOAT64), SAFE_CAST(TOTAL_AUM AS FLOAT64)) < 0.50 THEN 'LOW_DISCRETIONARY'
                WHEN SAFE_DIVIDE(SAFE_CAST(DISCRETIONARY_AUM AS FLOAT64), SAFE_CAST(TOTAL_AUM AS FLOAT64)) >= 0.80 THEN 'HIGH_DISCRETIONARY'
                ELSE 'MODERATE_DISCRETIONARY'
            END as discretionary_tier
        FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    ) fd ON bp.firm_crd = fd.firm_crd
    -- V3.3.2: Add average account size for T1G Growth Stage tier
    LEFT JOIN (
        SELECT 
            CRD_ID as firm_crd,
            SAFE_DIVIDE(SAFE_CAST(TOTAL_AUM AS FLOAT64), SAFE_CAST(TOTAL_ACCOUNTS AS FLOAT64)) as avg_account_size,
            CASE 
                WHEN SAFE_DIVIDE(SAFE_CAST(TOTAL_AUM AS FLOAT64), SAFE_CAST(TOTAL_ACCOUNTS AS FLOAT64)) >= 250000 THEN 'ESTABLISHED'
                WHEN SAFE_DIVIDE(SAFE_CAST(TOTAL_AUM AS FLOAT64), SAFE_CAST(TOTAL_ACCOUNTS AS FLOAT64)) IS NULL THEN 'UNKNOWN'
                ELSE 'GROWTH_STAGE'
            END as practice_maturity
        FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
        WHERE SAFE_CAST(TOTAL_AUM AS FLOAT64) > 0 AND SAFE_CAST(TOTAL_ACCOUNTS AS FLOAT64) > 0
    ) fas ON bp.firm_crd = fas.firm_crd
    -- V3.3.3: Add portable custodian flag for T1B_PRIME tier
    LEFT JOIN (
        SELECT 
            CRD_ID as firm_crd,
            CASE WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                      OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%'
                      OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
                      OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
                 THEN 1 ELSE 0 
            END as has_portable_custodian
        FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    ) fc ON bp.firm_crd = fc.firm_crd
    WHERE COALESCE(fm.turnover_pct, 0) < 100
      -- V3.3.1: Exclude low discretionary firms (0.34x baseline)
      -- Allow NULL/Unknown - don't penalize missing data
      AND (fd.discretionary_ratio >= 0.50 OR fd.discretionary_ratio IS NULL)
      -- V3.6.1: Exclude recent promotees (<5yr tenure + mid/senior title)
      -- These convert at 0.29-0.45% (6-9x worse than baseline)
      AND bp.crd NOT IN (SELECT crd FROM recent_promotee_exclusions)
),

-- ============================================================================
-- J2. JOIN V4.2.0 SCORES + GAIN-BASED NARRATIVES + V4.2.0 FEATURES
-- ============================================================================
-- V4.2.0 Changes:
-- - 23 features (added age_bucket_encoded)
-- - Gain-based narratives (SHAP deprecated due to XGBoost base_score bug)
-- - Improved performance: AUC 0.6352, Lift 2.28x
-- ============================================================================
v4_enriched AS (
    SELECT 
        ep.*,
        -- V4.2.0 Score and percentile (from v4_prospect_scores table)
        COALESCE(v4.v4_score, 0.5) as v4_score,
        COALESCE(v4.v4_percentile, 50) as v4_percentile,
        COALESCE(v4.v4_deprioritize, FALSE) as v4_deprioritize,
        COALESCE(v4.v4_upgrade_candidate, FALSE) as v4_upgrade_candidate,
        
        -- V4.2.0 Gain-based narratives (replaces SHAP)
        -- Note: Column names kept as shap_* for backwards compatibility with downstream CTEs
        -- but values are now gain-based feature importance (not SHAP values)
        v4.shap_top1_feature,
        v4.shap_top1_value,
        v4.shap_top2_feature,
        v4.shap_top2_value,
        v4.shap_top3_feature,
        v4.shap_top3_value,
        v4.v4_narrative as v4_narrative,
        
        -- V4.2.0 Feature columns (23 features including age)
        COALESCE(v4f.is_recent_mover, 0) as v4_is_recent_mover,
        COALESCE(v4f.days_since_last_move, 9999) as v4_days_since_last_move,
        COALESCE(v4f.firm_departures_corrected, 0) as v4_firm_departures_corrected,
        COALESCE(v4f.bleeding_velocity_encoded, 0) as v4_bleeding_velocity_encoded,
        COALESCE(v4f.is_dual_registered, 0) as v4_is_dual_registered,
        -- V4.2.0: Age feature (NEW)
        COALESCE(v4f.age_bucket_encoded, 2) as v4_age_bucket_encoded  -- Default to 50-64 bucket
    FROM enriched_prospects ep
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 
        ON ep.crd = v4.crd
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_features` v4f
        ON ep.crd = v4f.crd
),

-- ============================================================================
-- K. APPLY V4.2.0 DEPRIORITIZATION FILTER (Bottom 20% excluded)
-- ============================================================================
-- Optimization: Remove bottom 20% V4.2.0 scores to improve overall conversion rate
-- V4.2.0 bottom 20% converts at 1.21% (0.31x baseline) - strong deprioritization signal
v4_filtered AS (
    SELECT *
    FROM v4_enriched
    WHERE v4_percentile >= 20 OR v4_percentile IS NULL  -- Filter bottom 20%
),

-- ============================================================================
-- K2. APPLY V3.6.0 TIER LOGIC WITH CAREER CLOCK (V3.6.0)
-- ============================================================================
scored_prospects AS (
    SELECT 
        ep.*,
        
        -- Score tier (V3.6.0 - Career Clock tiers added at top)
        CASE 
            -- ================================================================
            -- TIER 0: CAREER CLOCK PRIORITY TIERS (V3.6.0)
            -- These are advisors with predictable patterns who are "due" to move
            -- Analysis: In_Window converts 2.43x vs No_Pattern within same age group
            -- ================================================================
            
            -- TIER_0A: Prime Mover + In Move Window (5.59% conversion)
            -- Combines T1 criteria with optimal timing signal
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.tenure_years BETWEEN 1 AND 4
                 AND ep.industry_tenure_years BETWEEN 5 AND 15
                 AND ep.firm_net_change_12mo < 0
                 AND ep.is_wirehouse = 0
            THEN 'TIER_0A_PRIME_MOVER_DUE'
            
            -- TIER_0B: Small Firm + In Move Window
            -- Small firm advisors who are personally "due" to move
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.firm_rep_count <= 10
                 AND ep.is_wirehouse = 0
            THEN 'TIER_0B_SMALL_FIRM_DUE'
            
            -- TIER_0C: Clockwork Due (any predictable advisor in window)
            -- Rescues STANDARD leads who have optimal timing
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.is_wirehouse = 0
            THEN 'TIER_0C_CLOCKWORK_DUE'
            
            -- V3.3.3: T1B_PRIME - Zero Friction Bleeder (HIGHEST PRIORITY - 13.64% conversion)
            WHEN has_series_65_only = 1
                 AND has_portable_custodian = 1
                 AND firm_rep_count <= 10
                 AND firm_net_change_12mo <= -3
                 AND has_cfp = 0
                 AND is_wirehouse = 0
            THEN 'TIER_1B_PRIME_ZERO_FRICTION'
            
            WHEN (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years >= 5 AND firm_net_change_12mo < 0 AND has_cfp = 1 AND is_wirehouse = 0) THEN 'TIER_1A_PRIME_MOVER_CFP'
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 'TIER_1_PRIME_MOVER'
            WHEN (is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND is_wirehouse = 0) THEN 'TIER_1F_HV_WEALTH_BLEEDER'
            -- V3.3.3: T1G_ENHANCED - Sweet Spot Growth Advisor ($500K-$2M)
            WHEN (industry_tenure_months BETWEEN 60 AND 180 
                  AND avg_account_size BETWEEN 500000 AND 2000000
                  AND firm_net_change_12mo > -3 
                  AND is_wirehouse = 0) THEN 'TIER_1G_ENHANCED_SWEET_SPOT'
            -- V3.3.3: T1G_REMAINDER - Growth Stage outside sweet spot
            WHEN (industry_tenure_months BETWEEN 60 AND 180 
                  AND avg_account_size >= 250000 
                  AND (avg_account_size < 500000 OR avg_account_size > 2000000)
                  AND firm_net_change_12mo > -3 
                  AND is_wirehouse = 0) THEN 'TIER_1G_GROWTH_STAGE'
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 'TIER_2_PROVEN_MOVER'
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5) THEN 'TIER_3_MODERATE_BLEEDER'
            -- OPTION C: TIER_4_EXPERIENCED_MOVER EXCLUDED (converts at baseline 2.74%, no value)
            -- OPTION C: TIER_5_HEAVY_BLEEDER EXCLUDED (marginal lift 3.42%, not worth including)
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 'STANDARD'  -- Map to STANDARD (excluded)
            WHEN (firm_net_change_12mo <= -10 AND industry_tenure_years >= 5) THEN 'STANDARD'  -- Map to STANDARD (excluded)
            
            -- ================================================================
            -- EXISTING TIER 1 TIERS (unchanged)
            -- ================================================================
            
            -- V3.3.3: T1B_PRIME - Zero Friction Bleeder (HIGHEST PRIORITY - 13.64% conversion)
            WHEN ep.has_series_65_only = 1
                 AND ep.has_portable_custodian = 1
                 AND ep.firm_rep_count <= 10
                 AND ep.firm_net_change_12mo <= -3
                 AND ep.has_cfp = 0
                 AND ep.is_wirehouse = 0
            THEN 'TIER_1B_PRIME_ZERO_FRICTION'
            
            WHEN (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years >= 5 AND ep.firm_net_change_12mo < 0 AND ep.has_cfp = 1 AND ep.is_wirehouse = 0) THEN 'TIER_1A_PRIME_MOVER_CFP'
            WHEN (((ep.tenure_years BETWEEN 1 AND 3 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.firm_rep_count <= 50 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 3 AND ep.firm_rep_count <= 10 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0))
                  AND ep.has_series_65_only = 1) THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            WHEN ((ep.tenure_years BETWEEN 1 AND 3 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.firm_rep_count <= 50 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 3 AND ep.firm_rep_count <= 10 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0)) THEN 'TIER_1_PRIME_MOVER'
            WHEN (ep.is_hv_wealth_title = 1 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0) THEN 'TIER_1F_HV_WEALTH_BLEEDER'
            -- V3.3.3: T1G_ENHANCED - Sweet Spot Growth Advisor ($500K-$2M)
            WHEN (ep.industry_tenure_months BETWEEN 60 AND 180 
                  AND ep.avg_account_size BETWEEN 500000 AND 2000000
                  AND ep.firm_net_change_12mo > -3 
                  AND ep.is_wirehouse = 0) THEN 'TIER_1G_ENHANCED_SWEET_SPOT'
            -- V3.3.3: T1G_REMAINDER - Growth Stage outside sweet spot
            WHEN (ep.industry_tenure_months BETWEEN 60 AND 180 
                  AND ep.avg_account_size >= 250000 
                  AND (ep.avg_account_size < 500000 OR ep.avg_account_size > 2000000)
                  AND ep.firm_net_change_12mo > -3 
                  AND ep.is_wirehouse = 0) THEN 'TIER_1G_GROWTH_STAGE'
            WHEN (ep.num_prior_firms >= 3 AND ep.industry_tenure_years >= 5) THEN 'TIER_2_PROVEN_MOVER'
            WHEN (ep.firm_net_change_12mo BETWEEN -10 AND -1 AND ep.industry_tenure_years >= 5) THEN 'TIER_3_MODERATE_BLEEDER'
            -- OPTION C: TIER_4_EXPERIENCED_MOVER EXCLUDED (converts at baseline 2.74%, no value)
            -- OPTION C: TIER_5_HEAVY_BLEEDER EXCLUDED (marginal lift 3.42%, not worth including)
            WHEN (ep.industry_tenure_years >= 20 AND ep.tenure_years BETWEEN 1 AND 4) THEN 'STANDARD'  -- Map to STANDARD (excluded)
            WHEN (ep.firm_net_change_12mo <= -10 AND ep.industry_tenure_years >= 5) THEN 'STANDARD'  -- Map to STANDARD (excluded)
            
            -- ================================================================
            -- NURTURE: Too Early (V3.6.0 - EXCLUDED from active list)
            -- Advisors too early in cycle - add to nurture sequence
            -- ================================================================
            WHEN ep.cc_is_too_early = 1
                 AND ep.firm_net_change_12mo >= -10  -- Not at heavy bleeding firm
            THEN 'TIER_NURTURE_TOO_EARLY'
            
            ELSE 'STANDARD'
        END as score_tier,
        
        -- Priority rank (V3.6.0 UPDATED - Career Clock tiers first)
        CASE 
            -- Career Clock Tiers: Highest priority (ranks 1-3)
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.tenure_years BETWEEN 1 AND 4
                 AND ep.industry_tenure_years BETWEEN 5 AND 15
                 AND ep.firm_net_change_12mo < 0
                 AND ep.is_wirehouse = 0
            THEN 1  -- TIER_0A
            
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.firm_rep_count <= 10
                 AND ep.is_wirehouse = 0
            THEN 2  -- TIER_0B
            
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.is_wirehouse = 0
            THEN 3  -- TIER_0C
            -- T1B_PRIME: Now rank 4 (was 1)
            WHEN ep.has_series_65_only = 1
                 AND ep.has_portable_custodian = 1
                 AND ep.firm_rep_count <= 10
                 AND ep.firm_net_change_12mo <= -3
                 AND ep.has_cfp = 0
                 AND ep.is_wirehouse = 0
            THEN 4
            
            -- T1A: Now rank 5 (was 2)
            WHEN (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years >= 5 AND ep.firm_net_change_12mo < 0 AND ep.has_cfp = 1 AND ep.is_wirehouse = 0) THEN 5
            
            -- T1G_ENHANCED: Now rank 6 (was 3)
            WHEN (ep.industry_tenure_months BETWEEN 60 AND 180 
                  AND ep.avg_account_size BETWEEN 500000 AND 2000000
                  AND ep.firm_net_change_12mo > -3 
                  AND ep.is_wirehouse = 0) THEN 6
            
            -- T1B: Now rank 7 (was 4)
            WHEN (((ep.tenure_years BETWEEN 1 AND 3 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.firm_rep_count <= 50 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 3 AND ep.firm_rep_count <= 10 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0))
                  AND ep.has_series_65_only = 1) THEN 7
            
            -- T1G_REMAINDER: Now rank 8 (was 5)
            WHEN (ep.industry_tenure_months BETWEEN 60 AND 180 
                  AND ep.avg_account_size >= 250000 
                  AND (ep.avg_account_size < 500000 OR ep.avg_account_size > 2000000)
                  AND ep.firm_net_change_12mo > -3 
                  AND ep.is_wirehouse = 0) THEN 8
            
            -- T1: Now rank 9 (was 6)
            WHEN ((ep.tenure_years BETWEEN 1 AND 3 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.firm_rep_count <= 50 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 3 AND ep.firm_rep_count <= 10 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0)) THEN 9
            
            -- T1F: Now rank 10 (was 7)
            WHEN (ep.is_hv_wealth_title = 1 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0) THEN 10
            
            -- T2: Now rank 11 (was 8)
            WHEN (ep.num_prior_firms >= 3 AND ep.industry_tenure_years >= 5) THEN 11
            
            -- T3: Now rank 12 (was 9)
            WHEN (ep.firm_net_change_12mo BETWEEN -10 AND -1 AND ep.industry_tenure_years >= 5) THEN 12
            
            -- OPTION C: TIER_4 and TIER_5 excluded (map to 99)
            WHEN (ep.industry_tenure_years >= 20 AND ep.tenure_years BETWEEN 1 AND 4) THEN 99  -- TIER_4 excluded
            WHEN (ep.firm_net_change_12mo <= -10 AND ep.industry_tenure_years >= 5) THEN 99  -- TIER_5 excluded
            
            -- NURTURE: Near bottom
            WHEN ep.cc_is_too_early = 1
                 AND ep.firm_net_change_12mo >= -10
            THEN 97
            
            ELSE 99
        END as priority_rank,
        
        -- Expected conversion rate (V3.6.0 UPDATED)
        CASE 
            -- Career Clock Tiers (V3.6.0)
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.tenure_years BETWEEN 1 AND 4
                 AND ep.industry_tenure_years BETWEEN 5 AND 15
                 AND ep.firm_net_change_12mo < 0
                 AND ep.is_wirehouse = 0
            THEN 0.0559  -- TIER_0A: 5.59% (from analysis)
            
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.firm_rep_count <= 10
                 AND ep.is_wirehouse = 0
            THEN 0.0550  -- TIER_0B: 5.50% (estimated)
            
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.is_wirehouse = 0
            THEN 0.0507  -- TIER_0C: 5.07% (from analysis)
            
            -- NURTURE
            WHEN ep.cc_is_too_early = 1
                 AND ep.firm_net_change_12mo >= -10
            THEN 0.0372  -- TIER_NURTURE: 3.72% (from analysis)
            -- T1B_PRIME: 13.64%
            WHEN ep.has_series_65_only = 1
                 AND ep.has_portable_custodian = 1
                 AND ep.firm_rep_count <= 10
                 AND ep.firm_net_change_12mo <= -3
                 AND ep.has_cfp = 0
                 AND ep.is_wirehouse = 0
            THEN 0.1364  -- V3.3.3: 13.64% conversion
            -- T1A: 10.00%
            WHEN (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years >= 5 AND ep.firm_net_change_12mo < 0 AND ep.has_cfp = 1 AND ep.is_wirehouse = 0) THEN 0.1000  -- V3.3.3: 10.00% conversion
            -- T1G_ENHANCED: 9.09%
            WHEN (ep.industry_tenure_months BETWEEN 60 AND 180 
                  AND ep.avg_account_size BETWEEN 500000 AND 2000000
                  AND ep.firm_net_change_12mo > -3 
                  AND ep.is_wirehouse = 0) THEN 0.0909  -- V3.3.3: 9.09% conversion
            -- T1B: 5.49%
            WHEN (((ep.tenure_years BETWEEN 1 AND 3 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.firm_rep_count <= 50 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 3 AND ep.firm_rep_count <= 10 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0))
                  AND ep.has_series_65_only = 1) THEN 0.0549  -- V3.3.3: 5.49% conversion
            -- T1G_REMAINDER: 5.08%
            WHEN (ep.industry_tenure_months BETWEEN 60 AND 180 
                  AND ep.avg_account_size >= 250000 
                  AND (ep.avg_account_size < 500000 OR ep.avg_account_size > 2000000)
                  AND ep.firm_net_change_12mo > -3 
                  AND ep.is_wirehouse = 0) THEN 0.0508  -- V3.3.3: 5.08% conversion
            WHEN ((ep.tenure_years BETWEEN 1 AND 3 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.firm_rep_count <= 50 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 3 AND ep.firm_rep_count <= 10 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0)) THEN 0.071
            WHEN (ep.is_hv_wealth_title = 1 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0) THEN 0.065
            WHEN (ep.num_prior_firms >= 3 AND ep.industry_tenure_years >= 5) THEN 0.052
            WHEN (ep.firm_net_change_12mo BETWEEN -10 AND -1 AND ep.industry_tenure_years >= 5) THEN 0.044
            -- OPTION C: TIER_4 and TIER_5 excluded (map to STANDARD rate)
            WHEN (ep.industry_tenure_years >= 20 AND ep.tenure_years BETWEEN 1 AND 4) THEN 0.025  -- TIER_4 excluded
            WHEN (ep.firm_net_change_12mo <= -10 AND ep.industry_tenure_years >= 5) THEN 0.025  -- TIER_5 excluded
            ELSE 0.025
        END as expected_conversion_rate,
        
        -- V3 TIER NARRATIVES (V3.6.0 - Career Clock added)
        CASE 
            -- Career Clock Narratives
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.tenure_years BETWEEN 1 AND 4
                 AND ep.industry_tenure_years BETWEEN 5 AND 15
                 AND ep.firm_net_change_12mo < 0
                 AND ep.is_wirehouse = 0
            THEN CONCAT(
                'CAREER CLOCK + PRIME MOVER: ', ep.first_name, ' matches Prime Mover criteria AND ',
                'has a predictable career pattern showing they are in their "move window" ',
                '(', CAST(ROUND(ep.cc_pct_through_cycle * 100, 0) AS STRING), '% through typical tenure). ',
                'Career Clock + Prime Mover leads convert at 5.59% (2.43x vs advisors with no pattern). ',
                'Firm has lost ', CAST(ABS(ep.firm_net_change_12mo) AS STRING), ' advisors.'
            )
            
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.firm_rep_count <= 10
                 AND ep.is_wirehouse = 0
            THEN CONCAT(
                'CAREER CLOCK + SMALL FIRM: ', ep.first_name, ' is at a small firm (', 
                CAST(ep.firm_rep_count AS STRING), ' reps) AND is in their personal "move window" ',
                '(', CAST(ROUND(ep.cc_pct_through_cycle * 100, 0) AS STRING), '% through typical tenure). ',
                'Small firm + optimal timing = high conversion potential.'
            )
            
            WHEN ep.cc_is_in_move_window = 1
                 AND ep.is_wirehouse = 0
            THEN CONCAT(
                'CLOCKWORK DUE: ', ep.first_name, ' has a predictable career pattern and is currently ',
                'in their "move window" (', CAST(ROUND(ep.cc_pct_through_cycle * 100, 0) AS STRING), 
                '% through typical ', CAST(ROUND(ep.cc_avg_prior_tenure_months, 0) AS STRING), 
                '-month tenure cycle). Even without other priority signals, timing alone makes them ',
                '1.33x more likely to convert (5.07% vs 3.82% baseline).'
            )
            
            WHEN ep.cc_is_too_early = 1
                 AND ep.firm_net_change_12mo >= -10
            THEN CONCAT(
                'NURTURE - TOO EARLY: ', ep.first_name, ' has a predictable career pattern but is ',
                'only ', CAST(ROUND(ep.cc_pct_through_cycle * 100, 0) AS STRING), '% through their typical cycle. ',
                'Contact in ~', CAST(COALESCE(ep.cc_months_until_window, 0) AS STRING), ' months when they enter move window. ',
                'Current conversion rate: 3.72% (below baseline).'
            )
            -- [KEEP ALL EXISTING NARRATIVES...]
            WHEN (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years >= 5 AND ep.firm_net_change_12mo < 0 AND ep.has_cfp = 1 AND ep.is_wirehouse = 0) THEN
                CONCAT(ep.first_name, ' is a CFP holder at ', ep.firm_name, ', which has lost ', CAST(ABS(ep.firm_net_change_12mo) AS STRING), 
                       ' advisors (net) in the past year. CFP designation indicates book ownership and client relationships. ',
                       'With ', CAST(ep.tenure_years AS STRING), ' years at the firm and ', CAST(ep.industry_tenure_years AS STRING), 
                       ' years of experience, this is an ULTRA-PRIORITY lead. Tier 1A: 10.00% expected conversion.')
            WHEN (((ep.tenure_years BETWEEN 1 AND 3 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.firm_rep_count <= 50 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 3 AND ep.firm_rep_count <= 10 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0))
                  AND ep.has_series_65_only = 1) THEN
                CONCAT(ep.first_name, ' is a fee-only RIA advisor (Series 65 only) at ', ep.firm_name, 
                       '. Pure RIA advisors have no broker-dealer ties, making transitions easier. ',
                       'Tier 1B: Prime Mover (Pure RIA) with 5.49% expected conversion.')
            WHEN ((ep.tenure_years BETWEEN 1 AND 3 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.firm_rep_count <= 50 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 3 AND ep.firm_rep_count <= 10 AND ep.is_wirehouse = 0)
                  OR (ep.tenure_years BETWEEN 1 AND 4 AND ep.industry_tenure_years BETWEEN 5 AND 15 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0)) THEN
                CONCAT(ep.first_name, ' has been at ', ep.firm_name, ' for ', CAST(ep.tenure_years AS STRING), ' years with ', 
                       CAST(ep.industry_tenure_years AS STRING), ' years of experience. ',
                       CASE WHEN ep.firm_net_change_12mo < 0 THEN CONCAT('The firm has lost ', CAST(ABS(ep.firm_net_change_12mo) AS STRING), ' advisors. ') ELSE '' END,
                       'Prime Mover tier with 7.1% expected conversion.')
            WHEN (ep.is_hv_wealth_title = 1 AND ep.firm_net_change_12mo < 0 AND ep.is_wirehouse = 0) THEN
                CONCAT(ep.first_name, ' holds a High-Value Wealth title at ', ep.firm_name, ', which has lost ', 
                       CAST(ABS(ep.firm_net_change_12mo) AS STRING), ' advisors. Tier 1F: HV Wealth (Bleeding) with 6.5% expected conversion.')
            WHEN (ep.num_prior_firms >= 3 AND ep.industry_tenure_years >= 5) THEN
                CONCAT(ep.first_name, ' has worked at ', CAST(ep.num_prior_firms + 1 AS STRING), ' different firms over ', 
                       CAST(ep.industry_tenure_years AS STRING), ' years. History of mobility demonstrates willingness to change. ',
                       'Proven Mover tier with 5.2% expected conversion.')
            WHEN (ep.firm_net_change_12mo BETWEEN -10 AND -1 AND ep.industry_tenure_years >= 5) THEN
                CONCAT(ep.firm_name, ' has experienced moderate advisor departures (net change: ', CAST(ep.firm_net_change_12mo AS STRING), '). ',
                       ep.first_name, ' is likely hearing about opportunities from departing colleagues. Moderate Bleeder tier: 4.4% expected conversion.')
            -- OPTION C: TIER_4 and TIER_5 excluded (map to STANDARD narrative)
            WHEN (ep.industry_tenure_years >= 20 AND ep.tenure_years BETWEEN 1 AND 4) THEN
                CONCAT(ep.first_name, ' at ', ep.firm_name, ' - STANDARD tier lead (TIER_4 excluded per Option C optimization).')
            WHEN (ep.firm_net_change_12mo <= -10 AND ep.industry_tenure_years >= 5) THEN
                CONCAT(ep.first_name, ' at ', ep.firm_name, ' - STANDARD tier lead (TIER_5 excluded per Option C optimization).')
            ELSE
                CONCAT(ep.first_name, ' at ', ep.firm_name, ' - STANDARD tier lead.')
        END as v3_score_narrative
        
    FROM v4_filtered ep
),

-- ============================================================================
-- M. RANK PROSPECTS
-- ============================================================================
ranked_prospects AS (
    SELECT 
        sp.*,
        CASE 
            WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 1
            WHEN sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids) THEN 2
            ELSE 99
        END as source_priority,
        ROW_NUMBER() OVER (
            PARTITION BY sp.firm_crd 
            ORDER BY 
                CASE WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 0 ELSE 1 END,
                sp.priority_rank,
                sp.v4_percentile DESC,
                sp.crd
        ) as rank_within_firm
    FROM scored_prospects sp
    WHERE sp.prospect_type = 'NEW_PROSPECT'
       OR sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids)
),

-- ============================================================================
-- N. APPLY FIRM DIVERSITY CAP
-- ============================================================================
diversity_filtered AS (
    SELECT * FROM ranked_prospects
    WHERE rank_within_firm <= 50 
      AND source_priority < 99
),

-- ============================================================================
-- O. APPLY TIER QUOTAS (V3.7.0 — Rules-Based Only, No STANDARD Backfill)
-- ============================================================================
-- V3.7.0: STANDARD_HIGH_V4 eliminated. All leads are rules-based tiers only.
tier_limited AS (
    SELECT 
        df.*,
        -- V3.7.0: STANDARD_HIGH_V4 backfill for filling SGAs to 200
        CASE WHEN df.score_tier = 'STANDARD' THEN 1 ELSE 0 END as is_high_v4_standard,
        -- STANDARD_HIGH_V4: map STANDARD to this for backfill; rules-based tiers unchanged
        CASE WHEN df.score_tier = 'STANDARD' THEN 'STANDARD_HIGH_V4' ELSE df.score_tier END as final_tier,
        -- Final expected rate (V3.4.0)
        CASE 
            -- Career Clock Tiers (V3.4.0)
            WHEN df.score_tier = 'TIER_0A_PRIME_MOVER_DUE' THEN 0.1613  -- 16.13%
            WHEN df.score_tier = 'TIER_0B_SMALL_FIRM_DUE' THEN 0.1200  -- 12.00%
            WHEN df.score_tier = 'TIER_0C_CLOCKWORK_DUE' THEN 0.1000  -- 10.00%
            WHEN df.score_tier = 'TIER_1B_PRIME_ZERO_FRICTION' THEN 0.1364  -- V3.3.3: 13.64% conversion
            WHEN df.score_tier = 'TIER_1A_PRIME_MOVER_CFP' THEN 0.1000      -- V3.3.3: 10.00% conversion
            WHEN df.score_tier = 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 0.0909  -- V3.3.3: 9.09% conversion
            WHEN df.score_tier = 'TIER_1B_PRIME_MOVER_SERIES65' THEN 0.0549  -- V3.3.3: 5.49% conversion
            WHEN df.score_tier = 'TIER_1G_GROWTH_STAGE' THEN 0.0508          -- V3.3.3: 5.08% conversion
            WHEN df.score_tier = 'TIER_1F_HV_WEALTH_BLEEDER' THEN 0.0606  -- Updated from optimization
            WHEN df.score_tier = 'TIER_2_PROVEN_MOVER' THEN 0.0591  -- Updated from optimization
            WHEN df.score_tier = 'TIER_1_PRIME_MOVER' THEN 0.0476  -- Updated from optimization
            WHEN df.score_tier = 'TIER_1A_PRIME_MOVER_CFP' THEN 0.0274  -- Updated from optimization
            WHEN df.score_tier = 'STANDARD' THEN 0.025   -- STANDARD_HIGH_V4 backfill (baseline)
            ELSE df.expected_conversion_rate 
        END as final_expected_rate,
        -- FINAL NARRATIVE: V3 rules-based only (no STANDARD_HIGH_V4 in V3.7.0)
        df.v3_score_narrative as score_narrative,
        ROW_NUMBER() OVER (
            PARTITION BY df.score_tier
            ORDER BY 
                df.source_priority,
                df.has_linkedin DESC,
                df.v4_percentile DESC,
                df.priority_rank,
                CASE WHEN df.firm_net_change_12mo < 0 THEN ABS(df.firm_net_change_12mo) ELSE 0 END DESC,
                df.crd
        ) as tier_rank
    FROM diversity_filtered df
    -- V3.7.0: Include STANDARD for STANDARD_HIGH_V4 backfill; rules-based tiers + STANDARD
    -- OPTION C: EXCLUDE TIER_4 and TIER_5 (they convert at/below baseline)
    WHERE (
        (df.score_tier != 'STANDARD' 
         AND df.score_tier NOT IN ('TIER_4_EXPERIENCED_MOVER', 'TIER_5_HEAVY_BLEEDER', 'TIER_NURTURE_TOO_EARLY'))
        OR df.score_tier = 'STANDARD'
    )
    AND df.firm_rep_count <= 50                       -- Size limit
),

-- ============================================================================
-- P. DEDUPLICATE BEFORE TIER QUOTAS (CRITICAL: Preserve priority tier leads)
-- ============================================================================
-- Deduplicate by CRD BEFORE applying tier quotas to ensure priority tiers aren't lost
-- Keep the best-ranked instance of each CRD
-- ============================================================================
deduplicated_before_quotas AS (
    SELECT 
        tl.*
    FROM tier_limited tl
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY tl.crd
        ORDER BY 
            CASE tl.final_tier
                -- Career Clock (highest)
                WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
                WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
                WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
                -- Zero Friction & Priority
                WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 6
                WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 7
                WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 8
                WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 9
                WHEN 'TIER_1G_GROWTH_STAGE' THEN 10
                WHEN 'TIER_1_PRIME_MOVER' THEN 11
                WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 12
                WHEN 'TIER_2_PROVEN_MOVER' THEN 13
                WHEN 'TIER_3_MODERATE_BLEEDER' THEN 14
                WHEN 'STANDARD_HIGH_V4' THEN 15
            END,
            tl.source_priority,
            tl.has_linkedin DESC,
            tl.v4_percentile DESC,
            tl.crd
    ) = 1
),

-- ============================================================================
-- P2. LINKEDIN PRIORITIZATION (Dynamic tier quotas based on SGA count)
-- ============================================================================
linkedin_prioritized AS (
    SELECT 
        dtl.*,
        ROW_NUMBER() OVER (
            ORDER BY 
                CASE final_tier
                    -- Career Clock (highest)
                    WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
                    WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
                    WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
                    -- Zero Friction & Priority
                    WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 6  -- V3.3.3: Highest priority
                    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 7
                    WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 8  -- V3.3.3: Higher than T1B
                    WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 9
                    WHEN 'TIER_1G_GROWTH_STAGE' THEN 10  -- V3.3.3: New tier
                    WHEN 'TIER_1_PRIME_MOVER' THEN 11
                    WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 12
                    WHEN 'TIER_2_PROVEN_MOVER' THEN 13
                    WHEN 'TIER_3_MODERATE_BLEEDER' THEN 14
                    WHEN 'STANDARD_HIGH_V4' THEN 15
                END,
                source_priority,
                has_linkedin DESC,
                v4_percentile DESC,
                crd
        ) as overall_rank,
        CASE 
            WHEN has_linkedin = 0 THEN
                ROW_NUMBER() OVER (
                    PARTITION BY CASE WHEN has_linkedin = 0 THEN 1 ELSE 0 END
                    ORDER BY 
                        CASE final_tier
                            -- Career Clock (highest)
                            WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
                            WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
                            WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
                            -- Zero Friction & Priority
                            WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 6  -- V3.3.3: Highest priority
                            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 7
                            WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 8  -- V3.3.3: Higher than T1B
                            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 9
                            WHEN 'TIER_1G_GROWTH_STAGE' THEN 10  -- V3.3.3: New tier
                            WHEN 'TIER_1_PRIME_MOVER' THEN 11
                            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 12
                            WHEN 'TIER_2_PROVEN_MOVER' THEN 13
                            WHEN 'TIER_3_MODERATE_BLEEDER' THEN 14
                            WHEN 'STANDARD_HIGH_V4' THEN 15
                            -- OPTION C: TIER_4 and TIER_5 excluded
                        END,
                        source_priority,
                        v4_percentile DESC,
                        crd
                )
            ELSE NULL
        END as no_linkedin_rank,
        ROW_NUMBER() OVER (
            PARTITION BY final_tier
            ORDER BY 
                source_priority,
                has_linkedin DESC,
                v4_percentile DESC,
                priority_rank,
                CASE WHEN firm_net_change_12mo < 0 THEN ABS(firm_net_change_12mo) ELSE 0 END DESC,
                crd
        ) as tier_rank
    FROM deduplicated_before_quotas dtl
    CROSS JOIN sga_constants sc
    WHERE 
        -- V3.7.0: Tier quotas (rules-based only; no STANDARD_HIGH_V4)
        (final_tier = 'TIER_0A_PRIME_MOVER_DUE' AND tier_rank <= CAST(100 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_0B_SMALL_FIRM_DUE' AND tier_rank <= CAST(150 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_0C_CLOCKWORK_DUE' AND tier_rank <= CAST(100 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_1A_PRIME_MOVER_CFP' AND tier_rank <= CAST(50 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_1B_PRIME_ZERO_FRICTION' AND tier_rank <= CAST(50 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_1G_ENHANCED_SWEET_SPOT' AND tier_rank <= CAST(75 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_1B_PRIME_MOVER_SERIES65' AND tier_rank <= CAST(150 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_1G_GROWTH_STAGE' AND tier_rank <= CAST(75 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_1_PRIME_MOVER' AND tier_rank <= CAST(380 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_1F_HV_WEALTH_BLEEDER' AND tier_rank <= CAST(50 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_2_PROVEN_MOVER' AND tier_rank <= CAST(1600 * sc.total_sgas / 12.0 AS INT64))
        OR (final_tier = 'TIER_3_MODERATE_BLEEDER' AND tier_rank <= CAST(72 * sc.total_sgas / 12.0 AS INT64))
        -- STANDARD_HIGH_V4 backfill: take up to 500 per 12 SGAs to fill toward 200/SGA
        OR (final_tier = 'STANDARD_HIGH_V4' AND v4_percentile >= 80 AND tier_rank <= CAST(500 * sc.total_sgas / 12.0 AS INT64))
),

-- ============================================================================
-- Q. DEDUPLICATED LEADS (Already deduplicated, just pass through)
-- ============================================================================
deduplicated_leads AS (
    SELECT 
        lp.*
    FROM linkedin_prioritized lp
    -- Already deduplicated in deduplicated_before_quotas, so no need to dedupe again
),

-- ============================================================================
-- Q2. SGA ASSIGNMENT (Equitable distribution based on expected conversion rate)
-- ============================================================================
-- Strategy: Distribute leads using stratified round-robin within conversion rate buckets
-- This ensures each SGA gets similar expected conversion value, not just tier distribution
-- Each SGA will receive exactly 200 leads with equitable conversion rate distribution
leads_with_conv_bucket AS (
    SELECT 
        dl.*,
        sc.total_leads_needed,
        sc.total_sgas,
        -- Create conversion rate buckets for stratified distribution
        CASE 
            WHEN dl.final_expected_rate >= 0.10 THEN 'HIGH_CONV'      -- 10%+ (T1B_PRIME, T1A, T1G_ENHANCED)
            WHEN dl.final_expected_rate >= 0.06 THEN 'MED_HIGH_CONV'  -- 6-10% (T1, T1F)
            WHEN dl.final_expected_rate >= 0.05 THEN 'MED_CONV'       -- 5-6% (T2)
            WHEN dl.final_expected_rate >= 0.04 THEN 'MED_LOW_CONV'   -- 4-5% (T3, T4)
            WHEN dl.final_expected_rate >= 0.03 THEN 'LOW_CONV'       -- 3-4% (T5; no STANDARD_HIGH_V4 in V3.7.0)
            ELSE 'VERY_LOW_CONV'                                       -- <3% (should not appear)
        END as conv_rate_bucket,
        -- Rank within conversion bucket and tier for round-robin
        ROW_NUMBER() OVER (
            PARTITION BY 
                CASE 
                    WHEN dl.final_expected_rate >= 0.10 THEN 'HIGH_CONV'
                    WHEN dl.final_expected_rate >= 0.06 THEN 'MED_HIGH_CONV'
                    WHEN dl.final_expected_rate >= 0.05 THEN 'MED_CONV'
                    WHEN dl.final_expected_rate >= 0.04 THEN 'MED_LOW_CONV'
                    WHEN dl.final_expected_rate >= 0.03 THEN 'LOW_CONV'
                    ELSE 'VERY_LOW_CONV'
                END,
                dl.final_tier
            ORDER BY dl.overall_rank
        ) as rank_within_bucket
    FROM deduplicated_leads dl
    CROSS JOIN sga_constants sc
    WHERE 
        dl.has_linkedin = 1 
        OR (dl.has_linkedin = 0 AND dl.no_linkedin_rank <= CAST(600 * sc.total_sgas / 12.0 AS INT64))
    -- Increased from 240 to 600 so leads that lost has_linkedin (e.g. FinTrx "NULL" string) still have room
    -- The SGA assignment will handle distributing them
),

-- Assign SGA using round-robin within conversion buckets
-- This ensures each SGA gets leads from all conversion buckets proportionally
leads_assigned AS (
    SELECT 
        l.*,
        -- Calculate which SGA number this lead should get (round-robin)
        MOD(l.rank_within_bucket - 1, l.total_sgas) + 1 as assigned_sga_num,
        -- Flag for partner/founder leads (case-insensitive)
        CASE 
            WHEN UPPER(COALESCE(l.job_title, '')) LIKE '%PARTNER%' 
                 OR UPPER(COALESCE(l.job_title, '')) LIKE '%FOUNDER%' 
            THEN 1 
            ELSE 0 
        END as is_partner_founder
    FROM leads_with_conv_bucket l
),

-- Group partner/founder leads by firm and assign to same SGA
-- This prevents multiple SGAs from reaching out to the same firm's leadership
partner_founder_groups AS (
    SELECT DISTINCT
        firm_crd,
        -- Get the SGA assigned to the highest-ranked (lowest overall_rank) lead in this firm group
        FIRST_VALUE(assigned_sga_num) OVER (
            PARTITION BY firm_crd
            ORDER BY overall_rank
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) as group_sga_num
    FROM leads_assigned
    WHERE is_partner_founder = 1
),

-- Update SGA assignment for partner/founder leads to use group SGA
leads_with_partner_founder_fix AS (
    SELECT 
        la.*,
        -- If this is a partner/founder lead, use the group SGA; otherwise keep original assignment
        CASE 
            WHEN la.is_partner_founder = 1 AND pfg.group_sga_num IS NOT NULL 
            THEN pfg.group_sga_num
            ELSE la.assigned_sga_num
        END as final_assigned_sga_num
    FROM leads_assigned la
    LEFT JOIN partner_founder_groups pfg 
        ON la.firm_crd = pfg.firm_crd
),

-- Join to get SGA details and ensure exactly 200 leads per SGA
leads_with_sga AS (
    SELECT 
        lapf.*,
        sga.sga_id,
        sga.sga_name as sga_owner,
        -- Rank within each SGA to ensure exactly 200 leads per SGA
        ROW_NUMBER() OVER (
            PARTITION BY sga.sga_id
            ORDER BY 
                lapf.conv_rate_bucket,
                lapf.final_tier,
                lapf.overall_rank
        ) as sga_lead_rank
    FROM leads_with_partner_founder_fix lapf
    INNER JOIN active_sgas sga ON lapf.final_assigned_sga_num = sga.sga_number
    -- Limit to exactly 200 leads per SGA
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY sga.sga_id
        ORDER BY 
            lapf.conv_rate_bucket,
            lapf.final_tier,
            lapf.overall_rank
    ) <= 200
),

-- ============================================================================
-- R. FINAL LEAD LIST (Exclude V3/V4.2.0 disagreement leads)
-- ============================================================================
-- V4.2.0 has strong lift (2.28x), so we maintain aggressive filtering
-- Threshold: 60th percentile for disagreement filtering (unchanged from V4.1.0)
-- 
-- Logic: Tier 1 leads with V4.2.0 < 60th percentile are likely false positives
-- V4.2.0 now includes age signal and improved bleeding detection
-- 
-- NOTE: Disclosure exclusions already applied in base_prospects CTE
-- NOTE: Deduplication already happened BEFORE SGA assignment
-- ============================================================================
final_lead_list AS (
    SELECT 
        lws.*
    FROM leads_with_sga lws
    WHERE lws.score_tier != 'TIER_NURTURE_TOO_EARLY'  -- V3.6.0: Exclude too-early leads
      AND NOT (
        -- V3/V4.2.0 Disagreement Filter
        -- Exclude Tier 1 leads where V4.2.0 < 60th percentile
        lws.score_tier IN (
            'TIER_1A_PRIME_MOVER_CFP',
            'TIER_1B_PRIME_ZERO_FRICTION',  -- V3.3.3: Zero Friction Bleeder
            'TIER_1B_PRIME_MOVER_SERIES65',
            'TIER_1_PRIME_MOVER',
            'TIER_1F_HV_WEALTH_BLEEDER',
            'TIER_1G_ENHANCED_SWEET_SPOT',  -- V3.3.3: Sweet Spot Growth Advisor
            'TIER_1G_GROWTH_STAGE'  -- V3.3.3: Growth Stage (outside sweet spot)
        )
        AND lws.v4_percentile < 60  -- V4.2.0 threshold (unchanged from V4.1.0)
    )
)

-- ============================================================================
-- T. FINAL OUTPUT (with SGA assignment, excluding V3/V4 disagreements)
-- ============================================================================
SELECT 
    crd as advisor_crd,
    existing_lead_id as salesforce_lead_id,
    first_name,
    last_name,
    email,
    phone,
    linkedin_url,
    has_linkedin,
    
    -- JOB TITLE
    job_title,
    
    producing_advisor,
    firm_name,
    firm_crd,
    firm_rep_count,
    firm_net_change_12mo,
    firm_arrivals_12mo,
    firm_departures_12mo,
    ROUND(firm_turnover_pct, 1) as firm_turnover_pct,
    tenure_months,
    tenure_years,
    industry_tenure_years,
    num_prior_firms,
    moves_3yr,
    score_tier as original_v3_tier,
    final_tier as score_tier,
    priority_rank,
    final_expected_rate as expected_conversion_rate,
    ROUND(final_expected_rate * 100, 2) as expected_rate_pct,
    
    -- SCORE NARRATIVE (V3 rules or V4.2.0 gain-based)
    score_narrative,
    
    has_cfp,
    has_series_65_only,
    has_series_7,
    has_cfa,
    is_hv_wealth_title,
    prospect_type,
    CASE 
        WHEN prospect_type = 'NEW_PROSPECT' THEN 'New - Not in Salesforce'
        ELSE 'Recyclable - 180+ days no contact'
    END as lead_source_description,
    
    -- Nurture / Original SGA owner / Bad contact info (when in Salesforce)
    is_nurture,
    original_sga_owner_name as `Original SGA Owner name`,
    original_sga_owner_id as `Original SGA owner ID`,
    bad_contact_info,
    
    -- V4.2.0 Scoring
    ROUND(v4_score, 4) as v4_score,
    v4_percentile,
    is_high_v4_standard,
    CASE 
        WHEN is_high_v4_standard = 1 THEN 'High-V4 STANDARD (Backfill)'
        ELSE 'V3 Tier Qualified'
    END as v4_status,
    
    -- V4.2.0 Feature Values (for transparency)
    v4_is_recent_mover,
    v4_days_since_last_move,
    v4_firm_departures_corrected,
    v4_bleeding_velocity_encoded,
    v4_is_dual_registered,
    v4_age_bucket_encoded,  -- NEW in V4.2.0
    
    -- V4.2.0 Top Features - Gain-based (for SDR context)
    -- Note: These are gain-based importance, not SHAP values
    -- Column names kept as shap_* for backwards compatibility
    shap_top1_feature,
    shap_top2_feature,
    shap_top3_feature,
    
    -- Career Clock Features (V3.6.0)
    cc_career_pattern,
    cc_cycle_status,
    ROUND(cc_pct_through_cycle, 2) as cc_pct_through_cycle,
    cc_months_until_window,
    cc_is_in_move_window,
    cc_is_too_early,
    
    -- SGA ASSIGNMENT (NEW!)
    sga_owner,
    sga_id,
    
    overall_rank as list_rank,
    CURRENT_TIMESTAMP() as generated_at

FROM final_lead_list
ORDER BY 
    overall_rank;

-- ============================================================================
-- VALIDATION (run after the above creates march_2026_lead_list):
-- ============================================================================
-- SELECT 
--     score_tier,
--     COUNT(*) as lead_count,
--     ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) as pct_of_total,
--     ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_conv_pct
-- FROM `savvy-gtm-analytics.ml_features.march_2026_lead_list`
-- GROUP BY score_tier
-- ORDER BY lead_count DESC;
-- Confirm: No STANDARD_HIGH_V4; TIER_2_PROVEN_MOVER ~60%+; total ~2,400-2,600.
-- ============================================================================

-- ============================================================================
-- NURTURE LIST: Too-Early Leads for Future Outreach (V3.4.0)
-- These leads should be contacted when they enter their move window
-- ============================================================================
CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.nurture_list_too_early` AS

WITH 
-- Recreate necessary CTEs for nurture list
career_clock_stats_nurture AS (
    SELECT
        RIA_CONTACT_CRD_ID as advisor_crd,
        AVG(DATE_DIFF(
            PREVIOUS_REGISTRATION_COMPANY_END_DATE,
            PREVIOUS_REGISTRATION_COMPANY_START_DATE,
            MONTH
        )) as avg_tenure_months,
        SAFE_DIVIDE(
            STDDEV(DATE_DIFF(
                PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                MONTH
            )),
            AVG(DATE_DIFF(
                PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                MONTH
            ))
        ) as tenure_cv
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
      AND DATE_DIFF(PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                    PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) > 0
    GROUP BY RIA_CONTACT_CRD_ID
    HAVING COUNT(*) >= 2
),
base_prospects_nurture AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        c.CONTACT_FIRST_NAME as first_name,
        c.CONTACT_LAST_NAME as last_name,
        c.PRIMARY_FIRM_NAME as firm_name,
        c.EMAIL as email,
        DATE_DIFF(CURRENT_DATE(), SAFE_CAST(c.PRIMARY_FIRM_START_DATE AS DATE), MONTH) as tenure_months,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    WHERE c.CONTACT_FIRST_NAME IS NOT NULL AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM_START_DATE IS NOT NULL
      AND COALESCE(LOWER(TRIM(CAST(c.PRODUCING_ADVISOR AS STRING))), '') = 'true'
),
firm_metrics_nurture AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_reps
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY PRIMARY_FIRM
),
firm_departures_nurture AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_END_DATE AS DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),
firm_arrivals_nurture AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE SAFE_CAST(PRIMARY_FIRM_START_DATE AS DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),
firm_stability_nurture AS (
    SELECT
        h.firm_crd,
        COALESCE(d.departures_12mo, 0) as departures_12mo,
        COALESCE(a.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(a.arrivals_12mo, 0) - COALESCE(d.departures_12mo, 0) as firm_net_change_12mo
    FROM firm_metrics_nurture h
    LEFT JOIN firm_departures_nurture d ON h.firm_crd = d.firm_crd
    LEFT JOIN firm_arrivals_nurture a ON h.firm_crd = a.firm_crd
),
nurture_prospects AS (
    SELECT 
        bp.crd,
        bp.first_name,
        bp.last_name,
        bp.firm_name,
        bp.email,
        bp.tenure_months,
        ccs.avg_tenure_months as cc_avg_prior_tenure_months,
        ccs.tenure_cv,
        SAFE_DIVIDE(SAFE_CAST(bp.tenure_months AS FLOAT64), SAFE_CAST(ccs.avg_tenure_months AS FLOAT64)) as cc_pct_through_cycle,
        COALESCE(fs.firm_net_change_12mo, 0) as firm_net_change_12mo,
        CASE
            WHEN ccs.tenure_cv IS NULL THEN 'No_Pattern'
            WHEN ccs.tenure_cv < 0.3 THEN 'Clockwork'
            WHEN ccs.tenure_cv < 0.5 THEN 'Semi_Predictable'
            WHEN ccs.tenure_cv < 0.8 THEN 'Variable'
            ELSE 'Chaotic'
        END as cc_career_pattern,
        CASE
            WHEN ccs.tenure_cv IS NULL THEN 'Unknown'
            WHEN ccs.tenure_cv >= 0.5 THEN 'Unpredictable'
            WHEN SAFE_DIVIDE(SAFE_CAST(bp.tenure_months AS FLOAT64), SAFE_CAST(ccs.avg_tenure_months AS FLOAT64)) < 0.7 THEN 'Too_Early'
            WHEN SAFE_DIVIDE(SAFE_CAST(bp.tenure_months AS FLOAT64), SAFE_CAST(ccs.avg_tenure_months AS FLOAT64)) BETWEEN 0.7 AND 1.3 THEN 'In_Window'
            ELSE 'Overdue'
        END as cc_cycle_status,
        CASE
            WHEN ccs.tenure_cv < 0.5 AND ccs.avg_tenure_months IS NOT NULL
            THEN GREATEST(0, CAST(SAFE_CAST(ccs.avg_tenure_months AS FLOAT64) * 0.7 AS INT64) - SAFE_CAST(bp.tenure_months AS INT64))
            ELSE NULL
        END as cc_months_until_window
    FROM base_prospects_nurture bp
    LEFT JOIN career_clock_stats_nurture ccs ON bp.crd = ccs.advisor_crd
    LEFT JOIN firm_stability_nurture fs ON bp.firm_crd = fs.firm_crd
    WHERE ccs.tenure_cv < 0.5  -- Predictable pattern
      AND SAFE_DIVIDE(SAFE_CAST(bp.tenure_months AS FLOAT64), SAFE_CAST(ccs.avg_tenure_months AS FLOAT64)) < 0.7  -- Too early
      AND COALESCE(fs.firm_net_change_12mo, 0) >= -10  -- Not at heavy bleeding firm
)
SELECT
    crd,
    first_name,
    last_name,
    firm_name as company,
    email,
    cc_career_pattern,
    cc_cycle_status,
    cc_pct_through_cycle,
    cc_months_until_window,
    DATE_ADD(CURRENT_DATE(), INTERVAL cc_months_until_window MONTH) as estimated_window_entry_date,
    cc_avg_prior_tenure_months,
    tenure_months as current_firm_tenure_months,
    CONCAT('Predictable advisor contacted too early in cycle. Will enter move window in ',
           CAST(cc_months_until_window AS STRING), ' months.') as nurture_reason,
    CURRENT_TIMESTAMP() as created_at
FROM nurture_prospects
ORDER BY cc_months_until_window ASC;  -- Soonest to enter window first