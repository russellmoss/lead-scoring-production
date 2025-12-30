# How to Get Scores for a List of CRDs

## Overview

The lead scoring system uses a **hybrid approach** with two components:

1. **V3 Rules-Based Model**: Computed **on-demand** in SQL queries (not pre-stored)
2. **V4 XGBoost ML Model**: **Pre-computed** and stored in BigQuery for all prospects

---

## What Gets Stored in BigQuery?

### ✅ Pre-Computed (Stored Tables)

| Table | Purpose | Coverage | Updated |
|-------|---------|----------|---------|
| `ml_features.v4_prospect_features` | V4 ML features for all prospects | ~285,690 prospects | Monthly (Step 1) |
| `ml_features.v4_prospect_scores` | V4 ML scores, percentiles, SHAP features | ~285,690 prospects | Monthly (Step 2) |

**V4 Scores Include:**
- `crd`: Advisor CRD ID
- `v4_score`: Raw ML prediction (0-1)
- `v4_percentile`: Percentile rank (1-100)
- `v4_deprioritize`: Boolean (TRUE if percentile ≤ 20)
- `v4_upgrade_candidate`: Boolean (TRUE if percentile ≥ 80)
- `shap_top1_feature`, `shap_top2_feature`, `shap_top3_feature`: Top 3 ML features
- `shap_top1_value`, `shap_top2_value`, `shap_top3_value`: SHAP values
- `v4_narrative`: Human-readable explanation

### ❌ NOT Pre-Computed (Computed On-Demand)

- **V3 Tier Assignments**: Computed in SQL queries using business rules
- **V3 Tier Names**: `TIER_1A_PRIME_MOVER_CFP`, `TIER_1B_PRIME_MOVER_SERIES65`, `TIER_1_PRIME_MOVER`, `TIER_1F_HV_WEALTH_BLEEDER`, `TIER_2_PROVEN_MOVER`, `TIER_3_MODERATE_BLEEDER`, `STANDARD`
- **V3 Narratives**: Generated on-the-fly based on tier rules

**Why V3 isn't stored?**
- V3 is rules-based (transparent SQL logic)
- No ML model to run - just business rules
- Can be computed instantly from FINTRX data
- Storing would duplicate data unnecessarily

---

## How to Get Scores for Your List of CRDs

### Option 1: Query V4 Scores Only (Fastest)

If you just need V4 ML scores:

```sql
-- Get V4 scores for your list of CRDs
SELECT 
  v4.crd,
  v4.v4_score,
  v4.v4_percentile,
  v4.v4_deprioritize,
  v4.v4_upgrade_candidate,
  v4.shap_top1_feature,
  v4.shap_top2_feature,
  v4.shap_top3_feature,
  v4.v4_narrative
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4
WHERE v4.crd IN (
  -- Your list of CRDs here
  1234567,
  2345678,
  3456789
  -- ... etc
)
ORDER BY v4.v4_percentile DESC;
```

### Option 2: Get V4 Scores + V3 Tiers (Complete Scoring)

If you need both V4 scores AND V3 tier assignments, you have two options:

#### Option 2A: Use the Lead List Query Logic

The lead list query (`January_2026_Lead_List_V3_V4_Hybrid.sql`) computes V3 tiers on-demand. You can modify it to filter by your CRD list:

```sql
-- Modified version: Get scores for specific CRDs
WITH your_crd_list AS (
  SELECT crd FROM UNNEST([
    1234567,
    2345678,
    3456789
    -- ... your CRDs
  ]) as crd
),
-- ... [rest of the lead list query logic]
-- Add WHERE clause: WHERE base_prospects.advisor_crd IN (SELECT crd FROM your_crd_list)
```

#### Option 2B: Create a Simple V3 Tier Query

Create a simplified query that just computes V3 tiers for your CRDs:

```sql
-- Get V3 tiers for your list of CRDs
WITH your_crds AS (
  SELECT crd FROM UNNEST([
    1234567,
    2345678,
    3456789
    -- ... your CRDs
  ]) as crd
),
advisor_data AS (
  SELECT 
    r.RIA_CONTACT_CRD_ID as crd,
    r.PRIMARY_FIRM_NAME as firm_name,
    r.PRIMARY_FIRM as firm_crd,
    -- Add other fields you need
    r.TITLE_NAME as job_title,
    r.EMAIL,
    r.LINKEDIN_PROFILE_URL as linkedin_url
  FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` r
  INNER JOIN your_crds y ON r.RIA_CONTACT_CRD_ID = y.crd
  WHERE r.PRODUCING_ADVISOR = TRUE
),
-- Add V3 tier logic here (simplified version)
-- See January_2026_Lead_List_V3_V4_Hybrid.sql for full logic
v3_tiers AS (
  SELECT 
    crd,
    -- Simplified tier assignment (see full query for complete logic)
    CASE 
      WHEN -- T1B logic
        THEN 'TIER_1B_PRIME_MOVER_SERIES65'
      WHEN -- T1A logic
        THEN 'TIER_1A_PRIME_MOVER_CFP'
      -- ... etc
      ELSE 'STANDARD'
    END as v3_tier
  FROM advisor_data
)
SELECT 
  a.*,
  v3.v3_tier,
  v4.v4_score,
  v4.v4_percentile,
  v4.v4_deprioritize
FROM advisor_data a
LEFT JOIN v3_tiers v3 ON a.crd = v3.crd
LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 ON a.crd = v4.crd
ORDER BY v4.v4_percentile DESC;
```

### Option 3: Use Python Script (Recommended for Large Lists)

If you have a large list of CRDs (CSV file, etc.), use Python:

```python
"""
Get scores for a list of CRDs from a CSV file
"""
import pandas as pd
from google.cloud import bigquery

PROJECT_ID = "savvy-gtm-analytics"

# Load your CRD list
your_crds_df = pd.read_csv('your_crd_list.csv')  # Should have 'crd' column
your_crds = your_crds_df['crd'].tolist()

# Query V4 scores
client = bigquery.Client(project=PROJECT_ID)

query = f"""
SELECT 
  v4.crd,
  v4.v4_score,
  v4.v4_percentile,
  v4.v4_deprioritize,
  v4.v4_upgrade_candidate,
  v4.shap_top1_feature,
  v4.shap_top2_feature,
  v4.shap_top3_feature,
  v4.v4_narrative
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4
WHERE v4.crd IN ({','.join(map(str, your_crds))})
ORDER BY v4.v4_percentile DESC
"""

v4_scores = client.query(query).to_dataframe()

# Merge with your original data
result = your_crds_df.merge(v4_scores, on='crd', how='left')

# Save results
result.to_csv('scored_crds.csv', index=False)
print(f"Scored {len(result)} CRDs")
```

---

## When Are Scores Updated?

### Monthly Pipeline (Automatic)

1. **Step 1**: Calculate V4 features for all prospects
   - Creates/updates: `ml_features.v4_prospect_features`
   - Runs: SQL query `v4_prospect_features.sql`
   - Coverage: All producing advisors in FINTRX (~285,690)

2. **Step 2**: Score prospects with V4 model
   - Creates/updates: `ml_features.v4_prospect_scores`
   - Runs: Python script `score_prospects_monthly.py`
   - Coverage: All prospects with features (~285,690)

3. **Step 3**: Generate lead list (uses pre-computed scores)
   - Creates: `ml_features.january_2026_lead_list_v4` (or current month)
   - Runs: SQL query `January_2026_Lead_List_V3_V4_Hybrid.sql`
   - Uses: Pre-computed V4 scores + on-demand V3 tiers

### Manual Refresh

If you need to refresh scores for new prospects:

```bash
# Step 1: Recalculate features (includes new prospects)
# Run in BigQuery: pipeline/sql/v4_prospect_features.sql

# Step 2: Re-score all prospects
cd pipeline
python scripts/score_prospects_monthly.py
```

**Note**: This re-scores ALL prospects (~285,690), not just new ones. The script is designed to be idempotent (safe to run multiple times).

---

## What If a CRD Isn't in the Scores Table?

### Possible Reasons:

1. **Not a producing advisor**: V4 only scores `PRODUCING_ADVISOR = TRUE`
2. **Missing features**: Some prospects may not have all required features
3. **New prospect**: Added to FINTRX after last monthly scoring run

### Solution:

1. **Check if prospect exists in FINTRX**:
```sql
SELECT 
  RIA_CONTACT_CRD_ID,
  PRODUCING_ADVISOR,
  PRIMARY_FIRM_NAME
FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
WHERE RIA_CONTACT_CRD_ID = [YOUR_CRD];
```

2. **Check if features exist**:
```sql
SELECT *
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`
WHERE crd = [YOUR_CRD];
```

3. **If missing, run monthly pipeline** (Step 1 + Step 2) to include new prospects

---

## Quick Reference: Table Schemas

### `ml_features.v4_prospect_scores`

| Column | Type | Description |
|--------|------|-------------|
| `crd` | INT64 | Advisor CRD ID (primary key) |
| `v4_score` | FLOAT64 | Raw ML prediction (0-1) |
| `v4_percentile` | FLOAT64 | Percentile rank (1-100) |
| `v4_deprioritize` | BOOL | TRUE if percentile ≤ 20 |
| `v4_upgrade_candidate` | BOOL | TRUE if percentile ≥ 80 |
| `shap_top1_feature` | STRING | Most important ML feature |
| `shap_top1_value` | FLOAT64 | SHAP value for top feature |
| `shap_top2_feature` | STRING | Second most important feature |
| `shap_top2_value` | FLOAT64 | SHAP value for second feature |
| `shap_top3_feature` | STRING | Third most important feature |
| `shap_top3_value` | FLOAT64 | SHAP value for third feature |
| `v4_narrative` | STRING | Human-readable explanation |

### V3 Tiers (Computed On-Demand)

| Tier | Description | Expected Conversion |
|------|-------------|---------------------|
| `TIER_1A_PRIME_MOVER_CFP` | CFP + Prime Mover criteria | ~10%+ |
| `TIER_1B_PRIME_MOVER_SERIES65` | Series 65 only + Prime Mover | 11.76% |
| `TIER_1_PRIME_MOVER` | Prime Mover (general) | 4.76% |
| `TIER_1F_HV_WEALTH_BLEEDER` | High-value wealth title + bleeding firm | 6.06% |
| `TIER_2_PROVEN_MOVER` | 3+ prior firms + 5+yr experience | 5.91% |
| `TIER_3_MODERATE_BLEEDER` | Firm losing 1-10 advisors | 6.76% |
| `STANDARD` | All other leads | 2.60% |

---

## Example: Complete Scoring Query

Here's a complete example that gets both V4 scores and V3 tiers for a list of CRDs:

```sql
-- Complete scoring for a list of CRDs
WITH your_crd_list AS (
  SELECT crd FROM UNNEST([
    1234567,
    2345678,
    3456789
    -- Add your CRDs here
  ]) as crd
),
-- Get advisor data
advisor_data AS (
  SELECT 
    r.RIA_CONTACT_CRD_ID as crd,
    r.RIA_CONTACT_PREFERRED_NAME as advisor_name,
    r.PRIMARY_FIRM_NAME as firm_name,
    r.PRIMARY_FIRM as firm_crd,
    r.TITLE_NAME as job_title,
    r.EMAIL,
    r.LINKEDIN_PROFILE_URL as linkedin_url
  FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` r
  INNER JOIN your_crd_list y ON r.RIA_CONTACT_CRD_ID = y.crd
  WHERE r.PRODUCING_ADVISOR = TRUE
)
SELECT 
  a.*,
  v4.v4_score,
  v4.v4_percentile,
  v4.v4_deprioritize,
  v4.v4_upgrade_candidate,
  v4.v4_narrative as v4_explanation,
  -- V3 tier would need full tier logic (see lead list query)
  -- For now, just get V4 scores
  'STANDARD' as v3_tier_placeholder  -- Replace with actual V3 logic
FROM advisor_data a
LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 
  ON a.crd = v4.crd
ORDER BY v4.v4_percentile DESC NULLS LAST;
```

---

## Summary

- **V4 Scores**: ✅ Pre-computed and stored in `ml_features.v4_prospect_scores` (~285,690 prospects)
- **V3 Tiers**: ❌ Computed on-demand in SQL queries (not stored)
- **To get scores**: Join your CRD list to `ml_features.v4_prospect_scores`
- **To get V3 tiers**: Use the tier logic from `January_2026_Lead_List_V3_V4_Hybrid.sql` or compute on-demand
- **Monthly updates**: Scores are refreshed monthly via the pipeline (Steps 1-2)

**Quick Answer**: If you have a list of CRDs, just join to `ml_features.v4_prospect_scores` to get V4 scores. For V3 tiers, you'll need to run the tier assignment logic (or use the lead list query as a template).

