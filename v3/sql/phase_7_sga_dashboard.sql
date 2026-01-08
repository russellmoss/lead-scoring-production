
-- V3.6.0_01082026 SGA Dashboard View (with Career Clock tiers)
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
    
    -- Certification Flags
    CASE WHEN has_cfp = 1 THEN 'Yes' ELSE 'No' END as Has_CFP,
    CASE WHEN has_series_65_only = 1 THEN 'Yes' ELSE 'No' END as Series_65_Only,
    CASE WHEN has_series_7 = 1 THEN 'Yes' ELSE 'No' END as Has_Series_7,
    CASE WHEN has_cfa = 1 THEN 'Yes' ELSE 'No' END as Has_CFA,
    
    -- V3.6.0: Career Clock features
    CASE WHEN cc_is_in_move_window = 1 THEN 'Yes' ELSE 'No' END as In_Move_Window,
    CASE WHEN cc_is_too_early = 1 THEN 'Yes' ELSE 'No' END as Too_Early,
    cc_career_pattern as Career_Pattern,
    cc_cycle_status as Cycle_Status,
    
    -- Scoring metadata
    scored_at,
    model_version

FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_6`
WHERE score_tier != 'STANDARD'
  AND score_tier != 'TIER_NURTURE_TOO_EARLY'  -- V3.6.0: Exclude nurture leads
ORDER BY priority_rank, expected_conversion_rate DESC
