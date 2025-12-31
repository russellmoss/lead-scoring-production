-- =============================================================================
-- V3.3.3 ULTIMATE MATRIX ANALYSIS
-- =============================================================================
-- 
-- PURPOSE:
-- Combined analysis merging two independent approaches:
-- 1. Our matrix effects exploration (credential stacking, tenure matrices)
-- 2. Gemini's portable book matrices (succession gap, platform friction, AUM sweet spot)
--
-- BASELINE CONVERSION RATE: 3.82%
-- VALIDATION CRITERIA: Lift >= 1.5x with sample >= 50
--
-- =============================================================================


-- =============================================================================
-- SECTION 1: SUCCESSION GAP MATRIX (Gemini's Top Insight)
-- =============================================================================
-- THEORY: Our T1G (Growth Stage) captures mid-career advisors at stable firms.
-- But we didn't check if the FIRM PRINCIPAL is aging (25+ years).
-- If so, the mid-career advisor is "Succession Blocked" - they can't buy out
-- the founder, so they're MORE motivated to leave.
--
-- THE COMBO: T1G criteria + Firm has aging principal (20+ years)
-- =============================================================================

-- 1.1: CHECK FIRM PRINCIPAL TENURE DATA AVAILABILITY
SELECT 
    '1.1 FIRM PRINCIPAL TENURE AVAILABILITY' as query_name,
    COUNTIF(FIRM_START_DATE IS NOT NULL) as has_firm_start,
    COUNT(*) as total_firms,
    ROUND(COUNTIF(FIRM_START_DATE IS NOT NULL) / COUNT(*) * 100, 2) as coverage_pct
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`;


-- 1.2: SUCCESSION GAP - T1G ENHANCED
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.CONTACT_BIO,
        c.TITLE_NAME
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.industry_tenure_months
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size,
        -- Calculate firm age as proxy for principal tenure
        DATE_DIFF(CURRENT_DATE(), PARSE_DATE('%Y-%m-%d', FIRM_START_DATE), MONTH) as firm_age_months
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.industry_tenure_months,
        fd.avg_account_size,
        fd.firm_age_months,
        -- T1G criteria (Growth Stage)
        CASE WHEN lf.industry_tenure_months BETWEEN 60 AND 180
                  AND fd.avg_account_size >= 250000
                  AND lf.firm_net_change_12mo > -3
             THEN 1 ELSE 0 END as is_t1g,
        -- Aging Firm flag (principal likely 20+ years)
        CASE WHEN fd.firm_age_months >= 240 THEN 1 ELSE 0 END as is_aging_firm,
        -- "Young" firm (potential growth firm)
        CASE WHEN fd.firm_age_months < 120 THEN 1 ELSE 0 END as is_young_firm
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '1.2 SUCCESSION GAP MATRIX' as query_name,
    CASE WHEN is_t1g = 1 THEN 'T1G (Growth Stage)' ELSE 'Not T1G' END as t1g_status,
    CASE 
        WHEN is_aging_firm = 1 THEN 'Aging Firm (20+ yr) - SUCCESSION BLOCKED'
        WHEN is_young_firm = 1 THEN 'Young Firm (<10yr)'
        ELSE 'Mid-Age Firm (10-20yr)'
    END as firm_age_status,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY t1g_status, firm_age_status
HAVING COUNT(*) >= 20
ORDER BY conv_rate_pct DESC;


-- 1.3: SUCCESSION GAP - DETAILED FIRM AGE BUCKETS
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.industry_tenure_months
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size,
        DATE_DIFF(CURRENT_DATE(), PARSE_DATE('%Y-%m-%d', FIRM_START_DATE), MONTH) as firm_age_months
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE FIRM_START_DATE IS NOT NULL
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.industry_tenure_months,
        fd.avg_account_size,
        fd.firm_age_months,
        -- T1G criteria
        CASE WHEN lf.industry_tenure_months BETWEEN 60 AND 180
                  AND fd.avg_account_size >= 250000
                  AND lf.firm_net_change_12mo > -3
             THEN 1 ELSE 0 END as is_t1g
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '1.3 T1G × FIRM AGE BUCKETS' as query_name,
    CASE 
        WHEN firm_age_months IS NULL THEN '0. Unknown'
        WHEN firm_age_months < 60 THEN '1. Startup (<5yr)'
        WHEN firm_age_months < 120 THEN '2. Young (5-10yr)'
        WHEN firm_age_months < 180 THEN '3. Established (10-15yr)'
        WHEN firm_age_months < 240 THEN '4. Mature (15-20yr)'
        WHEN firm_age_months < 300 THEN '5. Aging (20-25yr) ⭐'
        ELSE '6. Legacy (25+yr) ⭐'
    END as firm_age_bucket,
    CASE WHEN is_t1g = 1 THEN 'T1G' ELSE 'Non-T1G' END as t1g_status,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY firm_age_bucket, t1g_status
HAVING COUNT(*) >= 15
ORDER BY firm_age_bucket, t1g_status;


-- =============================================================================
-- SECTION 2: PLATFORM FRICTION MATRIX (Gemini's 2nd Insight)
-- =============================================================================
-- THEORY: We tested custodian alone (0.88x). But the TRIPLE COMBO of:
-- - Series 65 Only (no BD tie, pure RIA)
-- - Portable Custodian (Schwab/Fidelity)
-- - Small Firm (≤10 reps, no bureaucracy)
-- = "Zero Friction Move" - the easiest possible transition
--
-- THE COMBO: Series 65 Only + Portable Custodian + Small Firm
-- =============================================================================

-- 2.1: PLATFORM FRICTION TRIPLE COMBO
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.REP_LICENSES
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.firm_rep_count_at_contact
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        CUSTODIAN_PRIMARY_BUSINESS_NAME as custodian,
        -- Portable custodian flag
        CASE WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
             THEN 1 ELSE 0 END as has_portable_custodian
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.firm_rep_count_at_contact,
        fd.has_portable_custodian,
        -- Series 65 only (no BD)
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' 
             AND hl.REP_LICENSES NOT LIKE '%Series 7%' 
             THEN 1 ELSE 0 END as has_series_65_only,
        -- Small firm
        CASE WHEN lf.firm_rep_count_at_contact <= 10 THEN 1 ELSE 0 END as is_small_firm,
        -- Bleeding
        CASE WHEN lf.firm_net_change_12mo <= -3 THEN 1 ELSE 0 END as is_bleeding
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '2.1 PLATFORM FRICTION TRIPLE COMBO' as query_name,
    -- Count friction reducers
    (has_series_65_only + COALESCE(has_portable_custodian, 0) + is_small_firm) as friction_score,
    CASE 
        WHEN has_series_65_only = 1 AND has_portable_custodian = 1 AND is_small_firm = 1 
            THEN '⭐ ZERO FRICTION (All 3)'
        WHEN has_series_65_only = 1 AND has_portable_custodian = 1 
            THEN 'Low Friction (S65 + Custodian)'
        WHEN has_series_65_only = 1 AND is_small_firm = 1 
            THEN 'Low Friction (S65 + Small)'
        WHEN has_portable_custodian = 1 AND is_small_firm = 1 
            THEN 'Low Friction (Custodian + Small)'
        WHEN has_series_65_only = 1 THEN 'Series 65 Only'
        WHEN has_portable_custodian = 1 THEN 'Portable Custodian Only'
        WHEN is_small_firm = 1 THEN 'Small Firm Only'
        ELSE 'High Friction (None)'
    END as friction_combo,
    is_bleeding,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY friction_score, friction_combo, is_bleeding
HAVING COUNT(*) >= 15
ORDER BY friction_score DESC, conv_rate_pct DESC;


-- 2.2: PLATFORM FRICTION BY SPECIFIC CUSTODIAN
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.REP_LICENSES
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        CASE 
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                 OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%' THEN 'Schwab'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%' THEN 'Fidelity'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%' THEN 'Pershing'
            WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%TD AMER%' THEN 'TD Ameritrade'
            WHEN CUSTODIAN_PRIMARY_BUSINESS_NAME IS NULL THEN 'Unknown'
            ELSE 'Other'
        END as custodian_name
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),
analysis_base AS (
    SELECT 
        hl.*,
        fd.custodian_name,
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' 
             AND hl.REP_LICENSES NOT LIKE '%Series 7%' 
             THEN 1 ELSE 0 END as has_series_65_only
    FROM historical_leads hl
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '2.2 SERIES 65 × SPECIFIC CUSTODIAN' as query_name,
    custodian_name,
    CASE WHEN has_series_65_only = 1 THEN 'Series 65 Only' ELSE 'Has Series 7' END as license_type,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY custodian_name, license_type
HAVING COUNT(*) >= 20
ORDER BY conv_rate_pct DESC;


-- =============================================================================
-- SECTION 3: AUM SWEET SPOT MATRIX (Gemini's 3rd Insight)
-- =============================================================================
-- THEORY: We found UHNW ($5M+) converts WORST (0.54x).
-- But we used binary splits ($250K+, $500K+).
-- Gemini suggests the SWEET SPOT is $500K-$2M specifically:
-- - Big enough for advisor loyalty (not brand loyalty)
-- - Small enough to avoid institutional lock-in
--
-- THE COMBO: Refine AUM buckets to find optimal range
-- =============================================================================

-- 3.1: REFINED AUM SWEET SPOT
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.industry_tenure_months
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.industry_tenure_months,
        fd.avg_account_size,
        -- T1G criteria check
        CASE WHEN lf.industry_tenure_months BETWEEN 60 AND 180
                  AND lf.firm_net_change_12mo > -3
             THEN 1 ELSE 0 END as is_growth_stage_base
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '3.1 AUM SWEET SPOT (Refined Buckets)' as query_name,
    CASE 
        WHEN avg_account_size IS NULL THEN '0. Unknown'
        WHEN avg_account_size < 100000 THEN '1. Retail (<$100K)'
        WHEN avg_account_size < 250000 THEN '2. Mass Affluent ($100-250K)'
        WHEN avg_account_size < 500000 THEN '3. Affluent ($250-500K)'
        WHEN avg_account_size < 1000000 THEN '4. Lower HNW ($500K-1M) ⭐'
        WHEN avg_account_size < 2000000 THEN '5. Upper HNW ($1-2M) ⭐'
        WHEN avg_account_size < 5000000 THEN '6. VHNW ($2-5M)'
        ELSE '7. Ultra-HNW ($5M+)'
    END as aum_bucket,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY aum_bucket
HAVING COUNT(*) >= 20
ORDER BY aum_bucket;


-- 3.2: SWEET SPOT × GROWTH STAGE INTERACTION
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.industry_tenure_months
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.industry_tenure_months,
        fd.avg_account_size,
        -- Is in AUM Sweet Spot ($500K-$2M)?
        CASE WHEN fd.avg_account_size BETWEEN 500000 AND 2000000 THEN 1 ELSE 0 END as is_aum_sweet_spot,
        -- Is Growth Stage (tenure + stable)?
        CASE WHEN lf.industry_tenure_months BETWEEN 60 AND 180
                  AND lf.firm_net_change_12mo > -3
             THEN 1 ELSE 0 END as is_growth_stage_base
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
)
SELECT 
    '3.2 AUM SWEET SPOT × GROWTH STAGE' as query_name,
    CASE 
        WHEN is_aum_sweet_spot = 1 AND is_growth_stage_base = 1 
            THEN '⭐ Sweet Spot + Growth Stage (OPTIMAL)'
        WHEN is_aum_sweet_spot = 1 THEN 'Sweet Spot Only ($500K-$2M)'
        WHEN is_growth_stage_base = 1 THEN 'Growth Stage Only (Mid-career + Stable)'
        ELSE 'Neither'
    END as segment,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY segment
HAVING COUNT(*) >= 20
ORDER BY conv_rate_pct DESC;


-- =============================================================================
-- SECTION 4: CREDENTIAL STACKING (Our Original Idea)
-- =============================================================================
-- THEORY: Do advisors with MULTIPLE credentials convert better?
-- We know CFP + Bleeding = 9.80% (2.57x). What about CFP + CFA?
-- =============================================================================

-- 4.1: CREDENTIAL COMBINATIONS × BLEEDING
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.CONTACT_BIO,
        c.TITLE_NAME,
        c.REP_LICENSES
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        -- CFP
        CASE WHEN hl.CONTACT_BIO LIKE '%CFP%' 
             OR hl.CONTACT_BIO LIKE '%Certified Financial Planner%'
             OR hl.TITLE_NAME LIKE '%CFP%'
             THEN 1 ELSE 0 END as has_cfp,
        -- CFA
        CASE WHEN hl.CONTACT_BIO LIKE '%CFA%' 
             OR hl.CONTACT_BIO LIKE '%Chartered Financial Analyst%'
             OR hl.TITLE_NAME LIKE '%CFA%'
             THEN 1 ELSE 0 END as has_cfa,
        -- Series 65 only
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' 
             AND hl.REP_LICENSES NOT LIKE '%Series 7%' 
             THEN 1 ELSE 0 END as has_series_65_only,
        -- Bleeding
        CASE WHEN lf.firm_net_change_12mo <= -3 THEN 1 ELSE 0 END as is_bleeding
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
)
SELECT 
    '4.1 CREDENTIAL STACKING × BLEEDING' as query_name,
    -- Count credentials
    (has_cfp + has_cfa + has_series_65_only) as credential_count,
    CASE 
        WHEN has_cfp = 1 AND has_cfa = 1 THEN 'CFP + CFA (Double)'
        WHEN has_cfp = 1 AND has_series_65_only = 1 THEN 'CFP + Series 65 Only'
        WHEN has_cfp = 1 THEN 'CFP Only'
        WHEN has_cfa = 1 THEN 'CFA Only'
        WHEN has_series_65_only = 1 THEN 'Series 65 Only'
        ELSE 'No Major Credentials'
    END as credential_combo,
    CASE WHEN is_bleeding = 1 THEN 'Bleeding' ELSE 'Stable' END as firm_status,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY credential_count, credential_combo, firm_status
HAVING COUNT(*) >= 10
ORDER BY conv_rate_pct DESC;


-- =============================================================================
-- SECTION 5: CURRENT FIRM TENURE (Our Original Idea)
-- =============================================================================
-- THEORY: Do advisors with SHORT tenure at CURRENT firm convert better?
-- Hypothesis: Recently moved = still evaluating, more receptive
-- =============================================================================

-- 5.1: CURRENT FIRM TENURE × BLEEDING
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM_START_DATE
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        DATE_DIFF(CURRENT_DATE(), SAFE.PARSE_DATE('%Y-%m-%d', hl.PRIMARY_FIRM_START_DATE), MONTH) as months_at_firm,
        CASE WHEN lf.firm_net_change_12mo <= -3 THEN 1 ELSE 0 END as is_bleeding
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    WHERE hl.PRIMARY_FIRM_START_DATE IS NOT NULL
)
SELECT 
    '5.1 CURRENT FIRM TENURE × BLEEDING' as query_name,
    CASE 
        WHEN months_at_firm < 12 THEN '1. New (<1yr) - Still Evaluating'
        WHEN months_at_firm < 24 THEN '2. Recent (1-2yr)'
        WHEN months_at_firm < 48 THEN '3. Settled (2-4yr)'
        WHEN months_at_firm < 96 THEN '4. Established (4-8yr)'
        ELSE '5. Long-term (8+yr)'
    END as current_firm_tenure,
    CASE WHEN is_bleeding = 1 THEN 'Bleeding' ELSE 'Stable' END as firm_status,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY current_firm_tenure, firm_status
HAVING COUNT(*) >= 20
ORDER BY current_firm_tenure, firm_status;


-- =============================================================================
-- SECTION 6: EXPERIENCE × FIRM TENURE MATRIX (Full Heatmap)
-- =============================================================================
-- THEORY: Find the sweet spot combination of industry experience and
-- current firm tenure that predicts conversion.
-- =============================================================================

-- 6.1: FULL EXPERIENCE × FIRM TENURE MATRIX
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM_START_DATE
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.industry_tenure_months
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.industry_tenure_months,
        DATE_DIFF(CURRENT_DATE(), SAFE.PARSE_DATE('%Y-%m-%d', hl.PRIMARY_FIRM_START_DATE), MONTH) as months_at_firm
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    WHERE hl.PRIMARY_FIRM_START_DATE IS NOT NULL
      AND lf.industry_tenure_months IS NOT NULL
)
SELECT 
    '6.1 EXPERIENCE × FIRM TENURE MATRIX' as query_name,
    CASE 
        WHEN industry_tenure_months < 60 THEN 'Exp: Junior (<5yr)'
        WHEN industry_tenure_months < 120 THEN 'Exp: Mid-Early (5-10yr)'
        WHEN industry_tenure_months < 180 THEN 'Exp: Mid-Late (10-15yr)'
        ELSE 'Exp: Senior (15+yr)'
    END as experience_tier,
    CASE 
        WHEN months_at_firm < 24 THEN 'Firm: New (<2yr)'
        WHEN months_at_firm < 60 THEN 'Firm: Settled (2-5yr)'
        ELSE 'Firm: Established (5+yr)'
    END as firm_tenure_tier,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY experience_tier, firm_tenure_tier
HAVING COUNT(*) >= 30
ORDER BY conv_rate_pct DESC;


-- =============================================================================
-- SECTION 7: ULTIMATE COMBO - ALL FACTORS
-- =============================================================================
-- Combine the best signals into a composite score
-- =============================================================================

-- 7.1: MULTI-FACTOR PORTABILITY SCORE
WITH historical_leads AS (
    SELECT 
        tv.advisor_crd,
        tv.target as converted,
        c.PRIMARY_FIRM as firm_crd,
        c.CONTACT_BIO,
        c.TITLE_NAME,
        c.REP_LICENSES,
        c.PRIMARY_FIRM_START_DATE
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
),
lead_features AS (
    SELECT 
        f.advisor_crd,
        f.firm_net_change_12mo,
        f.industry_tenure_months,
        f.firm_rep_count_at_contact
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
),
firm_data AS (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size,
        DATE_DIFF(CURRENT_DATE(), PARSE_DATE('%Y-%m-%d', FIRM_START_DATE), MONTH) as firm_age_months,
        CASE WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
             THEN 1 ELSE 0 END as has_portable_custodian
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),
scored_leads AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        lf.industry_tenure_months,
        lf.firm_rep_count_at_contact,
        fd.avg_account_size,
        fd.firm_age_months,
        fd.has_portable_custodian,
        -- Individual signals
        CASE WHEN lf.industry_tenure_months BETWEEN 60 AND 180 THEN 1 ELSE 0 END as is_mid_career,
        CASE WHEN lf.firm_net_change_12mo > -3 THEN 1 ELSE 0 END as is_stable_firm,
        CASE WHEN fd.avg_account_size BETWEEN 500000 AND 2000000 THEN 1 ELSE 0 END as is_aum_sweet_spot,
        CASE WHEN fd.firm_age_months >= 240 THEN 1 ELSE 0 END as is_aging_firm,
        CASE WHEN lf.firm_rep_count_at_contact <= 10 THEN 1 ELSE 0 END as is_small_firm,
        CASE WHEN hl.REP_LICENSES LIKE '%Series 65%' 
             AND hl.REP_LICENSES NOT LIKE '%Series 7%' 
             THEN 1 ELSE 0 END as has_series_65_only,
        CASE WHEN hl.CONTACT_BIO LIKE '%CFP%' 
             OR hl.TITLE_NAME LIKE '%CFP%'
             THEN 1 ELSE 0 END as has_cfp
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
    LEFT JOIN firm_data fd ON hl.firm_crd = fd.firm_crd
),
final_scored AS (
    SELECT 
        *,
        -- Calculate composite portability score
        (
            is_mid_career +                              -- Growth stage: mid-career
            is_stable_firm +                             -- Stable firm (proactive mover)
            COALESCE(is_aum_sweet_spot, 0) +             -- AUM sweet spot ($500K-$2M)
            COALESCE(is_aging_firm, 0) +                 -- Succession blocked
            is_small_firm +                              -- Low bureaucracy
            has_series_65_only +                         -- Pure RIA, low regulatory friction
            COALESCE(has_portable_custodian, 0) +        -- Platform continuity
            has_cfp                                      -- Professional credential
        ) as portability_score
    FROM scored_leads
)
SELECT 
    '7.1 MULTI-FACTOR PORTABILITY SCORE' as query_name,
    CASE 
        WHEN portability_score >= 6 THEN '6+ Signals (ULTRA PORTABLE)'
        WHEN portability_score >= 5 THEN '5 Signals (HIGHLY PORTABLE)'
        WHEN portability_score >= 4 THEN '4 Signals (PORTABLE)'
        WHEN portability_score >= 3 THEN '3 Signals (MODERATE)'
        WHEN portability_score >= 2 THEN '2 Signals (LOW)'
        ELSE '0-1 Signals (VERY LOW)'
    END as portability_tier,
    portability_score,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM final_scored
GROUP BY portability_tier, portability_score
ORDER BY portability_score DESC;


-- =============================================================================
-- END OF V3.3.3 ULTIMATE MATRIX ANALYSIS
-- =============================================================================
--
-- SUMMARY OF TESTS:
-- 1. Succession Gap Matrix (T1G + Aging Firm)
-- 2. Platform Friction Triple (Series 65 + Custodian + Small Firm)
-- 3. AUM Sweet Spot ($500K-$2M refinement)
-- 4. Credential Stacking (CFP + CFA, CFP + Series 65)
-- 5. Current Firm Tenure (Recently moved = still evaluating)
-- 6. Experience × Firm Tenure Heatmap
-- 7. Multi-Factor Portability Score (Ultimate Combo)
--
-- INSTRUCTIONS FOR CURSOR.AI:
-- 1. Run all sections via MCP BigQuery
-- 2. Flag any segment with lift >= 1.5x AND sample >= 50
-- 3. Look for TRUE INTERACTION EFFECTS (A×B > A + B)
-- 4. Create summary report with top findings
--
-- =============================================================================
