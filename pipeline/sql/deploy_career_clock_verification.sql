-- ============================================================================
-- CAREER CLOCK DEPLOYMENT VERIFICATION
-- Run after deploying Career Clock features to verify successful deployment
-- ============================================================================

-- 1. VERIFY FEATURE ENGINEERING: Career Clock columns exist
SELECT 
    'Feature Engineering Verification' as check_type,
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ PASS'
        ELSE '❌ FAIL - Career Clock columns missing'
    END as status,
    COUNT(*) as cc_column_count
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'lead_scoring_features_pit'
  AND column_name LIKE 'cc_%';

-- 2. VERIFY FEATURE ENGINEERING: Career Clock data populated
SELECT 
    'Feature Engineering Data' as check_type,
    COUNT(*) as total_leads,
    COUNTIF(cc_completed_jobs > 0) as leads_with_career_pattern,
    COUNTIF(cc_is_in_move_window = TRUE) as in_move_window,
    COUNTIF(cc_is_too_early = TRUE) as too_early,
    COUNTIF(cc_career_pattern = 'Clockwork') as clockwork_pattern,
    COUNTIF(cc_career_pattern = 'Semi_Predictable') as semi_predictable_pattern
FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`
WHERE cc_completed_jobs IS NOT NULL;

-- 3. VERIFY TIER SCORING: Career Clock tiers exist
SELECT 
    'Tier Scoring Verification' as check_type,
    score_tier,
    COUNT(*) as lead_count,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_conv_rate,
    ROUND(AVG(expected_lift), 2) as avg_expected_lift
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_4`
WHERE score_tier LIKE 'TIER_0%' 
   OR score_tier = 'TIER_NURTURE_TOO_EARLY'
GROUP BY score_tier
ORDER BY 
    CASE score_tier
        WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
        WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
        WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
        WHEN 'TIER_NURTURE_TOO_EARLY' THEN 4
    END;

-- 4. VERIFY LEAD LIST: Career Clock tiers in active list
SELECT 
    'Lead List - Active Tiers' as check_type,
    score_tier,
    COUNT(*) as lead_count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_0%'
GROUP BY score_tier
ORDER BY score_tier;

-- 5. VERIFY NURTURE LIST: Too-Early leads captured
SELECT 
    'Nurture List Verification' as check_type,
    COUNT(*) as total_nurture_leads,
    COUNTIF(estimated_window_entry_date <= CURRENT_DATE()) as entered_window,
    COUNTIF(estimated_window_entry_date BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY)) as entering_next_30_days,
    COUNTIF(estimated_window_entry_date BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 90 DAY)) as entering_next_90_days,
    AVG(cc_months_until_window) as avg_months_until_window
FROM `savvy-gtm-analytics.ml_features.nurture_list_too_early`;

-- 6. VERIFY: No TIER_NURTURE_TOO_EARLY in active list
SELECT 
    'Active List Exclusion Check' as check_type,
    CASE 
        WHEN COUNT(*) = 0 THEN '✅ PASS - No too-early leads in active list'
        ELSE CONCAT('❌ FAIL - Found ', CAST(COUNT(*) AS STRING), ' too-early leads in active list')
    END as status,
    COUNT(*) as too_early_in_active_list
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier = 'TIER_NURTURE_TOO_EARLY';

-- 7. SUMMARY: Career Clock feature distribution
SELECT 
    'Career Clock Pattern Distribution' as check_type,
    cc_career_pattern,
    cc_cycle_status,
    COUNT(*) as lead_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as pct_of_total
FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`
WHERE cc_career_pattern IS NOT NULL
GROUP BY cc_career_pattern, cc_cycle_status
ORDER BY 
    CASE cc_career_pattern
        WHEN 'Clockwork' THEN 1
        WHEN 'Semi_Predictable' THEN 2
        WHEN 'Variable' THEN 3
        WHEN 'Chaotic' THEN 4
        WHEN 'No_Pattern' THEN 5
    END,
    CASE cc_cycle_status
        WHEN 'In_Window' THEN 1
        WHEN 'Too_Early' THEN 2
        WHEN 'Overdue' THEN 3
        WHEN 'Unpredictable' THEN 4
        WHEN 'Unknown' THEN 5
    END;
