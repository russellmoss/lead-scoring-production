-- ============================================================================
-- SERIES 65 ONLY ADVISORS AT SMALL INDEPENDENT RIAs WITH SALESFORCE DATA
-- ============================================================================
-- Run in: BigQuery Console, Location: northamerica-northeast2 (Toronto)
-- 
-- Target Population: Top 1000 advisors by lead scoring
-- - Producing advisors only
-- - Series 65 license WITHOUT Series 7 (pure fee-only RIAs)
-- - Small firms (≤50 producing reps)
-- - Excludes wirehouses, insurance firms, broker-dealers
-- - V3.2 and V4 scores must be aligned (both agree on priority)
-- - Includes Salesforce Lead and Opportunity data (prefers Opportunity)
--
-- Output includes:
-- - Contact info (CRD, name, email, phone, LinkedIn)
-- - Location (city, state, zip)
-- - Firm info (name, size, classification, AUM)
-- - Lead scores (V3 tier + V4 score)
-- - Salesforce status (Lead or Opportunity, stage, owner, disposition)
-- ============================================================================

WITH 
-- ============================================================================
-- A. FIRM SIZE CALCULATION
-- ============================================================================
firm_sizes AS (
    SELECT 
        PRIMARY_FIRM as firm_crd,
        COUNT(DISTINCT CASE WHEN PRODUCING_ADVISOR = TRUE THEN RIA_CONTACT_CRD_ID END) as producing_reps
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

-- ============================================================================
-- B. FIRM NET CHANGE (Arrivals - Departures in last 12 months)
-- ============================================================================
firm_departures AS (
    SELECT
        PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),

firm_arrivals AS (
    SELECT
        PRIMARY_FIRM as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

firm_stability AS (
    SELECT 
        fs.firm_crd,
        fs.producing_reps,
        COALESCE(fa.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(fd.departures_12mo, 0) as departures_12mo,
        COALESCE(fa.arrivals_12mo, 0) - COALESCE(fd.departures_12mo, 0) as net_change_12mo
    FROM firm_sizes fs
    LEFT JOIN firm_arrivals fa ON fs.firm_crd = fa.firm_crd
    LEFT JOIN firm_departures fd ON fs.firm_crd = fd.firm_crd
),

-- ============================================================================
-- C. ADVISOR EMPLOYMENT HISTORY (for num_prior_firms calculation)
-- ============================================================================
advisor_history AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID) as total_firms,
        MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE) as career_start_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    GROUP BY 1
),

-- ============================================================================
-- D. EXCLUDED FIRM PATTERNS (Wirehouses, Insurance, etc.)
-- ============================================================================
excluded_firms AS (
    SELECT firm_pattern FROM UNNEST([
        -- Wirehouses
        '%J.P. MORGAN%', '%MORGAN STANLEY%', '%MERRILL%', '%WELLS FARGO%', 
        '%UBS %', '%UBS,%', '%EDWARD JONES%', '%AMERIPRISE%', 
        '%NORTHWESTERN MUTUAL%', '%PRUDENTIAL%', '%RAYMOND JAMES%',
        '%FIDELITY%', '%SCHWAB%', '%VANGUARD%', '%GOLDMAN SACHS%', '%CITIGROUP%',
        '%LPL FINANCIAL%', '%COMMONWEALTH%', '%CETERA%', '%CAMBRIDGE%',
        '%OSAIC%', '%PRIMERICA%',
        -- Insurance
        '%STATE FARM%', '%ALLSTATE%', '%NEW YORK LIFE%', '%NYLIFE%',
        '%TRANSAMERICA%', '%FARM BUREAU%', '%NATIONWIDE%',
        '%LINCOLN FINANCIAL%', '%MASS MUTUAL%', '%MASSMUTUAL%',
        '%INSURANCE%',
        -- Internal exclusions
        '%SAVVY WEALTH%', '%SAVVY ADVISORS%', '%RITHOLTZ%'
    ]) as firm_pattern
),

-- ============================================================================
-- E. BASE ADVISOR DATA WITH ALL FILTERS
-- ============================================================================
base_advisors AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        c.CONTACT_FIRST_NAME as first_name,
        c.CONTACT_LAST_NAME as last_name,
        CONCAT(c.CONTACT_FIRST_NAME, ' ', c.CONTACT_LAST_NAME) as full_name,
        c.TITLE_NAME as job_title,
        c.EMAIL as email,
        c.PERSONAL_EMAIL_ADDRESS as personal_email,
        COALESCE(c.MOBILE_PHONE_NUMBER, c.OFFICE_PHONE_NUMBER) as phone,
        c.MOBILE_PHONE_NUMBER as mobile_phone,
        c.OFFICE_PHONE_NUMBER as office_phone,
        c.LINKEDIN_PROFILE_URL as linkedin_url,
        
        -- Location
        c.PRIMARY_LOCATION_CITY as city,
        c.PRIMARY_LOCATION_STATE as state,
        c.PRIMARY_LOCATION_POSTAL as zip,
        
        -- Firm info
        c.PRIMARY_FIRM as firm_crd,
        c.PRIMARY_FIRM_NAME as firm_name,
        c.PRIMARY_FIRM_CLASSIFICATION as firm_classification,
        c.PRIMARY_FIRM_TOTAL_AUM as firm_aum,
        c.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        
        -- Licenses & certifications
        c.REP_LICENSES as licenses,
        c.REP_TYPE as rep_type,
        c.INDUSTRY_TENURE_MONTHS as industry_tenure_months,
        c.CONTACT_BIO as bio,
        
        -- Flags
        CASE WHEN c.PRIMARY_FIRM_CLASSIFICATION LIKE '%Independent RIA%' THEN TRUE ELSE FALSE END as is_independent_ria,
        CASE WHEN c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%' THEN 1 ELSE 0 END as has_cfp,
        CASE WHEN c.CONTACT_BIO LIKE '%CFA%' OR c.TITLE_NAME LIKE '%CFA%' THEN 1 ELSE 0 END as has_cfa,
        
        -- High-value wealth title detection
        CASE WHEN (
            UPPER(c.TITLE_NAME) LIKE '%WEALTH MANAGER%'
            OR (UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%' AND UPPER(c.TITLE_NAME) LIKE '%WEALTH%')
            OR UPPER(c.TITLE_NAME) LIKE '%SENIOR WEALTH ADVISOR%'
            OR (UPPER(c.TITLE_NAME) LIKE '%FOUNDER%' AND UPPER(c.TITLE_NAME) LIKE '%WEALTH%')
            OR (UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%' AND UPPER(c.TITLE_NAME) LIKE '%WEALTH%')
            OR (UPPER(c.TITLE_NAME) LIKE '%PARTNER%' AND UPPER(c.TITLE_NAME) LIKE '%WEALTH%')
            OR (UPPER(c.TITLE_NAME) LIKE '%PRESIDENT%' AND UPPER(c.TITLE_NAME) LIKE '%WEALTH%')
            OR (UPPER(c.TITLE_NAME) LIKE '%MANAGING DIRECTOR%' AND UPPER(c.TITLE_NAME) LIKE '%WEALTH%')
        ) AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%' THEN 1 ELSE 0 END as is_hv_wealth_title

    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    
    WHERE 
        -- Core filters
        c.PRODUCING_ADVISOR = TRUE
        AND c.CONTACT_FIRST_NAME IS NOT NULL 
        AND c.CONTACT_LAST_NAME IS NOT NULL
        AND c.PRIMARY_FIRM IS NOT NULL
        AND c.PRIMARY_FIRM_NAME IS NOT NULL
        
        -- Series 65 ONLY (no Series 7 = pure RIA, no broker-dealer ties)
        AND c.REP_LICENSES LIKE '%Series 65%'
        AND c.REP_LICENSES NOT LIKE '%Series 7%'
        
        -- Exclude wirehouses/insurance by firm name
        AND NOT EXISTS (
            SELECT 1 FROM excluded_firms ef 
            WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
        )
        
        -- Exclude problematic titles
        AND NOT (
            UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTIONS ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS%'
            OR UPPER(c.TITLE_NAME) LIKE '%WHOLESALER%'
            OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE%'
            OR UPPER(c.TITLE_NAME) LIKE '%ASSISTANT%'
            OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE AGENT%'
        )
),

-- ============================================================================
-- F. ENRICH WITH FIRM STABILITY & ADVISOR HISTORY
-- ============================================================================
enriched_advisors AS (
    SELECT 
        ba.*,
        
        -- Firm metrics
        COALESCE(fstab.producing_reps, 1) as firm_rep_count,
        COALESCE(fstab.arrivals_12mo, 0) as firm_arrivals_12mo,
        COALESCE(fstab.departures_12mo, 0) as firm_departures_12mo,
        COALESCE(fstab.net_change_12mo, 0) as firm_net_change_12mo,
        
        -- Advisor history
        COALESCE(ah.total_firms, 1) - 1 as num_prior_firms,
        DATE_DIFF(CURRENT_DATE(), ah.career_start_date, YEAR) as industry_tenure_years,
        
        -- Tenure at current firm
        DATE_DIFF(CURRENT_DATE(), ba.current_firm_start_date, MONTH) as tenure_months,
        ROUND(DATE_DIFF(CURRENT_DATE(), ba.current_firm_start_date, MONTH) / 12.0, 1) as tenure_years
        
    FROM base_advisors ba
    LEFT JOIN firm_stability fstab ON ba.firm_crd = fstab.firm_crd
    LEFT JOIN advisor_history ah ON ba.crd = ah.crd
    
    -- Small firms only (≤50 producing reps)
    WHERE COALESCE(fstab.producing_reps, 1) <= 50
),

-- ============================================================================
-- G. CALCULATE TIER SIGNALS (for advisors without lead scores)
-- ============================================================================
with_calculated_tier AS (
    SELECT 
        ea.*,
        
        -- Calculate tier based on V3.2 model logic
        CASE 
            -- TIER_1B: Series 65 only (which all our results are) + Prime Mover criteria
            WHEN ea.tenure_years BETWEEN 1 AND 4 
                AND ea.industry_tenure_years >= 5 
                AND ea.firm_net_change_12mo < 0 
                AND ea.is_independent_ria = TRUE
            THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            
            -- TIER_1F: High-value wealth title at bleeding firm
            WHEN ea.is_hv_wealth_title = 1 
                AND ea.firm_net_change_12mo < 0 
                AND ea.is_independent_ria = TRUE
            THEN 'TIER_1F_HV_WEALTH_BLEEDER'
            
            -- TIER_2: Proven mover (3+ firms)
            WHEN ea.num_prior_firms >= 3 
                AND ea.industry_tenure_years >= 5
            THEN 'TIER_2_PROVEN_MOVER'
            
            -- TIER_3: At moderately bleeding firm
            WHEN ea.firm_net_change_12mo BETWEEN -10 AND -1 
                AND ea.industry_tenure_years >= 5
            THEN 'TIER_3_MODERATE_BLEEDER'
            
            ELSE 'STANDARD'
        END as calculated_tier,
        
        -- Expected conversion rates based on V3 model
        CASE 
            WHEN ea.tenure_years BETWEEN 1 AND 4 
                AND ea.industry_tenure_years >= 5 
                AND ea.firm_net_change_12mo < 0 
                AND ea.is_independent_ria = TRUE
            THEN 0.1176  -- TIER_1B rate
            WHEN ea.is_hv_wealth_title = 1 AND ea.firm_net_change_12mo < 0 
            THEN 0.0606  -- TIER_1F rate
            WHEN ea.num_prior_firms >= 3 AND ea.industry_tenure_years >= 5
            THEN 0.0591  -- TIER_2 rate
            WHEN ea.firm_net_change_12mo BETWEEN -10 AND -1 AND ea.industry_tenure_years >= 5
            THEN 0.0676  -- TIER_3 rate
            ELSE 0.0260  -- STANDARD baseline
        END as calculated_conversion_rate

    FROM enriched_advisors ea
),

-- ============================================================================
-- H. JOIN LEAD SCORES (V3 and V4)
-- ============================================================================
with_scores AS (
    SELECT 
        ct.*,
        
        -- V3 lead scores (from lead_scores_v3 table)
        ls.score_tier as v3_score_tier,
        -- Convert expected_lift to conversion rate (lift * baseline 2.74%)
        CASE 
            WHEN ls.expected_lift IS NOT NULL THEN ls.expected_lift * 0.0274
            ELSE NULL
        END as v3_conversion_rate,
        -- V3 doesn't have tier_explanation in the table, use score_tier
        ls.score_tier as v3_tier_explanation,
        
        -- V4 ML scores
        v4.v4_score,
        v4.v4_percentile,
        v4.v4_deprioritize,
        v4.shap_top1_feature,
        v4.shap_top2_feature,
        v4.shap_top3_feature,
        v4.v4_narrative
        
    FROM with_calculated_tier ct
    -- V3 scores - join by CRD (lead_scores_v3 uses advisor_crd as STRING)
    LEFT JOIN `savvy-gtm-analytics.ml_features.lead_scores_v3` ls 
        ON ct.crd = SAFE_CAST(REGEXP_REPLACE(CAST(ls.advisor_crd AS STRING), r'[^0-9]', '') AS INT64)
    -- V4 scores - crd is INT64, direct join
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 
        ON ct.crd = v4.crd
),

-- ============================================================================
-- I. SALESFORCE DATA - TASK ACTIVITY (for both Leads and Opportunities)
-- ============================================================================
lead_task_activity AS (
    SELECT 
        t.WhoId as record_id,
        'Lead' as record_type,
        MAX(GREATEST(
            COALESCE(DATE(t.ActivityDate), DATE('1900-01-01')),
            COALESCE(DATE(t.CompletedDateTime), DATE('1900-01-01')),
            COALESCE(DATE(t.CreatedDate), DATE('1900-01-01'))
        )) as last_activity_date
    FROM `savvy-gtm-analytics.SavvyGTMData.Task` t
    INNER JOIN `savvy-gtm-analytics.SavvyGTMData.Lead` l ON t.WhoId = l.Id
    WHERE t.IsDeleted = false 
      AND t.WhoId IS NOT NULL
      AND l.FA_CRD__c IS NOT NULL
      AND (
          t.Type IN ('Outgoing SMS', 'Incoming SMS')
          OR UPPER(t.Subject) LIKE '%SMS%' 
          OR UPPER(t.Subject) LIKE '%TEXT%'
          OR t.TaskSubtype = 'Call' 
          OR t.Type = 'Call'
          OR UPPER(t.Subject) LIKE '%CALL%' 
          OR t.CallType IS NOT NULL
          OR t.Type = 'Email'
          OR UPPER(t.Subject) LIKE '%EMAIL%'
          OR t.Type = 'Meeting'
          OR UPPER(t.Subject) LIKE '%MEETING%'
      )
    GROUP BY t.WhoId
),

opportunity_task_activity AS (
    SELECT 
        t.WhatId as record_id,
        'Opportunity' as record_type,
        MAX(GREATEST(
            COALESCE(DATE(t.ActivityDate), DATE('1900-01-01')),
            COALESCE(DATE(t.CompletedDateTime), DATE('1900-01-01')),
            COALESCE(DATE(t.CreatedDate), DATE('1900-01-01'))
        )) as last_activity_date
    FROM `savvy-gtm-analytics.SavvyGTMData.Task` t
    INNER JOIN `savvy-gtm-analytics.SavvyGTMData.Opportunity` o ON t.WhatId = o.Id
    WHERE t.IsDeleted = false 
      AND t.WhatId IS NOT NULL
      AND o.FA_CRD__c IS NOT NULL
      AND (
          t.Type IN ('Outgoing SMS', 'Incoming SMS')
          OR UPPER(t.Subject) LIKE '%SMS%' 
          OR UPPER(t.Subject) LIKE '%TEXT%'
          OR t.TaskSubtype = 'Call' 
          OR t.Type = 'Call'
          OR UPPER(t.Subject) LIKE '%CALL%' 
          OR t.CallType IS NOT NULL
          OR t.Type = 'Email'
          OR UPPER(t.Subject) LIKE '%EMAIL%'
          OR t.Type = 'Meeting'
          OR UPPER(t.Subject) LIKE '%MEETING%'
      )
    GROUP BY t.WhatId
),

-- ============================================================================
-- J. SALESFORCE DATA - LEADS
-- ============================================================================
salesforce_leads AS (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        l.Id as lead_id,
        l.Status as lead_status,
        l.Disposition__c as lead_disposition,
        l.OwnerId as lead_owner_id,
        u.Name as sga_owner_name,
        l.IsDeleted as lead_is_deleted,
        lta.last_activity_date as lead_last_activity_date,
        DATE_DIFF(CURRENT_DATE(), lta.last_activity_date, DAY) as days_since_lead_activity,
        ROW_NUMBER() OVER (
            PARTITION BY SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64)
            ORDER BY l.CreatedDate DESC
        ) as lead_rank
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.User` u ON l.OwnerId = u.Id
    LEFT JOIN lead_task_activity lta ON l.Id = lta.record_id
    WHERE l.FA_CRD__c IS NOT NULL
      AND l.IsDeleted = false
),

-- ============================================================================
-- K. SALESFORCE DATA - OPPORTUNITIES (via Account)
-- ============================================================================
salesforce_opportunities AS (
    SELECT 
        SAFE_CAST(REGEXP_REPLACE(CAST(o.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        o.Id as opportunity_id,
        o.StageName as opportunity_stage,
        o.Closed_Lost_Reason__c as closed_lost_reason,
        o.Closed_Lost_Details__c as closed_lost_reason_details,
        o.OwnerId as opportunity_owner_id,
        u.Name as sgm_owner_name,
        o.IsDeleted as opportunity_is_deleted,
        ota.last_activity_date as opportunity_last_activity_date,
        DATE_DIFF(CURRENT_DATE(), ota.last_activity_date, DAY) as days_since_opportunity_activity,
        ROW_NUMBER() OVER (
            PARTITION BY SAFE_CAST(REGEXP_REPLACE(CAST(o.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64)
            ORDER BY o.CreatedDate DESC
        ) as opportunity_rank
    FROM `savvy-gtm-analytics.SavvyGTMData.Opportunity` o
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.User` u ON o.OwnerId = u.Id
    LEFT JOIN opportunity_task_activity ota ON o.Id = ota.record_id
    WHERE o.FA_CRD__c IS NOT NULL
      AND o.IsDeleted = false
),

-- ============================================================================
-- L. COMBINE SALESFORCE DATA (Prefer Opportunity over Lead)
-- ============================================================================
salesforce_combined AS (
    SELECT 
        COALESCE(opp.crd, lead.crd) as crd,
        -- Prefer Opportunity, fallback to Lead
        CASE WHEN opp.opportunity_id IS NOT NULL THEN 'Opportunity' ELSE 'Lead' END as salesforce_object_type,
        opp.opportunity_id,
        opp.opportunity_stage,
        opp.closed_lost_reason,
        opp.closed_lost_reason_details,
        opp.sgm_owner_name,
        opp.opportunity_last_activity_date,
        opp.days_since_opportunity_activity,
        lead.lead_id,
        lead.lead_status,
        lead.lead_disposition,
        lead.sga_owner_name,
        lead.lead_last_activity_date,
        lead.days_since_lead_activity,
        -- Most recent activity across both objects (prefer Opportunity if both exist)
        COALESCE(opp.opportunity_last_activity_date, lead.lead_last_activity_date) as last_activity_date,
        COALESCE(opp.days_since_opportunity_activity, lead.days_since_lead_activity) as days_since_last_activity
    FROM salesforce_opportunities opp
    FULL OUTER JOIN salesforce_leads lead ON opp.crd = lead.crd
    WHERE (opp.opportunity_rank = 1 OR opp.opportunity_rank IS NULL)
      AND (lead.lead_rank = 1 OR lead.lead_rank IS NULL)
),

-- ============================================================================
-- M. FINAL SCORING & V3/V4 ALIGNMENT CHECK
-- ============================================================================
final_scored AS (
    SELECT 
        ws.*,
        sf.salesforce_object_type,
        sf.opportunity_id,
        sf.opportunity_stage,
        sf.closed_lost_reason,
        sf.closed_lost_reason_details,
        sf.sgm_owner_name,
        sf.lead_id,
        sf.lead_status,
        sf.lead_disposition,
        sf.sga_owner_name,
        sf.lead_last_activity_date,
        sf.days_since_lead_activity,
        sf.opportunity_last_activity_date,
        sf.days_since_opportunity_activity,
        sf.last_activity_date,
        sf.days_since_last_activity,
        
        -- Use V3 score if available, otherwise use calculated tier
        COALESCE(ws.v3_score_tier, ws.calculated_tier) as final_tier,
        COALESCE(ws.v3_conversion_rate, ws.calculated_conversion_rate) as final_conversion_rate,
        
        -- Priority rank (lower = better)
        CASE COALESCE(ws.v3_score_tier, ws.calculated_tier)
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
            WHEN 'TIER_1_PRIME_MOVER' THEN 3
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
            WHEN 'TIER_2_PROVEN_MOVER' THEN 5
            WHEN 'TIER_3_MODERATE_BLEEDER' THEN 6
            WHEN 'STANDARD' THEN 9
            ELSE 10
        END as tier_priority,
        
        -- Contact quality score (for secondary sorting)
        (CASE WHEN ws.email IS NOT NULL THEN 2 ELSE 0 END +
         CASE WHEN ws.linkedin_url IS NOT NULL AND TRIM(ws.linkedin_url) != '' THEN 2 ELSE 0 END +
         CASE WHEN ws.mobile_phone IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN ws.office_phone IS NOT NULL THEN 1 ELSE 0 END) as contact_quality_score,
        
        -- Has LinkedIn flag
        CASE WHEN ws.linkedin_url IS NOT NULL AND TRIM(ws.linkedin_url) != '' THEN 1 ELSE 0 END as has_linkedin,
        
        -- V3/V4 Alignment Check
        -- Aligned means V3 and V4 agree on priority level:
        -- 1. High V3 tiers (T1, T2, T3) should have V4 percentile >= 20 (not deprioritized)
        -- 2. STANDARD V3 tier should not have V4 percentile >= 80 (not upgraded)
        -- 3. If V4 score is missing, consider aligned (can't disagree)
        -- Based on historical analysis: Tier 1 with V4 < 70th percentile = 0% conversion
        CASE 
            -- High V3 tier (T1, T2, T3) should have V4 percentile >= 20 (not deprioritized)
            -- Stricter: Tier 1 should have V4 >= 70 (per historical analysis)
            WHEN COALESCE(ws.v3_score_tier, ws.calculated_tier) IN (
                'TIER_1A_PRIME_MOVER_CFP', 
                'TIER_1B_PRIME_MOVER_SERIES65', 
                'TIER_1_PRIME_MOVER', 
                'TIER_1F_HV_WEALTH_BLEEDER'
            )
            THEN (
                ws.v4_percentile IS NULL  -- No V4 score = aligned (can't disagree)
                OR ws.v4_percentile >= 70  -- Tier 1 requires V4 >= 70th percentile
            )
            -- Tier 2 and Tier 3 should have V4 percentile >= 20 (not deprioritized)
            WHEN COALESCE(ws.v3_score_tier, ws.calculated_tier) IN (
                'TIER_2_PROVEN_MOVER',
                'TIER_3_MODERATE_BLEEDER'
            )
            THEN (
                ws.v4_percentile IS NULL  -- No V4 score = aligned
                OR ws.v4_percentile >= 20  -- V4 doesn't deprioritize
            )
            -- STANDARD tier should not have high V4 upgrade (to avoid false positives)
            WHEN COALESCE(ws.v3_score_tier, ws.calculated_tier) = 'STANDARD'
            THEN (
                ws.v4_percentile IS NULL  -- No V4 score = aligned
                OR ws.v4_percentile < 80  -- V4 doesn't upgrade STANDARD
            )
            ELSE TRUE  -- Default to aligned if we can't determine
        END as v3_v4_aligned

    FROM with_scores ws
    LEFT JOIN salesforce_combined sf ON ws.crd = sf.crd
)

-- ============================================================================
-- FINAL OUTPUT - TOP 1000 WITH V3/V4 ALIGNMENT
-- ============================================================================
SELECT 
    -- Identifiers
    crd as advisor_crd,
    first_name,
    last_name,
    full_name,
    
    -- Contact Info
    email,
    personal_email,
    phone,
    mobile_phone,
    office_phone,
    linkedin_url,
    has_linkedin,
    
    -- Location
    city,
    state,
    zip,
    
    -- Job & Firm
    job_title,
    firm_name,
    firm_crd,
    firm_classification,
    is_independent_ria,
    firm_rep_count,
    firm_aum,
    ROUND(firm_aum / 1000000, 1) as firm_aum_millions,
    
    -- Firm Stability
    firm_net_change_12mo,
    firm_arrivals_12mo,
    firm_departures_12mo,
    
    -- Advisor Experience
    tenure_months,
    tenure_years,
    industry_tenure_years,
    num_prior_firms,
    
    -- Certifications & Flags
    has_cfp,
    has_cfa,
    is_hv_wealth_title,
    licenses,
    
    -- Lead Scoring
    final_tier as score_tier,
    ROUND(final_conversion_rate, 4) as expected_conversion_rate,
    ROUND(final_conversion_rate * 100, 2) as expected_conversion_pct,
    tier_priority,
    
    -- V3 Details (if available)
    v3_score_tier,
    v3_tier_explanation,
    
    -- V4 Details (if available)  
    v4_score,
    v4_percentile,
    v4_deprioritize,
    v4_narrative,
    
    -- Calculated tier (always populated)
    calculated_tier,
    
    -- Quality Score
    contact_quality_score,
    
    -- Salesforce Data
    salesforce_object_type,
    opportunity_id,
    opportunity_stage,
    closed_lost_reason,
    closed_lost_reason_details,
    sgm_owner_name,
    lead_id,
    lead_status,
    lead_disposition,
    sga_owner_name,
    lead_last_activity_date,
    days_since_lead_activity,
    opportunity_last_activity_date,
    days_since_opportunity_activity,
    last_activity_date,
    days_since_last_activity,
    
    -- Alignment Flag
    v3_v4_aligned,
    
    -- Metadata
    CURRENT_TIMESTAMP() as generated_at

FROM final_scored

-- Filter: Only V3/V4 aligned leads
WHERE v3_v4_aligned = TRUE

-- Prioritize by: 1) Tier priority, 2) V4 percentile, 3) Contact quality, 4) Firm size (smaller = better)
ORDER BY 
    tier_priority ASC,
    v4_percentile DESC NULLS LAST,
    contact_quality_score DESC,
    firm_rep_count ASC

-- Top 1000 only
LIMIT 1000;

