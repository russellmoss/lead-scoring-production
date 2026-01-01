-- ============================================================================
-- CAREER CLOCK PERFORMANCE MONITORING
-- Run weekly to track V3.4.0 tier performance
-- ============================================================================

-- 1. TIER PERFORMANCE vs EXPECTED
SELECT 
    'Career Clock Tier Performance' as report_section,
    score_tier,
    COUNT(*) as leads_contacted,
    SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as conversions,
    ROUND(AVG(CASE WHEN mql_date IS NOT NULL THEN 1.0 ELSE 0.0 END) * 100, 2) as actual_conv_rate,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_rate,
    ROUND(
        (AVG(CASE WHEN mql_date IS NOT NULL THEN 1.0 ELSE 0.0 END) - AVG(expected_conversion_rate)) 
        / AVG(expected_conversion_rate) * 100, 
    1) as pct_vs_expected
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` l
LEFT JOIN `savvy-gtm-analytics.salesforce_data.leads` sf ON l.crd = sf.FA_CRD__c
WHERE score_tier LIKE 'TIER_0%'
   OR score_tier IN ('TIER_1A_PRIME_MOVER_CFP', 'TIER_1B_PRIME_ZERO_FRICTION', 'STANDARD')
GROUP BY score_tier
ORDER BY MIN(priority_rank);

-- 2. NURTURE LIST: LEADS ENTERING MOVE WINDOW
SELECT 
    'Nurture List - Entering Window' as report_section,
    COUNT(*) as total_nurture_leads,
    COUNTIF(estimated_window_entry_date <= CURRENT_DATE()) as entered_window,
    COUNTIF(estimated_window_entry_date BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY)) as entering_next_30_days,
    COUNTIF(estimated_window_entry_date BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 90 DAY)) as entering_next_90_days
FROM `savvy-gtm-analytics.ml_features.nurture_list_too_early`;

-- 3. CAREER CLOCK PATTERN VALIDATION
SELECT
    'Career Clock Pattern Validation' as report_section,
    cc_career_pattern,
    cc_cycle_status,
    COUNT(*) as leads,
    SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as conversions,
    ROUND(AVG(CASE WHEN mql_date IS NOT NULL THEN 1.0 ELSE 0.0 END) * 100, 2) as conv_rate
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` l
LEFT JOIN `savvy-gtm-analytics.salesforce_data.leads` sf ON l.crd = sf.FA_CRD__c
WHERE cc_career_pattern IS NOT NULL
GROUP BY cc_career_pattern, cc_cycle_status
ORDER BY cc_career_pattern, 
    CASE cc_cycle_status WHEN 'In_Window' THEN 1 WHEN 'Too_Early' THEN 2 ELSE 3 END;

-- 4. ALERT: Tiers underperforming by >20%
SELECT 
    'ALERT: Underperforming Tiers' as report_section,
    score_tier,
    actual_conv_rate,
    expected_conv_rate,
    pct_vs_expected
FROM (
    SELECT 
        score_tier,
        ROUND(AVG(CASE WHEN mql_date IS NOT NULL THEN 1.0 ELSE 0.0 END) * 100, 2) as actual_conv_rate,
        ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_rate,
        ROUND(
            (AVG(CASE WHEN mql_date IS NOT NULL THEN 1.0 ELSE 0.0 END) - AVG(expected_conversion_rate)) 
            / AVG(expected_conversion_rate) * 100, 
        1) as pct_vs_expected
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` l
    LEFT JOIN `savvy-gtm-analytics.salesforce_data.leads` sf ON l.crd = sf.FA_CRD__c
    WHERE score_tier LIKE 'TIER_0%' OR score_tier LIKE 'TIER_1%'
    GROUP BY score_tier
    HAVING COUNT(*) >= 10  -- Only tiers with sufficient sample
)
WHERE pct_vs_expected < -20;
