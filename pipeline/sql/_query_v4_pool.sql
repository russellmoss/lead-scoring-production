SELECT COUNT(*) AS total_scored, COUNTIF(v4_percentile >= 80) AS high_v4_80pct, COUNTIF(v4_percentile >= 20) AS above_bottom_20 FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`;
