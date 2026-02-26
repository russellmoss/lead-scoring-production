SELECT COUNT(*) AS score_count, COUNT(v4_score) AS with_score, MIN(v4_percentile) AS min_pct, MAX(v4_percentile) AS max_pct FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`;
