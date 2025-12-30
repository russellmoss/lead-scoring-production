-- ============================================================================
-- EXCLUDED FIRMS REFERENCE TABLE
-- ============================================================================
-- Purpose: Centralized table of firm exclusion patterns for lead list generation
-- Usage: Referenced by January_2026_Lead_List_V3_V4_Hybrid.sql and future lead lists
-- 
-- To add a new exclusion:
--   INSERT INTO ml_features.excluded_firms VALUES ('%PATTERN%', 'Category', CURRENT_DATE(), 'Reason');
-- 
-- To remove an exclusion:
--   DELETE FROM ml_features.excluded_firms WHERE pattern = '%PATTERN%';
--
-- Created: 2025-12-30
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.excluded_firms` AS

SELECT * FROM UNNEST([
    -- ============================================================================
    -- WIREHOUSES (Major broker-dealers with captive advisors)
    -- ============================================================================
    STRUCT('%J.P. MORGAN%' as pattern, 'Wirehouse' as category, DATE('2025-12-30') as added_date, 'Major wirehouse - captive advisors' as reason),
    STRUCT('%MORGAN STANLEY%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors'),
    STRUCT('%MERRILL%', 'Wirehouse', DATE('2025-12-30'), 'Bank of America subsidiary - captive advisors'),
    STRUCT('%WELLS FARGO%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors'),
    STRUCT('%UBS %', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors'),
    STRUCT('%UBS,%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors (comma variant)'),
    STRUCT('%EDWARD JONES%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors'),
    STRUCT('%AMERIPRISE%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - captive advisors'),
    STRUCT('%RAYMOND JAMES%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse - semi-captive advisors'),
    STRUCT('%GOLDMAN SACHS%', 'Wirehouse', DATE('2025-12-30'), 'Major wirehouse/bank - captive advisors'),
    STRUCT('%CITIGROUP%', 'Wirehouse', DATE('2025-12-30'), 'Major bank - captive advisors'),
    
    -- ============================================================================
    -- LARGE INDEPENDENT BROKER-DEALERS (High volume, low conversion)
    -- ============================================================================
    STRUCT('%LPL FINANCIAL%', 'Large IBD', DATE('2025-12-30'), 'Largest IBD - high volume, low conversion'),
    STRUCT('%COMMONWEALTH%', 'Large IBD', DATE('2025-12-30'), 'Large IBD - low conversion historically'),
    STRUCT('%CETERA%', 'Large IBD', DATE('2025-12-30'), 'Large IBD network - low conversion'),
    STRUCT('%CAMBRIDGE%', 'Large IBD', DATE('2025-12-30'), 'Large IBD - low conversion historically'),
    STRUCT('%OSAIC%', 'Large IBD', DATE('2025-12-30'), 'Large IBD (formerly Advisor Group)'),
    STRUCT('%PRIMERICA%', 'Large IBD', DATE('2025-12-30'), 'MLM-style BD - not target market'),
    
    -- ============================================================================
    -- CUSTODIANS (Not advisory firms)
    -- ============================================================================
    STRUCT('%FIDELITY%', 'Custodian', DATE('2025-12-30'), 'Custodian/retail - not target market'),
    STRUCT('%SCHWAB%', 'Custodian', DATE('2025-12-30'), 'Custodian/retail - not target market'),
    STRUCT('%VANGUARD%', 'Custodian', DATE('2025-12-30'), 'Custodian/retail - not target market'),
    
    -- ============================================================================
    -- INSURANCE COMPANIES & THEIR BROKER-DEALERS
    -- ============================================================================
    STRUCT('%NORTHWESTERN MUTUAL%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%PRUDENTIAL%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%PRUCO%', 'Insurance BD', DATE('2025-12-30'), 'Prudential broker-dealer subsidiary'),
    STRUCT('%STATE FARM%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%ALLSTATE%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%NEW YORK LIFE%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%NYLIFE%', 'Insurance BD', DATE('2025-12-30'), 'New York Life broker-dealer subsidiary'),
    STRUCT('%TRANSAMERICA%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%FARM BUREAU%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%NATIONWIDE%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%LINCOLN FINANCIAL%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%MASS MUTUAL%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents'),
    STRUCT('%MASSMUTUAL%', 'Insurance', DATE('2025-12-30'), 'Insurance company - captive agents (no space)'),
    STRUCT('%ONEAMERICA%', 'Insurance BD', DATE('2025-12-30'), 'OneAmerica Financial - insurance BD'),
    STRUCT('%M HOLDINGS SECURITIES%', 'Insurance BD', DATE('2025-12-30'), 'M Financial Group - insurance distribution'),
    STRUCT('%NUVEEN SECURITIES%', 'Insurance BD', DATE('2025-12-30'), 'TIAA subsidiary - retirement focused'),
    STRUCT('%INSURANCE%', 'Insurance', DATE('2025-12-30'), 'Generic insurance pattern - catches remaining'),
    
    -- ============================================================================
    -- BANK BROKER-DEALERS
    -- ============================================================================
    STRUCT('%BMO NESBITT%', 'Bank BD', DATE('2025-12-30'), 'Bank of Montreal broker-dealer'),
    STRUCT('%NESBITT BURNS%', 'Bank BD', DATE('2025-12-30'), 'BMO Nesbitt Burns variant'),
    
    -- ============================================================================
    -- INTERNAL / PARTNER FIRMS (Do not contact)
    -- ============================================================================
    STRUCT('%SAVVY WEALTH%', 'Internal', DATE('2025-12-30'), 'Internal firm - do not contact'),
    STRUCT('%SAVVY ADVISORS%', 'Internal', DATE('2025-12-30'), 'Internal firm - do not contact'),
    STRUCT('%RITHOLTZ%', 'Partner', DATE('2025-12-30'), 'Partner firm - do not contact')
]);

-- Add primary key comment (BigQuery doesn't enforce PKs but good for documentation)
-- Primary Key: pattern (each pattern should be unique)

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- 1. Count by category
SELECT category, COUNT(*) as patterns
FROM `savvy-gtm-analytics.ml_features.excluded_firms`
GROUP BY category
ORDER BY patterns DESC;

-- 2. Full list
SELECT * FROM `savvy-gtm-analytics.ml_features.excluded_firms`
ORDER BY category, pattern;

