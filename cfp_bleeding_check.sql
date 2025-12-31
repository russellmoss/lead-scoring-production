-- ============================================================================
-- CFP ADVISOR ANALYSIS
-- ============================================================================
-- Purpose: Check if we have CFP advisors in the data and their firm status
-- ============================================================================

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
        advisor_crd,
        firm_net_change_12mo
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`
    WHERE lead_id IN (SELECT lead_id FROM `savvy-gtm-analytics.ml_features.v4_target_variable`)
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        CASE WHEN hl.REP_LICENSES LIKE '%CFP%' THEN 1 ELSE 0 END as has_cfp
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
)

-- ============================================================================
-- CHECK 1: Do we have CFP advisors in the data?
-- ============================================================================
SELECT 
    'CFP Distribution' as query_name,
    has_cfp,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
GROUP BY has_cfp
ORDER BY has_cfp DESC;

-- ============================================================================
-- CHECK 2: Do we have CFP + Bleeding combination?
-- ============================================================================
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
        advisor_crd,
        firm_net_change_12mo
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`
    WHERE lead_id IN (SELECT lead_id FROM `savvy-gtm-analytics.ml_features.v4_target_variable`)
),
analysis_base AS (
    SELECT 
        hl.*,
        lf.firm_net_change_12mo,
        CASE WHEN hl.REP_LICENSES LIKE '%CFP%' THEN 1 ELSE 0 END as has_cfp
    FROM historical_leads hl
    LEFT JOIN lead_features lf ON hl.advisor_crd = lf.advisor_crd
)
SELECT 
    'CFP + Firm Status' as query_name,
    has_cfp,
    CASE 
        WHEN firm_net_change_12mo <= -3 THEN 'Bleeding' 
        WHEN firm_net_change_12mo IS NULL THEN 'Unknown'
        ELSE 'Stable' 
    END as firm_status,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(AVG(converted) * 100, 2) as conv_rate_pct,
    ROUND(AVG(converted) / 0.0382, 2) as lift_vs_baseline
FROM analysis_base
WHERE has_cfp = 1
GROUP BY has_cfp, firm_status
ORDER BY has_cfp DESC, firm_status;

