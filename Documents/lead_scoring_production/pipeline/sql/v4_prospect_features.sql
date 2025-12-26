-- ============================================================================
-- V4 PROSPECT FEATURES TABLE
-- Creates features for all FINTRX prospects to enable V4 scoring
-- Run monthly BEFORE lead list generation
-- 
-- PURPOSE: Calculate V4 model features for all producing advisors in FINTRX
-- TARGET TABLE: ml_features.v4_prospect_features
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_prospect_features` AS

WITH 
-- ============================================================================
-- BASE: All producing advisors from FINTRX
-- ============================================================================
base_prospects AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
        c.PRIMARY_FIRM_NAME as firm_name,
        c.LATEST_REGISTERED_EMPLOYMENT_START_DATE as firm_start_date,
        c.EMAIL,
        c.LINKEDIN_PROFILE_URL,
        CURRENT_DATE() as prediction_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    WHERE c.RIA_CONTACT_CRD_ID IS NOT NULL
      AND c.PRODUCING_ADVISOR = TRUE
      AND c.ACTIVE = TRUE
),

-- ============================================================================
-- FEATURE GROUP 1: TENURE FEATURES
-- ============================================================================
-- First try employment history (PIT-compliant historical data)
history_firm AS (
    SELECT 
        bp.crd,
        bp.prediction_date,
        bp.firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd_from_history,
        eh.PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name_from_history,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_date_from_history,
        DATE_DIFF(bp.prediction_date, eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) as tenure_months
    FROM base_prospects bp
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON bp.crd = eh.RIA_CONTACT_CRD_ID
        AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= bp.prediction_date
        AND (eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
             OR eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= bp.prediction_date)
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY bp.crd 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
),

-- Fallback to current snapshot if no history found
current_snapshot AS (
    SELECT 
        bp.crd,
        bp.prediction_date,
        bp.firm_crd,
        bp.firm_name,
        bp.firm_start_date,
        CASE 
            WHEN bp.firm_start_date IS NOT NULL AND bp.firm_start_date <= bp.prediction_date 
            THEN DATE_DIFF(bp.prediction_date, bp.firm_start_date, MONTH)
            ELSE NULL
        END as tenure_months
    FROM base_prospects bp
    WHERE bp.firm_start_date IS NOT NULL
      AND bp.firm_start_date <= bp.prediction_date
),

-- Combine: prefer history, fallback to current snapshot
current_firm AS (
    SELECT 
        COALESCE(hf.crd, cs.crd) as crd,
        COALESCE(hf.prediction_date, cs.prediction_date) as prediction_date,
        COALESCE(hf.firm_crd_from_history, cs.firm_crd) as firm_crd,
        COALESCE(hf.firm_name_from_history, cs.firm_name) as firm_name,
        COALESCE(hf.firm_start_date_from_history, cs.firm_start_date) as firm_start_date,
        COALESCE(hf.tenure_months, cs.tenure_months) as tenure_months
    FROM history_firm hf
    FULL OUTER JOIN current_snapshot cs
        ON hf.crd = cs.crd
    WHERE COALESCE(hf.crd, cs.crd) IS NOT NULL
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY COALESCE(hf.crd, cs.crd)
        ORDER BY 
            CASE WHEN hf.crd IS NOT NULL THEN 1 ELSE 2 END,  -- Prefer history
            COALESCE(hf.firm_start_date_from_history, cs.firm_start_date) DESC
    ) = 1
),

-- Calculate industry tenure (OPTIMIZED - use ria_contacts_current as fallback)
-- For simplicity, use the INDUSTRY_TENURE_MONTHS field from ria_contacts_current
-- This is pre-calculated and avoids correlated subqueries
-- Note: This may slightly differ from training data, but acceptable for production
industry_tenure AS (
    SELECT
        cf.crd,
        cf.prediction_date,
        cf.firm_start_date,
        -- Use pre-calculated industry tenure from ria_contacts_current
        -- Subtract current firm tenure to get prior experience
        GREATEST(
            COALESCE(c.INDUSTRY_TENURE_MONTHS, 0) - COALESCE(cf.tenure_months, 0),
            0
        ) as industry_tenure_months
    FROM current_firm cf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON cf.crd = c.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- FEATURE GROUP 2: MOBILITY FEATURES
-- ============================================================================
mobility AS (
    SELECT 
        bp.crd,
        bp.prediction_date,
        COUNT(DISTINCT CASE 
            WHEN eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE > DATE_SUB(bp.prediction_date, INTERVAL 3 YEAR)
                AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= bp.prediction_date
            THEN eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID
        END) as mobility_3yr
    FROM base_prospects bp
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON bp.crd = eh.RIA_CONTACT_CRD_ID
    GROUP BY bp.crd, bp.prediction_date
),

-- ============================================================================
-- FEATURE GROUP 3: FIRM STABILITY (OPTIMIZED - pre-aggregated, no correlated subqueries)
-- ============================================================================

-- Pre-aggregate departures by firm (runs once, not per row)
firm_departures_agg AS (
    SELECT 
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE < CURRENT_DATE()
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
),

-- Pre-aggregate arrivals by firm (runs once, not per row)
firm_arrivals_agg AS (
    SELECT 
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PREVIOUS_REGISTRATION_COMPANY_START_DATE < CURRENT_DATE()
    GROUP BY 1
),

-- Pre-aggregate current rep count by firm (runs once, not per row)
firm_rep_count_agg AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as rep_count
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
      AND PRODUCING_ADVISOR = TRUE
      AND ACTIVE = TRUE
    GROUP BY 1
),

-- Combine firm metrics (simple JOINs instead of correlated subqueries)
firm_stability AS (
    SELECT
        cf.crd,
        cf.firm_crd,
        cf.prediction_date,
        COALESCE(fd.departures_12mo, 0) as firm_departures_12mo,
        COALESCE(fa.arrivals_12mo, 0) as firm_arrivals_12mo,
        COALESCE(fr.rep_count, 0) as firm_rep_count_at_contact
    FROM current_firm cf
    LEFT JOIN firm_departures_agg fd ON cf.firm_crd = fd.firm_crd
    LEFT JOIN firm_arrivals_agg fa ON cf.firm_crd = fa.firm_crd
    LEFT JOIN firm_rep_count_agg fr ON cf.firm_crd = fr.firm_crd
    WHERE cf.firm_crd IS NOT NULL
),

-- ============================================================================
-- FEATURE GROUP 4: WIREHOUSE & BROKER PROTOCOL
-- ============================================================================
wirehouse AS (
    SELECT
        cf.crd,
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
        cf.crd,
        CASE WHEN bp.firm_crd_id IS NOT NULL THEN 1 ELSE 0 END as is_broker_protocol
    FROM current_firm cf
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.broker_protocol_members` bp
        ON cf.firm_crd = bp.firm_crd_id
    QUALIFY ROW_NUMBER() OVER(PARTITION BY cf.crd ORDER BY bp.firm_crd_id) = 1
),

-- ============================================================================
-- FEATURE GROUP 5: EXPERIENCE
-- ============================================================================
experience AS (
    SELECT
        bp.crd,
        COALESCE(it.industry_tenure_months, c.INDUSTRY_TENURE_MONTHS, 0) / 12.0 as experience_years,
        CASE WHEN COALESCE(it.industry_tenure_months, c.INDUSTRY_TENURE_MONTHS) IS NULL THEN 1 ELSE 0 END as is_experience_missing
    FROM base_prospects bp
    LEFT JOIN industry_tenure it ON bp.crd = it.crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON bp.crd = c.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- FEATURE GROUP 6: DATA QUALITY FLAGS
-- ============================================================================
data_quality AS (
    SELECT
        bp.crd,
        CASE WHEN bp.EMAIL IS NOT NULL AND bp.EMAIL != '' THEN 1 ELSE 0 END as has_email,
        CASE WHEN bp.LINKEDIN_PROFILE_URL IS NOT NULL AND bp.LINKEDIN_PROFILE_URL != '' THEN 1 ELSE 0 END as has_linkedin,
        CASE WHEN cf.firm_crd IS NOT NULL THEN 1 ELSE 0 END as has_firm_data
    FROM base_prospects bp
    LEFT JOIN current_firm cf ON bp.crd = cf.crd
),

-- ============================================================================
-- COMBINE ALL FEATURES (matching training feature set)
-- ============================================================================
all_features AS (
    SELECT
        -- Base columns
        bp.crd,
        bp.firm_crd,
        bp.prediction_date,

        -- GROUP 1: TENURE FEATURES
        CASE
            WHEN cf.tenure_months IS NULL THEN 'Unknown'
            WHEN cf.tenure_months < 12 THEN '0-12'
            WHEN cf.tenure_months < 24 THEN '12-24'
            WHEN cf.tenure_months < 48 THEN '24-48'
            WHEN cf.tenure_months < 120 THEN '48-120'
            ELSE '120+'
        END as tenure_bucket,

        -- GROUP 2: EXPERIENCE FEATURES
        CASE
            WHEN e.experience_years IS NULL OR e.experience_years = 0 THEN 'Unknown'
            WHEN e.experience_years < 5 THEN '0-5'
            WHEN e.experience_years < 10 THEN '5-10'
            WHEN e.experience_years < 15 THEN '10-15'
            WHEN e.experience_years < 20 THEN '15-20'
            ELSE '20+'
        END as experience_bucket,
        e.is_experience_missing,

        -- GROUP 3: MOBILITY FEATURES
        CASE
            WHEN COALESCE(m.mobility_3yr, 0) = 0 THEN 'Stable'
            WHEN COALESCE(m.mobility_3yr, 0) = 1 THEN 'Low_Mobility'
            ELSE 'High_Mobility'
        END as mobility_tier,

        -- GROUP 4: FIRM STABILITY FEATURES
        COALESCE(fs.firm_rep_count_at_contact, 0) as firm_rep_count_at_contact,
        COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) as firm_net_change_12mo,
        CASE
            WHEN cf.firm_crd IS NULL THEN 'Unknown'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < -10 THEN 'Heavy_Bleeding'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < 0 THEN 'Light_Bleeding'
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) = 0 THEN 'Stable'
            ELSE 'Growing'
        END as firm_stability_tier,
        dq.has_firm_data,

        -- GROUP 5: WIREHOUSE & BROKER PROTOCOL
        COALESCE(w.is_wirehouse, 0) as is_wirehouse,
        COALESCE(bp_protocol.is_broker_protocol, 0) as is_broker_protocol,

        -- GROUP 6: DATA QUALITY FLAGS
        dq.has_email,
        dq.has_linkedin,

        -- ============================================================================
        -- INTERACTION FEATURES
        -- ============================================================================
        CASE
            WHEN COALESCE(m.mobility_3yr, 0) >= 2
                AND (COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0)) < -10
            THEN 1 ELSE 0
        END as mobility_x_heavy_bleeding,

        CASE
            WHEN COALESCE(cf.tenure_months, 9999) < 24 AND COALESCE(m.mobility_3yr, 0) >= 2
            THEN 1 ELSE 0
        END as short_tenure_x_high_mobility,

        -- Metadata
        CURRENT_TIMESTAMP() as created_at

    FROM base_prospects bp
    LEFT JOIN current_firm cf ON bp.crd = cf.crd
    LEFT JOIN industry_tenure it ON bp.crd = it.crd
    LEFT JOIN mobility m ON bp.crd = m.crd
    LEFT JOIN firm_stability fs ON bp.crd = fs.crd
    LEFT JOIN wirehouse w ON bp.crd = w.crd
    LEFT JOIN broker_protocol bp_protocol ON bp.crd = bp_protocol.crd
    LEFT JOIN experience e ON bp.crd = e.crd
    LEFT JOIN data_quality dq ON bp.crd = dq.crd
)

SELECT * FROM all_features;

