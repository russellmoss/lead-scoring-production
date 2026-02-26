SELECT score_tier, COUNT(*) AS cnt FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_6` GROUP BY score_tier ORDER BY cnt DESC;
