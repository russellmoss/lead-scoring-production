-- V7.2: M&A tier count
SELECT score_tier, COUNT(*) AS cnt
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
GROUP BY score_tier;
