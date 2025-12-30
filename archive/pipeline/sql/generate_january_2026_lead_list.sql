-- ============================================================================
-- GENERATE JANUARY 2026 LEAD LIST (V4.1-R3 PIPELINE)
-- ============================================================================
-- Purpose: Generate the final January 2026 lead list using V4.1-R3 pipeline
-- Date: 2025-12-30
-- 
-- This script:
-- 1. Generates the lead list using the V3 + V4.1-R3 hybrid approach
-- 2. Creates: ml_features.january_2026_lead_list
-- 3. Replaces old tables: january_2026_lead_list_v4, january_2026_lead_list, 
--    january_2026_excluded_v3_v4_disagreement
-- ============================================================================

-- Step 1: Generate the new lead list
-- This executes the main lead list SQL
-- Source: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql

-- Step 2: Clean up old tables (run separately after verifying new table)
-- Source: pipeline/sql/cleanup_old_january_tables.sql

-- ============================================================================
-- EXECUTION INSTRUCTIONS:
-- ============================================================================
-- 1. First, execute: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
--    This creates: ml_features.january_2026_lead_list
--
-- 2. Verify the new table:
--    SELECT COUNT(*) FROM ml_features.january_2026_lead_list;
--    Expected: ~2,800 rows (200 per SGA × 14 SGAs)
--
-- 3. After verification, execute: pipeline/sql/cleanup_old_january_tables.sql
--    This drops the old tables
-- ============================================================================

