-- =============================================================================
-- V3.3.1 PORTABLE BOOK EXCLUSIONS: SQL CODE SNIPPETS
-- =============================================================================
-- Purpose: Ready-to-use SQL snippets for Cursor.ai implementation
-- Version: V3.3.1_12312025_PORTABLE_BOOK_EXCLUSIONS
-- =============================================================================

-- =============================================================================
-- SNIPPET 1: FIRM_DISCRETIONARY CTE
-- Add this CTE after excluded_firms in phase_4_v3_tiered_scoring.sql
-- =============================================================================

-- V3.3.1: Firm discretionary ratio for portable book exclusion
-- Analysis: Low discretionary (<50%) converts at 0.34x baseline - EXCLUDE
-- High discretionary (>80%) converts at 0.92x baseline
-- Source: Portable Book Hypothesis Validation Analysis (December 2025)
firm_discretionary AS (
    SELECT 
        CRD_ID as firm_crd,
        TOTAL_AUM,
        DISCRETIONARY_AUM,
        SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) as discretionary_ratio,
        CASE 
            WHEN TOTAL_AUM IS NULL OR TOTAL_AUM = 0 THEN 'UNKNOWN'
            WHEN SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) < 0.50 THEN 'LOW_DISCRETIONARY'
            WHEN SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) >= 0.80 THEN 'HIGH_DISCRETIONARY'
            ELSE 'MODERATE_DISCRETIONARY'
        END as discretionary_tier
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),


-- =============================================================================
-- SNIPPET 2: UPDATED HEADER COMMENT
-- Replace existing header in phase_4_v3_tiered_scoring.sql
-- =============================================================================

-- =============================================================================
-- LEAD SCORING V3.3.1: PORTABLE BOOK SIGNAL EXCLUSIONS
-- =============================================================================
-- Version: V3.3.1_12312025_PORTABLE_BOOK_EXCLUSIONS
-- 
-- CHANGES FROM V3.2.4:
--   - ADDED: Low discretionary AUM exclusion (<50% discretionary = 0.34x baseline)
--   - ADDED: Large firm flag (>50 reps = 0.60x baseline, for V4 deprioritization)
--   - ADDED: is_low_discretionary flag to output
--   - VALIDATED: Servicer title exclusions confirmed (0.50x baseline)
--   - NOT ADDED: Solo practitioner tier (only 0.98x - not significant)
--   - NOT ADDED: Rainmaker title tier (actually 0.58x - WORSE than baseline!)
--
-- PORTABLE BOOK ANALYSIS RESULTS (December 2025):
--   Key Finding: These signals work as EXCLUSION criteria, not inclusion.
--   
--   | Signal                  | Conversion | Lift   | Action        |
--   |-------------------------|------------|--------|---------------|
--   | Low Discretionary <50%  | 1.32%      | 0.34x  | EXCLUDE       |
--   | Moderate Disc 50-80%    | 1.48%      | 0.39x  | MONITOR       |
--   | Large Firm >50 reps     | 2.31%      | 0.60x  | DEPRIORITIZE  |
--   | Servicer Titles         | 1.91%      | 0.50x  | EXCLUDE       |
--   | Rainmaker Titles        | 2.23%      | 0.58x  | DO NOT ADD    |
--   | Solo Practitioner       | 3.75%      | 0.98x  | NO ACTION     |
--
-- DISCRETIONARY AUM DISTRIBUTION (from FinTrx):
--   | Bucket              | Firms   | Avg AUM    |
--   |---------------------|---------|------------|
--   | 95%+ Discretionary  | 21,366  | $5.4B      |
--   | 80-95% Discretionary| 2,370   | $4.5B      |
--   | 50-80% Discretionary| 1,364   | $7.7B      |
--   | <50% Discretionary  | 1,159   | $7.4B      |
--   | 0% Discretionary    | 1,972   | $500M      |
--   | No AUM Data         | 17,002  | N/A        |
--
-- KEY INSIGHT: Low discretionary firms are NOT small firms - they're large
-- ($7.4B avg AUM) but have a fundamentally different business model
-- (transaction-based, not relationship-based).
--
-- EXPECTED IMPACT:
--   - Removes ~5,800 leads converting at 0.34x baseline
--   - Improves overall lead pool quality by ~7-10%
--   - No negative impact on high-performing tiers (validated <5% overlap)
--
-- PREVIOUS CHANGES (V3.2.4):
--   - CFP and Series 65 certification tiers (Tier 1A/1B) - 4.3x lift
--   - Data-driven title exclusion logic - removes 8.5% at 0% conversion
--   - TIER_1F_HV_WEALTH_BLEEDER - 3.35x lift
--   - PRODUCING_ADVISOR filter
--   - Insurance exclusions
-- =============================================================================


-- =============================================================================
-- SNIPPET 3: UPDATED leads_with_flags CTE
-- Modify existing CTE to include discretionary and large firm flags
-- =============================================================================

leads_with_flags AS (
    SELECT 
        lf.*,
        -- Existing wirehouse flag
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM excluded_firms ef 
                WHERE lf.company_upper LIKE ef.pattern
            ) THEN 1 ELSE 0 
        END as is_wirehouse,
        
        -- V3.3.1: Discretionary tier and flag
        COALESCE(fd.discretionary_tier, 'UNKNOWN') as discretionary_tier,
        COALESCE(fd.discretionary_ratio, -1) as discretionary_ratio,
        CASE 
            WHEN fd.discretionary_ratio < 0.50 AND fd.discretionary_ratio IS NOT NULL 
            THEN 1 ELSE 0 
        END as is_low_discretionary,
        
        -- V3.3.1: Large firm flag (for V4 deprioritization)
        CASE WHEN lf.firm_rep_count_at_contact > 50 THEN 1 ELSE 0 END as is_large_firm
        
    FROM lead_features lf
    LEFT JOIN firm_discretionary fd ON lf.firm_crd = fd.firm_crd
),


-- =============================================================================
-- SNIPPET 4: WHERE CLAUSE ADDITION
-- Add to final WHERE clause to exclude low discretionary leads
-- =============================================================================

-- Add this condition to your existing WHERE clause:
AND (
    -- V3.3.1: Exclude low discretionary firms (0.34x baseline)
    -- Allow NULL/Unknown - don't penalize missing data
    fd.discretionary_ratio >= 0.50 
    OR fd.discretionary_ratio IS NULL
    OR fd.TOTAL_AUM IS NULL 
    OR fd.TOTAL_AUM = 0
)


-- =============================================================================
-- SNIPPET 5: LEAD LIST GENERATION UPDATE
-- For January_2026_Lead_List_V3_V4_Hybrid.sql
-- =============================================================================

-- Add to the base_prospects or similar CTE:
LEFT JOIN (
    SELECT 
        CRD_ID as firm_crd,
        SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) as discretionary_ratio,
        CASE 
            WHEN TOTAL_AUM IS NULL OR TOTAL_AUM = 0 THEN 'UNKNOWN'
            WHEN SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) < 0.50 THEN 'LOW_DISCRETIONARY'
            WHEN SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) >= 0.80 THEN 'HIGH_DISCRETIONARY'
            ELSE 'MODERATE_DISCRETIONARY'
        END as discretionary_tier
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
) fd ON bp.firm_crd = fd.firm_crd

-- Add to WHERE clause:
WHERE 
    -- ... existing conditions ...
    AND (fd.discretionary_ratio >= 0.50 OR fd.discretionary_ratio IS NULL)


-- =============================================================================
-- SNIPPET 6: V4 FEATURES UPDATE
-- For v4_prospect_features.sql - add is_large_firm feature
-- =============================================================================

-- Add to the feature calculation:
-- V3.3.1: Large firm flag for deprioritization (>50 reps = 0.60x baseline)
CASE WHEN bp.firm_rep_count_at_contact > 50 THEN 1 ELSE 0 END as is_large_firm,


-- =============================================================================
-- SNIPPET 7: OUTPUT COLUMNS (Add to final SELECT)
-- Include new flags in output for monitoring
-- =============================================================================

-- Add to final SELECT statement:
discretionary_tier,
is_low_discretionary,
is_large_firm,


-- =============================================================================
-- VALIDATION QUERIES
-- Run these after implementation to verify correctness
-- =============================================================================

-- VALIDATION 1: Check exclusion impact on historical leads
SELECT 
    CASE 
        WHEN SAFE_DIVIDE(f.DISCRETIONARY_AUM, f.TOTAL_AUM) < 0.50 
        THEN 'EXCLUDED (Low Disc <50%)'
        WHEN f.TOTAL_AUM IS NULL OR f.TOTAL_AUM = 0 
        THEN 'INCLUDED (No AUM Data)'
        ELSE 'INCLUDED (High Disc >=50%)'
    END as status,
    COUNT(*) as leads,
    SUM(CASE WHEN tv.target = 1 THEN 1 ELSE 0 END) as conversions,
    ROUND(AVG(CASE WHEN tv.target = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) as conv_rate_pct,
    ROUND(AVG(CASE WHEN tv.target = 1 THEN 1.0 ELSE 0.0 END) / 0.0382, 2) as lift_vs_baseline
FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
    ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current` f 
    ON c.PRIMARY_FIRM = f.CRD_ID
GROUP BY 1
ORDER BY conv_rate_pct DESC;


-- VALIDATION 2: Check tier overlap with exclusion
SELECT 
    ls.score_tier,
    COUNT(*) as total_leads,
    COUNTIF(SAFE_DIVIDE(f.DISCRETIONARY_AUM, f.TOTAL_AUM) < 0.50) as would_exclude,
    ROUND(COUNTIF(SAFE_DIVIDE(f.DISCRETIONARY_AUM, f.TOTAL_AUM) < 0.50) / COUNT(*) * 100, 2) as exclude_pct
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3` ls
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
    ON ls.advisor_crd = c.RIA_CONTACT_CRD_ID
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current` f 
    ON c.PRIMARY_FIRM = f.CRD_ID
GROUP BY 1
HAVING COUNT(*) >= 10
ORDER BY exclude_pct DESC;


-- VALIDATION 3: Check large firm impact
SELECT 
    CASE 
        WHEN firm_rep_count_at_contact > 50 THEN 'Large Firm (>50 reps)'
        WHEN firm_rep_count_at_contact > 10 THEN 'Medium Firm (11-50 reps)'
        ELSE 'Small Firm (<=10 reps)'
    END as firm_size,
    COUNT(*) as leads,
    SUM(CASE WHEN target = 1 THEN 1 ELSE 0 END) as conversions,
    ROUND(AVG(CASE WHEN target = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) as conv_rate_pct
FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
JOIN `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f 
    ON tv.lead_id = f.lead_id
GROUP BY 1
ORDER BY conv_rate_pct DESC;


-- VALIDATION 4: Verify no data loss in joins
SELECT 
    'Total Leads' as check_type,
    COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.v4_target_variable`

UNION ALL

SELECT 
    'Leads with Firm Match' as check_type,
    COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
    ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current` f 
    ON c.PRIMARY_FIRM = f.CRD_ID

UNION ALL

SELECT 
    'Leads with Discretionary Data' as check_type,
    COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
    ON tv.advisor_crd = c.RIA_CONTACT_CRD_ID
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current` f 
    ON c.PRIMARY_FIRM = f.CRD_ID
WHERE f.TOTAL_AUM > 0 AND f.DISCRETIONARY_AUM IS NOT NULL;
