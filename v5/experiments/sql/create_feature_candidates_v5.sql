-- ============================================================================
-- FEATURE CANDIDATES TABLE FOR V5 ENHANCEMENT TESTING
-- ============================================================================
-- Purpose: Create isolated feature test table without touching production
-- Base: v4_prospect_features (V4.1 production features)
-- Output: ml_experiments.feature_candidates_v5
-- Created: 2025-12-30
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_experiments.feature_candidates_v5` AS

WITH base_features AS (
    -- Pull existing V4.1 features from production table (deduplicated - one row per advisor)
    SELECT 
        crd as advisor_crd,
        firm_crd,
        CURRENT_DATE() as prediction_date,
        -- Include existing V4.1 features for baseline comparison
        tenure_months,
        experience_years,
        mobility_3yr,
        firm_rep_count_at_contact,
        firm_net_change_12mo,
        is_wirehouse,
        is_broker_protocol,
        has_email,
        has_linkedin,
        has_firm_data,
        mobility_x_heavy_bleeding,
        short_tenure_x_high_mobility,
        tenure_bucket,
        mobility_tier,
        firm_stability_tier,
        is_recent_mover,
        days_since_last_move,
        firm_departures_corrected,
        bleeding_velocity_encoded,
        is_independent_ria,
        is_ia_rep_type,
        is_dual_registered
    FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY crd ORDER BY prediction_date DESC, created_at DESC) = 1
),

-- ============================================================================
-- CANDIDATE FEATURE 1: Firm AUM (Hypothesis: Higher AUM = more portable book)
-- ============================================================================
firm_aum_features AS (
    SELECT 
        bf.advisor_crd,
        bf.prediction_date,
        
        -- Raw firm AUM (PIT-safe: use prior month)
        fh.TOTAL_AUM as firm_aum_pit,
        
        -- Log-transformed (handles skew)
        LOG(GREATEST(COALESCE(fh.TOTAL_AUM, 1), 1)) as log_firm_aum,
        
        -- AUM per rep (efficiency metric)
        SAFE_DIVIDE(fh.TOTAL_AUM, bf.firm_rep_count_at_contact) as aum_per_rep,
        
        -- AUM bucket (categorical)
        CASE 
            WHEN fh.TOTAL_AUM IS NULL THEN 'Unknown'
            WHEN fh.TOTAL_AUM < 100000000 THEN 'Small (<$100M)'
            WHEN fh.TOTAL_AUM < 500000000 THEN 'Mid ($100M-$500M)'
            WHEN fh.TOTAL_AUM < 1000000000 THEN 'Large ($500M-$1B)'
            ELSE 'Very Large (>$1B)'
        END as firm_aum_bucket
        
    FROM base_features bf
    LEFT JOIN (
        SELECT 
            RIA_INVESTOR_CRD_ID,
            YEAR,
            MONTH,
            TOTAL_AUM
        FROM `savvy-gtm-analytics.FinTrx_data_CA.Firm_historicals`
        QUALIFY ROW_NUMBER() OVER (PARTITION BY RIA_INVESTOR_CRD_ID, YEAR, MONTH ORDER BY TOTAL_AUM DESC) = 1
    ) fh
        ON bf.firm_crd = fh.RIA_INVESTOR_CRD_ID
        AND fh.YEAR = EXTRACT(YEAR FROM DATE_SUB(bf.prediction_date, INTERVAL 1 MONTH))
        AND fh.MONTH = EXTRACT(MONTH FROM DATE_SUB(bf.prediction_date, INTERVAL 1 MONTH))  -- PIT: use prior month
),

-- ============================================================================
-- CANDIDATE FEATURE 2: Accolades (Hypothesis: Recognized advisors = quality)
-- ============================================================================
accolade_features AS (
    SELECT 
        bf.advisor_crd,
        
        -- Binary: has any accolade
        CASE WHEN COUNT(cah.RIA_CONTACT_CRD_ID) > 0 THEN 1 ELSE 0 END as has_accolade,
        
        -- Count of accolades
        COUNT(cah.RIA_CONTACT_CRD_ID) as accolade_count,
        
        -- Most recent accolade year
        MAX(cah.YEAR) as most_recent_accolade_year,
        
        -- Prestige score (Forbes=3, Barron's=2, Other=1)
        MAX(CASE 
            WHEN cah.OUTLET LIKE '%Forbes%' THEN 3
            WHEN cah.OUTLET LIKE '%Barron%' THEN 2
            ELSE 1
        END) as max_accolade_prestige
        
    FROM base_features bf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_accolades_historicals` cah
        ON bf.advisor_crd = cah.RIA_CONTACT_CRD_ID
        AND cah.YEAR <= EXTRACT(YEAR FROM bf.prediction_date)  -- PIT-safe
    GROUP BY bf.advisor_crd
),

-- ============================================================================
-- CANDIDATE FEATURE 3: Custodian (Hypothesis: Tech stack signals fit)
-- ============================================================================
custodian_features AS (
    SELECT 
        bf.advisor_crd,
        
        -- Primary custodian flags
        CASE WHEN ch.PRIMARY_BUSINESS_NAME LIKE '%Schwab%' THEN 1 ELSE 0 END as uses_schwab,
        CASE WHEN ch.PRIMARY_BUSINESS_NAME LIKE '%Fidelity%' THEN 1 ELSE 0 END as uses_fidelity,
        CASE WHEN ch.PRIMARY_BUSINESS_NAME LIKE '%Pershing%' THEN 1 ELSE 0 END as uses_pershing,
        
        -- Custodian modernity tier
        CASE 
            WHEN ch.PRIMARY_BUSINESS_NAME LIKE '%Schwab%' OR ch.PRIMARY_BUSINESS_NAME LIKE '%Fidelity%' THEN 'Modern'
            WHEN ch.PRIMARY_BUSINESS_NAME IS NOT NULL THEN 'Traditional'
            ELSE 'Unknown'
        END as custodian_tier
        
    FROM base_features bf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.custodians_historicals` ch
        ON bf.firm_crd = ch.RIA_INVESTOR_CRD_ID
        AND ch.period <= FORMAT_DATE('%Y-%m', bf.prediction_date)  -- PIT-safe
        AND ch.CURRENT_DATA = TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY bf.advisor_crd ORDER BY ch.period DESC) = 1
),

-- ============================================================================
-- CANDIDATE FEATURE 4: License Sophistication
-- ============================================================================
license_features AS (
    SELECT 
        bf.advisor_crd,
        
        -- License count (count commas + 1)
        CASE 
            WHEN rc.REP_LICENSES IS NULL OR rc.REP_LICENSES = '' THEN 0
            ELSE LENGTH(rc.REP_LICENSES) - LENGTH(REPLACE(rc.REP_LICENSES, ',', '')) + 1
        END as num_licenses,
        
        -- Specific licenses (using LIKE pattern matching)
        CASE WHEN rc.REP_LICENSES LIKE '%Series 66%' THEN 1 ELSE 0 END as has_series_66,
        CASE WHEN rc.REP_LICENSES LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_7,
        CASE WHEN rc.REP_LICENSES LIKE '%Series 63%' THEN 1 ELSE 0 END as has_series_63,
        
        -- Sophistication score (license count + CFP bonus)
        CASE 
            WHEN rc.REP_LICENSES IS NULL OR rc.REP_LICENSES = '' THEN 0
            ELSE LENGTH(rc.REP_LICENSES) - LENGTH(REPLACE(rc.REP_LICENSES, ',', '')) + 1
        END + 
        CASE WHEN rc.REP_LICENSES LIKE '%CFP%' OR rc.REP_LICENSES LIKE '%Certified Financial Planner%' THEN 2 ELSE 0 END as license_sophistication_score
        
    FROM base_features bf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON bf.advisor_crd = rc.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- CANDIDATE FEATURE 5: Disclosures (Disqualifier - negative signal)
-- ============================================================================
disclosure_features AS (
    SELECT 
        bf.advisor_crd,
        
        -- Binary: has any disclosure
        CASE WHEN COUNT(hd.CONTACT_CRD_ID) > 0 THEN 1 ELSE 0 END as has_disclosure,
        
        -- Count of disclosures
        COUNT(hd.CONTACT_CRD_ID) as disclosure_count
        
    FROM base_features bf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.Historical_Disclosure_data` hd
        ON bf.advisor_crd = hd.CONTACT_CRD_ID
    GROUP BY bf.advisor_crd
)

-- Final join with deduplication
SELECT DISTINCT
    bf.*,
    -- AUM features
    aum.firm_aum_pit,
    aum.log_firm_aum,
    aum.aum_per_rep,
    aum.firm_aum_bucket,
    -- Accolade features
    acc.has_accolade,
    acc.accolade_count,
    acc.most_recent_accolade_year,
    acc.max_accolade_prestige,
    -- Custodian features
    cust.uses_schwab,
    cust.uses_fidelity,
    cust.uses_pershing,
    cust.custodian_tier,
    -- License features
    lic.num_licenses,
    lic.has_series_66,
    lic.has_series_7,
    lic.has_series_63,
    lic.license_sophistication_score,
    -- Disclosure features
    disc.has_disclosure,
    disc.disclosure_count
FROM base_features bf
LEFT JOIN firm_aum_features aum ON bf.advisor_crd = aum.advisor_crd
LEFT JOIN accolade_features acc ON bf.advisor_crd = acc.advisor_crd
LEFT JOIN custodian_features cust ON bf.advisor_crd = cust.advisor_crd
LEFT JOIN license_features lic ON bf.advisor_crd = lic.advisor_crd
LEFT JOIN disclosure_features disc ON bf.advisor_crd = disc.advisor_crd;

