
-- =============================================================================
-- LEAD SCORING V3.2.4: UPDATED TIER MODEL WITH CERTIFICATIONS + TITLE EXCLUSIONS + HV WEALTH TIER + PRODUCING ADVISOR FILTER + INSURANCE EXCLUSIONS
-- =============================================================================
-- Version: V3.2.4_12232025_INSURANCE_EXCLUSIONS
-- Changes: 
--   - Added CFP and Series 65 certification tiers (Tier 1A/1B), updated Tier 1 rates
--   - Added data-driven title exclusion logic (removes ~8.5% of leads with 0% conversion)
--   - Added TIER_1F_HV_WEALTH_BLEEDER: High-Value Wealth titles at bleeding firms (12.78% conversion, 3.35x lift)
--   - Added PRODUCING_ADVISOR = TRUE filter to exclude non-advisors (operations, compliance, etc.)
--   - Added insurance exclusions: excludes "Insurance Agent" or "Insurance" in title or firm name
-- Expected Lift: T1A (CFP) = 4.3x, T1B (Series 65) = 4.3x, T1 = 3.5x, T1F (HV Wealth) = 3.35x, T2A = 2.5x, T2B = 2.5x
-- Historical Validation: Tier 1A (73 leads, 16.44%), Tier 1B (91 leads, 16.48%), Tier 1F (266 leads, 12.78%)
-- Title Exclusions: Based on analysis of 72,055 historical leads
-- HV Wealth Tier: Based on analysis of 6,503 wealth-related leads (high-value-analysis.md)
-- =============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.lead_scores_v3` AS

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
        END as is_wirehouse
    FROM lead_features lf
),

-- Certification and license detection from FINTRX
-- V3.2.1 Update: Added title exclusion logic (data-driven, removes ~8.5% of leads with 0% conversion)
lead_certifications AS (
    SELECT 
        l.lead_id,
        
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
leads_with_certs AS (
    SELECT 
        l.*,
        COALESCE(cert.has_cfp, 0) as has_cfp,
        COALESCE(cert.has_series_65_only, 0) as has_series_65_only,
        COALESCE(cert.has_series_7, 0) as has_series_7,
        COALESCE(cert.has_cfa, 0) as has_cfa,
        COALESCE(cert.is_hv_wealth_title, 0) as is_hv_wealth_title
    FROM leads_with_flags l
    INNER JOIN lead_certifications cert
        ON l.lead_id = cert.lead_id
    WHERE COALESCE(cert.is_excluded_title, 0) = 0  -- Exclude leads with excluded titles
      -- Note: PRODUCING_ADVISOR = TRUE filter already applied in lead_certifications CTE
),

-- Assign tiers (V3.2.1 UPDATED definitions with certifications)
tiered_leads_base AS (
    SELECT 
        *,
        CASE 
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
        -- Tier Display Names (for SGA dashboard)
        CASE score_tier
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN '🏆 Tier 1A: Prime Mover + CFP'
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN '🥇 Tier 1B: Prime Mover (Pure RIA)'
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN '🥇 Prime Mover (Small Firm)'
            WHEN 'TIER_1D_SMALL_FIRM' THEN '🥇 Small Firm Advisor'
            WHEN 'TIER_1E_PRIME_MOVER' THEN '🥇 Prime Mover'
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN '🏆 Tier 1F: HV Wealth (Bleeding)'
            WHEN 'TIER_2A_PROVEN_MOVER' THEN '🥈 Proven Mover'
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN '🥈 Moderate Bleeder'
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN '🥉 Experienced Mover'
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN '🎖️ Heavy Bleeder'
            ELSE 'Standard'
        END as tier_display,
        
        -- Expected Conversion Rate (calibrated from 3-year historical data)
        CASE score_tier
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 0.1644      -- NEW: 16.44% (n=73)
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 0.1648 -- NEW: 16.48% (n=91)
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN 0.1321   -- UPDATED: 13.21% (was 15%)
            WHEN 'TIER_1D_SMALL_FIRM' THEN 0.14
            WHEN 'TIER_1E_PRIME_MOVER' THEN 0.1321         -- UPDATED: 13.21% (was 13%)
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 0.1278   -- NEW: 12.78% (n=266)
            WHEN 'TIER_2A_PROVEN_MOVER' THEN 0.10
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN 0.11
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 0.10
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN 0.10
            ELSE 0.0382                                       -- UPDATED: 3.82% baseline
        END as expected_conversion_rate,
        
        -- Expected Lift vs baseline (3.82%)
        CASE score_tier
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 4.30        -- 16.44% / 3.82%
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 4.31   -- 16.48% / 3.82%
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN 3.46     -- 13.21% / 3.82%
            WHEN 'TIER_1D_SMALL_FIRM' THEN 3.66
            WHEN 'TIER_1E_PRIME_MOVER' THEN 3.46           -- 13.21% / 3.82%
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 3.35     -- 12.78% / 3.82%
            WHEN 'TIER_2A_PROVEN_MOVER' THEN 2.5
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN 2.5
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 2.5
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN 2.3
            ELSE 1.00
        END as expected_lift,
        
        -- Priority Ranking (for sorting - lower = higher priority)
        CASE score_tier
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1           -- NEW: Highest priority
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2      -- NEW: Second highest
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN 3         -- UPDATED: Was 1, now 3
            WHEN 'TIER_1D_SMALL_FIRM' THEN 4
            WHEN 'TIER_1E_PRIME_MOVER' THEN 5              -- UPDATED: Was 3, now 5
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 6        -- NEW
            WHEN 'TIER_2A_PROVEN_MOVER' THEN 7             -- UPDATED from 6
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN 8         -- UPDATED from 7
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 9         -- UPDATED from 8
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN 10            -- UPDATED from 9
            ELSE 99
        END as priority_rank,
        
        -- Action Recommended
        CASE score_tier
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN '🔥 ULTRA-PRIORITY: Call immediately - CFP at unstable firm'
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN '🔥 Call immediately - pure RIA (no BD ties)'
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN 'Call immediately - highest priority'
            WHEN 'TIER_1D_SMALL_FIRM' THEN 'Call immediately - highest priority'
            WHEN 'TIER_1E_PRIME_MOVER' THEN 'Call immediately - highest priority'
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN '🔥 High priority - wealth leader at unstable firm'
            WHEN 'TIER_2A_PROVEN_MOVER' THEN 'Priority outreach within 24 hours'
            WHEN 'TIER_2B_MODERATE_BLEEDER' THEN 'Priority outreach within 24 hours'
            WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 'Priority follow-up this week'
            WHEN 'TIER_4_HEAVY_BLEEDER' THEN 'Priority follow-up this week'
            ELSE 'Standard outreach cadence'
        END as action_recommended,
        
        -- Tier Explanation (for sales team - V3.2.1 includes certification context)
        CASE score_tier
            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 'CFP holder (Certified Financial Planner) at bleeding firm - CFP designation indicates book ownership and client relationships, making this advisor highly portable. Highest conversion potential at 16.44% (4.30x baseline).'
            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 'Fee-only RIA (Series 65 only, no Series 7) meeting Prime Mover criteria - pure RIA advisors have no broker-dealer ties, making transitions easier. Expected 16.48% conversion (4.31x baseline).'
            WHEN 'TIER_1C_PRIME_MOVER_SMALL' THEN 'Mid-career advisor (1-3yr tenure, 5-15yr exp) at small bleeding firm - highest conversion signal'
            WHEN 'TIER_1D_SMALL_FIRM' THEN 'Recent joiner at very small firm (<10 reps) - high portability signal'
            WHEN 'TIER_1E_PRIME_MOVER' THEN 'Mid-career advisor at bleeding firm - proven high-converting segment'
            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 'High-Value Wealth title holder (Wealth Manager, Director, Senior Advisor, Founder/Principal/Partner) at firm losing advisors. This combination of ownership-level title and firm instability historically converts at 12.78% (3.35x baseline). Title indicates book ownership and client relationships.'
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
    CURRENT_TIMESTAMP() as scored_at,
    'V3.2.4_12232025_INSURANCE_EXCLUSIONS' as model_version
FROM tiered_leads
ORDER BY priority_rank, expected_conversion_rate DESC, contacted_date DESC
