-- File: v4/sql/v4.1/create_recent_movers_table.sql
-- Purpose: Identify recent movers using START_DATE inference (60-90 days fresher signal)

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.recent_movers_v41` AS

WITH current_employment AS (
    -- Get current firm info for all advisors
    SELECT 
        CAST(RIA_CONTACT_CRD_ID AS INT64) as advisor_crd,
        SAFE_CAST(PRIMARY_FIRM AS INT64) as current_firm_crd,
        PRIMARY_FIRM_NAME as current_firm_name,
        PRIMARY_FIRM_START_DATE as current_firm_start_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE RIA_CONTACT_CRD_ID IS NOT NULL
      AND PRIMARY_FIRM IS NOT NULL
      AND PRIMARY_FIRM_START_DATE IS NOT NULL
),

prior_employment AS (
    -- Get most recent prior firm for each advisor
    SELECT 
        ida.advisor_crd,
        ida.departed_firm_crd as prior_firm_crd,
        ida.departed_firm_name as prior_firm_name,
        ida.inferred_departure_date as prior_firm_departure_date,
        ida.inference_gap_days
    FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis` ida
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ida.advisor_crd 
        ORDER BY ida.inferred_departure_date DESC
    ) = 1
)

SELECT 
    ce.advisor_crd,
    ce.current_firm_crd,
    ce.current_firm_name,
    ce.current_firm_start_date,
    pe.prior_firm_crd,
    pe.prior_firm_name,
    pe.prior_firm_departure_date,
    
    -- Days since move (using current firm start date)
    DATE_DIFF(CURRENT_DATE(), ce.current_firm_start_date, DAY) as days_since_move,
    
    -- Recent mover flags
    CASE 
        WHEN DATE_DIFF(CURRENT_DATE(), ce.current_firm_start_date, DAY) <= 365 
        THEN TRUE ELSE FALSE 
    END as is_recent_mover_12mo,
    
    CASE 
        WHEN DATE_DIFF(CURRENT_DATE(), ce.current_firm_start_date, DAY) <= 180 
        THEN TRUE ELSE FALSE 
    END as is_recent_mover_6mo,
    
    -- Flag if we detected via inference (has prior firm match)
    CASE WHEN pe.prior_firm_crd IS NOT NULL THEN TRUE ELSE FALSE END as move_detected_via_inference,
    
    -- Inference accuracy (gap between inferred and actual)
    pe.inference_gap_days

FROM current_employment ce
LEFT JOIN prior_employment pe
    ON ce.advisor_crd = pe.advisor_crd;

