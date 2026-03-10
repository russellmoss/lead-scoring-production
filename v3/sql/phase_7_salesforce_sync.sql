
-- V3.6.0 Salesforce Sync Query
-- Run this query to generate update payloads for Salesforce
-- Updated: January 8, 2026 - V3.6.0 Career Clock Tiers

SELECT 
    lead_id as Id,
    score_tier as Lead_Score_Tier__c,
    tier_display as Lead_Tier_Display__c,
    CAST(expected_conversion_rate * 100 AS STRING) || '%' as Expected_Conversion__c,
    CAST(expected_lift AS STRING) || 'x' as Expected_Lift__c,
    priority_rank as Lead_Priority_Rank__c,
    action_recommended as Lead_Action__c,
    tier_explanation as Lead_Score_Explanation__c,
    model_version as Lead_Model_Version__c,
    scored_at as Lead_Scored_At__c
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_6`
WHERE score_tier != 'STANDARD'
  AND score_tier != 'TIER_NURTURE_TOO_EARLY'  -- V3.6.0: Exclude nurture leads
    AND contacted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)  -- Only sync recent leads
