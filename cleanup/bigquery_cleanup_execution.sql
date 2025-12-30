-- ============================================================================
-- BIGQUERY TABLE CLEANUP - Delete Deprecated Tables
-- ============================================================================
-- Date: December 30, 2025
-- Purpose: Remove deprecated V4.0 tables and test tables
-- 
-- ⚠️ WARNING: This will permanently delete tables. Ensure backups exist if needed.
-- 
-- Tables to Delete:
-- 1. v4_daily_scores_v41 - Deprecated (superseded by v4_prospect_scores)
-- 2. v4_lead_scores_v41 - Deprecated (superseded by v4_prospect_scores)
-- 3. test_table - Test table (temporary)
-- 
-- Note: v4_production_features_v41 is a VIEW (not a table), so it's not deleted here.
--       If it needs to be removed, use DROP VIEW instead.
-- ============================================================================

-- Delete deprecated V4.1 tables (superseded by v4_prospect_scores)
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.v4_daily_scores_v41`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.v4_lead_scores_v41`;

-- Delete test tables
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.test_table`;

-- ============================================================================
-- VERIFICATION QUERIES (Run after deletion to verify)
-- ============================================================================

-- Verify deprecated tables are deleted
-- SELECT table_name 
-- FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
-- WHERE table_name IN ('v4_daily_scores_v41', 'v4_lead_scores_v41', 'test_table');
-- Expected: 0 rows

-- Verify production tables still exist
-- SELECT table_name 
-- FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
-- WHERE table_name IN ('v4_prospect_features', 'v4_prospect_scores', 'january_2026_lead_list');
-- Expected: 3 rows

