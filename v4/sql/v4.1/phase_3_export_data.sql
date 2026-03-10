-- File: v4/sql/v4.1/phase_3_export_data.sql
-- Purpose: Export feature data from BigQuery for model training
-- This query prepares data for export to CSV/Parquet for Python training

-- Export all features with split labels for training
-- Note: This query is used by Python script to download data

SELECT 
    -- Identifiers
    lead_id,
    advisor_crd,
    contacted_date,
    
    -- Target variable
    target,
    
    -- Split will be added in Phase 6, but we prepare data here
    -- For now, export all data - split will be applied in Python
    
    -- ====================================================================
    -- FEATURE GROUP 1: TENURE FEATURES
    -- ====================================================================
    tenure_months,
    tenure_bucket,
    is_tenure_missing,
    industry_tenure_months,
    experience_years,
    experience_bucket,
    is_experience_missing,
    
    -- ====================================================================
    -- FEATURE GROUP 2: MOBILITY FEATURES
    -- ====================================================================
    mobility_3yr,
    mobility_tier,
    
    -- ====================================================================
    -- FEATURE GROUP 3: FIRM STABILITY FEATURES
    -- ====================================================================
    firm_rep_count_at_contact,
    firm_rep_count_12mo_ago,
    firm_departures_12mo,
    firm_arrivals_12mo,
    firm_net_change_12mo,
    firm_stability_tier,
    has_firm_data,
    
    -- ====================================================================
    -- FEATURE GROUP 4: WIREHOUSE & BROKER PROTOCOL
    -- ====================================================================
    is_wirehouse,
    is_broker_protocol,
    
    -- ====================================================================
    -- FEATURE GROUP 5: DATA QUALITY FLAGS
    -- ====================================================================
    has_email,
    has_linkedin,
    has_fintrx_match,
    has_employment_history,
    
    -- ====================================================================
    -- FEATURE GROUP 6: LEAD SOURCE FEATURES
    -- ====================================================================
    is_linkedin_sourced,
    is_provided_list,
    
    -- ====================================================================
    -- INTERACTION FEATURES
    -- ====================================================================
    mobility_x_heavy_bleeding,
    short_tenure_x_high_mobility,
    tenure_bucket_x_mobility,
    
    -- ====================================================================
    -- V4.1 BLEEDING SIGNAL FEATURES
    -- ====================================================================
    is_recent_mover,
    days_since_last_move,
    firm_departures_corrected,
    bleeding_velocity_encoded,
    recent_mover_x_bleeding,
    
    -- ====================================================================
    -- V4.1 FIRM/REP TYPE FEATURES
    -- ====================================================================
    is_independent_ria,
    is_ia_rep_type,
    is_dual_registered,
    independent_ria_x_ia_rep

FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE target IS NOT NULL
ORDER BY contacted_date;

