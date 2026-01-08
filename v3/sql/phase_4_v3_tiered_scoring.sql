
-- =============================================================================
-- LEAD SCORING V3.6.0: CAREER CLOCK TIERS + ZERO FRICTION + SWEET SPOT TIERS
-- =============================================================================
-- Version: V3.6.0_01082026_CAREER_CLOCK_TIERS
-- 
-- CHANGES FROM V3.3.2:
--   - ADDED: TIER_1B_PRIME_ZERO_FRICTION - Highest converting segment (13.64%, 3.57x lift)
--   - CRITERIA: Series 65 Only + Portable Custodian (Schwab/Fidelity/Pershing) + Small Firm (≤10) + Bleeding + No CFP
--   - UPGRADED: TIER_1G → TIER_1G_ENHANCED_SWEET_SPOT (refined AUM $500K-$2M)
--   - PERFORMANCE: 9.09% conversion (2.38x lift) - 79% improvement over original T1G
--   - ADDED: TIER_1G_GROWTH_STAGE for leads outside sweet spot (5.08% conversion)
--   - ADDED: has_portable_custodian flag (Schwab/Fidelity/Pershing)
--   - DISCOVERY: Matrix effects create multiplicative lift (A×B > A + B)
--   - KEY INSIGHT: Platform friction signals work as a SYSTEM, not individually
--   - ANALYSIS: V3.3.3 Ultimate Matrix Analysis + Pre-Implementation Validation (January 2026)
--
-- TIER PERFORMANCE SUMMARY (V3.3.3):
--   | Tier              | Conversion | Lift  | Definition                        |
--   |-------------------|------------|-------|-----------------------------------|
--   | T1B_PRIME         | 13.64%     | 3.57x | Zero Friction Bleeder             |
--   | T1A               | 10.00%     | 2.62x | CFP + Bleeding                    |
--   | T1G_ENHANCED      | 9.09%      | 2.38x | Growth Stage + $500K-$2M          |
--   | T1B               | 5.49%      | 1.44x | Series 65 + Bleeding              |
--   | T1G_REMAINDER     | 5.08%      | 1.33x | Growth Stage (outside sweet spot) |
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

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.lead_scores_v3_6` AS

WITH 
-- Wirehouse and insurance exclusion patterns
excluded_firms AS (
    SELECT pattern FROM UNNEST([
        '%MERRILL%', '%MORGAN STANLEY%', '%UBS%', '%WELLS FARGO%',
        '%EDWARD JONES%', '%RAYMOND JAMES%', '%LPL FINANCIAL%',
        '%NORTHWESTERN MUTUAL%', '%MASS MUTUAL%', '%MASSMUTUAL%',
        '%NEW YORK LIFE%', '%NYLIFE%', '%PRUDENTIAL%', '%PRINCIPAL%',
        '%LINCOLN FINANCIAL%', '%TRANSAMERICA%', '%ALLSTATE%',
        '%STATE FARM%', '%FARM BUREAU%', '%BANK OF AMERICA%',
        '%JP MORGAN%', '%JPMORGAN%', '%AMERIPRISE%', '%FIDELITY%',
        '%SCHWAB%', '%CHARLES SCHWAB%', '%VANGUARD%',
        '%FISHER INVESTMENTS%', '%CREATIVE PLANNING%', '%EDELMAN%',
        '%FIRST COMMAND%', '%T. ROWE PRICE%',
        -- V3.2.4: Insurance firm exclusions
        '%INSURANCE%'
    ]) AS pattern
),

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

-- V3.3.2: Firm average account size for T1G Growth Stage tier
-- Calculated as TOTAL_AUM / TOTAL_ACCOUNTS
-- Used to identify "established practice" advisors ($250K+ avg)
-- Source: V3.3.2 Growth Stage Hypothesis Validation (December 2025)
firm_account_size AS (
    SELECT 
        CRD_ID as firm_crd,
        TOTAL_AUM,
        TOTAL_ACCOUNTS,
        SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) as avg_account_size,
        CASE 
            WHEN SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) >= 250000 THEN 'ESTABLISHED'
            WHEN SAFE_DIVIDE(TOTAL_AUM, TOTAL_ACCOUNTS) IS NULL THEN 'UNKNOWN'
            ELSE 'GROWTH_STAGE'
        END as practice_maturity
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
    WHERE TOTAL_AUM > 0 AND TOTAL_ACCOUNTS > 0
),

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

-- Base lead data with features
lead_features AS (
    SELECT 
        l.Id as lead_id,
        l.FirstName, l.LastName, l.Email, l.Phone,
        l.Company, l.Title, l.Status, l.LeadSource,
        l.FA_CRD__c as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        f.current_firm_tenure_months,
        f.industry_tenure_months,
        f.firm_rep_count_at_contact,
        f.firm_net_change_12mo,
        f.num_prior_firms,
        f.pit_moves_3yr,
        f.target as converted,
        
        -- Career Clock Features (V3.4.0)
        f.cc_is_in_move_window,
        f.cc_is_too_early,
        f.cc_career_pattern,
        f.cc_cycle_status,
        f.cc_months_until_window,
        
        -- Derived flags
        UPPER(l.Company) as company_upper
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    INNER JOIN `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
        ON l.Id = f.lead_id
    WHERE l.stage_entered_contacting__c IS NOT NULL
        AND l.FA_CRD__c IS NOT NULL
        AND l.Company NOT LIKE '%Savvy%'  -- Exclude own company
),

-- Add wirehouse flag
leads_with_flags AS (
    SELECT 
        lf.*,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM excluded_firms ef 
                WHERE lf.company_upper LIKE ef.pattern
            ) THEN 1 ELSE 0 
        END as is_wirehouse,
        -- V3.3.1: Large firm flag (for V4 deprioritization)
        CASE WHEN lf.firm_rep_count_at_contact > 50 THEN 1 ELSE 0 END as is_large_firm
    FROM lead_features lf
),

-- Certification and license detection from FINTRX
-- V3.2.1 Update: Added title exclusion logic (data-driven, removes ~8.5% of leads with 0% conversion)
lead_certifications AS (
    SELECT 
        l.lead_id,
        c.PRIMARY_FIRM as firm_crd,
        
        -- CFP from CONTACT_BIO or TITLE_NAME (professional certification)
        CASE WHEN c.CONTACT_BIO LIKE '%CFP%' 
             OR c.CONTACT_BIO LIKE '%Certified Financial Planner%'
             OR c.TITLE_NAME LIKE '%CFP%'
             THEN 1 ELSE 0 END as has_cfp,
        
        -- Series 65 only (pure RIA - NOT dual-registered)
        CASE WHEN c.REP_LICENSES LIKE '%Series 65%' 
             AND c.REP_LICENSES NOT LIKE '%Series 7%' 
             THEN 1 ELSE 0 END as has_series_65_only,
        
        -- Series 7 (broker-dealer registered - negative signal)
        CASE WHEN c.REP_LICENSES LIKE '%Series 7%' 
             THEN 1 ELSE 0 END as has_series_7,
        
        -- CFA (institutional focus - potential exclusion signal)
        CASE WHEN c.CONTACT_BIO LIKE '%CFA%' 
             OR c.CONTACT_BIO LIKE '%Chartered Financial Analyst%'
             OR c.TITLE_NAME LIKE '%CFA%'
             THEN 1 ELSE 0 END as has_cfa,
        
        -- High-Value Wealth Title flag (ownership/seniority + wealth focus)
        -- Added V3.2.2: 266 leads, 12.78% conversion when combined with bleeding firm
        CASE WHEN (
            (UPPER(c.TITLE_NAME) LIKE '%WEALTH MANAGER%' 
             AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%'
             AND UPPER(c.TITLE_NAME) NOT LIKE '%ASSOCIATE%'
             AND UPPER(c.TITLE_NAME) NOT LIKE '%ASSISTANT%')
            OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%WEALTH%DIRECTOR%'
            OR (UPPER(c.TITLE_NAME) LIKE '%SENIOR VICE%WEALTH%' 
                AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%')
            OR (UPPER(c.TITLE_NAME) LIKE '%SVP%WEALTH%'
                AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%')
            OR UPPER(c.TITLE_NAME) LIKE '%SENIOR WEALTH ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%FOUNDER%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%WEALTH%FOUNDER%'
            OR UPPER(c.TITLE_NAME) LIKE '%PRINCIPAL%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%WEALTH%PRINCIPAL%'
            OR (UPPER(c.TITLE_NAME) LIKE '%PARTNER%WEALTH%'
                AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%')
            OR UPPER(c.TITLE_NAME) LIKE '%PRESIDENT%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%WEALTH%PRESIDENT%'
            OR (UPPER(c.TITLE_NAME) LIKE '%MANAGING DIRECTOR%WEALTH%'
                AND UPPER(c.TITLE_NAME) NOT LIKE '%WEALTH MANAGEMENT ADVISOR%')
        ) THEN 1 ELSE 0 END as is_hv_wealth_title,
        
        -- Title exclusion flag (V3.2.1 - data-driven exclusions)
        CASE WHEN 
            -- HARD EXCLUSIONS: 0% conversion titles with n >= 30
            UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTIONS ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTION ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
            OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE WEALTH ADVISOR%'
            OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS MANAGER%'
            OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR OF OPERATIONS%'
            OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS SPECIALIST%'
            OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS ASSOCIATE%'
            OR UPPER(c.TITLE_NAME) LIKE '%CHIEF OPERATING OFFICER%'
            OR UPPER(c.TITLE_NAME) LIKE '%FIRST VICE PRESIDENT%'
            OR UPPER(c.TITLE_NAME) LIKE '%WHOLESALER%'
            OR UPPER(c.TITLE_NAME) LIKE '%INTERNAL WHOLESALER%'
            OR UPPER(c.TITLE_NAME) LIKE '%EXTERNAL WHOLESALER%'
            OR UPPER(c.TITLE_NAME) LIKE '%INTERNAL SALES%'
            OR UPPER(c.TITLE_NAME) LIKE '%EXTERNAL SALES%'
            OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE OFFICER%'
            OR UPPER(c.TITLE_NAME) LIKE '%CHIEF COMPLIANCE%'
            OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE MANAGER%'
            OR UPPER(c.TITLE_NAME) LIKE '%SUPERVISION%'
            OR UPPER(c.TITLE_NAME) LIKE '%REGISTERED ASSISTANT%'
            OR UPPER(c.TITLE_NAME) LIKE '%CLIENT SERVICE ASSOCIATE%'
            OR UPPER(c.TITLE_NAME) LIKE '%SALES ASSISTANT%'
            OR UPPER(c.TITLE_NAME) LIKE '%ADMINISTRATIVE ASSISTANT%'
            OR UPPER(c.TITLE_NAME) LIKE '%BRANCH OFFICE ADMINISTRATOR%'
            OR (UPPER(c.TITLE_NAME) LIKE '%ANALYST%' 
                AND UPPER(c.TITLE_NAME) NOT LIKE '%INVESTMENT ANALYST%'
                AND UPPER(c.TITLE_NAME) NOT LIKE '%FINANCIAL ANALYST%'
                AND UPPER(c.TITLE_NAME) NOT LIKE '%PORTFOLIO ANALYST%')
            OR UPPER(c.TITLE_NAME) = 'SENIOR VICE PRESIDENT, FINANCIAL ADVISOR'
            OR UPPER(c.TITLE_NAME) = 'SENIOR VICE PRESIDENT, WEALTH MANAGEMENT ADVISOR'
            OR UPPER(c.TITLE_NAME) = 'SENIOR VICE PRESIDENT, SENIOR FINANCIAL ADVISOR'
            OR UPPER(c.TITLE_NAME) = 'VICE PRESIDENT, SENIOR FINANCIAL ADVISOR'
            -- V3.2.4: Insurance exclusions
            OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE AGENT%'
            OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE%'
            THEN 1 ELSE 0 END as is_excluded_title
        
    FROM leads_with_flags l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.advisor_crd AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    WHERE c.PRODUCING_ADVISOR = TRUE  -- V3.2.3: Filter to only producing advisors
),

-- Join certifications to leads
-- V3.2.1 Update: Filter out excluded titles (data-driven, removes ~8.5% of leads)
-- V3.2.3 Update: Filter to only producing advisors (PRODUCING_ADVISOR = TRUE)
-- V3.3.1 Update: Add discretionary ratio join and exclusion filter
leads_with_certs AS (
    SELECT 
        l.*,
        COALESCE(cert.has_cfp, 0) as has_cfp,
        COALESCE(cert.has_series_65_only, 0) as has_series_65_only,
        COALESCE(cert.has_series_7, 0) as has_series_7,
        COALESCE(cert.has_cfa, 0) as has_cfa,
        COALESCE(cert.is_hv_wealth_title, 0) as is_hv_wealth_title,
        COALESCE(cert.is_excluded_title, 0) as is_excluded_title,
        -- V3.3.1: Discretionary tier and flag
        COALESCE(fd.discretionary_tier, 'UNKNOWN') as discretionary_tier,
        COALESCE(fd.discretionary_ratio, -1) as discretionary_ratio,
        CASE 
            WHEN fd.discretionary_ratio < 0.50 AND fd.discretionary_ratio IS NOT NULL 
            THEN 1 ELSE 0 
        END as is_low_discretionary,
        -- V3.3.2: Average account size for T1G Growth Stage tier
        COALESCE(fas.avg_account_size, 0) as avg_account_size,
        COALESCE(fas.practice_maturity, 'UNKNOWN') as practice_maturity,
        -- V3.3.3: Portable custodian flag for T1B_PRIME tier
        COALESCE(fc.has_portable_custodian, 0) as has_portable_custodian
    FROM leads_with_flags l
    INNER JOIN lead_certifications cert
        ON l.lead_id = cert.lead_id
    LEFT JOIN firm_discretionary fd ON cert.firm_crd = fd.firm_crd
    LEFT JOIN firm_account_size fas ON cert.firm_crd = fas.firm_crd
    LEFT JOIN firm_custodian fc ON cert.firm_crd = fc.firm_crd
    WHERE COALESCE(cert.is_excluded_title, 0) = 0  -- Exclude leads with excluded titles
      -- V3.3.1: Exclude low discretionary firms (0.34x baseline)
      -- Allow NULL/Unknown - don't penalize missing data
      AND (
          fd.discretionary_ratio >= 0.50 
          OR fd.discretionary_ratio IS NULL
          OR fd.TOTAL_AUM IS NULL 
          OR fd.TOTAL_AUM = 0
      )
      -- Note: PRODUCING_ADVISOR = TRUE filter already applied in lead_certifications CTE
),

-- Assign tiers (V3.4.0 UPDATED with Career Clock tiers)
tiered_leads_base AS (
    SELECT 
        *,
        CASE 
            -- ================================================================
            -- TIER 0: CAREER CLOCK PRIORITY TIERS (V3.4.0)
            -- These are advisors with predictable patterns who are "due" to move
            -- ================================================================
            
            -- TIER_0A: Prime Mover + In Move Window (5.59% conversion, 2.43x vs No_Pattern)
            -- Combines T1 criteria with Career Clock timing signal
            -- Analysis: career_clock_results.md (January 7, 2026)
            WHEN COALESCE(cc_is_in_move_window, FALSE) = TRUE
                 AND current_firm_tenure_months BETWEEN 12 AND 48
                 AND industry_tenure_months BETWEEN 60 AND 180
                 AND firm_net_change_12mo < 0
                 AND is_wirehouse = 0
            THEN 'TIER_0A_PRIME_MOVER_DUE'
            
            -- TIER_0B: Small Firm + In Move Window (5.50% estimated)
            -- Small firm advisors who are personally "due" to move
            WHEN COALESCE(cc_is_in_move_window, FALSE) = TRUE
                 AND firm_rep_count_at_contact <= 10
                 AND is_wirehouse = 0
            THEN 'TIER_0B_SMALL_FIRM_DUE'
            
            -- TIER_0C: Clockwork Due (5.07% conversion, 1.33x lift)
            -- Any predictable advisor in their move window (rescues STANDARD leads)
            WHEN COALESCE(cc_is_in_move_window, FALSE) = TRUE
                 AND is_wirehouse = 0
            THEN 'TIER_0C_CLOCKWORK_DUE'
            
            -- ==========================================================================
            -- TIER 1B_PRIME: ZERO FRICTION BLEEDER (Highest Converting Segment)
            -- ==========================================================================
            -- V3.3.3: NEW TIER - Our highest-converting segment ever found!
            -- 
            -- THEORY: "Zero Friction" transitions - when ALL barriers are removed:
            -- - Series 65 Only = No BD lock-in (pure RIA)
            -- - Portable Custodian = Same platform at new firm (Negative Consent paperwork)
            -- - Small Firm = No bureaucratic exit barriers
            -- - Bleeding Firm = Motivation to leave
            --
            -- CRITICAL: Leads with CFP credential go to T1A instead (CFP has higher value)
            --
            -- VALIDATION:
            -- - Conversion: 13.64% (3.57x baseline)
            -- - Sample: 22 leads
            -- - Only 1 lead overlaps with T1A (has CFP) - minimal conflict
            --
            -- CRITERIA:
            -- - Series 65 Only (no Series 7)
            -- - Portable Custodian (Schwab/Fidelity/Pershing)
            -- - Small Firm (≤10 reps)
            -- - Firm Bleeding (net_change ≤ -3)
            -- - NO CFP credential (CFP leads go to T1A)
            -- ==========================================================================
            WHEN has_series_65_only = 1                      -- Pure RIA (no BD)
                 AND has_portable_custodian = 1              -- Schwab/Fidelity/Pershing
                 AND firm_rep_count_at_contact <= 10         -- Small firm (no bureaucracy)
                 AND firm_net_change_12mo <= -3              -- Bleeding firm (motivation)
                 AND has_cfp = 0                             -- No CFP (CFP goes to T1A)
                 AND is_wirehouse = 0                        -- Not at wirehouse
                 AND is_excluded_title = 0                   -- Not excluded title
            THEN 'TIER_1B_PRIME_ZERO_FRICTION'
            
            -- ============================================================
            -- TIER 1A: PRIME MOVER + CFP at BLEEDING FIRM
            -- CFP holders (book ownership signal) at unstable firms
            -- Expected: 16.44% conversion, 4.3x lift
            -- Historical validation: 73 leads, 12 conversions
            -- ============================================================
            WHEN (
                current_firm_tenure_months BETWEEN 12 AND 48  -- 1-4 years tenure
                AND industry_tenure_months >= 60              -- 5+ years experience
                AND firm_net_change_12mo < 0                  -- Bleeding firm
                AND has_cfp = 1                               -- CFP designation
                AND is_wirehouse = 0
            )
            THEN 'TIER_1A_PRIME_MOVER_CFP'
            
            -- ============================================================
            -- TIER 1B: PRIME MOVER + SERIES 65 ONLY (Pure RIA)
            -- Series 65 (no Series 7) = fee-only RIA, easier to move
            -- Expected: 16.48% conversion, 4.3x lift
            -- Historical validation: 91 leads, 15 conversions
            -- ============================================================
            WHEN (
                -- Standard Tier 1 criteria
                (current_firm_tenure_months BETWEEN 12 AND 36
                 AND industry_tenure_months BETWEEN 60 AND 180
                 AND firm_net_change_12mo < 0
                 AND firm_rep_count_at_contact <= 50
                 AND is_wirehouse = 0)
                OR
                (current_firm_tenure_months BETWEEN 12 AND 36
                 AND firm_rep_count_at_contact <= 10
                 AND is_wirehouse = 0)
                OR
                (current_firm_tenure_months BETWEEN 12 AND 48
                 AND industry_tenure_months BETWEEN 60 AND 180
                 AND firm_net_change_12mo < 0
                 AND is_wirehouse = 0)
            )
            AND has_series_65_only = 1
            THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            
            -- ============================================================
            -- TIER 1C: PRIME MOVERS - SMALL FIRM (Expected ~13.21% conversion)
            -- Tightest criteria: short tenure + small bleeding firm
            -- ============================================================
            WHEN current_firm_tenure_months BETWEEN 12 AND 36  -- 1-3 years (tightened from 1-4)
                 AND industry_tenure_months BETWEEN 60 AND 180  -- 5-15 years experience
                 AND firm_net_change_12mo < 0                   -- Bleeding firm (changed from != 0)
                 AND firm_rep_count_at_contact <= 50            -- Small/mid firm (NEW)
                 AND is_wirehouse = 0
            THEN 'TIER_1C_PRIME_MOVER_SMALL'
            
            -- ============================================================
            -- TIER 1D: SMALL FIRM ADVISORS (Expected ~14% conversion)
            -- Very small firms convert well even without bleeding signal
            -- ============================================================
            WHEN current_firm_tenure_months BETWEEN 12 AND 36  -- 1-3 years tenure
                 AND firm_rep_count_at_contact <= 10            -- Very small firm (NEW)
                 AND is_wirehouse = 0
            THEN 'TIER_1D_SMALL_FIRM'
            
            -- ============================================================
            -- TIER 1E: PRIME MOVERS - ORIGINAL (Expected ~13.21% conversion)
            -- Original Tier 1 logic for larger firms (without CFP/Series 65 boost)
            -- ============================================================
            WHEN current_firm_tenure_months BETWEEN 12 AND 48  -- 1-4 years (original)
                 AND industry_tenure_months BETWEEN 60 AND 180  -- 5-15 years experience
                 AND firm_net_change_12mo < 0                   -- Bleeding firm
                 AND is_wirehouse = 0
            THEN 'TIER_1E_PRIME_MOVER'
            
            -- ============================================================
            -- TIER 1F: HV WEALTH TITLE + BLEEDING FIRM (NEW - V3.2.2)
            -- High-Value Wealth title at a firm losing advisors
            -- Expected: 12.78% conversion, 3.35x lift
            -- Historical validation: 266 leads, 34 conversions
            -- ============================================================
            WHEN is_hv_wealth_title = 1
                 AND firm_net_change_12mo < 0      -- Bleeding firm
                 AND is_wirehouse = 0
            THEN 'TIER_1F_HV_WEALTH_BLEEDER'
            
            -- ==========================================================================
            -- TIER 1G_ENHANCED: GROWTH STAGE + AUM SWEET SPOT (Proactive Movers)
            -- ==========================================================================
            -- V3.3.3: UPGRADED from T1G - Refined AUM range to $500K-$2M
            -- 
            -- THEORY: The "sweet spot" is $500K-$2M average account size:
            -- - Big enough for client loyalty (not brand loyalty)
            -- - Small enough to avoid institutional lock-in
            --
            -- VALIDATION:
            -- - Conversion: 9.09% (2.38x baseline)
            -- - Sample: 66 leads
            -- - 79% improvement over leads outside this range
            --
            -- CRITERIA:
            -- - Mid-career (5-15 years)
            -- - AUM Sweet Spot ($500K-$2M avg account) ← REFINED
            -- - Stable firm (net_change > -3)
            --
            -- Checked BEFORE T1B because 9.09% > 5.49%
            -- ==========================================================================
            WHEN industry_tenure_months BETWEEN 60 AND 180   -- Mid-career (5-15 years)
                 AND avg_account_size BETWEEN 500000 AND 2000000  -- Sweet Spot ($500K-$2M)
                 AND firm_net_change_12mo > -3               -- Stable firm (NOT bleeding)
                 AND is_wirehouse = 0                        -- Not at wirehouse
                 AND COALESCE(is_excluded_title, 0) = 0      -- Not excluded title
            THEN 'TIER_1G_ENHANCED_SWEET_SPOT'
            
            -- ==========================================================================
            -- TIER 1G_REMAINDER: GROWTH STAGE (Outside Sweet Spot)
            -- ==========================================================================
            -- V3.3.3: Catches Growth Stage leads outside the $500K-$2M sweet spot
            -- Lower priority than T1G_ENHANCED but still above T2
            --
            -- VALIDATION:
            -- - Conversion: 5.08% (1.33x baseline)
            -- - Sample: 59 leads
            -- ==========================================================================
            WHEN industry_tenure_months BETWEEN 60 AND 180   -- Mid-career (5-15 years)
                 AND avg_account_size >= 250000              -- Original threshold
                 AND (avg_account_size < 500000 OR avg_account_size > 2000000)  -- Outside sweet spot
                 AND firm_net_change_12mo > -3               -- Stable firm
                 AND is_wirehouse = 0                        -- Not at wirehouse
                 AND COALESCE(is_excluded_title, 0) = 0      -- Not excluded title
            THEN 'TIER_1G_GROWTH_STAGE'
            
            -- ============================================================
            -- TIER 2A: PROVEN MOVERS (Expected ~10% conversion) - NEW
            -- Career movers who have changed firms 3+ times
            -- ============================================================
            WHEN num_prior_firms >= 3                           -- 3+ prior employers (NEW)
                 AND industry_tenure_months >= 60               -- 5+ years experience
                 AND is_wirehouse = 0
            THEN 'TIER_2A_PROVEN_MOVER'
            
            -- ============================================================
            -- TIER 2B: MODERATE BLEEDERS (Expected ~11% conversion)
            -- Firms losing 1-10 advisors (original Tier 2)
            -- ============================================================
            WHEN firm_net_change_12mo BETWEEN -10 AND -1
                 AND industry_tenure_months >= 60               -- 5+ years experience
            THEN 'TIER_2B_MODERATE_BLEEDER'
            
            -- ============================================================
            -- TIER 3: EXPERIENCED MOVERS (Expected ~10% conversion)
            -- Veterans who recently moved (original Tier 3)
            -- ============================================================
            WHEN current_firm_tenure_months BETWEEN 12 AND 48  -- 1-4 years tenure
                 AND industry_tenure_months >= 240              -- 20+ years experience
            THEN 'TIER_3_EXPERIENCED_MOVER'
            
            -- ============================================================
            -- TIER 4: HEAVY BLEEDERS (Expected ~10% conversion)
            -- Firms in crisis losing 10+ advisors (original Tier 4)
            -- ============================================================
            WHEN firm_net_change_12mo < -10
                 AND industry_tenure_months >= 60               -- 5+ years experience
            THEN 'TIER_4_HEAVY_BLEEDER'
            
            -- ================================================================
            -- DEPRIORITIZATION: Too Early (V3.4.0)
            -- Predictable advisors contacted before their typical move window
            -- These should be nurtured, not actively pursued
            -- ================================================================
            
            -- Check AFTER all priority tiers, BEFORE STANDARD
            -- V3.6.0: Updated conversion rate to 3.72% (from analysis)
            WHEN COALESCE(cc_is_too_early, FALSE) = TRUE
                 AND firm_net_change_12mo >= -10  -- Not at a heavy bleeding firm (those convert anyway)
            THEN 'TIER_NURTURE_TOO_EARLY'
            
            -- ============================================================
            -- STANDARD: All other leads
            -- ============================================================
            ELSE 'STANDARD'
        END as score_tier
    FROM leads_with_certs
),

tiered_leads AS (
    SELECT 
        *,
        -- Tier Display Names (for SGA dashboard) - V3.4.0 UPDATED
        CASE score_tier
            WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN '⏰ Tier 0A: Prime Mover + Career Clock'
            WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN '⏰ Tier 0B: Small Firm + Career Clock'
            WHEN 'TIER_0C_CLOCKWORK_DUE' THEN '⏰ Tier 0C: Clockwork Due'
            WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN '⭐ Tier 1B_PRIME: Zero Friction Bleeder'
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN '🏆 Tier 1A: Prime Mover + CFP'
            WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN '🚀 Tier 1G_ENHANCED: Sweet Spot Growth'
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN '🥇 Tier 1B: Prime Mover (Pure RIA)'
            WHEN 'TIER_1G_GROWTH_STAGE' THEN '🚀 Tier 1G: Growth Stage (Outside Sweet Spot)'
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN '🥇 Prime Mover (Small Firm)'
            WHEN 'TIER_1D_SMALL_FIRM' THEN '🥇 Small Firm Advisor'
            WHEN 'TIER_1E_PRIME_MOVER' THEN '🥇 Prime Mover'
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN '🏆 Tier 1F: HV Wealth (Bleeding)'
            WHEN 'TIER_2A_PROVEN_MOVER' THEN '🥈 Proven Mover'
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN '🥈 Moderate Bleeder'
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN '🥉 Experienced Mover'
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN '🎖️ Heavy Bleeder'
            WHEN 'TIER_NURTURE_TOO_EARLY' THEN '🌱 Nurture: Too Early'
            ELSE 'Standard'
        END as tier_display,
        
        -- Expected Conversion Rate (V3.6.0 UPDATED - ordered by performance)
        CASE score_tier
            -- Career Clock Tiers (V3.6.0 - updated from analysis)
            WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 0.0559      -- 5.59% (from career_clock_results.md)
            WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 0.0550       -- 5.50% (estimated)
            WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 0.0507        -- 5.07% (from analysis)
            WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 0.1364     -- V3.3.3: 13.64% (n=22)
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 0.1000        -- V3.3.3: 10.00% (n=50) - UPDATED
            WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 0.0909    -- V3.3.3: 9.09% (n=66) - NEW
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 0.0549  -- V3.3.3: 5.49% (n=237) - UPDATED
            WHEN 'TIER_1G_GROWTH_STAGE' THEN 0.0508           -- V3.3.3: 5.08% (n=59) - NEW
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN 0.1321     -- UPDATED: 13.21% (was 15%)
            WHEN 'TIER_1D_SMALL_FIRM' THEN 0.14
            WHEN 'TIER_1E_PRIME_MOVER' THEN 0.1321           -- UPDATED: 13.21% (was 13%)
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 0.1278      -- NEW: 12.78% (n=266)
            WHEN 'TIER_2A_PROVEN_MOVER' THEN 0.10
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN 0.11
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 0.10
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN 0.10
            WHEN 'TIER_NURTURE_TOO_EARLY' THEN 0.0372       -- 3.72% (from analysis)
            ELSE 0.0382                                       -- UPDATED: 3.82% baseline
        END as expected_conversion_rate,
        
        -- Expected Lift vs baseline (3.82%) - V3.6.0 UPDATED
        CASE score_tier
            -- Career Clock Tiers (V3.6.0 - updated from analysis)
            WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1.46      -- 5.59% / 3.82% (2.43x vs No_Pattern within age group)
            WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 1.44       -- 5.50% / 3.82%
            WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 1.33        -- 5.07% / 3.82%
            WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 3.57    -- V3.3.3: 13.64% / 3.82%
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 2.62       -- V3.3.3: 10.00% / 3.82% - UPDATED
            WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 2.38    -- V3.3.3: 9.09% / 3.82% - NEW
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 1.44   -- V3.3.3: 5.49% / 3.82% - UPDATED
            WHEN 'TIER_1G_GROWTH_STAGE' THEN 1.33          -- V3.3.3: 5.08% / 3.82% - NEW
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN 3.46      -- 13.21% / 3.82%
            WHEN 'TIER_1D_SMALL_FIRM' THEN 3.66
            WHEN 'TIER_1E_PRIME_MOVER' THEN 3.46           -- 13.21% / 3.82%
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 3.35     -- 12.78% / 3.82%
            WHEN 'TIER_2A_PROVEN_MOVER' THEN 2.5
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN 2.5
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 2.5
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN 2.3
            WHEN 'TIER_NURTURE_TOO_EARLY' THEN 0.97       -- 3.72% / 3.82% (below baseline)
            ELSE 1.00
        END as expected_lift,
        
        -- Priority Ranking (for sorting - lower = higher priority) - V3.6.0 UPDATED
        CASE score_tier
            -- Career Clock Tiers (V3.6.0 - highest priority)
            WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1           -- Highest priority
            WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2            
            WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3             
            WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 4       -- Rank 4 (was 1 before CC tiers)
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 5           -- Was 2
            WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 6       -- Was 3
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 7      -- Was 4
            WHEN 'TIER_1G_GROWTH_STAGE' THEN 8               -- Was 5
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN 9          -- Was 6
            WHEN 'TIER_1D_SMALL_FIRM' THEN 10               -- Was 7
            WHEN 'TIER_1E_PRIME_MOVER' THEN 11               -- Was 8
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 12         -- Was 9
            WHEN 'TIER_2A_PROVEN_MOVER' THEN 13              -- Was 8
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN 14          -- Was 8
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 15          -- Was 9
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN 16              -- Was 10
            WHEN 'TIER_NURTURE_TOO_EARLY' THEN 98            -- NEW: Near bottom
            ELSE 99
        END as priority_rank,
        
        -- Action Recommended - V3.4.0 UPDATED
        CASE score_tier
            WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN '⏰ ULTRA-PRIORITY: Prime Mover + Career Clock timing (5.59% conversion, 2.43x vs No_Pattern)'
            WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN '⏰ ULTRA-PRIORITY: Small Firm + Career Clock timing (5.50% conversion)'
            WHEN 'TIER_0C_CLOCKWORK_DUE' THEN '⏰ HIGH PRIORITY: Career Clock timing signal (5.07% conversion, 1.33x lift)'
            WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN '⭐ ULTRA-PRIORITY: Zero Friction Bleeder - ALL barriers removed (13.64% conversion)'
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN '🔥 ULTRA-PRIORITY: Call immediately - CFP at unstable firm (10.00% conversion)'
            WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN '🚀 HIGH PRIORITY: Sweet Spot Growth Advisor - optimal AUM range (9.09% conversion)'
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN '🔥 Call immediately - pure RIA (no BD ties) - 5.49% conversion'
            WHEN 'TIER_1G_GROWTH_STAGE' THEN '🚀 High priority - proactive mover at stable firm (5.08% conversion)'
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN 'Call immediately - highest priority'
            WHEN 'TIER_1D_SMALL_FIRM' THEN 'Call immediately - highest priority'
            WHEN 'TIER_1E_PRIME_MOVER' THEN 'Call immediately - highest priority'
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN '🔥 High priority - wealth leader at unstable firm'
            WHEN 'TIER_2A_PROVEN_MOVER' THEN 'Priority outreach within 24 hours'
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN 'Priority outreach within 24 hours'
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 'Priority follow-up this week'
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN 'Priority follow-up this week'
            WHEN 'TIER_NURTURE_TOO_EARLY' THEN 'NURTURE - DO NOT ACTIVELY PURSUE: Too early in cycle (3.72% conversion, below baseline)'
            ELSE 'Standard outreach cadence'
        END as action_recommended,
        
        -- Tier Explanation (for sales team - V3.4.0 UPDATED with Career Clock)
        CASE score_tier
            WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN CONCAT(
                'HIGHEST PRIORITY - Career Clock: ', FirstName, ' matches Prime Mover criteria (1-4yr tenure, 5-15yr experience, ',
                'firm instability) AND has a predictable career pattern showing they are currently in their ',
                'typical "move window" (70-130% through their average tenure cycle). Career Clock + Prime Mover converts at ',
                '5.59% (2.43x vs advisors with no pattern within same age group). Analysis: career_clock_results.md.'
            )
            WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN CONCAT(
                'HIGHEST PRIORITY - Career Clock: ', FirstName, ' is at a small firm (≤10 reps) AND has a predictable career ',
                'pattern showing they are currently in their typical "move window". Small firm advisors have ',
                'portable books and this timing signal indicates high receptivity. Expected conversion: 5.50%.'
            )
            WHEN 'TIER_0C_CLOCKWORK_DUE' THEN CONCAT(
                'HIGH PRIORITY - Career Clock: ', FirstName, ' has a predictable career pattern (consistent tenure lengths) and ',
                'is currently in their typical "move window" (70-130% through their average tenure cycle). ',
                'Even without other priority signals, timing alone makes them 1.33x more likely to convert (5.07% vs 3.82% baseline). ',
                'Analysis: career_clock_results.md.'
            )
            WHEN 'TIER_NURTURE_TOO_EARLY' THEN CONCAT(
                'NURTURE - DO NOT ACTIVELY PURSUE: ', FirstName, ' has a predictable career pattern but is ',
                'TOO EARLY in their cycle (less than 70% through typical tenure). Contacting now wastes ',
                'outreach - they convert at only 3.72% (below 3.82% baseline). Add to nurture sequence and revisit in ',
                CAST(COALESCE(cc_months_until_window, 0) AS STRING), ' months when they enter their move window. Analysis: career_clock_results.md.'
            )
            WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN CONCAT(
                FirstName, ' is a ZERO FRICTION BLEEDER: ',
                'Pure RIA (Series 65 only) at small firm (', CAST(firm_rep_count_at_contact AS STRING), ' reps) ',
                'using portable custodian. Firm is bleeding (', CAST(firm_net_change_12mo AS STRING), ' net change). ',
                'All transition barriers removed - highest conversion segment (13.64%, 3.57x baseline).'
            )
            WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN CONCAT(
                FirstName, ' is a SWEET SPOT GROWTH ADVISOR: ',
                'Mid-career (', CAST(ROUND(industry_tenure_months/12, 0) AS STRING), ' years) ',
                'with optimal client base ($', CAST(ROUND(avg_account_size/1000, 0) AS STRING), 'K avg account). ',
                'Firm is stable - proactive mover seeking platform upgrade (9.09% conversion, 2.38x baseline).'
            )
            WHEN 'TIER_1G_GROWTH_STAGE' THEN CONCAT(
                FirstName, ' is a GROWTH STAGE ADVISOR: ',
                'Mid-career (', CAST(ROUND(industry_tenure_months/12, 0) AS STRING), ' years) ',
                'with established practice at ', Company, '. ',
                'Firm is stable - strategic growth opportunity (5.08% conversion, 1.33x baseline).'
            )
            WHEN 'TIER_2A_PROVEN_MOVER' THEN 'Has changed firms 3+ times - demonstrated willingness to move'
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN 'Experienced advisor at firm losing 1-10 reps - instability signal'
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 'Veteran (20+ yrs) who recently moved - has broken inertia'
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN 'Experienced advisor at firm in crisis (losing 10+ reps)'
            ELSE 'Standard lead - no priority signals detected'
        END as tier_explanation
    FROM tiered_leads_base
)

-- Final output
SELECT 
    lead_id,
    advisor_crd,
    contacted_date,
    FirstName,
    LastName,
    Email,
    Phone,
    Company,
    Title,
    Status,
    LeadSource,
    score_tier,
    tier_display,
    expected_conversion_rate,
    expected_lift,
    priority_rank,
    action_recommended,
    tier_explanation,
    -- Include key features for transparency
    current_firm_tenure_months,
    industry_tenure_months,
    firm_net_change_12mo,
    firm_rep_count_at_contact,
    num_prior_firms,
    is_wirehouse,
    converted,
    -- Certification flags (for analysis/tracking)
    has_cfp,
    has_series_65_only,
    has_series_7,
    has_cfa,
    is_hv_wealth_title,
    -- V3.3.1: Portable book signal flags
    discretionary_tier,
    discretionary_ratio,
    is_low_discretionary,
    is_large_firm,
    -- V3.3.2: Account size for T1G Growth Stage tier
    avg_account_size,
    practice_maturity,
    CURRENT_TIMESTAMP() as scored_at,
    'V3.6.0_01082026_CAREER_CLOCK_TIERS' as model_version
FROM tiered_leads
ORDER BY priority_rank, expected_conversion_rate DESC, contacted_date DESC
