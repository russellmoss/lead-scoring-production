# Monthly Lead List Generation: V3 + V4 Hybrid Approach

**Version**: 1.0  
**Created**: 2025-12-24  
**Purpose**: Generate monthly lead lists using V3 tier prioritization + V4 XGBoost deprioritization  
**Expected Outcome**: 2,400 leads with bottom 20% (by V4 score) filtered out, saving ~12% SDR effort

---

## ⚠️ IMPORTANT: Working Directory Configuration

**ALL WORK MUST BE DONE FROM THIS DIRECTORY:**
```
C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation
```

**Directory Structure (Cursor.ai should create if not exists):**
```
Lead_List_Generation/
├── sql/                          # SQL scripts
│   ├── v4_prospect_features.sql
│   ├── January_2026_Lead_List_V3_V4_Hybrid.sql
│   └── validation_queries.sql
├── scripts/                      # Python scripts
│   ├── score_prospects_monthly.py
│   └── export_lead_list.py
├── exports/                      # CSV exports for Salesforce
│   └── january_2026_lead_list_YYYYMMDD.csv
├── logs/                         # Execution logs
│   └── EXECUTION_LOG.md
└── config/                       # Configuration files
    └── paths.py
```

**V4 Model Files Location (READ ONLY - do not modify):**
```
C:\Users\russe\Documents\Lead Scoring\Version-4\models\v4.0.0\
├── model.pkl
├── model.json
└── feature_importance.csv

C:\Users\russe\Documents\Lead Scoring\Version-4\data\processed\
└── final_features.json
```

**Cursor.ai Instructions:**
1. Always `cd` to `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation` before running commands
2. Create all new files in the Lead_List_Generation directory
3. Reference V4 model files from Version-4 directory (read-only)
4. Log all actions to `logs/EXECUTION_LOG.md`

---

## Executive Summary

This guide creates a **repeatable monthly process** to generate lead lists that combine:
- **V3 Rules**: Tier assignment (T1A, T1B, T1, T2, T3, T4, T5) with 1.74x top decile lift
- **V4 XGBoost**: Deprioritization filter that removes bottom 20% (0.42x conversion rate)

**Monthly Time Estimate**: 15-20 minutes once pipeline is set up

---

## Prerequisites

Before starting, ensure you have:
- [ ] Access to BigQuery project: `savvy-gtm-analytics`
- [ ] V4 model files in `Version-4/models/v4.0.0/`
- [ ] Python environment with `xgboost`, `pandas`, `google-cloud-bigquery`
- [ ] Cursor.ai with MCP connection to BigQuery

---

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MONTHLY LEAD LIST PIPELINE                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  STEP 1: Calculate V4 Features for All Prospects                    │
│     └─> Creates: ml_features.v4_prospect_features                   │
│                                                                      │
│  STEP 2: Score Prospects with V4 Model                              │
│     └─> Creates: ml_features.v4_prospect_scores                     │
│                                                                      │
│  STEP 3: Run V3 + V4 Hybrid Lead List Query                         │
│     └─> Creates: ml_features.{month}_2026_lead_list                 │
│                                                                      │
│  STEP 4: Validate and Export                                        │
│     └─> Output: CSV file for Salesforce import                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## STEP 1: Calculate V4 Features for All Prospects

### Cursor Prompt 1.1: Create V4 Feature Table

```
@workspace Create a BigQuery table with V4 model features for all FINTRX prospects.

IMPORTANT - WORKING DIRECTORY:
- All work from: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation
- Save SQL to: Lead_List_Generation/sql/v4_prospect_features.sql
- Log to: Lead_List_Generation/logs/EXECUTION_LOG.md

Context:
- V4 model uses 14 features (see C:\Users\russe\Documents\Lead Scoring\Version-4\data\processed\final_features.json)
- Features must be PIT-compliant (using CURRENT_DATE() as prediction date)
- Source tables: ria_contacts_current, contact_registered_employment_history
- Target BigQuery table: ml_features.v4_prospect_features

Task:
1. Create the sql/ directory if it doesn't exist
2. Create SQL file at sql/v4_prospect_features.sql
3. Run it via MCP to create the table in BigQuery
4. Run validation query and log results to logs/EXECUTION_LOG.md with:
   - Total prospects
   - Feature coverage percentages
   - Any anomalies detected
5. Confirm table created successfully

Features needed:
- tenure_bucket (categorical: 0-12, 12-24, 24-48, 48-120, 120+, Unknown)
- experience_bucket (categorical)
- is_experience_missing (boolean)
- mobility_tier (categorical: Stable, Low_Mobility, High_Mobility)
- firm_rep_count_at_contact (integer)
- firm_net_change_12mo (integer)
- firm_stability_tier (categorical)
- has_firm_data (boolean)
- is_wirehouse (boolean)
- is_broker_protocol (boolean)
- has_email (boolean)
- has_linkedin (boolean)
- mobility_x_heavy_bleeding (boolean interaction)
- short_tenure_x_high_mobility (boolean interaction)

Reference: C:\Users\russe\Documents\Lead Scoring\Version-4\sql\phase_2_feature_engineering.sql for feature logic
```

### SQL Template for Step 1

```sql
-- ============================================================================
-- V4 PROSPECT FEATURES TABLE
-- Creates features for all prospects to enable V4 scoring
-- Run monthly BEFORE lead list generation
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_prospect_features` AS

WITH 
-- Base prospects from FINTRX
base_prospects AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        c.PRIMARY_FIRM as firm_crd,
        c.PRIMARY_FIRM_NAME as firm_name,
        c.PRIMARY_FIRM_START_DATE as firm_start_date,
        c.EMAIL,
        c.LINKEDIN_PROFILE_URL,
        CURRENT_DATE() as prediction_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    WHERE c.RIA_CONTACT_CRD_ID IS NOT NULL
      AND c.PRODUCING_ADVISOR = TRUE
),

-- Tenure calculation (from ria_contacts_current)
tenure_calc AS (
    SELECT 
        crd,
        DATE_DIFF(prediction_date, firm_start_date, MONTH) as tenure_months,
        CASE 
            WHEN firm_start_date IS NULL THEN 'Unknown'
            WHEN DATE_DIFF(prediction_date, firm_start_date, MONTH) <= 12 THEN '0-12'
            WHEN DATE_DIFF(prediction_date, firm_start_date, MONTH) <= 24 THEN '12-24'
            WHEN DATE_DIFF(prediction_date, firm_start_date, MONTH) <= 48 THEN '24-48'
            WHEN DATE_DIFF(prediction_date, firm_start_date, MONTH) <= 120 THEN '48-120'
            ELSE '120+'
        END as tenure_bucket
    FROM base_prospects
),

-- Industry experience from employment history
experience_calc AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        DATE_DIFF(CURRENT_DATE(), MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE), YEAR) as experience_years
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    GROUP BY RIA_CONTACT_CRD_ID
),

-- Mobility (moves in last 3 years)
mobility_calc AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        COUNT(DISTINCT CASE 
            WHEN PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 YEAR)
            THEN PREVIOUS_REGISTRATION_COMPANY_CRD_ID 
        END) as moves_3yr
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    GROUP BY RIA_CONTACT_CRD_ID
),

-- Firm headcount
firm_headcount AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_reps
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY PRIMARY_FIRM
),

-- Firm departures (12 months)
firm_departures AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),

-- Firm arrivals (12 months)
firm_arrivals AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),

-- Firm metrics combined
firm_metrics AS (
    SELECT
        h.firm_crd,
        h.current_reps as firm_rep_count,
        COALESCE(d.departures_12mo, 0) as departures_12mo,
        COALESCE(a.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(a.arrivals_12mo, 0) - COALESCE(d.departures_12mo, 0) as firm_net_change_12mo,
        CASE 
            WHEN h.current_reps IS NULL THEN 'Unknown'
            WHEN COALESCE(d.departures_12mo, 0) >= 10 THEN 'Heavy_Bleeding'
            WHEN COALESCE(d.departures_12mo, 0) >= 1 THEN 'Light_Bleeding'
            WHEN COALESCE(a.arrivals_12mo, 0) > COALESCE(d.departures_12mo, 0) THEN 'Growing'
            ELSE 'Stable'
        END as firm_stability_tier
    FROM firm_headcount h
    LEFT JOIN firm_departures d ON h.firm_crd = d.firm_crd
    LEFT JOIN firm_arrivals a ON h.firm_crd = a.firm_crd
),

-- Wirehouse detection
wirehouse_patterns AS (
    SELECT firm_pattern FROM UNNEST([
        '%MORGAN STANLEY%', '%MERRILL%', '%WELLS FARGO%', '%UBS %', 
        '%EDWARD JONES%', '%AMERIPRISE%', '%RAYMOND JAMES%'
    ]) as firm_pattern
),

-- Broker protocol members
broker_protocol AS (
    SELECT DISTINCT firm_crd
    FROM `savvy-gtm-analytics.ml_features.broker_protocol_members`
)

-- Final feature assembly
SELECT 
    bp.crd,
    bp.firm_crd,
    bp.prediction_date,
    
    -- Tenure features
    COALESCE(tc.tenure_bucket, 'Unknown') as tenure_bucket,
    
    -- Experience features
    CASE 
        WHEN ec.experience_years IS NULL THEN 'Unknown'
        WHEN ec.experience_years < 5 THEN '0-5'
        WHEN ec.experience_years < 10 THEN '5-10'
        WHEN ec.experience_years < 15 THEN '10-15'
        WHEN ec.experience_years < 20 THEN '15-20'
        ELSE '20+'
    END as experience_bucket,
    CASE WHEN ec.experience_years IS NULL THEN 1 ELSE 0 END as is_experience_missing,
    
    -- Mobility features
    CASE 
        WHEN COALESCE(mc.moves_3yr, 0) = 0 THEN 'Stable'
        WHEN COALESCE(mc.moves_3yr, 0) <= 2 THEN 'Low_Mobility'
        ELSE 'High_Mobility'
    END as mobility_tier,
    
    -- Firm features
    COALESCE(fm.firm_rep_count, 0) as firm_rep_count_at_contact,
    COALESCE(fm.firm_net_change_12mo, 0) as firm_net_change_12mo,
    COALESCE(fm.firm_stability_tier, 'Unknown') as firm_stability_tier,
    CASE WHEN fm.firm_crd IS NOT NULL THEN 1 ELSE 0 END as has_firm_data,
    
    -- Wirehouse flag
    CASE WHEN EXISTS (
        SELECT 1 FROM wirehouse_patterns wp 
        WHERE UPPER(bp.firm_name) LIKE wp.firm_pattern
    ) THEN 1 ELSE 0 END as is_wirehouse,
    
    -- Broker protocol flag
    CASE WHEN bpm.firm_crd IS NOT NULL THEN 1 ELSE 0 END as is_broker_protocol,
    
    -- Data quality flags
    CASE WHEN bp.EMAIL IS NOT NULL AND bp.EMAIL != '' THEN 1 ELSE 0 END as has_email,
    CASE WHEN bp.LINKEDIN_PROFILE_URL IS NOT NULL AND bp.LINKEDIN_PROFILE_URL != '' THEN 1 ELSE 0 END as has_linkedin,
    
    -- Interaction features
    CASE 
        WHEN COALESCE(mc.moves_3yr, 0) >= 3 AND COALESCE(fm.firm_stability_tier, 'Unknown') = 'Heavy_Bleeding' 
        THEN 1 ELSE 0 
    END as mobility_x_heavy_bleeding,
    
    CASE 
        WHEN tc.tenure_bucket IN ('0-12', '12-24') AND COALESCE(mc.moves_3yr, 0) >= 3 
        THEN 1 ELSE 0 
    END as short_tenure_x_high_mobility,
    
    -- Metadata
    CURRENT_TIMESTAMP() as created_at

FROM base_prospects bp
LEFT JOIN tenure_calc tc ON bp.crd = tc.crd
LEFT JOIN experience_calc ec ON bp.crd = ec.crd
LEFT JOIN mobility_calc mc ON bp.crd = mc.crd
LEFT JOIN firm_metrics fm ON SAFE_CAST(bp.firm_crd AS INT64) = fm.firm_crd
LEFT JOIN broker_protocol bpm ON SAFE_CAST(bp.firm_crd AS INT64) = bpm.firm_crd;
```

### Validation Query for Step 1

```sql
-- Run after Step 1 to validate
SELECT 
    'Total Prospects' as metric,
    COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`

UNION ALL

SELECT 
    'With Known Tenure' as metric,
    COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`
WHERE tenure_bucket != 'Unknown'

UNION ALL

SELECT 
    'High Mobility' as metric,
    COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`
WHERE mobility_tier = 'High_Mobility'

UNION ALL

SELECT 
    'Heavy Bleeding Firms' as metric,
    COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`
WHERE firm_stability_tier = 'Heavy_Bleeding'

UNION ALL

SELECT 
    'Interaction: mobility_x_heavy_bleeding' as metric,
    SUM(mobility_x_heavy_bleeding) as value
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`;
```

### Cursor Prompt 1.2: Run and Validate

```
@workspace Run the V4 feature table creation SQL via MCP BigQuery connection.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Task:
1. Execute the SQL in Lead_List_Generation/sql/v4_prospect_features.sql via MCP
2. Run the validation query
3. Log results to Lead_List_Generation/logs/EXECUTION_LOG.md with:
   - Timestamp
   - Total prospects created
   - Feature coverage percentages
   - Any anomalies detected
4. Confirm table ml_features.v4_prospect_features created successfully
```

---

## STEP 2: Score Prospects with V4 Model

### Cursor Prompt 2.1: Score All Prospects

```
@workspace Score all prospects in v4_prospect_features using the V4 XGBoost model.

IMPORTANT - PATHS:
- Working directory: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation
- V4 model (READ ONLY): C:\Users\russe\Documents\Lead Scoring\Version-4\models\v4.0.0\model.pkl
- V4 features (READ ONLY): C:\Users\russe\Documents\Lead Scoring\Version-4\data\processed\final_features.json
- Output script: Lead_List_Generation/scripts/score_prospects_monthly.py
- Log file: Lead_List_Generation/logs/EXECUTION_LOG.md

Context:
- Model location: Version-4/models/v4.0.0/model.pkl
- Features: Version-4/data/processed/final_features.json
- Reference inference class: Version-4/inference/lead_scorer_v4.py

Task:
1. Create scripts/ directory if it doesn't exist
2. Create score_prospects_monthly.py in Lead_List_Generation/scripts/
3. Run the script to:
   - Load features from BigQuery table ml_features.v4_prospect_features
   - Score using the V4 XGBoost model
   - Calculate percentiles (1-100)
   - Set deprioritize flag for bottom 20%
   - Write results back to BigQuery as ml_features.v4_prospect_scores
4. Log results to Lead_List_Generation/logs/EXECUTION_LOG.md

Output columns:
- crd (INT64)
- v4_score (FLOAT64, 0-1)
- v4_percentile (INT64, 1-100)
- v4_deprioritize (BOOLEAN, TRUE if percentile <= 20)
- scored_at (TIMESTAMP)
```

### Python Script for Step 2

Save this file to: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation\scripts\score_prospects_monthly.py`

```python
"""
Score all prospects with V4 model and upload to BigQuery.
Run monthly BEFORE lead list generation.

Working Directory: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation
Usage: python scripts/score_prospects_monthly.py
"""

import pandas as pd
import numpy as np
from pathlib import Path
from google.cloud import bigquery
import pickle
import json
from datetime import datetime

# ============================================================================
# PATH CONFIGURATION
# ============================================================================
# Working directory (where this script runs from)
WORKING_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation")

# V4 Model files (read-only, from Version-4)
V4_MODEL_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4\models\v4.0.0")
V4_FEATURES_FILE = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4\data\processed\final_features.json")

# Output directories (in Lead_List_Generation)
EXPORTS_DIR = WORKING_DIR / "exports"
LOGS_DIR = WORKING_DIR / "logs"

# Ensure output directories exist
EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
LOGS_DIR.mkdir(parents=True, exist_ok=True)

# ============================================================================
# BIGQUERY CONFIGURATION
# ============================================================================
PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
FEATURES_TABLE = "v4_prospect_features"
SCORES_TABLE = "v4_prospect_scores"

# Deprioritization threshold
DEPRIORITIZE_PERCENTILE = 20

def load_model():
    """Load the V4 XGBoost model from Version-4 directory."""
    model_path = V4_MODEL_DIR / "model.pkl"
    with open(model_path, 'rb') as f:
        model = pickle.load(f)
    print(f"[INFO] Loaded model from {model_path}")
    return model

def load_features_list():
    """Load the final feature list from Version-4 directory."""
    with open(V4_FEATURES_FILE, 'r') as f:
        data = json.load(f)
    features = data['final_features']
    print(f"[INFO] Loaded {len(features)} features")
    return features

def fetch_prospect_features(client):
    """Fetch prospect features from BigQuery."""
    query = f"""
    SELECT *
    FROM `{PROJECT_ID}.{DATASET}.{FEATURES_TABLE}`
    """
    print(f"[INFO] Fetching features from {FEATURES_TABLE}...")
    df = client.query(query).to_dataframe()
    print(f"[INFO] Loaded {len(df):,} prospects")
    return df

def prepare_features(df, feature_list):
    """Prepare features for model inference."""
    X = df.copy()
    
    # Select only required features
    missing = set(feature_list) - set(X.columns)
    if missing:
        raise ValueError(f"Missing features: {missing}")
    
    X = X[feature_list].copy()
    
    # Encode categoricals
    categorical_cols = ['tenure_bucket', 'experience_bucket', 'mobility_tier', 'firm_stability_tier']
    for col in categorical_cols:
        if col in X.columns:
            X[col] = X[col].astype('category').cat.codes.replace(-1, 0)
    
    # Fill NaN
    X = X.fillna(0)
    
    return X

def score_prospects(model, X):
    """Generate V4 scores."""
    import xgboost as xgb
    dmatrix = xgb.DMatrix(X)
    scores = model.predict(dmatrix)
    print(f"[INFO] Scored {len(scores):,} prospects")
    print(f"[INFO] Score range: {scores.min():.4f} - {scores.max():.4f}")
    return scores

def calculate_percentiles(scores):
    """Calculate percentile ranks (1-100)."""
    percentiles = pd.Series(scores).rank(pct=True, method='min') * 100
    return percentiles.astype(int).values

def upload_scores(client, df_scores):
    """Upload scores to BigQuery."""
    table_id = f"{PROJECT_ID}.{DATASET}.{SCORES_TABLE}"
    
    # Configure job
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        schema=[
            bigquery.SchemaField("crd", "INT64"),
            bigquery.SchemaField("v4_score", "FLOAT64"),
            bigquery.SchemaField("v4_percentile", "INT64"),
            bigquery.SchemaField("v4_deprioritize", "BOOLEAN"),
            bigquery.SchemaField("scored_at", "TIMESTAMP"),
        ]
    )
    
    job = client.load_table_from_dataframe(df_scores, table_id, job_config=job_config)
    job.result()
    print(f"[INFO] Uploaded {len(df_scores):,} scores to {table_id}")

def main():
    print("=" * 70)
    print("V4 MONTHLY PROSPECT SCORING")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Working Directory: {WORKING_DIR}")
    print("=" * 70)
    
    # Initialize
    client = bigquery.Client(project=PROJECT_ID)
    model = load_model()
    feature_list = load_features_list()
    
    # Fetch features
    df = fetch_prospect_features(client)
    
    # Prepare and score
    X = prepare_features(df, feature_list)
    scores = score_prospects(model, X)
    
    # Calculate percentiles
    percentiles = calculate_percentiles(scores)
    
    # Build output DataFrame
    df_scores = pd.DataFrame({
        'crd': df['crd'].astype(int),
        'v4_score': scores,
        'v4_percentile': percentiles,
        'v4_deprioritize': percentiles <= DEPRIORITIZE_PERCENTILE,
        'scored_at': datetime.now()
    })
    
    # Upload to BigQuery
    upload_scores(client, df_scores)
    
    # Summary
    summary = f"""
{"=" * 70}
SCORING SUMMARY
{"=" * 70}
Total prospects scored: {len(df_scores):,}
Deprioritize (bottom {DEPRIORITIZE_PERCENTILE}%): {df_scores['v4_deprioritize'].sum():,}
Prioritize (top {100-DEPRIORITIZE_PERCENTILE}%): {(~df_scores['v4_deprioritize']).sum():,}
{"=" * 70}
"""
    print(summary)
    
    # Log to file
    log_file = LOGS_DIR / "EXECUTION_LOG.md"
    with open(log_file, 'a') as f:
        f.write(f"\n## V4 Scoring - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"- Total scored: {len(df_scores):,}\n")
        f.write(f"- Deprioritize: {df_scores['v4_deprioritize'].sum():,}\n")
        f.write(f"- Prioritize: {(~df_scores['v4_deprioritize']).sum():,}\n")
    print(f"[INFO] Logged to {log_file}")
    
    return df_scores

if __name__ == "__main__":
    main()
```

### Cursor Prompt 2.2: Run and Validate Scoring

```
@workspace Run the V4 scoring script and validate results.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Task:
1. Run Lead_List_Generation/scripts/score_prospects_monthly.py
2. Validate scores in BigQuery via MCP:
   - Check score distribution (should be 0-1)
   - Check percentile distribution (should be uniform 1-100)
   - Verify deprioritize flags (20% should be TRUE)
3. Log results to Lead_List_Generation/logs/EXECUTION_LOG.md
```

### Validation Query for Step 2

```sql
-- Validate V4 scores
SELECT 
    'Total Scored' as metric,
    COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`

UNION ALL

SELECT 
    'Deprioritize (bottom 20%)' as metric,
    COUNT(*) as value
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
WHERE v4_deprioritize = TRUE

UNION ALL

SELECT 
    'Avg V4 Score' as metric,
    ROUND(AVG(v4_score), 4) as value
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`

UNION ALL

SELECT 
    'Score Range: Min' as metric,
    ROUND(MIN(v4_score), 4) as value
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`

UNION ALL

SELECT 
    'Score Range: Max' as metric,
    ROUND(MAX(v4_score), 4) as value
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`;
```

---

## STEP 3: Run V3 + V4 Hybrid Lead List Query

### Cursor Prompt 3.1: Create Hybrid Query

```
@workspace Create the January 2026 lead list query with V4 deprioritization.

IMPORTANT - PATHS:
- Working directory: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation
- Base V3 query: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation\sql\January_2026_Lead_List_Query_V3_2.sql
- Output SQL: Lead_List_Generation/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
- Log: Lead_List_Generation/logs/EXECUTION_LOG.md

Context:
- V4 scores table: ml_features.v4_prospect_scores
- Goal: Skip prospects where v4_deprioritize = TRUE (bottom 20%)

Task:
1. Copy the V3.2 query to Lead_List_Generation/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
2. Add a new CTE "v4_enriched" that joins v4_prospect_scores after enriched_prospects
3. Modify scored_prospects to use v4_enriched instead of enriched_prospects
4. Add filter in diversity_filtered CTE: AND v4_deprioritize = FALSE
5. Add v4_percentile DESC to ORDER BY clauses for tie-breaking
6. Add V4 columns to final output: v4_score, v4_percentile, v4_status
7. Update header comments to reflect V4 integration
8. Log changes to EXECUTION_LOG.md

Key changes:
- New CTE: v4_enriched (joins v4_prospect_scores on crd)
- Filter: AND v4_deprioritize = FALSE in diversity_filtered
- Output: v4_score, v4_percentile columns
- Keep all other V3.2 logic unchanged
```

### Hybrid Query Modifications

Add these changes to the V3.2 query:

```sql
-- ============================================================================
-- JANUARY 2026 LEAD LIST GENERATOR (V3.2.5 + V4 DEPRIORITIZATION)
-- Model: V3.2.5 + V4 XGBoost Hybrid
-- 
-- V4 INTEGRATION:
-- - Joins V4 prospect scores (ml_features.v4_prospect_scores)
-- - Filters out bottom 20% by V4 score (v4_deprioritize = TRUE)
-- - Expected efficiency gain: ~12% (skip 20% of leads, lose only 8% conversions)
-- ============================================================================

-- ... (keep all existing CTEs through enriched_prospects) ...

-- ============================================================================
-- J2. JOIN V4 SCORES (NEW!)
-- ============================================================================
v4_enriched AS (
    SELECT 
        ep.*,
        COALESCE(v4.v4_score, 0.5) as v4_score,
        COALESCE(v4.v4_percentile, 50) as v4_percentile,
        COALESCE(v4.v4_deprioritize, FALSE) as v4_deprioritize
    FROM enriched_prospects ep
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 
        ON ep.crd = v4.crd
),

-- ============================================================================
-- K. APPLY V3.2 TIER LOGIC (MODIFIED: use v4_enriched instead of enriched_prospects)
-- ============================================================================
scored_prospects AS (
    SELECT 
        ep.*,
        -- ... (keep all existing tier logic, just change FROM enriched_prospects to FROM v4_enriched) ...
    FROM v4_enriched ep  -- CHANGED from enriched_prospects
),

-- ... (keep ranked_prospects unchanged) ...

-- ============================================================================
-- M. APPLY FIRM DIVERSITY CAP + V4 FILTER (MODIFIED!)
-- ============================================================================
diversity_filtered AS (
    SELECT * FROM ranked_prospects
    WHERE rank_within_firm <= 50 
      AND source_priority < 99
      AND v4_deprioritize = FALSE  -- NEW: Skip V4 bottom 20%
),

-- ... (keep rest of query unchanged) ...

-- ============================================================================
-- P. FINAL OUTPUT (Add V4 columns)
-- ============================================================================
SELECT 
    -- ... (keep all existing columns) ...
    
    -- V4 Score columns (NEW!)
    v4_score,
    v4_percentile,
    v4_deprioritize,
    
    -- ... (keep rest of columns) ...
```

### Complete Modified Section (diversity_filtered and output)

```sql
-- ============================================================================
-- M. APPLY FIRM DIVERSITY CAP + V4 DEPRIORITIZATION
-- ============================================================================
diversity_filtered AS (
    SELECT * FROM ranked_prospects
    WHERE rank_within_firm <= 50 
      AND source_priority < 99
      AND v4_deprioritize = FALSE  -- V4: Skip bottom 20% by XGBoost score
),
```

Add to final SELECT:

```sql
-- ============================================================================
-- P. FINAL OUTPUT (Apply LinkedIn Cap + V4 Columns)
-- ============================================================================
SELECT 
    crd as advisor_crd,
    existing_lead_id as salesforce_lead_id,
    first_name,
    last_name,
    email,
    phone,
    linkedin_url,
    has_linkedin,
    fintrx_title,
    producing_advisor,
    firm_name,
    firm_crd,
    firm_rep_count,
    firm_net_change_12mo,
    firm_arrivals_12mo,
    firm_departures_12mo,
    ROUND(firm_turnover_pct, 1) as firm_turnover_pct,
    tenure_months,
    tenure_years,
    industry_tenure_years,
    num_prior_firms,
    moves_3yr,
    score_tier,
    tier_qualification_path,
    priority_rank,
    expected_conversion_rate,
    ROUND(expected_conversion_rate * 100, 2) as expected_rate_pct,
    score_narrative,
    has_cfp,
    has_series_65_only,
    has_series_7,
    has_cfa,
    is_hv_wealth_title,
    prospect_type,
    CASE 
        WHEN prospect_type = 'NEW_PROSPECT' THEN 'New - Not in Salesforce'
        ELSE 'Recyclable - 180+ days no contact'
    END as lead_source_description,
    
    -- V4 Score columns (NEW!)
    ROUND(v4_score, 4) as v4_score,
    v4_percentile,
    'Not Deprioritized' as v4_status,  -- All included leads passed V4 filter
    
    overall_rank as list_rank,
    CURRENT_TIMESTAMP() as generated_at

FROM linkedin_prioritized
WHERE 
    has_linkedin = 1 
    OR (has_linkedin = 0 AND no_linkedin_rank <= 240)
ORDER BY 
    overall_rank
LIMIT 2400;
```

### Cursor Prompt 3.2: Run Hybrid Query

```
@workspace Run the V3 + V4 hybrid lead list query for January 2026.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Task:
1. Execute Lead_List_Generation/sql/January_2026_Lead_List_V3_V4_Hybrid.sql via MCP BigQuery
2. Create table: ml_features.january_2026_lead_list_v4
3. Run validation queries (see below)
4. Log results to Lead_List_Generation/logs/EXECUTION_LOG.md with:
   - Timestamp
   - Total leads generated
   - Tier distribution
   - V4 score distribution (avg percentile)
   - Leads filtered by V4 (count, if trackable)
```

### Validation Query for Step 3

```sql
-- Validate January 2026 lead list (V3 + V4 hybrid)

-- 1. Total leads and tier distribution
SELECT 
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(v4_percentile), 1) as avg_v4_percentile,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_conv
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY score_tier
ORDER BY 
    CASE score_tier
        WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
        WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
        WHEN 'TIER_1_PRIME_MOVER' THEN 3
        WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
        WHEN 'TIER_2_PROVEN_MOVER' THEN 5
        WHEN 'TIER_3_MODERATE_BLEEDER' THEN 6
        WHEN 'TIER_4_EXPERIENCED_MOVER' THEN 7
        WHEN 'TIER_5_HEAVY_BLEEDER' THEN 8
    END;

-- 2. V4 score distribution
SELECT 
    CASE 
        WHEN v4_percentile >= 80 THEN 'Top 20%'
        WHEN v4_percentile >= 50 THEN 'Middle 30-80%'
        ELSE 'Bottom 50%'
    END as v4_tier,
    COUNT(*) as leads,
    ROUND(AVG(v4_score), 4) as avg_score
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY 1
ORDER BY 1;

-- 3. LinkedIn coverage
SELECT 
    has_linkedin,
    COUNT(*) as leads,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY 1;

-- 4. Prospect type distribution
SELECT 
    prospect_type,
    COUNT(*) as leads
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY 1;
```

---

## STEP 4: Validate and Export

### Cursor Prompt 4.1: Final Validation

```
@workspace Validate the January 2026 lead list and prepare for export.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation
EXPORT TO: Lead_List_Generation/exports/
LOG TO: Lead_List_Generation/logs/EXECUTION_LOG.md

Task:
1. Run all validation queries via MCP BigQuery
2. Compare to previous month (if exists):
   - Lead count
   - Tier distribution
   - V4 score distribution
3. Check for data quality issues:
   - Duplicate CRDs
   - Missing required fields
   - Invalid email formats
4. Create export script at Lead_List_Generation/scripts/export_lead_list.py
5. Export to CSV at Lead_List_Generation/exports/january_2026_lead_list_YYYYMMDD.csv
6. Log final summary to Lead_List_Generation/logs/EXECUTION_LOG.md with:
   - Total leads exported
   - Export file path
   - Any data quality issues found
```

### Final Validation Queries

```sql
-- ============================================================================
-- FINAL VALIDATION SUITE
-- ============================================================================

-- 1. Check for duplicates
SELECT 
    'Duplicate CRDs' as check_name,
    COUNT(*) - COUNT(DISTINCT advisor_crd) as duplicates
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`;

-- 2. Required fields completeness
SELECT 
    'Missing First Name' as field,
    SUM(CASE WHEN first_name IS NULL OR first_name = '' THEN 1 ELSE 0 END) as missing_count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
UNION ALL
SELECT 'Missing Last Name', SUM(CASE WHEN last_name IS NULL OR last_name = '' THEN 1 ELSE 0 END)
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
UNION ALL
SELECT 'Missing Email', SUM(CASE WHEN email IS NULL OR email = '' THEN 1 ELSE 0 END)
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
UNION ALL
SELECT 'Missing Firm Name', SUM(CASE WHEN firm_name IS NULL OR firm_name = '' THEN 1 ELSE 0 END)
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`;

-- 3. Summary statistics
SELECT 
    COUNT(*) as total_leads,
    COUNT(DISTINCT firm_crd) as unique_firms,
    ROUND(AVG(v4_percentile), 1) as avg_v4_percentile,
    MIN(v4_percentile) as min_v4_percentile,
    MAX(v4_percentile) as max_v4_percentile,
    SUM(CASE WHEN has_linkedin = 1 THEN 1 ELSE 0 END) as with_linkedin,
    SUM(CASE WHEN prospect_type = 'NEW_PROSPECT' THEN 1 ELSE 0 END) as new_prospects
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`;
```

### Export Script

Save this file to: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation\scripts\export_lead_list.py`

```python
"""
Export lead list to CSV for Salesforce import.

Working Directory: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation
Usage: python scripts/export_lead_list.py --month january --year 2026
"""

from google.cloud import bigquery
import pandas as pd
from datetime import datetime
from pathlib import Path
import argparse

# ============================================================================
# PATH CONFIGURATION
# ============================================================================
WORKING_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation")
EXPORTS_DIR = WORKING_DIR / "exports"
LOGS_DIR = WORKING_DIR / "logs"

# Ensure directories exist
EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
LOGS_DIR.mkdir(parents=True, exist_ok=True)

# BigQuery config
PROJECT_ID = "savvy-gtm-analytics"

def export_lead_list(month: str, year: int):
    """Export lead list to CSV."""
    client = bigquery.Client(project=PROJECT_ID)
    
    table_name = f"ml_features.{month}_{year}_lead_list_v4"
    
    query = f"""
    SELECT 
        advisor_crd,
        salesforce_lead_id,
        first_name,
        last_name,
        email,
        phone,
        linkedin_url,
        firm_name,
        firm_crd,
        score_tier,
        expected_rate_pct,
        v4_percentile,
        prospect_type,
        list_rank
    FROM `{PROJECT_ID}.{table_name}`
    ORDER BY list_rank
    """
    
    print(f"[INFO] Querying {table_name}...")
    df = client.query(query).to_dataframe()
    
    # Export
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    output_file = EXPORTS_DIR / f"{month}_{year}_lead_list_{timestamp}.csv"
    df.to_csv(output_file, index=False)
    
    print(f"[INFO] Exported {len(df):,} leads to {output_file}")
    
    # Log
    log_file = LOGS_DIR / "EXECUTION_LOG.md"
    with open(log_file, 'a') as f:
        f.write(f"\n## Export - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"- Month: {month} {year}\n")
        f.write(f"- Leads exported: {len(df):,}\n")
        f.write(f"- File: {output_file.name}\n")
    
    return output_file

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Export lead list to CSV')
    parser.add_argument('--month', type=str, default='january', help='Month name (e.g., january)')
    parser.add_argument('--year', type=int, default=2026, help='Year (e.g., 2026)')
    args = parser.parse_args()
    
    export_lead_list(args.month, args.year)
```

---

## Monthly Execution Checklist

Use this checklist each month:

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
- **Total Leads**: ___________
- **V4 Filtered Out**: ___________ (should be ~20% of eligible)
- **Avg V4 Percentile**: ___________
- **New Prospects**: ___________
- **Recyclable Leads**: ___________

### Notes
[Any issues or observations]
```

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "No v4_prospect_scores found" | Step 2 not completed | Run scoring script first |
| Low V4 percentile average | V4 scores not joined | Check JOIN in v4_enriched CTE |
| Too few leads | V4 filter too aggressive | Check v4_deprioritize filter |
| Duplicate CRDs | JOIN issue | Add DISTINCT or fix JOIN |
| Missing features | Column name mismatch | Check feature names in final_features.json |

### Debug Queries

```sql
-- Check if V4 scores exist
SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`;

-- Check V4 deprioritize distribution
SELECT 
    v4_deprioritize,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
GROUP BY 1;

-- Check how many prospects were filtered by V4
WITH before_v4 AS (
    SELECT COUNT(*) as cnt FROM ranked_prospects WHERE rank_within_firm <= 50 AND source_priority < 99
),
after_v4 AS (
    SELECT COUNT(*) as cnt FROM diversity_filtered
)
SELECT 
    b.cnt as before_v4_filter,
    a.cnt as after_v4_filter,
    b.cnt - a.cnt as filtered_by_v4
FROM before_v4 b, after_v4 a;
```

---

## Appendix A: Full Hybrid Query Template

See `Lead_List_Generation/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` for the complete query with all V4 modifications marked.

---

## Appendix B: Complete File Path Reference

### Working Directory
```
C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation\
```

### Files Created by This Pipeline (in Lead_List_Generation/)
| Path | Purpose |
|------|---------|
| `sql/v4_prospect_features.sql` | Step 1: V4 feature calculation SQL |
| `sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | Step 3: Hybrid query |
| `scripts/score_prospects_monthly.py` | Step 2: V4 scoring script |
| `scripts/export_lead_list.py` | Step 4: Export script |
| `exports/january_2026_lead_list_YYYYMMDD.csv` | Final CSV export |
| `logs/EXECUTION_LOG.md` | Execution log |

### V4 Model Files (READ ONLY - in Version-4/)
| Path | Purpose |
|------|---------|
| `Version-4/models/v4.0.0/model.pkl` | Trained XGBoost model |
| `Version-4/models/v4.0.0/model.json` | Model configuration |
| `Version-4/data/processed/final_features.json` | Feature list |
| `Version-4/inference/lead_scorer_v4.py` | Reference scorer class |

### BigQuery Tables Created
| Table | Purpose |
|-------|---------|
| `ml_features.v4_prospect_features` | V4 features for all prospects |
| `ml_features.v4_prospect_scores` | V4 scores with percentiles |
| `ml_features.january_2026_lead_list_v4` | Final January 2026 lead list |

---

**Document Version**: 1.0  
**Last Updated**: 2025-12-24  
**Working Directory**: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation`  
**Maintainer**: Data Science Team
