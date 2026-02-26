-- V6.1: Lead count and tier distribution
SELECT score_tier, COUNT(*) AS cnt
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY score_tier
ORDER BY cnt DESC;
