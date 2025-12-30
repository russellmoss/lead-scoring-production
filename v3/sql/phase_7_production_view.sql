
-- =============================================================================
-- V3.2.1 Production View - Current Lead Scores
-- =============================================================================
-- Version: v3.2.1-updated-20250122
-- =============================================================================

CREATE OR REPLACE VIEW `savvy-gtm-analytics.ml_features.lead_scores_v3_current` AS
SELECT 
    lead_id,
    advisor_crd,
    contacted_date,
    score_tier,
    tier_display,
    expected_conversion_rate,
    expected_lift,
    priority_rank,
    action_recommended,
    tier_explanation,
    -- Include key features for transparency
    current_firm_tenure_months,
    industry_tenure_months,
    firm_net_change_12mo,
    firm_rep_count_at_contact,
    num_prior_firms,
    is_wirehouse,
    -- Certification flags (NEW)
    has_cfp,
    has_series_65_only,
    has_series_7,
    has_cfa,
    scored_at,
    model_version
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE score_tier != 'STANDARD'  -- Only priority leads in this view
ORDER BY priority_rank, expected_conversion_rate DESC
