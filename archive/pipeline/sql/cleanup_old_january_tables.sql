-- ============================================================================
-- CLEANUP OLD JANUARY 2026 LEAD LIST TABLES
-- ============================================================================
-- Purpose: Remove old lead list tables after migration to new single table
-- Date: 2025-12-30
-- 
-- This script drops the old tables that are being replaced by:
-- ml_features.january_2026_lead_list
-- ============================================================================

-- Drop old lead list tables
-- NOTE: DO NOT drop january_2026_lead_list - that's the NEW table we just created!
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.january_2026_excluded_v3_v4_disagreement`;

-- Verify cleanup (run this separately to check)
-- SELECT table_name 
-- FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
-- WHERE table_name LIKE '%january_2026%'
-- ORDER BY table_name;

