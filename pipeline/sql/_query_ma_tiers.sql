SELECT ma_tier, COUNT(*) AS cnt FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors` GROUP BY ma_tier ORDER BY cnt DESC;
