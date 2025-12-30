-- File: v4/sql/v4.1/phase_6_train_test_split.sql
-- Purpose: Create temporal train/test split for V4.1 model training

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_splits_v41` AS

SELECT 
    *,
    CASE 
        -- TRAIN: Feb 2024 - July 2025
        WHEN contacted_date >= '2024-02-01' AND contacted_date <= '2025-07-31' 
        THEN 'TRAIN'
        
        -- GAP: August 2025 (excluded)
        WHEN contacted_date >= '2025-08-01' AND contacted_date <= '2025-08-31' 
        THEN 'GAP'
        
        -- TEST: September - October 2025
        WHEN contacted_date >= '2025-09-01' AND contacted_date <= '2025-10-31' 
        THEN 'TEST'
        
        ELSE 'EXCLUDED'
    END as split

FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE target IS NOT NULL;

-- Validation query
SELECT 
    split,
    COUNT(*) as lead_count,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    MIN(contacted_date) as min_date,
    MAX(contacted_date) as max_date,
    DATE_DIFF(MAX(contacted_date), MIN(contacted_date), DAY) as date_range_days
FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
GROUP BY split
ORDER BY 
    CASE split
        WHEN 'TRAIN' THEN 1
        WHEN 'GAP' THEN 2
        WHEN 'TEST' THEN 3
        ELSE 4
    END;

