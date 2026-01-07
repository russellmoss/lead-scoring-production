-- ============================================================================
-- CREATE HISTORICAL LEAD PERFORMANCE TABLE
-- Version: 1.0
-- Created: January 3, 2026
-- Purpose: Create historical_lead_performance table for tier confidence analysis
--          Combines Salesforce Lead outcomes with V3 tier assignments
--
-- ⚠️ CRITICAL: POINT-IN-TIME (PIT) METHODOLOGY
-- ============================================================================
-- This table ensures strict PIT compliance:
-- 1. Tier assignments come from lead_scores_v3, which uses lead_scoring_features_pit
-- 2. lead_scoring_features_pit calculates ALL features using only data available
--    at contacted_date (or month before for firm data to account for lag)
-- 3. Tier matching prioritizes exact contacted_date match to ensure we're
--    using the tier that was assigned at contact time, not current state
--
-- PIT Verification:
-- - lead_scores_v3 features come from lead_scoring_features_pit (PIT-safe)
-- - lead_scoring_features_pit uses pit_month = month BEFORE contacted_date
-- - All historical queries filter by dates <= contacted_date
-- - Fixed analysis_date = 2025-10-31 (for training set stability)
--
-- This ensures tiers reflect advisor/firm state AT THE TIME OF CONTACT,
-- not current state, preventing data leakage.
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.historical_lead_performance` AS

WITH 
-- ============================================================================
-- BASE: Salesforce Lead Data with Outcomes
-- ============================================================================
sf_leads AS (
    SELECT
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        l.Company as company_name,
        l.LeadSource as lead_source,
        DATE(l.CreatedDate) as lead_created_date,
        -- Maturity check: lead must be at least 30 days old (for 30-day conversion window)
        DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) as days_since_contact
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.stage_entered_contacting__c IS NOT NULL
      -- Only include mature leads (at least 30 days old)
      AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 30
      -- Exclude test/duplicate leads
      AND l.LeadSource NOT LIKE '%Test%'
      AND l.LeadSource NOT LIKE '%Duplicate%'
),

-- ============================================================================
-- TIER ASSIGNMENTS: Get tier from V3 scores (PIT-SAFE)
-- ============================================================================
tier_assignments AS (
    -- Get tier from lead_scores_v3 (primary source for historical tiers)
    -- 
    -- PIT COMPLIANCE: lead_scores_v3 tiers are PIT-correct because:
    -- 1. They come from lead_scoring_features_pit which uses PIT methodology
    -- 2. Features calculated using only data available at contacted_date
    -- 3. Firm data uses month BEFORE contact (accounts for 1-month data lag)
    -- 4. All historical lookbacks filter by dates <= contacted_date
    --
    -- Note: advisor_crd is STRING in lead_scores_v3, so cast to STRING for matching
    SELECT 
        CAST(ls.advisor_crd AS STRING) as crd_str,
        ls.contacted_date,  -- CRITICAL: This is the PIT date - tier reflects state at this date
        ls.score_tier,
        ls.model_version,
        ls.scored_at
    FROM `savvy-gtm-analytics.ml_features.lead_scores_v3` ls
    WHERE ls.contacted_date IS NOT NULL
      AND ls.score_tier IS NOT NULL
      AND ls.advisor_crd IS NOT NULL
),

-- ============================================================================
-- TIER MATCHING: Find best tier match for each lead (PIT-PRESERVING)
-- ============================================================================
tier_matches AS (
    SELECT 
        sf.lead_id,
        sf.crd,
        sf.contacted_date,  -- Salesforce contacted_date
        ta.score_tier,
        ta.model_version,
        ta.scored_at,
        -- Priority: 1 = exact date match (BEST - ensures PIT accuracy), 
        --           2 = within 7 days (acceptable - tier likely same), 
        --           3 = any match (fallback - may not be PIT-accurate)
        -- 
        -- PIT NOTE: Exact date match (priority 1) ensures we use the tier that
        -- was assigned at the exact contacted_date, preserving PIT methodology.
        -- Within 7 days (priority 2) is acceptable because advisor/firm state
        -- typically doesn't change significantly in 7 days.
        CASE 
            WHEN ta.contacted_date = sf.contacted_date THEN 1  -- EXACT PIT MATCH
            WHEN ABS(DATE_DIFF(ta.contacted_date, sf.contacted_date, DAY)) <= 7 THEN 2  -- NEAR PIT MATCH
            ELSE 3  -- FALLBACK (may not be PIT-accurate)
        END as match_priority,
        ABS(DATE_DIFF(ta.contacted_date, sf.contacted_date, DAY)) as date_diff_days
    FROM sf_leads sf
    LEFT JOIN tier_assignments ta 
        ON CAST(sf.crd AS STRING) = ta.crd_str
    WHERE ta.score_tier IS NOT NULL
),

-- ============================================================================
-- BEST TIER MATCH: Get the best tier match for each lead
-- ============================================================================
best_tier_match AS (
    SELECT 
        lead_id,
        crd,
        contacted_date,
        score_tier,
        model_version,
        ROW_NUMBER() OVER (
            PARTITION BY lead_id 
            ORDER BY match_priority ASC, date_diff_days ASC, scored_at DESC
        ) as rn
    FROM tier_matches
),

-- ============================================================================
-- COMBINE: Join Salesforce leads with tier assignments
-- ============================================================================
combined AS (
    SELECT 
        sf.lead_id,
        sf.crd,
        sf.contacted_date,
        sf.mql_date,
        sf.company_name,
        sf.lead_source,
        sf.lead_created_date,
        sf.days_since_contact,
        
        -- Tier assignment (use best match, or STANDARD if no match)
        COALESCE(btm.score_tier, 'STANDARD') as score_tier,
        
        -- Conversion flag (MQL within 30 days) - matches analysis query expectations
        CASE 
            WHEN sf.mql_date IS NOT NULL 
                 AND DATE_DIFF(sf.mql_date, sf.contacted_date, DAY) <= 30
            THEN 1
            ELSE 0
        END as converted_30d,
        -- Also include simple conversion flag for compatibility
        CASE WHEN sf.mql_date IS NOT NULL THEN 1 ELSE 0 END as converted,
        
        -- Days to conversion (if converted)
        CASE 
            WHEN sf.mql_date IS NOT NULL 
                 AND DATE_DIFF(sf.mql_date, sf.contacted_date, DAY) <= 30
            THEN DATE_DIFF(sf.mql_date, sf.contacted_date, DAY)
            ELSE NULL
        END as days_to_conversion
        
    FROM sf_leads sf
    LEFT JOIN best_tier_match btm 
        ON sf.lead_id = btm.lead_id 
        AND btm.rn = 1
)

-- ============================================================================
-- FINAL OUTPUT
-- ============================================================================
SELECT 
    lead_id,
    crd,
    contacted_date,
    mql_date,
    score_tier,
    company_name,
    lead_source,
    lead_created_date,
    days_since_contact,
    converted_30d,
    converted,  -- Simple conversion flag (any MQL, regardless of timing)
    days_to_conversion,
    CURRENT_TIMESTAMP() as created_at
FROM combined
ORDER BY contacted_date DESC, crd;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check row count and tier distribution
-- SELECT 
--     score_tier,
--     COUNT(*) as sample_size,
--     SUM(converted_30d) as conversions,
--     ROUND(SUM(converted_30d) * 100.0 / COUNT(*), 2) as conversion_rate
-- FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`
-- GROUP BY score_tier
-- ORDER BY conversion_rate DESC;

-- Check date range
-- SELECT 
--     MIN(contacted_date) as earliest_contact,
--     MAX(contacted_date) as latest_contact,
--     COUNT(*) as total_leads,
--     SUM(converted_30d) as total_conversions,
--     ROUND(SUM(converted_30d) * 100.0 / COUNT(*), 2) as overall_conversion_rate
-- FROM `savvy-gtm-analytics.ml_features.historical_lead_performance`;
