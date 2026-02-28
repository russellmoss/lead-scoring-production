SELECT 
    score_tier, 
    COUNT(*) as lead_count, 
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) as pct_of_total, 
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_conv_pct 
FROM `savvy-gtm-analytics.ml_features.march_2026_lead_list` 
GROUP BY score_tier 
ORDER BY lead_count DESC;
