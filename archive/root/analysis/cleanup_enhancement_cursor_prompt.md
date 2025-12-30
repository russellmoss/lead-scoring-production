# Repository Cleanup Enhancement - Comprehensive Cursor.ai Prompt

**Purpose**: This prompt enhances the existing `recommended_cleanup.md` plan by addressing identified gaps, adding missing components, and creating comprehensive documentation.

**Working Directory**: `C:\Users\russe\Documents\lead_scoring_production`

---

## Overview of Gaps Identified

After comprehensive analysis of the repository, the following gaps and enhancements are needed:

| Gap | Priority | Impact |
|-----|----------|--------|
| 1. Recyclable Lead Pipeline not documented | HIGH | Production pipeline missing from plan |
| 2. docs/ folder preservation unclear | HIGH | Critical FINTRX documentation |
| 3. BigQuery table cleanup not addressed | MEDIUM | Deprecated tables consuming resources |
| 4. Predictive RIA Movement Model structure | MEDIUM | Future development placeholder |
| 5. MODEL_EVOLUTION_HISTORY.md content | HIGH | Core deliverable needs specification |
| 6. Salesforce integration documentation | HIGH | Production-critical sync scripts |
| 7. validation/ folder not addressed | MEDIUM | Important validation scripts |
| 8. SHAP analysis lessons learned | MEDIUM | Valuable debugging insights |
| 9. Model registry consolidation | LOW | Two registries → one |
| 10. Quick Start guides preservation | MEDIUM | User-facing documentation |
| 11. Firm exclusions documentation | HIGH | Production-critical exclusion logic |
| 12. Cursor prompt methodology preservation | LOW | Historical methodology reference |

---

## PHASE 0: Pre-Cleanup Audit

### Prompt 0.1: Complete File Inventory

```
@workspace Before starting cleanup, create a complete inventory of all files in the repository.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

Task:
1. Create file: `cleanup/pre_cleanup_inventory.md`

2. Generate inventory with the following structure:
```markdown
# Pre-Cleanup File Inventory
Generated: [DATE]

## Summary Statistics
- Total files: [COUNT]
- Total directories: [COUNT]
- Total size: [SIZE]

## Files by Extension
| Extension | Count | Total Size |
|-----------|-------|------------|
| .md | X | X MB |
| .sql | X | X MB |
| .py | X | X MB |
| .json | X | X MB |
| .pkl | X | X MB |
| Other | X | X MB |

## Files by Directory
### Root (/)
- [LIST ALL FILES]

### v3/
- [LIST ALL FILES RECURSIVELY]

### v4/
- [LIST ALL FILES RECURSIVELY]

### pipeline/
- [LIST ALL FILES RECURSIVELY]

### docs/
- [LIST ALL FILES RECURSIVELY]

### validation/
- [LIST ALL FILES RECURSIVELY]
```

3. This inventory will serve as the "before" snapshot for cleanup validation.
```

### Prompt 0.2: BigQuery Table Inventory

```
@workspace Create an inventory of all BigQuery tables in ml_features dataset.

Task:
1. Run the following query in BigQuery:
```sql
SELECT 
    table_name,
    ROUND(size_bytes / 1024 / 1024, 2) as size_mb,
    row_count,
    creation_time,
    CASE 
        WHEN table_name LIKE '%v4.0%' THEN 'DEPRECATED'
        WHEN table_name LIKE '%v4.1.0%' AND table_name NOT LIKE '%r3%' THEN 'DEPRECATED'
        WHEN table_name LIKE '%old%' OR table_name LIKE '%backup%' THEN 'DEPRECATED'
        WHEN table_name LIKE '%test%' THEN 'TEST'
        ELSE 'ACTIVE'
    END as status
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
ORDER BY creation_time DESC;
```

2. Create file: `cleanup/bigquery_table_inventory.md` with results

3. Identify tables for:
   - KEEP (production)
   - ARCHIVE (historical reference)
   - DELETE (deprecated/test)
```

---

## PHASE 1: Create MODEL_EVOLUTION_HISTORY.md (Enhanced)

### Prompt 1.1: Create Comprehensive Evolution Document

```
@workspace Create the MODEL_EVOLUTION_HISTORY.md document capturing all institutional knowledge.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

Task:
1. Create file: `MODEL_EVOLUTION_HISTORY.md`

2. Use the following comprehensive template:

```markdown
# Lead Scoring Model Evolution History

**Document Purpose**: Comprehensive record of model development, lessons learned, and institutional knowledge preserved during repository cleanup (December 2025).

**Current Production**: V3.3 (Rules-Based Prioritization) + V4.1.0 R3 (XGBoost Deprioritization) Hybrid

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Version Timeline](#version-timeline)
3. [V1: Initial Attempt](#v1-initial-attempt)
4. [V2: First ML Model](#v2-first-ml-model)
5. [V3: Rules-Based Success](#v3-rules-based-success)
6. [V4: ML Redemption](#v4-ml-redemption)
7. [Hybrid Strategy](#hybrid-strategy)
8. [Key Lessons Learned](#key-lessons-learned)
9. [Technical Decisions Registry](#technical-decisions-registry)
10. [Feature Engineering Insights](#feature-engineering-insights)
11. [Data Leakage Prevention](#data-leakage-prevention)
12. [SHAP Analysis Journey](#shap-analysis-journey)
13. [Archived Files Reference](#archived-files-reference)

---

## Executive Summary

This document preserves the institutional knowledge accumulated across 4+ major model versions developed between [START_DATE] and December 2025. The current hybrid approach combines:

- **V3.3 Rules-Based Model**: Identifies HIGH-priority leads (top ~5%) with 3.69x+ lift
- **V4.1.0 R3 XGBoost Model**: Identifies LOW-priority leads (bottom 20%) to skip

**Key Insight**: ML excels at identifying who NOT to contact, while business rules excel at identifying who TO contact.

---

## Version Timeline

| Version | Date | Approach | Top Lift | Status | Key Learning |
|---------|------|----------|----------|--------|--------------|
| V1 | [DATE] | [APPROACH] | [X]x | Deprecated | [LESSON] |
| V2 | Pre-Dec 2024 | XGBoost (20 features) | 1.50x | Deprecated | Data leakage killed it |
| V3.0 | Dec 2024 | Rules-based tiers | 3.69x | Deprecated | Simplicity wins |
| V3.2 | Dec 21, 2024 | 7→5 tier consolidation | 3.69x | Deprecated | Operational simplicity |
| V3.3 | Dec 2025 | Bleeding signal refinement | 4.30x (T1A) | **Production** | Inferred departures fresher |
| V4.0.0 | Dec 24, 2025 | XGBoost (14 features) | 1.51x | Deprecated | Good for deprioritization |
| V4.1.0 R1 | Dec 2025 | XGBoost (26 features) | ~1.8x | Deprecated | Overfitting issues |
| V4.1.0 R2 | Dec 2025 | XGBoost (22 features) | ~1.9x | Deprecated | SHAP issues |
| V4.1.0 R3 | Dec 30, 2025 | XGBoost (22 features) | 2.03x | **Production** | SHAP working via KernelExplainer |

---

## V1: Initial Attempt

### What Was Tried
[FILL FROM HISTORICAL KNOWLEDGE]

### Why It Failed
[FILL FROM HISTORICAL KNOWLEDGE]

### Key Lesson
[FILL FROM HISTORICAL KNOWLEDGE]

---

## V2: First ML Model

### Architecture
- **Algorithm**: XGBoost
- **Features**: 20
- **Training Period**: [DATES]
- **Performance**: 1.50x top decile lift

### The Data Leakage Disaster

**The Problem**: V2 included a feature called `days_in_gap` that calculated the time between employment records. This data was retrospectively backfilled—meaning the `end_date` of an employment record only exists AFTER the person leaves.

**Impact**:
- Feature showed strong signal (IV = 0.478)
- Model looked great in testing
- Would completely fail in production (data wouldn't exist at prediction time)

**Detection**: Discovered during V3 development when auditing all features for point-in-time validity.

**Prevention (V3+ Rule)**: 
> "NEVER use `end_date` from employment history. All features must be calculated from data available at `contacted_date`."

### Other V2 Issues
1. **Black Box Problem**: Sales team couldn't understand why leads were scored high
2. **Low Adoption**: Without explainability, trust was low
3. **CV Implementation**: Issues with temporal ordering in cross-validation

---

## V3: Rules-Based Success

### Why Rules Beat ML

| Aspect | V2 ML | V3 Rules |
|--------|-------|----------|
| Top Lift | 1.50x | 3.69x |
| Explainability | None | Full |
| Sales Trust | Low | High |
| Maintenance | Retrain | Edit SQL |
| Data Leakage Risk | High | Low |

### Key V3 Innovations

1. **Point-in-Time Methodology**
   - Fixed analysis_date = '2025-10-31'
   - Virtual snapshot construction from historical tables
   - Zero leakage audit

2. **Small Firm Signal Discovery**
   - Firms with ≤10 reps convert 3.5x better
   - This became a Tier 1 path

3. **Certification Boost (V3.2.1)**
   - CFP at bleeding firm: 16.44% conversion
   - Series 65 only: 16.48% conversion

4. **Bleeding Signal Refinement (V3.3)**
   - Use inferred departures (60-90 days fresher)
   - Removed TIER_5_HEAVY_BLEEDER (converted below baseline)
   - Added bleeding velocity detection

### V3 Tier Evolution

| Original (V3.0) | Consolidated (V3.2) | Current (V3.3) |
|-----------------|---------------------|----------------|
| T1A, T1B, T1C | T1_PRIME_MOVER | T1A_CFP, T1B_S65, T1_PRIME |
| T2A | T2_PROVEN_MOVER | T2_PROVEN_MOVER |
| T2B | T3_MODERATE_BLEEDER | T3_MODERATE_BLEEDER |
| T3 | T4_EXPERIENCED_MOVER | T4_EXPERIENCED_MOVER |
| T4 | T5_HEAVY_BLEEDER | **REMOVED** |

---

## V4: ML Redemption

### The Insight That Saved ML

**Key Realization**: ML doesn't have to beat rules at prioritization. ML can excel at DEPRIORITIZATION.

**V4 Performance**:
- Top decile lift: 1.51x → 2.03x (V4.1 R3)
- Bottom 20% conversion: 1.33% (vs 3.20% baseline)
- Skip 20% of leads, lose only 8.3% of conversions = **11.7% efficiency gain**

### V4.1 Feature Engineering

**New Features Added**:
- `is_recent_mover` - Changed firms in last 2 years
- `days_since_last_move` - Freshness of movement signal
- `firm_departures_corrected` - Inferred departures (fresher)
- `bleeding_velocity_encoded` - Accelerating vs decelerating bleeding
- `is_independent_ria` - Firm type signal
- `is_ia_rep_type` - Rep type signal
- `is_dual_registered` - Dual registration flag

**Removed Features (Multicollinearity)**:
- `industry_tenure_months` (r=0.96 with experience_years)
- `tenure_bucket_x_mobility` (r=0.94 with mobility_3yr)
- `independent_ria_x_ia_rep` (r=0.97 with is_ia_rep_type)
- `recent_mover_x_bleeding` (r=0.90 with is_recent_mover)

### SHAP Analysis Journey

**Challenge**: TreeExplainer wouldn't work with our XGBoost model.

**Attempts**:
1. `phase_10_shap_analysis_v41.py` - TreeExplainer failed
2. `phase_10_shap_fix.py` - Still failed
3. `phase_10_shap_analysis_v41_r2.py` - Sampling approach, partial success
4. `phase_10_shap_analysis_v41_r3.py` - **KernelExplainer worked!**

**Solution**: Use KernelExplainer with background sampling (100 samples). Slower but reliable.

**Lesson**: Document which SHAP explainer works with which model type.

---

## Hybrid Strategy

### How V3.3 + V4.1 R3 Work Together

```
Lead Scoring Pipeline:
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   All Leads     │────▶│  V3.3 Tier       │────▶│  V4.1 Score     │
│   (~50,000)     │     │  Assignment      │     │  Percentile     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                │                         │
                                ▼                         ▼
                    ┌───────────────────────────────────────────┐
                    │           HYBRID PRIORITY LOGIC           │
                    ├───────────────────────────────────────────┤
                    │ V3 T1 + V4 top 50%  → HIGHEST PRIORITY    │
                    │ V3 T1 + V4 bottom 50% → HIGH (verify)     │
                    │ V3 Standard + V4 top 20% → UPGRADE        │
                    │ V3 Standard + V4 bottom 20% → SKIP        │
                    └───────────────────────────────────────────┘
```

### Expected Business Impact

| Scenario | Leads Contacted | Expected Conversions | Efficiency |
|----------|-----------------|----------------------|------------|
| No model | 6,000 | 192 | Baseline |
| V3 only (priority tiers) | 600 | ~33 | 1.74x lift |
| V4 filter (skip bottom 20%) | 4,800 | 176 | +11.7% efficiency |
| **Hybrid (V3 + V4)** | ~4,800 | ~180+ | **Best of both** |

---

## Key Lessons Learned

### 1. Data Leakage Prevention (CRITICAL)

**Rules**:
1. NEVER use `end_date` from employment history
2. ALWAYS use point-in-time methodology
3. Fixed analysis_date prevents training drift
4. Audit all features for temporal validity

**Audit Query**:
```sql
SELECT COUNTIF(feature_calculation_date > contacted_date) as leakage_count
FROM feature_table
-- Result must be 0
```

### 2. Explainability Matters More Than Accuracy

Even a 2x better model is useless if sales team won't use it. V3 rules with 3.69x lift and full explainability beat V2 ML with 1.50x lift and zero explainability.

### 3. ML is Better at "Don't Contact" Than "Do Contact"

The insight that saved V4: use ML for deprioritization, not prioritization.

### 4. Small Firms Convert Better

Discovery from V3.2 analysis: firms with ≤10 reps convert 3.5x better than baseline. This became a Tier 1 qualification path.

### 5. Certification Signals Work

CFP holders at bleeding firms: 16.44% conversion (4.30x lift)
Series 65 only at bleeding firms: 16.48% conversion (4.31x lift)

### 6. Bleeding Signals Need Freshness

- Inferred departures (from current vs historical rep counts) are 60-90 days fresher
- Bleeding velocity (accelerating vs decelerating) improves signal
- Heavy bleeders (10+ departures) convert BELOW baseline—removed in V3.3

### 7. SHAP Explainer Compatibility

| Model Type | TreeExplainer | KernelExplainer |
|------------|---------------|-----------------|
| XGBoost (our model) | ❌ Failed | ✅ Works |
| Random Forest | ✅ Works | ✅ Works |
| Linear Models | N/A | ✅ Works |

---

## Technical Decisions Registry

| Decision | Date | Context | Outcome |
|----------|------|---------|---------|
| Use rules over ML for prioritization | Dec 2024 | V2 had data leakage | V3 achieved 3.69x lift |
| Fixed analysis_date | Dec 2024 | CURRENT_DATE() caused drift | Stable training sets |
| 7 tiers → 5 tiers consolidation | Dec 21, 2025 | Operational complexity | Simpler without lift loss |
| Use ML for deprioritization | Dec 24, 2025 | V4 didn't beat V3 at top | 11.7% efficiency gain |
| KernelExplainer for SHAP | Dec 30, 2025 | TreeExplainer failed | SHAP narratives working |
| Remove TIER_5_HEAVY_BLEEDER | Dec 2025 | Converted below baseline | Improved overall lift |

---

## Feature Engineering Insights

### Features That Work

| Feature | Signal | Why It Works |
|---------|--------|--------------|
| `tenure_months` (1-4 years) | Strong | Mid-tenure = peak portability |
| `firm_net_change_12mo` | Strong | Firm instability = opportunity |
| `is_wirehouse` = 0 | Strong | Non-wirehouse = more portable |
| `has_cfp` | Strong | Quality signal, portable credential |
| `mobility_3yr` | Moderate | Past movement predicts future |
| `bleeding_velocity` | Moderate | Accelerating bleeding = urgent |

### Features That Don't Work

| Feature | Why It Failed |
|---------|---------------|
| `days_in_gap` | Data leakage (retrospective) |
| `rep_aum` | 99.1% NULL rate |
| `wealth_team_aum` | 87% NULL rate |
| `heavy_bleeder` (10+) | Converts below baseline |

### Features to Explore (Future)

| Feature | Hypothesis | Data Source |
|---------|------------|-------------|
| Economic indicators | Movement correlates with economy | External (BLS, Fed) |
| Seasonality | Q1/Q4 may have patterns | Historical analysis |
| News mentions | Recent news = activity signal | ria_contact_news |

---

## Archived Files Reference

### V3 Development Archives
Location: `archive/v3_development/`

| File | Purpose | Key Insight |
|------|---------|-------------|
| `run_phase_*.py` | Training scripts | Point-in-time methodology |
| `EXECUTION_LOG.md` | Execution history | Phase-by-phase decisions |
| `backtest_*.sql` | Historical validation | 5.12x average backtest lift |

### V4 Development Archives
Location: `archive/v4_development/`

| File | Purpose | Key Insight |
|------|---------|-------------|
| `v4.0.0/` | Original V4 model | Deprioritization discovery |
| `v4.1.0/`, `v4.1.0_r2/` | Iteration attempts | Multicollinearity fixes |
| `phase_10_shap_*.py` | SHAP debugging | KernelExplainer solution |
| `EXECUTION_LOG_V4.1.md` | V4.1 development log | R1→R2→R3 progression |

### Analysis Archives
Location: `archive/root_analysis/`

| File | Purpose | Key Insight |
|------|---------|-------------|
| `bleeding_exploration*.md` | Bleeding signal analysis | Inferred departures fresher |
| `final_bleed_analysis*.md` | Final bleeding conclusions | Heavy bleeders underperform |
| `*update_guide*.md` | Version upgrade guides | Step-by-step methodology |

---

## Document Maintenance

**Last Updated**: [DATE]
**Updated By**: [NAME]
**Next Review**: [DATE + 6 months]

When updating this document:
1. Add new lessons to appropriate sections
2. Update version timeline
3. Add new technical decisions
4. Archive superseded information

---

*This document preserves institutional knowledge that took months to accumulate. Please maintain it carefully.*
```

3. Populate the template by:
   - Searching for version history in existing documentation
   - Reading EXECUTION_LOG files for timeline details
   - Extracting lessons from VERSION_*_MODEL_REPORT.md files
   - Reviewing Cursor prompt files for methodology

4. Save the completed document.
```

---

## PHASE 2: Address Missing Pipeline Documentation

### Prompt 2.1: Document Recyclable Lead Pipeline

```
@workspace The recyclable lead pipeline is a production system that's not well-covered in the cleanup plan. Document it properly.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

Task:
1. Read the following files to understand the recyclable pipeline:
   - pipeline/Monthly_Recyclable_Lead_List_Generation_Guide_V2.md
   - pipeline/sql/recycling/recyclable_pool_master_v2.1.sql
   - pipeline/scripts/recycling/ (if exists)

2. Update `recommended_cleanup.md` to add a new section under "### 4. pipeline/ Directory" that explicitly covers:

```markdown
### 4.1 Recyclable Lead Pipeline (KEEP - Production)

#### Production Files ✅
```
pipeline/
├── sql/
│   └── recycling/
│       └── recyclable_pool_master_v2.1.sql  # Production SQL
├── scripts/
│   └── recycling/
│       └── generate_recyclable_list_v2.1.py  # Production script
└── Monthly_Recyclable_Lead_List_Generation_Guide_V2.md  # User guide
```

#### Key Logic (V2 - Corrected)
- **EXCLUDE** people who changed firms < 2 years ago (just settled in)
- **INCLUDE** people who changed firms 2-3 years ago (may be restless)
- **HIGHEST PRIORITY**: High V4 score + long tenure + no recent move

#### Monthly Output
- Target: 600 recyclable leads
- Output: `exports/{month}_{year}_recyclable_leads.csv`
- Report: `reports/recycling_analysis/{month}_{year}_recyclable_list_report.md`
```

3. Ensure the recyclable pipeline files are in the KEEP section, not ARCHIVE.
```

### Prompt 2.2: Document Firm Exclusions System

```
@workspace The firm exclusions system is production-critical. Document it properly.

Task:
1. Read the following files:
   - pipeline/sql/create_excluded_firms_table.sql
   - pipeline/sql/create_excluded_firm_crds_table.sql
   - pipeline/CENTRALIZED_EXCLUSIONS_SUMMARY.md (if exists)

2. Create or update documentation: `docs/FIRM_EXCLUSIONS_GUIDE.md`

```markdown
# Firm Exclusions System Guide

## Overview
Centralized firm exclusion system that filters out inappropriate leads from all scoring pipelines.

## Exclusion Types

### Pattern-Based Exclusions (excluded_firms table)
Firms excluded by name pattern matching:
- Insurance companies (`%INSURANCE%`)
- Banks (`%BANK%`, `%BANKING%`)
- Known non-targets

### CRD-Based Exclusions (excluded_firm_crds table)
Specific firm CRDs excluded individually:
- Firms that requested removal
- Known competitors
- Compliance-flagged firms

## BigQuery Tables
- `ml_features.excluded_firms` - Pattern exclusions
- `ml_features.excluded_firm_crds` - CRD exclusions

## How to Add Exclusions

### Add Pattern Exclusion
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firms`
(pattern, reason, added_date, added_by)
VALUES ('%NEW_PATTERN%', 'Reason for exclusion', CURRENT_DATE(), 'Your Name');
```

### Add CRD Exclusion
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firm_crds`
(firm_crd, firm_name, reason, added_date, added_by)
VALUES (123456, 'Firm Name', 'Reason for exclusion', CURRENT_DATE(), 'Your Name');
```

## Usage in Queries
All lead scoring queries should include:
```sql
WHERE c.PRIMARY_FIRM NOT IN (
    SELECT firm_crd FROM `ml_features.excluded_firm_crds`
)
AND NOT EXISTS (
    SELECT 1 FROM `ml_features.excluded_firms` ef
    WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.pattern
)
```
```

3. Add this file to the KEEP list in `recommended_cleanup.md`.
```

---

## PHASE 3: Preserve Critical Documentation

### Prompt 3.1: Consolidate docs/ Folder

```
@workspace The docs/ folder contains critical FINTRX documentation. Preserve and organize it.

Task:
1. Verify these files exist and are in KEEP list:
   - docs/FINTRX_Data_Dictionary.md
   - docs/FINTRX_Architecture_Overview.md
   - docs/FINTRX_Lead_Scoring_Features.md (if exists)

2. Update `recommended_cleanup.md` to add explicit docs/ section:

```markdown
### 5. docs/ Directory

#### KEEP ✅ (Critical Reference Documentation)
```
docs/
├── FINTRX_Data_Dictionary.md        # Field-level documentation for all 25 FINTRX tables
├── FINTRX_Architecture_Overview.md  # Dataset architecture and PIT limitations
├── FINTRX_Lead_Scoring_Features.md  # Feature engineering documentation
└── FIRM_EXCLUSIONS_GUIDE.md         # Firm exclusion system (NEW)
```

#### Why These Are Critical
- **Data Dictionary**: Essential for any new feature engineering
- **Architecture Overview**: Documents PIT limitations (what CAN'T be done)
- **Lead Scoring Features**: Maps features to source tables
- **Firm Exclusions**: Production-critical exclusion logic

#### DO NOT ARCHIVE
These documents represent months of data exploration and are essential for:
- Onboarding new team members
- Future model development
- Debugging data issues
```

3. If any docs are missing, create placeholder files noting they need to be created.
```

### Prompt 3.2: Preserve Quick Start Guides

```
@workspace Preserve user-facing quick start guides.

Task:
1. Locate and verify these files:
   - v3/docs/QUICK_START_LEAD_LISTS.md
   - v3/docs/LEAD_LIST_GENERATION_GUIDE.md
   - pipeline/sql/EXECUTE_JANUARY_2026_LEAD_LIST.md
   - pipeline/sql/READY_TO_EXECUTE.md

2. Update `recommended_cleanup.md` to ensure these are in KEEP section.

3. Consider consolidating into single `docs/QUICK_START_GUIDE.md` that covers:
   - Monthly lead list generation
   - Recyclable lead list generation
   - Salesforce sync process
   - Validation queries
```

---

## PHASE 4: BigQuery Cleanup Plan

### Prompt 4.1: Create BigQuery Cleanup Documentation

```
@workspace Create a BigQuery table cleanup plan.

Task:
1. Create file: `cleanup/BIGQUERY_CLEANUP_PLAN.md`

```markdown
# BigQuery Table Cleanup Plan

## Dataset: `savvy-gtm-analytics.ml_features`

### Tables to KEEP (Production)

| Table | Purpose | Size | Last Updated |
|-------|---------|------|--------------|
| `lead_scores_v3` | V3 production scores | [SIZE] | [DATE] |
| `lead_scores_v3_2_12212025` | V3.2 consolidated | [SIZE] | [DATE] |
| `v4_prospect_features` | V4.1 features | [SIZE] | [DATE] |
| `v4_prospect_scores` | V4.1 scores | [SIZE] | [DATE] |
| `january_2026_lead_list` | Current lead list | [SIZE] | [DATE] |
| `excluded_firms` | Pattern exclusions | [SIZE] | [DATE] |
| `excluded_firm_crds` | CRD exclusions | [SIZE] | [DATE] |

### Tables to ARCHIVE (Keep for Reference)

| Table | Purpose | Archive Reason |
|-------|---------|----------------|
| `lead_scores_v3_1_*` | V3.1 scores | Superseded by V3.2 |
| `v4_prospect_features_v40` | V4.0 features | Superseded by V4.1 |

### Tables to DELETE

| Table | Reason |
|-------|--------|
| `*_test_*` | Test tables |
| `*_backup_*` | Temporary backups |
| `*_old_*` | Explicitly deprecated |
| `january_2026_lead_list_v4` | Replaced by hybrid list |
| `january_2026_excluded_v3_v4_disagreement` | Temporary analysis |

### Cleanup SQL

```sql
-- Run AFTER verifying production tables work
-- DELETE deprecated tables
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`;
DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.january_2026_excluded_v3_v4_disagreement`;

-- Archive old versions (create snapshots first if needed)
-- DROP TABLE IF EXISTS `savvy-gtm-analytics.ml_features.lead_scores_v3_1_*`;
```

### Validation Before Cleanup

Run these queries to ensure production tables are working:

```sql
-- Verify V3 scores
SELECT COUNT(*) as v3_count FROM `ml_features.lead_scores_v3`;

-- Verify V4 scores
SELECT COUNT(*) as v4_count FROM `ml_features.v4_prospect_scores`;

-- Verify January lead list
SELECT COUNT(*) as jan_count FROM `ml_features.january_2026_lead_list`;
```
```

2. Add reference to this file in `recommended_cleanup.md`.
```

---

## PHASE 5: Future Development Structure

### Prompt 5.1: Create Placeholder for Predictive RIA Movement Model

```
@workspace The user mentioned working on a Predictive RIA Advisor Movement Model. Create a placeholder structure.

Task:
1. Create directory structure:
```
predictive_movement/
├── README.md
├── docs/
│   └── MODEL_DESIGN.md
├── data/
│   └── .gitkeep
├── sql/
│   └── .gitkeep
├── scripts/
│   └── .gitkeep
└── models/
    └── .gitkeep
```

2. Create `predictive_movement/README.md`:

```markdown
# Predictive RIA Advisor Movement Model

**Status**: Planning / Development
**Started**: [DATE]

## Overview

This model correlates movement of "priority advisors" (those fitting our ICP) with economic metrics to:
1. Determine when to alert the team that conditions favor advisor movement
2. Identify when market conditions require higher funnel volume

## Hypotheses

1. Advisor movement correlates with economic indicators (unemployment, market volatility, etc.)
2. Movement patterns have seasonal components
3. Firm-level stress signals precede advisor departures

## Data Sources

### Internal
- Historical lead conversion data
- V3/V4 model features
- FINTRX historical snapshots

### External (To Explore)
- BLS unemployment data
- S&P 500 / VIX volatility
- Interest rate changes
- Industry news sentiment

## Planned Approach

1. **Phase 1**: Exploratory analysis of movement patterns
2. **Phase 2**: Correlate with economic indicators
3. **Phase 3**: Build predictive model
4. **Phase 4**: Create alerting system

## Key Questions

- What's the lag between economic signals and movement?
- Are there firm-specific early warning indicators?
- How do we define "good time for movement"?

## Files

- `docs/MODEL_DESIGN.md` - Detailed model design (TBD)
- `sql/` - Feature engineering queries
- `scripts/` - Analysis and model training scripts
- `models/` - Trained model artifacts
```

3. Create `predictive_movement/docs/MODEL_DESIGN.md`:

```markdown
# Predictive Movement Model Design

## Target Variable

**Definition**: Monthly aggregate metric of "favorable movement conditions"

Options:
1. Binary: Above/below historical average movement rate
2. Continuous: Movement rate (advisors who moved / total advisors)
3. Multi-class: Low / Medium / High movement months

## Features (Planned)

### Economic Indicators
| Feature | Source | Lag | Hypothesis |
|---------|--------|-----|------------|
| Unemployment rate | BLS | 0-3 months | Higher unemployment → more movement |
| S&P 500 YoY return | Yahoo Finance | 0 months | Poor returns → advisor dissatisfaction |
| VIX average | CBOE | 0 months | High volatility → uncertainty |
| Fed funds rate | FRED | 0-6 months | Rate changes → business model pressure |

### Internal Signals
| Feature | Source | Hypothesis |
|---------|--------|------------|
| Aggregate firm bleeding | FINTRX | More bleeding firms → more movement |
| New firm formations | FINTRX | New firms → opportunities |
| Avg tenure at contact | Lead data | Longer tenure → pent-up movement |

## Model Architecture

TBD - Options:
1. Time series regression
2. Classification with time features
3. ARIMA with exogenous variables

## Alerting System

TBD - Integrate with:
- Slack notifications
- Dashboard indicators
- Lead quota adjustments
```

4. Add this new directory to `recommended_cleanup.md` as a "NEW - Future Development" section.
```

---

## PHASE 6: Model Registry Consolidation

### Prompt 6.1: Consolidate Model Registries

```
@workspace There are two model registries (v3 and v4). Consider consolidating them.

Task:
1. Read current registries:
   - v3/models/model_registry_v3.json
   - v4/models/registry.json

2. Create consolidated registry: `models/UNIFIED_MODEL_REGISTRY.json`

```json
{
  "registry_version": "1.0.0",
  "last_updated": "2025-12-30",
  "production_models": {
    "prioritization": {
      "model": "v3.3",
      "type": "rules-based",
      "location": "v3/sql/generate_lead_list_v3.3.0.sql",
      "registry": "v3/models/model_registry_v3.json"
    },
    "deprioritization": {
      "model": "v4.1.0_r3",
      "type": "xgboost",
      "location": "v4/models/v4.1.0_r3/",
      "registry": "v4/models/registry.json"
    }
  },
  "hybrid_pipeline": {
    "location": "pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql",
    "strategy": "V3 prioritizes top, V4 filters bottom 20%"
  },
  "deprecated_models": [
    {"model": "v1", "deprecated_date": "[DATE]", "reason": "[REASON]"},
    {"model": "v2", "deprecated_date": "2024-12-01", "reason": "Data leakage"},
    {"model": "v3.0-v3.2", "deprecated_date": "2025-12-25", "reason": "Superseded by v3.3"},
    {"model": "v4.0.0", "deprecated_date": "2025-12-30", "reason": "Superseded by v4.1.0_r3"},
    {"model": "v4.1.0_r1", "deprecated_date": "2025-12-28", "reason": "Overfitting"},
    {"model": "v4.1.0_r2", "deprecated_date": "2025-12-29", "reason": "SHAP issues"}
  ]
}
```

3. Update `recommended_cleanup.md` to reference unified registry.

4. Keep individual registries (v3/v4) but note they're referenced by unified registry.
```

---

## PHASE 7: Update Cleanup Plan with All Changes

### Prompt 7.1: Final Update to recommended_cleanup.md

```
@workspace Update the recommended_cleanup.md with all identified enhancements.

Task:
1. Add new sections to recommended_cleanup.md:

```markdown
---

## Additional Sections (Added During Enhancement)

### 6. docs/ Directory (CRITICAL - Preserve)

See Prompt 3.1 above for details.

### 7. validation/ Directory

#### KEEP ✅
```
validation/
├── backtest_optimized_january_list.py  # Backtest validation script
└── [other validation scripts]
```

### 8. BigQuery Cleanup

See `cleanup/BIGQUERY_CLEANUP_PLAN.md` for table-level cleanup plan.

### 9. Future Development Structure

New directory for Predictive RIA Movement Model:
```
predictive_movement/
├── README.md
├── docs/MODEL_DESIGN.md
└── [placeholder directories]
```

### 10. Unified Model Registry

New consolidated registry at `models/UNIFIED_MODEL_REGISTRY.json` that references both V3 and V4 registries.

---

## Updated File Counts

### Before Cleanup (Estimated)
- Total files: ~200+
- Production files: ~30-40
- Archive candidates: ~100-150
- Delete candidates: ~30-50

### After Cleanup (Target)
- Production files: ~50 (including docs, validation, new structure)
- Archive files: ~100-150
- New documentation: ~5-10 files

---

## Enhanced Checklist

### Pre-Cleanup
- [ ] Complete file inventory (Prompt 0.1)
- [ ] BigQuery table inventory (Prompt 0.2)
- [ ] Create git branch: `cleanup/repository-consolidation`
- [ ] Full backup verified

### Phase 1: Documentation
- [ ] MODEL_EVOLUTION_HISTORY.md created (Prompt 1.1)
- [ ] Recyclable pipeline documented (Prompt 2.1)
- [ ] Firm exclusions documented (Prompt 2.2)
- [ ] docs/ folder consolidated (Prompt 3.1)
- [ ] Quick start guides preserved (Prompt 3.2)

### Phase 2: BigQuery Cleanup
- [ ] BigQuery cleanup plan created (Prompt 4.1)
- [ ] Production tables verified
- [ ] Deprecated tables identified

### Phase 3: Future Structure
- [ ] predictive_movement/ structure created (Prompt 5.1)
- [ ] Model registries consolidated (Prompt 6.1)

### Phase 4: File Cleanup
- [ ] Archive directories created
- [ ] Deprecated files moved to archive
- [ ] Temporary files removed

### Phase 5: Validation
- [ ] Production pipeline verified
- [ ] All documentation links working
- [ ] Team review completed
```

2. Save the updated file.
```

---

## Execution Summary

Run these prompts in order:

| Phase | Prompts | Duration | Risk |
|-------|---------|----------|------|
| 0. Audit | 0.1, 0.2 | 30 min | None |
| 1. Evolution Doc | 1.1 | 2-3 hours | None |
| 2. Pipeline Docs | 2.1, 2.2 | 1 hour | None |
| 3. Preserve Docs | 3.1, 3.2 | 30 min | None |
| 4. BigQuery Plan | 4.1 | 30 min | None |
| 5. Future Structure | 5.1 | 30 min | None |
| 6. Registry | 6.1 | 30 min | Low |
| 7. Final Update | 7.1 | 30 min | None |
| **Total** | **12 prompts** | **6-8 hours** | **Low** |

---

## Post-Enhancement Next Steps

After running all prompts:

1. **Review all created documentation** for accuracy
2. **Execute the file cleanup phases** from original plan
3. **Run BigQuery cleanup** after file cleanup is validated
4. **Team review** of new structure
5. **30-day monitoring period** before deleting archived files

---

**Document Created**: December 30, 2025
**Purpose**: Enhance repository cleanup plan with comprehensive coverage
**Status**: Ready for Execution
