-- ============================================================================
-- PHASE 1: TARGET VARIABLE DEFINITION
-- ============================================================================
-- 
-- Purpose: Define the target variable for lead scoring model
-- Target: Whether a "Contacted" lead converts to "MQL" within 43 days
-- 
-- Target Definition Rules:
-- 1. Lead must have stage_entered_contacting__c IS NOT NULL
-- 2. Lead must have FA_CRD__c IS NOT NULL (FINTRX match)
-- 3. Convert = 1 if stage_entered_mql__c within 43 days of contacted date
-- 4. Convert = 0 if 43+ days passed without MQL conversion
-- 5. Exclude leads too recent to determine outcome (right-censored)
-- 6. CRITICAL: Filter to OUTBOUND leads only (Provided Lead List)
--    Excludes inbound/high-intent sources: Advisor Waitlist, Recruitment Firm, Event, Referral
-- 
-- Point-in-Time (PIT) Compliance:
-- - All dates use only data available at contacted_date
-- - No future-looking information
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_target_variable` AS

WITH
-- ============================================================================
-- CTE 1: Contacted Leads
-- ============================================================================
-- Extract all leads that entered "Contacted" status
-- Filter: Must have FA_CRD__c (FINTRX match) and be in date range
-- ============================================================================
contacted_leads AS (
    SELECT
        l.Id as lead_id,
        
        -- Advisor CRD for FINTRX matching
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as advisor_crd,
        
        -- Key dates (PIT-safe: use only these dates, no future data)
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.CreatedDate) as created_date,
        
        -- Lead source (for drift analysis)
        l.LeadSource as lead_source_original,
        
        -- Lead source grouping (critical for handling distribution drift)
        CASE 
            WHEN l.LeadSource LIKE '%Provided Lead List%' 
                OR l.LeadSource LIKE '%Provided Lead%'
                OR l.LeadSource LIKE '%Lead List%'
            THEN 'Provided List'
            WHEN l.LeadSource LIKE '%LinkedIn%' 
                OR l.LeadSource LIKE '%Linked In%'
            THEN 'LinkedIn'
            WHEN l.LeadSource LIKE '%Event%' 
                OR l.LeadSource LIKE '%Conference%'
                OR l.LeadSource LIKE '%Webinar%'
            THEN 'Event'
            WHEN l.LeadSource LIKE '%Referral%' 
                OR l.LeadSource LIKE '%Advisor Referral%'
            THEN 'Referral'
            ELSE 'Other'
        END as lead_source_grouped,
        
        -- Company name (for exclusion)
        l.Company as company_name
        
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.stage_entered_contacting__c IS NOT NULL
        AND l.FA_CRD__c IS NOT NULL
        AND DATE(l.stage_entered_contacting__c) >= '2024-02-01'
        AND DATE(l.stage_entered_contacting__c) <= '2025-10-31'
        AND (l.Company IS NULL OR UPPER(l.Company) NOT LIKE '%SAVVY%')
        -- CRITICAL: Filter to outbound leads only (exclude inbound/high-intent sources)
        -- Target population is Provided Lead List prospects (cold outbound)
        -- Exclude: Advisor Waitlist, Recruitment Firm, Event, Referral (inbound/warm)
        AND (
            l.LeadSource LIKE '%Provided Lead List%' 
            OR l.LeadSource LIKE '%Provided Lead%'
            OR l.LeadSource LIKE '%Lead List%'
            -- Option: Uncomment to include LinkedIn (outbound but self-sourced)
            -- OR l.LeadSource LIKE '%LinkedIn%'
            -- OR l.LeadSource LIKE '%Linked In%'
        )
),

-- ============================================================================
-- CTE 2: MQL Outcomes
-- ============================================================================
-- Extract leads that converted to MQL (Stage_Entered_Call_Scheduled__c)
-- This is our positive class indicator
-- ============================================================================
mql_outcomes AS (
    SELECT
        l.Id as lead_id,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date
        
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.Stage_Entered_Call_Scheduled__c IS NOT NULL
        AND l.stage_entered_contacting__c IS NOT NULL
        AND l.FA_CRD__c IS NOT NULL
        AND DATE(l.stage_entered_contacting__c) >= '2024-02-01'
        AND DATE(l.stage_entered_contacting__c) <= '2025-10-31'
        AND (l.Company IS NULL OR UPPER(l.Company) NOT LIKE '%SAVVY%')
        -- Match the same filter as contacted_leads (outbound only)
        AND (
            l.LeadSource LIKE '%Provided Lead List%' 
            OR l.LeadSource LIKE '%Provided Lead%'
            OR l.LeadSource LIKE '%Lead List%'
            -- Option: Uncomment to include LinkedIn
            -- OR l.LeadSource LIKE '%LinkedIn%'
            -- OR l.LeadSource LIKE '%Linked In%'
        )
),

-- ============================================================================
-- CTE 3: Maturity Check
-- ============================================================================
-- Calculate days since contact to determine if lead is "mature" enough
-- to determine outcome. Leads < 43 days old are right-censored.
-- ============================================================================
maturity_check AS (
    SELECT
        cl.lead_id,
        cl.contacted_date,
        CURRENT_DATE() as analysis_date,
        DATE_DIFF(CURRENT_DATE(), cl.contacted_date, DAY) as days_since_contact,
        
        -- Maturity flag: 1 if >= 43 days since contact (can determine outcome)
        CASE 
            WHEN DATE_DIFF(CURRENT_DATE(), cl.contacted_date, DAY) >= 43 
            THEN 1 
            ELSE 0 
        END as is_mature
        
    FROM contacted_leads cl
),

-- ============================================================================
-- CTE 4: Final Target Calculation
-- ============================================================================
-- Join all CTEs and calculate the target variable
-- Target = 1 if converted within 43 days, 0 if not converted after 43 days
-- Target = NULL if right-censored (< 43 days old)
-- ============================================================================
final_target AS (
    SELECT
        cl.lead_id,
        cl.advisor_crd,
        cl.contacted_date,
        cl.created_date,
        cl.lead_source_original,
        cl.lead_source_grouped,
        
        -- MQL conversion information
        mo.mql_date,
        CASE 
            WHEN mo.mql_date IS NOT NULL 
            THEN DATE_DIFF(mo.mql_date, cl.contacted_date, DAY)
            ELSE NULL
        END as days_to_conversion,
        
        -- Maturity flag
        mc.is_mature,
        mc.days_since_contact,
        
        -- TARGET VARIABLE CALCULATION
        -- Rule 1: Convert = 1 if MQL within 43 days
        -- Rule 2: Convert = 0 if 43+ days passed without MQL
        -- Rule 3: Convert = NULL if < 43 days old (right-censored)
        CASE 
            -- Converted within maturity window
            WHEN mo.mql_date IS NOT NULL 
                AND DATE_DIFF(mo.mql_date, cl.contacted_date, DAY) <= 43
            THEN 1
            
            -- Not converted and mature enough to determine outcome
            WHEN mo.mql_date IS NULL 
                AND mc.is_mature = 1
            THEN 0
            
            -- Right-censored: too recent to determine outcome
            ELSE NULL
        END as target
        
    FROM contacted_leads cl
    LEFT JOIN mql_outcomes mo
        ON cl.lead_id = mo.lead_id
    LEFT JOIN maturity_check mc
        ON cl.lead_id = mc.lead_id
)

-- ============================================================================
-- FINAL OUTPUT
-- ============================================================================
SELECT
    lead_id,
    advisor_crd,
    contacted_date,
    created_date,
    mql_date,
    days_to_conversion,
    target,
    is_mature,
    days_since_contact,
    lead_source_original,
    lead_source_grouped
    
FROM final_target
-- Only include leads where we can determine the target (mature leads)
-- This excludes right-censored leads for training
WHERE target IS NOT NULL

ORDER BY contacted_date, lead_id;

-- ============================================================================
-- VALIDATION QUERIES
-- ============================================================================
-- Run these after table creation to validate output:

-- Query 1: Target distribution
-- SELECT 
--     target,
--     COUNT(*) as count,
--     ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct
-- FROM `savvy-gtm-analytics.ml_features.v4_target_variable`
-- GROUP BY target
-- ORDER BY target;

-- Query 2: Conversion rate by lead source
-- SELECT 
--     lead_source_grouped,
--     COUNT(*) as total_leads,
--     SUM(target) as conversions,
--     ROUND(AVG(target) * 100, 2) as conversion_rate_pct
-- FROM `savvy-gtm-analytics.ml_features.v4_target_variable`
-- GROUP BY lead_source_grouped
-- ORDER BY conversion_rate_pct DESC;

-- Query 3: Date range check
-- SELECT 
--     MIN(contacted_date) as earliest_contact,
--     MAX(contacted_date) as latest_contact,
--     COUNT(*) as total_leads,
--     COUNT(DISTINCT advisor_crd) as unique_advisors
-- FROM `savvy-gtm-analytics.ml_features.v4_target_variable`;

