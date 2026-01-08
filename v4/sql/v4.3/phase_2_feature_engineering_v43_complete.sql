-- ============================================================================
-- V4.3.1 TRAINING FEATURE ENGINEERING (CAREER CLOCK + RECENT PROMOTEE)
-- ============================================================================
-- 
-- CRITICAL: All features must use only data available at contacted_date
-- 
-- CHANGES FROM V4.2.0:
-- - ADDED: cc_is_in_move_window (Career Clock timing signal)
-- - ADDED: cc_is_too_early (Career Clock deprioritization signal)
-- - Total features: 26 (was 23)
--
-- V4.3.1 CHANGES:
-- - ADDED: is_likely_recent_promotee (Recent promotee pattern detection)
-- - FIXED: Career Clock now excludes current firm from employment history
-- 
-- PIT Compliance Rules:
-- - Employment history: START_DATE <= contacted_date
-- - Career Clock: END_DATE < contacted_date (only completed jobs)
-- - NEVER use *_current tables for calculations (except null indicators)
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_training_features_v43` AS

WITH 
-- ============================================================================
-- BASE: Get target variable data
-- ============================================================================
base AS (
    SELECT 
        lead_id,
        advisor_crd,
        contacted_date,
        target as converted,  -- Renamed for validation queries
        lead_source_grouped
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable`
    WHERE target IS NOT NULL  -- Only mature leads for training
),

-- ============================================================================
-- FEATURE GROUP 1: TENURE FEATURES (from employment history)
-- ============================================================================
history_firm AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        b.advisor_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_date,
        DATE_DIFF(b.contacted_date, eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) as tenure_months
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
        AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= b.contacted_date
        AND (eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
             OR eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= b.contacted_date)
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY b.lead_id 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
),

current_snapshot AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        b.advisor_crd,
        c.LATEST_REGISTERED_EMPLOYMENT_COMPANY_CRD_ID as firm_crd,
        c.LATEST_REGISTERED_EMPLOYMENT_COMPANY as firm_name,
        c.LATEST_REGISTERED_EMPLOYMENT_START_DATE as firm_start_date,
        CASE 
            WHEN c.LATEST_REGISTERED_EMPLOYMENT_START_DATE <= b.contacted_date 
            THEN DATE_DIFF(b.contacted_date, c.LATEST_REGISTERED_EMPLOYMENT_START_DATE, MONTH)
            ELSE NULL
        END as tenure_months
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON b.advisor_crd = c.RIA_CONTACT_CRD_ID
    WHERE c.LATEST_REGISTERED_EMPLOYMENT_START_DATE IS NOT NULL
      AND c.LATEST_REGISTERED_EMPLOYMENT_START_DATE <= b.contacted_date
),

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

industry_tenure AS (
    SELECT
        cf.lead_id,
        cf.contacted_date,
        cf.firm_start_date,
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
                AND eh2.PREVIOUS_REGISTRATION_COMPANY_START_DATE < cf.firm_start_date
                AND (eh2.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
                     OR eh2.PREVIOUS_REGISTRATION_COMPANY_END_DATE <= cf.contacted_date)
        ), 0) as industry_tenure_months
    FROM current_firm cf
    WHERE cf.firm_start_date IS NOT NULL
),

-- ============================================================================
-- FEATURE GROUP 2: MOBILITY FEATURES
-- ============================================================================
mobility AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
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
-- FEATURE GROUP 3: FIRM STABILITY
-- ============================================================================
firm_stability AS (
    SELECT 
        cf.lead_id,
        cf.firm_crd,
        cf.contacted_date,
        COALESCE((
            SELECT COUNT(DISTINCT eh_count.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_count
            WHERE eh_count.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
                AND eh_count.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= cf.contacted_date
                AND (eh_count.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
                     OR eh_count.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= cf.contacted_date)
        ), 0) as firm_rep_count_at_contact,
        COALESCE((
            SELECT COUNT(DISTINCT eh_d.RIA_CONTACT_CRD_ID)
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_d
            WHERE eh_d.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
                AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(cf.contacted_date, INTERVAL 12 MONTH)
                AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE < cf.contacted_date
                AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
        ), 0) as firm_departures_12mo,
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
-- FEATURE GROUP 5: EXPERIENCE
-- ============================================================================
experience AS (
    SELECT 
        b.lead_id,
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
data_quality AS (
    SELECT
        b.lead_id,
        CASE WHEN l.Email IS NOT NULL THEN 1 ELSE 0 END as has_email,
        CASE WHEN l.LinkedIn_Profile_Apollo__c IS NOT NULL THEN 1 ELSE 0 END as has_linkedin,
        CASE WHEN b.advisor_crd IS NOT NULL THEN 1 ELSE 0 END as has_fintrx_match,
        CASE WHEN cf.firm_crd IS NOT NULL THEN 1 ELSE 0 END as has_employment_history,
        CASE WHEN cf.firm_crd IS NOT NULL THEN 1 ELSE 0 END as has_firm_data
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.Lead` l
        ON b.lead_id = l.Id
    LEFT JOIN current_firm cf
        ON b.lead_id = cf.lead_id
),

-- ============================================================================
-- V4.1: RECENT MOVER DETECTION (PIT-SAFE)
-- ============================================================================
recent_mover_pit AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        b.advisor_crd,
        CASE 
            WHEN rc.PRIMARY_FIRM_START_DATE IS NOT NULL
             AND rc.PRIMARY_FIRM_START_DATE <= b.contacted_date
             AND DATE_DIFF(b.contacted_date, rc.PRIMARY_FIRM_START_DATE, DAY) <= 365
            THEN 1 ELSE 0 
        END as is_recent_mover,
        CASE 
            WHEN rc.PRIMARY_FIRM_START_DATE IS NOT NULL
             AND rc.PRIMARY_FIRM_START_DATE <= b.contacted_date
            THEN DATE_DIFF(b.contacted_date, rc.PRIMARY_FIRM_START_DATE, DAY)
            ELSE 9999
        END as days_since_last_move
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON b.advisor_crd = rc.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- V4.1: CORRECTED FIRM BLEEDING (PIT-SAFE)
-- ============================================================================
firm_bleeding_pit AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        COALESCE(cf.firm_crd, 0) as firm_crd,
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.contacted_date, INTERVAL 365 DAY)
             AND ida.inferred_departure_date < b.contacted_date
            THEN ida.advisor_crd 
        END) as firm_departures_corrected,
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.contacted_date, INTERVAL 90 DAY)
             AND ida.inferred_departure_date < b.contacted_date
            THEN ida.advisor_crd 
        END) as departures_90d_before_contact,
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
-- V4.1: BLEEDING VELOCITY (PIT-SAFE)
-- ============================================================================
bleeding_velocity_pit AS (
    SELECT 
        lead_id,
        contacted_date,
        firm_crd,
        firm_departures_corrected,
        departures_90d_before_contact,
        departures_90_180d_before_contact,
        CASE 
            WHEN firm_departures_corrected < 3 THEN 0
            WHEN departures_90d_before_contact > departures_90_180d_before_contact * 1.5 THEN 3
            WHEN departures_90d_before_contact < departures_90_180d_before_contact * 0.5 THEN 1
            ELSE 2
        END as bleeding_velocity_encoded
    FROM firm_bleeding_pit
),

-- ============================================================================
-- V4.1: FIRM TYPE AND REP TYPE FEATURES
-- ============================================================================
firm_rep_type_features AS (
    SELECT 
        b.lead_id,
        b.advisor_crd,
        COALESCE(frt.is_independent_ria, 0) as is_independent_ria,
        COALESCE(frt.is_ia_rep_type, 0) as is_ia_rep_type,
        COALESCE(frt.is_dual_registered, 0) as is_dual_registered
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.ml_features.firm_rep_type_features_v41` frt
        ON b.advisor_crd = frt.advisor_crd
),

-- ============================================================================
-- V4.2.0: AGE BUCKET FEATURE
-- ============================================================================
age_data AS (
    SELECT 
        RIA_CONTACT_CRD_ID as advisor_crd,
        CASE 
            WHEN AGE_RANGE IN ('18-24', '25-29', '30-34') THEN 0
            WHEN AGE_RANGE IN ('35-39', '40-44', '45-49') THEN 1
            WHEN AGE_RANGE IN ('50-54', '55-59', '60-64') THEN 2
            WHEN AGE_RANGE IN ('65-69') THEN 3
            WHEN AGE_RANGE IN ('70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 4
            ELSE 2
        END as age_bucket_encoded
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
),

-- ============================================================================
-- CAREER CLOCK STATS (V4.3.0) - TRAINING VERSION
-- ============================================================================
career_clock_stats_training AS (
    SELECT
        b.lead_id,
        b.advisor_crd,
        b.contacted_date,
        COUNT(*) as cc_completed_jobs,
        AVG(DATE_DIFF(
            eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
            eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
            MONTH
        )) as cc_avg_prior_tenure_months,
        SAFE_DIVIDE(
            STDDEV(DATE_DIFF(
                eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                MONTH
            )),
            AVG(DATE_DIFF(
                eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                MONTH
            ))
        ) as cc_tenure_cv
    FROM base b
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id
    WHERE eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < b.contacted_date
      AND DATE_DIFF(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                    eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) > 0
      -- ============================================================================
      -- V4.3.1 FIX: Exclude current firm from employment history
      -- ============================================================================
      -- Analysis (January 8, 2026) found ~692 advisors with polluted Career Clock
      -- data because their current firm appeared in employment history (e.g., firm
      -- re-registrations, CRD changes). This caused advisors like Rafael Delasierra
      -- (27yr founder) to incorrectly appear in "move window."
      -- ============================================================================
      AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != COALESCE(cf.firm_crd, -1)
    GROUP BY b.lead_id, b.advisor_crd, b.contacted_date
    HAVING COUNT(*) >= 2
),

-- ============================================================================
-- CAREER CLOCK FEATURES (V4.3.0) - TRAINING VERSION
-- ============================================================================
career_clock_features_training AS (
    SELECT
        cf.lead_id,
        cf.contacted_date,
        CASE 
            WHEN ccs.cc_tenure_cv IS NOT NULL 
                 AND ccs.cc_tenure_cv < 0.5 
                 AND SAFE_DIVIDE(cf.tenure_months, ccs.cc_avg_prior_tenure_months) BETWEEN 0.7 AND 1.3
            THEN 1 
            ELSE 0 
        END as cc_is_in_move_window,
        CASE 
            WHEN ccs.cc_tenure_cv IS NOT NULL 
                 AND ccs.cc_tenure_cv < 0.5 
                 AND SAFE_DIVIDE(cf.tenure_months, ccs.cc_avg_prior_tenure_months) < 0.7
            THEN 1 
            ELSE 0 
        END as cc_is_too_early
    FROM current_firm cf
    LEFT JOIN career_clock_stats_training ccs 
        ON cf.lead_id = ccs.lead_id
        AND cf.contacted_date = ccs.contacted_date
),

-- ============================================================================
-- RECENT PROMOTEE FEATURE (V4.3.1)
-- ============================================================================
-- Analysis (January 8, 2026) found advisors with <5 years industry tenure
-- holding mid/senior titles convert at 0.29-0.45% (0.10-0.16x baseline).
-- 
-- These "recent promotees" likely don't have portable books yet:
-- - Recently promoted from junior roles
-- - Still building client relationships
-- - May not have decision-making authority to move
--
-- Conversion by career stage:
--   LIKELY_RECENT_PROMOTEE (Senior): 0.29% (0.10x lift) - 348 leads
--   LIKELY_RECENT_PROMOTEE (Mid):    0.45% (0.16x lift) - 1,567 leads
--   ESTABLISHED_PRODUCER:            0.73% (0.27x lift) - baseline comparison
--   FOUNDER_OWNER:                   1.07% (0.39x lift) - DO NOT FLAG
-- ============================================================================
recent_promotee_feature AS (
    SELECT
        b.lead_id,
        CASE 
            -- Less than 5 years industry tenure (60 months)
            WHEN COALESCE(it.industry_tenure_months, c.INDUSTRY_TENURE_MONTHS, 0) < 60
            -- Has mid-level or senior title (suggests promotion)
            AND (
                UPPER(c.TITLE_NAME) LIKE '%FINANCIAL ADVISOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%WEALTH ADVISOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%INVESTMENT ADVISOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%FINANCIAL PLANNER%'
                OR UPPER(c.TITLE_NAME) LIKE '%PORTFOLIO MANAGER%'
                OR UPPER(c.TITLE_NAME) LIKE '%SENIOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%MANAGING%'
                OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%'
                OR UPPER(c.TITLE_NAME) LIKE '%VP %'
                OR UPPER(c.TITLE_NAME) LIKE '%VICE PRESIDENT%'
            )
            -- Exclude if they're clearly still junior (shouldn't be on list anyway)
            AND NOT (
                UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE%'
                OR UPPER(c.TITLE_NAME) LIKE '%ASSISTANT%'
                OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
                OR UPPER(c.TITLE_NAME) LIKE '%JUNIOR%'
                OR UPPER(c.TITLE_NAME) LIKE '%INTERN%'
                OR UPPER(c.TITLE_NAME) LIKE '%TRAINEE%'
            )
            -- DO NOT flag founders/owners - they convert at 1.07%
            AND NOT (
                UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
                OR UPPER(c.TITLE_NAME) LIKE '%OWNER%'
                OR UPPER(c.TITLE_NAME) LIKE '%CEO%'
                OR UPPER(c.TITLE_NAME) LIKE '% PRESIDENT%'  -- Space before to avoid VP
            )
            THEN 1
            ELSE 0
        END as is_likely_recent_promotee
    FROM base b
    LEFT JOIN industry_tenure it ON b.lead_id = it.lead_id
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON b.advisor_crd = c.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- COMBINE ALL FEATURES (26 features for V4.3.1)
-- ============================================================================
all_features AS (
    SELECT
        -- Base columns
        b.lead_id,
        b.advisor_crd,
        b.contacted_date,
        b.converted,
        b.lead_source_grouped,
        
        -- ====================================================================
        -- V4.2.0 FEATURES (23 - ALL PRESERVED) - Matching train_v42_age_feature.py order
        -- ====================================================================
        -- Original V4 features (12)
        -- 1. tenure_months
        COALESCE(cf.tenure_months, 0) as tenure_months,
        
        -- 2. mobility_3yr
        COALESCE(m.mobility_3yr, 0) as mobility_3yr,
        
        -- 3. firm_rep_count_at_contact
        COALESCE(fs.firm_rep_count_at_contact, 0) as firm_rep_count_at_contact,
        
        -- 4. firm_net_change_12mo
        COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) as firm_net_change_12mo,
        
        -- 5. is_wirehouse
        COALESCE(w.is_wirehouse, 0) as is_wirehouse,
        
        -- 6. is_broker_protocol
        COALESCE(bp.is_broker_protocol, 0) as is_broker_protocol,
        
        -- 7. has_email
        COALESCE(dq.has_email, 0) as has_email,
        
        -- 8. has_linkedin
        COALESCE(dq.has_linkedin, 0) as has_linkedin,
        
        -- 9. has_firm_data
        COALESCE(dq.has_firm_data, 0) as has_firm_data,
        
        -- 10. mobility_x_heavy_bleeding
        CASE 
            WHEN COALESCE(m.mobility_3yr, 0) >= 2 
                AND (COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0)) < -10
            THEN 1 ELSE 0
        END as mobility_x_heavy_bleeding,
        
        -- 11. short_tenure_x_high_mobility
        CASE 
            WHEN COALESCE(cf.tenure_months, 9999) < 24 AND COALESCE(m.mobility_3yr, 0) >= 2
            THEN 1 ELSE 0
        END as short_tenure_x_high_mobility,
        
        -- 12. experience_years
        COALESCE(e.experience_years, 0) as experience_years,
        
        -- Encoded categoricals (3)
        -- 13. tenure_bucket_encoded
        CASE 
            WHEN COALESCE(cf.tenure_months, 0) = 0 OR cf.tenure_months IS NULL THEN 5  -- Unknown
            WHEN cf.tenure_months < 12 THEN 0  -- 0-12
            WHEN cf.tenure_months < 24 THEN 1  -- 12-24
            WHEN cf.tenure_months < 48 THEN 2  -- 24-48
            WHEN cf.tenure_months < 120 THEN 3  -- 48-120
            ELSE 4  -- 120+
        END as tenure_bucket_encoded,
        
        -- 14. mobility_tier_encoded
        CASE 
            WHEN COALESCE(m.mobility_3yr, 0) = 0 THEN 0  -- Stable
            WHEN COALESCE(m.mobility_3yr, 0) = 1 THEN 1  -- Low_Mobility
            ELSE 2  -- High_Mobility
        END as mobility_tier_encoded,
        
        -- 15. firm_stability_tier_encoded
        CASE 
            WHEN cf.firm_crd IS NULL THEN 0  -- Unknown
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < -10 THEN 1  -- Heavy_Bleeding
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) < 0 THEN 2  -- Light_Bleeding
            WHEN COALESCE(fs.firm_arrivals_12mo, 0) - COALESCE(fs.firm_departures_12mo, 0) = 0 THEN 3  -- Stable
            ELSE 4  -- Growing
        END as firm_stability_tier_encoded,
        
        -- V4.1 Bleeding features (4)
        -- 16. is_recent_mover
        COALESCE(rm.is_recent_mover, 0) as is_recent_mover,
        
        -- 17. days_since_last_move
        COALESCE(rm.days_since_last_move, 9999) as days_since_last_move,
        
        -- 18. firm_departures_corrected
        COALESCE(bv.firm_departures_corrected, 0) as firm_departures_corrected,
        
        -- 19. bleeding_velocity_encoded
        COALESCE(bv.bleeding_velocity_encoded, 0) as bleeding_velocity_encoded,
        
        -- V4.1 Firm/Rep type features (3)
        -- 20. is_independent_ria
        COALESCE(frt.is_independent_ria, 0) as is_independent_ria,
        
        -- 21. is_ia_rep_type
        COALESCE(frt.is_ia_rep_type, 0) as is_ia_rep_type,
        
        -- 22. is_dual_registered
        COALESCE(frt.is_dual_registered, 0) as is_dual_registered,
        
        -- V4.2.0 NEW: Age feature (1)
        -- 23. age_bucket_encoded
        COALESCE(ad.age_bucket_encoded, 2) as age_bucket_encoded,
        
        -- ================================================================
        -- V4.3.0: CAREER CLOCK FEATURES (2 features)
        -- ================================================================
        COALESCE(ccf.cc_is_in_move_window, 0) as cc_is_in_move_window,
        COALESCE(ccf.cc_is_too_early, 0) as cc_is_too_early,
        
        -- ================================================================
        -- V4.3.1: RECENT PROMOTEE FEATURE (1 new feature)
        -- ================================================================
        -- Analysis (January 8, 2026) found advisors with <5yr tenure + mid/senior
        -- titles convert at 0.29-0.45% (6-9x worse than baseline).
        -- This feature lets the model learn the pattern and find exceptions.
        -- ================================================================
        COALESCE(rp.is_likely_recent_promotee, 0) as is_likely_recent_promotee
        
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
    LEFT JOIN age_data ad ON b.advisor_crd = ad.advisor_crd
    LEFT JOIN career_clock_features_training ccf 
        ON b.lead_id = ccf.lead_id
        AND b.contacted_date = ccf.contacted_date
    LEFT JOIN recent_promotee_feature rp ON b.lead_id = rp.lead_id
)

SELECT DISTINCT * FROM all_features;
