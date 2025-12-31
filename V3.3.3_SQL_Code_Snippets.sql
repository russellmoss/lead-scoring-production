-- =============================================================================
-- V3.3.3 SQL CODE SNIPPETS: T1B_PRIME + T1G_ENHANCED
-- =============================================================================
-- 
-- PURPOSE: Ready-to-use SQL snippets for Cursor.ai implementation
-- VERSION: V3.3.3_01012026_ZERO_FRICTION_SWEET_SPOT
--
-- NEW TIERS:
-- - T1B_PRIME: Zero Friction Bleeder (13.64%, 3.57x lift)
-- - T1G_ENHANCED: Sweet Spot Growth Advisor (9.09%, 2.38x lift)
--
-- =============================================================================


-- =============================================================================
-- SNIPPET 1: FIRM_CUSTODIAN CTE
-- Add after firm_account_size CTE in phase_4_v3_tiered_scoring.sql
-- =============================================================================

-- V3.3.3: Portable custodian flag for T1B_PRIME tier
-- Identifies firms using Schwab, Fidelity, or Pershing as custodian
-- These custodians enable "zero friction" transitions via Negative Consent
-- Source: V3.3.3 Matrix Effects Validation (January 2026)
firm_custodian AS (
    SELECT 
        CRD_ID as firm_crd,
        CUSTODIAN_PRIMARY_BUSINESS_NAME as custodian_name,
        CASE WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' 
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%CHARLES%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%'
                  OR UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%'
             THEN 1 ELSE 0 
        END as has_portable_custodian
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
),


-- =============================================================================
-- SNIPPET 2: CREDENTIAL FLAGS
-- Add to leads_with_flags CTE if not already present
-- =============================================================================

-- CFP credential detection (from bio and title, NOT from licenses)
-- Note: CFP is a professional certification, not a securities license
CASE WHEN CONTACT_BIO LIKE '%CFP%' 
          OR CONTACT_BIO LIKE '%Certified Financial Planner%'
          OR TITLE_NAME LIKE '%CFP%'
     THEN 1 ELSE 0 
END as has_cfp,

-- Series 65 Only (no Series 7 = pure RIA, no BD ties)
CASE WHEN REP_LICENSES LIKE '%Series 65%' 
          AND REP_LICENSES NOT LIKE '%Series 7%' 
     THEN 1 ELSE 0 
END as has_series_65_only,


-- =============================================================================
-- SNIPPET 3: JOIN FIRM_CUSTODIAN
-- Add to leads_with_flags CTE joins
-- =============================================================================

LEFT JOIN firm_custodian fc ON lf.firm_crd = fc.firm_crd


-- =============================================================================
-- SNIPPET 4: SELECT has_portable_custodian
-- Add to leads_with_flags CTE SELECT
-- =============================================================================

COALESCE(fc.has_portable_custodian, 0) as has_portable_custodian,


-- =============================================================================
-- SNIPPET 5: UPDATED HEADER COMMENT
-- Replace existing header in phase_4_v3_tiered_scoring.sql
-- =============================================================================

-- =============================================================================
-- LEAD SCORING V3.3.3: ZERO FRICTION + SWEET SPOT TIERS
-- =============================================================================
-- Version: V3.3.3_01012026_ZERO_FRICTION_SWEET_SPOT
-- 
-- CHANGES FROM V3.3.2:
--   - ADDED: TIER_1B_PRIME_ZERO_FRICTION - Highest converting segment (13.64%)
--   - UPGRADED: TIER_1G → TIER_1G_ENHANCED_SWEET_SPOT (refined AUM $500K-$2M)
--   - ADDED: TIER_1G_GROWTH_STAGE for leads outside sweet spot
--   - ADDED: has_portable_custodian flag (Schwab/Fidelity/Pershing)
--
-- T1B_PRIME TIER DETAILS:
--   Target: "Zero Friction" movers - all transition barriers removed
--   
--   CRITERIA:
--   - Series 65 Only (no Series 7) - Pure RIA, no BD lock-in
--   - Portable Custodian (Schwab/Fidelity/Pershing) - Platform continuity
--   - Small Firm (≤10 reps) - No bureaucratic barriers
--   - Firm Bleeding (net_change ≤ -3) - Motivation to move
--   - NO CFP credential - CFP leads go to T1A instead
--
--   VALIDATION:
--   - Conversion: 13.64% (3.57x baseline)
--   - Sample: 22 leads
--   - Only 1 lead overlaps with T1A (has CFP)
--
-- T1G_ENHANCED TIER DETAILS:
--   Target: "Sweet Spot" growth advisors with optimal AUM
--   
--   CRITERIA:
--   - Mid-career (5-15 years industry tenure)
--   - AUM Sweet Spot ($500K-$2M avg account size)
--   - Stable firm (net_change > -3)
--
--   VALIDATION:
--   - Conversion: 9.09% (2.38x baseline)
--   - Sample: 66 leads
--   - 79% improvement over leads outside $500K-$2M range
--
-- KEY INSIGHT: Matrix Effects Are Real
--   Individual signals fail, but combinations create multiplicative lift:
--   - Custodian alone: 0.84x (negative)
--   - S65 + Custodian + Small + Bleeding: 3.57x (multiplicative!)
--
-- TIER PERFORMANCE SUMMARY (V3.3.3):
--   | Tier              | Conversion | Lift  | Definition                        |
--   |-------------------|------------|-------|-----------------------------------|
--   | T1B_PRIME         | 13.64%     | 3.57x | Zero Friction Bleeder             |
--   | T1A               | 10.00%     | 2.62x | CFP + Bleeding                    |
--   | T1G_ENHANCED      | 9.09%      | 2.38x | Growth Stage + $500K-$2M          |
--   | T1B               | 5.49%      | 1.44x | Series 65 + Bleeding              |
--   | T1G_REMAINDER     | 5.08%      | 1.33x | Growth Stage (outside sweet spot) |
-- =============================================================================


-- =============================================================================
-- SNIPPET 6: COMPLETE TIER PRIORITY LOGIC (V3.3.3)
-- Replace existing CASE statement in scored_prospects CTE
-- =============================================================================

CASE 
    -- ==========================================================================
    -- PRIORITY 1: T1B_PRIME - ZERO FRICTION BLEEDER (13.64%, 3.57x)
    -- ==========================================================================
    -- V3.3.3: NEW - Highest converting segment ever found!
    -- 
    -- THEORY: "Zero Friction" transitions - when ALL barriers are removed:
    -- - Series 65 Only = No BD lock-in (pure RIA)
    -- - Portable Custodian = Same platform at new firm (Negative Consent)
    -- - Small Firm = No bureaucratic exit barriers
    -- - Bleeding Firm = Motivation to leave
    --
    -- CRITICAL: Leads with CFP go to T1A instead (CFP has higher credential value)
    -- ==========================================================================
    WHEN has_series_65_only = 1                      -- Pure RIA (no BD)
         AND has_portable_custodian = 1              -- Schwab/Fidelity/Pershing
         AND firm_rep_count_at_contact <= 10         -- Small firm (no bureaucracy)
         AND firm_net_change_12mo <= -3              -- Bleeding firm (motivation)
         AND has_cfp = 0                             -- No CFP (CFP goes to T1A)
         AND is_wirehouse = 0                        -- Not at wirehouse
         AND is_excluded_title = 0                   -- Not excluded title
    THEN 'TIER_1B_PRIME_ZERO_FRICTION'
    
    -- ==========================================================================
    -- PRIORITY 2: T1A - CFP + BLEEDING (10.00%, 2.62x)
    -- ==========================================================================
    -- CFP certification at bleeding firm - strong credential + motivation
    -- ==========================================================================
    WHEN has_cfp = 1                                 -- CFP credential
         AND firm_net_change_12mo <= -3              -- Bleeding firm
         AND is_wirehouse = 0                        -- Not at wirehouse
         AND is_excluded_title = 0                   -- Not excluded title
    THEN 'TIER_1A_PRIME_MOVER_CFP'
    
    -- ==========================================================================
    -- PRIORITY 3: T1G_ENHANCED - SWEET SPOT GROWTH ADVISOR (9.09%, 2.38x)
    -- ==========================================================================
    -- V3.3.3: UPGRADED from T1G - Refined AUM range to $500K-$2M
    -- 
    -- THEORY: The "sweet spot" is $500K-$2M average account size:
    -- - Big enough for client loyalty (not brand loyalty)
    -- - Small enough to avoid institutional lock-in
    --
    -- Checked BEFORE T1B because 9.09% > 5.49%
    -- ==========================================================================
    WHEN industry_tenure_months BETWEEN 60 AND 180   -- Mid-career (5-15 years)
         AND avg_account_size BETWEEN 500000 AND 2000000  -- Sweet Spot ($500K-$2M)
         AND firm_net_change_12mo > -3               -- Stable firm (NOT bleeding)
         AND is_wirehouse = 0                        -- Not at wirehouse
         AND is_excluded_title = 0                   -- Not excluded title
    THEN 'TIER_1G_ENHANCED_SWEET_SPOT'
    
    -- ==========================================================================
    -- PRIORITY 4: T1B - SERIES 65 + BLEEDING (5.49%, 1.44x)
    -- ==========================================================================
    -- Series 65 Only at bleeding firm - remainder after T1B_PRIME
    -- ==========================================================================
    WHEN has_series_65_only = 1                      -- Series 65 Only
         AND firm_net_change_12mo <= -3              -- Bleeding firm
         AND is_wirehouse = 0                        -- Not at wirehouse
         AND is_excluded_title = 0                   -- Not excluded title
    THEN 'TIER_1B_PRIME_MOVER_SERIES65'
    
    -- ==========================================================================
    -- PRIORITY 5: T1G_REMAINDER - GROWTH STAGE OUTSIDE SWEET SPOT (5.08%, 1.33x)
    -- ==========================================================================
    -- V3.3.3: Growth Stage leads outside the $500K-$2M sweet spot
    -- ==========================================================================
    WHEN industry_tenure_months BETWEEN 60 AND 180   -- Mid-career (5-15 years)
         AND avg_account_size >= 250000              -- Original threshold
         AND (avg_account_size < 500000 OR avg_account_size > 2000000)  -- Outside sweet spot
         AND firm_net_change_12mo > -3               -- Stable firm
         AND is_wirehouse = 0                        -- Not at wirehouse
         AND is_excluded_title = 0                   -- Not excluded title
    THEN 'TIER_1G_GROWTH_STAGE'
    
    -- ==========================================================================
    -- PRIORITY 6+: OTHER TIERS (T1, T1F, T2, T3, etc.)
    -- ==========================================================================
    -- ... existing tier logic continues here ...
    
    ELSE 'STANDARD'
END as score_tier


-- =============================================================================
-- SNIPPET 7: EXPECTED CONVERSION RATES (V3.3.3)
-- =============================================================================

CASE 
    WHEN score_tier = 'TIER_1B_PRIME_ZERO_FRICTION' THEN 0.1364     -- 13.64%
    WHEN score_tier = 'TIER_1A_PRIME_MOVER_CFP' THEN 0.1000         -- 10.00%
    WHEN score_tier = 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 0.0909     -- 9.09%
    WHEN score_tier = 'TIER_1B_PRIME_MOVER_SERIES65' THEN 0.0549    -- 5.49%
    WHEN score_tier = 'TIER_1G_GROWTH_STAGE' THEN 0.0508            -- 5.08%
    -- ... other existing tiers ...
    ELSE 0.0382  -- Baseline
END as expected_conversion_rate


-- =============================================================================
-- SNIPPET 8: SCORE NARRATIVES (V3.3.3)
-- =============================================================================

WHEN score_tier = 'TIER_1B_PRIME_ZERO_FRICTION' THEN
    CONCAT(
        first_name, ' is a ZERO FRICTION BLEEDER: ',
        'Pure RIA (Series 65 only) at small firm (', CAST(firm_rep_count_at_contact AS STRING), ' reps) ',
        'using portable custodian. Firm is bleeding (', CAST(firm_net_change_12mo AS STRING), ' net change). ',
        'All transition barriers removed - highest conversion segment (13.64%).'
    )

WHEN score_tier = 'TIER_1G_ENHANCED_SWEET_SPOT' THEN
    CONCAT(
        first_name, ' is a SWEET SPOT GROWTH ADVISOR: ',
        'Mid-career (', CAST(ROUND(industry_tenure_months/12, 0) AS STRING), ' years) ',
        'with optimal client base ($', CAST(ROUND(avg_account_size/1000, 0) AS STRING), 'K avg account). ',
        'Firm is stable - proactive mover seeking platform upgrade (9.09% conversion).'
    )

WHEN score_tier = 'TIER_1G_GROWTH_STAGE' THEN
    CONCAT(
        first_name, ' is a GROWTH STAGE ADVISOR: ',
        'Mid-career (', CAST(ROUND(industry_tenure_months/12, 0) AS STRING), ' years) ',
        'with established practice at ', firm_name, '. ',
        'Firm is stable - strategic growth opportunity (5.08% conversion).'
    )


-- =============================================================================
-- VALIDATION QUERIES
-- Run these after implementation to verify correctness
-- =============================================================================

-- VALIDATION 1: Check T1B_PRIME tier exists and has correct count
SELECT 
    'VALIDATION 1: T1B_PRIME Exists' as check_name,
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_pct
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE score_tier = 'TIER_1B_PRIME_ZERO_FRICTION'
GROUP BY score_tier;
-- Expected: ~22 leads, 13.64% expected rate


-- VALIDATION 2: Check T1G_ENHANCED exists and has correct count
SELECT 
    'VALIDATION 2: T1G Tiers Split' as check_name,
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_pct
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE score_tier IN ('TIER_1G_ENHANCED_SWEET_SPOT', 'TIER_1G_GROWTH_STAGE')
GROUP BY score_tier
ORDER BY expected_conv_pct DESC;
-- Expected: T1G_ENHANCED ~66 leads at 9.09%, T1G_REMAINDER ~59 leads at 5.08%


-- VALIDATION 3: Check T1B_PRIME has NO CFP overlap
SELECT 
    'VALIDATION 3: T1B_PRIME No CFP' as check_name,
    COUNT(*) as t1b_prime_leads,
    COUNTIF(c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%') as has_cfp_count
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3` ls
JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON ls.advisor_crd = c.RIA_CONTACT_CRD_ID
WHERE ls.score_tier = 'TIER_1B_PRIME_ZERO_FRICTION';
-- Expected: has_cfp_count = 0 (all CFP leads should go to T1A)


-- VALIDATION 4: Check T1B_PRIME criteria are all met
SELECT 
    'VALIDATION 4: T1B_PRIME Criteria Check' as check_name,
    COUNT(*) as leads,
    COUNTIF(f.firm_rep_count_at_contact <= 10) as small_firm_count,
    COUNTIF(f.firm_net_change_12mo <= -3) as bleeding_count
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3` ls
JOIN `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
    ON ls.lead_id = f.lead_id
WHERE ls.score_tier = 'TIER_1B_PRIME_ZERO_FRICTION';
-- Expected: All counts should equal total leads


-- VALIDATION 5: Check T1G_ENHANCED AUM range is correct
SELECT 
    'VALIDATION 5: T1G_ENHANCED AUM Range' as check_name,
    COUNT(*) as leads,
    ROUND(MIN(fas.avg_account_size), 0) as min_avg_account,
    ROUND(MAX(fas.avg_account_size), 0) as max_avg_account,
    ROUND(AVG(fas.avg_account_size), 0) as avg_avg_account
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3` ls
JOIN `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
    ON ls.lead_id = f.lead_id
JOIN (
    SELECT CRD_ID as firm_crd, SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
) fas ON f.firm_crd = fas.firm_crd
WHERE ls.score_tier = 'TIER_1G_ENHANCED_SWEET_SPOT';
-- Expected: min >= 500,000 AND max <= 2,000,000


-- VALIDATION 6: Full Tier 1 distribution by conversion rate
SELECT 
    'VALIDATION 6: Full Tier Distribution' as check_name,
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_pct
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE score_tier LIKE 'TIER_1%'
GROUP BY score_tier
ORDER BY expected_conv_pct DESC;
-- Expected order: T1B_PRIME > T1A > T1G_ENHANCED > T1B > T1G_REMAINDER


-- VALIDATION 7: No duplicate tier assignments
SELECT 
    'VALIDATION 7: No Duplicate Tiers' as check_name,
    advisor_crd,
    COUNT(DISTINCT score_tier) as tier_count
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
GROUP BY advisor_crd
HAVING COUNT(DISTINCT score_tier) > 1;
-- Expected: 0 rows (each advisor has exactly 1 tier)


-- VALIDATION 8: Compare to original T1G (should be split)
SELECT 
    'VALIDATION 8: T1G Split Check' as check_name,
    CASE 
        WHEN score_tier = 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 'T1G_ENHANCED ($500K-$2M)'
        WHEN score_tier = 'TIER_1G_GROWTH_STAGE' THEN 'T1G_REMAINDER (outside)'
        ELSE 'Other'
    END as t1g_segment,
    COUNT(*) as leads,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_pct
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE score_tier LIKE 'TIER_1G%'
GROUP BY t1g_segment;
-- Expected: T1G_ENHANCED ~66 leads + T1G_REMAINDER ~59 leads = ~125 total


-- =============================================================================
-- DIAGNOSTIC QUERIES
-- Use these if validation fails
-- =============================================================================

-- DIAGNOSTIC 1: Check portable custodian distribution
SELECT 
    'DIAGNOSTIC: Custodian Distribution' as check_name,
    CASE 
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%SCHWAB%' THEN 'Schwab'
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%FIDELITY%' THEN 'Fidelity'
        WHEN UPPER(CUSTODIAN_PRIMARY_BUSINESS_NAME) LIKE '%PERSHING%' THEN 'Pershing'
        WHEN CUSTODIAN_PRIMARY_BUSINESS_NAME IS NULL THEN 'NULL'
        ELSE 'Other'
    END as custodian,
    COUNT(*) as firms
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
GROUP BY custodian
ORDER BY firms DESC;


-- DIAGNOSTIC 2: Check firm rep count distribution
SELECT 
    'DIAGNOSTIC: Firm Size Distribution' as check_name,
    CASE 
        WHEN firm_rep_count_at_contact <= 3 THEN 'Micro (1-3)'
        WHEN firm_rep_count_at_contact <= 10 THEN 'Small (4-10) ← T1B_PRIME target'
        WHEN firm_rep_count_at_contact <= 50 THEN 'Medium (11-50)'
        ELSE 'Large (50+)'
    END as firm_size,
    COUNT(*) as leads
FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`
GROUP BY firm_size
ORDER BY leads DESC;


-- DIAGNOSTIC 3: Check AUM sweet spot distribution
SELECT 
    'DIAGNOSTIC: AUM Distribution' as check_name,
    CASE 
        WHEN avg_account_size < 250000 THEN 'Below $250K'
        WHEN avg_account_size BETWEEN 250000 AND 500000 THEN '$250K-$500K'
        WHEN avg_account_size BETWEEN 500000 AND 2000000 THEN '$500K-$2M ← Sweet Spot'
        WHEN avg_account_size > 2000000 THEN '$2M+'
        ELSE 'Unknown'
    END as aum_bucket,
    COUNT(*) as firms
FROM (
    SELECT CRD_ID, SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
)
GROUP BY aum_bucket
ORDER BY firms DESC;


-- =============================================================================
-- MODEL REGISTRY UPDATE (JSON)
-- Add to v3/models/model_registry_v3.json
-- =============================================================================
/*
{
  "model_version": "V3.3.3_01012026_ZERO_FRICTION_SWEET_SPOT",
  "updated_date": "2026-01-01",
  "changes_from_v3.3.2": [
    "ADDED: TIER_1B_PRIME_ZERO_FRICTION - Zero Friction Bleeder (S65 + Custodian + Small + Bleeding)",
    "PERFORMANCE: 13.64% conversion (3.57x lift) - HIGHEST TIER EVER",
    "CRITERIA: Series 65 Only + Portable Custodian + Small Firm (≤10) + Bleeding + No CFP",
    "UPGRADED: TIER_1G → TIER_1G_ENHANCED_SWEET_SPOT (refined AUM $500K-$2M)",
    "PERFORMANCE: 9.09% conversion (2.38x lift) - 79% improvement over original",
    "ADDED: TIER_1G_GROWTH_STAGE for leads outside sweet spot (5.08% conversion)",
    "DISCOVERY: Matrix effects create multiplicative lift (A×B > A + B)",
    "KEY INSIGHT: Platform friction signals work as a SYSTEM, not individually",
    "ANALYSIS: V3.3.3 Ultimate Matrix Analysis + Pre-Implementation Validation"
  ],
  "tier_definitions": {
    "TIER_1B_PRIME_ZERO_FRICTION": {
      "description": "Zero Friction Bleeder - All transition barriers removed",
      "criteria": {
        "series_65_only": "true (no Series 7)",
        "has_portable_custodian": "Schwab, Fidelity, or Pershing",
        "firm_rep_count": "<= 10",
        "firm_net_change_12mo": "<= -3 (bleeding)",
        "has_cfp": "false (CFP leads go to T1A)"
      },
      "expected_conversion_rate": 0.1364,
      "expected_lift": 3.57,
      "sample_size_validated": 22,
      "added_version": "V3.3.3"
    },
    "TIER_1G_ENHANCED_SWEET_SPOT": {
      "description": "Growth Stage Advisor with optimal AUM sweet spot",
      "criteria": {
        "industry_tenure_months": "60-180 (5-15 years)",
        "avg_account_size": "500000-2000000 ($500K-$2M sweet spot)",
        "firm_net_change_12mo": "> -3 (stable, not bleeding)"
      },
      "expected_conversion_rate": 0.0909,
      "expected_lift": 2.38,
      "sample_size_validated": 66,
      "added_version": "V3.3.3",
      "replaces": "TIER_1G_GROWTH_STAGE_ADVISOR (V3.3.2)"
    },
    "TIER_1G_GROWTH_STAGE": {
      "description": "Growth Stage Advisor outside AUM sweet spot",
      "criteria": {
        "industry_tenure_months": "60-180 (5-15 years)",
        "avg_account_size": ">= 250000 but outside $500K-$2M range",
        "firm_net_change_12mo": "> -3 (stable)"
      },
      "expected_conversion_rate": 0.0508,
      "expected_lift": 1.33,
      "sample_size_validated": 59,
      "added_version": "V3.3.3"
    }
  }
}
*/
