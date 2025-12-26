# Lead Scoring Production Pipeline - Hybrid V3 + V4 Model

**Version**: 2.0  
**Last Updated**: December 2025  
**Status**: Production Ready

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Quick Start Guide](#quick-start-guide)
3. [Pipeline Architecture](#pipeline-architecture)
4. [Step-by-Step Execution](#step-by-step-execution)
5. [Model Logic & Methodology](#model-logic--methodology)
6. [V4 XGBoost Model Features](#v4-xgboost-model-features)
7. [Testing & Validation](#testing--validation)
8. [Troubleshooting](#troubleshooting)
9. [Appendix](#appendix)

---

## Executive Summary

This repository contains a **hybrid lead scoring system** that combines:

- **V3 Rules-Based Model**: Tiered classification system (T1A, T1B, T1, T2, T3, T4, T5) achieving **1.74x top decile lift**
- **V4 XGBoost ML Model**: Machine learning model that upgrades STANDARD tier leads with high conversion potential (4.60% conversion rate for top 20%)

**Key Results:**
- **Target Output**: 200 leads per active SGA (dynamically calculated)
- **V3 Tier Performance**: Top tiers convert at 7.41% - 16.48% (vs 3.20% baseline)
- **V4 Upgrade Performance**: STANDARD leads with V4 ≥ 80th percentile convert at 4.60% (1.42x baseline)
- **Expected Improvement**: +6-12% overall conversion rate
- **Equitable Distribution**: Each SGA receives exactly 200 leads with similar expected conversion rates

**Monthly Time Estimate**: 15-20 minutes once pipeline is set up

---

## Quick Start Guide

### Prerequisites

Before starting, ensure you have:

- ✅ Access to BigQuery project: `savvy-gtm-analytics`
- ✅ V4 model files in `v4/models/v4.0.0/`:
  - `model.pkl` (trained XGBoost model)
  - `model.json` (model configuration)
- ✅ Python environment with required packages:
  ```bash
  pip install xgboost pandas google-cloud-bigquery shap numpy
  ```
- ✅ Working directory: `pipeline/` (this directory)

### Monthly Execution (4 Steps)

```bash
# Step 1: Calculate V4 features for all prospects
# Run SQL: pipeline/sql/v4_prospect_features.sql
# Creates: ml_features.v4_prospect_features

# Step 2: Score prospects with V4 model
cd pipeline
python scripts/score_prospects_monthly.py
# Creates: ml_features.v4_prospect_scores

# Step 3: Generate hybrid lead list
# Run SQL: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
# Creates: ml_features.january_2026_lead_list_v4

# Step 4: Export to CSV
python scripts/export_lead_list.py
# Output: pipeline/exports/january_2026_lead_list_YYYYMMDD.csv
```

**Expected Output**: CSV file with 200 leads per active SGA (e.g., 3,000 leads for 15 SGAs) ready for Salesforce import

---

## Pipeline Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              MONTHLY LEAD LIST GENERATION PIPELINE              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  STEP 1: Calculate V4 Features                                  │
│     └─> SQL: v4_prospect_features.sql                           │
│     └─> Output: ml_features.v4_prospect_features                │
│     └─> Purpose: Calculate 14 ML features for all prospects      │
│                                                                  │
│  STEP 2: Score Prospects with V4 Model                         │
│     └─> Python: score_prospects_monthly.py                      │
│     └─> Output: ml_features.v4_prospect_scores                 │
│     └─> Purpose: Generate ML scores, percentiles, SHAP features │
│                                                                  │
│  STEP 3: Run Hybrid Lead List Query                            │
│     └─> SQL: January_2026_Lead_List_V3_V4_Hybrid.sql            │
│     └─> Output: ml_features.january_2026_lead_list_v4          │
│     └─> Purpose: Combine V3 tiers + V4 upgrades → 200 leads per SGA  │
│                                                                  │
│  STEP 4: Export to CSV                                          │
│     └─> Python: export_lead_list.py                             │
│     └─> Output: exports/january_2026_lead_list_YYYYMMDD.csv    │
│     └─> Purpose: CSV file for Salesforce import                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

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

### Step 1: Calculate V4 Features for All Prospects

**Purpose**: Calculate the 14 features required by the V4 XGBoost model for all producing advisors in FINTRX.

**File**: `pipeline/sql/v4_prospect_features.sql`

**What It Does**:
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

### Step 2: Score Prospects with V4 Model

**Purpose**: Generate ML scores for all prospects using the trained XGBoost model.

**File**: `pipeline/scripts/score_prospects_monthly.py`

**What It Does**:
1. Loads V4 XGBoost model from `v4/models/v4.0.0/model.pkl`
2. Fetches features from `ml_features.v4_prospect_features`
3. Generates predictions (0-1 probability scores)
4. Calculates percentile ranks (1-100)
5. Identifies deprioritize candidates (bottom 20%)
6. Generates SHAP narratives for V4 upgrade candidates (top 20%)
7. Uploads scores to `ml_features.v4_prospect_scores`

**Execution**:
```bash
cd pipeline
python scripts/score_prospects_monthly.py
```

**Output Columns**:
- `crd`: Advisor CRD ID
- `v4_score`: Raw prediction (0-1)
- `v4_percentile`: Percentile rank (1-100)
- `v4_deprioritize`: Boolean (TRUE if percentile ≤ 20)
- `v4_upgrade_candidate`: Boolean (TRUE if percentile ≥ 80)
- `shap_top1_feature`, `shap_top2_feature`, `shap_top3_feature`: Top 3 ML features
- `shap_top1_value`, `shap_top2_value`, `shap_top3_value`: SHAP values
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

### Step 3: Run Hybrid Lead List Query

**Purpose**: Combine V3 tier rules with V4 ML upgrades to generate the final lead list.

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**What It Does**:

1. **Salesforce Matching & Prioritization**:
   - **Checks Salesforce**: Queries `SavvyGTMData.Lead` table to find existing leads by CRD
   - **NEW_PROSPECT**: Leads NOT in Salesforce (preferred - highest priority)
   - **Recyclable Leads**: Leads in Salesforce with 180+ days since last SMS/Call activity
     - Must NOT be in bad status (Closed, Converted, Dead, Unqualified, etc.)
     - Must NOT have DoNotCall = true
   - **Excluded**: Leads in Salesforce that don't meet recyclable criteria (recently contacted, bad status, etc.)
   - **Priority**: NEW_PROSPECT (priority 1) > Recyclable (priority 2)

2. **V3 Tier Assignment**:
   - Applies rules-based tier logic (T1A, T1B, T1, T2, T3, T4, T5, STANDARD)
   - Filters out wirehouses, insurance firms, excluded titles
   - Only processes NEW_PROSPECT or recyclable leads

3. **V4 Integration**:
   - Joins V4 scores from `ml_features.v4_prospect_scores`
   - **Upgrade Path**: STANDARD tier leads with V4 ≥ 80th percentile → upgraded to `V4_UPGRADE` tier
   - Expected conversion: 4.60% for V4 upgrades (1.42x baseline)

3. **Tier Quotas**:
   - T1A: 50 leads
   - T1B: 60 leads
   - T1: 300 leads
   - T1F: 50 leads
   - T2: 1,500 leads
   - T3: 300 leads
   - T4: 300 leads
   - T5: 1,500 leads
   - **V4_UPGRADE: 500 leads** (NEW)

4. **Final Filtering**:
   - Firm diversity cap (max 50 leads per firm)
   - LinkedIn prioritization (prefer leads with LinkedIn)
   - Final limit: 200 leads per active SGA (dynamically calculated)

**Execution**:
```sql
-- Run in BigQuery
-- Creates: ml_features.january_2026_lead_list_v4
-- Expected rows: 200 leads per active SGA (e.g., 3,000 for 15 SGAs)
```

**Validation Queries**:

**1. Tier Distribution**:
```sql
SELECT 
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(v4_percentile), 1) as avg_v4_percentile,
    ROUND(AVG(expected_rate_pct), 2) as avg_expected_conv_pct,
    SUM(CASE WHEN is_v4_upgrade = 1 THEN 1 ELSE 0 END) as v4_upgrades
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY score_tier
ORDER BY 
    CASE score_tier
        WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
        WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
        WHEN 'TIER_1_PRIME_MOVER' THEN 3
        WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
        WHEN 'TIER_2_PROVEN_MOVER' THEN 5
        WHEN 'V4_UPGRADE' THEN 6
        WHEN 'TIER_3_MODERATE_BLEEDER' THEN 7
        WHEN 'TIER_4_EXPERIENCED_MOVER' THEN 8
        WHEN 'TIER_5_HEAVY_BLEEDER' THEN 9
    END;
```

**2. Salesforce Matching Validation**:
```sql
SELECT 
    prospect_type,
    COUNT(*) as lead_count,
    COUNT(DISTINCT salesforce_lead_id) as with_salesforce_id,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY prospect_type;
```

**3. Verify No Data Quality Issues**:
```sql
-- Check: NEW_PROSPECT should NOT have salesforce_lead_id
SELECT 
    COUNT(*) as new_prospects_with_sf_id
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
WHERE prospect_type = 'NEW_PROSPECT' 
  AND salesforce_lead_id IS NOT NULL;
-- Expected: 0 (should be 0)
```

**Expected Results**:
- Total leads: 200 × number of active SGAs (e.g., 3,000 for 15 SGAs)
- V4 upgrades: ~500 leads (20.8%)
- Average V4 percentile: ~75-85 (higher is better)
- Tier distribution: See tier quotas above
- **NEW_PROSPECT**: Typically 80-90% of leads (not in Salesforce)
- **Recyclable**: Typically 10-20% of leads (in Salesforce, 180+ days no contact)
- **NEW_PROSPECT with salesforce_lead_id**: Should be **0** (data quality check)

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

### Step 4: Export to CSV

**Purpose**: Export lead list to CSV format for Salesforce import.

**File**: `pipeline/scripts/export_lead_list.py`

**What It Does**:
1. Fetches lead list from `ml_features.january_2026_lead_list_v4`
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
- `score_tier`: Final tier (V3 tier or V4_UPGRADE)
- `original_v3_tier`: Original V3 tier before upgrade
- `expected_rate_pct`: Expected conversion rate (%)
- `score_narrative`: Human-readable explanation (V3 rules or V4 SHAP)
- `v4_score`: V4 XGBoost score (0-1)
- `v4_percentile`: V4 percentile rank (1-100)
- `is_v4_upgrade`: 1 = V4 upgraded lead, 0 = V3 tier lead
- `v4_status`: Description of V4 status
- `shap_top1_feature`: Most important ML feature driving score
- `shap_top2_feature`: Second most important feature
- `shap_top3_feature`: Third most important feature
- `prospect_type`: NEW_PROSPECT or recyclable
- `sga_owner`: Assigned SGA name (automatically assigned)
- `sga_id`: Assigned SGA Salesforce ID (for matching)
- `list_rank`: Overall ranking in list (1 to total_leads_needed)

**Validation**:
- Row count: 200 × number of active SGAs
- Duplicate CRDs: 0
- Missing required fields: < 1%
- Excluded firms (Savvy, Ritholtz): 0

---

## Model Logic & Methodology

### V3 Rules-Based Model

**Philosophy**: Transparent, explainable business rules that assign leads to priority tiers.

**Tier Definitions**:

| Tier | Criteria | Conversion Rate | Lift |
|------|----------|----------------|------|
| **T1A** | CFP holder + 1-4yr tenure + 5+yr experience + bleeding firm | 16.44% | 4.30x |
| **T1B** | Series 65 only + Tier 1 criteria | 16.48% | 4.31x |
| **T1** | 1-4yr tenure + 5-15yr experience + bleeding firm + small firm | 13.21% | 3.46x |
| **T1F** | High-value wealth title + bleeding firm | 12.78% | 3.35x |
| **T2** | 3+ prior firms + 5+yr experience | 8.59% | 2.50x |
| **T3** | Firm losing 1-10 advisors + 5+yr experience | 9.52% | 2.77x |
| **T4** | 20+yr experience + 1-4yr tenure (recent mover) | 11.54% | 3.35x |
| **T5** | Firm losing 10+ advisors + 5+yr experience | 7.27% | 2.11x |
| **STANDARD** | All other leads | 3.82% | 1.0x |

**Key Design Principles**:
1. **Zero Data Leakage**: All features calculated using Point-in-Time (PIT) methodology
2. **Transparent Rules**: Every tier assignment is explainable
3. **Statistical Validation**: All tiers validated with confidence intervals
4. **Temporal Validation**: Tested on future data (August-October 2025)

---

### V4 XGBoost ML Model

**Philosophy**: Machine learning model that identifies high-potential leads missed by V3 rules.

**Algorithm**: XGBoost (Gradient Boosting)
- **Objective**: Binary classification (logistic)
- **Regularization**: Strong (max_depth=3, min_child_weight=50)
- **Training Period**: 2024-02-01 to 2025-07-31
- **Test Period**: 2025-08-01 to 2025-10-31

**Performance Metrics**:
- **AUC-ROC**: 0.5989
- **AUC-PR**: 0.0432
- **Top Decile Lift**: 1.51x
- **Bottom 20% Conversion**: 1.33% (0.42x lift - deprioritization signal)

**Use Case**: **Upgrade Path** for STANDARD tier leads
- STANDARD leads with V4 ≥ 80th percentile convert at **4.60%** (1.42x baseline)
- Historical validation: 1,174 leads at 4.60% conversion rate
- Expected improvement: +6-12% overall conversion rate

**Why Hybrid Approach?**:
- V3 excels at **prioritization** (identifying top tiers)
- V4 excels at **upgrading STANDARD leads** (finding hidden gems)
- Combined: Best of both worlds

---

## V4 XGBoost Model Features

### Feature Overview

The V4 model uses **14 features** across 6 categories:

1. **Tenure Features** (1 feature)
2. **Experience Features** (2 features)
3. **Mobility Features** (1 feature)
4. **Firm Stability Features** (4 features)
5. **Wirehouse & Broker Protocol** (2 features)
6. **Data Quality Flags** (2 features)
7. **Interaction Features** (2 features)

### Feature Importance Rankings

Based on XGBoost feature importance (gain-based):

| Rank | Feature | Importance | Category | Description |
|------|---------|------------|----------|-------------|
| 1 | `mobility_tier` | 178.85 | Mobility | Career mobility (Stable, Low_Mobility, High_Mobility) |
| 2 | `has_email` | 158.87 | Data Quality | Whether email contact information is available |
| 3 | `tenure_bucket` | 143.16 | Tenure | Tenure at current firm (0-12, 12-24, 24-48, 48-120, 120+, Unknown) |
| 4 | `mobility_x_heavy_bleeding` | 117.26 | Interaction | High mobility AND heavy bleeding firm (powerful signal) |
| 5 | `has_linkedin` | 110.46 | Data Quality | Whether LinkedIn profile is available |
| 6 | `firm_stability_tier` | 101.08 | Firm Stability | Firm stability category (Unknown, Heavy_Bleeding, Light_Bleeding, Stable, Growing) |
| 7 | `is_wirehouse` | 84.76 | Wirehouse | Whether advisor is at a wirehouse firm |
| 8 | `firm_rep_count_at_contact` | 83.30 | Firm Stability | Current number of reps at firm |
| 9 | `short_tenure_x_high_mobility` | 81.95 | Interaction | Short tenure (<24mo) AND high mobility |
| 10 | `firm_net_change_12mo` | 71.99 | Firm Stability | Net change in advisors (arrivals - departures) over 12 months |
| 11 | `is_broker_protocol` | 64.26 | Broker Protocol | Whether firm participates in Broker Protocol |
| 12 | `experience_bucket` | 64.17 | Experience | Industry experience bucket (0-5, 5-10, 10-15, 15-20, 20+) |
| 13 | `has_firm_data` | 55.48 | Firm Stability | Whether firm data is available |
| 14 | `is_experience_missing` | 39.04 | Experience | Whether experience data is missing |

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
| AUC-ROC | 0.5989 | ≥ 0.6 | ⚠️ Warning (0.001 below) |
| AUC-PR | 0.0432 | ≥ 0.1 | ⚠️ Warning (acceptable for deprioritization) |
| Top Decile Lift | 1.51x | ≥ 1.5x | ✅ Passed |
| Statistical Significance | p = 0.0170 | < 0.05 | ✅ Passed |

**Lift by Decile**:

| Decile | Leads | Conversions | Conv Rate | Lift |
|--------|-------|-------------|-----------|------|
| 1 (Bottom) | 600 | 8 | 1.33% | 0.42x |
| 2 | 600 | 7 | 1.17% | 0.36x |
| 3 | 601 | 14 | 2.33% | 0.73x |
| 4 | 600 | 20 | 3.33% | 1.04x |
| 5 | 601 | 21 | 3.49% | 1.09x |
| 6 | 600 | 19 | 3.17% | 0.99x |
| 7 | 600 | 20 | 3.33% | 1.04x |
| 8 | 601 | 30 | 4.99% | 1.56x |
| 9 | 600 | 23 | 3.83% | 1.20x |
| 10 (Top) | 601 | 29 | 4.83% | 1.51x |

**Key Findings**:
- **Bottom 20%** converts at **1.33%** (0.42x lift) - strong deprioritization signal
- **Top 20%** converts at **4.83%** (1.51x lift) - upgrade signal
- **STANDARD tier with V4 ≥ 80%**: 4.60% conversion (1.42x baseline)

---

### Hybrid Approach Validation

**Investigation Findings** (V3 vs V4 Comparison):

| Finding | Evidence | Action |
|---------|----------|--------|
| V3 tier ordering validated | T1 converts at 7.41% vs T2 at 3.20% | ✅ Keep V3 prioritization |
| V4 better at prediction | V4 AUC-ROC (0.6141) > V3 AUC-ROC (0.5095) | ✅ Use V4 for upgrades |
| V4 deprioritization not adding value | 90% of V3 leads scored in top 10% | ❌ Removed deprioritization filter |
| STANDARD + V4 ≥ 80% converts at 4.60% | 1,174 historical leads validated | ✅ Added upgrade path |

**Hybrid Strategy**:
- **V3 Rules**: Primary prioritization (T1-T5 tiers)
- **V4 ML**: Upgrade path for STANDARD tier leads (V4 ≥ 80th percentile)
- **Expected Improvement**: +6-12% overall conversion rate

**Validation Results**:
- V4 upgrades: 500 leads at 4.60% conversion (vs 3.82% STANDARD baseline)
- Expected additional conversions: ~4 conversions per month
- Efficiency gain: No additional SDR effort (same 200 leads per SGA)

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "No v4_prospect_scores found" | Step 2 not completed | Run `score_prospects_monthly.py` first |
| Low V4 percentile average | V4 scores not joined | Check JOIN in `v4_enriched` CTE |
| Too few leads (< 200 per SGA) | Tier quotas too restrictive or insufficient prospects | Check tier distribution, verify SGA count, check prospect pool |
| Duplicate CRDs | JOIN issue | Add DISTINCT or fix JOIN logic |
| Missing features | Column name mismatch | Check feature names in `final_features.json` |
| SHAP calculation fails | Memory or model issues | Use feature importance fallback (already implemented) |

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
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
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
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
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
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
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
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
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
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
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
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`;
```

**Expected Results**:
- `new_prospects_with_sf_id` should be **0** (NEW_PROSPECT should not have salesforce_lead_id)
- `recyclable_leads` should have `salesforce_lead_id` populated
- Most leads should be `NEW_PROSPECT` (typically 80-90%)

---

## Appendix

### File Structure

```
lead_scoring_production/
├── pipeline/                          # Main pipeline directory
│   ├── sql/
│   │   ├── v4_prospect_features.sql   # Step 1: Feature calculation
│   │   └── January_2026_Lead_List_V3_V4_Hybrid.sql  # Step 3: Hybrid query
│   ├── scripts/
│   │   ├── score_prospects_monthly.py # Step 2: ML scoring
│   │   └── export_lead_list.py        # Step 4: CSV export
│   ├── exports/                       # CSV output files
│   ├── logs/                          # Execution logs
│   └── config/                        # Configuration files
├── v3/                                # V3 rules-based model
│   ├── models/
│   ├── scripts/
│   └── reports/
├── v4/                                # V4 XGBoost ML model
│   ├── models/v4.0.0/
│   │   ├── model.pkl                  # Trained model
│   │   ├── model.json                 # Model config
│   │   └── feature_importance.csv     # Feature importance
│   ├── data/processed/
│   │   └── final_features.json        # Feature list
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
| `ml_features.v4_prospect_features` | V4 features for all prospects | Step 1 SQL |
| `ml_features.v4_prospect_scores` | V4 scores with percentiles | Step 2 Python |
| `ml_features.january_2026_lead_list_v4` | Final lead list | Step 3 SQL |

### Key Metrics Reference

| Metric | Value | Source |
|--------|-------|--------|
| Baseline conversion rate | 3.20% | Historical data |
| V3 T1A conversion rate | 16.44% | V3 validation |
| V3 T1B conversion rate | 16.48% | V3 validation |
| V4 upgrade conversion rate | 4.60% | V4 validation |
| Target leads per month | 2,400 | Business requirement |
| V4 upgrade quota | 500 leads | Hybrid strategy |

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
- [ ] Created ml_features.[month]_2026_lead_list_v4
- [ ] Lead count: ___________
- [ ] Tier distribution validated

### Step 4: Export
- [ ] Final validation passed
- [ ] Exported to CSV
- [ ] File location: ___________

### Summary
- **Total Leads**: ___________ (should be 200 × number of active SGAs)
- **Leads per SGA**: ___________ (should be exactly 200)
- **Number of Active SGAs**: ___________
- **V4 Upgrades**: ___________ (should be ~500)
- **Avg V4 Percentile**: ___________
- **New Prospects**: ___________
- **Recyclable Leads**: ___________
```

---

## References

- **V3 Model Report**: `v3/VERSION_3_MODEL_REPORT.md`
- **V4 Model Report**: `v4/VERSION_4_MODEL_REPORT.md`
- **Architecture Overview**: `docs/FINTRX_Architecture_Overview.md`
- **Feature Documentation**: `docs/FINTRX_Lead_Scoring_Features.md`
- **Validation Findings**: `validation/LEAD_SCORING_KEY_FINDINGS.md`
- **Monthly Generation Guide**: `pipeline/Monthly_Lead_List_Generation_V3_V4_Hybrid.md`

---

**Document Version**: 2.0  
**Last Updated**: December 2025  
**Maintainer**: Data Science Team  
**Questions?**: Contact the Data Science team

