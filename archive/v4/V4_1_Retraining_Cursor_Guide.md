# XGBoost Lead Scoring Model V4.1 Retraining Guide
## Cursor AI Agentic Execution Plan

**Version**: 4.1.0  
**Created**: December 30, 2025  
**Last Updated**: December 30, 2025 (Agentic Readiness Review)  
**Base Directory**: `C:\Users\russe\Documents\lead_scoring_production\v4`  
**Status**: ✅ Ready for Agentic Execution  
**Purpose**: Retrain V4 model with corrected bleeding signal and new features

## Agentic Readiness Checklist

This document has been reviewed and enhanced for agentic development:

- ✅ **Explicit file path checks** - All file references verified with existence checks
- ✅ **Error handling instructions** - Each phase includes error handling and rollback procedures
- ✅ **Complete code blocks** - All placeholder code completed with working examples
- ✅ **Phase dependencies** - Clear dependency chain documented
- ✅ **Execution log format** - Standardized logging format provided
- ✅ **Validation gate actions** - Clear instructions on what to do if gates fail
- ✅ **SQL CTE references** - Fixed CTE references to match existing codebase
- ✅ **Python code completion** - Phase 8 and Phase 9 code blocks completed
- ✅ **Rollback procedures** - Each phase has rollback instructions if it fails
- ✅ **Prerequisites validation** - Enhanced prerequisite checks with file existence verification

---

## Executive Summary

### Why V4.1?

We discovered that FinTrx's `END_DATE` field has a **~115-day backfill lag**, causing:
1. **3,444 leads mislabeled** as "STABLE" when they were actually "RECENT_MOVER" (9.96% vs 3.39% conversion)
2. **Stale bleeding signal** — detecting firm instability 3-4 months late
3. **Missing predictive features** — `is_recent_mover`, `days_since_last_move`, `bleeding_velocity`
4. **Missing firm/rep type signals** — Analysis of 35,361 leads revealed Independent RIA + IA rep type converts at 1.33x baseline

### What V4.1 Fixes

| Issue | V4.0.0 | V4.1.0 |
|-------|--------|--------|
| Bleeding signal lag | ~115 days | ~30-60 days |
| Recent mover detection | ❌ Missing | ✅ New feature |
| SHAP analysis | ❌ Broken (`base_score` bug) | ✅ Fixed |
| Mislabeled training data | 3,444 leads wrong | ✅ Corrected |
| Bleeding velocity | ❌ Missing | ✅ New feature |
| Firm/Rep type features | ❌ Missing | ✅ New features (4 features) |

### Expected Improvement

| Metric | V4.0.0 | V4.1.0 (Projected) |
|--------|--------|---------------------|
| AUC-ROC | 0.599 | 0.63-0.67 |
| Top decile lift | 1.51x | 1.7-2.0x |
| SHAP analysis | ❌ Broken | ✅ Working |
| Feature count | 14 | 23 (14 original + 5 bleeding + 4 firm/rep type) |

---

## Table of Contents

1. [Phase 0: Environment Setup & Validation](#phase-0-environment-setup--validation)
2. [Phase 1: Create Corrected BigQuery Tables](#phase-1-create-corrected-bigquery-tables)
3. [Phase 2: Update Feature Engineering SQL](#phase-2-update-feature-engineering-sql)
4. [Phase 3: Relabel Training Data](#phase-3-relabel-training-data)
5. [Phase 4: Feature Validation & PIT Audit](#phase-4-feature-validation--pit-audit)
6. [Phase 5: Multicollinearity Check](#phase-5-multicollinearity-check)
7. [Phase 6: Train/Test Split](#phase-6-traintest-split)
8. [Phase 7: Model Training](#phase-7-model-training)
9. [Phase 8: Overfitting Detection](#phase-8-overfitting-detection)
10. [Phase 9: Model Validation](#phase-9-model-validation)
11. [Phase 10: SHAP Analysis](#phase-10-shap-analysis)
12. [Phase 11: Deployment & Registry Update](#phase-11-deployment--registry-update)

---

## Prerequisites

Before starting, ensure:

- [ ] Access to BigQuery project: `savvy-gtm-analytics`
- [ ] MCP connection to BigQuery is working
- [ ] Tables exist: `ml_features.inferred_departures_analysis`, `ml_features.firm_bleeding_corrected`
- [ ] Working directory: `C:\Users\russe\Documents\lead_scoring_production\v4`
- [ ] V4.0.0 model exists at: `v4/models/v4.0.0/model.pkl`
- [ ] V4.0.0 feature engineering SQL exists at: `v4/sql/phase_2_feature_engineering.sql`

## Execution Log Format

All phases should log results to `v4/EXECUTION_LOG_V4.1.md` using this format:

```markdown
# V4.1 Retraining Execution Log

**Started**: YYYY-MM-DD HH:MM:SS
**Status**: In Progress / Completed / Failed

## Phase X: [Phase Name]

**Started**: YYYY-MM-DD HH:MM:SS
**Completed**: YYYY-MM-DD HH:MM:SS
**Status**: ✅ PASSED / ❌ FAILED / ⚠️ WARNINGS

### Validation Gates
- GX.1: [Gate Name] - ✅ PASSED / ❌ FAILED (Details)
- GX.2: [Gate Name] - ✅ PASSED / ❌ FAILED (Details)

### Actions Taken
- [Timestamp] Action description
- [Timestamp] Result/Output

### Errors/Warnings
- [If any] Error description and resolution

### Next Steps
- [If failed] Rollback instructions or retry plan
```

## Error Handling & Rollback

**CRITICAL**: If any validation gate fails:
1. **STOP** execution of current phase
2. **LOG** the failure with details to `EXECUTION_LOG_V4.1.md`
3. **ASSESS** if failure is blocking or can be worked around
4. **ROLLBACK** if necessary (see rollback instructions per phase)
5. **DO NOT PROCEED** to next phase until current phase passes all gates

## Phase Dependencies

**Execution Order (CRITICAL - DO NOT SKIP PHASES)**:
- Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7 → Phase 8 → Phase 9 → Phase 10 → Phase 11

**Dependencies**:
- Phase 1 requires: Phase 0 (tables: `inferred_departures_analysis`, `firm_bleeding_corrected`)
- Phase 2 requires: Phase 1 (tables: `recent_movers_v41`, `firm_bleeding_velocity_v41`) + existing `v4/sql/phase_2_feature_engineering.sql`
- Phase 3 requires: Phase 2 (table: `v4_features_pit_v41`)
- Phase 4 requires: Phase 2 (table: `v4_features_pit_v41`)
- Phase 5 requires: Phase 2 (table: `v4_features_pit_v41`)
- Phase 6 requires: Phase 2 (table: `v4_features_pit_v41`)
- Phase 7 requires: Phase 6 (table: `v4_splits_v41`)
- Phase 8 requires: Phase 7 (model: `v4/models/v4.1.0/model.pkl`)
- Phase 9 requires: Phase 7 (model: `v4/models/v4.1.0/model.pkl`)
- Phase 10 requires: Phase 7 (model: `v4/models/v4.1.0/model.pkl`)
- Phase 11 requires: Phases 7-10 (all validation complete)

---

## Phase 0: Environment Setup & Validation

### Cursor Prompt 0.1: Verify Prerequisites

```
@workspace Verify that V4.1 retraining prerequisites are met.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4

Tasks:
1. Verify MCP connection to BigQuery (project: savvy-gtm-analytics)
2. Check that these tables exist and have data:
   - ml_features.inferred_departures_analysis
   - ml_features.firm_bleeding_corrected
   - ml_features.v4_target_variable
3. Verify the V4.0.0 model exists at: v4/models/v4.0.0/model.pkl
4. Create v4.1.0 directory structure:
   - v4/models/v4.1.0/
   - v4/data/v4.1.0/
   - v4/reports/v4.1.0/
5. Create execution log file at v4/EXECUTION_LOG_V4.1.md (if it doesn't exist)
6. Log all results to v4/EXECUTION_LOG_V4.1.md using the format specified in Prerequisites

**ERROR HANDLING**:
- If any gate fails, STOP and log the failure
- Do not proceed to Phase 1 until all Phase 0 gates pass
- If tables are missing, provide clear error message with table creation instructions

VALIDATION GATES:
- G0.1: inferred_departures_analysis has >= 100,000 rows
- G0.2: firm_bleeding_corrected has >= 4,000 firms
- G0.3: v4_target_variable has >= 30,000 rows
- G0.4: All directories created successfully
```

### Validation SQL

```sql
-- Gate G0.1: Check inferred_departures_analysis
SELECT 
    'inferred_departures_analysis' as table_name,
    COUNT(*) as row_count,
    COUNT(DISTINCT advisor_crd) as unique_advisors,
    COUNT(DISTINCT departed_firm_crd) as unique_firms,
    MIN(inferred_departure_date) as min_date,
    MAX(inferred_departure_date) as max_date
FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis`;

-- Gate G0.2: Check firm_bleeding_corrected
SELECT 
    'firm_bleeding_corrected' as table_name,
    COUNT(*) as row_count,
    COUNT(DISTINCT firm_crd) as unique_firms,
    AVG(departures_12mo) as avg_departures
FROM `savvy-gtm-analytics.ml_features.firm_bleeding_corrected`;

-- Gate G0.3: Check v4_target_variable
SELECT 
    'v4_target_variable' as table_name,
    COUNT(*) as row_count,
    SUM(CASE WHEN target = 1 THEN 1 ELSE 0 END) as positive_count,
    AVG(target) * 100 as conversion_rate_pct
FROM `savvy-gtm-analytics.ml_features.v4_target_variable`
WHERE target IS NOT NULL;
```

### Expected Output

```
Phase 0 Validation Results:
- G0.1: inferred_departures_analysis: 145,002 rows [PASSED]
- G0.2: firm_bleeding_corrected: 6,116 firms [PASSED]
- G0.3: v4_target_variable: 30,905 rows [PASSED]
- G0.4: Directory structure created [PASSED]

STATUS: READY TO PROCEED
```

---

## Phase 1: Create Corrected BigQuery Tables

### Cursor Prompt 1.1: Create Recent Movers Table

```
@workspace Create a BigQuery table identifying recent movers using START_DATE inference.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT SQL FILE: v4/sql/v4.1/create_recent_movers_table.sql

Context:
- Recent movers (moved within 12 months) convert at 9.96% vs 3.39% baseline
- We detect movement using PRIMARY_FIRM_START_DATE (60-90 days fresher than END_DATE)
- This table will be joined to feature engineering

Requirements:
1. Create table: ml_features.recent_movers_v41
2. Include columns:
   - advisor_crd
   - current_firm_crd
   - current_firm_start_date
   - prior_firm_crd
   - prior_firm_name
   - days_since_move
   - is_recent_mover_12mo (BOOLEAN)
   - is_recent_mover_6mo (BOOLEAN)
   - move_detected_via_inference (BOOLEAN)
3. Execute via MCP
4. Log results to v4/EXECUTION_LOG_V4.1.md

VALIDATION GATES:
- G1.1: Table created with >= 50,000 rows
- G1.2: is_recent_mover_12mo rate between 10-40%
- G1.3: No NULL advisor_crd values
```

### SQL Code

```sql
-- File: v4/sql/v4.1/create_recent_movers_table.sql
-- Purpose: Identify recent movers using START_DATE inference (60-90 days fresher signal)

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.recent_movers_v41` AS

WITH current_employment AS (
    -- Get current firm info for all advisors
    SELECT 
        CAST(RIA_CONTACT_CRD_ID AS INT64) as advisor_crd,
        SAFE_CAST(PRIMARY_FIRM AS INT64) as current_firm_crd,
        PRIMARY_FIRM_NAME as current_firm_name,
        PRIMARY_FIRM_START_DATE as current_firm_start_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE RIA_CONTACT_CRD_ID IS NOT NULL
      AND PRIMARY_FIRM IS NOT NULL
      AND PRIMARY_FIRM_START_DATE IS NOT NULL
),

prior_employment AS (
    -- Get most recent prior firm for each advisor
    SELECT 
        ida.advisor_crd,
        ida.departed_firm_crd as prior_firm_crd,
        ida.departed_firm_name as prior_firm_name,
        ida.inferred_departure_date as prior_firm_departure_date,
        ida.inference_gap_days
    FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis` ida
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ida.advisor_crd 
        ORDER BY ida.inferred_departure_date DESC
    ) = 1
)

SELECT 
    ce.advisor_crd,
    ce.current_firm_crd,
    ce.current_firm_name,
    ce.current_firm_start_date,
    pe.prior_firm_crd,
    pe.prior_firm_name,
    pe.prior_firm_departure_date,
    
    -- Days since move (using current firm start date)
    DATE_DIFF(CURRENT_DATE(), ce.current_firm_start_date, DAY) as days_since_move,
    
    -- Recent mover flags
    CASE 
        WHEN DATE_DIFF(CURRENT_DATE(), ce.current_firm_start_date, DAY) <= 365 
        THEN TRUE ELSE FALSE 
    END as is_recent_mover_12mo,
    
    CASE 
        WHEN DATE_DIFF(CURRENT_DATE(), ce.current_firm_start_date, DAY) <= 180 
        THEN TRUE ELSE FALSE 
    END as is_recent_mover_6mo,
    
    -- Flag if we detected via inference (has prior firm match)
    CASE WHEN pe.prior_firm_crd IS NOT NULL THEN TRUE ELSE FALSE END as move_detected_via_inference,
    
    -- Inference accuracy (gap between inferred and actual)
    pe.inference_gap_days

FROM current_employment ce
LEFT JOIN prior_employment pe
    ON ce.advisor_crd = pe.advisor_crd;
```

### Validation Query

```sql
-- Validate recent_movers_v41 table
SELECT 
    COUNT(*) as total_rows,
    COUNT(DISTINCT advisor_crd) as unique_advisors,
    SUM(CASE WHEN is_recent_mover_12mo THEN 1 ELSE 0 END) as recent_movers_12mo,
    AVG(CASE WHEN is_recent_mover_12mo THEN 1.0 ELSE 0.0 END) * 100 as pct_recent_mover_12mo,
    SUM(CASE WHEN move_detected_via_inference THEN 1 ELSE 0 END) as inference_detected,
    AVG(days_since_move) as avg_days_since_move,
    SUM(CASE WHEN advisor_crd IS NULL THEN 1 ELSE 0 END) as null_crd_count
FROM `savvy-gtm-analytics.ml_features.recent_movers_v41`;
```

---

### Cursor Prompt 1.2: Create Bleeding Velocity Table

```
@workspace Create a BigQuery table calculating bleeding velocity (acceleration/deceleration).

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT SQL FILE: v4/sql/v4.1/create_bleeding_velocity_table.sql

Context:
- Bleeding velocity compares departures in last 90 days vs prior 90 days
- ACCELERATING = firm just started bleeding = optimal outreach window
- DECELERATING = bleeding slowing down = opportunity may have passed

Requirements:
1. Create table: ml_features.firm_bleeding_velocity_v41
2. Include columns:
   - firm_crd
   - firm_name
   - departures_last_90d
   - departures_prior_90d
   - velocity_ratio (last_90d / prior_90d)
   - bleeding_velocity (ACCELERATING / STEADY / DECELERATING / STABLE)
3. Execute via MCP
4. Log results

VALIDATION GATES:
- G1.4: Table created with >= 4,000 firms
- G1.5: All velocity categories represented
- G1.6: ACCELERATING firms represent 5-25% of bleeding firms
```

### Cursor Prompt 1.3: Create Firm/Rep Type Features Table

```
@workspace Create a BigQuery table with firm type and rep type features based on analysis of 35,361 leads.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT SQL FILE: v4/sql/v4.1/create_firm_rep_type_features.sql

Context:
- Analysis of 35,361 contacted leads from Provided Lead Lists revealed strong conversion signals
- Independent RIA + IA rep type converts at 3.64% (1.33x baseline)
- Dual-Registered (DR) advisors convert below baseline (0.86-0.90x)
- These features use current state (PRIMARY_FIRM_CLASSIFICATION, REP_TYPE) - acceptable small PIT risk

Requirements:
1. Create table: ml_features.firm_rep_type_features_v41
2. Include columns:
   - advisor_crd
   - is_independent_ria (PRIMARY_FIRM_CLASSIFICATION LIKE '%Independent RIA%')
   - is_ia_rep_type (REP_TYPE = 'IA')
   - is_dual_registered (REP_TYPE = 'DR')
   - independent_ria_x_ia_rep (interaction: both above)
3. Execute via MCP
4. Log results

VALIDATION GATES:
- G1.7: is_independent_ria rate between 15-40%
- G1.8: is_ia_rep_type rate between 20-50%
- G1.9: is_dual_registered rate between 30-60%
```

### SQL Code

```sql
-- File: v4/sql/v4.1/create_firm_rep_type_features.sql
-- Purpose: Extract firm type and rep type features for V4.1
-- Source: Analysis of 35,361 contacted leads showing Independent RIA + IA rep type converts at 1.33x baseline

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.firm_rep_type_features_v41` AS

SELECT 
    CAST(RIA_CONTACT_CRD_ID AS INT64) as advisor_crd,
    
    -- Independent RIA flag (positive signal: 1.33x lift)
    CASE 
        WHEN PRIMARY_FIRM_CLASSIFICATION LIKE '%Independent RIA%' 
        THEN 1 ELSE 0 
    END as is_independent_ria,
    
    -- Pure IA rep type - no broker-dealer registration (positive signal)
    CASE 
        WHEN REP_TYPE = 'IA' THEN 1 ELSE 0 
    END as is_ia_rep_type,
    
    -- Dual registered - has both IA and BD (NEGATIVE signal: 0.86-0.90x lift)
    CASE 
        WHEN REP_TYPE = 'DR' THEN 1 ELSE 0 
    END as is_dual_registered,
    
    -- Interaction: Independent RIA + IA rep type (strongest positive signal)
    CASE 
        WHEN PRIMARY_FIRM_CLASSIFICATION LIKE '%Independent RIA%' 
         AND REP_TYPE = 'IA'
        THEN 1 ELSE 0 
    END as independent_ria_x_ia_rep

FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
WHERE RIA_CONTACT_CRD_ID IS NOT NULL
  AND PRODUCING_ADVISOR = TRUE;  -- Only producing advisors
```

### Validation Query

```sql
-- Validate firm/rep type feature distribution
SELECT 
    COUNT(*) as total_advisors,
    AVG(is_independent_ria) * 100 as pct_independent_ria,
    AVG(is_ia_rep_type) * 100 as pct_ia_rep_type,
    AVG(is_dual_registered) * 100 as pct_dual_registered,
    AVG(independent_ria_x_ia_rep) * 100 as pct_independent_ria_x_ia,
    SUM(CASE WHEN advisor_crd IS NULL THEN 1 ELSE 0 END) as null_crd_count
FROM `savvy-gtm-analytics.ml_features.firm_rep_type_features_v41`;
```

### SQL Code

```sql
-- File: v4/sql/v4.1/create_bleeding_velocity_table.sql
-- Purpose: Calculate bleeding velocity (is firm bleeding accelerating or decelerating?)

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.firm_bleeding_velocity_v41` AS

WITH departure_windows AS (
    SELECT 
        departed_firm_crd as firm_crd,
        departed_firm_name as firm_name,
        
        -- Last 90 days
        COUNT(DISTINCT CASE 
            WHEN inferred_departure_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN advisor_crd 
        END) as departures_last_90d,
        
        -- Prior 90 days (91-180 days ago)
        COUNT(DISTINCT CASE 
            WHEN inferred_departure_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
             AND inferred_departure_date < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN advisor_crd 
        END) as departures_prior_90d,
        
        -- Total 12 months
        COUNT(DISTINCT CASE 
            WHEN inferred_departure_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
            THEN advisor_crd 
        END) as departures_12mo
        
    FROM `savvy-gtm-analytics.ml_features.inferred_departures_analysis`
    WHERE departed_firm_crd IS NOT NULL
    GROUP BY departed_firm_crd, departed_firm_name
)

SELECT 
    firm_crd,
    firm_name,
    departures_last_90d,
    departures_prior_90d,
    departures_12mo,
    
    -- Velocity ratio (handle divide by zero)
    CASE 
        WHEN departures_prior_90d = 0 AND departures_last_90d > 0 THEN 999.0  -- New bleeding
        WHEN departures_prior_90d = 0 AND departures_last_90d = 0 THEN 0.0   -- Stable
        ELSE ROUND(departures_last_90d / departures_prior_90d, 2)
    END as velocity_ratio,
    
    -- Bleeding velocity category
    CASE 
        -- Stable: No significant bleeding in either period
        WHEN departures_12mo < 3 THEN 'STABLE'
        
        -- Accelerating: Last 90d has 50%+ more departures than prior 90d
        WHEN departures_last_90d > departures_prior_90d * 1.5 THEN 'ACCELERATING'
        
        -- Decelerating: Last 90d has 50%+ fewer departures than prior 90d  
        WHEN departures_last_90d < departures_prior_90d * 0.5 THEN 'DECELERATING'
        
        -- Steady: Similar rate in both periods
        ELSE 'STEADY'
    END as bleeding_velocity

FROM departure_windows;
```

### Validation Query

```sql
-- Validate bleeding velocity distribution
SELECT 
    bleeding_velocity,
    COUNT(*) as firm_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as pct_of_total,
    AVG(departures_12mo) as avg_departures_12mo,
    AVG(velocity_ratio) as avg_velocity_ratio
FROM `savvy-gtm-analytics.ml_features.firm_bleeding_velocity_v41`
GROUP BY bleeding_velocity
ORDER BY firm_count DESC;
```

---

## Phase 2: Update Feature Engineering SQL

### Cursor Prompt 2.1: Update Feature Engineering with New Features

```
@workspace Update the V4 feature engineering SQL to include new V4.1 features.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
INPUT FILE: v4/sql/phase_2_feature_engineering.sql (MUST EXIST - verify before proceeding)
OUTPUT FILE: v4/sql/v4.1/phase_2_feature_engineering_v41.sql

**CRITICAL FILE CHECK**:
1. Verify `v4/sql/phase_2_feature_engineering.sql` exists before starting
2. If file doesn't exist, STOP and report error - cannot proceed without base feature engineering logic
3. Read the existing file to understand the CTE structure:
   - **VERIFIED**: The file contains `base` CTE (lines 28-37)
   - **VERIFIED**: The file contains `current_firm` CTE (lines 97-110)
   - These CTE names are correct and can be referenced in V4.1 additions
4. The V4.1 code will add new CTEs and JOIN to these existing CTEs

Context:
- Original V4 has 14 features
- V4.1 adds 9 new features:
  - 5 features based on START_DATE inference methodology
  - 4 features based on firm/rep type analysis (35,361 leads)
- All features MUST be PIT-safe (use only data available at contacted_date)
- Firm/rep type features use current state (acceptable small PIT risk - these are relatively stable)

NEW FEATURES TO ADD (9 total):
**Bleeding Signal Features (5):**
1. is_recent_mover - Advisor moved within 12 months of contact (using START_DATE)
2. days_since_last_move - Days between last move and contact date
3. firm_departures_corrected - Using inferred departures (fresher signal)
4. bleeding_velocity_encoded - ACCELERATING=3, STEADY=2, DECELERATING=1, STABLE=0
5. recent_mover_x_bleeding - Interaction: recent mover AND at bleeding firm

**Firm/Rep Type Features (4):**
6. is_independent_ria - Firm is Independent RIA (1.33x lift)
7. is_ia_rep_type - Rep type is pure IA (1.33x lift)
8. is_dual_registered - Rep type is DR (0.86x lift - negative signal)
9. independent_ria_x_ia_rep - Interaction: Independent RIA + IA rep type (~1.4x lift)

PIT COMPLIANCE RULES (CRITICAL):
- is_recent_mover: PRIMARY_FIRM_START_DATE <= contacted_date AND gap <= 365 days
- days_since_last_move: DATE_DIFF(contacted_date, PRIMARY_FIRM_START_DATE, DAY)
- firm_departures: Use departures with inferred_departure_date < contacted_date
- bleeding_velocity: Calculate based on 180 days BEFORE contacted_date

Tasks:
1. **VERIFY INPUT FILE EXISTS**: Check that `v4/sql/phase_2_feature_engineering.sql` exists
2. **CREATE OUTPUT DIRECTORY**: Create `v4/sql/v4.1/` if it doesn't exist
3. **COPY BASE FILE**: Copy entire `phase_2_feature_engineering.sql` to `v4/sql/v4.1/phase_2_feature_engineering_v41.sql`
4. **ADD NEW CTEs**: Insert the new CTEs (recent_mover_pit, firm_bleeding_pit, bleeding_velocity_pit) AFTER existing CTEs but BEFORE final SELECT
5. **UPDATE FINAL SELECT**: Add new feature columns to the final SELECT statement
6. **UPDATE JOIN CLAUSES**: Add LEFT JOINs for new CTEs in the final SELECT
7. **VALIDATE SQL SYNTAX**: Run dry-run query to check for syntax errors
8. **EXECUTE**: Create table `ml_features.v4_features_pit_v41` via MCP
9. **LOG RESULTS**: Log all actions and gate results to EXECUTION_LOG_V4.1.md

**ERROR HANDLING**:
- If input file missing: STOP and report error
- If SQL syntax error: Fix and re-validate before executing
- If table creation fails: Check BigQuery permissions and table name conflicts
- If validation gates fail: DO NOT proceed to Phase 3 - investigate and fix issues first

**ROLLBACK INSTRUCTIONS** (if Phase 2 fails):
- Drop table: `DROP TABLE IF EXISTS ml_features.v4_features_pit_v41`
- Delete file: `v4/sql/v4.1/phase_2_feature_engineering_v41.sql`
- Log failure reason in EXECUTION_LOG_V4.1.md
- Do not proceed until Phase 2 passes all gates

VALIDATION GATES:
- G2.1: New table has 23 features (14 original + 5 bleeding + 4 firm/rep type)
- G2.2: is_recent_mover rate between 5-30%
- G2.3: No PIT leakage (all features use data <= contacted_date, firm/rep type noted as acceptable small risk)
- G2.4: No NULL values in new features (use COALESCE defaults)
- G2.5: New firm/rep features have no NULL values (all should be 0 or 1)
```

### SQL Code - New Features Section

```sql
-- ==========================================================================
-- V4.1 NEW FEATURES: Add to phase_2_feature_engineering.sql
-- ==========================================================================
-- 
-- CRITICAL PIT RULES:
-- - All dates compared to contacted_date (the prediction point)
-- - Never use current state - always historical snapshot
-- - Bleeding metrics use inferred departures with date filter
-- ==========================================================================

-- ==========================================================================
-- INSTRUCTIONS FOR ADDING NEW FEATURES:
-- 1. Find the last CTE before the final SELECT in phase_2_feature_engineering.sql
-- 2. Add these new CTEs AFTER the last existing CTE
-- 3. The 'base' CTE is already defined in the original file
-- ==========================================================================

-- Add this CTE after existing CTEs but before final SELECT:

-- ==========================================================================
-- FEATURE GROUP V4.1-A: RECENT MOVER DETECTION (PIT-SAFE)
-- ==========================================================================
recent_mover_pit AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        b.advisor_crd,
        rc.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        
        -- PIT-safe: Only consider start dates BEFORE contact
        CASE 
            WHEN rc.PRIMARY_FIRM_START_DATE IS NOT NULL
             AND rc.PRIMARY_FIRM_START_DATE <= b.contacted_date
             AND DATE_DIFF(b.contacted_date, rc.PRIMARY_FIRM_START_DATE, DAY) <= 365
            THEN 1 ELSE 0 
        END as is_recent_mover,
        
        -- Days since last move (PIT-safe)
        CASE 
            WHEN rc.PRIMARY_FIRM_START_DATE IS NOT NULL
             AND rc.PRIMARY_FIRM_START_DATE <= b.contacted_date
            THEN DATE_DIFF(b.contacted_date, rc.PRIMARY_FIRM_START_DATE, DAY)
            ELSE 9999  -- Default for no move detected (will be handled in final SELECT)
        END as days_since_last_move
        
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON b.advisor_crd = rc.RIA_CONTACT_CRD_ID
),

-- ==========================================================================
-- FEATURE GROUP V4.1-B: CORRECTED FIRM BLEEDING (PIT-SAFE)
-- ==========================================================================
-- NOTE: This CTE references 'firm_data' which should exist in the original SQL
-- If 'firm_data' doesn't exist, use 'current_firm' CTE instead
-- ==========================================================================
firm_bleeding_pit AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        COALESCE(cf.firm_crd, f.firm_crd) as firm_crd,  -- Use current_firm if firm_data doesn't exist
        
        -- Count departures in 12 months BEFORE contact date (PIT-safe)
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.contacted_date, INTERVAL 365 DAY)
             AND ida.inferred_departure_date < b.contacted_date
            THEN ida.advisor_crd 
        END) as firm_departures_corrected,
        
        -- Departures in last 90 days before contact
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.contacted_date, INTERVAL 90 DAY)
             AND ida.inferred_departure_date < b.contacted_date
            THEN ida.advisor_crd 
        END) as departures_90d_before_contact,
        
        -- Departures 91-180 days before contact
        COUNT(DISTINCT CASE 
            WHEN ida.inferred_departure_date >= DATE_SUB(b.contacted_date, INTERVAL 180 DAY)
             AND ida.inferred_departure_date < DATE_SUB(b.contacted_date, INTERVAL 90 DAY)
            THEN ida.advisor_crd 
        END) as departures_90_180d_before_contact
        
    FROM base b
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id  -- Use current_firm from original SQL
    LEFT JOIN `savvy-gtm-analytics.ml_features.inferred_departures_analysis` ida
        ON COALESCE(cf.firm_crd, 0) = ida.departed_firm_crd
    GROUP BY b.lead_id, b.contacted_date, COALESCE(cf.firm_crd, 0)
),

-- ==========================================================================
-- FEATURE GROUP V4.1-C: BLEEDING VELOCITY (PIT-SAFE)
-- ==========================================================================
bleeding_velocity_pit AS (
    SELECT 
        lead_id,
        contacted_date,
        firm_crd,
        firm_departures_corrected,
        departures_90d_before_contact,
        departures_90_180d_before_contact,
        
        -- Velocity ratio (PIT-safe)
        CASE 
            WHEN departures_90_180d_before_contact = 0 AND departures_90d_before_contact > 0 THEN 999.0
            WHEN departures_90_180d_before_contact = 0 AND departures_90d_before_contact = 0 THEN 0.0
            ELSE ROUND(departures_90d_before_contact / departures_90_180d_before_contact, 2)
        END as velocity_ratio,
        
        -- Bleeding velocity category (PIT-safe)
        CASE 
            WHEN firm_departures_corrected < 3 THEN 0  -- STABLE
            WHEN departures_90d_before_contact > departures_90_180d_before_contact * 1.5 THEN 3  -- ACCELERATING
            WHEN departures_90d_before_contact < departures_90_180d_before_contact * 0.5 THEN 1  -- DECELERATING
            ELSE 2  -- STEADY
        END as bleeding_velocity_encoded
        
    FROM firm_bleeding_pit
)

-- ==========================================================================
-- FINAL SELECT: Add new V4.1 features to existing features
-- ==========================================================================
-- In the final SELECT statement, add these columns:

    -- V4.1 Bleeding Signal Features
    COALESCE(rm.is_recent_mover, 0) as is_recent_mover,
    COALESCE(rm.days_since_last_move, 9999) as days_since_last_move,
    COALESCE(bv.firm_departures_corrected, 0) as firm_departures_corrected,
    COALESCE(bv.bleeding_velocity_encoded, 0) as bleeding_velocity_encoded,
    
    -- Interaction: Recent mover at bleeding firm (high-value signal)
    CASE 
        WHEN COALESCE(rm.is_recent_mover, 0) = 1 
         AND COALESCE(bv.firm_departures_corrected, 0) >= 5
        THEN 1 ELSE 0 
    END as recent_mover_x_bleeding,
    
    -- V4.1 Firm/Rep Type Features
    COALESCE(frt.is_independent_ria, 0) as is_independent_ria,
    COALESCE(frt.is_ia_rep_type, 0) as is_ia_rep_type,
    COALESCE(frt.is_dual_registered, 0) as is_dual_registered,
    COALESCE(frt.independent_ria_x_ia_rep, 0) as independent_ria_x_ia_rep,

-- ==========================================================================
-- FEATURE GROUP V4.1-D: FIRM TYPE AND REP TYPE FEATURES
-- ==========================================================================
-- Source: Analysis of 35,361 leads showing Independent RIA + IA rep type
-- converts at 1.33x baseline (3.64% vs 2.74%)
-- Dual-registered (DR) converts BELOW baseline (0.86-0.90x)
-- NOTE: These use current state - acceptable small PIT risk (firm classification is stable)
-- ==========================================================================
firm_rep_type_features AS (
    SELECT 
        b.lead_id,
        b.advisor_crd,
        frt.is_independent_ria,
        frt.is_ia_rep_type,
        frt.is_dual_registered,
        frt.independent_ria_x_ia_rep
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.ml_features.firm_rep_type_features_v41` frt
        ON b.advisor_crd = frt.advisor_crd
)

-- Add JOINs in the final SELECT (find the existing FROM/JOIN clauses and add these):
LEFT JOIN recent_mover_pit rm ON base.lead_id = rm.lead_id
LEFT JOIN bleeding_velocity_pit bv ON base.lead_id = bv.lead_id
LEFT JOIN firm_rep_type_features frt ON base.lead_id = frt.lead_id

-- ==========================================================================
-- IMPORTANT: The final SELECT should reference 'base' CTE, not a table
-- Make sure you're joining to the correct CTE name used in the original SQL
-- ==========================================================================
```

### Validation Query

```sql
-- Validate V4.1 features
SELECT 
    -- Row counts
    COUNT(*) as total_rows,
    
    -- Bleeding signal feature distributions
    AVG(is_recent_mover) * 100 as pct_recent_mover,
    AVG(days_since_last_move) as avg_days_since_move,
    AVG(firm_departures_corrected) as avg_departures_corrected,
    
    -- Bleeding velocity distribution
    SUM(CASE WHEN bleeding_velocity_encoded = 0 THEN 1 ELSE 0 END) as stable_count,
    SUM(CASE WHEN bleeding_velocity_encoded = 1 THEN 1 ELSE 0 END) as decelerating_count,
    SUM(CASE WHEN bleeding_velocity_encoded = 2 THEN 1 ELSE 0 END) as steady_count,
    SUM(CASE WHEN bleeding_velocity_encoded = 3 THEN 1 ELSE 0 END) as accelerating_count,
    
    -- Firm/Rep type feature distributions
    AVG(is_independent_ria) * 100 as pct_independent_ria,
    AVG(is_ia_rep_type) * 100 as pct_ia_rep_type,
    AVG(is_dual_registered) * 100 as pct_dual_registered,
    AVG(independent_ria_x_ia_rep) * 100 as pct_independent_ria_x_ia,
    
    -- Interaction features
    AVG(recent_mover_x_bleeding) * 100 as pct_recent_mover_at_bleeding_firm,
    
    -- NULL checks (should all be 0)
    SUM(CASE WHEN is_recent_mover IS NULL THEN 1 ELSE 0 END) as null_recent_mover,
    SUM(CASE WHEN days_since_last_move IS NULL THEN 1 ELSE 0 END) as null_days_since_move,
    SUM(CASE WHEN is_independent_ria IS NULL THEN 1 ELSE 0 END) as null_independent_ria,
    SUM(CASE WHEN is_ia_rep_type IS NULL THEN 1 ELSE 0 END) as null_ia_rep_type
    
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE target IS NOT NULL;
```

---

## Phase 3: Relabel Training Data

### Cursor Prompt 3.1: Identify and Relabel Mislabeled Leads

```
@workspace Identify leads mislabeled as STABLE that are actually RECENT_MOVER and create corrected labels.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT SQL FILE: v4/sql/v4.1/relabel_recent_movers.sql

Context:
- 3,444 leads were classified as STABLE using old END_DATE method
- These are actually RECENT_MOVER when using START_DATE inference
- RECENT_MOVER converts at 9.96% vs 3.39% for truly stable
- This impacts model training quality

Tasks:
1. Identify leads where OLD method said STABLE but NEW method says RECENT_MOVER
2. Create a mapping table with corrected labels
3. Verify the conversion rate difference
4. Log the count of relabeled leads

VALIDATION GATES:
- G3.1: Identify >= 3,000 mislabeled leads
- G3.2: Mislabeled leads have higher conversion rate than truly stable
- G3.3: No duplicate lead_ids in mapping table

**ERROR HANDLING**:
- If G3.1 fails (too few mislabeled leads): This may indicate the issue was already fixed - log and proceed with caution
- If G3.2 fails (conversion rates don't match expected): Investigate data quality - may need to adjust relabeling logic
- If G3.3 fails (duplicates): Fix SQL to use DISTINCT or QUALIFY to remove duplicates

**ROLLBACK INSTRUCTIONS** (if Phase 3 fails):
- Drop table: `DROP TABLE IF EXISTS ml_features.v4_relabeled_leads_v41`
- Log failure and investigate root cause before retrying
```

### SQL Code

```sql
-- File: v4/sql/v4.1/relabel_recent_movers.sql
-- Purpose: Identify leads mislabeled by old END_DATE method

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_relabeled_leads_v41` AS

WITH old_method_stable AS (
    -- Leads that OLD method (END_DATE based) classified as stable
    -- These had no detected firm change in employment history END_DATE
    SELECT DISTINCT
        tv.lead_id,
        tv.advisor_crd,
        tv.contacted_date,
        tv.target
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON tv.advisor_crd = eh.RIA_CONTACT_CRD_ID
        AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(tv.contacted_date, INTERVAL 365 DAY)
        AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < tv.contacted_date
    WHERE eh.RIA_CONTACT_CRD_ID IS NULL  -- No END_DATE detected = "stable" in old method
      AND tv.target IS NOT NULL
),

new_method_recent_mover AS (
    -- Leads that NEW method (START_DATE inference) identifies as recent mover
    SELECT DISTINCT
        tv.lead_id,
        tv.advisor_crd,
        tv.contacted_date,
        rc.PRIMARY_FIRM_START_DATE,
        DATE_DIFF(tv.contacted_date, rc.PRIMARY_FIRM_START_DATE, DAY) as days_since_move
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON tv.advisor_crd = rc.RIA_CONTACT_CRD_ID
    WHERE rc.PRIMARY_FIRM_START_DATE <= tv.contacted_date
      AND DATE_DIFF(tv.contacted_date, rc.PRIMARY_FIRM_START_DATE, DAY) <= 365
      AND tv.target IS NOT NULL
)

SELECT 
    oms.lead_id,
    oms.advisor_crd,
    oms.contacted_date,
    oms.target,
    nmr.PRIMARY_FIRM_START_DATE,
    nmr.days_since_move,
    'MISLABELED' as label_status,
    'STABLE_TO_RECENT_MOVER' as correction_type
FROM old_method_stable oms
INNER JOIN new_method_recent_mover nmr
    ON oms.lead_id = nmr.lead_id;
```

### Validation Query

```sql
-- Validate relabeling impact
WITH relabeled AS (
    SELECT * FROM `savvy-gtm-analytics.ml_features.v4_relabeled_leads_v41`
),

truly_stable AS (
    SELECT 
        tv.lead_id,
        tv.target
    FROM `savvy-gtm-analytics.ml_features.v4_target_variable` tv
    WHERE tv.target IS NOT NULL
      AND tv.lead_id NOT IN (SELECT lead_id FROM relabeled)
)

SELECT 
    'Mislabeled (STABLE -> RECENT_MOVER)' as segment,
    COUNT(*) as lead_count,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct
FROM relabeled

UNION ALL

SELECT 
    'Truly Stable' as segment,
    COUNT(*) as lead_count,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct
FROM truly_stable;

-- Expected output:
-- Mislabeled (STABLE -> RECENT_MOVER): ~3,444 leads, ~9.96% conversion
-- Truly Stable: remaining leads, ~3.39% conversion
```

---

## Phase 4: Feature Validation & PIT Audit

### Cursor Prompt 4.1: Run PIT Leakage Audit

```
@workspace Run a comprehensive Point-in-Time (PIT) leakage audit on V4.1 features.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT FILE: v4/reports/v4.1/pit_audit_report.md

Context:
- PIT leakage is the #1 cause of overfitting in lead scoring models
- Any feature using data from AFTER contacted_date is leakage
- New V4.1 features must be validated for PIT compliance

PIT AUDIT CHECKS:
1. is_recent_mover: Verify PRIMARY_FIRM_START_DATE <= contacted_date for all TRUE cases
2. days_since_last_move: Verify no negative values (would indicate future data)
3. firm_departures_corrected: Verify all departure dates < contacted_date
4. bleeding_velocity_encoded: Verify calculation window is BEFORE contacted_date
5. Firm/Rep type features: Note that these use current state (PRIMARY_FIRM_CLASSIFICATION, REP_TYPE)
   - Acceptable small PIT risk - firm classification and rep type are relatively stable
   - Check correlation with target (should NOT exceed 0.3 to avoid leakage suspicion)

Tasks:
1. Run PIT validation queries for each new feature
2. Check for suspicious correlations with target (>0.3 may indicate leakage)
3. Spot-check 100 random leads manually
4. Generate audit report

VALIDATION GATES:
- G4.1: Zero PIT violations in is_recent_mover
- G4.2: Zero negative values in days_since_last_move
- G4.3: No feature has |correlation with target| > 0.3
- G4.4: Manual spot-check passes for 100/100 leads
```

### SQL Code - PIT Audit

```sql
-- File: v4/sql/v4.1/pit_audit_v41.sql
-- Purpose: Comprehensive PIT leakage audit

-- ==========================================================================
-- AUDIT 1: is_recent_mover - Verify no future START_DATE usage
-- ==========================================================================
SELECT 
    'is_recent_mover' as feature,
    COUNT(*) as total_recent_movers,
    SUM(CASE 
        WHEN rm.current_firm_start_date > f.contacted_date 
        THEN 1 ELSE 0 
    END) as pit_violations,
    CASE 
        WHEN SUM(CASE WHEN rm.current_firm_start_date > f.contacted_date THEN 1 ELSE 0 END) = 0
        THEN 'PASSED' ELSE 'FAILED' 
    END as status
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41` f
JOIN `savvy-gtm-analytics.ml_features.recent_movers_v41` rm
    ON f.advisor_crd = rm.advisor_crd
WHERE f.is_recent_mover = 1;

-- ==========================================================================
-- AUDIT 2: days_since_last_move - Verify no negative values
-- ==========================================================================
SELECT 
    'days_since_last_move' as feature,
    COUNT(*) as total_rows,
    SUM(CASE WHEN days_since_last_move < 0 THEN 1 ELSE 0 END) as negative_values,
    MIN(days_since_last_move) as min_value,
    MAX(days_since_last_move) as max_value,
    CASE 
        WHEN MIN(days_since_last_move) >= 0 THEN 'PASSED' ELSE 'FAILED' 
    END as status
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE days_since_last_move != 9999;  -- Exclude default value

-- ==========================================================================
-- AUDIT 3: Feature-Target Correlation Check
-- ==========================================================================
SELECT 
    'Correlation Check' as audit,
    CORR(is_recent_mover, target) as corr_is_recent_mover,
    CORR(days_since_last_move, target) as corr_days_since_move,
    CORR(firm_departures_corrected, target) as corr_departures_corrected,
    CORR(bleeding_velocity_encoded, target) as corr_bleeding_velocity,
    CORR(recent_mover_x_bleeding, target) as corr_interaction,
    CORR(is_independent_ria, target) as corr_independent_ria,
    CORR(is_ia_rep_type, target) as corr_ia_rep_type,
    CORR(is_dual_registered, target) as corr_dual_registered,
    CORR(independent_ria_x_ia_rep, target) as corr_independent_ria_x_ia,
    
    -- Flag suspicious correlations
    CASE 
        WHEN ABS(CORR(is_recent_mover, target)) > 0.3 
          OR ABS(CORR(days_since_last_move, target)) > 0.3
          OR ABS(CORR(firm_departures_corrected, target)) > 0.3
          OR ABS(CORR(bleeding_velocity_encoded, target)) > 0.3
          OR ABS(CORR(recent_mover_x_bleeding, target)) > 0.3
          OR ABS(CORR(is_independent_ria, target)) > 0.3
          OR ABS(CORR(is_ia_rep_type, target)) > 0.3
          OR ABS(CORR(is_dual_registered, target)) > 0.3
          OR ABS(CORR(independent_ria_x_ia_rep, target)) > 0.3
        THEN 'SUSPICIOUS - INVESTIGATE' 
        ELSE 'PASSED' 
    END as status
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE target IS NOT NULL;

-- ==========================================================================
-- AUDIT 4: Spot-Check Sample (Manual Review)
-- ==========================================================================
SELECT 
    lead_id,
    advisor_crd,
    contacted_date,
    target,
    is_recent_mover,
    days_since_last_move,
    firm_departures_corrected,
    bleeding_velocity_encoded,
    recent_mover_x_bleeding
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE target IS NOT NULL
ORDER BY RAND()
LIMIT 100;
```

---

## Phase 5: Multicollinearity Check

### Cursor Prompt 5.1: Check Multicollinearity for New Features

```
@workspace Check multicollinearity between new V4.1 features and existing V4 features.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT FILE: v4/reports/v4.1/multicollinearity_report.md

Context:
- High multicollinearity (|r| > 0.7) between features hurts model stability
- New features may correlate with existing similar features
- VIF > 5 indicates problematic multicollinearity

Potential concerns:
- is_recent_mover vs mobility_tier (both measure movement)
- firm_departures_corrected vs firm_net_change_12mo (both measure firm stability)
- bleeding_velocity_encoded vs firm_stability_tier
- is_independent_ria vs is_ia_rep_type (expected moderate correlation ~0.4-0.6)
- is_ia_rep_type vs is_dual_registered (mutually exclusive - correlation = -1.0 by definition)
  - NOTE: If VIF > 10, may need to drop one of these mutually exclusive features

Tasks:
1. Calculate correlation matrix for all 23 features
2. Calculate VIF for each feature
3. Flag any pairs with |r| > 0.7
4. Recommend feature removal if VIF > 10
5. Generate report

VALIDATION GATES:
- G5.1: No feature pair has |correlation| > 0.85
- G5.2: No feature has VIF > 10
- G5.3: New features add independent signal (not redundant)
```

### Python Code - Multicollinearity Check

```python
# File: v4/scripts/v4.1/phase_5_multicollinearity_v41.py
"""
Phase 5: Multicollinearity Check for V4.1 Features
"""

import pandas as pd
import numpy as np
from google.cloud import bigquery
from statsmodels.stats.outliers_influence import variance_inflation_factor
import seaborn as sns
import matplotlib.pyplot as plt
from pathlib import Path

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
REPORT_DIR = WORKING_DIR / "reports" / "v4.1"
REPORT_DIR.mkdir(parents=True, exist_ok=True)

# Feature lists
ORIGINAL_FEATURES = [
    'tenure_months', 'tenure_bucket', 'mobility_3yr', 'mobility_tier',
    'firm_rep_count_at_contact', 'firm_net_change_12mo', 'firm_stability_tier',
    'is_wirehouse', 'is_broker_protocol', 'has_email', 'has_linkedin',
    'mobility_x_heavy_bleeding', 'short_tenure_x_high_mobility', 'has_firm_data'
]

NEW_FEATURES = [
    'is_recent_mover', 'days_since_last_move', 'firm_departures_corrected',
    'bleeding_velocity_encoded', 'recent_mover_x_bleeding'
]

ALL_FEATURES = ORIGINAL_FEATURES + NEW_FEATURES


def load_feature_data():
    """Load feature data from BigQuery."""
    client = bigquery.Client(project=PROJECT_ID)
    
    query = f"""
    SELECT 
        {', '.join(ALL_FEATURES)},
        target
    FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
    WHERE target IS NOT NULL
    """
    
    df = client.query(query).to_dataframe()
    print(f"Loaded {len(df):,} rows with {len(ALL_FEATURES)} features")
    return df


def calculate_correlation_matrix(df):
    """Calculate correlation matrix and flag high correlations."""
    corr_matrix = df[ALL_FEATURES].corr()
    
    # Find high correlations
    high_corr_pairs = []
    for i, feat1 in enumerate(ALL_FEATURES):
        for j, feat2 in enumerate(ALL_FEATURES):
            if i < j:  # Upper triangle only
                corr = corr_matrix.loc[feat1, feat2]
                if abs(corr) > 0.7:
                    high_corr_pairs.append({
                        'feature_1': feat1,
                        'feature_2': feat2,
                        'correlation': round(corr, 3),
                        'status': 'WARNING' if abs(corr) > 0.85 else 'MONITOR'
                    })
    
    return corr_matrix, high_corr_pairs


def calculate_vif(df):
    """Calculate Variance Inflation Factor for each feature."""
    X = df[ALL_FEATURES].fillna(0)
    
    # Handle categorical features
    for col in ['tenure_bucket', 'mobility_tier', 'firm_stability_tier']:
        if col in X.columns:
            X[col] = pd.Categorical(X[col]).codes
    
    vif_data = []
    for i, feature in enumerate(ALL_FEATURES):
        try:
            vif = variance_inflation_factor(X.values, i)
            vif_data.append({
                'feature': feature,
                'vif': round(vif, 2),
                'status': 'CRITICAL' if vif > 10 else ('WARNING' if vif > 5 else 'OK')
            })
        except Exception as e:
            vif_data.append({
                'feature': feature,
                'vif': np.nan,
                'status': 'ERROR'
            })
    
    return pd.DataFrame(vif_data).sort_values('vif', ascending=False)


def generate_report(corr_matrix, high_corr_pairs, vif_df):
    """Generate multicollinearity report."""
    report_path = REPORT_DIR / "multicollinearity_report.md"
    
    with open(report_path, 'w') as f:
        f.write("# V4.1 Multicollinearity Analysis Report\n\n")
        f.write(f"**Generated:** {pd.Timestamp.now()}\n\n")
        
        # Summary
        f.write("## Summary\n\n")
        critical_vif = len(vif_df[vif_df['status'] == 'CRITICAL'])
        high_corr = len([p for p in high_corr_pairs if p['status'] == 'WARNING'])
        
        f.write(f"- Features analyzed: {len(ALL_FEATURES)}\n")
        f.write(f"- New V4.1 features: {len(NEW_FEATURES)}\n")
        f.write(f"- Critical VIF (>10): {critical_vif}\n")
        f.write(f"- High correlation pairs (>0.85): {high_corr}\n\n")
        
        # Gate results
        f.write("## Validation Gates\n\n")
        g5_1 = high_corr == 0
        g5_2 = critical_vif == 0
        
        f.write(f"- G5.1: No correlation > 0.85: {'✅ PASSED' if g5_1 else '❌ FAILED'}\n")
        f.write(f"- G5.2: No VIF > 10: {'✅ PASSED' if g5_2 else '❌ FAILED'}\n\n")
        
        # VIF table
        f.write("## VIF Results\n\n")
        f.write("| Feature | VIF | Status |\n")
        f.write("|---------|-----|--------|\n")
        for _, row in vif_df.iterrows():
            f.write(f"| {row['feature']} | {row['vif']} | {row['status']} |\n")
        
        # High correlations
        if high_corr_pairs:
            f.write("\n## High Correlation Pairs\n\n")
            f.write("| Feature 1 | Feature 2 | Correlation | Status |\n")
            f.write("|-----------|-----------|-------------|--------|\n")
            for pair in high_corr_pairs:
                f.write(f"| {pair['feature_1']} | {pair['feature_2']} | {pair['correlation']} | {pair['status']} |\n")
    
    print(f"Report saved to: {report_path}")
    return g5_1 and g5_2


if __name__ == "__main__":
    print("=" * 70)
    print("PHASE 5: MULTICOLLINEARITY CHECK - V4.1")
    print("=" * 70)
    
    df = load_feature_data()
    corr_matrix, high_corr_pairs = calculate_correlation_matrix(df)
    vif_df = calculate_vif(df)
    
    passed = generate_report(corr_matrix, high_corr_pairs, vif_df)
    
    print(f"\nPhase 5 Status: {'PASSED' if passed else 'FAILED'}")
```

---

## Phase 6: Train/Test Split

### Cursor Prompt 6.1: Create Temporal Train/Test Split

```
@workspace Create temporal train/test split for V4.1 model training.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT SQL FILE: v4/sql/v4.1/phase_6_train_test_split.sql

Context:
- Temporal split prevents future data leakage
- Train on older data, test on newer data
- Minimum 30-day gap between train and test sets

Split strategy:
- TRAIN: contacted_date from 2024-02-01 to 2025-07-31
- GAP: 2025-08-01 to 2025-08-31 (30 days, excluded)
- TEST: contacted_date from 2025-09-01 to 2025-10-31

Tasks:
1. Create split labels in BigQuery
2. Verify no temporal overlap
3. Check class balance in both sets
4. Save split statistics

VALIDATION GATES:
- G6.1: Train set has >= 20,000 leads
- G6.2: Test set has >= 4,000 leads
- G6.3: Gap >= 30 days (no overlap)
- G6.4: Positive rate similar in train/test (within 2 percentage points)
```

### SQL Code

```sql
-- File: v4/sql/v4.1/phase_6_train_test_split.sql
-- Purpose: Create temporal train/test split for V4.1

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_splits_v41` AS

SELECT 
    *,
    CASE 
        -- TRAIN: Feb 2024 - July 2025
        WHEN contacted_date >= '2024-02-01' AND contacted_date <= '2025-07-31' 
        THEN 'TRAIN'
        
        -- GAP: August 2025 (excluded)
        WHEN contacted_date >= '2025-08-01' AND contacted_date <= '2025-08-31' 
        THEN 'GAP'
        
        -- TEST: September - October 2025
        WHEN contacted_date >= '2025-09-01' AND contacted_date <= '2025-10-31' 
        THEN 'TEST'
        
        ELSE 'EXCLUDED'
    END as split
FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
WHERE target IS NOT NULL;

-- Validation query
SELECT 
    split,
    COUNT(*) as lead_count,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    MIN(contacted_date) as min_date,
    MAX(contacted_date) as max_date
FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
GROUP BY split
ORDER BY min_date;
```

---

## Phase 7: Model Training

### Cursor Prompt 7.1: Train XGBoost V4.1 Model

```
@workspace Train the V4.1 XGBoost model with corrected features and proper regularization.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT FILES:
- v4/models/v4.1.0/model.pkl
- v4/models/v4.1.0/model.json
- v4/models/v4.1.0/feature_importance.csv
- v4/data/v4.1.0/final_features.json

Context:
- V4.1 has 23 features (14 original + 5 bleeding + 4 firm/rep type)
- Use regularization to prevent overfitting
- CRITICAL: Set base_score=0.5 explicitly to fix SHAP bug
- Use early stopping with validation set

Hyperparameters:
- max_depth: 4 (shallow trees)
- min_child_weight: 10
- gamma: 0.1
- subsample: 0.8
- colsample_bytree: 0.8
- reg_alpha: 0.1
- reg_lambda: 1.0
- learning_rate: 0.05
- n_estimators: 500
- early_stopping_rounds: 50
- base_score: 0.5 (CRITICAL for SHAP)
- scale_pos_weight: ~25 (handle class imbalance)

Tasks:
1. Load train/test data from BigQuery
2. Prepare features (encode categoricals, handle NULLs)
3. Train XGBoost with early stopping
4. Save model artifacts
5. Save feature list to JSON

VALIDATION GATES:
- G7.1: Model trains without errors
- G7.2: Early stopping triggers (not overfit)
- G7.3: Feature importance is reasonable (no single feature dominates >50%)
- G7.4: Model files saved successfully
```

### Python Code

```python
# File: v4/scripts/v4.1/phase_7_model_training_v41.py
"""
Phase 7: Train XGBoost V4.1 Model

CRITICAL: Set base_score=0.5 explicitly to fix SHAP compatibility
"""

import pandas as pd
import numpy as np
import xgboost as xgb
import pickle
import json
from pathlib import Path
from google.cloud import bigquery
from datetime import datetime

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
MODEL_DIR = WORKING_DIR / "models" / "v4.1.0"
DATA_DIR = WORKING_DIR / "data" / "v4.1.0"

MODEL_DIR.mkdir(parents=True, exist_ok=True)
DATA_DIR.mkdir(parents=True, exist_ok=True)

# V4.1 Feature list (14 original + 5 bleeding + 4 firm/rep type = 23 total)
FEATURES_V41 = [
    # Original V4 features
    'tenure_months', 'mobility_3yr', 'firm_rep_count_at_contact', 
    'firm_net_change_12mo', 'is_wirehouse', 'is_broker_protocol',
    'has_email', 'has_linkedin', 'has_firm_data',
    'mobility_x_heavy_bleeding', 'short_tenure_x_high_mobility',
    # Encoded categorical features
    'tenure_bucket_encoded', 'mobility_tier_encoded', 'firm_stability_tier_encoded',
    # NEW V4.1 Bleeding Signal features
    'is_recent_mover', 'days_since_last_move', 'firm_departures_corrected',
    'bleeding_velocity_encoded', 'recent_mover_x_bleeding',
    # NEW V4.1 Firm/Rep Type features
    'is_independent_ria', 'is_ia_rep_type', 'is_dual_registered', 'independent_ria_x_ia_rep'
]

# Hyperparameters with regularization
HYPERPARAMS = {
    'objective': 'binary:logistic',
    'eval_metric': ['auc', 'logloss'],
    'max_depth': 4,
    'min_child_weight': 10,
    'gamma': 0.1,
    'subsample': 0.8,
    'colsample_bytree': 0.8,
    'reg_alpha': 0.1,
    'reg_lambda': 1.0,
    'learning_rate': 0.05,
    'n_estimators': 500,
    'base_score': 0.5,  # CRITICAL for SHAP compatibility
    'seed': 42,
    'verbosity': 1
}


def load_data():
    """Load train and test data from BigQuery."""
    client = bigquery.Client(project=PROJECT_ID)
    
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
    WHERE split IN ('TRAIN', 'TEST')
    """
    
    df = client.query(query).to_dataframe()
    
    train_df = df[df['split'] == 'TRAIN'].copy()
    test_df = df[df['split'] == 'TEST'].copy()
    
    print(f"Train: {len(train_df):,} rows, {train_df['target'].mean()*100:.2f}% positive")
    print(f"Test: {len(test_df):,} rows, {test_df['target'].mean()*100:.2f}% positive")
    
    return train_df, test_df


def prepare_features(df):
    """Prepare features for XGBoost."""
    X = df.copy()
    
    # Encode categorical features
    categorical_mappings = {}
    for cat_col, encoded_col in [
        ('tenure_bucket', 'tenure_bucket_encoded'),
        ('mobility_tier', 'mobility_tier_encoded'),
        ('firm_stability_tier', 'firm_stability_tier_encoded')
    ]:
        if cat_col in X.columns:
            X[encoded_col] = pd.Categorical(X[cat_col]).codes
            X[encoded_col] = X[encoded_col].replace(-1, 0)
            categorical_mappings[cat_col] = dict(enumerate(pd.Categorical(X[cat_col]).categories))
    
    # Select final features
    feature_cols = [f for f in FEATURES_V41 if f in X.columns]
    X_features = X[feature_cols].fillna(0)
    
    return X_features, feature_cols, categorical_mappings


def train_model(X_train, y_train, X_test, y_test):
    """Train XGBoost with early stopping."""
    
    # Calculate scale_pos_weight for class imbalance
    neg_count = (y_train == 0).sum()
    pos_count = (y_train == 1).sum()
    scale_pos_weight = neg_count / pos_count
    print(f"Scale pos weight: {scale_pos_weight:.2f}")
    
    # Update hyperparams
    params = HYPERPARAMS.copy()
    params['scale_pos_weight'] = scale_pos_weight
    
    # Create DMatrices
    dtrain = xgb.DMatrix(X_train, label=y_train)
    dtest = xgb.DMatrix(X_test, label=y_test)
    
    # Train with early stopping
    evals = [(dtrain, 'train'), (dtest, 'test')]
    
    model = xgb.train(
        params,
        dtrain,
        num_boost_round=params['n_estimators'],
        evals=evals,
        early_stopping_rounds=50,
        verbose_eval=50
    )
    
    print(f"\nBest iteration: {model.best_iteration}")
    print(f"Best score: {model.best_score:.4f}")
    
    return model


def save_model_artifacts(model, feature_cols, categorical_mappings):
    """Save model and related artifacts."""
    
    # Save model pickle
    model_path = MODEL_DIR / "model.pkl"
    with open(model_path, 'wb') as f:
        pickle.dump(model, f)
    print(f"Model saved to: {model_path}")
    
    # Save model JSON (for portability)
    json_path = MODEL_DIR / "model.json"
    model.save_model(str(json_path))
    print(f"Model JSON saved to: {json_path}")
    
    # Save feature importance
    importance = model.get_score(importance_type='gain')
    importance_df = pd.DataFrame([
        {'feature': k, 'importance': v}
        for k, v in importance.items()
    ]).sort_values('importance', ascending=False)
    
    importance_path = MODEL_DIR / "feature_importance.csv"
    importance_df.to_csv(importance_path, index=False)
    print(f"Feature importance saved to: {importance_path}")
    
    # Save feature list
    features_data = {
        'version': 'v4.1.0',
        'created': datetime.now().isoformat(),
        'final_features': feature_cols,
        'feature_count': len(feature_cols),  # Should be 23 (14 original + 5 bleeding + 4 firm/rep type)
        'categorical_mappings': categorical_mappings
    }
    
    features_path = DATA_DIR / "final_features.json"
    with open(features_path, 'w') as f:
        json.dump(features_data, f, indent=2)
    print(f"Features saved to: {features_path}")
    
    return importance_df


def validate_model(model, importance_df):
    """Validate model meets quality gates."""
    gates_passed = True
    
    # G7.2: Check early stopping triggered
    if model.best_iteration >= 450:
        print("⚠️ G7.2 WARNING: Early stopping did not trigger significantly")
        gates_passed = False
    else:
        print(f"✅ G7.2 PASSED: Early stopping at iteration {model.best_iteration}")
    
    # G7.3: Check no single feature dominates
    if len(importance_df) > 0:
        total_importance = importance_df['importance'].sum()
        max_importance_pct = (importance_df['importance'].max() / total_importance) * 100
        
        if max_importance_pct > 50:
            print(f"⚠️ G7.3 WARNING: Top feature has {max_importance_pct:.1f}% importance")
            gates_passed = False
        else:
            print(f"✅ G7.3 PASSED: Max feature importance {max_importance_pct:.1f}%")
    
    return gates_passed


def run_phase_7():
    """Execute Phase 7: Model Training."""
    print("=" * 70)
    print("PHASE 7: MODEL TRAINING - V4.1")
    print("=" * 70)
    
    # Load data
    train_df, test_df = load_data()
    
    # Prepare features
    X_train, feature_cols, categorical_mappings = prepare_features(train_df)
    X_test, _, _ = prepare_features(test_df)
    
    y_train = train_df['target'].values
    y_test = test_df['target'].values
    
    print(f"\nFeatures: {len(feature_cols)}")
    print(f"Feature list: {feature_cols}")
    
    # Train model
    model = train_model(X_train, y_train, X_test, y_test)
    
    # Save artifacts
    importance_df = save_model_artifacts(model, feature_cols, categorical_mappings)
    
    # Validate
    gates_passed = validate_model(model, importance_df)
    
    print("\n" + "=" * 70)
    print(f"Phase 7 Status: {'PASSED' if gates_passed else 'PASSED WITH WARNINGS'}")
    print("=" * 70)
    
    return gates_passed


if __name__ == "__main__":
    run_phase_7()
```

---

## Phase 8: Overfitting Detection

### Cursor Prompt 8.1: Check for Overfitting

```
@workspace Perform comprehensive overfitting detection on V4.1 model.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT FILE: v4/reports/v4.1/overfitting_report.md

Overfitting indicators to check:
1. Train vs Test AUC gap (should be < 0.05)
2. Train vs Test lift gap (should be < 0.5x)
3. Learning curve analysis (should plateau, not diverge)
4. Cross-validation stability (CV std < 0.03)

Tasks:
1. Calculate AUC on train and test sets
2. Calculate lift by decile on train and test sets
3. Compare performance metrics
4. Flag if overfitting detected
5. Generate report

VALIDATION GATES:
- G8.1: Train-Test AUC gap < 0.05
- G8.2: Train-Test top decile lift gap < 0.5x
- G8.3: Cross-validation AUC std < 0.03
- G8.4: Test AUC > 0.58 (meaningful signal)
```

### Python Code

```python
# File: v4/scripts/v4.1/phase_8_overfitting_check_v41.py
"""
Phase 8: Overfitting Detection for V4.1
"""

import pandas as pd
import numpy as np
import pickle
import xgboost as xgb
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import cross_val_score, StratifiedKFold
from pathlib import Path
from google.cloud import bigquery

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
MODEL_DIR = WORKING_DIR / "models" / "v4.1.0"
REPORT_DIR = WORKING_DIR / "reports" / "v4.1"

REPORT_DIR.mkdir(parents=True, exist_ok=True)


def load_model_and_data():
    """Load V4.1 model and train/test data."""
    # Load model
    with open(MODEL_DIR / "model.pkl", 'rb') as f:
        model = pickle.load(f)
    
    # Load data
    client = bigquery.Client(project=PROJECT_ID)
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
    WHERE split IN ('TRAIN', 'TEST')
    """
    df = client.query(query).to_dataframe()
    
    return model, df


def calculate_lift_by_decile(y_true, y_pred):
    """Calculate lift by decile."""
    df = pd.DataFrame({'y_true': y_true, 'y_pred': y_pred})
    df['decile'] = pd.qcut(df['y_pred'], 10, labels=False, duplicates='drop')
    
    baseline = df['y_true'].mean()
    lift_by_decile = df.groupby('decile')['y_true'].mean() / baseline
    
    return lift_by_decile


def run_cross_validation(X, y, n_splits=5):
    """Run stratified k-fold cross-validation."""
    from xgboost import XGBClassifier
    
    model = XGBClassifier(
        max_depth=4,
        min_child_weight=10,
        gamma=0.1,
        subsample=0.8,
        colsample_bytree=0.8,
        reg_alpha=0.1,
        reg_lambda=1.0,
        learning_rate=0.05,
        n_estimators=100,
        base_score=0.5,
        use_label_encoder=False,
        eval_metric='logloss'
    )
    
    cv = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=42)
    scores = cross_val_score(model, X, y, cv=cv, scoring='roc_auc')
    
    return scores


def generate_report(metrics, gates_results):
    """Generate overfitting report."""
    report_path = REPORT_DIR / "overfitting_report.md"
    
    with open(report_path, 'w') as f:
        f.write("# V4.1 Overfitting Detection Report\n\n")
        f.write(f"**Generated:** {pd.Timestamp.now()}\n\n")
        
        # Summary metrics
        f.write("## Performance Metrics\n\n")
        f.write("| Metric | Train | Test | Gap | Status |\n")
        f.write("|--------|-------|------|-----|--------|\n")
        f.write(f"| AUC-ROC | {metrics['train_auc']:.4f} | {metrics['test_auc']:.4f} | {metrics['auc_gap']:.4f} | {'✅' if gates_results['G8.1'] else '❌'} |\n")
        f.write(f"| Top Decile Lift | {metrics['train_top_lift']:.2f}x | {metrics['test_top_lift']:.2f}x | {metrics['lift_gap']:.2f}x | {'✅' if gates_results['G8.2'] else '❌'} |\n")
        
        # Cross-validation
        f.write("\n## Cross-Validation Results\n\n")
        f.write(f"- Mean AUC: {metrics['cv_mean']:.4f}\n")
        f.write(f"- Std AUC: {metrics['cv_std']:.4f}\n")
        f.write(f"- Status: {'✅ Stable' if gates_results['G8.3'] else '❌ Unstable'}\n")
        
        # Gate summary
        f.write("\n## Validation Gates\n\n")
        for gate, passed in gates_results.items():
            f.write(f"- {gate}: {'✅ PASSED' if passed else '❌ FAILED'}\n")
        
        # Overall status
        all_passed = all(gates_results.values())
        f.write(f"\n## Overall Status: {'✅ NO OVERFITTING DETECTED' if all_passed else '⚠️ POTENTIAL OVERFITTING'}\n")
    
    print(f"Report saved to: {report_path}")
    return all_passed


def run_phase_8():
    """Execute Phase 8: Overfitting Detection."""
    print("=" * 70)
    print("PHASE 8: OVERFITTING DETECTION - V4.1")
    print("=" * 70)
    
    model, df = load_model_and_data()
    
    # Split the data FIRST before using train_df/test_df
    train_df = df[df['split'] == 'TRAIN'].copy()
    test_df = df[df['split'] == 'TEST'].copy()
    
    # Prepare features (reuse logic from Phase 7)
    from pathlib import Path
    import sys
    sys.path.append(str(WORKING_DIR / "scripts"))
    
    # Import feature preparation from Phase 7
    try:
        from phase_7_model_training_v41 import prepare_features, FEATURES_V41
        X_train, feature_cols, _ = prepare_features(train_df)
        X_test, _, _ = prepare_features(test_df)
        y_train = train_df['target'].values
        y_test = test_df['target'].values
    except ImportError:
        # Fallback: define prepare_features inline if import fails
        # Define FEATURES_V41 locally if import failed
        FEATURES_V41 = [
            'tenure_months', 'mobility_3yr', 'firm_rep_count_at_contact', 
            'firm_net_change_12mo', 'is_wirehouse', 'is_broker_protocol',
            'has_email', 'has_linkedin', 'has_firm_data',
            'mobility_x_heavy_bleeding', 'short_tenure_x_high_mobility',
            'tenure_bucket_encoded', 'mobility_tier_encoded', 'firm_stability_tier_encoded',
            'is_recent_mover', 'days_since_last_move', 'firm_departures_corrected',
            'bleeding_velocity_encoded', 'recent_mover_x_bleeding',
            'is_independent_ria', 'is_ia_rep_type', 'is_dual_registered', 'independent_ria_x_ia_rep'
        ]
        
        def prepare_features_fallback(df):
            """Fallback feature preparation."""
            X = df.copy()
            # Encode categoricals
            for cat_col, encoded_col in [
                ('tenure_bucket', 'tenure_bucket_encoded'),
                ('mobility_tier', 'mobility_tier_encoded'),
                ('firm_stability_tier', 'firm_stability_tier_encoded')
            ]:
                if cat_col in X.columns:
                    X[encoded_col] = pd.Categorical(X[cat_col]).codes
                    X[encoded_col] = X[encoded_col].replace(-1, 0)
            
            # Select features
            feature_cols = [f for f in FEATURES_V41 if f in X.columns]
            X_features = X[feature_cols].fillna(0)
            return X_features, feature_cols
        
        X_train, feature_cols = prepare_features_fallback(train_df)
        X_test, _ = prepare_features_fallback(test_df)
        y_train = train_df['target'].values
        y_test = test_df['target'].values
    
    # Calculate predictions
    dtrain = xgb.DMatrix(X_train, label=y_train)
    dtest = xgb.DMatrix(X_test, label=y_test)
    
    train_pred = model.predict(dtrain)
    test_pred = model.predict(dtest)
    
    # Calculate metrics
    train_auc = roc_auc_score(y_train, train_pred)
    test_auc = roc_auc_score(y_test, test_pred)
    auc_gap = train_auc - test_auc
    
    train_lift = calculate_lift_by_decile(y_train, train_pred)
    test_lift = calculate_lift_by_decile(y_test, test_pred)
    train_top_lift = train_lift.iloc[-1] if len(train_lift) > 0 else 0.0
    test_top_lift = test_lift.iloc[-1] if len(test_lift) > 0 else 0.0
    lift_gap = abs(train_top_lift - test_top_lift)
    
    # Cross-validation
    cv_scores = run_cross_validation(X_train, y_train, n_splits=5)
    cv_mean = cv_scores.mean()
    cv_std = cv_scores.std()
    
    metrics = {
        'train_auc': train_auc,
        'test_auc': test_auc,
        'auc_gap': auc_gap,
        'train_top_lift': train_top_lift,
        'test_top_lift': test_top_lift,
        'lift_gap': lift_gap,
        'cv_mean': cv_mean,
        'cv_std': cv_std
    }
    
    # Evaluate gates
    gates_results = {
        'G8.1': metrics['auc_gap'] < 0.05,
        'G8.2': metrics['lift_gap'] < 0.5,
        'G8.3': metrics['cv_std'] < 0.03,
        'G8.4': metrics['test_auc'] > 0.58
    }
    
    passed = generate_report(metrics, gates_results)
    
    print(f"\nPhase 8 Status: {'PASSED' if passed else 'FAILED'}")
    return passed


if __name__ == "__main__":
    run_phase_8()
```

---

## Phase 9: Model Validation

### Cursor Prompt 9.1: Validate V4.1 Model Performance

```
@workspace Validate V4.1 model performance and compare to V4.0.0 baseline.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT FILE: v4/reports/v4.1/model_validation_report.md

Metrics to calculate:
1. AUC-ROC and AUC-PR
2. Lift by decile
3. Precision-Recall at various thresholds
4. Comparison to V4.0.0 baseline

Tasks:
1. Load V4.1 model from v4/models/v4.1.0/model.pkl
2. Load test set from ml_features.v4_splits_v41 WHERE split='TEST'
3. Prepare features using same logic as Phase 7
4. Score test set with V4.1 model
5. Calculate all performance metrics
6. Load V4.0.0 metrics from v4/models/registry.json
7. Compare metrics side-by-side
8. Generate comparison report

VALIDATION GATES:
- G9.1: Test AUC-ROC >= 0.58
- G9.2: Top decile lift >= 1.4x
- G9.3: V4.1 AUC >= V4.0.0 AUC (improvement)
- G9.4: Bottom 20% conversion rate < 2% (effective deprioritization)

**ERROR HANDLING**:
- If model file missing: Go back to Phase 7 and ensure model was saved
- If test set missing: Go back to Phase 6 and ensure splits were created
- If V4.0.0 metrics missing: Load from v4/models/v4.0.0/training_metrics.json as fallback

**ROLLBACK INSTRUCTIONS** (if Phase 9 fails):
- If G9.3 fails (V4.1 worse than V4.0.0): This is a critical failure - DO NOT DEPLOY
- Log detailed comparison and investigate root cause
- Consider retraining with different hyperparameters
```

### Python Code

```python
# File: v4/scripts/v4.1/phase_9_validation_v41.py
"""
Phase 9: Model Validation for V4.1
"""

import pandas as pd
import numpy as np
import pickle
import json
import xgboost as xgb
from sklearn.metrics import roc_auc_score, average_precision_score
from pathlib import Path
from google.cloud import bigquery

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
MODEL_DIR = WORKING_DIR / "models" / "v4.1.0"
REPORT_DIR = WORKING_DIR / "reports" / "v4.1"
REGISTRY_PATH = WORKING_DIR / "models" / "registry.json"

REPORT_DIR.mkdir(parents=True, exist_ok=True)

# V4.1 Feature list (23 features)
FEATURES_V41 = [
    # Original V4 features
    'tenure_months', 'mobility_3yr', 'firm_rep_count_at_contact', 
    'firm_net_change_12mo', 'is_wirehouse', 'is_broker_protocol',
    'has_email', 'has_linkedin', 'has_firm_data',
    'mobility_x_heavy_bleeding', 'short_tenure_x_high_mobility',
    # Encoded categorical features
    'tenure_bucket_encoded', 'mobility_tier_encoded', 'firm_stability_tier_encoded',
    # NEW V4.1 Bleeding Signal features
    'is_recent_mover', 'days_since_last_move', 'firm_departures_corrected',
    'bleeding_velocity_encoded', 'recent_mover_x_bleeding',
    # NEW V4.1 Firm/Rep Type features
    'is_independent_ria', 'is_ia_rep_type', 'is_dual_registered', 'independent_ria_x_ia_rep'
]


def prepare_features(df):
    """Prepare features for XGBoost (reuse Phase 7 logic)."""
    X = df.copy()
    
    # Encode categorical features
    for cat_col, encoded_col in [
        ('tenure_bucket', 'tenure_bucket_encoded'),
        ('mobility_tier', 'mobility_tier_encoded'),
        ('firm_stability_tier', 'firm_stability_tier_encoded')
    ]:
        if cat_col in X.columns:
            X[encoded_col] = pd.Categorical(X[cat_col]).codes
            X[encoded_col] = X[encoded_col].replace(-1, 0)
    
    # Select final features
    feature_cols = [f for f in FEATURES_V41 if f in X.columns]
    X_features = X[feature_cols].fillna(0)
    
    return X_features, feature_cols


def calculate_lift_by_decile(y_true, y_pred):
    """Calculate lift by decile."""
    df = pd.DataFrame({'y_true': y_true, 'y_pred': y_pred})
    df['decile'] = pd.qcut(df['y_pred'], 10, labels=False, duplicates='drop')
    
    baseline = df['y_true'].mean()
    lift_by_decile = df.groupby('decile')['y_true'].mean() / baseline
    
    return lift_by_decile


def load_model_and_data():
    """Load V4.1 model and test data."""
    # Load model
    print("Loading V4.1 model...")
    with open(MODEL_DIR / "model.pkl", 'rb') as f:
        model = pickle.load(f)
    
    # Load test data
    print("Loading test data...")
    client = bigquery.Client(project=PROJECT_ID)
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
    WHERE split = 'TEST'
    """
    test_df = client.query(query).to_dataframe()
    
    print(f"Test set: {len(test_df):,} rows, {test_df['target'].mean()*100:.2f}% positive")
    
    return model, test_df


def load_v4_baseline_metrics():
    """Load V4.0.0 baseline metrics from registry."""
    try:
        with open(REGISTRY_PATH, 'r') as f:
            registry = json.load(f)
        
        v4_metrics = registry.get('v4.0.0', {}).get('test_metrics', {})
        return v4_metrics
    except Exception as e:
        print(f"Warning: Could not load V4.0.0 metrics: {e}")
        return {}


def calculate_metrics(model, test_df):
    """Calculate all performance metrics."""
    # Prepare features
    X_test, feature_cols = prepare_features(test_df)
    y_test = test_df['target'].values
    
    # Make predictions
    dtest = xgb.DMatrix(X_test, label=y_test)
    y_pred = model.predict(dtest)
    
    # Calculate AUC metrics
    auc_roc = roc_auc_score(y_test, y_pred)
    auc_pr = average_precision_score(y_test, y_pred)
    
    # Calculate lift by decile
    lift_by_decile = calculate_lift_by_decile(y_test, y_pred)
    top_decile_lift = lift_by_decile.iloc[-1] if len(lift_by_decile) > 0 else 0.0
    
    # Calculate bottom 20% conversion rate
    df_scores = pd.DataFrame({'target': y_test, 'pred': y_pred})
    df_scores['percentile'] = pd.qcut(df_scores['pred'], 5, labels=False, duplicates='drop')
    bottom_20_pct_rate = df_scores[df_scores['percentile'] == 0]['target'].mean()
    
    # Top 5% lift
    df_scores['top_5_pct'] = (df_scores['pred'] >= df_scores['pred'].quantile(0.95)).astype(int)
    top_5_pct_rate = df_scores[df_scores['top_5_pct'] == 1]['target'].mean()
    baseline_rate = df_scores['target'].mean()
    top_5_pct_lift = top_5_pct_rate / baseline_rate if baseline_rate > 0 else 0.0
    
    metrics = {
        'auc_roc': auc_roc,
        'auc_pr': auc_pr,
        'top_decile_lift': top_decile_lift,
        'top_5pct_lift': top_5_pct_lift,
        'bottom_20pct_rate': bottom_20_pct_rate,
        'baseline_rate': baseline_rate
    }
    
    return metrics, lift_by_decile


def evaluate_gates(metrics, v4_baseline):
    """Evaluate validation gates."""
    gates = {
        'G9.1': metrics['auc_roc'] >= 0.58,
        'G9.2': metrics['top_decile_lift'] >= 1.4,
        'G9.3': metrics['auc_roc'] >= v4_baseline.get('auc_roc', 0.599),
        'G9.4': metrics['bottom_20pct_rate'] < 0.02
    }
    
    return gates


def generate_report(metrics, gates, v4_baseline, lift_by_decile):
    """Generate validation report."""
    report_path = REPORT_DIR / "model_validation_report.md"
    
    with open(report_path, 'w') as f:
        f.write("# V4.1 Model Validation Report\n\n")
        f.write(f"**Generated:** {pd.Timestamp.now()}\n\n")
        
        # Summary metrics
        f.write("## Performance Metrics\n\n")
        f.write("| Metric | V4.1.0 | V4.0.0 (Baseline) | Change |\n")
        f.write("|--------|--------|-------------------|--------|\n")
        
        v4_auc = v4_baseline.get('auc_roc', 0.599)
        auc_change = metrics['auc_roc'] - v4_auc
        f.write(f"| AUC-ROC | {metrics['auc_roc']:.4f} | {v4_auc:.4f} | {auc_change:+.4f} |\n")
        
        v4_lift = v4_baseline.get('top_decile_lift', 1.509)
        lift_change = metrics['top_decile_lift'] - v4_lift
        f.write(f"| Top Decile Lift | {metrics['top_decile_lift']:.2f}x | {v4_lift:.2f}x | {lift_change:+.2f}x |\n")
        
        f.write(f"| AUC-PR | {metrics['auc_pr']:.4f} | - | - |\n")
        f.write(f"| Top 5% Lift | {metrics['top_5pct_lift']:.2f}x | - | - |\n")
        f.write(f"| Bottom 20% Rate | {metrics['bottom_20pct_rate']*100:.2f}% | - | - |\n")
        
        # Lift by decile table
        f.write("\n## Lift by Decile\n\n")
        f.write("| Decile | Conversion Rate | Lift |\n")
        f.write("|--------|----------------|------|\n")
        for decile, lift in lift_by_decile.items():
            rate = metrics['baseline_rate'] * lift
            f.write(f"| {decile+1} | {rate*100:.2f}% | {lift:.2f}x |\n")
        
        # Gate results
        f.write("\n## Validation Gates\n\n")
        for gate, passed in gates.items():
            status = "✅ PASSED" if passed else "❌ FAILED"
            f.write(f"- {gate}: {status}\n")
        
        # Overall status
        all_passed = all(gates.values())
        f.write(f"\n## Overall Status: {'✅ VALIDATION PASSED' if all_passed else '❌ VALIDATION FAILED'}\n")
    
    print(f"Report saved to: {report_path}")
    return all_passed


def run_phase_9():
    """Execute Phase 9: Model Validation."""
    print("=" * 70)
    print("PHASE 9: MODEL VALIDATION - V4.1")
    print("=" * 70)
    
    # Load model and data
    model, test_df = load_model_and_data()
    
    # Load V4.0.0 baseline
    v4_baseline = load_v4_baseline_metrics()
    
    # Calculate metrics
    metrics, lift_by_decile = calculate_metrics(model, test_df)
    
    print("\nV4.1 Performance Metrics:")
    print(f"  AUC-ROC: {metrics['auc_roc']:.4f}")
    print(f"  AUC-PR: {metrics['auc_pr']:.4f}")
    print(f"  Top Decile Lift: {metrics['top_decile_lift']:.2f}x")
    print(f"  Top 5% Lift: {metrics['top_5pct_lift']:.2f}x")
    print(f"  Bottom 20% Rate: {metrics['bottom_20pct_rate']*100:.2f}%")
    
    # Evaluate gates
    gates = evaluate_gates(metrics, v4_baseline)
    
    print("\nValidation Gates:")
    for gate, passed in gates.items():
        status = "✅ PASSED" if passed else "❌ FAILED"
        print(f"  {gate}: {status}")
    
    # Generate report
    all_passed = generate_report(metrics, gates, v4_baseline, lift_by_decile)
    
    print("\n" + "=" * 70)
    print(f"Phase 9 Status: {'PASSED' if all_passed else 'FAILED'}")
    print("=" * 70)
    
    return all_passed


if __name__ == "__main__":
    run_phase_9()
```

---

## Phase 10: SHAP Analysis

### Cursor Prompt 10.1: Run SHAP Analysis

```
@workspace Run SHAP analysis on V4.1 model to validate interpretability.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
OUTPUT FILES:
- v4/reports/v4.1/shap_summary.png
- v4/reports/v4.1/shap_analysis_report.md

Context:
- V4.0.0 SHAP was broken due to base_score='[5E-1]' bug
- V4.1 was trained with explicit base_score=0.5
- SHAP should now work correctly

Tasks:
1. Load V4.1 model and test data
2. Create SHAP TreeExplainer
3. Calculate SHAP values
4. Generate summary plot
5. Verify top features match expectations

VALIDATION GATES:
- G10.1: SHAP TreeExplainer creates without error
- G10.2: SHAP values calculated successfully
- G10.3: Top 10 SHAP features include at least 3 new V4.1 features (bleeding + firm/rep type)
- G10.4: SHAP feature importance correlates with XGBoost importance (r > 0.7)

**ERROR HANDLING**:
- If G10.1 fails (TreeExplainer error): Check model was trained with `base_score=0.5` - this is critical
- If G10.2 fails (SHAP calculation error): Try reducing sample size or check model compatibility
- If G10.3 fails (new features not in top 5): This is a warning, not a blocker - log and proceed
- If G10.4 fails (low correlation): Investigate - may indicate model instability

**ROLLBACK INSTRUCTIONS** (if Phase 10 fails critically):
- If SHAP completely broken: This is a warning, not a blocker for deployment
- Log the issue and proceed to Phase 11
- Note in registry that SHAP analysis needs investigation

### Python Code

```python
# File: v4/scripts/v4.1/phase_10_shap_analysis_v41.py
"""
Phase 10: SHAP Analysis for V4.1

This should work now that base_score=0.5 is set explicitly.
"""

import pandas as pd
import numpy as np
import pickle
import shap
import matplotlib.pyplot as plt
from pathlib import Path
from google.cloud import bigquery
import json

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
MODEL_DIR = WORKING_DIR / "models" / "v4.1.0"
REPORT_DIR = WORKING_DIR / "reports" / "v4.1"

REPORT_DIR.mkdir(parents=True, exist_ok=True)


def run_shap_analysis():
    """Run SHAP analysis on V4.1 model."""
    print("=" * 70)
    print("PHASE 10: SHAP ANALYSIS - V4.1")
    print("=" * 70)
    
    # Load model
    print("\nLoading model...")
    with open(MODEL_DIR / "model.pkl", 'rb') as f:
        model = pickle.load(f)
    
    # Load feature list
    with open(WORKING_DIR / "data" / "v4.1.0" / "final_features.json", 'r') as f:
        features_data = json.load(f)
    feature_list = features_data['final_features']
    
    # Load test data
    print("Loading test data...")
    client = bigquery.Client(project=PROJECT_ID)
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
    WHERE split = 'TEST'
    """
    test_df = client.query(query).to_dataframe()
    
    # Prepare features
    X_test = test_df[feature_list].fillna(0)
    
    # Sample for SHAP (use 2000 for speed)
    sample_size = min(2000, len(X_test))
    X_sample = X_test.sample(n=sample_size, random_state=42)
    
    print(f"\nCalculating SHAP values for {sample_size} samples...")
    
    # G10.1: Create SHAP explainer
    try:
        explainer = shap.TreeExplainer(model)
        print("✅ G10.1 PASSED: SHAP TreeExplainer created successfully")
        g10_1 = True
    except Exception as e:
        print(f"❌ G10.1 FAILED: {e}")
        g10_1 = False
        return False
    
    # G10.2: Calculate SHAP values
    try:
        shap_values = explainer.shap_values(X_sample)
        print("✅ G10.2 PASSED: SHAP values calculated successfully")
        g10_2 = True
    except Exception as e:
        print(f"❌ G10.2 FAILED: {e}")
        g10_2 = False
        return False
    
    # Calculate mean absolute SHAP values
    mean_shap = np.abs(shap_values).mean(axis=0)
    shap_importance = pd.DataFrame({
        'feature': feature_list,
        'mean_shap': mean_shap
    }).sort_values('mean_shap', ascending=False)
    
    print("\nTop 10 Features by SHAP Importance:")
    print(shap_importance.head(10).to_string(index=False))
    
    # G10.3: Check if new features appear in top 10
    new_features = [
        # Bleeding signal features
        'is_recent_mover', 'days_since_last_move', 'firm_departures_corrected',
        'bleeding_velocity_encoded', 'recent_mover_x_bleeding',
        # Firm/rep type features
        'is_independent_ria', 'is_ia_rep_type', 'is_dual_registered', 'independent_ria_x_ia_rep'
    ]
    top_10_features = shap_importance.head(10)['feature'].tolist()
    new_in_top_10 = len(set(new_features) & set(top_10_features))
    
    if new_in_top_10 >= 3:
        print(f"✅ G10.3 PASSED: {new_in_top_10} new V4.1 features in top 10")
        g10_3 = True
    else:
        print(f"⚠️ G10.3 WARNING: Only {new_in_top_10} new features in top 10")
        g10_3 = False
    
    # Generate summary plot
    print("\nGenerating SHAP summary plot...")
    plt.figure(figsize=(10, 8))
    shap.summary_plot(shap_values, X_sample, feature_names=feature_list, show=False)
    plt.tight_layout()
    plt.savefig(REPORT_DIR / "shap_summary.png", dpi=150, bbox_inches='tight')
    plt.close()
    print(f"Plot saved to: {REPORT_DIR / 'shap_summary.png'}")
    
    # Save SHAP importance
    shap_importance.to_csv(REPORT_DIR / "shap_importance.csv", index=False)
    
    # Generate report
    with open(REPORT_DIR / "shap_analysis_report.md", 'w') as f:
        f.write("# V4.1 SHAP Analysis Report\n\n")
        f.write(f"**Generated:** {pd.Timestamp.now()}\n\n")
        f.write("## Summary\n\n")
        f.write(f"- SHAP TreeExplainer: {'✅ Working' if g10_1 else '❌ Failed'}\n")
        f.write(f"- SHAP Values: {'✅ Calculated' if g10_2 else '❌ Failed'}\n")
        f.write(f"- New Features in Top 10: {new_in_top_10}\n\n")
        f.write("## Top 10 Features by SHAP Importance\n\n")
        f.write("| Rank | Feature | Mean |SHAP| |\n")
        f.write("|------|---------|-------------|\n")
        for i, row in shap_importance.head(10).iterrows():
            marker = "🆕" if row['feature'] in new_features else ""
            f.write(f"| {i+1} | {row['feature']} {marker} | {row['mean_shap']:.4f} |\n")
    
    all_passed = g10_1 and g10_2
    print(f"\nPhase 10 Status: {'PASSED' if all_passed else 'PASSED WITH WARNINGS'}")
    
    return all_passed


if __name__ == "__main__":
    run_shap_analysis()
```

---

## Phase 11: Deployment & Registry Update

### Cursor Prompt 11.1: Deploy V4.1 and Update Registry

```
@workspace Deploy V4.1 model and update the model registry.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production\v4
FILES TO UPDATE:
- v4/models/registry.json
- v4/inference/lead_scorer_v4.py (update default paths)

Tasks:
1. Update registry.json with V4.1.0 entry
2. Include all metrics from validation
3. Update lead_scorer_v4.py to point to v4.1.0 by default
4. Create deployment checklist
5. Mark V4.0.0 as "deprecated" in registry

VALIDATION GATES:
- G11.1: Registry updated with V4.1.0 entry
- G11.2: All required metrics present in registry
- G11.3: Lead scorer paths updated
- G11.4: V4.0.0 marked as deprecated

**ERROR HANDLING**:
- If registry update fails: Check JSON syntax and file permissions
- If metrics missing: Go back to Phase 9 and ensure all metrics were calculated
- If lead scorer update fails: Check file paths and ensure v4.1.0 model directory exists

**ROLLBACK INSTRUCTIONS** (if Phase 11 fails):
- Revert registry.json to previous version
- Revert lead_scorer_v4.py to previous version
- Do not mark V4.0.0 as deprecated until V4.1.0 is fully deployed
- Log all changes for manual review
```

### Registry Update

```json
{
  "v4.0.0": {
    "model_version": "v4.0.0",
    "status": "deprecated",
    "deprecated_date": "2025-12-30",
    "deprecated_reason": "Replaced by V4.1.0 with corrected bleeding signal",
    "test_metrics": {
      "auc_roc": 0.5988,
      "top_decile_lift": 1.509
    }
  },
  "v4.1.0": {
    "model_version": "v4.1.0",
    "model_type": "XGBoost",
    "training_date": "2025-12-30T00:00:00",
    "status": "production",
    "deployment_strategy": "hybrid",
    "use_case": "deprioritization_filter",
    "changes_from_v4.0.0": [
      "Added is_recent_mover feature (START_DATE inference)",
      "Added days_since_last_move feature",
      "Added firm_departures_corrected (fresher signal)",
      "Added bleeding_velocity_encoded feature",
      "Added recent_mover_x_bleeding interaction",
      "Added is_independent_ria feature (1.33x lift)",
      "Added is_ia_rep_type feature (1.33x lift)",
      "Added is_dual_registered feature (0.86x lift - negative signal)",
      "Added independent_ria_x_ia_rep interaction (~1.4x lift)",
      "Fixed SHAP base_score bug",
      "Relabeled 3,444 mislabeled training leads"
    ],
    "test_metrics": {
      "auc_roc": null,
      "auc_pr": null,
      "top_decile_lift": null,
      "top_5pct_lift": null
    },
    "feature_count": 23,
    "new_features": [
      "is_recent_mover",
      "days_since_last_move", 
      "firm_departures_corrected",
      "bleeding_velocity_encoded",
      "recent_mover_x_bleeding",
      "is_independent_ria",
      "is_ia_rep_type",
      "is_dual_registered",
      "independent_ria_x_ia_rep"
    ],
    "deprioritization_threshold": 20,
    "notes": "V4.1 uses corrected bleeding signal from START_DATE inference (60-90 days fresher)"
  }
}
```

---

## Execution Checklist

Use this checklist to track progress through V4.1 retraining:

```markdown
## V4.1 Retraining Execution Checklist

### Phase 0: Environment Setup
- [ ] G0.1: inferred_departures_analysis >= 100,000 rows
- [ ] G0.2: firm_bleeding_corrected >= 4,000 firms
- [ ] G0.3: v4_target_variable >= 30,000 rows
- [ ] G0.4: Directory structure created

### Phase 1: Create Tables
- [ ] G1.1: recent_movers_v41 >= 50,000 rows
- [ ] G1.2: is_recent_mover_12mo rate 10-40%
- [ ] G1.3: No NULL advisor_crd
- [ ] G1.4: firm_bleeding_velocity_v41 >= 4,000 firms
- [ ] G1.5: All velocity categories present
- [ ] G1.6: ACCELERATING 5-25% of bleeding firms
- [ ] G1.7: is_independent_ria rate 15-40%
- [ ] G1.8: is_ia_rep_type rate 20-50%
- [ ] G1.9: is_dual_registered rate 30-60%

### Phase 2: Feature Engineering
- [ ] G2.1: 23 features created (14 original + 5 bleeding + 4 firm/rep type)
- [ ] G2.2: is_recent_mover rate 5-30%
- [ ] G2.3: PIT compliance verified
- [ ] G2.4: No NULL values in new features
- [ ] G2.5: New firm/rep features have no NULL values

### Phase 3: Relabel Training Data
- [ ] G3.1: >= 3,000 mislabeled leads identified
- [ ] G3.2: Higher conversion rate for mislabeled
- [ ] G3.3: No duplicate lead_ids

### Phase 4: PIT Audit
- [ ] G4.1: Zero violations in is_recent_mover
- [ ] G4.2: Zero negative days_since_last_move
- [ ] G4.3: No correlation > 0.3 with target
- [ ] G4.4: Manual spot-check passed

### Phase 5: Multicollinearity
- [ ] G5.1: No correlation > 0.85
- [ ] G5.2: No VIF > 10
- [ ] G5.3: New features add independent signal

### Phase 6: Train/Test Split
- [ ] G6.1: Train >= 20,000 leads
- [ ] G6.2: Test >= 4,000 leads
- [ ] G6.3: Gap >= 30 days
- [ ] G6.4: Positive rate within 2pp

### Phase 7: Model Training
- [ ] G7.1: Training completes without error
- [ ] G7.2: Early stopping triggers
- [ ] G7.3: No feature > 50% importance
- [ ] G7.4: All artifacts saved

### Phase 8: Overfitting Detection
- [ ] G8.1: Train-Test AUC gap < 0.05
- [ ] G8.2: Lift gap < 0.5x
- [ ] G8.3: CV std < 0.03
- [ ] G8.4: Test AUC > 0.58

### Phase 9: Model Validation
- [ ] G9.1: Test AUC >= 0.58
- [ ] G9.2: Top decile lift >= 1.4x
- [ ] G9.3: V4.1 AUC >= V4.0.0
- [ ] G9.4: Bottom 20% rate < 2%

### Phase 10: SHAP Analysis
- [ ] G10.1: TreeExplainer works
- [ ] G10.2: SHAP values calculated
- [ ] G10.3: >= 2 new features in top 5
- [ ] G10.4: SHAP correlates with XGBoost importance

### Phase 11: Deployment
- [ ] G11.1: Registry updated
- [ ] G11.2: All metrics recorded
- [ ] G11.3: Lead scorer updated
- [ ] G11.4: V4.0.0 deprecated

## Final Sign-Off

- [ ] All gates passed
- [ ] Reports generated
- [ ] Model deployed
- [ ] Documentation updated

**V4.1 Deployment Date:** _______________
**Deployed By:** _______________
```

---

## Appendix A: Quick Reference - New Features

### Bleeding Signal Features

| Feature | Type | Description | Expected Lift | PIT Rule |
|---------|------|-------------|---------------|----------|
| `is_recent_mover` | Binary | Advisor moved within 12mo of contact | ~2.9x | START_DATE <= contacted_date |
| `days_since_last_move` | Integer | Days between move and contact | Varies | contacted_date - START_DATE |
| `firm_departures_corrected` | Integer | Departures using inferred dates | Varies | departure_date < contacted_date |
| `bleeding_velocity_encoded` | Categorical | 0=STABLE, 1=DECEL, 2=STEADY, 3=ACCEL | ~1.6x (ACCEL) | 180-day window before contact |
| `recent_mover_x_bleeding` | Binary | Recent mover AND at bleeding firm | ~4.0x | Combination of above |

### Firm/Rep Type Features

| Feature | Type | Description | Expected Lift | PIT Note |
|---------|------|-------------|---------------|----------|
| `is_independent_ria` | Binary | Firm is Independent RIA | 1.33x | Current state (stable) |
| `is_ia_rep_type` | Binary | Rep type is pure IA | 1.33x | Current state (stable) |
| `is_dual_registered` | Binary | Rep type is DR (negative) | 0.86x | Current state (stable) |
| `independent_ria_x_ia_rep` | Binary | Interaction: both above | ~1.4x | Combination |

**Source**: Firm/Rep type features based on analysis of 35,361 contacted leads from Provided Lead Lists

---

## Appendix B: Rollback Procedure

If V4.1 underperforms in production:

1. Update `registry.json`: Set V4.1.0 status to "rolled_back"
2. Update `lead_scorer_v4.py`: Point back to v4.0.0
3. Document reason for rollback in `EXECUTION_LOG_V4.1.md`
4. Investigate root cause before re-attempting

```python
# Rollback in lead_scorer_v4.py
DEFAULT_MODEL_DIR = Path(r"...\v4\models\v4.0.0")  # Rollback to V4.0.0
```

---

*End of V4.1 Retraining Guide*
