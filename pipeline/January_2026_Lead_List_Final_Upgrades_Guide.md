# January 2026 Lead List Generation - Final Upgrades

**Version**: 2.0  
**Created**: 2025-12-24  
**Purpose**: Implement SHAP narratives, job titles, and firm exclusions  
**Working Directory**: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation`

---

## Overview of Upgrades

| Upgrade | Description | Impact |
|---------|-------------|--------|
| **1. SHAP Narratives** | Generate human-readable explanations for V4 upgraded leads | SDRs understand why ML flagged each lead |
| **2. Job Titles** | Include `job_title` column in exported lists | Better context for outreach |
| **3. Firm Exclusions** | Exclude Savvy Wealth (CRD 318493) and Ritholtz (CRD 168652) | Remove internal/partner firms |

---

## Prerequisites

Before starting, ensure you have:
- ✅ `ml_features.v4_prospect_features` table exists (285,690 rows)
- ✅ V4 model at `C:\Users\russe\Documents\Lead Scoring\Version-4\models\v4.0.0\model.pkl`
- ✅ Python environment with `shap`, `xgboost`, `pandas`, `google-cloud-bigquery`

Install SHAP if needed:
```bash
pip install shap
```

---

## Directory Structure

```
Lead_List_Generation/
├── sql/
│   ├── v4_prospect_features.sql           # Step 1 (already done)
│   └── January_2026_Lead_List_V3_V4_Hybrid.sql  # Step 3 (UPDATE)
├── scripts/
│   ├── score_prospects_monthly.py         # Step 2 (UPDATE - add SHAP)
│   └── export_lead_list.py                # Step 4 (UPDATE - add job_title)
├── exports/
│   └── january_2026_lead_list_YYYYMMDD.csv
└── logs/
    └── EXECUTION_LOG.md
```

---

# STEP 1: Update Scoring Script with SHAP Narratives

## Cursor Prompt 1.1: Replace Scoring Script

```
@workspace Replace the scoring script with SHAP narrative generation.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Task:
1. Replace scripts/score_prospects_monthly.py with the new version below
2. This version:
   - Calculates SHAP values for all prospects
   - Extracts top 3 SHAP features per prospect
   - Generates human-readable narratives for V4 upgrade candidates
   - Uploads new columns to BigQuery: shap_top1/2/3_feature, shap_top1/2/3_value, v4_narrative
3. Install shap if needed: pip install shap
4. Verify the script runs without errors

New columns in ml_features.v4_prospect_scores:
- shap_top1_feature (STRING): Most important feature driving score
- shap_top1_value (FLOAT): SHAP value for that feature
- shap_top2_feature, shap_top2_value: Second most important
- shap_top3_feature, shap_top3_value: Third most important  
- v4_narrative (STRING): Human-readable explanation for V4 upgrades
```

## Code: score_prospects_monthly.py (with SHAP)

```python
"""
Score all prospects with V4 model and generate SHAP-based narratives.
Run monthly BEFORE lead list generation.

UPDATED: 
- Includes SHAP narrative generation for V4 upgraded leads
- Extracts top 3 SHAP features per prospect

Working Directory: Lead_List_Generation
Usage: python scripts/score_prospects_monthly.py
"""

import pandas as pd
import numpy as np
from pathlib import Path
from google.cloud import bigquery
import pickle
import json
from datetime import datetime
import xgboost as xgb
import shap

# ============================================================================
# PATH CONFIGURATION
# ============================================================================
WORKING_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation")
V4_MODEL_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4\models\v4.0.0")
V4_FEATURES_FILE = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4\data\processed\final_features.json")

EXPORTS_DIR = WORKING_DIR / "exports"
LOGS_DIR = WORKING_DIR / "logs"

EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
LOGS_DIR.mkdir(parents=True, exist_ok=True)

# ============================================================================
# BIGQUERY CONFIGURATION
# ============================================================================
PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
FEATURES_TABLE = "v4_prospect_features"
SCORES_TABLE = "v4_prospect_scores"

# Thresholds
DEPRIORITIZE_PERCENTILE = 20
V4_UPGRADE_PERCENTILE = 80

# ============================================================================
# SHAP FEATURE DESCRIPTIONS (Human-readable explanations)
# ============================================================================
FEATURE_DESCRIPTIONS = {
    'tenure_bucket': {
        'name': 'Tenure at Current Firm',
        'positive': 'relatively new at their current firm (1-4 years), indicating potential mobility',
        'negative': 'been at their firm for a long time, suggesting stability'
    },
    'experience_bucket': {
        'name': 'Industry Experience',
        'positive': 'significant industry experience, suggesting a portable book of business',
        'negative': 'limited industry experience'
    },
    'mobility_tier': {
        'name': 'Career Mobility',
        'positive': 'demonstrated willingness to change firms in the past',
        'negative': 'historically stable with limited firm changes'
    },
    'firm_stability_tier': {
        'name': 'Firm Stability',
        'positive': 'working at a firm experiencing advisor departures',
        'negative': 'working at a stable or growing firm'
    },
    'firm_net_change_12mo': {
        'name': 'Firm Net Change',
        'positive': 'their firm is losing advisors, creating instability',
        'negative': 'their firm is stable or growing'
    },
    'firm_rep_count_at_contact': {
        'name': 'Firm Size',
        'positive': 'working at a smaller firm with more autonomy and portability',
        'negative': 'working at a larger firm'
    },
    'is_wirehouse': {
        'name': 'Wirehouse Status',
        'positive': 'not at a wirehouse, fewer restrictions on client portability',
        'negative': 'at a wirehouse with potential transition barriers'
    },
    'is_broker_protocol': {
        'name': 'Broker Protocol',
        'positive': 'their firm participates in the Broker Protocol, making client transitions smoother',
        'negative': 'their firm is not in the Broker Protocol'
    },
    'has_email': {
        'name': 'Email Available',
        'positive': 'we have verified email contact information',
        'negative': 'missing email contact'
    },
    'has_linkedin': {
        'name': 'LinkedIn Available',
        'positive': 'we have LinkedIn profile for personalized outreach',
        'negative': 'missing LinkedIn profile'
    },
    'has_firm_data': {
        'name': 'Firm Data Quality',
        'positive': 'complete firm data available for analysis',
        'negative': 'incomplete firm data'
    },
    'is_experience_missing': {
        'name': 'Experience Data',
        'positive': 'complete experience data available',
        'negative': 'missing experience data'
    },
    'mobility_x_heavy_bleeding': {
        'name': 'Mobility + Bleeding Firm Combination',
        'positive': 'historically mobile AND currently at a firm losing advisors - strong signal',
        'negative': 'does not have the powerful mobility + bleeding firm combination'
    },
    'short_tenure_x_high_mobility': {
        'name': 'Short Tenure + High Mobility',
        'positive': 'new to current firm AND history of moves - very likely to move again',
        'negative': 'does not have short tenure + mobility combination'
    }
}


def load_model():
    """Load the V4 XGBoost model."""
    model_path = V4_MODEL_DIR / "model.pkl"
    if not model_path.exists():
        raise FileNotFoundError(f"Model file not found: {model_path}")
    
    with open(model_path, 'rb') as f:
        model = pickle.load(f)
    print(f"[INFO] Loaded model from {model_path}")
    return model


def load_features_list():
    """Load the final feature list."""
    if not V4_FEATURES_FILE.exists():
        raise FileNotFoundError(f"Features file not found: {V4_FEATURES_FILE}")
    
    with open(V4_FEATURES_FILE, 'r') as f:
        data = json.load(f)
    features = data['final_features']
    print(f"[INFO] Loaded {len(features)} features: {features}")
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
        print(f"[WARNING] Missing features (will be filled with 0): {missing}")
        for m in missing:
            X[m] = 0
    
    X = X[feature_list].copy()
    
    # Encode categoricals
    categorical_cols = ['tenure_bucket', 'experience_bucket', 'mobility_tier', 'firm_stability_tier']
    for col in categorical_cols:
        if col in X.columns:
            X[col] = X[col].astype('category').cat.codes
            X[col] = X[col].replace(-1, 0)
    
    # Fill NaN
    X = X.fillna(0)
    
    # Ensure numeric types
    for col in X.columns:
        if X[col].dtype == 'object':
            try:
                X[col] = pd.to_numeric(X[col], errors='coerce').fillna(0)
            except:
                pass
    
    return X


def score_prospects(model, X):
    """Generate V4 scores."""
    dmatrix = xgb.DMatrix(X)
    scores = model.predict(dmatrix)
    print(f"[INFO] Scored {len(scores):,} prospects")
    print(f"[INFO] Score range: {scores.min():.4f} - {scores.max():.4f}")
    return scores


def calculate_percentiles(scores):
    """Calculate percentile ranks (0-99)."""
    percentiles = pd.Series(scores).rank(pct=True, method='min') * 100
    return percentiles.astype(int).values


def calculate_shap_values(model, X):
    """Calculate SHAP values for feature importance explanations."""
    print(f"[INFO] Calculating SHAP values for {len(X):,} prospects...")
    print(f"[INFO] This may take several minutes...")
    
    # Use TreeExplainer for XGBoost (fast)
    explainer = shap.TreeExplainer(model)
    
    # Calculate SHAP values
    shap_values = explainer.shap_values(X)
    
    print(f"[INFO] SHAP values calculated successfully")
    
    return shap_values, explainer.expected_value


def generate_narrative(v4_score, v4_percentile, top_features, top_values, feature_names):
    """Generate a human-readable narrative for a V4 upgrade candidate."""
    
    # Build list of positive factors
    positive_factors = []
    
    for i, (feat, val) in enumerate(zip(top_features, top_values)):
        if feat is None or val is None:
            continue
        if feat not in FEATURE_DESCRIPTIONS:
            continue
        
        desc = FEATURE_DESCRIPTIONS[feat]
        
        # Only include if it's a positive contribution
        if val > 0.01:
            positive_factors.append(desc['positive'])
    
    # Build narrative
    narrative_parts = [
        f"V4 Model Upgrade: Identified as a high-potential lead ",
        f"(V4 score: {v4_score:.2f}, {v4_percentile}th percentile). "
    ]
    
    if positive_factors:
        narrative_parts.append("Key factors: This advisor is ")
        narrative_parts.append(positive_factors[0])
        if len(positive_factors) > 1:
            narrative_parts.append(f", and is {positive_factors[1]}")
        narrative_parts.append(". ")
    
    narrative_parts.append(
        f"Historical conversion rate for similar leads: 4.60% (1.42x baseline). "
        f"Promoted from STANDARD tier via V4 machine learning analysis."
    )
    
    return ''.join(narrative_parts)


def extract_top_shap_features(shap_values, feature_list, scores, percentiles):
    """Extract top 3 SHAP features for each prospect and generate narratives."""
    
    print("[INFO] Extracting top SHAP features and generating narratives...")
    
    n_prospects = len(shap_values)
    
    results = {
        'shap_top1_feature': [],
        'shap_top1_value': [],
        'shap_top2_feature': [],
        'shap_top2_value': [],
        'shap_top3_feature': [],
        'shap_top3_value': [],
        'v4_narrative': []
    }
    
    for i in range(n_prospects):
        # Get absolute SHAP values and sort
        shap_abs = np.abs(shap_values[i])
        top_idx = np.argsort(shap_abs)[::-1][:3]
        
        # Top 3 features
        top_features = [feature_list[idx] for idx in top_idx]
        top_values = [float(shap_values[i][idx]) for idx in top_idx]
        
        results['shap_top1_feature'].append(top_features[0] if len(top_features) > 0 else None)
        results['shap_top1_value'].append(top_values[0] if len(top_values) > 0 else 0.0)
        results['shap_top2_feature'].append(top_features[1] if len(top_features) > 1 else None)
        results['shap_top2_value'].append(top_values[1] if len(top_values) > 1 else 0.0)
        results['shap_top3_feature'].append(top_features[2] if len(top_features) > 2 else None)
        results['shap_top3_value'].append(top_values[2] if len(top_values) > 2 else 0.0)
        
        # Generate narrative only for V4 upgrade candidates (>=80th percentile)
        if percentiles[i] >= V4_UPGRADE_PERCENTILE:
            narrative = generate_narrative(
                v4_score=scores[i],
                v4_percentile=percentiles[i],
                top_features=top_features,
                top_values=top_values,
                feature_names=feature_list
            )
        else:
            narrative = None
        
        results['v4_narrative'].append(narrative)
        
        # Progress indicator
        if (i + 1) % 50000 == 0:
            print(f"[INFO] Processed {i+1:,} / {n_prospects:,} prospects...")
    
    # Count narratives generated
    narrative_count = sum(1 for n in results['v4_narrative'] if n is not None)
    print(f"[INFO] Generated {narrative_count:,} V4 upgrade narratives")
    
    return results


def upload_scores(client, df_scores):
    """Upload scores to BigQuery."""
    table_id = f"{PROJECT_ID}.{DATASET}.{SCORES_TABLE}"
    
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        schema=[
            bigquery.SchemaField("crd", "INT64"),
            bigquery.SchemaField("v4_score", "FLOAT64"),
            bigquery.SchemaField("v4_percentile", "INT64"),
            bigquery.SchemaField("v4_deprioritize", "BOOLEAN"),
            bigquery.SchemaField("v4_upgrade_candidate", "BOOLEAN"),
            bigquery.SchemaField("shap_top1_feature", "STRING"),
            bigquery.SchemaField("shap_top1_value", "FLOAT64"),
            bigquery.SchemaField("shap_top2_feature", "STRING"),
            bigquery.SchemaField("shap_top2_value", "FLOAT64"),
            bigquery.SchemaField("shap_top3_feature", "STRING"),
            bigquery.SchemaField("shap_top3_value", "FLOAT64"),
            bigquery.SchemaField("v4_narrative", "STRING"),
            bigquery.SchemaField("scored_at", "TIMESTAMP"),
        ]
    )
    
    job = client.load_table_from_dataframe(df_scores, table_id, job_config=job_config)
    job.result()
    print(f"[INFO] Uploaded {len(df_scores):,} scores to {table_id}")


def main():
    print("=" * 70)
    print("V4 MONTHLY PROSPECT SCORING WITH SHAP NARRATIVES")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Working Directory: {WORKING_DIR}")
    print("=" * 70)
    
    # Initialize
    client = bigquery.Client(project=PROJECT_ID)
    model = load_model()
    feature_list = load_features_list()
    
    # Fetch features
    df_raw = fetch_prospect_features(client)
    
    # Prepare features
    X = prepare_features(df_raw, feature_list)
    
    # Score
    scores = score_prospects(model, X)
    percentiles = calculate_percentiles(scores)
    
    # Calculate SHAP values
    shap_values, expected_value = calculate_shap_values(model, X)
    
    # Extract top features and generate narratives
    shap_results = extract_top_shap_features(shap_values, feature_list, scores, percentiles)
    
    # Build output DataFrame
    df_scores = pd.DataFrame({
        'crd': df_raw['crd'].astype(int),
        'v4_score': scores,
        'v4_percentile': percentiles,
        'v4_deprioritize': percentiles <= DEPRIORITIZE_PERCENTILE,
        'v4_upgrade_candidate': percentiles >= V4_UPGRADE_PERCENTILE,
        'shap_top1_feature': shap_results['shap_top1_feature'],
        'shap_top1_value': shap_results['shap_top1_value'],
        'shap_top2_feature': shap_results['shap_top2_feature'],
        'shap_top2_value': shap_results['shap_top2_value'],
        'shap_top3_feature': shap_results['shap_top3_feature'],
        'shap_top3_value': shap_results['shap_top3_value'],
        'v4_narrative': shap_results['v4_narrative'],
        'scored_at': datetime.now()
    })
    
    # Upload to BigQuery
    upload_scores(client, df_scores)
    
    # Summary
    print("\n" + "=" * 70)
    print("SCORING SUMMARY")
    print("=" * 70)
    print(f"Total prospects scored: {len(df_scores):,}")
    print(f"V4 Upgrade candidates (>={V4_UPGRADE_PERCENTILE}%): {df_scores['v4_upgrade_candidate'].sum():,}")
    print(f"V4 narratives generated: {sum(1 for n in shap_results['v4_narrative'] if n is not None):,}")
    print(f"Score range: {df_scores['v4_score'].min():.4f} - {df_scores['v4_score'].max():.4f}")
    print(f"Mean score: {df_scores['v4_score'].mean():.4f}")
    
    # Top SHAP features summary
    print("\nMost common top SHAP features:")
    top1_counts = pd.Series(shap_results['shap_top1_feature']).value_counts().head(5)
    for feat, count in top1_counts.items():
        pct = count / len(df_scores) * 100
        print(f"  - {feat}: {count:,} ({pct:.1f}%)")
    
    print("=" * 70)
    
    # Log to file
    log_file = LOGS_DIR / "EXECUTION_LOG.md"
    with open(log_file, 'a', encoding='utf-8') as f:
        f.write(f"\n## Step 2: V4 Scoring with SHAP Narratives - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write(f"**Status**: ✅ SUCCESS\n\n")
        f.write(f"**Results:**\n")
        f.write(f"- Total scored: {len(df_scores):,}\n")
        f.write(f"- V4 upgrade candidates: {df_scores['v4_upgrade_candidate'].sum():,}\n")
        f.write(f"- V4 narratives generated: {sum(1 for n in shap_results['v4_narrative'] if n is not None):,}\n")
        f.write(f"- Score range: {df_scores['v4_score'].min():.4f} - {df_scores['v4_score'].max():.4f}\n")
        f.write(f"\n**New Columns:**\n")
        f.write(f"- `shap_top1/2/3_feature`: Top 3 SHAP features\n")
        f.write(f"- `shap_top1/2/3_value`: SHAP values for those features\n")
        f.write(f"- `v4_narrative`: Human-readable narrative for V4 upgrades\n")
        f.write(f"\n**Table Updated**: `{PROJECT_ID}.{DATASET}.{SCORES_TABLE}`\n\n")
        f.write("---\n\n")
    
    print(f"[INFO] Logged to {log_file}")
    print("[INFO] Scoring with SHAP complete!")
    
    return df_scores


if __name__ == "__main__":
    main()
```

---

## Cursor Prompt 1.2: Run the Updated Scoring Script

```
@workspace Run the V4 scoring script with SHAP narrative generation.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Prerequisites:
- scripts/score_prospects_monthly.py has been replaced with SHAP version
- shap package is installed (pip install shap)
- ml_features.v4_prospect_features exists

Task:
1. Run: python scripts/score_prospects_monthly.py
2. This will take 5-15 minutes due to SHAP calculations
3. Verify ml_features.v4_prospect_scores has new columns:
   - shap_top1_feature, shap_top1_value
   - shap_top2_feature, shap_top2_value
   - shap_top3_feature, shap_top3_value
   - v4_narrative
4. Log results to logs/EXECUTION_LOG.md

Validation query:
SELECT 
    v4_upgrade_candidate,
    COUNT(*) as count,
    COUNT(v4_narrative) as narratives,
    AVG(v4_score) as avg_score
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
GROUP BY 1;
```

---

# STEP 2: Update SQL with Firm Exclusions and Job Titles

## Cursor Prompt 2.1: Replace Lead List SQL

```
@workspace Replace the lead list SQL with firm exclusions, job titles, and narratives.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Task:
1. Replace sql/January_2026_Lead_List_V3_V4_Hybrid.sql with the new version below
2. Key changes:
   - ADDED: Exclusion for Savvy Wealth (CRD 318493) and Ritholtz (CRD 168652)
   - ADDED: job_title column in output
   - ADDED: score_narrative column combining V3 rules + V4 SHAP narratives
3. Verify SQL syntax is correct

New exclusions:
- Savvy Advisors, Inc. - CRD # 318493
- Ritholtz Wealth Management - CRD # 168652
```

## Code: January_2026_Lead_List_V3_V4_Hybrid.sql (Updated)

```sql
-- ============================================================================
-- JANUARY 2026 LEAD LIST GENERATOR (V3.2.5 + V4 UPGRADE PATH)
-- Version: 2.0 with SHAP Narratives, Job Titles, and Firm Exclusions
-- 
-- FEATURES:
-- - V3 Rules: Tier assignment with rich human-readable narratives
-- - V4 XGBoost: Upgrade path with SHAP-based narratives
-- - Job Titles: Included in output for SDR context
-- - Firm Exclusions: Savvy Wealth and Ritholtz excluded
--
-- FIRM EXCLUSIONS:
-- - Savvy Advisors, Inc. (CRD 318493) - Internal firm
-- - Ritholtz Wealth Management (CRD 168652) - Partner firm
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4` AS

WITH 
-- ============================================================================
-- A. EXCLUSIONS (Wirehouses + Insurance + Specific Firms)
-- ============================================================================
excluded_firms AS (
    SELECT firm_pattern FROM UNNEST([
        -- Wirehouses
        '%J.P. MORGAN%', '%MORGAN STANLEY%', '%MERRILL%', '%WELLS FARGO%', 
        '%UBS %', '%UBS,%', '%EDWARD JONES%', '%AMERIPRISE%', 
        '%NORTHWESTERN MUTUAL%', '%PRUDENTIAL%', '%RAYMOND JAMES%',
        '%FIDELITY%', '%SCHWAB%', '%VANGUARD%', '%GOLDMAN SACHS%', '%CITIGROUP%',
        '%LPL FINANCIAL%', '%COMMONWEALTH%', '%CETERA%', '%CAMBRIDGE%',
        '%OSAIC%', '%PRIMERICA%',
        -- Insurance
        '%STATE FARM%', '%ALLSTATE%', '%NEW YORK LIFE%', '%NYLIFE%',
        '%TRANSAMERICA%', '%FARM BUREAU%', '%NATIONWIDE%',
        '%LINCOLN FINANCIAL%', '%MASS MUTUAL%', '%MASSMUTUAL%',
        '%INSURANCE%',
        -- Specific firm name exclusions (backup for CRD exclusion)
        '%SAVVY WEALTH%', '%SAVVY ADVISORS%',
        '%RITHOLTZ%'
    ]) as firm_pattern
),

-- NEW: Specific CRD exclusions for Savvy and Ritholtz
excluded_firm_crds AS (
    SELECT firm_crd FROM UNNEST([
        318493,  -- Savvy Advisors, Inc.
        168652   -- Ritholtz Wealth Management
    ]) as firm_crd
),

-- ============================================================================
-- B. EXISTING SALESFORCE CRDs
-- ============================================================================
salesforce_crds AS (
    SELECT DISTINCT 
        SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
        Id as lead_id
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE FA_CRD__c IS NOT NULL AND IsDeleted = false
),

-- ============================================================================
-- C. RECYCLABLE LEADS (180+ days no contact)
-- ============================================================================
lead_task_activity AS (
    SELECT 
        t.WhoId as lead_id,
        MAX(GREATEST(
            COALESCE(DATE(t.ActivityDate), DATE('1900-01-01')),
            COALESCE(DATE(t.CompletedDateTime), DATE('1900-01-01')),
            COALESCE(DATE(t.CreatedDate), DATE('1900-01-01'))
        )) as last_activity_date
    FROM `savvy-gtm-analytics.SavvyGTMData.Task` t
    WHERE t.IsDeleted = false AND t.WhoId IS NOT NULL
      AND (t.Type IN ('Outgoing SMS', 'Incoming SMS')
           OR UPPER(t.Subject) LIKE '%SMS%' OR UPPER(t.Subject) LIKE '%TEXT%'
           OR t.TaskSubtype = 'Call' OR t.Type = 'Call'
           OR UPPER(t.Subject) LIKE '%CALL%' OR t.CallType IS NOT NULL)
    GROUP BY t.WhoId
),

recyclable_lead_ids AS (
    SELECT l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN lead_task_activity la ON l.Id = la.lead_id
    WHERE l.IsDeleted = false AND l.FA_CRD__c IS NOT NULL
      AND (la.last_activity_date IS NULL OR DATE_DIFF(CURRENT_DATE(), la.last_activity_date, DAY) > 180)
      AND (l.DoNotCall IS NULL OR l.DoNotCall = false)
      AND l.Status NOT IN ('Closed', 'Converted', 'Dead', 'Unqualified', 'Disqualified', 
                           'Do Not Contact', 'Not Qualified', 'Bad Data', 'Duplicate')
),

-- ============================================================================
-- D. ADVISOR EMPLOYMENT HISTORY
-- ============================================================================
advisor_moves AS (
    SELECT 
        RIA_CONTACT_CRD_ID as crd,
        COUNT(DISTINCT PREVIOUS_REGISTRATION_COMPANY_CRD_ID) as total_firms,
        COUNT(DISTINCT CASE 
            WHEN PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 YEAR)
            THEN PREVIOUS_REGISTRATION_COMPANY_CRD_ID END) as moves_3yr,
        MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE) as career_start_date
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    GROUP BY RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- E. FIRM HEADCOUNT
-- ============================================================================
firm_headcount AS (
    SELECT 
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_reps
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM IS NOT NULL
    GROUP BY PRIMARY_FIRM
),

-- ============================================================================
-- F. FIRM DEPARTURES
-- ============================================================================
firm_departures AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),

-- ============================================================================
-- G. FIRM ARRIVALS
-- ============================================================================
firm_arrivals AS (
    SELECT
        SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PRIMARY_FIRM IS NOT NULL
    GROUP BY 1
),

-- ============================================================================
-- H. COMBINED FIRM METRICS
-- ============================================================================
firm_metrics AS (
    SELECT
        h.firm_crd,
        h.current_reps as firm_rep_count,
        COALESCE(d.departures_12mo, 0) as departures_12mo,
        COALESCE(a.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(a.arrivals_12mo, 0) - COALESCE(d.departures_12mo, 0) as firm_net_change_12mo,
        CASE WHEN h.current_reps > 0 
             THEN COALESCE(d.departures_12mo, 0) * 100.0 / h.current_reps 
             ELSE 0 END as turnover_pct
    FROM firm_headcount h
    LEFT JOIN firm_departures d ON h.firm_crd = d.firm_crd
    LEFT JOIN firm_arrivals a ON h.firm_crd = a.firm_crd
    WHERE h.current_reps >= 20
),

-- ============================================================================
-- I. BASE PROSPECT DATA (with firm CRD exclusions)
-- ============================================================================
base_prospects AS (
    SELECT 
        c.RIA_CONTACT_CRD_ID as crd,
        c.CONTACT_FIRST_NAME as first_name,
        c.CONTACT_LAST_NAME as last_name,
        c.PRIMARY_FIRM_NAME as firm_name,
        SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
        c.EMAIL as email,
        COALESCE(c.MOBILE_PHONE_NUMBER, c.OFFICE_PHONE_NUMBER) as phone,
        c.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        c.PRIMARY_FIRM_EMPLOYEE_COUNT as firm_employee_count,
        DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, MONTH) as tenure_months,
        DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, YEAR) as tenure_years,
        CASE WHEN sf.crd IS NULL THEN 'NEW_PROSPECT' ELSE 'IN_SALESFORCE' END as prospect_type,
        sf.lead_id as existing_lead_id,
        -- JOB TITLE (NEW!)
        c.TITLE_NAME as job_title
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    LEFT JOIN salesforce_crds sf ON c.RIA_CONTACT_CRD_ID = sf.crd
    WHERE c.CONTACT_FIRST_NAME IS NOT NULL AND c.CONTACT_LAST_NAME IS NOT NULL
      AND c.PRIMARY_FIRM_START_DATE IS NOT NULL AND c.PRIMARY_FIRM_NAME IS NOT NULL
      AND c.PRIMARY_FIRM IS NOT NULL
      AND c.PRODUCING_ADVISOR = TRUE
      -- Exclude by firm name pattern
      AND NOT EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern)
      -- NEW: Exclude by firm CRD (Savvy 318493, Ritholtz 168652)
      AND SAFE_CAST(c.PRIMARY_FIRM AS INT64) NOT IN (SELECT firm_crd FROM excluded_firm_crds)
      -- Title exclusions
      AND NOT (
          UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTIONS ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE ADVISOR%'
          OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS%'
          OR UPPER(c.TITLE_NAME) LIKE '%WHOLESALER%'
          OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE%'
          OR UPPER(c.TITLE_NAME) LIKE '%ASSISTANT%'
          OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE AGENT%'
          OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE%'
      )
),

-- ============================================================================
-- J. ENRICH WITH ADVISOR HISTORY, FIRM METRICS, AND CERTIFICATIONS
-- ============================================================================
enriched_prospects AS (
    SELECT 
        bp.*,
        COALESCE(am.total_firms, 1) as total_firms,
        COALESCE(am.total_firms, 1) - 1 as num_prior_firms,
        COALESCE(am.moves_3yr, 0) as moves_3yr,
        DATE_DIFF(CURRENT_DATE(), am.career_start_date, YEAR) as industry_tenure_years,
        DATE_DIFF(CURRENT_DATE(), am.career_start_date, MONTH) as industry_tenure_months,
        COALESCE(fm.firm_rep_count, bp.firm_employee_count, 1) as firm_rep_count,
        COALESCE(fm.arrivals_12mo, 0) as firm_arrivals_12mo,
        COALESCE(fm.departures_12mo, 0) as firm_departures_12mo,
        COALESCE(fm.firm_net_change_12mo, 0) as firm_net_change_12mo,
        COALESCE(fm.turnover_pct, 0) as firm_turnover_pct,
        CASE WHEN EXISTS (SELECT 1 FROM excluded_firms ef WHERE UPPER(bp.firm_name) LIKE ef.firm_pattern) THEN 1 ELSE 0 END as is_wirehouse,
        
        -- Certifications
        CASE WHEN c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%' THEN 1 ELSE 0 END as has_cfp,
        CASE WHEN c.REP_LICENSES LIKE '%Series 65%' AND c.REP_LICENSES NOT LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_65_only,
        CASE WHEN c.REP_LICENSES LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_7,
        CASE WHEN c.CONTACT_BIO LIKE '%CFA%' OR c.TITLE_NAME LIKE '%CFA%' THEN 1 ELSE 0 END as has_cfa,
        
        -- High-value wealth title
        CASE WHEN (
            UPPER(c.TITLE_NAME) LIKE '%WEALTH MANAGER%'
            OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%WEALTH%'
            OR UPPER(c.TITLE_NAME) LIKE '%SENIOR WEALTH ADVISOR%'
        ) THEN 1 ELSE 0 END as is_hv_wealth_title,
        
        -- LinkedIn
        c.LINKEDIN_PROFILE_URL as linkedin_url,
        CASE WHEN c.LINKEDIN_PROFILE_URL IS NOT NULL AND TRIM(c.LINKEDIN_PROFILE_URL) != '' THEN 1 ELSE 0 END as has_linkedin,
        c.PRODUCING_ADVISOR as producing_advisor
        
    FROM base_prospects bp
    LEFT JOIN advisor_moves am ON bp.crd = am.crd
    LEFT JOIN firm_metrics fm ON bp.firm_crd = fm.firm_crd
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c ON bp.crd = c.RIA_CONTACT_CRD_ID
    WHERE COALESCE(fm.turnover_pct, 0) < 100
),

-- ============================================================================
-- J2. JOIN V4 SCORES + SHAP NARRATIVES
-- ============================================================================
v4_enriched AS (
    SELECT 
        ep.*,
        COALESCE(v4.v4_score, 0.5) as v4_score,
        COALESCE(v4.v4_percentile, 50) as v4_percentile,
        COALESCE(v4.v4_deprioritize, FALSE) as v4_deprioritize,
        COALESCE(v4.v4_upgrade_candidate, FALSE) as v4_upgrade_candidate,
        -- SHAP data for narrative generation
        v4.shap_top1_feature,
        v4.shap_top1_value,
        v4.shap_top2_feature,
        v4.shap_top2_value,
        v4.shap_top3_feature,
        v4.shap_top3_value,
        v4.v4_narrative as v4_shap_narrative
    FROM enriched_prospects ep
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 
        ON ep.crd = v4.crd
),

-- ============================================================================
-- K. APPLY V3.2 TIER LOGIC WITH NARRATIVES
-- ============================================================================
scored_prospects AS (
    SELECT 
        ep.*,
        
        -- Score tier
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years >= 5 AND firm_net_change_12mo < 0 AND has_cfp = 1 AND is_wirehouse = 0) THEN 'TIER_1A_PRIME_MOVER_CFP'
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 'TIER_1B_PRIME_MOVER_SERIES65'
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 'TIER_1_PRIME_MOVER'
            WHEN (is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND is_wirehouse = 0) THEN 'TIER_1F_HV_WEALTH_BLEEDER'
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 'TIER_2_PROVEN_MOVER'
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5) THEN 'TIER_3_MODERATE_BLEEDER'
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 'TIER_4_EXPERIENCED_MOVER'
            WHEN (firm_net_change_12mo <= -10 AND industry_tenure_years >= 5) THEN 'TIER_5_HEAVY_BLEEDER'
            ELSE 'STANDARD'
        END as score_tier,
        
        -- Priority rank
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years >= 5 AND firm_net_change_12mo < 0 AND has_cfp = 1 AND is_wirehouse = 0) THEN 1
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 2
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 3
            WHEN (is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND is_wirehouse = 0) THEN 4
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 5
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5) THEN 6
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 7
            WHEN (firm_net_change_12mo <= -10 AND industry_tenure_years >= 5) THEN 8
            ELSE 99
        END as priority_rank,
        
        -- Expected conversion rate
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years >= 5 AND firm_net_change_12mo < 0 AND has_cfp = 1 AND is_wirehouse = 0) THEN 0.087
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN 0.079
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN 0.071
            WHEN (is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND is_wirehouse = 0) THEN 0.065
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN 0.052
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5) THEN 0.044
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN 0.041
            WHEN (firm_net_change_12mo <= -10 AND industry_tenure_years >= 5) THEN 0.038
            ELSE 0.025
        END as expected_conversion_rate,
        
        -- V3 TIER NARRATIVES
        CASE 
            WHEN (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years >= 5 AND firm_net_change_12mo < 0 AND has_cfp = 1 AND is_wirehouse = 0) THEN
                CONCAT(first_name, ' is a CFP holder at ', firm_name, ', which has lost ', CAST(ABS(firm_net_change_12mo) AS STRING), 
                       ' advisors (net) in the past year. CFP designation indicates book ownership and client relationships. ',
                       'With ', CAST(tenure_years AS STRING), ' years at the firm and ', CAST(industry_tenure_years AS STRING), 
                       ' years of experience, this is an ULTRA-PRIORITY lead. Tier 1A: 8.7% expected conversion.')
            WHEN (((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0))
                  AND has_series_65_only = 1) THEN
                CONCAT(first_name, ' is a fee-only RIA advisor (Series 65 only) at ', firm_name, 
                       '. Pure RIA advisors have no broker-dealer ties, making transitions easier. ',
                       'Tier 1B: Prime Mover (Pure RIA) with 7.9% expected conversion.')
            WHEN ((tenure_years BETWEEN 1 AND 3 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND firm_rep_count <= 50 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 3 AND firm_rep_count <= 10 AND is_wirehouse = 0)
                  OR (tenure_years BETWEEN 1 AND 4 AND industry_tenure_years BETWEEN 5 AND 15 AND firm_net_change_12mo < 0 AND is_wirehouse = 0)) THEN
                CONCAT(first_name, ' has been at ', firm_name, ' for ', CAST(tenure_years AS STRING), ' years with ', 
                       CAST(industry_tenure_years AS STRING), ' years of experience. ',
                       CASE WHEN firm_net_change_12mo < 0 THEN CONCAT('The firm has lost ', CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors. ') ELSE '' END,
                       'Prime Mover tier with 7.1% expected conversion.')
            WHEN (is_hv_wealth_title = 1 AND firm_net_change_12mo < 0 AND is_wirehouse = 0) THEN
                CONCAT(first_name, ' holds a High-Value Wealth title at ', firm_name, ', which has lost ', 
                       CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors. Tier 1F: HV Wealth (Bleeding) with 6.5% expected conversion.')
            WHEN (num_prior_firms >= 3 AND industry_tenure_years >= 5) THEN
                CONCAT(first_name, ' has worked at ', CAST(num_prior_firms + 1 AS STRING), ' different firms over ', 
                       CAST(industry_tenure_years AS STRING), ' years. History of mobility demonstrates willingness to change. ',
                       'Proven Mover tier with 5.2% expected conversion.')
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1 AND industry_tenure_years >= 5) THEN
                CONCAT(firm_name, ' has experienced moderate advisor departures (net change: ', CAST(firm_net_change_12mo AS STRING), '). ',
                       first_name, ' is likely hearing about opportunities from departing colleagues. Moderate Bleeder tier: 4.4% expected conversion.')
            WHEN (industry_tenure_years >= 20 AND tenure_years BETWEEN 1 AND 4) THEN
                CONCAT(first_name, ' is a ', CAST(industry_tenure_years AS STRING), '-year veteran who recently moved to ', firm_name, 
                       '. A veteran who recently changed firms will move for the right opportunity. Experienced Mover: 4.1% expected conversion.')
            WHEN (firm_net_change_12mo <= -10 AND industry_tenure_years >= 5) THEN
                CONCAT(firm_name, ' is losing ', CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors (net). ', first_name, 
                       ' is watching the workplace destabilize. Heavy Bleeder tier: 3.8% expected conversion.')
            ELSE
                CONCAT(first_name, ' at ', firm_name, ' - checking for V4 upgrade eligibility.')
        END as v3_score_narrative
        
    FROM v4_enriched ep
),

-- ============================================================================
-- L. RANK PROSPECTS
-- ============================================================================
ranked_prospects AS (
    SELECT 
        sp.*,
        CASE 
            WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 1
            WHEN sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids) THEN 2
            ELSE 99
        END as source_priority,
        ROW_NUMBER() OVER (
            PARTITION BY sp.firm_crd 
            ORDER BY 
                CASE WHEN sp.prospect_type = 'NEW_PROSPECT' THEN 0 ELSE 1 END,
                sp.priority_rank,
                sp.v4_percentile DESC,
                sp.crd
        ) as rank_within_firm
    FROM scored_prospects sp
    WHERE sp.prospect_type = 'NEW_PROSPECT'
       OR sp.existing_lead_id IN (SELECT lead_id FROM recyclable_lead_ids)
),

-- ============================================================================
-- M. APPLY FIRM DIVERSITY CAP
-- ============================================================================
diversity_filtered AS (
    SELECT * FROM ranked_prospects
    WHERE rank_within_firm <= 50 
      AND source_priority < 99
),

-- ============================================================================
-- N. APPLY TIER QUOTAS + V4 UPGRADE PATH
-- ============================================================================
tier_limited AS (
    SELECT 
        df.*,
        -- V4 upgrade flag
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 1 
            ELSE 0 
        END as is_v4_upgrade,
        -- Final tier
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 'V4_UPGRADE'
            ELSE df.score_tier 
        END as final_tier,
        -- Final expected rate
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 0.046
            ELSE df.expected_conversion_rate 
        END as final_expected_rate,
        -- FINAL NARRATIVE: V3 or V4 SHAP
        CASE 
            WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN
                COALESCE(
                    df.v4_shap_narrative,
                    CONCAT(
                        'V4 Model Upgrade: ', df.first_name, ' at ', df.firm_name, ' identified as high-potential lead ',
                        '(V4 score: ', CAST(ROUND(df.v4_score, 2) AS STRING), ', ', CAST(df.v4_percentile AS STRING), 'th percentile). ',
                        CASE 
                            WHEN df.shap_top1_feature = 'mobility_tier' THEN 'Key factor: demonstrated career mobility. '
                            WHEN df.shap_top1_feature = 'firm_stability_tier' THEN 'Key factor: firm experiencing instability. '
                            WHEN df.shap_top1_feature = 'tenure_bucket' THEN 'Key factor: favorable tenure at current firm. '
                            WHEN df.shap_top1_feature = 'is_broker_protocol' THEN 'Key factor: firm participates in Broker Protocol. '
                            WHEN df.shap_top1_feature = 'experience_bucket' THEN 'Key factor: significant industry experience. '
                            ELSE 'Key factors identified through ML analysis. '
                        END,
                        'Historical conversion: 4.60% (1.42x baseline). Track as V4 Upgrade.'
                    )
                )
            ELSE df.v3_score_narrative
        END as score_narrative,
        ROW_NUMBER() OVER (
            PARTITION BY 
                CASE 
                    WHEN df.score_tier = 'STANDARD' AND df.v4_percentile >= 80 THEN 'V4_UPGRADE'
                    ELSE df.score_tier 
                END
            ORDER BY 
                df.source_priority,
                df.has_linkedin DESC,
                df.v4_percentile DESC,
                df.priority_rank,
                CASE WHEN df.firm_net_change_12mo < 0 THEN ABS(df.firm_net_change_12mo) ELSE 0 END DESC,
                df.crd
        ) as tier_rank
    FROM diversity_filtered df
    WHERE df.score_tier != 'STANDARD'
       OR (df.score_tier = 'STANDARD' AND df.v4_percentile >= 80)
),

-- ============================================================================
-- O. LINKEDIN PRIORITIZATION
-- ============================================================================
linkedin_prioritized AS (
    SELECT 
        tl.*,
        ROW_NUMBER() OVER (
            ORDER BY 
                CASE final_tier
                    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
                    WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
                    WHEN 'TIER_1_PRIME_MOVER' THEN 3
                    WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
                    WHEN 'TIER_2_PROVEN_MOVER' THEN 5
                    WHEN 'V4_UPGRADE' THEN 6
                    WHEN 'TIER_3_MODERATE_BLEEDER' THEN 7
                    WHEN 'TIER_4_EXPERIENCED_MOVER' THEN 8
                    WHEN 'TIER_5_HEAVY_BLEEDER' THEN 9
                END,
                source_priority,
                has_linkedin DESC,
                v4_percentile DESC,
                crd
        ) as overall_rank,
        CASE 
            WHEN has_linkedin = 0 THEN
                ROW_NUMBER() OVER (
                    PARTITION BY CASE WHEN has_linkedin = 0 THEN 1 ELSE 0 END
                    ORDER BY 
                        CASE final_tier
                            WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
                            WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
                            WHEN 'TIER_1_PRIME_MOVER' THEN 3
                            WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
                            WHEN 'TIER_2_PROVEN_MOVER' THEN 5
                            WHEN 'V4_UPGRADE' THEN 6
                            WHEN 'TIER_3_MODERATE_BLEEDER' THEN 7
                            WHEN 'TIER_4_EXPERIENCED_MOVER' THEN 8
                            WHEN 'TIER_5_HEAVY_BLEEDER' THEN 9
                        END,
                        source_priority,
                        v4_percentile DESC,
                        crd
                )
            ELSE NULL
        END as no_linkedin_rank
    FROM tier_limited tl
    WHERE 
        (final_tier = 'TIER_1A_PRIME_MOVER_CFP' AND tier_rank <= 50)
        OR (final_tier = 'TIER_1B_PRIME_MOVER_SERIES65' AND tier_rank <= 60)
        OR (final_tier = 'TIER_1_PRIME_MOVER' AND tier_rank <= 300)
        OR (final_tier = 'TIER_1F_HV_WEALTH_BLEEDER' AND tier_rank <= 50)
        OR (final_tier = 'TIER_2_PROVEN_MOVER' AND tier_rank <= 1500)
        OR (final_tier = 'TIER_3_MODERATE_BLEEDER' AND tier_rank <= 300)
        OR (final_tier = 'TIER_4_EXPERIENCED_MOVER' AND tier_rank <= 300)
        OR (final_tier = 'TIER_5_HEAVY_BLEEDER' AND tier_rank <= 1500)
        OR (final_tier = 'V4_UPGRADE' AND tier_rank <= 500)
)

-- ============================================================================
-- P. FINAL OUTPUT
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
    
    -- JOB TITLE (NEW!)
    job_title,
    
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
    score_tier as original_v3_tier,
    final_tier as score_tier,
    priority_rank,
    final_expected_rate as expected_conversion_rate,
    ROUND(final_expected_rate * 100, 2) as expected_rate_pct,
    
    -- SCORE NARRATIVE (V3 rules or V4 SHAP)
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
    
    -- V4 columns
    ROUND(v4_score, 4) as v4_score,
    v4_percentile,
    is_v4_upgrade,
    CASE 
        WHEN is_v4_upgrade = 1 THEN 'V4 Upgrade (STANDARD with V4 >= 80%)'
        ELSE 'V3 Tier Qualified'
    END as v4_status,
    shap_top1_feature,
    shap_top2_feature,
    shap_top3_feature,
    
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

---

## Cursor Prompt 2.2: Run the Updated SQL

```
@workspace Execute the updated lead list SQL with firm exclusions and job titles.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Prerequisites:
- sql/January_2026_Lead_List_V3_V4_Hybrid.sql has been replaced with new version
- ml_features.v4_prospect_scores has SHAP columns (from Step 1)

Task:
1. Execute sql/January_2026_Lead_List_V3_V4_Hybrid.sql via MCP BigQuery
2. Verify output includes:
   - job_title column
   - score_narrative column (V3 or V4 based)
   - No leads from Savvy (CRD 318493) or Ritholtz (CRD 168652)
3. Log results to logs/EXECUTION_LOG.md

Validation queries:

-- Check no Savvy or Ritholtz leads
SELECT firm_crd, firm_name, COUNT(*) 
FROM ml_features.january_2026_lead_list_v4
WHERE firm_crd IN (318493, 168652)
   OR UPPER(firm_name) LIKE '%SAVVY%'
   OR UPPER(firm_name) LIKE '%RITHOLTZ%'
GROUP BY 1, 2;
-- Should return 0 rows

-- Check job_title coverage
SELECT 
    COUNT(*) as total,
    COUNTIF(job_title IS NOT NULL) as has_job_title,
    ROUND(COUNTIF(job_title IS NOT NULL) * 100.0 / COUNT(*), 1) as pct
FROM ml_features.january_2026_lead_list_v4;

-- Check narrative coverage
SELECT 
    score_tier,
    is_v4_upgrade,
    COUNT(*) as count,
    COUNTIF(score_narrative IS NOT NULL) as has_narrative
FROM ml_features.january_2026_lead_list_v4
GROUP BY 1, 2
ORDER BY count DESC;
```

---

# STEP 3: Update Export Script

## Cursor Prompt 3.1: Update Export Script

```
@workspace Update the export script to include job_title and score_narrative columns.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Task:
1. Update scripts/export_lead_list.py to include new columns:
   - job_title
   - score_narrative
   - shap_top1_feature, shap_top2_feature, shap_top3_feature
2. Update EXPORT_COLUMNS list
3. Update validation to check job_title and narrative coverage
```

## Code: export_lead_list.py (Updated)

```python
"""
Export lead list from BigQuery to CSV for Salesforce import.

UPDATED: Includes job_title and score_narrative columns

Working Directory: Lead_List_Generation
Usage: python scripts/export_lead_list.py
"""

import pandas as pd
from pathlib import Path
from google.cloud import bigquery
from datetime import datetime
import sys

# ============================================================================
# PATH CONFIGURATION
# ============================================================================
WORKING_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation")
EXPORTS_DIR = WORKING_DIR / "exports"
LOGS_DIR = WORKING_DIR / "logs"

EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
LOGS_DIR.mkdir(parents=True, exist_ok=True)

# ============================================================================
# BIGQUERY CONFIGURATION
# ============================================================================
PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
TABLE_NAME = "january_2026_lead_list_v4"

# ============================================================================
# EXPORT COLUMNS (UPDATED - includes job_title, score_narrative)
# ============================================================================
EXPORT_COLUMNS = [
    'advisor_crd',
    'salesforce_lead_id',
    'first_name',
    'last_name',
    'job_title',                # NEW!
    'email',
    'phone',
    'linkedin_url',
    'firm_name',
    'firm_crd',
    'score_tier',
    'original_v3_tier',
    'expected_rate_pct',
    'score_narrative',          # NEW!
    'v4_score',
    'v4_percentile',
    'is_v4_upgrade',
    'v4_status',
    'shap_top1_feature',        # NEW!
    'shap_top2_feature',        # NEW!
    'shap_top3_feature',        # NEW!
    'prospect_type',
    'list_rank'
]


def fetch_lead_list(client):
    """Fetch lead list from BigQuery."""
    query = f"""
    SELECT *
    FROM `{PROJECT_ID}.{DATASET}.{TABLE_NAME}`
    ORDER BY list_rank
    """
    
    print(f"[INFO] Fetching lead list from {TABLE_NAME}...")
    df = client.query(query).to_dataframe()
    print(f"[INFO] Loaded {len(df):,} leads")
    return df


def validate_export(df):
    """Validate the exported data."""
    print("\n" + "=" * 70)
    print("VALIDATION CHECKS")
    print("=" * 70)
    
    validation_results = {
        "row_count": len(df),
        "expected_rows": 2400,
        "duplicate_crds": df['advisor_crd'].duplicated().sum(),
        "has_job_title": df['job_title'].notna().sum() if 'job_title' in df.columns else 0,
        "has_narrative": df['score_narrative'].notna().sum() if 'score_narrative' in df.columns else 0,
        "has_linkedin": (df['linkedin_url'].notna() & (df['linkedin_url'] != '')).sum(),
        "v4_upgrade_count": df['is_v4_upgrade'].sum() if 'is_v4_upgrade' in df.columns else 0,
    }
    
    validation_results['job_title_pct'] = validation_results['has_job_title'] / len(df) * 100 if len(df) > 0 else 0
    validation_results['narrative_pct'] = validation_results['has_narrative'] / len(df) * 100 if len(df) > 0 else 0
    validation_results['linkedin_pct'] = validation_results['has_linkedin'] / len(df) * 100 if len(df) > 0 else 0
    validation_results['v4_upgrade_pct'] = validation_results['v4_upgrade_count'] / len(df) * 100 if len(df) > 0 else 0
    
    print(f"Row Count: {validation_results['row_count']:,}")
    print(f"Duplicate CRDs: {validation_results['duplicate_crds']}")
    
    print(f"\nJob Title Coverage: {validation_results['has_job_title']:,} ({validation_results['job_title_pct']:.1f}%)")
    print(f"Narrative Coverage: {validation_results['has_narrative']:,} ({validation_results['narrative_pct']:.1f}%)")
    print(f"LinkedIn Coverage: {validation_results['has_linkedin']:,} ({validation_results['linkedin_pct']:.1f}%)")
    
    print(f"\nV4 Upgrades: {validation_results['v4_upgrade_count']:,} ({validation_results['v4_upgrade_pct']:.1f}%)")
    
    # Check for excluded firms
    savvy_count = len(df[df['firm_crd'] == 318493]) if 'firm_crd' in df.columns else 0
    ritholtz_count = len(df[df['firm_crd'] == 168652]) if 'firm_crd' in df.columns else 0
    
    print(f"\nExcluded Firm Check:")
    print(f"  Savvy (CRD 318493): {savvy_count} {'✅' if savvy_count == 0 else '❌'}")
    print(f"  Ritholtz (CRD 168652): {ritholtz_count} {'✅' if ritholtz_count == 0 else '❌'}")
    
    # Tier distribution
    print(f"\nTier Distribution:")
    if 'score_tier' in df.columns:
        tier_dist = df['score_tier'].value_counts().sort_index()
        for tier, count in tier_dist.items():
            pct = count / len(df) * 100
            print(f"  {tier}: {count:,} ({pct:.1f}%)")
    
    print("=" * 70 + "\n")
    
    return validation_results


def export_to_csv(df, output_path):
    """Export DataFrame to CSV."""
    print(f"[INFO] Exporting to {output_path}...")
    
    available_cols = [c for c in EXPORT_COLUMNS if c in df.columns]
    df_export = df[available_cols].copy()
    
    df_export.to_csv(output_path, index=False, encoding='utf-8')
    
    file_size = output_path.stat().st_size / 1024
    print(f"[INFO] Exported {len(df_export):,} rows to {output_path}")
    print(f"[INFO] File size: {file_size:.1f} KB")
    print(f"[INFO] Columns: {len(available_cols)}")
    
    return output_path


def main():
    print("=" * 70)
    print("EXPORT LEAD LIST TO CSV")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)
    
    client = bigquery.Client(project=PROJECT_ID)
    df = fetch_lead_list(client)
    validation_results = validate_export(df)
    
    timestamp = datetime.now().strftime('%Y%m%d')
    output_filename = f"january_2026_lead_list_{timestamp}.csv"
    output_path = EXPORTS_DIR / output_filename
    
    export_to_csv(df, output_path)
    
    print("\n" + "=" * 70)
    print("EXPORT COMPLETE")
    print("=" * 70)
    print(f"File: {output_path}")
    print(f"Rows: {len(df):,}")
    print(f"Includes: job_title, score_narrative, SHAP features")
    print("=" * 70)
    
    return output_path


if __name__ == "__main__":
    try:
        output_path = main()
        sys.exit(0)
    except Exception as e:
        print(f"\n[ERROR] Export failed: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
```

---

# STEP 4: Run Complete Pipeline

## Cursor Prompt 4.1: Run Full Pipeline

```
@workspace Run the complete January 2026 lead list generation pipeline with all upgrades.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Pipeline Steps:
1. [Already done] v4_prospect_features.sql - Feature table exists
2. [RE-RUN] python scripts/score_prospects_monthly.py - Add SHAP narratives
3. [RE-RUN] January_2026_Lead_List_V3_V4_Hybrid.sql - New version with exclusions
4. [RUN] python scripts/export_lead_list.py - Export with all new columns

Task:
1. Run Step 2: python scripts/score_prospects_monthly.py
   - Wait for SHAP calculation (5-15 minutes)
   - Verify v4_narrative column populated

2. Run Step 3: Execute SQL via MCP BigQuery
   - Verify no Savvy/Ritholtz leads
   - Verify job_title and score_narrative populated

3. Run Step 4: python scripts/export_lead_list.py
   - Export to exports/january_2026_lead_list_YYYYMMDD.csv

4. Log all results to logs/EXECUTION_LOG.md

Final validation:
- 2,400 leads exported
- 0 leads from Savvy (318493) or Ritholtz (168652)
- 100% narrative coverage
- ~95%+ job_title coverage
- V4_UPGRADE tier present (~300-500 leads)
```

---

# Summary of Changes

| Component | Change | Files Affected |
|-----------|--------|----------------|
| **SHAP Narratives** | Generate ML-based explanations for V4 upgrades | `score_prospects_monthly.py` |
| **Job Titles** | Include `job_title` column in output | `January_2026_Lead_List_V3_V4_Hybrid.sql`, `export_lead_list.py` |
| **Firm Exclusions** | Exclude Savvy (318493) and Ritholtz (168652) | `January_2026_Lead_List_V3_V4_Hybrid.sql` |

## New Columns in Output

| Column | Description | Source |
|--------|-------------|--------|
| `job_title` | Advisor's job title from FINTRX | FINTRX TITLE_NAME |
| `score_narrative` | Human-readable explanation | V3 rules OR V4 SHAP |
| `shap_top1_feature` | Most important ML feature | SHAP analysis |
| `shap_top2_feature` | Second most important | SHAP analysis |
| `shap_top3_feature` | Third most important | SHAP analysis |

## Firm Exclusions

| Firm | CRD | Reason |
|------|-----|--------|
| Savvy Advisors, Inc. | 318493 | Internal firm |
| Ritholtz Wealth Management | 168652 | Partner firm |

---

**Document Version**: 2.0  
**Created**: 2025-12-24  
**Working Directory**: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation`
