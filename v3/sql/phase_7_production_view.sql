
-- =============================================================================
-- V3.6.0 Production View - Current Lead Scores
-- =============================================================================
-- Version: V3.6.0_01082026_CAREER_CLOCK_TIERS
-- 
-- CHANGES FROM V3.2.1:
-- - Updated to reference lead_scores_v3_6 table (was lead_scores_v3)
-- - Includes Career Clock tiers (TIER_0A, TIER_0B, TIER_0C, TIER_NURTURE_TOO_EARLY)
-- - Updated conversion rates based on career_clock_results.md analysis
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
    -- Certification flags
    has_cfp,
    has_series_65_only,
    has_series_7,
    has_cfa,
    is_hv_wealth_title,
    -- V3.3.1: Portable book signal flags
    discretionary_tier,
    discretionary_ratio,
    is_low_discretionary,
    is_large_firm,
    -- V3.3.2: Account size for T1G Growth Stage tier
    avg_account_size,
    practice_maturity,
    -- V3.3.3: Portable custodian flag
    has_portable_custodian,
    -- V3.6.0: Career Clock features
    cc_is_in_move_window,
    cc_is_too_early,
    cc_career_pattern,
    cc_cycle_status,
    cc_months_until_window,
    scored_at,
    model_version
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_6`
WHERE score_tier != 'STANDARD'  -- Only priority leads in this view
  AND score_tier != 'TIER_NURTURE_TOO_EARLY'  -- V3.6.0: Exclude nurture leads from active view
ORDER BY priority_rank, expected_conversion_rate DESC
