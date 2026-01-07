-- ============================================================================
-- ENRICH LEAD LIST WITH AGE_RANGE
-- Version: 1.0
-- Created: January 7, 2026
-- Purpose: Add AGE_RANGE from FinTrx data to January_Leads_Real lead list
--          and identify leads likely over age 65
-- ============================================================================

-- ============================================================================
-- QUERY 1: Enriched Lead List with AGE_RANGE
-- ============================================================================
-- This query adds AGE_RANGE to the lead list by joining with FinTrx data
-- Match: advisor_crd (lead list) = RIA_CONTACT_CRD_ID (FinTrx)
-- ============================================================================

SELECT 
    ll.*,
    c.AGE_RANGE,
    -- Flag for likely over 65 (includes 65-69, 70-74, 75-79, 80-84, 85-89, 90-94, 95-99)
    CASE 
        WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 1
        ELSE 0
    END as is_likely_over_65,
    -- More granular age grouping
    CASE 
        WHEN c.AGE_RANGE IN ('65-69') THEN '65-69'
        WHEN c.AGE_RANGE IN ('70-74') THEN '70-74'
        WHEN c.AGE_RANGE IN ('75-79') THEN '75-79'
        WHEN c.AGE_RANGE IN ('80-84', '85-89', '90-94', '95-99') THEN '80+'
        WHEN c.AGE_RANGE IS NULL THEN 'UNKNOWN'
        ELSE 'UNDER_65'
    END as age_group
FROM `savvy-gtm-analytics.ml_features.January_Leads_Real` ll
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON ll.advisor_crd = c.RIA_CONTACT_CRD_ID
ORDER BY ll.list_rank;


-- ============================================================================
-- QUERY 2: Summary Statistics - Age Distribution
-- ============================================================================
-- Count leads by age range and identify those over 65
-- ============================================================================

SELECT 
    COALESCE(c.AGE_RANGE, 'UNKNOWN') as age_range,
    CASE 
        WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 'OVER_65'
        WHEN c.AGE_RANGE IS NULL THEN 'UNKNOWN'
        ELSE 'UNDER_65'
    END as age_category,
    COUNT(*) as lead_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as pct_of_total
FROM `savvy-gtm-analytics.ml_features.January_Leads_Real` ll
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON ll.advisor_crd = c.RIA_CONTACT_CRD_ID
GROUP BY c.AGE_RANGE
ORDER BY 
    CASE 
        WHEN c.AGE_RANGE = 'UNKNOWN' THEN 999
        WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 1
        ELSE 2
    END,
    c.AGE_RANGE;


-- ============================================================================
-- QUERY 3: Count Leads Over 65 (Summary)
-- ============================================================================
-- Quick summary of how many leads are likely over age 65
-- ============================================================================

SELECT 
    COUNT(*) as total_leads,
    COUNT(CASE WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 1 END) as leads_over_65,
    COUNT(CASE WHEN c.AGE_RANGE IS NULL THEN 1 END) as leads_unknown_age,
    COUNT(CASE WHEN c.AGE_RANGE NOT IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') 
               AND c.AGE_RANGE IS NOT NULL THEN 1 END) as leads_under_65,
    ROUND(COUNT(CASE WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 1 END) * 100.0 / COUNT(*), 2) as pct_over_65,
    ROUND(COUNT(CASE WHEN c.AGE_RANGE IS NULL THEN 1 END) * 100.0 / COUNT(*), 2) as pct_unknown_age
FROM `savvy-gtm-analytics.ml_features.January_Leads_Real` ll
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON ll.advisor_crd = c.RIA_CONTACT_CRD_ID;


-- ============================================================================
-- QUERY 4: Leads Over 65 by Tier
-- ============================================================================
-- Breakdown of leads over 65 by score_tier
-- ============================================================================

SELECT 
    ll.score_tier,
    COUNT(*) as total_leads_in_tier,
    COUNT(CASE WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 1 END) as leads_over_65,
    ROUND(COUNT(CASE WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 1 END) * 100.0 / COUNT(*), 2) as pct_over_65_in_tier,
    COUNT(CASE WHEN c.AGE_RANGE IS NULL THEN 1 END) as unknown_age,
    -- Age distribution for over-65 leads
    COUNT(CASE WHEN c.AGE_RANGE = '65-69' THEN 1 END) as age_65_69,
    COUNT(CASE WHEN c.AGE_RANGE = '70-74' THEN 1 END) as age_70_74,
    COUNT(CASE WHEN c.AGE_RANGE = '75-79' THEN 1 END) as age_75_79,
    COUNT(CASE WHEN c.AGE_RANGE IN ('80-84', '85-89', '90-94', '95-99') THEN 1 END) as age_80_plus
FROM `savvy-gtm-analytics.ml_features.January_Leads_Real` ll
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON ll.advisor_crd = c.RIA_CONTACT_CRD_ID
GROUP BY ll.score_tier
ORDER BY leads_over_65 DESC;


-- ============================================================================
-- QUERY 5: Create Enriched Table (Optional - if you want to save results)
-- ============================================================================
-- Uncomment and run this if you want to create a new table with AGE_RANGE
-- ============================================================================

/*
CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.January_Leads_Real_With_Age` AS
SELECT 
    ll.*,
    c.AGE_RANGE,
    CASE 
        WHEN c.AGE_RANGE IN ('65-69', '70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 1
        ELSE 0
    END as is_likely_over_65,
    CASE 
        WHEN c.AGE_RANGE IN ('65-69') THEN '65-69'
        WHEN c.AGE_RANGE IN ('70-74') THEN '70-74'
        WHEN c.AGE_RANGE IN ('75-79') THEN '75-79'
        WHEN c.AGE_RANGE IN ('80-84', '85-89', '90-94', '95-99') THEN '80+'
        WHEN c.AGE_RANGE IS NULL THEN 'UNKNOWN'
        ELSE 'UNDER_65'
    END as age_group
FROM `savvy-gtm-analytics.ml_features.January_Leads_Real` ll
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON ll.advisor_crd = c.RIA_CONTACT_CRD_ID;
*/
