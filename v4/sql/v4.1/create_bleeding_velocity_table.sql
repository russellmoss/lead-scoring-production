-- File: v4/sql/v4.1/create_bleeding_velocity_table.sql
-- Purpose: Calculate bleeding velocity (is firm bleeding accelerating or decelerating?)

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.firm_bleeding_velocity_v41` AS

WITH departure_windows AS (
    SELECT 
        departed_firm_crd as firm_crd,
        departed_firm_name as firm_name,
        
        -- Last 90 days
        COUNT(DISTINCT CASE 
            WHEN inferred_departure_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN advisor_crd 
        END) as departures_last_90d,
        
        -- Prior 90 days (91-180 days ago)
        COUNT(DISTINCT CASE 
            WHEN inferred_departure_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
             AND inferred_departure_date < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN advisor_crd 
        END) as departures_prior_90d,
        
        -- Total 12 months
        COUNT(DISTINCT CASE 
            WHEN inferred_departure_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
            THEN advisor_crd 
        END) as departures_12mo
        
    FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis`
    WHERE departed_firm_crd IS NOT NULL
    GROUP BY departed_firm_crd, departed_firm_name
)

SELECT 
    firm_crd,
    firm_name,
    departures_last_90d,
    departures_prior_90d,
    departures_12mo,
    
    -- Velocity ratio (handle divide by zero)
    CASE 
        WHEN departures_prior_90d = 0 AND departures_last_90d > 0 THEN 999.0  -- New bleeding
        WHEN departures_prior_90d = 0 AND departures_last_90d = 0 THEN 0.0   -- Stable
        ELSE ROUND(departures_last_90d / departures_prior_90d, 2)
    END as velocity_ratio,
    
    -- Bleeding velocity category
    CASE 
        -- Stable: No significant bleeding in either period
        WHEN departures_12mo < 3 THEN 'STABLE'
        
        -- Accelerating: Last 90d has 50%+ more departures than prior 90d
        WHEN departures_last_90d > departures_prior_90d * 1.5 THEN 'ACCELERATING'
        
        -- Decelerating: Last 90d has 50%+ fewer departures than prior 90d  
        WHEN departures_last_90d < departures_prior_90d * 0.5 THEN 'DECELERATING'
        
        -- Steady: Similar rate in both periods
        ELSE 'STEADY'
    END as bleeding_velocity

FROM departure_windows;

