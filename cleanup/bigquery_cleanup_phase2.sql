-- ============================================================================
-- BIGQUERY TABLE CLEANUP - Phase 2: Delete Historical/Analysis Tables
-- ============================================================================
-- Date: December 30, 2025
-- Purpose: Remove historical V3/V4 tables and analysis tables not used in production
-- 
-- ⚠️ WARNING: This will permanently delete tables. Ensure backups exist if needed.
-- 
-- PREREQUISITE: Update v3/sql/phase_7_sga_dashboard.sql to use lead_scores_v3
--               instead of lead_scores_v3_2_12212025 (DONE)
-- ============================================================================

-- ============================================================================
-- PHASE 1: Delete Historical V3 Tables (5 tables)
-- ============================================================================
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scores_v3_2_12212025`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scores_v3_final`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scoring_features_pit_v2`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scoring_splits_v2`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scoring_features`;

-- ============================================================================
-- PHASE 2: Delete Historical V4 Tables (2 tables)
-- ============================================================================
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.v4_features_pit`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.v4_splits`;

-- ============================================================================
-- PHASE 3: Delete Analysis Tables (5 tables)
-- ============================================================================
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.historical_leads_v4_features`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.historical_leads_v4_scores`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.historical_leads_with_outcomes`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.historical_leads_with_tiers`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_optimization_analysis`;

-- ============================================================================
-- PHASE 4: Delete Additional Historical Tables (3 tables)
-- ============================================================================
-- These are old versions that are no longer used
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scoring_splits`;

-- ============================================================================
-- VERIFICATION QUERIES (Run after deletion to verify)
-- ============================================================================

-- Verify deleted tables are gone
-- SELECT table_name 
-- FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
-- WHERE table_name IN (
--     'lead_scores_v3_2_12212025',
--     'lead_scores_v3_final',
--     'lead_scoring_features_pit_v2',
--     'lead_scoring_splits_v2',
--     'lead_scoring_features',
--     'v4_features_pit',
--     'v4_splits',
--     'historical_leads_v4_features',
--     'historical_leads_v4_scores',
--     'historical_leads_with_outcomes',
--     'historical_leads_with_tiers',
--     'lead_optimization_analysis',
--     'lead_scoring_splits'
-- );
-- Expected: 0 rows

-- Verify production tables still exist
-- SELECT table_name
-- FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
-- WHERE table_name IN (
--     'v4_prospect_features',
--     'v4_prospect_scores',
--     'january_2026_lead_list',
--     'excluded_firms',
--     'excluded_firm_crds',
--     'lead_scoring_features_pit',
--     'lead_scores_v3'
-- )
-- ORDER BY table_name;
-- Expected: 7 rows

