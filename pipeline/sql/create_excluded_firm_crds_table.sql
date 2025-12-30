-- ============================================================================
-- EXCLUDED FIRM CRDs TABLE
-- ============================================================================
-- Purpose: Specific firm CRD exclusions (more precise than pattern matching)
-- Usage: For firms we want to exclude by exact CRD, not pattern
-- 
-- Created: 2025-12-30
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.excluded_firm_crds` AS

SELECT * FROM UNNEST([
    STRUCT(318493 as firm_crd, 'Savvy Advisors, Inc.' as firm_name, 'Internal' as category, DATE('2025-12-30') as added_date, 'Internal firm - do not contact' as reason),
    STRUCT(168652, 'Ritholtz Wealth Management', 'Partner', DATE('2025-12-30'), 'Partner firm - do not contact')
]);

-- Verification
SELECT * FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`;

