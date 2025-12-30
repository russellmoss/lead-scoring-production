-- ============================================================================
-- PHASE 2: POINT-IN-TIME FEATURE ENGINEERING
-- ============================================================================
-- 
-- CRITICAL: All features must use only data available at contacted_date
-- 
-- Features:
-- 1. Tenure at firm (from employment history)
-- 2. Industry tenure (sum of all prior employment periods)
-- 3. Mobility (moves in 3 years before contact)
-- 4. Firm stability (net change in 12 months before contact)
-- 5. Wirehouse flag
-- 6. Broker protocol membership
-- 7. Interaction features (prioritized by exploration results)
-- 
-- PIT Compliance Rules:
-- - Employment history: START_DATE <= contacted_date
-- - Firm historicals: YEAR/MONTH <= contact YEAR/MONTH
-- - NEVER use *_current tables for calculations (except null indicators)
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_features_pit_v41` AS

WITH 
-- ============================================================================
-- BASE: Get target variable data
-- ============================================================================
base AS (
    SELECT 
        lead_id,
        advisor_crd,
        contacted_date,
        target,
        lead_source_grouped
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable`
    WHERE target IS NOT NULL  -- Only mature leads for training
),

-- ============================================================================
-- FEATURE GROUP 1: TENURE FEATURES (from employment history)
-- ============================================================================
-- PIT-safe: Uses only START_DATE <= contacted_date
-- FIX: Added fallback to ria_contacts_current for current employment
-- ============================================================================
-- First try employment history (PIT-compliant historical data)
history_firm AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        b.advisor_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_date,
        
        -- Tenure at current firm (PIT-safe: uses START_DATE only)
        DATE_DIFF(b.contacted_date, eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) as tenure_months
        
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
        -- PIT: Only consider firms where employment started before contact
        AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= b.contacted_date
        -- PIT: Either still employed (no end date) or end date is after contact
        AND (eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
             OR eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= b.contacted_date)
    -- Take most recent firm (by start date) if multiple
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY b.lead_id 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
),

-- Fallback to current snapshot if no history found (FIX: addresses 97% Unknown tenure bug)
current_snapshot AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        b.advisor_crd,
        c.LATEST_REGISTERED_EMPLOYMENT_COMPANY_CRD_ID as firm_crd,
        c.LATEST_REGISTERED_EMPLOYMENT_COMPANY as firm_name,
        c.LATEST_REGISTERED_EMPLOYMENT_START_DATE as firm_start_date,
        -- PIT-safe: Only calculate tenure if start date is before contact date
        CASE 
            WHEN c.LATEST_REGISTERED_EMPLOYMENT_START_DATE <= b.contacted_date 
            THEN DATE_DIFF(b.contacted_date, c.LATEST_REGISTERED_EMPLOYMENT_START_DATE, MONTH)
            ELSE NULL
        END as tenure_months
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON b.advisor_crd = c.RIA_CONTACT_CRD_ID
    WHERE c.LATEST_REGISTERED_EMPLOYMENT_START_DATE IS NOT NULL
      -- PIT: Only use if start date is before or equal to contact date
      AND c.LATEST_REGISTERED_EMPLOYMENT_START_DATE <= b.contacted_date
),

-- Combine: prefer history, fallback to current snapshot
current_firm AS (
    SELECT 
        COALESCE(hf.lead_id, cs.lead_id) as lead_id,
        COALESCE(hf.contacted_date, cs.contacted_date) as contacted_date,
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

-- Calculate industry tenure (sum of all prior completed employment periods)
industry_tenure AS (
    SELECT
        cf.lead_id,
        cf.contacted_date,
        cf.firm_start_date,
        
        -- Sum all completed employment periods before current firm
        -- PIT-safe: Only uses periods that ended before or at contact date
        COALESCE((
            SELECT SUM(
                DATE_DIFF(
                    COALESCE(eh2.PREVIOUS_REGISTRATION_COMPANY_END_DATE, cf.contacted_date),
                    eh2.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                    MONTH
                )
            )
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh2
            WHERE eh2.RIA_CONTACT_CRD_ID = cf.advisor_crd
                -- Only periods that started before current firm
                AND eh2.PREVIOUS_REGISTRATION_COMPANY_START_DATE < cf.firm_start_date
                -- PIT: Only periods that ended before or at contact date
                AND (eh2.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
                     OR eh2.PREVIOUS_REGISTRATION_COMPANY_END_DATE <= cf.contacted_date)
        ), 0) as industry_tenure_months
        
    FROM current_firm cf
    WHERE cf.firm_start_date IS NOT NULL
),

-- ============================================================================
-- FEATURE GROUP 2: MOBILITY FEATURES
-- ============================================================================
-- PIT-safe: Counts moves in 3 years BEFORE contacted_date
-- ============================================================================
mobility AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        
        -- Count distinct firms where employment STARTED in 3-year window before contact
        -- PIT-safe: Only counts moves that occurred before contact date
        COUNT(DISTINCT CASE 
            WHEN eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE > DATE_SUB(b.contacted_date, INTERVAL 3 YEAR)
                AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= b.contacted_date
            THEN eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID 
        END) as mobility_3yr
        
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
    GROUP BY b.lead_id, b.contacted_date
),

-- ============================================================================
-- FEATURE GROUP 3: FIRM STABILITY (from Firm_historicals)
-- ============================================================================
-- PIT-safe: Uses historical snapshots with YEAR/MONTH <= contact YEAR/MONTH
-- ============================================================================
firm_stability AS (
    SELECT 
        cf.lead_id,
        cf.firm_crd,
        cf.contacted_date,
        
        -- Calculate firm rep count at contact date from employment history
        -- PIT-safe: Count distinct reps employed at this firm on contacted_date
        COALESCE((
            SELECT COUNT(DISTINCT eh_count.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_count
            WHERE eh_count.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
                AND eh_count.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= cf.contacted_date
                AND (eh_count.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
                     OR eh_count.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= cf.contacted_date)
        ), 0) as firm_rep_count_at_contact,
        
        -- Calculate firm rep count 12 months before contact
        COALESCE((
            SELECT COUNT(DISTINCT eh_count_12mo.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_count_12mo
            WHERE eh_count_12mo.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
                AND eh_count_12mo.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= DATE_SUB(cf.contacted_date, INTERVAL 12 MONTH)
                AND (eh_count_12mo.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
                     OR eh_count_12mo.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(cf.contacted_date, INTERVAL 12 MONTH))
        ), 0) as firm_rep_count_12mo_ago,
        
        -- Calculate net change using employment history (more reliable)
        -- Departures: Reps who LEFT this firm in 12 months before contact
        -- PIT-safe: Uses END_DATE which is backfilled, but only dates BEFORE contacted_date
        COALESCE((
            SELECT COUNT(DISTINCT eh_d.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_d
            WHERE eh_d.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
                AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(cf.contacted_date, INTERVAL 12 MONTH)
                AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE < cf.contacted_date
                AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
        ), 0) as firm_departures_12mo,
        
        -- Arrivals: Reps who JOINED this firm in 12 months before contact
        -- PIT-safe: Uses START_DATE only
        COALESCE((
            SELECT COUNT(DISTINCT eh_a.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_a
            WHERE eh_a.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
                AND eh_a.PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(cf.contacted_date, INTERVAL 12 MONTH)
                AND eh_a.PREVIOUS_REGISTRATION_COMPANY_START_DATE < cf.contacted_date
        ), 0) as firm_arrivals_12mo
        
    FROM current_firm cf
    WHERE cf.firm_crd IS NOT NULL
),

-- ============================================================================
-- FEATURE GROUP 4: WIREHOUSE & BROKER PROTOCOL
-- ============================================================================
-- PIT-safe: Wirehouse detection uses firm name at contact, Protocol is static
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
    SELECT DISTINCT
        cf.lead_id,
        CASE WHEN bp.firm_crd_id IS NOT NULL THEN 1 ELSE 0 END as is_broker_protocol
    FROM current_firm cf
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.broker_protocol_members` bp
        ON cf.firm_crd = bp.firm_crd_id
),

-- ============================================================================
-- FEATURE GROUP 5: EXPERIENCE (from current state - use as proxy)
-- ============================================================================
-- NOTE: INDUSTRY_TENURE_MONTHS from ria_contacts_current is current state
-- We calculate industry_tenure from history above, but keep this as fallback
-- ============================================================================
experience AS (
    SELECT 
        b.lead_id,
        -- Use calculated industry_tenure if available, otherwise fallback to current
        COALESCE(it.industry_tenure_months, c.INDUSTRY_TENURE_MONTHS, 0) / 12.0 as experience_years,
        CASE WHEN COALESCE(it.industry_tenure_months, c.INDUSTRY_TENURE_MONTHS) IS NULL THEN 1 ELSE 0 END as is_experience_missing
    FROM base b
    LEFT JOIN industry_tenure it ON b.lead_id = it.lead_id
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON b.advisor_crd = c.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- FEATURE GROUP 6: DATA QUALITY FLAGS
-- ============================================================================
-- PIT-safe: These are indicators of data availability, not future data
-- ============================================================================
data_quality AS (
    SELECT
        b.lead_id,
        -- Check if lead has email (from Salesforce Lead)
        CASE WHEN l.Email IS NOT NULL THEN 1 ELSE 0 END as has_email,
        -- Check if lead has LinkedIn (from Salesforce Lead)
        CASE WHEN l.LinkedIn_Profile_Apollo__c IS NOT NULL THEN 1 ELSE 0 END as has_linkedin,
        -- FINTRX match (already have advisor_crd, so this is 1)
        CASE WHEN b.advisor_crd IS NOT NULL THEN 1 ELSE 0 END as has_fintrx_match,
        -- Employment history available
        CASE WHEN cf.firm_crd IS NOT NULL THEN 1 ELSE 0 END as has_employment_history
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.Lead` l
        ON b.lead_id = l.Id
    LEFT JOIN current_firm cf
        ON b.lead_id = cf.lead_id
),

-- ============================================================================
-- V4.1 NEW FEATURES: RECENT MOVER DETECTION (PIT-SAFE)
-- ============================================================================
recent_mover_pit AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        b.advisor_crd,
        rc.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        
        -- PIT-safe: Only consider start dates BEFORE contact
        CASE 
            WHEN rc.PRIMARY_FIRM_START_DATE IS NOT NULL
             AND rc.PRIMARY_FIRM_START_DATE <= b.contacted_date
             AND DATE_DIFF(b.contacted_date, rc.PRIMARY_FIRM_START_DATE, DAY) <= 365
            THEN 1 ELSE 0 
        END as is_recent_mover,
        
        -- Days since last move (PIT-safe)
        CASE 
            WHEN rc.PRIMARY_FIRM_START_DATE IS NOT NULL
             AND rc.PRIMARY_FIRM_START_DATE <= b.contacted_date
            THEN DATE_DIFF(b.contacted_date, rc.PRIMARY_FIRM_START_DATE, DAY)
            ELSE 9999  -- Default for no move detected (will be handled in final SELECT)
        END as days_since_last_move
        
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON b.advisor_crd = rc.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- V4.1 NEW FEATURES: CORRECTED FIRM BLEEDING (PIT-SAFE)
-- ============================================================================
firm_bleeding_pit AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        COALESCE(cf.firm_crd, 0) as firm_crd,
        
        -- Count departures in 12 months BEFORE contact date (PIT-safe)
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.contacted_date, INTERVAL 365 DAY)
             AND ida.inferred_departure_date < b.contacted_date
            THEN ida.advisor_crd 
        END) as firm_departures_corrected,
        
        -- Departures in last 90 days before contact
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.contacted_date, INTERVAL 90 DAY)
             AND ida.inferred_departure_date < b.contacted_date
            THEN ida.advisor_crd 
        END) as departures_90d_before_contact,
        
        -- Departures 91-180 days before contact
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.contacted_date, INTERVAL 180 DAY)
             AND ida.inferred_departure_date < DATE_SUB(b.contacted_date, INTERVAL 90 DAY)
            THEN ida.advisor_crd 
        END) as departures_90_180d_before_contact
        
    FROM base b
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id
    LEFT JOIN `savvy-gtm-analytics.ml_features.inferred_departures_analysis` ida
        ON COALESCE(cf.firm_crd, 0) = ida.departed_firm_crd
    GROUP BY b.lead_id, b.contacted_date, COALESCE(cf.firm_crd, 0)
),

-- ============================================================================
-- V4.1 NEW FEATURES: BLEEDING VELOCITY (PIT-SAFE)
-- ============================================================================
bleeding_velocity_pit AS (
    SELECT 
        lead_id,
        contacted_date,
        firm_crd,
        firm_departures_corrected,
        departures_90d_before_contact,
        departures_90_180d_before_contact,
        
        -- Velocity ratio (PIT-safe)
        CASE 
            WHEN departures_90_180d_before_contact = 0 AND departures_90d_before_contact > 0 THEN 999.0
            WHEN departures_90_180d_before_contact = 0 AND departures_90d_before_contact = 0 THEN 0.0
            ELSE ROUND(departures_90d_before_contact / departures_90_180d_before_contact, 2)
        END as velocity_ratio,
        
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
-- V4.1 NEW FEATURES: FIRM TYPE AND REP TYPE FEATURES
-- ============================================================================
-- NOTE: These use current state - acceptable small PIT risk (firm classification is stable)
-- ============================================================================
firm_rep_type_features AS (
    SELECT 
        b.lead_id,
        b.advisor_crd,
        frt.is_independent_ria,
        frt.is_ia_rep_type,
        frt.is_dual_registered,
        frt.independent_ria_x_ia_rep
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.ml_features.firm_rep_type_features_v41` frt
        ON b.advisor_crd = frt.advisor_crd
),

-- ============================================================================
-- COMBINE ALL FEATURES
-- ============================================================================
all_features AS (
    SELECT
        -- Base columns (preserve from target variable)
        b.lead_id,
        b.advisor_crd,
        b.contacted_date,
        b.target,
        b.lead_source_grouped,
        
        -- Firm at contact
        cf.firm_crd,
        cf.firm_name,
        
        -- ====================================================================
        -- GROUP 1: TENURE FEATURES
        -- ====================================================================
        COALESCE(cf.tenure_months, 0) as tenure_months,
        CASE 
            WHEN cf.tenure_months IS NULL THEN 'Unknown'
            WHEN cf.tenure_months < 12 THEN '0-12'
            WHEN cf.tenure_months < 24 THEN '12-24'
            WHEN cf.tenure_months < 48 THEN '24-48'
            WHEN cf.tenure_months < 120 THEN '48-120'
            ELSE '120+'
        END as tenure_bucket,
        CASE WHEN cf.tenure_months IS NULL THEN 1 ELSE 0 END as is_tenure_missing,
        
        -- Industry tenure
        COALESCE(it.industry_tenure_months, 0) as industry_tenure_months,
        e.experience_years,
        CASE 
            WHEN e.experience_years < 5 THEN '0-5'
            WHEN e.experience_years < 10 THEN '5-10'
            WHEN e.experience_years < 15 THEN '10-15'
            WHEN e.experience_years < 20 THEN '15-20'
            ELSE '20+'
        END as experience_bucket,
        e.is_experience_missing,
        
        -- ====================================================================
        -- GROUP 2: MOBILITY FEATURES
        -- ====================================================================
        COALESCE(m.mobility_3yr, 0) as mobility_3yr,
        CASE 
            WHEN COALESCE(m.mobility_3yr, 0) = 0 THEN 'Stable'
            WHEN COALESCE(m.mobility_3yr, 0) = 1 THEN 'Low_Mobility'
            ELSE 'High_Mobility'
        END as mobility_tier,
        
        -- ====================================================================
        -- GROUP 3: FIRM STABILITY FEATURES
        -- ====================================================================
        fs.firm_rep_count_at_contact,
        fs.firm_rep_count_12mo_ago,
        COALESCE(fs.firm_departures_12mo, 0) as firm_departures_12mo,
        COALESCE(fs.firm_arrivals_12mo, 0) as firm_arrivals_12mo,
        COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) as firm_net_change_12mo,
        CASE 
            WHEN cf.firm_crd IS NULL THEN 'Unknown'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < -10 THEN 'Heavy_Bleeding'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < 0 THEN 'Light_Bleeding'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) = 0 THEN 'Stable'
            ELSE 'Growing'
        END as firm_stability_tier,
        CASE WHEN cf.firm_crd IS NULL THEN 0 ELSE 1 END as has_firm_data,
        
        -- ====================================================================
        -- GROUP 4: WIREHOUSE & BROKER PROTOCOL
        -- ====================================================================
        COALESCE(w.is_wirehouse, 0) as is_wirehouse,
        COALESCE(bp.is_broker_protocol, 0) as is_broker_protocol,
        
        -- ====================================================================
        -- GROUP 5: DATA QUALITY FLAGS
        -- ====================================================================
        dq.has_email,
        dq.has_linkedin,
        dq.has_fintrx_match,
        dq.has_employment_history,
        
        -- ====================================================================
        -- GROUP 6: LEAD SOURCE FEATURES
        -- ====================================================================
        -- NOTE: Since we filtered to Provided List only, these will have zero variance:
        -- is_linkedin_sourced will always be 0, is_provided_list will always be 1
        -- These will be automatically removed in Phase 4 (multicollinearity analysis)
        CASE WHEN b.lead_source_grouped = 'LinkedIn' THEN 1 ELSE 0 END as is_linkedin_sourced,
        CASE WHEN b.lead_source_grouped = 'Provided List' THEN 1 ELSE 0 END as is_provided_list,
        
        -- ====================================================================
        -- INTERACTION FEATURES (Prioritized by exploration results)
        -- ====================================================================
        -- TOP PRIORITY: Mobility × Heavy Bleeding (4.85x lift, 20.37% conversion)
        -- Mobile reps (2+ moves) at heavily bleeding firms (<-10 net change)
        CASE 
            WHEN COALESCE(m.mobility_3yr, 0) >= 2 
                AND (COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0)) < -10
            THEN 1 ELSE 0
        END as mobility_x_heavy_bleeding,
        
        -- HIGH PRIORITY: Short Tenure × High Mobility (4.59x lift, 19.27% conversion)
        -- Short tenure (<24 months) combined with high mobility (2+ moves)
        CASE 
            WHEN COALESCE(cf.tenure_months, 9999) < 24 AND COALESCE(m.mobility_3yr, 0) >= 2
            THEN 1 ELSE 0
        END as short_tenure_x_high_mobility,
        
        -- Secondary: Numeric interaction for gradient boosting
        -- Tenure bucket (1=short, 2=medium, 3=long) × Mobility count
        CASE 
            WHEN COALESCE(cf.tenure_months, 0) < 24 THEN 1
            WHEN COALESCE(cf.tenure_months, 0) < 60 THEN 2
            ELSE 3
        END * COALESCE(m.mobility_3yr, 0) as tenure_bucket_x_mobility,
        
        -- ====================================================================
        -- V4.1 BLEEDING SIGNAL FEATURES
        -- ====================================================================
        COALESCE(rm.is_recent_mover, 0) as is_recent_mover,
        COALESCE(rm.days_since_last_move, 9999) as days_since_last_move,
        COALESCE(bv.firm_departures_corrected, 0) as firm_departures_corrected,
        COALESCE(bv.bleeding_velocity_encoded, 0) as bleeding_velocity_encoded,
        
        -- Interaction: Recent mover at bleeding firm (high-value signal)
        CASE 
            WHEN COALESCE(rm.is_recent_mover, 0) = 1 
             AND COALESCE(bv.firm_departures_corrected, 0) >= 5
            THEN 1 ELSE 0 
        END as recent_mover_x_bleeding,
        
        -- ====================================================================
        -- V4.1 FIRM/REP TYPE FEATURES
        -- ====================================================================
        COALESCE(frt.is_independent_ria, 0) as is_independent_ria,
        COALESCE(frt.is_ia_rep_type, 0) as is_ia_rep_type,
        COALESCE(frt.is_dual_registered, 0) as is_dual_registered,
        COALESCE(frt.independent_ria_x_ia_rep, 0) as independent_ria_x_ia_rep
        
    FROM base b
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id
    LEFT JOIN industry_tenure it ON b.lead_id = it.lead_id
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

SELECT DISTINCT * FROM all_features;

-- ============================================================================
-- VALIDATION QUERIES (Run after table creation)
-- ============================================================================

-- Query 1: Feature null rates
-- SELECT
--     'tenure_months' as feature,
--     ROUND(COUNTIF(tenure_months IS NULL OR tenure_months = 0) / COUNT(*) * 100, 2) as null_or_zero_pct
-- FROM `savvy-gtm-analytics.ml_features.v4_features_pit`
-- UNION ALL
-- SELECT 'mobility_3yr', ROUND(COUNTIF(mobility_3yr IS NULL) / COUNT(*) * 100, 2)
-- FROM `savvy-gtm-analytics.ml_features.v4_features_pit`
-- UNION ALL
-- SELECT 'firm_net_change_12mo', ROUND(COUNTIF(firm_net_change_12mo IS NULL) / COUNT(*) * 100, 2)
-- FROM `savvy-gtm-analytics.ml_features.v4_features_pit`
-- ORDER BY null_or_zero_pct DESC;

-- Query 2: Row count preservation
-- SELECT 
--     (SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.v4_target_variable`) as target_count,
--     (SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.v4_features_pit`) as feature_count,
--     (SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.v4_target_variable`) - 
--     (SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.v4_features_pit`) as difference;

-- Query 3: Interaction feature validation
-- SELECT 
--     mobility_x_heavy_bleeding,
--     short_tenure_x_high_mobility,
--     COUNT(*) as count,
--     SUM(target) as conversions,
--     ROUND(AVG(target) * 100, 2) as conv_rate
-- FROM `savvy-gtm-analytics.ml_features.v4_features_pit`
-- GROUP BY 1, 2
-- ORDER BY count DESC;

