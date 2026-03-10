-- ============================================================================
-- V4.1.0 Salesforce Sync Query
-- ============================================================================
-- 
-- PURPOSE: Generate update payloads for Salesforce Lead records
-- 
-- VERSION: V4.1.0 R3 (Deployed: 2025-12-30)
-- 
-- USAGE:
--   1. Run this query to get scores for leads
--   2. Use Python script to sync to Salesforce
--   3. Updates Lead records with V4.1.0 scores
-- 
-- SALESFORCE FIELDS:
--   - V4_Score__c: Raw prediction (0-1)
--   - V4_Score_Percentile__c: Percentile rank (1-100)
--   - V4_Deprioritize__c: Boolean (TRUE if percentile <= 20)
--   - V4_Model_Version__c: Model version string ('v4.1.0')
--   - V4_Scored_At__c: Timestamp of scoring
-- ============================================================================

-- ============================================================================
-- STEP 1: Get scores from v4_daily_scores_v41 and calculate percentiles
-- ============================================================================
-- Note: This assumes scores have been calculated and stored in v4_daily_scores_v41
-- If scores are not yet calculated, use lead_scorer_v4.py to generate them first
-- ============================================================================

WITH scored_leads AS (
    SELECT 
        ds.lead_id,
        ds.advisor_crd,
        ds.prediction_date,
        ds.model_version,
        ds.scored_at,
        
        -- Calculate percentile from scores (if scores are in the table)
        -- If scores are not in the table, they need to be calculated first using lead_scorer_v4.py
        -- For now, this query assumes scores will be added to the table after scoring
        
        -- Placeholder: In production, scores should be calculated and stored
        -- This query structure is ready for when scores are added
        
        CURRENT_TIMESTAMP() as sync_timestamp
    FROM `savvy-gtm-analytics.ml_features.v4_daily_scores_v41` ds
    WHERE ds.model_version = 'v4.1.0'
      -- Only sync leads that are still in "Contacting" stage (not converted)
      AND ds.lead_id IN (
          SELECT Id 
          FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
          WHERE Stage_Entered_Call_Scheduled__c IS NULL
            AND stage_entered_contacting__c IS NOT NULL
      )
)

-- ============================================================================
-- STEP 2: Format for Salesforce update
-- ============================================================================
-- This query will need to be updated once scores are calculated and stored
-- For now, it provides the structure for the sync
-- ============================================================================

SELECT 
    sl.lead_id as Id,
    
    -- V4.1.0 Score (0-1) - TO BE POPULATED AFTER SCORING
    -- CAST(v4_score AS FLOAT64) as V4_Score__c,
    NULL as V4_Score__c,  -- Placeholder - will be populated after scoring
    
    -- V4.1.0 Percentile (1-100) - TO BE POPULATED AFTER SCORING
    -- CAST(v4_percentile AS INT64) as V4_Score_Percentile__c,
    NULL as V4_Score_Percentile__c,  -- Placeholder - will be populated after scoring
    
    -- V4.1.0 Deprioritize flag (TRUE if percentile <= 20) - TO BE POPULATED AFTER SCORING
    -- CASE WHEN v4_percentile <= 20 THEN TRUE ELSE FALSE END as V4_Deprioritize__c,
    FALSE as V4_Deprioritize__c,  -- Placeholder - will be populated after scoring
    
    -- Model version
    'v4.1.0' as V4_Model_Version__c,
    
    -- Timestamp
    sl.scored_at as V4_Scored_At__c
    
FROM scored_leads sl
ORDER BY sl.scored_at DESC
LIMIT 1000;  -- Limit for testing - remove in production

-- ============================================================================
-- NOTES:
-- ============================================================================
-- 
-- 1. This query structure is ready for when scores are calculated
-- 2. Scores should be calculated using lead_scorer_v4.py and stored in a scores table
-- 3. Once scores are available, update this query to join with the scores table
-- 4. The actual sync to Salesforce should be done via Python script using simple-salesforce
-- 
-- RECOMMENDED WORKFLOW:
--   1. Query v4_daily_scores_v41 for leads needing scores
--   2. Use lead_scorer_v4.py to generate predictions
--   3. Calculate percentiles and deprioritize flags
--   4. Store scores in a scores table (or add to v4_daily_scores_v41)
--   5. Run this query to get sync payload
--   6. Use Python script to update Salesforce
-- 
-- ============================================================================

