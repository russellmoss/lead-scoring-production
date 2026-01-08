# Lead Scoring Production Pipeline - Hybrid V3 + V4 Model

**Version**: 3.6.1 (V4.3.2 Career Clock Fuzzy Firm Matching + Recent Promotee Exclusion)  
**Last Updated**: January 8, 2026  
**Status**: ✅ Production Ready  
**V3 Model**: V3.6.1_01082026_CAREER_CLOCK_TIERS - Career Clock tiers + Recent Promotee Exclusion + M&A tiers  
**V4 Model**: V4.3.2 (26 features with Career Clock fuzzy firm matching fix + Recent Promotee feature) - Updated January 8, 2026  
**Architecture**: Two-Query (bypasses BigQuery CTE optimization issues)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Quick Start Guide](#quick-start-guide)
3. [Required Files for Full Pipeline Execution](#required-files-for-full-pipeline-execution)
4. [Pipeline Architecture](#pipeline-architecture)
5. [Step-by-Step Execution](#step-by-step-execution)
6. [Model Logic & Methodology](#model-logic--methodology)
7. [V4 XGBoost Model Features](#v4-xgboost-model-features)
8. [Testing & Validation](#testing--validation)
9. [Troubleshooting](#troubleshooting)
10. [Appendix](#appendix)

---

## Executive Summary

This repository contains a **hybrid lead scoring system** that combines:

- **V3 Rules-Based Model**: Tiered classification with Career Clock tiers, Zero Friction, Sweet Spot, and M&A tiers (V3.6.0)
- **V4 XGBoost ML Model**: Machine learning model for deprioritization and backfill
- **Two-Query Architecture**: Reliable M&A lead insertion (bypasses BigQuery CTE issues)

**Key Results (January 2026 Lead List - V3.6.0):**
- **Total Leads**: 3,100 (2,800 standard + 300 M&A)
- **M&A Leads**: 300 (TIER_MA_ACTIVE_PRIME at 9.0% expected conversion)
- **Large Firm Exemption**: 293 M&A leads from firms with >200 reps (normally excluded)
- **Expected MQLs from M&A Tier**: ~27 additional MQLs (300 × 9.0%)
- **Architecture**: Two-query approach (INSERT after CREATE)

**V3.6.0 Tier Performance:**
- **Career Clock Tiers**: 0A (16.13%), 0B (10.0%), 0C (6.5%) - timing-aware prioritization
- **Zero Friction Tier**: 13.64% conversion (3.57x lift) - Series 65 + Portable Custodian + Small Firm + Bleeding
- **Sweet Spot Tier**: 9.09% conversion (2.38x lift) - Growth Stage + $500K-$2M AUM
- **M&A Tier Performance** (from V3.5.0, based on Commonwealth/LPL Analysis):
- **TIER_MA_ACTIVE_PRIME**: 9.0% conversion (2.36x baseline) - Senior titles + mid-career at M&A targets
- **TIER_MA_ACTIVE**: 5.4% conversion (1.41x baseline) - All advisors at M&A target firms
- **Evidence**: Commonwealth Financial Network converted at 5.37% during LPL acquisition (242 contacts, 13 MQLs)

**Why M&A Tiers Matter:**
- Large firms (>50 reps) normally convert at 0.60x baseline → we exclude them
- But M&A disruption changes dynamics → Commonwealth converted at 5.37% during acquisition
- Without M&A tiers, we would miss 100-500 MQLs per major M&A event

**V4.3.2 Model Performance (January 8, 2026 Update):**
- **Features**: 26 (added 2 Career Clock features + 1 Recent Promotee feature: cc_is_in_move_window, cc_is_too_early, is_likely_recent_promotee)
- **Test AUC-ROC**: 0.6322 (slightly below V4.3.0's 0.6389, but acceptable after data quality fix)
- **Top Decile Lift**: 2.40x
- **Overfitting Gap**: 0.0480 (within acceptable range < 0.05)
- **Narrative Generation**: Gain-based (SHAP fix deferred to V4.4.0 due to XGBoost/SHAP compatibility issue)
- **Recent Promotee Feature Importance**: is_likely_recent_promotee = 2.39% of total gain (model learning the pattern)
- **Career Clock Feature Importance**: 0.0% (may be due to data quality fix removing polluted data)
- **V4.3.2 Fix**: Fuzzy firm name matching for re-registrations - excludes ~135 advisors incorrectly in move window

**Monthly Time Estimate**: 15-20 minutes once pipeline is set up

---

## Quick Start Guide

### Prerequisites

Before starting, ensure you have:

- ✅ Access to BigQuery project: `savvy-gtm-analytics`
- ✅ V4.3.1 model files in `v4/models/v4.3.1/` (used by V4.3.2):
  - `v4.3.1_model.json` (XGBoost model)
  - `v4.3.1_feature_importance.csv` (gain-based importance for narratives)
  - `v4.3.1_metadata.json` (training metrics and validation results)
  - `v4.3.1_shap_metadata.json` (SHAP configuration - note: SHAP fix deferred)
- ✅ Python environment with required packages:
  ```bash
  pip install xgboost pandas google-cloud-bigquery numpy
  # Note: SHAP no longer required for narratives (using gain-based approach)
  ```
- ✅ Working directory: `pipeline/` (this directory)

### Monthly Execution (6 Steps)

```bash
# Step 1: Refresh M&A Advisors Table
# Run SQL: pipeline/sql/create_ma_eligible_advisors.sql
# Creates: ml_features.ma_eligible_advisors (~2,225 advisors)

# Step 2: Calculate V4 features for all prospects
# Run SQL: pipeline/sql/v4_prospect_features.sql
# Creates: ml_features.v4_prospect_features (~285,690 prospects)

# Step 3: Score prospects with V4.3.1 model
cd pipeline
python scripts/score_prospects_v43.py
# Creates: ml_features.v4_prospect_scores (~285,690 scores)
# Note: Use score_prospects_v43.py (NOT score_prospects_monthly.py which is V4.2.0)

# Step 4: Generate base hybrid lead list (Query 1)
# Run SQL: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
# Creates: ml_features.january_2026_lead_list (~2,800 leads)

# Step 5: Insert M&A leads (Query 2) ⚠️ MUST RUN AFTER STEP 4
# Run SQL: pipeline/sql/Insert_MA_Leads.sql
# Adds: ~300 M&A leads to existing january_2026_lead_list table

# Step 6: Export to CSV
python scripts/export_lead_list.py
# Output: pipeline/exports/[month]_2026_lead_list_YYYYMMDD.csv
```

**Expected Output**: CSV file with ~200 leads per active SGA (e.g., 2,800 standard + 300 M&A = 3,100 total leads) ready for Salesforce import

---

## Required Files for Full Pipeline Execution

This section lists **all required files** to run the complete monthly pipeline (V3.6.1 + V4.3.2).

### Core Pipeline Files (6 files)

| Step | File | Location | Purpose | Output Table |
|------|------|----------|---------|--------------|
| 1 | `create_ma_eligible_advisors.sql` | `pipeline/sql/create_ma_eligible_advisors.sql` | Pre-build M&A advisor list | `ml_features.ma_eligible_advisors` |
| 2 | `v4_prospect_features.sql` | `pipeline/sql/v4_prospect_features.sql` | Calculate 26 V4.3.1 features | `ml_features.v4_prospect_features` |
| 3 | `score_prospects_v43.py` | `pipeline/scripts/score_prospects_v43.py` | Score with V4.3.1 model | `ml_features.v4_prospect_scores` |
| 4 | `January_2026_Lead_List_V3_V4_Hybrid.sql` | `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | Generate base lead list | `ml_features.january_2026_lead_list` |
| 5 | `Insert_MA_Leads.sql` | `pipeline/sql/Insert_MA_Leads.sql` | Add M&A leads | (adds to Step 4 table) |
| 6 | `export_lead_list.py` | `pipeline/scripts/export_lead_list.py` | Export to CSV | `pipeline/exports/[month]_2026_lead_list_YYYYMMDD.csv` |

**⚠️ Important Notes**:
- **Step 3**: Use `score_prospects_v43.py` (V4.3.1). Do NOT use `score_prospects_monthly.py` (V4.2.0 only).
- **Step 5**: MUST run AFTER Step 4 (two-query architecture).

### V3.6.0 Supporting Files (2 files)

| File | Location | Purpose | Output Table |
|------|----------|---------|--------------|
| `lead_scoring_features_pit.sql` | `v3/sql/lead_scoring_features_pit.sql` | V3 feature engineering (37 features) | `ml_features.lead_scoring_features_pit` |
| `phase_4_v3_tiered_scoring.sql` | `v3/sql/phase_4_v3_tiered_scoring.sql` | V3.6.0 tier assignment logic | `ml_features.lead_scores_v3_6` |

**Note**: These tables should be refreshed periodically (monthly or when V3 logic changes).

### V4.3.1 Model Artifacts (4 files)

| File | Location | Purpose |
|------|----------|---------|
| `v4.3.1_model.json` | `v4/models/v4.3.1/v4.3.1_model.json` | Trained XGBoost model (used by V4.3.2) |
| `v4.3.1_feature_importance.csv` | `v4/models/v4.3.1/v4.3.1_feature_importance.csv` | Feature importance for gain-based narratives |
| `v4.3.1_metadata.json` | `v4/models/v4.3.1/v4.3.1_metadata.json` | Training metadata and validation results |

### Configuration Files (Optional)

| File | Location | Purpose |
|------|----------|---------|
| `create_excluded_firms_table.sql` | `pipeline/sql/create_excluded_firms_table.sql` | Create firm exclusion patterns table |
| `create_excluded_firm_crds_table.sql` | `pipeline/sql/create_excluded_firm_crds_table.sql` | Create CRD-based exclusions table |
| `manage_excluded_firms.sql` | `pipeline/sql/manage_excluded_firms.sql` | Helper queries for managing exclusions |

### File Status Checklist

**✅ All Required Files Present**:
- [x] `pipeline/sql/create_ma_eligible_advisors.sql`
- [x] `pipeline/sql/v4_prospect_features.sql` (V4.3.1)
- [x] `pipeline/scripts/score_prospects_v43.py` (V4.3.1)
- [x] `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` (V3.6.1/V4.3.1)
- [x] `pipeline/sql/Insert_MA_Leads.sql`
- [x] `pipeline/scripts/export_lead_list.py`
- [x] `v3/sql/lead_scoring_features_pit.sql` (V3 features)
- [x] `v3/sql/phase_4_v3_tiered_scoring.sql` (V3.6.0 tiers)
- [x] `v4/models/v4.3.1/v4.3.1_model.json` (V4.3.1 model, used by V4.3.2)
- [x] `v4/models/v4.3.1/v4.3.1_feature_importance.csv` (V4.3.1 importance)

**⚠️ Deprecated Files (Do NOT Use)**:
- [ ] `pipeline/scripts/score_prospects_monthly.py` (V4.2.0 only - outdated)
- [ ] `v4/models/v4.2.0/` (superseded by V4.3.1)
- [ ] `v4/models/v4.3.0/` (superseded by V4.3.1/V4.3.2)

**📚 For Complete File Documentation**: See `pipeline/V4.3.0_V3.6.0_PIPELINE_REQUIRED_FILES.md` (Note: Some file names may reference V4.3.0, but current version is V4.3.2)

---

## Pipeline Architecture

### High-Level Flow (V3.6.0 + V4.3.0 Two-Query Architecture)

```
┌─────────────────────────────────────────────────────────────────┐
│        MONTHLY LEAD LIST GENERATION PIPELINE (V3.6.1 + V4.3.1) │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  STEP 1: Refresh M&A Advisors Table                             │
│     └─> SQL: pipeline/sql/create_ma_eligible_advisors.sql      │
│     └─> Output: ml_features.ma_eligible_advisors (~2,225)       │
│     └─> Purpose: Pre-build M&A advisor list with tier assignments│
│                                                                  │
│  STEP 2: Calculate V4 Features                                  │
│     └─> SQL: pipeline/sql/v4_prospect_features.sql              │
│     └─> Output: ml_features.v4_prospect_features (~285,690)    │
│     └─> Purpose: Calculate 26 ML features (V4.3.1) for all prospects│
│                                                                  │
│  STEP 3: Score Prospects with V4.3.1 Model (V4.3.2 features)  │
│     └─> Python: pipeline/scripts/score_prospects_v43.py         │
│     └─> Output: ml_features.v4_prospect_scores (~285,690)      │
│     └─> Purpose: Generate ML scores, percentiles, gain-based narratives│
│     └─> ⚠️ NOTE: Use score_prospects_v43.py (NOT score_prospects_monthly.py)│
│                                                                  │
│  STEP 4: Generate Base Lead List (Query 1)                     │
│     └─> SQL: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql│
│     └─> Output: ml_features.january_2026_lead_list (~2,800)     │
│     └─> Purpose: Standard leads with V3.6.1 tiers + V4.3.1 upgrades│
│                                                                  │
│  STEP 5: Insert M&A Leads (Query 2) ⚠️ MUST RUN AFTER STEP 4   │
│     └─> SQL: pipeline/sql/Insert_MA_Leads.sql                  │
│     └─> Output: Adds ~300 M&A leads to existing table            │
│     └─> Purpose: Add M&A tier leads (bypasses CTE issues)       │
│                                                                  │
│  STEP 6: Export to CSV                                          │
│     └─> Python: pipeline/scripts/export_lead_list.py            │
│     └─> Output: pipeline/exports/[month]_2026_lead_list_YYYYMMDD.csv│
│     └─> Purpose: CSV file for Salesforce import                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why Two-Query Architecture?

Single-query approaches failed due to BigQuery CTE optimization issues:

| Approach Attempted | Result |
|--------------------|--------|
| EXISTS subquery exemption | ❌ Works in isolation, fails in full query |
| JOIN exemption | ❌ Works in isolation, fails in full query |
| UNION two-track architecture | ❌ Works in isolation, fails in full query |
| LEFT JOIN with inline subquery | ❌ Works in isolation, fails in full query |
| **INSERT after CREATE** | ✅ **Works reliably** |

The INSERT approach completely bypasses BigQuery's CTE optimization by using two separate, simple queries instead of one complex 1,400+ line query.

### Data Flow

```
FINTRX Data (BigQuery)
    ↓
[Step 1] Feature Engineering
    ↓
V4 Features Table (285,690 prospects)
    ↓
[Step 2] ML Scoring
    ↓
V4 Scores Table (285,690 scored prospects)
    ↓
[Step 3] Hybrid Query (V3 Rules + V4 Upgrades)
    ↓
Lead List Table (200 leads per active SGA)
    ↓
[Step 4] CSV Export
    ↓
Salesforce Import File
```

---

## Step-by-Step Execution

### Step 1: Refresh M&A Eligible Advisors Table

**Purpose**: Pre-build the M&A advisors table with tier assignments. This table is refreshed monthly or when new M&A news hits.

**File**: `pipeline/sql/create_ma_eligible_advisors.sql`

**What It Does**:
- Joins `active_ma_target_firms` with `ria_contacts_current`
- Assigns tier based on senior title or mid-career status
- Creates `ml_features.ma_eligible_advisors` table

**Execution**:
```sql
-- Run in BigQuery
-- Creates: ml_features.ma_eligible_advisors
-- Expected rows: ~2,225 advisors
```

**Validation Query**:
```sql
SELECT 
    ma_tier,
    COUNT(*) as count,
    COUNT(DISTINCT firm_crd) as unique_firms
FROM `savvy-gtm-analytics.ml_features.ma_eligible_advisors`
GROUP BY ma_tier;
```

**Expected Results**:
- TIER_MA_ACTIVE_PRIME: ~1,100 advisors
- TIER_MA_ACTIVE: ~1,100 advisors
- Total: ~2,225 advisors across 66 firms

---

### Step 2: Calculate V4 Features for All Prospects

**Purpose**: Calculate the 25 features required by the V4.3.0 XGBoost model (including Career Clock features) for all producing advisors in FINTRX.

**File**: `pipeline/sql/v4_prospect_features.sql` (V4.3.0)

**What It Does**:
- Calculates 26 ML features for all producing advisors (V4.3.1)
- Includes 23 features from V4.2.0 + 2 new Career Clock features (`cc_is_in_move_window`, `cc_is_too_early`)
- Includes encoded categoricals: `tenure_bucket_encoded`, `mobility_tier_encoded`, `firm_stability_tier_encoded`, `age_bucket_encoded`
- Includes duplicate prevention (QUALIFY ROW_NUMBER on firm-level JOINs) - fixed January 8, 2026
- Queries `ria_contacts_current` for all producing advisors
- Calculates tenure, experience, mobility, firm stability features
- Creates interaction features (mobility × bleeding, short tenure × mobility)
- Handles missing data with appropriate defaults

**Execution**:
```sql
-- Run in BigQuery
-- Creates: ml_features.v4_prospect_features
-- Expected rows: ~285,690 prospects
```

**Validation Query**:
```sql
SELECT 
    COUNT(*) as total_prospects,
    COUNT(DISTINCT firm_crd) as unique_firms,
    SUM(CASE WHEN tenure_bucket != 'Unknown' THEN 1 ELSE 0 END) as with_tenure,
    SUM(CASE WHEN mobility_tier = 'High_Mobility' THEN 1 ELSE 0 END) as high_mobility
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`;
```

**Expected Results**:
- Total prospects: ~285,690
- Tenure coverage: ~78.6% (21.4% Unknown)
- High mobility: ~5-10% of prospects

---

### Step 3: Score Prospects with V4.3.1 Model

**Purpose**: Generate ML scores for all prospects using the trained V4.3.1 XGBoost model.

**File**: `pipeline/scripts/score_prospects_v43.py` ⚠️ **USE THIS FOR V4.3.1/V4.3.2**

**Alternative (Deprecated)**: `pipeline/scripts/score_prospects_monthly.py` (V4.2.0 only - DO NOT USE)

**What It Does**:
1. Loads V4.3.1 XGBoost model from `v4/models/v4.3.1/v4.3.1_model.json`
2. Loads feature importance from `v4/models/v4.3.1/v4.3.1_feature_importance.csv`
3. Fetches features from `ml_features.v4_prospect_features` (26 features including Career Clock and Recent Promotee)
4. Generates predictions (0-1 probability scores)
5. Calculates percentile ranks (1-100)
6. Identifies deprioritize candidates (bottom 20%)
7. Generates gain-based narratives for V4 upgrade candidates (top 20%)
8. Uploads scores to `ml_features.v4_prospect_scores` with Career Clock features

**Execution**:
```bash
cd pipeline
python scripts/score_prospects_v43.py
```

**Output Columns**:
- `crd`: Advisor CRD ID
- `v4_score`: Raw prediction (0-1)
- `v4_percentile`: Percentile rank (1-100)
- `v4_deprioritize`: Boolean (TRUE if percentile ≤ 20)
- `v4_upgrade_candidate`: Boolean (TRUE if percentile ≥ 80)
- `top1_feature`, `top2_feature`, `top3_feature`: Top 3 ML features (gain-based)
- `top1_value`, `top2_value`, `top3_value`: Feature values
- `v4_narrative`: Human-readable explanation for upgrades

**Validation**:
```sql
SELECT 
    COUNT(*) as total_scored,
    SUM(CASE WHEN v4_deprioritize = TRUE THEN 1 ELSE 0 END) as deprioritize_count,
    SUM(CASE WHEN v4_upgrade_candidate = TRUE THEN 1 ELSE 0 END) as upgrade_count,
    AVG(v4_score) as avg_score,
    MIN(v4_score) as min_score,
    MAX(v4_score) as max_score
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`;
```

**Expected Results**:
- Total scored: ~285,690
- Deprioritize (bottom 20%): ~57,138 (20%)
- Upgrade candidates (top 20%): ~57,138 (20%)
- Score range: 0.0 - 1.0

---

### Step 4: Generate Base Lead List (Query 1)

**Purpose**: Combine V3.6.1 tier rules with V4.3.1 ML upgrades to generate the base lead list.

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` (V3.6.1/V4.3.1)

**What It Does**:

1. **Firm Exclusions (Centralized)**:
   - References `ml_features.excluded_firms` for pattern-based exclusions
   - References `ml_features.excluded_firm_crds` for CRD-based exclusions
   - Excludes wirehouses, insurance BDs, large IBDs, custodians, internal/partner firms
   - See "Firm Exclusions" section below for management details

2. **Salesforce Matching & Prioritization**:
   - **Checks Salesforce**: Queries `SavvyGTMData.Lead` table to find existing leads by CRD
   - **NEW_PROSPECT**: Leads NOT in Salesforce (preferred - highest priority)
   - **Recyclable Leads**: Leads in Salesforce with 180+ days since last SMS/Call activity
     - Must NOT be in bad status (Closed, Converted, Dead, Unqualified, etc.)
     - Must NOT have DoNotCall = true
   - **Excluded**: Leads in Salesforce that don't meet recyclable criteria (recently contacted, bad status, etc.)
   - **Priority**: NEW_PROSPECT (priority 1) > Recyclable (priority 2)

2. **Firm Exclusions**:
   - **Centralized Exclusion System**: Firm exclusions are managed in BigQuery tables (not hardcoded in SQL)
   - **Pattern-Based Exclusions**: `ml_features.excluded_firms` table contains 42 exclusion patterns
     - Categories: Wirehouse, Large IBD, Custodian, Insurance, Insurance BD, Bank BD, Internal, Partner
     - Examples: Morgan Stanley, Merrill, LPL Financial, Prudential, OneAmerica, etc.
   - **CRD-Based Exclusions**: `ml_features.excluded_firm_crds` table for specific firm CRDs
     - Examples: Savvy Advisors (318493), Ritholtz Wealth (168652)
   - **Benefits**: Easy to add/remove exclusions without editing SQL
   - **Management**: See `pipeline/sql/manage_excluded_firms.sql` for helper queries
   - **Documentation**: See `pipeline/sql/CENTRALIZED_EXCLUSIONS_SUMMARY.md` for details

3. **V3 Tier Assignment**:
   - Applies rules-based tier logic (T1A, T1B, T1, T2, T3, T4, T5, STANDARD)
   - Filters out excluded firms (from centralized tables), excluded titles
   - Only processes NEW_PROSPECT or recyclable leads

4. **V4 Integration (Option C)**:
   - Joins V4 scores from `ml_features.v4_prospect_scores`
   - **Deprioritization**: Filters out bottom 20% V4 scores across all tiers
   - **Backfill Identification**: STANDARD tier leads with V4 ≥ 80th percentile used for backfill only
   - Expected conversion: 3.67% for HIGH_V4 backfill (1.3x baseline)

5. **Tier Quotas (Option C - TIER_4 and TIER_5 Excluded)**:
   - T1A: 50 leads
   - T1B: 60 leads
   - T1: 300 leads
   - T1F: 50 leads
   - T2: 1,500 leads
   - T3: 300 leads
   - **TIER_4: EXCLUDED** (converts at baseline 2.74%, no value)
   - **TIER_5: EXCLUDED** (marginal lift 3.42%, not worth including)
   - **STANDARD_HIGH_V4: ~200-400 leads** (backfill only, after priority tiers exhausted)

6. **Final Filtering**:
   - Firm diversity cap (max 50 leads per firm)
   - LinkedIn prioritization (prefer leads with LinkedIn)
   - Final limit: 200 leads per active SGA (dynamically calculated)

**Execution**:
```sql
-- Run in BigQuery
-- Creates: ml_features.january_2026_lead_list
-- Expected rows: 200 leads per active SGA (e.g., 2,800 for 14 SGAs)
```

**Note**: The lead list table name is now `ml_features.january_2026_lead_list` (single table, not versioned). Old versioned tables (`january_2026_lead_list_v4`, etc.) are deprecated.

**Validation Queries**:

**1. Tier Distribution (Option C)**:
```sql
SELECT 
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(v4_percentile), 1) as avg_v4_percentile,
    ROUND(AVG(expected_rate_pct), 2) as avg_expected_conv_pct,
    SUM(CASE WHEN is_high_v4_standard = 1 THEN 1 ELSE 0 END) as high_v4_backfill
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY score_tier
ORDER BY 
    CASE score_tier
        WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
        WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
        WHEN 'TIER_1_PRIME_MOVER' THEN 3
        WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
        WHEN 'TIER_2_PROVEN_MOVER' THEN 5
        WHEN 'TIER_3_MODERATE_BLEEDER' THEN 6
        WHEN 'STANDARD_HIGH_V4' THEN 7
    END;
```

**1a. Verify TIER_4 and TIER_5 Exclusion**:
```sql
SELECT COUNT(*) as excluded_tier_4_5
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier IN ('TIER_4_EXPERIENCED_MOVER', 'TIER_5_HEAVY_BLEEDER');
-- Expected: 0 (Option C exclusion)
```

**1b. Verify Firm Exclusions**:
```sql
-- Check no excluded firms slipped through
SELECT 
    jl.firm_name,
    ef.pattern as matched_pattern,
    ef.category
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` jl
INNER JOIN `savvy-gtm-analytics.ml_features.excluded_firms` ef
    ON UPPER(jl.firm_name) LIKE ef.pattern;
-- Expected: 0 rows (all excluded firms removed)

-- Check no excluded CRDs slipped through
SELECT jl.firm_name, jl.firm_crd
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` jl
INNER JOIN `savvy-gtm-analytics.ml_features.excluded_firm_crds` ec
    ON jl.firm_crd = ec.firm_crd;
-- Expected: 0 rows (all excluded CRDs removed)
```

**2. Salesforce Matching Validation**:
```sql
SELECT 
    prospect_type,
    COUNT(*) as lead_count,
    COUNT(DISTINCT salesforce_lead_id) as with_salesforce_id,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY prospect_type;
```

**3. Verify No Data Quality Issues**:
```sql
-- Check: NEW_PROSPECT should NOT have salesforce_lead_id
SELECT 
    COUNT(*) as new_prospects_with_sf_id
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE prospect_type = 'NEW_PROSPECT' 
  AND salesforce_lead_id IS NOT NULL;
-- Expected: 0 (should be 0)

-- Check: Deduplication (each CRD should appear only once)
SELECT 
    COUNT(*) as total_leads,
    COUNT(DISTINCT advisor_crd) as unique_crds,
    COUNT(*) - COUNT(DISTINCT advisor_crd) as duplicates
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
-- Expected: duplicates = 0
```

**Expected Results**:
- Total leads: ~200 × number of active SGAs (e.g., 2,800 for 14 SGAs)
- TIER_4 and TIER_5: **0 leads** (excluded per Option C)
- STANDARD_HIGH_V4 backfill: ~200-400 leads (7-15%)
- Average V4 percentile: ~75-85 (higher is better)
- Tier distribution: T1A, T1B, T1, T1F, T2, T3, STANDARD_HIGH_V4 only
- **NEW_PROSPECT**: Typically 80-90% of leads (not in Salesforce)
- **Recyclable**: Typically 10-20% of leads (in Salesforce, 180+ days no contact)
- **NEW_PROSPECT with salesforce_lead_id**: Should be **0** (data quality check)
- **Excluded firms**: Should be **0** (all wirehouses, insurance BDs, etc. excluded)
- **Duplicate CRDs**: Should be **0** (each advisor appears only once)

**SGA Assignment** (Automatic):
- **Each SGA receives exactly 200 leads** with equitable conversion rate distribution
- **Distribution Strategy**: Stratified round-robin within conversion rate buckets
  - High Conv (8%+): T1A, T1B leads
  - Med-High Conv (6-8%): T1, T1F leads
  - Med Conv (5-6%): T2 leads
  - Med-Low Conv (4-5%): T3, T4, V4_UPGRADE leads
  - Low Conv (<4%): T5, STANDARD leads
- **Equity Goal**: Each SGA gets similar expected conversion value (not just tier count)
- **Dynamic**: Automatically calculates total leads based on active SGA count
  - Queries `SavvyGTMData.User` table for active SGAs
  - Excludes: Jacqueline Tully, GinaRose, Savvy Marketing, Savvy Operations, Anett Davis, Anett Diaz
  - Generates 200 leads per SGA (e.g., 3,000 leads for 15 SGAs)
- **Tier Quotas**: Scale proportionally with SGA count (base quotas for 12 SGAs)

**SGA Assignment Columns**:
- `sga_owner`: SGA name (e.g., "Amy Waller")
- `sga_id`: Salesforce User ID (for matching/updating leads)

---

### Step 5: Insert M&A Leads (Query 2) ⚠️ MUST RUN AFTER STEP 4

**Purpose**: Add M&A tier leads to the base lead list. This must run AFTER Step 4.

**File**: `pipeline/sql/Insert_MA_Leads.sql`

**What It Does**:
- Inserts ~300 M&A leads into the existing `ml_features.january_2026_lead_list` table
- Uses advisors from `ml_features.ma_eligible_advisors` (created in Step 1)
- Assigns M&A tiers: TIER_MA_ACTIVE_PRIME (9.0% conversion) and TIER_MA_ACTIVE (5.4% conversion)
- Bypasses BigQuery CTE optimization issues by using separate INSERT query

**Execution**:
```sql
-- Run in BigQuery AFTER Step 4 completes
-- Adds: ~300 M&A leads to ml_features.january_2026_lead_list
```

**Why Two Queries?**
- BigQuery CTE optimization issues prevent M&A advisors from appearing when integrated into the main query
- This separate INSERT approach guarantees M&A leads are added successfully

**Validation Query**:
```sql
SELECT 
    COUNT(*) as total_leads,
    COUNTIF(score_tier LIKE 'TIER_MA%') as ma_leads
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
```

**Expected Results**:
- Total leads: ~3,100 (2,800 base + 300 M&A)
- M&A leads: ~300

---

### Step 6: Export to CSV

**Purpose**: Export lead list to CSV format for Salesforce import.

**File**: `pipeline/scripts/export_lead_list.py`

**What It Does**:
1. Fetches lead list from `ml_features.january_2026_lead_list`
2. Validates data quality (duplicates, missing fields, exclusions)
3. Exports to CSV with all required columns
4. Logs results to `pipeline/logs/EXECUTION_LOG.md`

**Execution**:
```bash
cd pipeline
python scripts/export_lead_list.py
```

**Output File**: `pipeline/exports/january_2026_lead_list_YYYYMMDD.csv`

**CSV Columns** (25 total):
- `advisor_crd`: FINTRX CRD ID
- `salesforce_lead_id`: Salesforce Lead ID (if exists)
- `first_name`: Contact first name
- `last_name`: Contact last name
- `job_title`: Advisor's job title from FINTRX
- `email`: Email address
- `phone`: Phone number
- `linkedin_url`: LinkedIn profile URL
- `firm_name`: Firm name
- `firm_crd`: Firm CRD ID
- `score_tier`: Final tier (V3 tier or STANDARD_HIGH_V4)
- `expected_rate_pct`: Expected conversion rate (%)
- `score_narrative`: Human-readable explanation (V3 rules or V4 gain-based)
- `v4_score`: V4 XGBoost score (0-1)
- `v4_percentile`: V4 percentile rank (1-100)
- `is_high_v4_standard`: 1 = HIGH_V4 backfill lead, 0 = V3 tier lead
- `v4_status`: Description of V4 status
- `top1_feature`: Most important ML feature driving score (gain-based)
- `top2_feature`: Second most important feature
- `top3_feature`: Third most important feature
- `prospect_type`: NEW_PROSPECT or recyclable
- `sga_owner`: Assigned SGA name (automatically assigned)
- `sga_id`: Assigned SGA Salesforce ID (for matching)
- `priority_rank`: Overall ranking in list (1 to total_leads_needed)
- `tier_category`: Tier category for reporting

**Validation**:
- Row count: ~200 × number of active SGAs (e.g., 2,800 for 14 SGAs)
- Duplicate CRDs: 0
- Missing required fields: < 1%
- Excluded firms (from centralized tables): 0
- TIER_4 and TIER_5 leads: 0 (Option C exclusion)

---

## V3.5.0 M&A Active Tiers

### Overview

V3.5.0 adds two M&A (Mergers & Acquisitions) opportunity tiers that capture advisors at firms undergoing M&A activity. These leads would normally be excluded by the large firm filter (>50 reps) but convert at elevated rates during M&A disruption.

### New Tiers

| Tier | Expected Conversion | Lift | Criteria |
|------|---------------------|------|----------|
| **TIER_MA_ACTIVE_PRIME** | 9.0% | 2.36x | Senior title OR mid-career (10-20yr) at M&A target |
| **TIER_MA_ACTIVE** | 5.4% | 1.41x | All advisors at M&A target firms |

### Evidence: Commonwealth/LPL Merger Analysis

**Event**: LPL Financial announced acquisition of Commonwealth Financial Network (July 2024)

| Metric | Value |
|--------|-------|
| Total Commonwealth advisors | ~2,500 |
| Advisors contacted | 242 |
| Conversions (MQLs) | 13 |
| **Conversion Rate** | **5.37%** |
| **Lift vs Baseline** | **1.41x** |

**Profile Analysis**:
- Senior Titles: 9.30% conversion (2.06x lift)
- Mid-Career (10-20yr): 8.16% conversion (1.75x lift)
- Serial Movers: 5.14% conversion (0.86x lift) - Does NOT help
- Newer to Firm: 4.65% conversion (0.81x lift) - Does NOT help

### Implementation Files

| File | Purpose |
|------|---------|
| `pipeline/sql/create_ma_eligible_advisors.sql` | Pre-build M&A advisors table |
| `pipeline/sql/Insert_MA_Leads.sql` | Insert M&A leads after base list |
| `pipeline/sql/post_implementation_verification_ma_tiers.sql` | Verification queries |
| `V3_5_0_MA_TIER_COMPREHENSIVE_IMPLEMENTATION_GUIDE.md` | Full implementation guide |

### M&A Target Firms Table

The `ml_features.active_ma_target_firms` table tracks firms with active M&A activity:

| Column | Description |
|--------|-------------|
| `firm_crd` | Firm CRD ID |
| `firm_name` | Firm name |
| `ma_status` | HOT (60-180 days) or ACTIVE (181-365 days) |
| `days_since_first_news` | Days since M&A announcement |
| `firm_employees` | Number of advisors at firm |

**Current Stats** (January 2026):
- HOT: 39 firms, 183 advisors
- ACTIVE: 27 firms, 2,042 advisors
- Total: 66 firms, 2,225 advisors

### Refresh Schedule

| Trigger | Action |
|---------|--------|
| Monthly | Re-run `create_ma_eligible_advisors.sql` |
| M&A news | Update `active_ma_target_firms`, re-run creation script |
| Firm status change | Update `ma_status` (HOT → ACTIVE → STALE) |

---

## Firm Exclusions

### Overview

Firm exclusions are managed through **centralized BigQuery tables** rather than hardcoded SQL patterns. This makes exclusions easier to maintain - add/remove firms without editing complex SQL.

### Exclusion Tables

#### 1. `ml_features.excluded_firms` (Pattern-Based)
- **Purpose**: Pattern-based firm exclusions using SQL `LIKE` patterns
- **Rows**: 42 patterns
- **Categories**: 8 (Wirehouse, Large IBD, Custodian, Insurance, Insurance BD, Bank BD, Internal, Partner)
- **Schema**:
  - `pattern` (STRING): LIKE pattern (e.g., `'%MERRILL%'`)
  - `category` (STRING): Exclusion category
  - `added_date` (DATE): When exclusion was added
  - `reason` (STRING): Why firm is excluded

**Example Patterns**:
- Wirehouses: `'%MORGAN STANLEY%'`, `'%MERRILL%'`, `'%WELLS FARGO%'`
- Large IBDs: `'%LPL FINANCIAL%'`, `'%COMMONWEALTH%'`, `'%CETERA%'`
- Insurance: `'%PRUDENTIAL%'`, `'%PRUCO%'`, `'%ONEAMERICA%'`, `'%STATE FARM%'`
- Custodians: `'%FIDELITY%'`, `'%SCHWAB%'`, `'%VANGUARD%'`
- Internal/Partner: `'%SAVVY WEALTH%'`, `'%RITHOLTZ%'`

#### 2. `ml_features.excluded_firm_crds` (CRD-Based)
- **Purpose**: Specific firm CRD exclusions (more precise than patterns)
- **Rows**: 2 CRDs (Savvy 318493, Ritholtz 168652)
- **Schema**:
  - `firm_crd` (INT64): Firm CRD number
  - `firm_name` (STRING): Firm name
  - `category` (STRING): Exclusion category
  - `added_date` (DATE): When exclusion was added
  - `reason` (STRING): Why firm is excluded

### How to Add a New Exclusion

#### Pattern-Based (Recommended)
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firms` 
VALUES ('%NEW_FIRM_PATTERN%', 'Category', CURRENT_DATE(), 'Reason for exclusion');
```

**Example**:
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firms` 
VALUES ('%NEW_WIREHOUSE%', 'Wirehouse', CURRENT_DATE(), 'Major wirehouse - captive advisors');
```

#### CRD-Based (For Specific Firms)
```sql
INSERT INTO `savvy-gtm-analytics.ml_features.excluded_firm_crds`
VALUES (123456, 'Firm Name', 'Category', CURRENT_DATE(), 'Reason for exclusion');
```

**After Adding**:
1. Regenerate the lead list: `python pipeline/scripts/execute_january_lead_list.py`
2. Verify exclusion: Check that the firm no longer appears in `ml_features.january_2026_lead_list`

### How to Remove an Exclusion

```sql
-- Pattern-based
DELETE FROM `savvy-gtm-analytics.ml_features.excluded_firms`
WHERE pattern = '%PATTERN_TO_REMOVE%';

-- CRD-based
DELETE FROM `savvy-gtm-analytics.ml_features.excluded_firm_crds`
WHERE firm_crd = 123456;
```

### Management Helper Queries

See `pipeline/sql/manage_excluded_firms.sql` for:
- View all exclusions
- Check if a firm would be excluded
- Find potential exclusions in prospect data
- Add/remove exclusions

### Benefits

1. ✅ **Easier Maintenance** - Add/remove exclusions without editing complex SQL
2. ✅ **Audit Trail** - `added_date` tracks when exclusions were added
3. ✅ **Documentation** - `reason` explains why each firm is excluded
4. ✅ **Reusable** - Same tables can be used by future lead lists
5. ✅ **Queryable** - Easy to see all exclusions and their categories

### Files

- **Table Creation**: `pipeline/sql/create_excluded_firms_table.sql`
- **CRD Table Creation**: `pipeline/sql/create_excluded_firm_crds_table.sql`
- **Management Queries**: `pipeline/sql/manage_excluded_firms.sql`
- **Documentation**: `pipeline/sql/CENTRALIZED_EXCLUSIONS_SUMMARY.md`

---

## Model Logic & Methodology

### V3 Rules-Based Model

**Philosophy**: Transparent, explainable business rules based on validated SGA expertise that assign leads to priority tiers.

**Tier Definitions (Option C - Only Tiers Above Baseline)**:

| Tier | Criteria | Historical Rate | vs Baseline (2.74%) | Status |
|------|----------|----------------|---------------------|--------|
| **T1B** | Series 65 only + Tier 1 criteria | 11.76% | 4.3x | ✅ Included |
| **T1A** | CFP holder + 1-4yr tenure + 5+yr experience + bleeding firm | ~10%+ | 3.6x+ | ✅ Included |
| **T3** | Firm losing 1-10 advisors + 5+yr experience | 6.76% | 2.5x | ✅ Included |
| **T1F** | High-value wealth title + bleeding firm | 6.06% | 2.2x | ✅ Included |
| **T2** | 3+ prior firms + 5+yr experience | 5.91% | 2.2x | ✅ Included |
| **T1** | 1-4yr tenure + 5-15yr experience + bleeding firm + small firm | 4.76% | 1.7x | ✅ Included |
| **TIER_4** | 20+yr experience + 1-4yr tenure (recent mover) | 2.74% | 1.0x | ❌ **EXCLUDED** (Option C) |
| **TIER_5** | Firm losing 10+ advisors + 5+yr experience | 3.42% | 1.2x | ❌ **EXCLUDED** (Option C) |
| **STANDARD** | All other leads | 2.60% | 0.95x | ❌ Excluded (unless HIGH_V4) |

**Key Design Principles**:
1. **Zero Data Leakage**: All features calculated using Point-in-Time (PIT) methodology
2. **Transparent Rules**: Every tier assignment is explainable
3. **Statistical Validation**: All tiers validated with confidence intervals
4. **Temporal Validation**: Tested on future data (August-October 2025)
5. **Option C Optimization**: Only tiers that convert significantly above baseline are included

---

### V4 XGBoost ML Model (V4.3.0 - Current Production)

**Philosophy**: Machine learning model that deprioritizes low-potential leads and identifies intelligent backfill candidates.

**Algorithm**: XGBoost (Gradient Boosting)
- **Objective**: Binary classification (logistic)
- **Regularization**: Strong (max_depth=2, min_child_weight=30)
- **Training Period**: 2024-02-01 to 2025-07-31
- **Test Period**: 2025-08-01 to 2025-10-31
- **Features**: 26 (23 from V4.2.0 + 2 Career Clock features + 1 Recent Promotee feature)

**Performance Metrics (V4.3.1/V4.3.2)**:
- **Test AUC-ROC**: 0.6322 (slightly below V4.3.0's 0.6389, acceptable after data quality fixes)
- **Top Decile Lift**: 2.40x
- **Overfitting Gap**: 0.0480 (within acceptable range < 0.05)
- **Recent Promotee Feature Importance**: is_likely_recent_promotee = 2.39% of total gain
- **Career Clock Importance**: 0.0% (may be due to data quality fixes removing polluted data)
- **Narrative Method**: Gain-based (SHAP deferred to V4.4.0)
- **V4.3.2 Fix**: Fuzzy firm name matching excludes ~135 advisors incorrectly in move window

**Model Evolution**:
| Version | AUC-ROC | Top Decile Lift | Features | Status |
|---------|---------|-----------------|----------|--------|
| V4.3.2 | **0.6322** | **2.40x** | 26 | ✅ Production |
| V4.3.1 | 0.6322 | 2.40x | 26 | Superseded |
| V4.3.0 | 0.6389 | 2.80x | 25 | Superseded |
| V4.2.0 | 0.6352 | 2.28x | 23 | Deprecated |
| V4.1.0 R3 | 0.620 | 2.03x | 22 | ❌ Deprecated |
| V4.0.0 | 0.599 | 1.51x | 14 | ❌ Archived |

**Use Cases (Option C)**:
1. **Deprioritization**: Filters out bottom 20% V4 scores across all tiers
2. **Backfill Identification**: STANDARD tier leads with V4 ≥ 80th percentile used for backfill only
   - HIGH_V4 backfill converts at **3.67%** (1.3x baseline)
   - Historical validation: 6,043 leads at 3.67% conversion rate
   - Only used after priority tiers (T1-T3) are exhausted

**Why Hybrid Approach?**:
- V3 excels at **prioritization** (identifying top tiers based on validated SGA expertise)
- V4 excels at **filtering and backfilling** (removing worst leads, finding best remaining candidates)
- Combined: Maximum conversion rate while maintaining volume targets

---

## V4 XGBoost Model Features (V4.3.2 - 26 Features)

The V4.3.2 model uses **26 features**:
- **23 features from V4.2.0** (including `age_bucket_encoded` added January 7, 2026)
- **2 Career Clock features** (added V4.3.0, improved V4.3.2 with fuzzy firm matching, January 8, 2026): `cc_is_in_move_window`, `cc_is_too_early`
- **1 Recent Promotee feature** (added V4.3.1, January 8, 2026): `is_likely_recent_promotee`

### Core Features (12)
| # | Feature | Description |
|---|---------|-------------|
| 1 | tenure_months | Months at current firm |
| 2 | mobility_3yr | Job moves in last 3 years |
| 3 | firm_rep_count_at_contact | Firm size at time of contact |
| 4 | firm_net_change_12mo | Net rep change (12 months) |
| 5 | is_wirehouse | Wirehouse flag |
| 6 | is_broker_protocol | Broker Protocol member |
| 7 | has_email | Email available |
| 8 | has_linkedin | LinkedIn available |
| 9 | has_firm_data | Firm data available |
| 10 | mobility_x_heavy_bleeding | Interaction: mobility × bleeding |
| 11 | short_tenure_x_high_mobility | Interaction: short tenure × high mobility |
| 12 | experience_years | Years in industry |

### Encoded Categoricals (3)
| # | Feature | Description |
|---|---------|-------------|
| 13 | tenure_bucket_encoded | Tenure category (0-5 scale) |
| 14 | mobility_tier_encoded | Mobility tier (0-2 scale) |
| 15 | firm_stability_tier_encoded | Firm stability (0-4 scale) |

### Bleeding Features (4)
| # | Feature | Description |
|---|---------|-------------|
| 16 | is_recent_mover | Moved in last 2 years |
| 17 | days_since_last_move | Days since last job change |
| 18 | firm_departures_corrected | Corrected departure count |
| 19 | bleeding_velocity_encoded | Bleeding acceleration (0-3 scale) |

### Firm/Rep Type Features (3)
| # | Feature | Description |
|---|---------|-------------|
| 20 | is_independent_ria | Independent RIA flag |
| 21 | is_ia_rep_type | IA rep type flag |
| 22 | is_dual_registered | Dual registered flag |

### Age Feature (1) - V4.2.0
| # | Feature | Description |
|---|---------|-------------|
| 23 | age_bucket_encoded | Age category (0=Under 35, 1=35-49, 2=50-64, 3=65-69, 4=70+) |

### Career Clock Features (2) - NEW in V4.3.0
| # | Feature | Description | Importance |
|---|---------|-------------|------------|
| 24 | cc_is_in_move_window | Career Clock timing signal - advisor in optimal move window | 2.02% |
| 25 | cc_is_too_early | Career Clock deprioritization signal - advisor too early in cycle | 0.0% |

**Career Clock Feature Details**:

**24. `cc_is_in_move_window`** (2.02% importance)
- **Purpose**: Career Clock timing signal - advisor in optimal move window
- **Logic**: Predictable pattern (CV < 0.5) AND 70-130% through typical tenure cycle
- **Validation**: 5.59% conversion (2.43x lift), independent from age (r=0.035)
- **Business Value**: Optimal timing signal for outreach

**25. `cc_is_too_early`** (0.0% importance)
- **Purpose**: Career Clock deprioritization signal - advisor too early in cycle
- **Logic**: Predictable pattern (CV < 0.5) BUT < 70% through typical tenure cycle
- **Validation**: 3.72% conversion (deprioritization signal), independent from age (r=0.003)
- **Business Value**: Deprioritization signal for resource allocation

### Feature Importance (Top 10 by Gain)

| Rank | Feature | Gain | % of Total |
|------|---------|------|------------|
| 1 | tenure_bucket_encoded | 501.87 | 11.43% |
| 2 | is_dual_registered | 293.63 | 6.69% |
| 3 | has_firm_data | 285.20 | 6.49% |
| 4 | days_since_last_move | 265.33 | 6.04% |
| 5 | has_email | 261.50 | 5.96% |
| 6 | is_independent_ria | 256.72 | 5.85% |
| 7 | mobility_tier_encoded | 254.17 | 5.79% |
| 8 | tenure_months | 224.79 | 5.12% |
| 9 | is_ia_rep_type | 219.76 | 5.00% |
| 10 | **age_bucket_encoded** | **190.61** | **4.34%** |

*Note: Age feature ranked #10 with 4.34% importance - meaningful contribution to model.*

### Feature Descriptions

#### 1. Tenure Features

**`tenure_bucket`** (Importance: 143.16)
- **Type**: Categorical
- **Values**: `0-12`, `12-24`, `24-48`, `48-120`, `120+`, `Unknown`
- **Calculation**: Months at current firm from employment history
- **Insight**: Advisors with 1-4 years tenure are more mobile and likely to convert

#### 2. Experience Features

**`experience_bucket`** (Importance: 64.17)
- **Type**: Categorical
- **Values**: `0-5`, `5-10`, `10-15`, `15-20`, `20+`, `Unknown`
- **Calculation**: Total industry experience in years
- **Insight**: Mid-career advisors (5-15 years) have portable books of business

**`is_experience_missing`** (Importance: 39.04)
- **Type**: Boolean
- **Purpose**: Flags missing experience data
- **Insight**: Missing data can be informative (newer advisors, incomplete records)

#### 3. Mobility Features

**`mobility_tier`** (Importance: 178.85) ⭐ **MOST IMPORTANT**
- **Type**: Categorical
- **Values**: `Stable` (0 moves), `Low_Mobility` (1-2 moves), `High_Mobility` (3+ moves)
- **Calculation**: Number of distinct firms in last 3 years
- **Insight**: Advisors with history of moves are more likely to move again
- **Key Finding**: Recent movers convert at 2.5x the rate of stable advisors

#### 4. Firm Stability Features

**`firm_stability_tier`** (Importance: 101.08)
- **Type**: Categorical
- **Values**: `Unknown`, `Heavy_Bleeding` (losing 10+), `Light_Bleeding` (losing 1-10), `Stable`, `Growing`
- **Calculation**: Based on net change in advisors over 12 months
- **Insight**: Firms losing advisors create instability signals

**`firm_rep_count_at_contact`** (Importance: 83.30)
- **Type**: Integer
- **Calculation**: Current number of producing advisors at firm
- **Insight**: Smaller firms (<50 reps) indicate more autonomy and portability

**`firm_net_change_12mo`** (Importance: 71.99)
- **Type**: Integer
- **Calculation**: Arrivals - Departures over 12 months
- **Insight**: Negative values indicate firm instability

**`has_firm_data`** (Importance: 55.48)
- **Type**: Boolean
- **Purpose**: Flags whether firm data is available
- **Insight**: Complete firm data enables better scoring

#### 5. Wirehouse & Broker Protocol

**`is_wirehouse`** (Importance: 84.76)
- **Type**: Boolean
- **Calculation**: Pattern matching on firm name (Merrill, Morgan Stanley, UBS, etc.)
- **Insight**: Wirehouse advisors have more restrictions on client portability

**`is_broker_protocol`** (Importance: 64.26)
- **Type**: Boolean
- **Calculation**: Check against broker protocol members table
- **Insight**: Broker Protocol participation makes client transitions smoother

#### 6. Data Quality Flags

**`has_email`** (Importance: 158.87) ⭐ **SECOND MOST IMPORTANT**
- **Type**: Boolean
- **Calculation**: Whether email address is available
- **Insight**: Contact information availability is a strong signal (data quality + engagement)

**`has_linkedin`** (Importance: 110.46)
- **Type**: Boolean
- **Calculation**: Whether LinkedIn profile URL is available
- **Insight**: LinkedIn enables personalized outreach and indicates professional presence

#### 7. Interaction Features

**`mobility_x_heavy_bleeding`** (Importance: 117.26) ⭐ **THIRD MOST IMPORTANT**
- **Type**: Boolean
- **Calculation**: High mobility (3+ moves) AND heavy bleeding firm (losing 10+)
- **Insight**: Powerful combination signal - mobile advisor at unstable firm
- **Sample Size**: 53 leads in training (small but strong signal)

**`short_tenure_x_high_mobility`** (Importance: 81.95)
- **Type**: Boolean
- **Calculation**: Tenure < 24 months AND high mobility (3+ moves)
- **Insight**: New to current firm AND history of moves = very likely to move again
- **Sample Size**: 93 leads in training

### Feature Engineering Insights

**Key Findings from Feature Analysis**:

1. **Mobility is the strongest signal** (178.85 importance)
   - Recent movers convert at 10.0% vs 4.0% for stable advisors
   - 2.5x conversion rate difference

2. **Data quality matters** (has_email: 158.87, has_linkedin: 110.46)
   - Contact information availability is highly predictive
   - Indicates both data completeness and engagement potential

3. **Interaction features are powerful** (mobility_x_heavy_bleeding: 117.26)
   - Combining signals creates stronger predictions
   - Small sample sizes but high importance

4. **Firm stability provides context** (firm_stability_tier: 101.08)
   - Bleeding firms create instability signals
   - Note: Best advisors leave first, so timing matters

5. **Tenure matters** (tenure_bucket: 143.16)
   - 1-4 years tenure is the "sweet spot" for mobility
   - Too new (<1yr) or too established (>4yr) are less likely to move

---

## Lead Narrative Generation

### Current Approach: Gain-Based Narratives (V4.3.0)

As of January 8, 2026 (V4.3.0), lead narratives are generated using **XGBoost gain-based feature importance** instead of SHAP values.

**Why the change?**
- SHAP TreeExplainer failed due to XGBoost serialization bug (`base_score` stored as `'[2.3813374E-2]'` instead of `0.023813`)
- Multiple fix attempts (JSON conversion, monkey-patching, Explainer fallback) all failed
- Gain-based approach works immediately, is fast, and provides meaningful narratives
- SHAP fix deferred to V4.4.0 when XGBoost/SHAP versions can be upgraded

**How it works:**
1. Load pre-computed feature importance from `v4/models/v4.3.0/v4.3.0_feature_importance.csv`
2. For each lead, identify "notable" features:
   - High importance globally
   - Notable value for this specific lead (e.g., recent mover, bleeding firm, Career Clock signals)
3. Generate human-readable narrative with top 3 factors
4. Includes Career Clock feature descriptions when applicable

**Example Output:**
```
Score: 0.6543
Narrative: Key factors: Tenure Category (Down), Recent Mobility (Up mobile), Firm Net Change (Down bleeding)
Top 1: Tenure Category = 1
Top 2: Recent Mobility = 2
Top 3: Firm Net Change = -7
```

**Trade-offs:**

| Approach | Pros | Cons |
|----------|------|------|
| **Gain-based (current)** | Works immediately, fast, deterministic | Global importance, not per-lead |
| **SHAP TreeExplainer** | Per-lead importance | Broken due to base_score bug |

**For Future Models:**
When retraining V4.3.0+, ensure `base_score=0.5` is explicitly set and test SHAP before deployment:
```python
model = xgb.XGBClassifier(base_score=0.5, ...)  # Explicit float
explainer = shap.TreeExplainer(model)  # Test before saving
```

---

## V4.3.2 Career Clock Features Model - Production (Deployed 2026-01-08)

V4.3.0 adds Career Clock features (`cc_is_in_move_window`, `cc_is_too_early`) as the 24th and 25th features, achieving significant performance improvements:

| Metric | V4.2.0 (Previous) | V4.3.0 (Current) | Improvement |
|--------|-------------------|------------------|-------------|
| **Test AUC-ROC** | 0.6352 | **0.6389** | **+0.58%** |
| **Top Decile Lift** | 2.28x | **2.80x** | **+22.8%** |
| **Overfitting Gap** | 0.0264 | **0.0353** | Within acceptable range |
| **Features** | 23 | **25** | +2 Career Clock features |
| **Career Clock Features** | None | **cc_is_in_move_window, cc_is_too_early** | ✅ New capability |

**Key Improvements:**
- Better model discrimination (+0.58% AUC)
- Significantly stronger top decile performance (+22.8% lift)
- Career Clock features provide unique timing signals
- Independent from age (correlation < 0.035)

**SHAP Status**: Gain-based narratives (SHAP fix deferred to V4.4.0 due to XGBoost/SHAP compatibility issue)

---

## V4.2.0 Age Feature Model - Deprecated (2026-01-08)

### Executive Summary

V4.2.0 adds `age_bucket_encoded` as the 23rd feature, achieving significant performance improvements:

| Metric | V4.1.0 R3 (Previous) | V4.2.0 (Current) | Improvement |
|--------|---------------------|------------------|-------------|
| **Test AUC-ROC** | 0.620 | **0.6352** | **+1.52%** |
| **Top Decile Lift** | 2.03x | **2.28x** | **+12.3%** |
| **Overfitting Gap** | 0.075 | **0.0264** | **-64.8%** ✅ |
| **Features** | 22 | **23** | +1 age feature |
| **Age Feature** | None | **age_bucket_encoded** | ✅ New capability |

**Key Improvements:**
- Better model discrimination (+1.52% AUC)
- Stronger top decile performance (+12.3% lift)
- Reduced overfitting (-64.8% gap)
- Age provides unique signal (correlation with experience: 0.072)

---

## V4.1.0 R3 Model - Deprecated (2026-01-07)

**Status**: Deprecated (Superseded by V4.2.0 on January 7, 2026)

### Historical Performance

| Metric | V4.0.0 (Previous) | V4.1.0 R3 | Improvement |
|--------|-------------------|-----------|-------------|
| **Test AUC-ROC** | 0.599 | **0.620** | **+3.5%** |
| **Top Decile Lift** | 1.51x | **2.03x** | **+34.4%** |
| **Test AUC-PR** | 0.043 | **0.070** | **+62.8%** |
| **Features** | 14 | **22** | +8 new features |
| **SHAP** | Limited | **Full KernelExplainer** | ✅ Enhanced |

---

## Unified Model Registry

**Location**: `models/UNIFIED_MODEL_REGISTRY.json`

**Purpose**: Single source of truth for all model versions (V3 and V4)

**Current Production Models**:
- **V3.6.1**: Rules-based tiered classification (prioritization) with Career Clock tiers + Recent Promotee exclusion
  - Production SQL: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
  - Career Clock Tiers: TIER_0A/0B/0C (Prime Mover Due, Small Firm Due, Clockwork Due)
  - Recent Promotee Exclusion: Excludes <5yr tenure + mid/senior titles (~1,915 leads)
  - M&A V4 Filter: Excludes M&A leads with V4 < 20th percentile
- **V4.3.2**: XGBoost ML model (deprioritization) with Career Clock features (fuzzy firm matching) + Recent Promotee feature (26 features)
  - Registry: `v4/models/registry.json`
  - Documentation: `v4/VERSION_4_MODEL_REPORT.md`
  - Production SQL: `pipeline/sql/v4_prospect_features.sql` (V4.3.2 with fuzzy firm matching)
  - Inference Script: `pipeline/scripts/score_prospects_v43.py` (USE THIS - uses V4.3.1 model with V4.3.2 features)
  - Career Clock Features: cc_is_in_move_window, cc_is_too_early (V4.3.2: fuzzy firm matching fix)
  - Recent Promotee Feature: is_likely_recent_promotee (26th feature, 2.39% importance)
  - Age Feature: age_bucket_encoded (23rd feature, from V4.2.0)

**Deprecated Models** (archived):
- V4.2.0 → Deprecated 2026-01-08 (superseded by V4.3.0)
- V4.1.0 R3 → Deprecated 2026-01-07 (superseded by V4.2.0)
- V4.1.0 R2 → `archive/v4/models/v4.1.0_r2/`
- V4.1.0 → `archive/v4/models/v4.1.0/`
- V4.0.0 → `archive/v4/models/v4.0.0/`

**Documentation**:
- Model Evolution: `MODEL_EVOLUTION_HISTORY.md`
- V3 Report: `v3/VERSION_3_MODEL_REPORT.md`
- V4 Report: `v4/VERSION_4_MODEL_REPORT.md`

---

### Model Evolution: V4.0.0 → V4.1.0 → V4.2.0 → V4.3.0

**V4.0.0 → V4.1.0 (December 2025)**

The original V4.0.0 model lacked direct bleeding signal features. V4.1.0 added 8 new features:
- **Bleeding signals**: `is_recent_mover`, `days_since_last_move`, `firm_departures_corrected`, `bleeding_velocity_encoded`
- **Firm/rep type**: `is_independent_ria`, `is_ia_rep_type`, `is_dual_registered`

Result: AUC improved from 0.599 → 0.620 (+3.5%), Lift improved from 1.51x → 2.03x (+34.4%)

**V4.1.0 → V4.2.0 (January 7, 2026)**

Age analysis showed age provides unique signal (correlation with experience_years = 0.072). V4.2.0 added `age_bucket_encoded` as the 23rd feature.

Result: AUC improved from 0.620 → 0.6352 (+1.52%), Lift improved from 2.03x → 2.28x (+12.3%), Overfitting reduced by 64.8%

### Current Feature List (V4.2.0 - 23 Features)

#### Original V4.0.0 Features (12)
| # | Feature | Description |
|---|---------|-------------|
| 1 | `tenure_months` | Months at current firm |
| 2 | `mobility_3yr` | Firm moves in last 3 years |
| 3 | `firm_rep_count_at_contact` | Firm headcount |
| 4 | `firm_net_change_12mo` | Firm's net advisor change |
| 5 | `is_wirehouse` | Major wirehouse flag |
| 6 | `is_broker_protocol` | Broker Protocol participant |
| 7 | `has_email` | Email available |
| 8 | `has_linkedin` | LinkedIn available |
| 9 | `has_firm_data` | Firm data quality |
| 10 | `mobility_x_heavy_bleeding` | Interaction: mobile + bleeding firm |
| 11 | `short_tenure_x_high_mobility` | Interaction: short tenure + mobile |
| 12 | `experience_years` | Total industry experience |

#### Encoded Categoricals (3)
| # | Feature | Description |
|---|---------|-------------|
| 13 | `tenure_bucket_encoded` | Tenure category (0-5 scale) |
| 14 | `mobility_tier_encoded` | Mobility category (0-2 scale) |
| 15 | `firm_stability_tier_encoded` | Firm bleeding category (0-4 scale) |

#### V4.1.0 Bleeding Features (4)
| # | Feature | Description |
|---|---------|-------------|
| 16 | `is_recent_mover` | Moved in last 2 years |
| 17 | `days_since_last_move` | Days since firm change |
| 18 | `firm_departures_corrected` | Corrected departure count |
| 19 | `bleeding_velocity_encoded` | 0=Stable, 3=Accelerating |

#### V4.1.0 Firm/Rep Type Features (3)
| # | Feature | Description |
|---|---------|-------------|
| 20 | `is_independent_ria` | Independent RIA flag |
| 21 | `is_ia_rep_type` | IA rep type |
| 22 | `is_dual_registered` | Broker-dealer + IA |

#### V4.2.0 Age Feature (1) - NEW
| # | Feature | Description |
|---|---------|-------------|
| 23 | `age_bucket_encoded` | Age category (0=Under 35, 1=35-49, 2=50-64, 3=65-69, 4=70+) |

### V4.2.0 Validation Results

#### Test Set Performance
```
Test Set: 3,393 leads | 133 conversions | 3.92% conversion rate

Lift by Decile (V4.2.0):
┌─────────┬────────────┬─────────────┬───────────┬──────────┐
│ Decile  │ Avg Score  │ Conversions │ Conv Rate │   Lift   │
├─────────┼────────────┼─────────────┼───────────┼──────────┤
│ 0 (bot) │ 0.31       │ 4           │ 1.21%     │ 0.31x    │
│ 1       │ 0.35       │ 5           │ 1.50%     │ 0.38x    │
│ 2       │ 0.38       │ 11          │ 3.24%     │ 0.83x    │
│ 3       │ 0.41       │ 11          │ 3.39%     │ 0.86x    │
│ 4       │ 0.44       │ 15          │ 4.30%     │ 1.10x    │
│ 5       │ 0.47       │ 17          │ 5.11%     │ 1.30x    │
│ 6       │ 0.50       │ 3           │ 0.86%     │ 0.22x    │
│ 7       │ 0.53       │ 12          │ 3.61%     │ 0.92x    │
│ 8       │ 0.57       │ 22          │ 6.71%     │ 1.71x    │
│ 9 (top) │ 0.62       │ 29          │ 8.93%     │ 2.28x ⭐ │
└─────────┴────────────┴─────────────┴───────────┴──────────┘
```

#### Validation Gates (V4.2.0 - All Passed)
| Gate | Criterion | Result | Status |
|------|-----------|--------|--------|
| G1 | Test AUC-ROC ≥ 0.620 | 0.6352 | ✅ PASSED (+1.52%) |
| G2 | Top Decile Lift ≥ 2.03x | 2.28x | ✅ PASSED (+12.3%) |
| G3 | Overfitting Gap < 0.15 | 0.0264 | ✅ PASSED (-64.8%) |
| G4 | Age Importance > 0 | 4.34% | ✅ PASSED (Rank #10) |

### File Reference

#### Model Files
| File | Path | Description |
|------|------|-------------|
| Model (pickle) | `v4/models/v4.2.0/model.pkl` | Trained XGBoost model |
| Model (JSON) | `v4/models/v4.2.0/model.json` | Model JSON format |
| Features | `v4/inference/lead_scorer_v4.py` | 23 feature list (22 + age_bucket_encoded) |
| Hyperparameters | `v4/models/v4.2.0/hyperparameters.json` | Training config |
| Feature importance | `v4/models/v4.2.0/feature_importance.csv` | XGBoost importance |
| Training metrics | `v4/models/v4.2.0/training_metrics.json` | Performance metrics |

#### Pipeline Files
| File | Path | Description |
|------|------|-------------|
| M&A Advisors SQL | `pipeline/sql/create_ma_eligible_advisors.sql` | Pre-build M&A advisors table |
| Feature SQL | `pipeline/sql/v4_prospect_features.sql` | V4.3.2 feature engineering (26 features with fuzzy firm matching) |
| Scoring script | `pipeline/scripts/score_prospects_v43.py` | V4.3.1 scoring (USE THIS) |
| Scoring script (deprecated) | `pipeline/scripts/score_prospects_monthly.py` | V4.2.0 only (DO NOT USE) |
| Lead list SQL | `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | Base lead list (V3.6.1/V4.3.1) |
| M&A Leads SQL | `pipeline/sql/Insert_MA_Leads.sql` | Insert M&A leads (run after base list) |
| Export script | `pipeline/scripts/export_lead_list.py` | CSV export for Salesforce |

#### BigQuery Tables (V4.3.2)
| Table | Description |
|------|-------------|
| `ml_features.v4_prospect_features` | V4.3.1 features (26 features including Career Clock and Recent Promotee) |
| `ml_features.v4_prospect_scores` | V4.3.1 scores with percentiles and gain-based narratives |
| `ml_features.january_2026_lead_list` | Final lead list with V4.3.2 columns |

### Monthly Execution Checklist (V4.3.2 + V3.6.1)

```markdown
## [MONTH] 2026 Lead List Generation (V4.3.1 + V3.6.1)

**Date**: YYYY-MM-DD

### Step 1: Refresh M&A Advisors Table
- [ ] Run: pipeline/sql/create_ma_eligible_advisors.sql
- [ ] Verify: ml_features.ma_eligible_advisors created/updated
- [ ] Row count: __________ (~2,225 advisors)

### Step 2: Generate V4.3.2 Features
- [ ] Run: pipeline/sql/v4_prospect_features.sql
- [ ] Verify: ml_features.v4_prospect_features created/updated
- [ ] Row count: __________ (~285,690 prospects)
- [ ] Feature count: 26 (including Career Clock features with fuzzy firm matching)
- [ ] Feature version: v4.3.2

### Step 3: Score Prospects with V4.3.1 Model (V4.3.2 features)
- [ ] Run: python pipeline/scripts/score_prospects_v43.py
- [ ] Verify: ml_features.v4_prospect_scores created/updated
- [ ] Row count: __________ (~285,690 scores)
- [ ] Career Clock features populated: cc_is_in_move_window, cc_is_too_early
- [ ] Bottom 20% count: __________ (~57,138 deprioritized)

### Step 4: Generate Base Lead List (Query 1)
- [ ] Run: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
- [ ] Verify: ml_features.january_2026_lead_list created
- [ ] Row count: __________ (~2,800 leads)

### Step 5: Insert M&A Leads (Query 2) ⚠️ MUST RUN AFTER STEP 4
- [ ] Run: pipeline/sql/Insert_MA_Leads.sql
- [ ] Verify: M&A leads added to existing table
- [ ] Total row count: __________ (~3,100 leads: 2,800 base + 300 M&A)

### Step 6: Export to CSV
- [ ] Run: python pipeline/scripts/export_lead_list.py
- [ ] Verify: CSV file created in pipeline/exports/
- [ ] File name: [month]_2026_lead_list_YYYYMMDD.csv
- [ ] Row count: __________
- [ ] Bottom 20% count: __________

### Step 4: Generate Base Lead List (Query 1)
- [ ] Run: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
- [ ] Verify: ml_features.january_2026_lead_list created
- [ ] Base lead count: __________ (~2,800 leads)

### Step 5: Insert M&A Leads (Query 2) ⚠️ MUST RUN AFTER STEP 4
- [ ] Run: pipeline/sql/Insert_MA_Leads.sql
- [ ] Verify: M&A leads added to existing table
- [ ] Total lead count: __________ (~3,100: 2,800 base + 300 M&A)

### Step 6: Export to CSV
- [ ] Run: python pipeline/scripts/export_lead_list.py
- [ ] Verify: CSV file created in pipeline/exports/
- [ ] File name: [month]_2026_lead_list_YYYYMMDD.csv
- [ ] Upload to Salesforce
- [ ] Notify team
```

### Changelog

#### V3.6.1 / V4.3.2 - January 8, 2026 - Career Clock Fuzzy Firm Matching + Recent Promotee Feature

**V4.3.2 Changes**:
- Fixed Career Clock fuzzy firm name matching: Excludes same firm with different CRD (re-registrations)
- Example: James Patton at "Patton Albertson Miller Group" (CRD 281558) had "Patton Albertson & Miller" (CRD 126145) incorrectly counted as prior job
- Impact: ~135 advisors removed from incorrect move window status
- Uses first-15-chars fuzzy match on cleaned firm names (validated 100% accuracy)

**V4.3.1 Changes** (from previous update):
- Fixed Career Clock data quality: Excluded current firm from employment history calculation
- Added Recent Promotee feature: `is_likely_recent_promotee` (26th feature, 2.39% importance)
- Test AUC: 0.6322 (slightly below V4.3.0's 0.6389, acceptable after data quality fix)
- Top Decile Lift: 2.40x (still strong performance)
- Uses gain-based narratives (SHAP deferred to V4.4.0)
- Fixed duplicate prevention in `v4_prospect_features.sql` (QUALIFY ROW_NUMBER on firm-level JOINs)

**V3.6.1 Changes**:
- Career Clock tiers (0A, 0B, 0C) - timing-aware prioritization (from V3.6.0)
- Zero Friction tier (TIER_1B_PRIME_ZERO_FRICTION) - 13.64% conversion (from V3.6.0)
- Sweet Spot tiers (TIER_1G_ENHANCED_SWEET_SPOT) - 9.09% conversion (from V3.6.0)
- **NEW**: Recent Promotee exclusion (<5yr tenure + mid/senior titles) - excludes ~1,915 low-converting leads
- **NEW**: V4 deprioritization filter for M&A leads (V4 percentile >= 20)
- M&A tiers from V3.5.0 preserved

#### V3.5.0 / V4.2.0 - January 7, 2026 - Age Feature + SHAP Resolution

**Summary:** Added age_bucket_encoded as 23rd feature to V4 model, significantly improving model performance. Resolved SHAP TreeExplainer bug by switching to gain-based narratives.

**V4.2.0 Model Changes:**

1. **Added age_bucket_encoded Feature**
   - Encoding: UNDER_35=0, 35_49=1, 50_64=2, 65_69=3, 70_PLUS=4
   - Correlation with experience_years: 0.072 (provides unique signal)
   - Feature importance: Rank #10 of 23, 4.34% of total gain

2. **Performance Improvements**
   | Metric | V4.1.0 R3 | V4.2.0 | Improvement |
   |--------|-----------|--------|-------------|
   | Test AUC-ROC | 0.620 | 0.6352 | **+1.52%** |
   | Top Decile Lift | 2.03x | 2.28x | **+12.3%** |
   | Overfitting Gap | 0.075 | 0.0264 | **-64.8%** |

3. **Validation Gates - ALL PASSED**
   - G1: AUC ≥ 0.620 → ✅ 0.6352
   - G2: Lift ≥ 2.03x → ✅ 2.28x
   - G3: Overfit < 0.15 → ✅ 0.0264

**SHAP Resolution:**

1. **Problem:** SHAP TreeExplainer failed with `ValueError: could not convert string to float: '[5E-1]'`
   - Root cause: XGBoost serializes `base_score` incorrectly in pickle format
   - Multiple fix attempts failed (JSON conversion, monkey-patching, Explainer fallback)

2. **Solution:** Switched to gain-based narratives
   - Uses XGBoost native feature importance (instant, reliable)
   - Identifies top 3 "notable" features per lead
   - Generates human-readable narrative

3. **Model Serialization Updated:**
   - Primary format: `model.json` (XGBoost native)
   - Backup: `model.pkl` and `model_backup.pkl` (legacy)
   - Future models: Must verify SHAP works before deployment

**Files Created:**
- `v4/models/v4.2.0/model.json` - Primary model file
- `v4/models/v4.2.0/feature_importance.csv` - Gain-based importance
- `v4/models/v4.2.0/training_metrics.json` - Validation results
- `v4/SHAP_debug.md` - Full debugging history
- `v4/reports/v4.2/V4.2_Final_Summary.md` - Deployment summary

**Files Modified:**
- `v4/inference/lead_scorer_v4.py` - Gain-based narratives
- `v4/training/train_v42_age_feature.py` - Save as JSON, verify SHAP
- `pipeline/sql/v4_prospect_features.sql` - Added age_bucket_encoded
- `README.md` - This document

**Lift by Decile (V4.2.0):**
| Decile | Conv Rate | Lift |
|--------|-----------|------|
| 10 (Top) | 8.93% | **2.28x** |
| 9 | 6.71% | 1.71x |
| 8 | 3.61% | 0.92x |
| ... | ... | ... |
| 1 (Bottom) | 1.21% | 0.31x |

**Key Learnings:**
1. **Age provides unique signal** - Low correlation with experience (0.072) means age captures different information
2. **XGBoost serialization quirks** - Always set `base_score` explicitly and verify SHAP after training
3. **Gain-based narratives work well** - Simpler, faster, and more reliable than SHAP for production use

---

| Version | Date | Changes |
|---------|------|---------|
| V3.5.0 | 2026-01-03 | M&A Active Tiers - Two-query architecture, 300 M&A leads, 9.0% conversion |
| V3.3.1 | 2025-12-31 | Portable Book Signal Exclusions - Low discretionary AUM exclusion, large firm flag |
| V4.2.0 (old) | 2026-01-01 | Career Clock deployment - 29 features, 0.626 AUC (superseded by age feature version) |
| V4.1.0 R3 | 2025-12-30 | Deprecated 2026-01-01 - 22 features, 0.620 AUC, 2.03x lift |
| V4.1.0 R2 | 2025-12-30 | Added regularization - overfitting controlled |
| V4.1.0 R1 | 2025-12-30 | Initial V4.1 training - 26 features |
| V4.0.0 | 2025-12-15 | Original ML model - 14 features, 0.599 AUC |
| V3.2.5 | 2025-12-01 | Rules-based tier system - production |

---

## V3.3.1: Portable Book Signal Exclusions (December 2025)

### Background & Motivation

In December 2025, we conducted a comprehensive hypothesis validation analysis to test four signals that might indicate advisors with **portable books of business**:

| Hypothesis | Theory | Data Source |
|------------|--------|-------------|
| Solo-Practitioner Proxy | Advisors at firms with 1-3 reps OWN the book entirely | `firm_rep_count` calculated from FinTrx |
| Discretionary AUM Ratio | >80% discretionary = trust-based, portable relationships | `ria_firms_current.DISCRETIONARY_AUM / TOTAL_AUM` |
| Portable Custodian | Schwab/Fidelity/Pershing = easier transitions | `ria_firms_current.CUSTODIAN_PRIMARY_BUSINESS_NAME` |
| Rainmaker vs Servicer | Founders/Partners own books; Associates don't | `ria_contacts_current.TITLE_NAME` pattern matching |

### 🔄 Key Finding: Invert Your Thinking

**These signals work better as EXCLUSION criteria than INCLUSION criteria.**

Our existing tier system (CFP + Bleeding Firm, Series 65 Only, HV Wealth Titles) already captures positive signals effectively. The portable book analysis revealed **strong NEGATIVE signals** that help filter out low-converting leads.

### ✅ Validated Signals (Implemented)

| Signal | Conversion Rate | Lift vs Baseline | Action | Impact |
|--------|-----------------|------------------|--------|--------|
| **Low Discretionary (<50%)** | 1.32% | **0.34x** | **EXCLUDE** | ~5,800 leads removed |
| **Large Firm (>50 reps)** | 2.31% | **0.60x** | **V4 DEPRIORITIZE** | Flag for ML |
| **Servicer Titles** | 1.91% | **0.50x** | **EXCLUDE** | Already implemented |
| Moderate Discretionary (50-80%) | 1.48% | 0.39x | Monitor | Future consideration |

### ❌ Signals NOT Added (Invalidated by Data)

| Signal | Conversion Rate | Lift | Why NOT Added |
|--------|-----------------|------|---------------|
| **Solo Practitioner (1-3 reps)** | 3.75% | 0.98x | Not significantly better than 3.82% baseline |
| **Rainmaker Titles** | 2.23% | **0.58x** | Actually **WORSE** than regular producers! |
| **Portable Custodian** | N/A | N/A | Data quality issue - 0 matches found |

### 🤔 Why Rainmakers Convert Worse (Counterintuitive but Logical)

The hypothesis that Founders/Principals/Partners would convert better was intuitive but **wrong**:

1. **Already successful** - They've built their ideal practice; why change?
2. **Equity-locked** - Partnership agreements create golden handcuffs
3. **Succession mindset** - Planning exit, not growth
4. **Our sweet spot is mid-career** - Ambitious producers building toward ownership

**This validates our existing model's focus on mobility + bleeding firms over seniority/ownership titles.**

### 📊 Discretionary AUM Data Quality

The discretionary signal comes from **Form ADV** regulatory filings:

| Discretionary Bucket | Firm Count | Avg AUM | % of Firms |
|---------------------|------------|---------|------------|
| 95%+ Discretionary | 21,366 | $5.4B | 47% |
| 80-95% Discretionary | 2,370 | $4.5B | 5% |
| 50-80% Discretionary | 1,364 | $7.7B | 3% |
| <50% Discretionary | 1,159 | $7.4B | 3% |
| 0% Discretionary | 1,972 | $500M | 4% |
| No AUM Data | 17,002 | N/A | 38% |

**Key Insight:** Low discretionary firms are NOT small firms - they're large ($7.4B avg AUM) but have a fundamentally different business model (transaction-based, not relationship-based). The 0.34x lift isn't because they're small; it's because their client relationships aren't portable.

### 🔧 Implementation Details

**Files Modified:**
```
v3/sql/phase_4_v3_tiered_scoring.sql     # Added firm_discretionary CTE + exclusion filter
pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql  # Added discretionary filter
pipeline/sql/v4_prospect_features.sql    # Added is_large_firm feature
v3/models/model_registry_v3.json         # Updated to V3.3.1
```

**SQL Exclusion Filter:**
```sql
-- Exclude low discretionary firms (0.34x baseline)
-- Allow NULL/Unknown - don't penalize missing data
AND (
    discretionary_ratio >= 0.50 
    OR discretionary_ratio IS NULL
)
```

**New V4 Feature:**
```sql
-- Large firm flag for deprioritization
CASE WHEN firm_rep_count_at_contact > 50 THEN 1 ELSE 0 END as is_large_firm
```

### 📈 Expected Impact

| Metric | Before V3.3.1 | After V3.3.1 | Change |
|--------|---------------|--------------|--------|
| Total Lead Pool | ~35,000 | ~29,200 | -17% |
| Excluded Lead Conv Rate | - | 1.32% | - |
| Remaining Pool Conv Rate | 3.82% | ~4.1% (est) | **+7%** |
| High-Tier Overlap | - | <5% | ✅ Safe |

### 🔬 Analysis Documentation

Full analysis details available in:
- `v3/VERSION_3_MODEL_REPORT.md` - Section: V3.3.1 Portable Book Signal Analysis
- `portable-book-analysis.md` - Raw analysis results
- `v3/models/model_registry_v3.json` - Version changelog

### 🚀 Future Enhancements

Based on the analysis, consider these future improvements:

1. **Investigate Custodian Data** - Run diagnostic queries to understand actual field values
2. **Test Moderate Discretionary Exclusion** - Consider excluding 50-80% range (0.39x lift)
3. **Add Discretionary to V4 Model** - Include as continuous feature for ML optimization
4. **Monitor Exclusion Impact** - Track actual conversion rates post-implementation

---

*Analysis conducted December 2025. Implementation: V3.3.1_12312025_PORTABLE_BOOK_EXCLUSIONS*

---

## V3.3.2: Growth Stage Advisor Tier (January 2026)

### Background & Discovery

Following V3.3.1, we tested additional "portable book" hypotheses. While most individual signals were invalidated (ownership, HNW focus, SMA usage), we discovered a powerful new segment through combination analysis:

**"Proactive Movers"** - Advisors at STABLE firms who are seeking a platform upgrade.

This is fundamentally different from our existing bleeding-firm tiers (T1A, T1B, T1F) which target "reactive movers" in crisis situations.

### Two Types of High-Converting Leads

| Mover Type | Firm Status | Motivation | Tiers |
|------------|-------------|------------|-------|
| **Reactive Movers** | Bleeding | "My firm is failing, I need to leave" | T1A, T1B, T1F |
| **Proactive Movers** ⭐ | **Stable** | "I've outgrown my firm, I want better" | **T1G (NEW)** |

### T1G: Growth Stage Advisor

**Definition:**
```sql
WHEN industry_tenure_months BETWEEN 60 AND 180  -- 5-15 years (mid-career)
     AND avg_account_size >= 250000              -- Established practice ($250K+)
     AND firm_net_change_12mo > -3               -- Stable firm (not bleeding)
THEN 'TIER_1G_GROWTH_STAGE_ADVISOR'
```

**Performance:**

| Metric | Value |
|--------|-------|
| Conversion Rate | **7.20%** |
| Lift vs Baseline | **1.88x** |
| Sample Size | 125 leads (validated), 92 leads (production) |
| Overlap with T1A/T1B | **0** (mutually exclusive) |
| **Actual Performance** | **8.70%** (exceeds expected) |

**Why They Convert:**
1. **Strategic mindset** - Making thoughtful career decisions, not panic moves
2. **Established book** - Have real AUM ($250K+ avg account) to bring
3. **Growth-oriented** - Mid-career (5-15 years), still building
4. **Platform fit** - Need better technology/support to reach next level

### Updated Tier Hierarchy

| Priority | Tier | Definition | Conv Rate | Lift |
|----------|------|------------|-----------|------|
| 1 | **T1A** | CFP + Bleeding Firm | 9.80% | 2.57x |
| 2 | **T1G** ⭐ | **Growth Stage (NEW)** | **7.20%** | **1.88x** |
| 3 | **T1B** | Series 65 + Bleeding | 6.18% | 1.62x |
| 4 | T1F | HV Wealth + Bleeding | ~5% | ~1.3x |
| 5 | T1 | Prime Mover + Bleeding | ~4% | ~1.0x |

### Validation Results

| Check | Threshold | Result | Status |
|-------|-----------|--------|--------|
| Lift | ≥ 1.5x | 1.88x | ✅ PASS |
| Sample Size | ≥ 50 | 125 (validated), 92 (production) | ✅ PASS |
| Overlap with T1A | 0 | 0 | ✅ PASS |
| Overlap with T1B | 0 | 0 | ✅ PASS |
| 95% CI | Non-overlapping | ✅ | ✅ PASS |
| **Production Performance** | 7.20% expected | **8.70% actual** | ✅ **EXCEEDS** |

### Why T1G Has Zero Overlap

T1G is **mutually exclusive** with existing tiers because of firm stability requirements:

- **T1A/T1B/T1F:** Require `firm_net_change_12mo <= -3` (bleeding)
- **T1G:** Requires `firm_net_change_12mo > -3` (stable)

A firm cannot be both bleeding AND stable simultaneously.

### V3.3.2 Hypothesis Testing Summary

**Individual Signals (All Failed):**

| Signal | Expected | Actual | Result |
|--------|----------|--------|--------|
| Low Ownership (<5%) | >1.5x | 0.64x | ❌ INVERTED |
| HNW Focus ($500K+ avg) | >1.5x | 0.54x | ❌ INVERTED |
| SMA Usage | >1.5x | N/A | ❌ Data issue |
| Portable Custodian | >1.5x | 0.88x | ❌ Not significant |

**Combination Analysis (Success):**

| Combination | Conv Rate | Lift | Result |
|-------------|-----------|------|--------|
| **Established + Stable + Mid-Career** | **7.20%** | **1.88x** | ✅ **T1G** |
| Growth Focus + Bleeding + Senior | 5.79% | 1.52x | ⚠️ Alternative |

### Implementation Details

**Files Modified:**
```
v3/sql/phase_4_v3_tiered_scoring.sql          # T1G tier logic + avg_account_size CTE
pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql  # T1G in lead list
v3/models/model_registry_v3.json              # Updated to V3.3.2
README.md                                      # This section
v3/VERSION_3_MODEL_REPORT.md                  # Analysis documentation
```

**New Feature Added:**
```sql
-- avg_account_size = TOTAL_AUM / TOTAL_ACCOUNTS
-- Identifies "established practice" - advisors with meaningful client base
avg_account_size >= 250000  -- $250K+ average account
```

### Key Learnings

1. **Two types of high-converting leads exist:**
   - Reactive (bleeding firm, crisis-driven)
   - Proactive (stable firm, growth-driven)

2. **"Portable book" signals don't work individually:**
   - Ownership, HNW focus, SMA usage all failed or inverted
   - The COMBINATION matters, not individual signals

3. **Counter-intuitive findings:**
   - HNW advisors convert WORSE (too established, not looking to move)
   - Retail advisors convert BETTER (still growing, open to change)

4. **CFP detection was using wrong field:**
   - Was: `REP_LICENSES LIKE '%CFP%'` (WRONG - CFP is not a license)
   - Fixed: `CONTACT_BIO LIKE '%CFP%' OR TITLE_NAME LIKE '%CFP%'`

### Expected Impact

| Metric | Before V3.3.2 | After V3.3.2 | Change |
|--------|---------------|--------------|--------|
| Priority Tiers | T1A, T1B, T1F | T1A, T1B, T1F, **T1G** | +1 tier |
| High-Converting Leads | ~310 | ~435 | **+125 leads** |
| New Segment | - | Proactive movers | ✅ Captured |

### Future Opportunities

**T1H Super-Tier (Monitor for V4):**
- Definition: Certification (CFP/Series 65) + T1G criteria
- Performance: 8.57% conversion (2.24x lift)
- Current sample: 35 leads (too small)
- Action: Monitor - implement if sample grows to 50+

---

*V3.3.2 implemented January 2026 | Analysis: V3.3.2 Growth Stage Hypothesis Validation*

---

## V3.3.3: Zero Friction + Sweet Spot Tiers (January 2026)

### Major Discoveries

The V3.3.3 Matrix Effects Analysis uncovered two breakthrough findings through a comprehensive "interaction effects" study.

### Discovery #1: T1B_PRIME - Zero Friction Bleeder (NEW HIGHEST TIER)

**The Finding:** When ALL transition barriers are removed AND the firm is bleeding, conversion jumps to **13.64%** - our highest-converting segment ever.

**The "Zero Friction" Components:**

| Component | What It Does | Why It Matters |
|-----------|--------------|----------------|
| **Series 65 Only** | No broker-dealer lock-in | Pure RIA can move without FINRA complications |
| **Portable Custodian** | Schwab/Fidelity/Pershing | Same platform at new firm = "Negative Consent" paperwork only |
| **Small Firm (≤10)** | No bureaucratic barriers | No committee approvals, no retention negotiations |
| **Bleeding Firm** | Motivation to leave | Firm instability creates urgency |

**Performance:**

| Metric | Value |
|--------|-------|
| Conversion Rate | **13.64%** |
| Lift vs Baseline | **3.57x** |
| Sample Size | 22 leads |
| Previous Best | T1A at 9.80% |

**Key Insight - Matrix Effects Are Real:**
```
Individual signals:
- Series 65 Only: ~1.0x (neutral)
- Portable Custodian: 0.84x (negative!)
- Small Firm: 2.36x (positive)

Combined (all three + bleeding):
- 3.57x (multiplicative, not additive!)
```

### Discovery #2: T1G_ENHANCED - AUM Sweet Spot (UPGRADED)

**The Finding:** The optimal AUM range is **$500K-$2M**, not just $250K+. This refinement improves conversion by **79%**.

| AUM Range | Conversion | Lift | Improvement |
|-----------|------------|------|-------------|
| **$500K-$2M (Sweet Spot)** | **9.09%** | **2.38x** | - |
| Outside Range ($250K-$500K or $2M+) | 5.08% | 1.33x | - |
| **Improvement** | - | - | **+79%** |

**Why $500K-$2M Works:**
- **Big enough:** Clients are loyal to the ADVISOR, not the brand
- **Small enough:** Avoids institutional lock-in and golden handcuffs

### Updated Tier Hierarchy (V3.3.3)

| Priority | Tier | Definition | Conv Rate | Lift | Change |
|----------|------|------------|-----------|------|--------|
| **1** | **T1B_PRIME** ⭐ | Zero Friction Bleeder | **13.64%** | **3.57x** | **NEW** |
| 2 | T1A | CFP + Bleeding | 10.00% | 2.62x | - |
| **3** | **T1G_ENHANCED** ⭐ | Growth Stage + $500K-$2M | **9.09%** | **2.38x** | **UPGRADED** |
| 4 | T1B | S65 + Bleeding | 5.49% | 1.44x | - |
| 5 | T1G_REMAINDER | Growth Stage (outside range) | 5.08% | 1.33x | **NEW** |

### Tier Criteria Reference

#### T1B_PRIME: Zero Friction Bleeder
```sql
WHEN has_series_65_only = 1                  -- Pure RIA
     AND has_portable_custodian = 1          -- Schwab/Fidelity/Pershing
     AND firm_rep_count_at_contact <= 10     -- Small firm
     AND firm_net_change_12mo <= -3          -- Bleeding
     AND has_cfp = 0                         -- No CFP (goes to T1A)
THEN 'TIER_1B_PRIME_ZERO_FRICTION'
```

#### T1G_ENHANCED: Sweet Spot Growth Advisor
```sql
WHEN industry_tenure_months BETWEEN 60 AND 180    -- 5-15 years
     AND avg_account_size BETWEEN 500000 AND 2000000  -- Sweet spot
     AND firm_net_change_12mo > -3                -- Stable firm
THEN 'TIER_1G_ENHANCED_SWEET_SPOT'
```

### Matrix Effects Key Learning

**Before V3.3.3:** We tested signals individually and many failed (custodian = 0.84x).

**After V3.3.3:** We discovered signals work as a **SYSTEM**:

| Analysis Approach | Finding |
|-------------------|---------|
| Custodian alone | 0.84x (NEGATIVE) |
| S65 + Custodian | 2.09x (good) |
| S65 + Custodian + Small | 2.28x (better) |
| **S65 + Custodian + Small + Bleeding** | **3.57x (BEST)** |

**The Pattern:** Platform friction signals are **multiplicative**, not additive.

### Implementation Details

**Files Modified:**
```
v3/sql/phase_4_v3_tiered_scoring.sql
  - Added firm_custodian CTE
  - Added has_portable_custodian flag
  - Added T1B_PRIME tier logic
  - Split T1G into T1G_ENHANCED and T1G_REMAINDER

pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
  - Updated tier logic

v3/models/model_registry_v3.json
  - Updated to V3.3.3
```

**New Features Added:**
- `has_portable_custodian` flag (Schwab/Fidelity/Pershing detection)
- `has_cfp` flag for T1B_PRIME exclusion (CFP leads go to T1A)
- Refined AUM range ($500K-$2M sweet spot)

### Validation Results

| Check | Result | Status |
|-------|--------|--------|
| T1B_PRIME unique leads | 22 | ✅ |
| T1B_PRIME has no CFP overlap | 0 CFP leads | ✅ |
| T1G_ENHANCED is subset | Confirmed | ✅ |
| T1G_ENHANCED outperforms | 9.09% vs 5.08% | ✅ |

### Expected Impact

| Metric | Before V3.3.3 | After V3.3.3 | Change |
|--------|---------------|--------------|--------|
| Highest Tier Conv | 9.80% (T1A) | **13.64%** (T1B_PRIME) | **+39%** |
| T1G Performance | 7.20% | **9.09%** (Enhanced) | **+26%** |
| New Tier 1 Leads | 0 | 22 (T1B_PRIME) | +22 |

### Deferred: Succession Gap Analysis

**Status:** ⏸️ Data unavailable

The "Succession Gap" hypothesis (T1G leads at aging firms with 20+ year principals) could not be validated because `FIRM_START_DATE` is not available in the data.

**Future Action:** Investigate if SEC registration date or alternative fields can serve as proxy.

---

*V3.3.3 implemented January 2026 | Analysis: V3.3.3 Matrix Effects + Pre-Implementation Validation*

---

## Testing & Validation

### V3 Model Validation

**Training Period**: February 2024 - July 2025 (30,727 leads)  
**Test Period**: August 2025 - October 2025 (6,919 leads)  
**Gap**: 30 days (prevents data leakage)

**Results**:

| Tier | Training Conv Rate | Test Conv Rate | Lift | Status |
|------|-------------------|----------------|------|--------|
| T1A | 16.44% | 15.2% | 4.30x | ✅ Validated |
| T1B | 16.48% | 14.8% | 4.31x | ✅ Validated |
| T1 | 13.21% | 12.5% | 3.46x | ✅ Validated |
| T2 | 8.59% | 8.1% | 2.50x | ✅ Validated |
| T3 | 9.52% | 9.0% | 2.77x | ✅ Validated |
| T4 | 11.54% | 11.2% | 3.35x | ✅ Validated |
| T5 | 7.27% | 7.0% | 2.11x | ✅ Validated |

**Statistical Validation**:
- All priority tiers have 95% confidence intervals that **do not overlap** with baseline
- Temporal validation confirms model robustness on future data

---

### V4 Model Validation

**Training Period**: 2024-02-01 to 2025-07-31  
**Test Period**: 2025-08-01 to 2025-10-31  
**Cross-Validation**: 5 time-based folds

**Results**:

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| AUC-ROC | 0.6352 | ≥ 0.620 | ✅ Passed (+1.52% vs V4.1.0) |
| AUC-PR | 0.0749 | ≥ 0.070 | ✅ Passed (+7.0% vs V4.1.0) |
| Top Decile Lift | 2.28x | ≥ 2.03x | ✅ Passed (+12.3% vs V4.1.0) |
| Overfitting Gap | 0.0264 | < 0.15 | ✅ Passed (-64.8% vs V4.1.0) |

**Lift by Decile (V4.2.0)**:

| Decile | Leads | Conversions | Conv Rate | Lift |
|--------|-------|-------------|-----------|------|
| 1 (Bottom) | 339 | 4 | 1.21% | 0.31x |
| 2 | 339 | 5 | 1.50% | 0.38x |
| 3 | 339 | 11 | 3.24% | 0.83x |
| 4 | 339 | 11 | 3.39% | 0.86x |
| 5 | 339 | 15 | 4.30% | 1.10x |
| 6 | 339 | 17 | 5.11% | 1.30x |
| 7 | 339 | 3 | 0.86% | 0.22x |
| 8 | 339 | 12 | 3.61% | 0.92x |
| 9 | 339 | 22 | 6.71% | 1.71x |
| 10 (Top) | 339 | 29 | 8.93% | 2.28x ⭐ |

**Key Findings (V4.2.0)**:
- **Bottom 20%** converts at **1.21%** (0.31x lift) - strong deprioritization signal
- **Top 20%** converts at **8.93%** (2.28x lift) - upgrade signal
- **STANDARD tier with V4 ≥ 80%**: Improved conversion with age feature

---

### Hybrid Approach Validation (Option C)

**Investigation Findings**:

| Finding | Evidence | Action |
|---------|----------|--------|
| V3 tier ordering validated | T1B converts at 11.76% vs T2 at 5.91% | ✅ Keep V3 prioritization |
| TIER_4 converts at baseline | 2.74% = baseline, no value added | ❌ **EXCLUDED** (Option C) |
| TIER_5 marginal lift | 3.42% = only 1.2x baseline | ❌ **EXCLUDED** (Option C) |
| V4 deprioritization effective | Bottom 20% converts at 1.33% (0.42x) | ✅ Applied across all tiers |
| STANDARD + V4 ≥ 80% converts at 3.67% | 6,043 historical leads validated | ✅ Used for backfill only |

**Hybrid Strategy (Option C)**:
- **V3 Rules**: Primary prioritization (T1A, T1B, T1, T1F, T2, T3 only)
- **V4 ML**: Deprioritization (bottom 20%) + backfill identification (STANDARD with V4 ≥ 80th percentile)
- **Expected Improvement**: +68.5% vs baseline (4.61% vs 2.74%)

**Validation Results (January 2026)**:
- Total leads: 2,768 (198 per SGA)
- Expected conversion: 4.61% (128 MQLs)
- Conservative estimate (P10): 3.85% (107 MQLs)
- P(exceed baseline): 99.98%
- P(exceed 5%): 25.3%

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "No v4_prospect_scores found" | Step 3 not completed | Run `score_prospects_v43.py` first |
| Low V4 percentile average | V4 scores not joined | Check JOIN in `v4_enriched` CTE |
| Too few leads (< 200 per SGA) | Tier quotas too restrictive or insufficient prospects | Check tier distribution, verify SGA count, check prospect pool |
| Duplicate CRDs | JOIN issue | Add DISTINCT or fix JOIN logic |
| Missing features | Column name mismatch | Check feature names in `final_features.json` |
| SHAP calculation fails | Memory or model issues | Use feature importance fallback (already implemented) |
| SHAP TreeExplainer fails with base_score error | XGBoost serialization bug | See [SHAP base_score Error](#shap-treesplainer-fails-with-base_score-error) below |

### Debug Queries

**Check V4 scores exist**:
```sql
SELECT COUNT(*) 
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`;
```

**Check V4 deprioritize distribution**:
```sql
SELECT 
    v4_deprioritize,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
GROUP BY 1;
```

**Check tier distribution**:
```sql
SELECT 
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(v4_percentile), 1) as avg_v4_percentile
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY score_tier
ORDER BY COUNT(*) DESC;
```

**Check SGA lead counts** (should be exactly 200 per SGA):
```sql
SELECT 
    sga_owner,
    COUNT(*) as lead_count,
    ROUND(AVG(expected_rate_pct), 2) as avg_expected_conv_pct,
    ROUND(SUM(expected_rate_pct) / 100.0, 1) as total_expected_mqls
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY sga_owner
ORDER BY sga_owner;
```

**Check SGA conversion rate equity** (should be similar across SGAs):
```sql
SELECT 
    sga_owner,
    COUNT(*) as lead_count,
    ROUND(AVG(expected_rate_pct), 2) as avg_expected_conv_pct,
    ROUND(SUM(expected_rate_pct) / 100, 1) as expected_conversions
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY sga_owner
ORDER BY sga_owner;
```

**Check SGA tier distribution** (should be similar across SGAs):
```sql
SELECT 
    sga_owner,
    score_tier,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY sga_owner), 1) as pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY sga_owner, score_tier
ORDER BY sga_owner, score_tier;
```

**Check Salesforce matching and prospect types**:
```sql
SELECT 
    prospect_type,
    COUNT(*) as lead_count,
    COUNT(DISTINCT salesforce_lead_id) as with_salesforce_id,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY prospect_type
ORDER BY prospect_type;
```

**Verify no duplicate Salesforce leads**:
```sql
-- Check if any leads in list are already in Salesforce (should only be recyclable)
SELECT 
    COUNT(*) as total_leads,
    SUM(CASE WHEN salesforce_lead_id IS NOT NULL THEN 1 ELSE 0 END) as in_salesforce,
    SUM(CASE WHEN prospect_type = 'NEW_PROSPECT' AND salesforce_lead_id IS NOT NULL THEN 1 ELSE 0 END) as new_prospects_with_sf_id,
    SUM(CASE WHEN prospect_type != 'NEW_PROSPECT' THEN 1 ELSE 0 END) as recyclable_leads
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`;
```

**Verify firm exclusions**:
```sql
-- Check no excluded firms slipped through
SELECT 
    jl.firm_name,
    ef.pattern as matched_pattern,
    ef.category
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` jl
INNER JOIN `savvy-gtm-analytics.ml_features.excluded_firms` ef
    ON UPPER(jl.firm_name) LIKE ef.pattern;
-- Expected: 0 rows

-- Check no excluded CRDs slipped through
SELECT jl.firm_name, jl.firm_crd
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` jl
INNER JOIN `savvy-gtm-analytics.ml_features.excluded_firm_crds` ec
    ON jl.firm_crd = ec.firm_crd;
-- Expected: 0 rows
```

**Expected Results**:
- `new_prospects_with_sf_id` should be **0** (NEW_PROSPECT should not have salesforce_lead_id)
- `recyclable_leads` should have `salesforce_lead_id` populated
- Most leads should be `NEW_PROSPECT` (typically 80-90%)

---

## Appendix

## Repository Structure (Post-Cleanup)

**Last Updated**: December 30, 2025  
**Cleanup Status**: Completed (see `recommended_cleanup.md` for details)

### Core Production Files

```
lead_scoring_production/
├── README.md                          # This file - main documentation
├── Lead_Scoring_Methodology_Final.md  # Methodology documentation
├── MODEL_EVOLUTION_HISTORY.md         # Complete model evolution history
├── recommended_cleanup.md             # Cleanup plan and execution log
│
├── models/
│   └── UNIFIED_MODEL_REGISTRY.json    # Unified registry (references V3 & V4)
│
├── v3/                                # V3 Rules-Based Model (Production)
│   ├── sql/
│   │   ├── generate_lead_list_v3.3.0.sql  # Production SQL
│   │   ├── phase_4_v3_tiered_scoring.sql
│   │   ├── lead_scoring_features_pit.sql
│   │   ├── phase_7_production_view.sql
│   │   ├── phase_7_salesforce_sync.sql
│   │   └── phase_7_sga_dashboard.sql
│   ├── models/
│   │   └── model_registry_v3.json
│   ├── docs/
│   │   ├── LEAD_LIST_GENERATION_GUIDE.md
│   │   └── QUICK_START_LEAD_LISTS.md
│   ├── VERSION_3_MODEL_REPORT.md
│   └── PRODUCTION_MODEL_UPDATE_CHECKLIST.md
│
├── v4/                                # V4 XGBoost Model (Production)
│   ├── models/
│   │   ├── registry.json
│   │   └── v4.1.0_r3/                 # Production model
│   ├── data/
│   │   └── v4.1.0_r3/
│   │       └── final_features.json
│   ├── sql/
│   │   ├── production_scoring_v41.sql
│   │   └── v4.1/
│   │       ├── create_recent_movers_table.sql
│   │       ├── create_bleeding_velocity_table.sql
│   │       ├── create_firm_rep_type_features.sql
│   │       └── phase_2_feature_engineering_v41.sql
│   ├── inference/
│   │   └── lead_scorer_v4.py
│   ├── VERSION_4_MODEL_REPORT.md
│   └── reports/
│       └── v4.1/
│           ├── V4.1_Final_Summary.md
│           ├── model_validation_report_r3.md
│           └── shap_*.png
│
├── pipeline/                          # Production Pipeline
│   ├── sql/
│   │   ├── January_2026_Lead_List_V3_V4_Hybrid.sql  # Production lead list
│   │   ├── v4_prospect_features.sql
│   │   ├── create_excluded_firms_table.sql
│   │   ├── create_excluded_firm_crds_table.sql
│   │   ├── manage_excluded_firms.sql
│   │   └── recycling/
│   │       └── recyclable_pool_master_v2.1.sql
│   ├── scripts/
│   │   ├── score_prospects_monthly.py
│   │   ├── execute_january_lead_list.py
│   │   └── export_lead_list.py
│   └── Monthly_Lead_List_Generation_V3_V4_Hybrid.md
│
├── docs/                              # Core Documentation
│   ├── FINTRX_Architecture_Overview.md
│   ├── FINTRX_Data_Dictionary.md
│   ├── FINTRX_Lead_Scoring_Features.md
│   ├── RECYCLABLE_LEADS_GUIDE.md
│   ├── FIRM_EXCLUSIONS_GUIDE.md
│   └── SALESFORCE_INTEGRATION_GUIDE.md
│
└── archive/                           # Archived Files (Historical Reference)
    ├── v3/                            # V3 historical files
    ├── v4/                            # V4 deprecated models & training scripts
    ├── pipeline/                      # Pipeline historical files
    └── root/                          # Root-level analysis documents
```

### Archive Directory

**Purpose**: Historical files preserved for reference (not deleted)

**Contents**:
- Deprecated model versions (v4.0.0, v4.1.0, v4.1.0_r2)
- Historical training scripts (one-time use)
- Historical execution logs
- Historical analysis documents
- Old CSV exports (regenerate as needed)

**Note**: All files in `archive/` are preserved but not used in production. See `cleanup/phase_2_archive_summary.md` for complete list.

### File Structure (Legacy - See Above for Updated Structure)

```
lead_scoring_production/
├── pipeline/                          # Main pipeline directory
│   ├── sql/
│   │   ├── v4_prospect_features.sql   # Step 1: Feature calculation
│   │   ├── January_2026_Lead_List_V3_V4_Hybrid.sql  # Step 3: Hybrid query
│   │   ├── create_excluded_firms_table.sql  # Exclusion table creation
│   │   ├── create_excluded_firm_crds_table.sql  # CRD exclusion table
│   │   ├── manage_excluded_firms.sql  # Exclusion management queries
│   │   └── CENTRALIZED_EXCLUSIONS_SUMMARY.md  # Exclusion documentation
│   ├── scripts/
│   │   ├── score_prospects_v43.py      # Step 3: V4.3.0 ML scoring (USE THIS)
│   │   ├── score_prospects_monthly.py  # V4.2.0 only (deprecated - DO NOT USE)
│   │   ├── export_lead_list.py        # Step 6: CSV export
│   │   └── execute_january_lead_list.py  # Lead list execution helper
│   ├── exports/                       # CSV output files
│   ├── logs/                          # Execution logs
│   └── config/                        # Configuration files
├── v3/                                # V3 rules-based model
│   ├── models/
│   ├── scripts/
│   └── reports/
├── v4/                                # V4 XGBoost ML model
│   ├── models/v4.2.0/                 # V4.2.0 Age Feature (current production)
│   ├── models/v4.1.0_r3/             # V4.1.0 R3 (deprecated 2026-01-07, superseded by V4.2.0)
│   │   ├── model.pkl                  # Trained model
│   │   ├── model.json                 # Model config
│   │   └── feature_importance.csv     # Feature importance
│   ├── models/v4.0.0/                 # V4.0.0 (deprecated)
│   ├── data/v4.1.0/
│   │   └── final_features.json        # 22 feature list
│   └── reports/
├── docs/                              # Documentation
│   ├── FINTRX_Architecture_Overview.md
│   ├── FINTRX_Lead_Scoring_Features.md
│   └── FINTRX_Data_Dictionary.md
└── validation/                        # Testing & validation reports
```

### BigQuery Tables

| Table | Purpose | Created By |
|-------|---------|------------|
| `ml_features.active_ma_target_firms` | M&A target firm tracking | Manual (news feed) |
| `ml_features.ma_eligible_advisors` | Pre-built M&A advisor list | Step 1 (monthly) |
| `ml_features.v4_prospect_features` | V4 features for all prospects | Step 2 SQL |
| `ml_features.v4_prospect_scores` | V4 scores with percentiles | Step 3 Python |
| `ml_features.january_2026_lead_list` | Final lead list | Steps 4-5 SQL |
| `ml_features.excluded_firms` | Pattern-based firm exclusions | Manual (see Firm Exclusions section) |
| `ml_features.excluded_firm_crds` | CRD-based firm exclusions | Manual (see Firm Exclusions section) |

### Key Metrics Reference

| Metric | Value | Source |
|--------|-------|--------|
| Baseline conversion rate (Provided Lead List) | 2.74% | Historical data (32,264 leads) |
| V3 T1B conversion rate | 11.76% | V3 validation (34 leads) |
| V3 T3 conversion rate | 6.76% | V3 validation (74 leads) |
| V3 T1F conversion rate | 6.06% | V3 validation (99 leads) |
| V3 T2 conversion rate | 5.91% | V3 validation (711 leads) |
| V3 T1 conversion rate | 4.76% | V3 validation (42 leads) |
| HIGH_V4 backfill conversion rate | 3.67% | V4 validation (6,043 leads) |
| Target leads per month | ~2,800 | Business requirement (200 per SGA) |
| January 2026 actual leads | 2,768 | Generated list |
| Expected conversion rate | 4.61% | Option C backtest |

### Monthly Checklist

```markdown
## [MONTH] 2026 Lead List Generation

**Date**: YYYY-MM-DD
**Operator**: [Name]

### Pre-Flight Checks
- [ ] BigQuery access verified
- [ ] V4 model files present
- [ ] Previous month's list archived

### Step 1: V4 Features
- [ ] Created ml_features.v4_prospect_features
- [ ] Row count: ___________
- [ ] Feature coverage validated

### Step 2: V4 Scoring
- [ ] Scored all prospects
- [ ] Created ml_features.v4_prospect_scores
- [ ] Row count: ___________
- [ ] Deprioritize count (20%): ___________

### Step 3: Hybrid Query
- [ ] Ran V3 + V4 hybrid query
- [ ] Created ml_features.january_2026_lead_list
- [ ] Lead count: ___________
- [ ] Tier distribution validated
- [ ] Firm exclusions verified (0 excluded firms in list)
- [ ] Deduplication verified (0 duplicate CRDs)

### Step 4: Export
- [ ] Final validation passed
- [ ] Exported to CSV
- [ ] File location: ___________

### Summary
- **Total Leads**: ___________ (should be ~200 × number of active SGAs)
- **Leads per SGA**: ___________ (should be ~200)
- **Number of Active SGAs**: ___________
- **TIER_4 and TIER_5**: ___________ (should be 0 - Option C exclusion)
- **STANDARD_HIGH_V4 Backfill**: ___________ (should be ~200-400)
- **Avg V4 Percentile**: ___________
- **New Prospects**: ___________
- **Recyclable Leads**: ___________
- **Expected Conversion Rate**: ___________ (should be ~4.6%)
```

---

## References

- **Lead Scoring Methodology**: `Lead_Scoring_Methodology_Final.md` ⭐ **Primary methodology document**
- **V3 Model Report**: `v3/VERSION_3_MODEL_REPORT.md`
- **V4 Model Report**: `v4/VERSION_4_MODEL_REPORT.md`
- **Architecture Overview**: `docs/FINTRX_Architecture_Overview.md`
- **Feature Documentation**: `docs/FINTRX_Lead_Scoring_Features.md`
- **Validation Findings**: `validation/LEAD_SCORING_KEY_FINDINGS.md`
- **Monthly Generation Guide**: `pipeline/Monthly_Lead_List_Generation_V3_V4_Hybrid.md`

---

## Change Log

### V3.5.0 - January 3, 2026 - M&A Active Tiers + Two-Query Architecture

**Summary:** Added M&A opportunity tiers to capture advisors at firms undergoing M&A activity. Implemented two-query architecture after single-query approaches failed due to BigQuery CTE optimization issues.

#### Key Changes

1. **Added TIER_MA_ACTIVE_PRIME**
   - Senior title OR mid-career (10-20yr) at M&A target
   - Expected conversion: 9.0% (2.36x lift)
   - Validated on Commonwealth/LPL merger data

2. **Added TIER_MA_ACTIVE**
   - All advisors at M&A target firms
   - Expected conversion: 5.4% (1.41x lift)
   - Captures opportunity window (60-365 days post-announcement)

3. **Implemented Two-Query Architecture**
   - Query 1: Generate base lead list (standard leads)
   - Query 2: INSERT M&A leads after base list created
   - Reason: Single-query approaches failed due to BigQuery CTE optimization

4. **Created Pre-Built M&A Advisors Table**
   - `ml_features.ma_eligible_advisors` (~2,225 advisors)
   - Pre-computes tier assignments
   - Refreshed monthly or on M&A news

5. **Large Firm Exemption for M&A**
   - M&A advisors exempt from >50 rep exclusion
   - 293 of 300 M&A leads are at firms with >200 reps
   - Would have been excluded without M&A exemption

#### Evidence Supporting Changes

| Signal | Conversion | Lift | Action |
|--------|------------|------|--------|
| Commonwealth M&A (overall) | 5.37% | 1.41x | Add TIER_MA_ACTIVE |
| Senior titles at M&A | 9.30% | 2.06x | Add to TIER_MA_ACTIVE_PRIME |
| Mid-career at M&A | 8.16% | 1.75x | Add to TIER_MA_ACTIVE_PRIME |

#### Why Single-Query Failed

Four approaches were attempted and all failed:

1. EXISTS subquery exemption → Works in isolation, fails in full query
2. JOIN exemption → Works in isolation, fails in full query
3. UNION two-track → Works in isolation, fails in full query
4. LEFT JOIN with inline subquery → Works in isolation, fails in full query

Root cause: BigQuery's CTE optimization in complex queries (1,400+ lines) causes unpredictable behavior.

#### Files Created

- `pipeline/sql/create_ma_eligible_advisors.sql`
- `pipeline/sql/Insert_MA_Leads.sql`
- `pipeline/sql/pre_implementation_verification_ma_tiers.sql`
- `pipeline/sql/post_implementation_verification_ma_tiers.sql`
- `V3_5_0_MA_TIER_COMPREHENSIVE_IMPLEMENTATION_GUIDE.md`
- `pipeline/V3_5_0_MA_TIER_IMPLEMENTATION_RESULTS.md`

#### Files Modified

- `v3/models/model_registry_v3.json` (updated to V3.5.0)
- `README.md` (this document)
- `v3/VERSION_3_MODEL_REPORT.md`

#### Verification Results

| Check | Result |
|-------|--------|
| M&A tiers populated | ✅ 300 leads |
| Large firm exemption | ✅ 293 leads with >200 reps |
| No violations | ✅ 0 non-M&A large firms |
| Narratives | ✅ 100% coverage |

---

### V3.6.1 - January 8, 2026 - Career Clock Fix + Recent Promotee Exclusion

**Summary:** Fixed Career Clock data quality issue and added exclusion for low-converting recent promotees.

#### Key Changes

1. **Fixed Career Clock Data Quality**
   - Excluded current firm CRD from employment history calculation
   - ~692 advisors had polluted Career Clock data (10-19% of long-tenure advisors)
   - Example: Rafael Delasierra (founder, 27yr at firm) incorrectly in "move window"
   - Root cause: Firm re-registrations appearing as separate "completed jobs"
   - Impact by tenure bucket:
     - 10-15 years: 19.3% affected
     - 20+ years: 10.6% affected

2. **Added Recent Promotee Exclusion**
   - Advisors with <5yr tenure + mid/senior titles convert at 0.29-0.45%
   - This is 6-9x worse than 2.74% baseline
   - ~1,915 leads excluded from pipeline
   - Founders/Owners NOT excluded (1.07% conversion)
   - Rationale: Recent promotees don't have portable books yet

3. **Added V4 Filter to M&A Leads**
   - M&A leads now filtered by V4 percentile >= 20
   - Prevents low-V4 individuals from bypassing deprioritization
   - Example: Michael Puls (8th percentile) would now be excluded
   - While M&A tier has 9.0% aggregate conversion, V4 model can identify individual low-potential leads

#### Analysis Supporting Changes

| Finding | Data | Action |
|---------|------|--------|
| Current firm in history | 692 advisors, 10-19% of long-tenure | EXCLUDE from Career Clock calc |
| Recent promotee (Senior) | 0.29% conv (0.10x) | EXCLUDE |
| Recent promotee (Mid) | 0.45% conv (0.16x) | EXCLUDE |
| Founder/Owner | 1.07% conv (0.39x) | KEEP |
| Bottom 20% V4 in M&A | Unknown individual rate | EXCLUDE |

#### Files Modified

- `pipeline/sql/v4_prospect_features.sql` - Career Clock fix + Recent Promotee feature (V4.3.1)
  - Added `current_firm_crd` to `base_prospects` CTE
  - Added exclusion filter: `AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != bp.current_firm_crd`
  - Added `recent_promotee_feature` CTE to calculate `is_likely_recent_promotee` (26th feature)
  - Added feature to final SELECT and LEFT JOIN
  
- `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` - Recent promotee exclusion (V3.6.1)
  - Added `recent_promotee_exclusions` CTE
  - Applied filter in `enriched_prospects` WHERE clause
  
- `pipeline/sql/Insert_MA_Leads.sql` - V4 filter for M&A (V3.6.1)
  - Added V4 deprioritization filter: `AND COALESCE(v4.v4_percentile, 50) >= 20`
  - Enhanced comment with detailed rationale
  
- `v4/scripts/train_model_v43.py` - Updated to V4.3.1 (26 features)
  - Added `is_likely_recent_promotee` to feature list
  - Updated validation gates (adjusted AUC threshold for data quality fix)
  - Updated model output paths to `v4.3.1`
  
- `pipeline/scripts/score_prospects_v43.py` - Updated to V4.3.1 (26 features)
  - Added `is_likely_recent_promotee` to feature list and descriptions
  - Updated model path to `v4/models/v4.3.1`

#### Validation Queries

After deployment, run these queries to validate:

```sql
-- Validate Career Clock fix: Rafael should no longer be in move window
SELECT crd, cc_is_in_move_window, cc_avg_prior_tenure_months, cc_tenure_cv
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`
WHERE crd = 2206086;  -- Rafael Delasierra

-- Verify recent promotees are excluded
SELECT 
    CASE 
        WHEN c.INDUSTRY_TENURE_MONTHS < 60 
             AND (UPPER(c.TITLE_NAME) LIKE '%FINANCIAL ADVISOR%' 
                  OR UPPER(c.TITLE_NAME) LIKE '%WEALTH ADVISOR%'
                  OR UPPER(c.TITLE_NAME) LIKE '%SENIOR%')
             AND UPPER(c.TITLE_NAME) NOT LIKE '%FOUNDER%'
        THEN 'Recent Promotee'
        ELSE 'Other'
    END as category,
    COUNT(*) as lead_count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` ll
INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON ll.advisor_crd = c.RIA_CONTACT_CRD_ID
GROUP BY 1;

-- Check M&A leads V4 percentile distribution
SELECT 
    score_tier,
    COUNT(*) as total,
    SUM(CASE WHEN v4_percentile < 20 THEN 1 ELSE 0 END) as below_20_pct,
    AVG(v4_percentile) as avg_percentile
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%'
GROUP BY score_tier;
```

---

### V3.3.0 - December 30, 2025 - Bleeding Signal Refinement

**Summary:** Major refinement to bleeding signal based on comprehensive conversion analysis.

#### Key Changes

1. **REMOVED TIER_5_HEAVY_BLEEDER**
   - Analysis showed heavy bleeding firms convert at 3.27% (BELOW 3.82% baseline)
   - Root cause: Best advisors leave first; by heavy bleeding phase, opportunity passed
   - Impact: ~25,000 leads will now fall to STANDARD instead of priority tier

2. **Implemented Inferred Departures**
   - Now use `PRIMARY_FIRM_START_DATE` to infer departures from prior firm
   - Provides 60-90 day fresher signal than waiting for `END_DATE` backfill
   - Validation: Median gap between inferred and actual date is only 8 days

3. **Tightened TIER_3 Threshold**
   - Changed from -10 to -1 → -15 to -3 (net change)
   - Sweet spot: 3-15 departures indicates "conversations happening" without "too late"

4. **Added Bleeding Velocity**
   - New signal: ACCELERATING / STEADY / DECELERATING
   - Compares last 90 days vs prior 90 days
   - Accelerating = firm just started bleeding = optimal outreach window

5. **Added TIER_3A_ACCELERATING_BLEEDER**
   - Moderate bleeding + accelerating velocity
   - Estimated 6% conversion (to be validated)
   - Catch advisors in "should I go?" phase

#### Data Supporting These Changes

| Signal | Conversion | Decision |
|--------|------------|----------|
| Heavy Bleeding (16+ departures) | 3.27% | Remove tier (below baseline) |
| Moderate Bleeding (3-15) | 5.43% | Keep tier, tighten threshold |
| Low Bleeding (1-3) | 5.35% | Falls to moderate or stable |
| Stable (0) | 5.47% | Baseline comparison |
| Baseline (all leads) | 3.82% | Reference point |

#### Files Modified

- `v3/sql/generate_lead_list_v3.3.0.sql` (renamed from v3.2.1.sql)
  - Updated firm_departures CTE (inferred approach)
  - Added firm_departures_velocity CTE
  - Removed TIER_5_HEAVY_BLEEDER
  - Updated TIER_3 threshold
  - Added TIER_3A_ACCELERATING_BLEEDER

- `v3/models/model_registry_v3.json`
  - Version bump to V3.3.0
  - Updated tier definitions
  - Added change log

- `v3/VERSION_3_MODEL_REPORT.md`
  - Added V3.3 changes section
  - Updated tier hierarchy

#### Validation Plan

1. Deploy V3.3 for January 2026 lead list
2. Track conversion rates by tier for 90 days
3. Validate TIER_3A conversion estimate (~6%)
4. Compare V3.3 vs V3.2 tier distributions

#### Rollback Plan

If V3.3 underperforms:
1. Revert to V3.2.4 SQL
2. File preserved at `v3/sql/generate_lead_list_v3.2.1.sql.bak`

---

---

### December 30, 2025 - Centralized Firm Exclusion System

**Summary:** Migrated firm exclusions from hardcoded SQL patterns to centralized BigQuery tables.

#### Key Changes

1. **Created Exclusion Tables**:
   - `ml_features.excluded_firms`: 42 pattern-based exclusions (Wirehouse, Insurance, Large IBD, etc.)
   - `ml_features.excluded_firm_crds`: 2 CRD-based exclusions (Savvy, Ritholtz)

2. **Updated Lead List SQL**:
   - Changed from hardcoded `UNNEST([...])` to `SELECT pattern FROM ml_features.excluded_firms`
   - Changed exclusion logic from `NOT EXISTS` to `LEFT JOIN ... WHERE ... IS NULL` (BigQuery compatibility)

3. **Benefits**:
   - Easier maintenance: Add/remove exclusions without editing SQL
   - Audit trail: Track when exclusions were added
   - Documentation: Reason field explains each exclusion
   - Reusable: Same tables for future lead lists

#### Files Created

- `pipeline/sql/create_excluded_firms_table.sql`
- `pipeline/sql/create_excluded_firm_crds_table.sql`
- `pipeline/sql/manage_excluded_firms.sql`
- `pipeline/sql/CENTRALIZED_EXCLUSIONS_SUMMARY.md`

#### Files Updated

- `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
- `pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql`

---

**Document Version**: 3.6.1 (V4.3.1 Career Clock Data Quality Fix + Recent Promotee Exclusion)  
**Last Updated**: January 8, 2026  
**V3 Model Version**: V3.6.1_01082026_CAREER_CLOCK_TIERS  
**V4 Model Version**: V4.3.2 (26 features, gain-based narratives, Career Clock features with fuzzy firm matching fix + Recent Promotee feature)  
**Architecture**: Two-Query (CREATE then INSERT)  
**Maintainer**: Data Science Team  
**Questions?**: Contact the Data Science team

