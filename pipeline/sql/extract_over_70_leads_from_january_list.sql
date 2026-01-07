-- ============================================================================
-- EXTRACT OVER 70 LEADS FROM JANUARY_LEADS_REAL
-- ============================================================================
-- Version: 1.1
-- Created: January 7, 2026
-- Updated: January 7, 2026
-- Purpose: Extract names, CRDs, Salesforce Lead IDs, Owner, and Status for leads 70+ 
--          years old from January_Leads_Real, matching specific tier quotas by age group
--
-- TIER QUOTAS BY AGE:
--   STANDARD_HIGH_V4: 119 (70-74) + 61 (75-79) + 29 (80+) = 209 total
--   TIER_2_PROVEN_MOVER: 28 (70-74) + 12 (75-79) + 3 (80+) = 43 total
--   TIER_1_PRIME_MOVER: 4 (70-74) + 1 (75-79) + 1 (80+) = 6 total
--   TIER_1B_PRIME_MOVER_SERIES65: 1 (70-74) + 1 (75-79) + 0 (80+) = 2 total
--   TIER_1F_HV_WEALTH_BLEEDER: 0 (70-74) + 0 (75-79) + 2 (80+) = 2 total
--   TIER_3_MODERATE_BLEEDER: 0 (70-74) + 1 (75-79) + 0 (80+) = 1 total
--   TOTAL: 263 leads
-- ============================================================================

WITH 
-- ============================================================================
-- A. JOIN JANUARY_LEADS_REAL WITH AGE DATA AND SALESFORCE LEAD ID
-- ============================================================================
leads_with_age AS (
    SELECT 
        jl.advisor_crd,
        jl.first_name,
        jl.last_name,
        jl.score_tier,
        c.AGE_RANGE,
        sf.Id as salesforce_lead_id,
        sf.OwnerId as owner_id,
        sf.SGA_Owner_Name__c as owner_name,
        sf.Status as prospect_status,
        '005VS000005ahzdYAA' as Savvy_Operations_ID,
        CASE 
            WHEN c.AGE_RANGE = '70-74' THEN 'age_70_74'
            WHEN c.AGE_RANGE = '75-79' THEN 'age_75_79'
            WHEN c.AGE_RANGE IN ('80-84', '85-89', '90-94', '95-99') THEN 'age_80_plus'
            ELSE 'other'
        END as age_group,
        -- Rank within tier and specific age range for quota application
        ROW_NUMBER() OVER (
            PARTITION BY jl.score_tier, c.AGE_RANGE
            ORDER BY jl.advisor_crd
        ) as rank_within_age_range
    FROM `savvy-gtm-analytics.ml_features.January_Leads_Real` jl
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON jl.advisor_crd = c.RIA_CONTACT_CRD_ID
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.Lead` sf
        ON jl.advisor_crd = SAFE_CAST(REGEXP_REPLACE(CAST(sf.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64)
        AND sf.IsDeleted = false
    WHERE jl.score_tier IN (
        'STANDARD_HIGH_V4',
        'TIER_2_PROVEN_MOVER',
        'TIER_1_PRIME_MOVER',
        'TIER_1B_PRIME_MOVER_SERIES65',
        'TIER_1F_HV_WEALTH_BLEEDER',
        'TIER_3_MODERATE_BLEEDER'
    )
      AND c.AGE_RANGE IN ('70-74', '75-79', '80-84', '85-89', '90-94', '95-99')
),

-- ============================================================================
-- B. APPLY QUOTAS BY TIER AND AGE RANGE
-- ============================================================================
quota_filtered AS (
    SELECT 
        lwa.*,
        CASE 
            WHEN lwa.age_group = 'age_70_74' THEN 'age_70_74'
            WHEN lwa.age_group IN ('age_75_79', 'age_80_plus') THEN 'age_75_80_plus'
            ELSE 'other'
        END as age_group_display
    FROM leads_with_age lwa
    WHERE 
        -- STANDARD_HIGH_V4: 119 (70-74) + 61 (75-79) + 29 (80+) = 209
        (lwa.score_tier = 'STANDARD_HIGH_V4' 
         AND lwa.AGE_RANGE = '70-74' 
         AND lwa.rank_within_age_range <= 119)
        OR (lwa.score_tier = 'STANDARD_HIGH_V4' 
            AND lwa.AGE_RANGE = '75-79' 
            AND lwa.rank_within_age_range <= 61)
        OR (lwa.score_tier = 'STANDARD_HIGH_V4' 
            AND lwa.AGE_RANGE IN ('80-84', '85-89', '90-94', '95-99')
            AND lwa.rank_within_age_range <= 29)
        
        -- TIER_2_PROVEN_MOVER: 28 (70-74) + 12 (75-79) + 3 (80+) = 43
        OR (lwa.score_tier = 'TIER_2_PROVEN_MOVER' 
            AND lwa.AGE_RANGE = '70-74' 
            AND lwa.rank_within_age_range <= 28)
        OR (lwa.score_tier = 'TIER_2_PROVEN_MOVER' 
            AND lwa.AGE_RANGE = '75-79' 
            AND lwa.rank_within_age_range <= 12)
        OR (lwa.score_tier = 'TIER_2_PROVEN_MOVER' 
            AND lwa.AGE_RANGE IN ('80-84', '85-89', '90-94', '95-99')
            AND lwa.rank_within_age_range <= 3)
        
        -- TIER_1_PRIME_MOVER: 4 (70-74) + 1 (75-79) + 1 (80+) = 6
        OR (lwa.score_tier = 'TIER_1_PRIME_MOVER' 
            AND lwa.AGE_RANGE = '70-74' 
            AND lwa.rank_within_age_range <= 4)
        OR (lwa.score_tier = 'TIER_1_PRIME_MOVER' 
            AND lwa.AGE_RANGE = '75-79' 
            AND lwa.rank_within_age_range <= 1)
        OR (lwa.score_tier = 'TIER_1_PRIME_MOVER' 
            AND lwa.AGE_RANGE IN ('80-84', '85-89', '90-94', '95-99')
            AND lwa.rank_within_age_range <= 1)
        
        -- TIER_1B_PRIME_MOVER_SERIES65: 1 (70-74) + 1 (75-79) + 0 (80+) = 2
        OR (lwa.score_tier = 'TIER_1B_PRIME_MOVER_SERIES65' 
            AND lwa.AGE_RANGE = '70-74' 
            AND lwa.rank_within_age_range <= 1)
        OR (lwa.score_tier = 'TIER_1B_PRIME_MOVER_SERIES65' 
            AND lwa.AGE_RANGE = '75-79' 
            AND lwa.rank_within_age_range <= 1)
        
        -- TIER_1F_HV_WEALTH_BLEEDER: 0 (70-74) + 0 (75-79) + 2 (80+) = 2
        OR (lwa.score_tier = 'TIER_1F_HV_WEALTH_BLEEDER' 
            AND lwa.AGE_RANGE IN ('80-84', '85-89', '90-94', '95-99')
            AND lwa.rank_within_age_range <= 2)
        
        -- TIER_3_MODERATE_BLEEDER: 0 (70-74) + 1 (75-79) + 0 (80+) = 1
        OR (lwa.score_tier = 'TIER_3_MODERATE_BLEEDER' 
            AND lwa.AGE_RANGE = '75-79' 
            AND lwa.rank_within_age_range <= 1)
)

-- ============================================================================
-- FINAL OUTPUT: Names, CRDs, Salesforce Lead IDs, Owner, and Status
-- ============================================================================
SELECT 
    advisor_crd,
    first_name,
    last_name,
    CONCAT(first_name, ' ', last_name) as full_name,
    salesforce_lead_id,
    owner_id,
    owner_name,
    prospect_status,
    Savvy_Operations_ID,
    score_tier,
    AGE_RANGE,
    age_group_display as age_group
FROM quota_filtered
ORDER BY 
    CASE score_tier
        WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 1
        WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 2
        WHEN 'TIER_1_PRIME_MOVER' THEN 3
        WHEN 'TIER_2_PROVEN_MOVER' THEN 4
        WHEN 'TIER_3_MODERATE_BLEEDER' THEN 5
        WHEN 'STANDARD_HIGH_V4' THEN 6
    END,
    age_group_display,
    advisor_crd;

-- ============================================================================
-- VERIFICATION QUERY (Run after to confirm counts)
-- ============================================================================
-- SELECT 
--     score_tier,
--     age_group_display as age_group,
--     COUNT(*) as count
-- FROM quota_filtered
-- GROUP BY score_tier, age_group_display
-- ORDER BY 
--     CASE score_tier
--         WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 1
--         WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 2
--         WHEN 'TIER_1_PRIME_MOVER' THEN 3
--         WHEN 'TIER_2_PROVEN_MOVER' THEN 4
--         WHEN 'TIER_3_MODERATE_BLEEDER' THEN 5
--         WHEN 'STANDARD_HIGH_V4' THEN 6
--     END,
--     age_group_display;
