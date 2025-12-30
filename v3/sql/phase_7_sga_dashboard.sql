
-- V3.2.1_12212025 SGA Dashboard View (with certifications)
CREATE OR REPLACE VIEW `savvy-gtm-analytics.ml_features.sga_priority_leads_v3` AS
SELECT 
    -- Lead Info
    lead_id,
    advisor_crd,
    contacted_date,
    
    -- Tier Info
    tier_display as Priority,
    action_recommended as Action,
    tier_explanation as Why_Prioritized,
    
    -- Expected Performance
    ROUND(expected_conversion_rate * 100, 1) as Expected_Conv_Pct,
    expected_lift as Lift_vs_Baseline,
    
    -- Key Signals (transparency for sales team)
    ROUND(current_firm_tenure_months / 12.0, 1) as Tenure_Years,
    ROUND(industry_tenure_months / 12.0, 0) as Experience_Years,
    firm_net_change_12mo as Firm_Net_Change,
    firm_rep_count_at_contact as Firm_Size,
    num_prior_firms as Prior_Firms,
    
    -- Certification Flags (V3.2.1 - NEW)
    CASE WHEN has_cfp = 1 THEN 'Yes' ELSE 'No' END as Has_CFP,
    CASE WHEN has_series_65_only = 1 THEN 'Yes' ELSE 'No' END as Series_65_Only,
    CASE WHEN has_series_7 = 1 THEN 'Yes' ELSE 'No' END as Has_Series_7,
    CASE WHEN has_cfa = 1 THEN 'Yes' ELSE 'No' END as Has_CFA,
    
    -- Scoring metadata
    scored_at,
    model_version

FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_2_12212025`
WHERE score_tier != 'STANDARD'
ORDER BY priority_rank, expected_conversion_rate DESC
