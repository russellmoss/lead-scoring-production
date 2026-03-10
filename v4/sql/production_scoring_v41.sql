-- ============================================================================
-- PRODUCTION SCORING: V4.1.0 Feature Engineering for Live Leads
-- ============================================================================
-- 
-- PURPOSE: Generate features for V4.1.0 model scoring on current leads
-- 
-- VERSION: V4.1.0 R3 (Deployed: 2025-12-30)
-- FEATURES: 22 (removed 4 redundant: industry_tenure_months, tenure_bucket_x_mobility,
--              independent_ria_x_ia_rep, recent_mover_x_bleeding)
-- 
-- USAGE:
--   - Run daily to score new leads
--   - Refresh when new leads are added or advisor data is updated
--   - Features are PIT-compliant (use only data available at CURRENT_DATE)
-- 
-- DEPLOYMENT:
--   - This SQL prepares features
--   - Python model (lead_scorer_v4.py) generates predictions
--   - Scores are written back to BigQuery/Salesforce
-- 
-- HYBRID STRATEGY:
--   - V3 Rules: Primary prioritization (T1, T2, T3, T4, Standard)
--   - V4.1.0 Score: Deprioritization filter (skip bottom 20%)
--   - Combined: V3 tier + V4.1.0 percentile = final priority
-- ============================================================================

-- ============================================================================
-- VIEW: Production Features for Scoring (V4.1.0)
-- ============================================================================
-- This view calculates features for all leads that need scoring
-- Includes V4.1.0 new features: bleeding signals, firm/rep type
-- ============================================================================

CREATE OR REPLACE VIEW `savvy-gtm-analytics.ml_features.v4_production_features_v41` AS

WITH 
-- ============================================================================
-- BASE: Get leads that need scoring
-- ============================================================================
base AS (
    SELECT 
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as advisor_crd,
        CURRENT_DATE() as prediction_date,  -- Use current date as "contact date" for scoring
        l.LeadSource,
        l.Email,
        l.LinkedIn_Profile_Apollo__c as linkedin_url,
        -- Group lead source for filtering
        CASE 
            WHEN l.LeadSource LIKE '%Provided%' OR l.LeadSource LIKE '%List%' THEN 'Provided List'
            WHEN l.LeadSource LIKE '%LinkedIn%' THEN 'LinkedIn'
            ELSE 'Other'
        END as lead_source_grouped
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.FA_CRD__c IS NOT NULL
      AND l.stage_entered_contacting__c IS NOT NULL
      -- Only score leads that are contacted but not yet converted
      AND l.Stage_Entered_Call_Scheduled__c IS NULL
      -- Exclude Savvy employees
      AND (l.Company IS NULL OR UPPER(l.Company) NOT LIKE '%SAVVY%')
),

-- ============================================================================
-- FEATURE GROUP 1: TENURE FEATURES (from employment history)
-- ============================================================================
history_firm AS (
    SELECT 
        b.lead_id,
        b.prediction_date,
        b.advisor_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_date,
        DATE_DIFF(b.prediction_date, eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) as tenure_months
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
        AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= b.prediction_date
        AND (eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
             OR eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= b.prediction_date)
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY b.lead_id 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
),

current_snapshot AS (
    SELECT 
        b.lead_id,
        b.prediction_date,
        b.advisor_crd,
        c.LATEST_REGISTERED_EMPLOYMENT_COMPANY_CRD_ID as firm_crd,
        c.LATEST_REGISTERED_EMPLOYMENT_COMPANY as firm_name,
        c.LATEST_REGISTERED_EMPLOYMENT_START_DATE as firm_start_date,
        CASE 
            WHEN c.LATEST_REGISTERED_EMPLOYMENT_START_DATE <= b.prediction_date 
            THEN DATE_DIFF(b.prediction_date, c.LATEST_REGISTERED_EMPLOYMENT_START_DATE, MONTH)
            ELSE NULL
        END as tenure_months
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON b.advisor_crd = c.RIA_CONTACT_CRD_ID
    WHERE c.LATEST_REGISTERED_EMPLOYMENT_START_DATE IS NOT NULL
      AND c.LATEST_REGISTERED_EMPLOYMENT_START_DATE <= b.prediction_date
),

current_firm AS (
    SELECT 
        COALESCE(hf.lead_id, cs.lead_id) as lead_id,
        COALESCE(hf.prediction_date, cs.prediction_date) as prediction_date,
        COALESCE(hf.advisor_crd, cs.advisor_crd) as advisor_crd,
        COALESCE(hf.firm_crd, cs.firm_crd) as firm_crd,
        COALESCE(hf.firm_name, cs.firm_name) as firm_name,
        COALESCE(hf.firm_start_date, cs.firm_start_date) as firm_start_date,
        COALESCE(hf.tenure_months, cs.tenure_months) as tenure_months
    FROM history_firm hf
    FULL OUTER JOIN current_snapshot cs
        ON hf.lead_id = cs.lead_id
    WHERE COALESCE(hf.lead_id, cs.lead_id) IS NOT NULL
),

-- ============================================================================
-- FEATURE GROUP 2: MOBILITY FEATURES
-- ============================================================================
mobility AS (
    SELECT 
        b.lead_id,
        b.prediction_date,
        COUNT(DISTINCT CASE 
            WHEN eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE > DATE_SUB(b.prediction_date, INTERVAL 3 YEAR)
                AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= b.prediction_date
            THEN eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID
        END) as mobility_3yr
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
    GROUP BY b.lead_id, b.prediction_date
),

-- ============================================================================
-- FEATURE GROUP 3: FIRM STABILITY
-- ============================================================================
firm_stability AS (
    SELECT
        cf.lead_id,
        cf.firm_crd,
        cf.prediction_date,
        COALESCE((
            SELECT COUNT(DISTINCT eh_d.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_d
            WHERE eh_d.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
              AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(cf.prediction_date, INTERVAL 12 MONTH)
              AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE < cf.prediction_date
              AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
        ), 0) as firm_departures_12mo,
        COALESCE((
            SELECT COUNT(DISTINCT eh_a.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_a
            WHERE eh_a.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
              AND eh_a.PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(cf.prediction_date, INTERVAL 12 MONTH)
              AND eh_a.PREVIOUS_REGISTRATION_COMPANY_START_DATE < cf.prediction_date
        ), 0) as firm_arrivals_12mo,
        COALESCE((
            SELECT COUNT(DISTINCT eh_current.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_current
            WHERE eh_current.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
              AND eh_current.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= cf.prediction_date
              AND (eh_current.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL OR eh_current.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= cf.prediction_date)
        ), 0) as firm_rep_count_at_contact
    FROM current_firm cf
    WHERE cf.firm_crd IS NOT NULL
),

-- ============================================================================
-- FEATURE GROUP 4: WIREHOUSE & BROKER PROTOCOL
-- ============================================================================
wirehouse AS (
    SELECT
        cf.lead_id,
        CASE
            WHEN UPPER(cf.firm_name) LIKE '%MERRILL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%MORGAN STANLEY%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%UBS%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%WELLS FARGO%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%EDWARD JONES%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%RAYMOND JAMES%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%AMERIPRISE%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%LPL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%NORTHWESTERN MUTUAL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%STIFEL%' THEN 1
            ELSE 0
        END as is_wirehouse
    FROM current_firm cf
),

broker_protocol AS (
    SELECT
        cf.lead_id,
        CASE WHEN bp.firm_crd_id IS NOT NULL THEN 1 ELSE 0 END as is_broker_protocol
    FROM current_firm cf
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.broker_protocol_members` bp
        ON cf.firm_crd = bp.firm_crd_id
    QUALIFY ROW_NUMBER() OVER(PARTITION BY cf.lead_id ORDER BY bp.firm_crd_id) = 1
),

-- ============================================================================
-- FEATURE GROUP 5: EXPERIENCE
-- ============================================================================
experience AS (
    SELECT
        b.lead_id,
        COALESCE(c.INDUSTRY_TENURE_MONTHS, 0) / 12.0 as experience_years,
        CASE WHEN c.INDUSTRY_TENURE_MONTHS IS NULL THEN 1 ELSE 0 END as is_experience_missing
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON b.advisor_crd = c.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- FEATURE GROUP 6: DATA QUALITY FLAGS
-- ============================================================================
data_quality AS (
    SELECT
        b.lead_id,
        CASE WHEN b.Email IS NOT NULL THEN 1 ELSE 0 END as has_email,
        CASE WHEN b.linkedin_url IS NOT NULL THEN 1 ELSE 0 END as has_linkedin,
        CASE WHEN b.advisor_crd IS NOT NULL THEN 1 ELSE 0 END as has_fintrx_match,
        CASE WHEN cf.firm_crd IS NOT NULL THEN 1 ELSE 0 END as has_employment_history
    FROM base b
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id
),

-- ============================================================================
-- V4.1.0 NEW FEATURES: RECENT MOVER DETECTION (PIT-SAFE)
-- ============================================================================
recent_mover_pit AS (
    SELECT 
        b.lead_id,
        b.prediction_date,
        b.advisor_crd,
        rc.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        
        -- PIT-safe: Only consider start dates BEFORE prediction date
        CASE 
            WHEN rc.PRIMARY_FIRM_START_DATE IS NOT NULL
             AND rc.PRIMARY_FIRM_START_DATE <= b.prediction_date
             AND DATE_DIFF(b.prediction_date, rc.PRIMARY_FIRM_START_DATE, DAY) <= 365
            THEN 1 ELSE 0 
        END as is_recent_mover,
        
        -- Days since last move (PIT-safe)
        CASE 
            WHEN rc.PRIMARY_FIRM_START_DATE IS NOT NULL
             AND rc.PRIMARY_FIRM_START_DATE <= b.prediction_date
            THEN DATE_DIFF(b.prediction_date, rc.PRIMARY_FIRM_START_DATE, DAY)
            ELSE 9999  -- Default for no move detected
        END as days_since_last_move
        
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON b.advisor_crd = rc.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- V4.1.0 NEW FEATURES: CORRECTED FIRM BLEEDING (PIT-SAFE)
-- ============================================================================
firm_bleeding_pit AS (
    SELECT 
        b.lead_id,
        b.prediction_date,
        COALESCE(cf.firm_crd, 0) as firm_crd,
        
        -- Count departures in 12 months BEFORE prediction date (PIT-safe)
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.prediction_date, INTERVAL 365 DAY)
             AND ida.inferred_departure_date < b.prediction_date
            THEN ida.advisor_crd 
        END) as firm_departures_corrected,
        
        -- Departures in last 90 days before prediction date
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.prediction_date, INTERVAL 90 DAY)
             AND ida.inferred_departure_date < b.prediction_date
            THEN ida.advisor_crd 
        END) as departures_90d_before_contact,
        
        -- Departures 91-180 days before prediction date
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.prediction_date, INTERVAL 180 DAY)
             AND ida.inferred_departure_date < DATE_SUB(b.prediction_date, INTERVAL 90 DAY)
            THEN ida.advisor_crd 
        END) as departures_90_180d_before_contact
        
    FROM base b
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id
    LEFT JOIN `savvy-gtm-analytics.ml_features.inferred_departures_analysis` ida
        ON COALESCE(cf.firm_crd, 0) = ida.departed_firm_crd
    GROUP BY b.lead_id, b.prediction_date, COALESCE(cf.firm_crd, 0)
),

-- ============================================================================
-- V4.1.0 NEW FEATURES: BLEEDING VELOCITY (PIT-SAFE)
-- ============================================================================
bleeding_velocity_pit AS (
    SELECT 
        lead_id,
        prediction_date,
        firm_crd,
        firm_departures_corrected,
        departures_90d_before_contact,
        departures_90_180d_before_contact,
        
        -- Bleeding velocity category (PIT-safe)
        CASE 
            WHEN firm_departures_corrected < 3 THEN 0  -- STABLE
            WHEN departures_90d_before_contact > departures_90_180d_before_contact * 1.5 THEN 3  -- ACCELERATING
            WHEN departures_90d_before_contact < departures_90_180d_before_contact * 0.5 THEN 1  -- DECELERATING
            ELSE 2  -- STEADY
        END as bleeding_velocity_encoded
        
    FROM firm_bleeding_pit
),

-- ============================================================================
-- V4.1.0 NEW FEATURES: FIRM TYPE AND REP TYPE FEATURES
-- ============================================================================
-- NOTE: These use current state - acceptable small PIT risk (firm classification is stable)
-- ============================================================================
firm_rep_type_features AS (
    SELECT 
        b.lead_id,
        b.advisor_crd,
        frt.is_independent_ria,
        frt.is_ia_rep_type,
        frt.is_dual_registered
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.ml_features.firm_rep_type_features_v41` frt
        ON b.advisor_crd = frt.advisor_crd
),

-- ============================================================================
-- COMBINE ALL FEATURES (matching V4.1.0 R3 training feature set - 22 features)
-- ============================================================================
all_features AS (
    SELECT
        -- Base columns
        b.lead_id,
        b.advisor_crd,
        b.prediction_date,
        b.lead_source_grouped,

        -- Firm at contact
        cf.firm_crd,
        cf.firm_name,

        -- GROUP 1: TENURE FEATURES
        COALESCE(cf.tenure_months, 0) as tenure_months,
        CASE
            WHEN cf.tenure_months IS NULL THEN 'Unknown'
            WHEN cf.tenure_months < 12 THEN '0-12'
            WHEN cf.tenure_months < 24 THEN '12-24'
            WHEN cf.tenure_months < 48 THEN '24-48'
            WHEN cf.tenure_months < 120 THEN '48-120'
            ELSE '120+'
        END as tenure_bucket,

        -- Experience (NOTE: industry_tenure_months removed in V4.1.0 R3)
        e.experience_years,
        CASE
            WHEN e.experience_years < 5 THEN '0-5'
            WHEN e.experience_years < 10 THEN '5-10'
            WHEN e.experience_years < 15 THEN '10-15'
            WHEN e.experience_years < 20 THEN '15-20'
            ELSE '20+'
        END as experience_bucket,
        e.is_experience_missing,

        -- GROUP 2: MOBILITY FEATURES
        COALESCE(m.mobility_3yr, 0) as mobility_3yr,
        CASE
            WHEN COALESCE(m.mobility_3yr, 0) = 0 THEN 'Stable'
            WHEN COALESCE(m.mobility_3yr, 0) = 1 THEN 'Low_Mobility'
            ELSE 'High_Mobility'
        END as mobility_tier,

        -- GROUP 3: FIRM STABILITY FEATURES
        fs.firm_rep_count_at_contact,
        COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) as firm_net_change_12mo,
        CASE
            WHEN cf.firm_crd IS NULL THEN 'Unknown'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < -10 THEN 'Heavy_Bleeding'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < 0 THEN 'Light_Bleeding'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) = 0 THEN 'Stable'
            ELSE 'Growing'
        END as firm_stability_tier,
        CASE WHEN cf.firm_crd IS NULL THEN 0 ELSE 1 END as has_firm_data,

        -- GROUP 4: WIREHOUSE & BROKER PROTOCOL
        COALESCE(w.is_wirehouse, 0) as is_wirehouse,
        COALESCE(bp.is_broker_protocol, 0) as is_broker_protocol,

        -- GROUP 5: DATA QUALITY FLAGS
        dq.has_email,
        dq.has_linkedin,
        dq.has_fintrx_match,
        dq.has_employment_history,

        -- ====================================================================
        -- INTERACTION FEATURES (NOTE: tenure_bucket_x_mobility removed in V4.1.0 R3)
        -- ====================================================================
        CASE
            WHEN COALESCE(m.mobility_3yr, 0) >= 2
                AND (COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0)) < -10
            THEN 1 ELSE 0
        END as mobility_x_heavy_bleeding,

        CASE
            WHEN COALESCE(cf.tenure_months, 9999) < 24 AND COALESCE(m.mobility_3yr, 0) >= 2
            THEN 1 ELSE 0
        END as short_tenure_x_high_mobility,

        -- ====================================================================
        -- V4.1.0 BLEEDING SIGNAL FEATURES
        -- ====================================================================
        COALESCE(rm.is_recent_mover, 0) as is_recent_mover,
        COALESCE(rm.days_since_last_move, 9999) as days_since_last_move,
        COALESCE(bv.firm_departures_corrected, 0) as firm_departures_corrected,
        COALESCE(bv.bleeding_velocity_encoded, 0) as bleeding_velocity_encoded,
        -- NOTE: recent_mover_x_bleeding removed in V4.1.0 R3

        -- ====================================================================
        -- V4.1.0 FIRM/REP TYPE FEATURES
        -- ====================================================================
        COALESCE(frt.is_independent_ria, 0) as is_independent_ria,
        COALESCE(frt.is_ia_rep_type, 0) as is_ia_rep_type,
        COALESCE(frt.is_dual_registered, 0) as is_dual_registered,
        -- NOTE: independent_ria_x_ia_rep removed in V4.1.0 R3

        -- Metadata
        CURRENT_TIMESTAMP() as feature_extraction_timestamp

    FROM base b
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id
    LEFT JOIN mobility m ON b.lead_id = m.lead_id
    LEFT JOIN firm_stability fs ON b.lead_id = fs.lead_id
    LEFT JOIN wirehouse w ON b.lead_id = w.lead_id
    LEFT JOIN broker_protocol bp ON b.lead_id = bp.lead_id
    LEFT JOIN experience e ON b.lead_id = e.lead_id
    LEFT JOIN data_quality dq ON b.lead_id = dq.lead_id
    LEFT JOIN recent_mover_pit rm ON b.lead_id = rm.lead_id
    LEFT JOIN bleeding_velocity_pit bv ON b.lead_id = bv.lead_id
    LEFT JOIN firm_rep_type_features frt ON b.lead_id = frt.lead_id
)

SELECT * FROM all_features;

-- ============================================================================
-- TABLE: Daily Scores (for caching and Salesforce sync) - V4.1.0
-- ============================================================================
-- This table stores the latest scores for each lead
-- Refresh daily or when new leads are added
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_daily_scores_v41` AS

SELECT
    pf.lead_id,
    pf.advisor_crd,
    pf.prediction_date,
    -- All features (for model inference) - 22 features matching V4.1.0 R3
    pf.tenure_bucket,
    pf.experience_bucket,
    pf.is_experience_missing,
    pf.mobility_tier,
    pf.firm_rep_count_at_contact,
    pf.firm_net_change_12mo,
    pf.firm_stability_tier,
    pf.has_firm_data,
    pf.is_wirehouse,
    pf.is_broker_protocol,
    pf.has_email,
    pf.has_linkedin,
    pf.mobility_x_heavy_bleeding,
    pf.short_tenure_x_high_mobility,
    -- V4.1.0 new features
    pf.is_recent_mover,
    pf.days_since_last_move,
    pf.firm_departures_corrected,
    pf.bleeding_velocity_encoded,
    pf.is_independent_ria,
    pf.is_ia_rep_type,
    pf.is_dual_registered,
    -- Metadata
    CURRENT_TIMESTAMP() as scored_at,
    'v4.1.0' as model_version
FROM `savvy-gtm-analytics.ml_features.v4_production_features_v41` pf;

-- ============================================================================
-- USAGE NOTES
-- ============================================================================
--
-- REFRESH SCHEDULE:
--   - Run daily (recommended: 6 AM EST)
--   - Refresh when new leads are added
--   - Refresh when advisor data is updated in FINTRX
--
-- TRIGGERS FOR RESCORE:
--   - New lead enters "Contacting" stage
--   - Advisor changes firms (employment history updated)
--   - Firm stability data refreshed (monthly)
--
-- DATA FRESHNESS:
--   - FINTRX data: Updated daily
--   - Employment history: Real-time (backfilled)
--   - Firm stability: Calculated from employment history (real-time)
--   - Inferred departures: Updated daily (from ml_features.inferred_departures_analysis)
--   - Firm/rep type features: Updated daily (from ml_features.firm_rep_type_features_v41)
--
-- PYTHON SCORING:
--   1. Query this table/view for leads needing scores
--   2. Use lead_scorer_v4.py (V4.1.0) to generate predictions
--   3. Write scores back to BigQuery/Salesforce
--   4. Calculate percentile (1-100) for deprioritization
--
-- SALESFORCE FIELDS:
--   - V4_Score__c: Raw prediction (0-1)
--   - V4_Score_Percentile__c: Percentile rank (1-100)
--   - V4_Deprioritize__c: TRUE if bottom 20% (percentile <= 20)
--
-- MODEL VERSION:
--   - V4.1.0 R3 (22 features, deployed 2025-12-30)
--   - Model location: v4/models/v4.1.0/model.pkl
--   - Features file: v4/data/v4.1.0/final_features.json
--
-- ============================================================================

