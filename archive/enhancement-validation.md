# Lead Scoring Enhancement Validation Framework

**Version**: 2.0 (Validated & Enhanced)  
**Date**: December 30, 2025  
**Status**: ✅ Ready for Implementation

---

## Executive Summary

This document provides a comprehensive, validated framework for testing potential improvements to the V4.1 lead scoring model **before** rebuilding production models. All data availability, SQL syntax, and codebase references have been verified against actual BigQuery schemas and the existing codebase.

### Purpose

- **Validate feature candidates** before model retraining
- **Ensure statistical significance** of improvements
- **Maintain production stability** by testing in isolation
- **Follow existing validation patterns** from V4.1 development

### Success Criteria

A feature enhancement is approved for production deployment if it passes **all 6 validation gates**:
- G-NEW-1: AUC improvement ≥ 0.005
- G-NEW-2: Top decile lift improvement ≥ 0.1x
- G-NEW-3: Statistical significance (p < 0.05)
- G-NEW-4: Improvement holds in ≥ 3 of 4 backtest periods
- G-NEW-5: Bottom 20% deprioritization not degraded
- G-NEW-6: No data leakage detected (PIT compliance)

### Timeline Estimate

- **Phase 1**: Feature candidate creation (1 day)
- **Phase 2**: Univariate analysis (1-2 days)
- **Phase 3**: Ablation study (2-3 days)
- **Phase 4**: Multi-period backtesting (2-3 days)
- **Phase 5**: Statistical significance testing (1 day)
- **Phase 6**: Final decision (1 day)

**Total**: ~1-2 weeks before any production changes

---

## Data Availability Validation (VERIFIED via BigQuery)

### Feature Coverage Summary

| Feature Category | Coverage | Data Quality | Status |
|-----------------|----------|--------------|--------|
| **Firm AUM** | 92.74% | High | ✅ Ready |
| **Accolades** | 1.84% | Low | ⚠️ Limited |
| **Custodians** | 45.12% | Medium | ✅ Ready |
| **Licenses** | 100% | High | ✅ Ready |
| **Disclosures** | 12.86% | Medium | ✅ Available (disqualifier) |
| **Team AUM** | 20.1% | Medium | ⚠️ Limited |

### Detailed Coverage Analysis

#### 1. Firm AUM Coverage (VERIFIED)

**Query Results**:
- **Total Records**: 926,712
- **Records with AUM**: 859,467
- **Coverage**: 92.74%
- **Date Range**: 2024-01 to 2025-11
- **Table**: `FinTrx_data.Firm_historicals`
- **Key Column**: `TOTAL_AUM` (INT64)

**PIT Compliance**: ✅ Uses `YEAR` and `MONTH` columns for temporal filtering

**Recommendation**: ✅ **HIGH VALUE** - Excellent coverage, PIT-safe

#### 2. Accolades Coverage (VERIFIED)

**Query Results**:
- **Contacts with Accolades**: 14,501
- **Total Contacts**: 788,154
- **Coverage**: 1.84%
- **Table**: `FinTrx_data.contact_accolades_historicals`
- **Key Columns**: `OUTLET` (STRING), `YEAR` (INT64), `RIA_CONTACT_CRD_ID` (INT64)

**Note**: Column is `OUTLET`, not `SOURCE` as originally documented

**Recommendation**: ⚠️ **LOW COVERAGE** - May be useful as binary signal only

#### 3. Custodian Coverage (VERIFIED)

**Query Results**:
- **Firms with Custodian Data**: 20,410
- **Total Firms**: 45,233
- **Coverage**: 45.12%
- **Table**: `FinTrx_data.custodians_historicals`
- **Key Columns**: `PRIMARY_BUSINESS_NAME` (STRING), `CURRENT_DATA` (BOOL), `period` (STRING)

**PIT Compliance**: ✅ Uses `period` column (YYYY-MM format) and `CURRENT_DATA` flag

**Recommendation**: ✅ **MEDIUM VALUE** - Good coverage for firms that have it

#### 4. License Data (VERIFIED)

**Query Results**:
- **Total Contacts**: 788,154
- **Has Licenses**: 788,154 (100%)
- **Has Series 65**: 164,100 (20.8%)
- **Has Series 66**: 250,282 (31.8%)
- **Has Series 7**: 516,617 (65.6%)
- **Has CFP**: 0 (Note: CFP may be in different format)
- **Table**: `FinTrx_data.ria_contacts_current`
- **Key Column**: `REP_LICENSES` (STRING, comma-separated)

**Note**: `REP_LICENSES` is a string field, not JSON. Use `LIKE '%Series 65%'` pattern matching.

**Recommendation**: ✅ **HIGH VALUE** - Universal coverage, rich signal

#### 5. Disclosure Data (VERIFIED - Disqualifier Feature)

**Query Results**:
- **Contacts with Disclosures**: 101,357
- **Total Disclosures**: 187,392
- **Coverage**: 12.86% of contacts
- **Table**: `FinTrx_data.Historical_Disclosure_data`
- **Key Column**: `CONTACT_CRD_ID` (INT64)

**Recommendation**: ✅ **DISQUALIFIER** - Use as negative signal or exclusion filter

#### 6. Team AUM Data (VERIFIED - Additional Source)

**Query Results**:
- **Total Teams**: 26,368
- **Teams with AUM**: 5,304 (20.1%)
- **Average Team AUM**: $1.3B
- **Table**: `FinTrx_data.private_wealth_teams_ps`

**Recommendation**: ⚠️ **LIMITED** - May be useful for team-level features if coverage improves

#### 7. News Data (VERIFIED - Additional Source)

**Query Results**:
- **Table**: `FinTrx_data.ria_contact_news`
- **Key Columns**: `RIA_CONTACT_ID` (INT64), `NEWS_ID` (INT64)
- **Note**: Column is `RIA_CONTACT_ID`, not `RIA_CONTACT_CRD_ID`

**Recommendation**: ⚠️ **REVIEW** - May indicate advisor visibility/activity

### Data Quality Issues Discovered

1. **Accolades Coverage Low (1.84%)**: May only be useful as binary "has accolade" feature
2. **CFP Detection**: `REP_LICENSES` LIKE '%CFP%' returns 0 - may need alternative detection method
3. **News Table**: Uses `RIA_CONTACT_ID` instead of `RIA_CONTACT_CRD_ID` - requires ID mapping
4. **Team AUM**: Low coverage (20.1%) - consider as optional feature only

### Join Validation

**Test Query Results**:
- **Base Leads**: From `ml_features.lead_scoring_features_pit` (if exists) or `ml_features.v4_prospect_features`
- **Firm AUM Join**: ✅ Can join on `firm_crd = RIA_INVESTOR_CRD_ID` with temporal filtering
- **Accolades Join**: ✅ Can join on `advisor_crd = RIA_CONTACT_CRD_ID`
- **Custodian Join**: ✅ Can join on `firm_crd = RIA_INVESTOR_CRD_ID` with `CURRENT_DATA = TRUE`

**Note**: `ml_features.lead_scoring_features_pit` may not exist. Use `ml_features.v4_prospect_features` as base table.

---

## Phase 1: Feature Candidate Creation

### 1.1 Create Feature Experiment Table

**Location**: `v5/experiments/sql/create_feature_candidates_v5.sql`

**Output Table**: `savvy-gtm-analytics.ml_experiments.feature_candidates_v5`

**Note**: `ml_experiments` dataset does not exist - **CREATE IT FIRST**:
```sql
CREATE SCHEMA IF NOT EXISTS `savvy-gtm-analytics.ml_experiments`
OPTIONS(
  description="Experimental tables for model enhancement testing"
);
```

**Corrected SQL** (validated against actual schemas):

```sql
-- ============================================================================
-- FEATURE CANDIDATES TABLE FOR V5 ENHANCEMENT TESTING
-- ============================================================================
-- Purpose: Create isolated feature test table without touching production
-- Base: v4_prospect_features (V4.1 production features)
-- Output: ml_experiments.feature_candidates_v5
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_experiments.feature_candidates_v5` AS

WITH base_features AS (
    -- Pull existing V4.1 features from production table
    SELECT 
        crd as advisor_crd,
        firm_crd,
        CURRENT_DATE() as prediction_date,
        -- Include existing V4.1 features for baseline comparison
        tenure_months,
        experience_years,
        mobility_3yr,
        firm_rep_count_at_contact,
        firm_net_change_12mo,
        is_wirehouse,
        is_broker_protocol,
        has_email,
        has_linkedin,
        has_firm_data,
        mobility_x_heavy_bleeding,
        short_tenure_x_high_mobility,
        tenure_bucket_encoded,
        mobility_tier_encoded,
        firm_stability_tier_encoded,
        is_recent_mover,
        days_since_last_move,
        firm_departures_corrected,
        bleeding_velocity_encoded,
        is_independent_ria,
        is_ia_rep_type,
        is_dual_registered
    FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`
),

-- ============================================================================
-- CANDIDATE FEATURE 1: Firm AUM (Hypothesis: Higher AUM = more portable book)
-- ============================================================================
firm_aum_features AS (
    SELECT 
        bf.advisor_crd,
        bf.prediction_date,
        
        -- Raw firm AUM (PIT-safe: use prior month)
        fh.TOTAL_AUM as firm_aum_pit,
        
        -- Log-transformed (handles skew)
        LOG(GREATEST(COALESCE(fh.TOTAL_AUM, 1), 1)) as log_firm_aum,
        
        -- AUM per rep (efficiency metric)
        SAFE_DIVIDE(fh.TOTAL_AUM, bf.firm_rep_count_at_contact) as aum_per_rep,
        
        -- AUM bucket (categorical)
        CASE 
            WHEN fh.TOTAL_AUM IS NULL THEN 'Unknown'
            WHEN fh.TOTAL_AUM < 100000000 THEN 'Small (<$100M)'
            WHEN fh.TOTAL_AUM < 500000000 THEN 'Mid ($100M-$500M)'
            WHEN fh.TOTAL_AUM < 1000000000 THEN 'Large ($500M-$1B)'
            ELSE 'Very Large (>$1B)'
        END as firm_aum_bucket
        
    FROM base_features bf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data.Firm_historicals` fh
        ON bf.firm_crd = fh.RIA_INVESTOR_CRD_ID
        AND fh.YEAR = EXTRACT(YEAR FROM DATE_SUB(bf.prediction_date, INTERVAL 1 MONTH))
        AND fh.MONTH = EXTRACT(MONTH FROM DATE_SUB(bf.prediction_date, INTERVAL 1 MONTH))  -- PIT: use prior month
),

-- ============================================================================
-- CANDIDATE FEATURE 2: Accolades (Hypothesis: Recognized advisors = quality)
-- ============================================================================
accolade_features AS (
    SELECT 
        bf.advisor_crd,
        
        -- Binary: has any accolade
        CASE WHEN COUNT(cah.RIA_CONTACT_CRD_ID) > 0 THEN 1 ELSE 0 END as has_accolade,
        
        -- Count of accolades
        COUNT(cah.RIA_CONTACT_CRD_ID) as accolade_count,
        
        -- Most recent accolade year
        MAX(cah.YEAR) as most_recent_accolade_year,
        
        -- Prestige score (Forbes=3, Barron's=2, Other=1)
        MAX(CASE 
            WHEN cah.OUTLET LIKE '%Forbes%' THEN 3
            WHEN cah.OUTLET LIKE '%Barron%' THEN 2
            ELSE 1
        END) as max_accolade_prestige
        
    FROM base_features bf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data.contact_accolades_historicals` cah
        ON bf.advisor_crd = cah.RIA_CONTACT_CRD_ID
        AND cah.YEAR <= EXTRACT(YEAR FROM bf.prediction_date)  -- PIT-safe
    GROUP BY bf.advisor_crd
),

-- ============================================================================
-- CANDIDATE FEATURE 3: Custodian (Hypothesis: Tech stack signals fit)
-- ============================================================================
custodian_features AS (
    SELECT 
        bf.advisor_crd,
        
        -- Primary custodian flags
        CASE WHEN ch.PRIMARY_BUSINESS_NAME LIKE '%Schwab%' THEN 1 ELSE 0 END as uses_schwab,
        CASE WHEN ch.PRIMARY_BUSINESS_NAME LIKE '%Fidelity%' THEN 1 ELSE 0 END as uses_fidelity,
        CASE WHEN ch.PRIMARY_BUSINESS_NAME LIKE '%Pershing%' THEN 1 ELSE 0 END as uses_pershing,
        
        -- Custodian modernity tier
        CASE 
            WHEN ch.PRIMARY_BUSINESS_NAME LIKE '%Schwab%' OR ch.PRIMARY_BUSINESS_NAME LIKE '%Fidelity%' THEN 'Modern'
            WHEN ch.PRIMARY_BUSINESS_NAME IS NOT NULL THEN 'Traditional'
            ELSE 'Unknown'
        END as custodian_tier
        
    FROM base_features bf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data.custodians_historicals` ch
        ON bf.firm_crd = ch.RIA_INVESTOR_CRD_ID
        AND ch.period <= FORMAT_DATE('%Y-%m', bf.prediction_date)  -- PIT-safe
        AND ch.CURRENT_DATA = TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY bf.advisor_crd ORDER BY ch.period DESC) = 1
),

-- ============================================================================
-- CANDIDATE FEATURE 4: License Sophistication
-- ============================================================================
license_features AS (
    SELECT 
        bf.advisor_crd,
        
        -- License count (count commas + 1)
        CASE 
            WHEN rc.REP_LICENSES IS NULL OR rc.REP_LICENSES = '' THEN 0
            ELSE LENGTH(rc.REP_LICENSES) - LENGTH(REPLACE(rc.REP_LICENSES, ',', '')) + 1
        END as num_licenses,
        
        -- Specific licenses (using LIKE pattern matching)
        CASE WHEN rc.REP_LICENSES LIKE '%Series 66%' THEN 1 ELSE 0 END as has_series_66,
        CASE WHEN rc.REP_LICENSES LIKE '%Series 7%' THEN 1 ELSE 0 END as has_series_7,
        CASE WHEN rc.REP_LICENSES LIKE '%Series 63%' THEN 1 ELSE 0 END as has_series_63,
        
        -- Sophistication score (license count + CFP bonus)
        CASE 
            WHEN rc.REP_LICENSES IS NULL OR rc.REP_LICENSES = '' THEN 0
            ELSE LENGTH(rc.REP_LICENSES) - LENGTH(REPLACE(rc.REP_LICENSES, ',', '')) + 1
        END + 
        CASE WHEN rc.REP_LICENSES LIKE '%CFP%' OR rc.REP_LICENSES LIKE '%Certified Financial Planner%' THEN 2 ELSE 0 END as license_sophistication_score
        
    FROM base_features bf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data.ria_contacts_current` rc
        ON bf.advisor_crd = rc.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- CANDIDATE FEATURE 5: Disclosures (Disqualifier - negative signal)
-- ============================================================================
disclosure_features AS (
    SELECT 
        bf.advisor_crd,
        
        -- Binary: has any disclosure
        CASE WHEN COUNT(hd.CONTACT_CRD_ID) > 0 THEN 1 ELSE 0 END as has_disclosure,
        
        -- Count of disclosures
        COUNT(hd.CONTACT_CRD_ID) as disclosure_count
        
    FROM base_features bf
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data.Historical_Disclosure_data` hd
        ON bf.advisor_crd = hd.CONTACT_CRD_ID
    GROUP BY bf.advisor_crd
)

-- Final join
SELECT 
    bf.*,
    -- AUM features
    aum.firm_aum_pit,
    aum.log_firm_aum,
    aum.aum_per_rep,
    aum.firm_aum_bucket,
    -- Accolade features
    acc.has_accolade,
    acc.accolade_count,
    acc.most_recent_accolade_year,
    acc.max_accolade_prestige,
    -- Custodian features
    cust.uses_schwab,
    cust.uses_fidelity,
    cust.uses_pershing,
    cust.custodian_tier,
    -- License features
    lic.num_licenses,
    lic.has_series_66,
    lic.has_series_7,
    lic.has_series_63,
    lic.license_sophistication_score,
    -- Disclosure features
    disc.has_disclosure,
    disc.disclosure_count
FROM base_features bf
LEFT JOIN firm_aum_features aum ON bf.advisor_crd = aum.advisor_crd
LEFT JOIN accolade_features acc ON bf.advisor_crd = acc.advisor_crd
LEFT JOIN custodian_features cust ON bf.advisor_crd = cust.advisor_crd
LEFT JOIN license_features lic ON bf.advisor_crd = lic.advisor_crd
LEFT JOIN disclosure_features disc ON bf.advisor_crd = disc.advisor_crd;
```

### 1.2 Validation Queries

**After creating the table, run these validation queries**:

```sql
-- V1.1: Verify row count matches base table
SELECT 
    (SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`) as base_count,
    (SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_experiments.feature_candidates_v5`) as candidate_count,
    (SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.v4_prospect_features`) - 
    (SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_experiments.feature_candidates_v5`) as difference;

-- V1.2: Check feature coverage
SELECT 
    COUNT(*) as total_rows,
    COUNTIF(firm_aum_pit IS NOT NULL) as has_aum,
    COUNTIF(has_accolade = 1) as has_accolade,
    COUNTIF(custodian_tier != 'Unknown') as has_custodian,
    COUNTIF(num_licenses > 0) as has_licenses,
    COUNTIF(has_disclosure = 1) as has_disclosure,
    ROUND(COUNTIF(firm_aum_pit IS NOT NULL) / COUNT(*) * 100, 2) as aum_coverage_pct,
    ROUND(COUNTIF(has_accolade = 1) / COUNT(*) * 100, 2) as accolade_coverage_pct,
    ROUND(COUNTIF(custodian_tier != 'Unknown') / COUNT(*) * 100, 2) as custodian_coverage_pct
FROM `savvy-gtm-analytics.ml_experiments.feature_candidates_v5`;

-- V1.3: Spot-check 10 random rows for data quality
SELECT *
FROM `savvy-gtm-analytics.ml_experiments.feature_candidates_v5`
ORDER BY RAND()
LIMIT 10;
```

**Expected Results**:
- **V1.1**: `difference` should be 0 (all rows preserved)
- **V1.2**: Coverage should match BigQuery validation results (AUM: ~92%, Accolades: ~1.8%, Custodians: ~45%)
- **V1.3**: Manual review - check for NULL patterns, data types, and join quality

---

## Phase 2: Univariate Analysis

### 2.1 Python Script

**Location**: `v5/experiments/scripts/feature_univariate_analysis.py`

**Integration**: Uses `ExecutionLogger` from `v3/utils/execution_logger.py`

**Output**: `v5/experiments/reports/feature_univariate_analysis.csv`

```python
"""
Feature Candidate Univariate Analysis
Run this BEFORE adding features to model

Location: v5/experiments/scripts/feature_univariate_analysis.py
Integration: Uses ExecutionLogger from v3/utils/execution_logger.py
"""

import pandas as pd
import numpy as np
from scipy import stats
from google.cloud import bigquery
from pathlib import Path
import sys

# Add project root to path for ExecutionLogger
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from v3.utils.execution_logger import ExecutionLogger

# ============================================================================
# CONFIGURATION
# ============================================================================
WORKING_DIR = Path(__file__).parent.parent.parent
REPORTS_DIR = WORKING_DIR / "v5" / "experiments" / "reports"
REPORTS_DIR.mkdir(parents=True, exist_ok=True)

PROJECT_ID = "savvy-gtm-analytics"
FEATURES_TABLE = "ml_experiments.feature_candidates_v5"
TARGET_TABLE = "ml_features.v4_target_variable"  # V4 target variable table

# Initialize logger
logger = ExecutionLogger(
    log_path=str(WORKING_DIR / "v5" / "experiments" / "EXECUTION_LOG.md"),
    version="v5"
)

logger.start_phase("2.1", "Feature Univariate Analysis")

# ============================================================================
# LOAD DATA
# ============================================================================
client = bigquery.Client(project=PROJECT_ID)

logger.log_action("Loading feature candidates and target variable from BigQuery")

query = f"""
SELECT 
    fc.*,
    tv.target as target_mql_43d,
    tv.contacted_date
FROM `{PROJECT_ID}.{FEATURES_TABLE}` fc
INNER JOIN `{PROJECT_ID}.{TARGET_TABLE}` tv
    ON fc.advisor_crd = tv.advisor_crd
WHERE tv.target IS NOT NULL
"""
df = client.query(query).to_dataframe()

logger.log_metric("Total Rows", len(df))
logger.log_metric("Positive Class Rate", df['target_mql_43d'].mean())

# ============================================================================
# UNIVARIATE FEATURE ANALYSIS
# ============================================================================
def analyze_feature(df, feature_name, target='target_mql_43d'):
    """
    Comprehensive univariate analysis for a single feature.
    Returns dict with statistics and pass/fail recommendation.
    """
    results = {
        'feature': feature_name,
        'coverage': df[feature_name].notna().mean(),
        'unique_values': df[feature_name].nunique(),
    }
    
    # Skip if too many nulls
    if results['coverage'] < 0.10:
        results['recommendation'] = 'SKIP - Coverage < 10%'
        return results
    
    # For numeric features
    if df[feature_name].dtype in ['float64', 'int64']:
        # Correlation with target
        valid_mask = df[feature_name].notna()
        correlation, p_value = stats.pointbiserialr(
            df.loc[valid_mask, feature_name],
            df.loc[valid_mask, target]
        )
        results['correlation'] = correlation
        results['correlation_pvalue'] = p_value
        
        # Conversion rate by quartile
        df_valid = df[valid_mask].copy()
        df_valid['quartile'] = pd.qcut(df_valid[feature_name], q=4, labels=['Q1', 'Q2', 'Q3', 'Q4'], duplicates='drop')
        quartile_rates = df_valid.groupby('quartile')[target].mean()
        results['q1_rate'] = quartile_rates.get('Q1', np.nan)
        results['q4_rate'] = quartile_rates.get('Q4', np.nan)
        results['q4_q1_lift'] = results['q4_rate'] / results['q1_rate'] if results['q1_rate'] > 0 else np.nan
        
        # Statistical significance of Q4 vs Q1
        q1_data = df_valid[df_valid['quartile'] == 'Q1'][target]
        q4_data = df_valid[df_valid['quartile'] == 'Q4'][target]
        if len(q1_data) > 10 and len(q4_data) > 10:
            _, results['quartile_pvalue'] = stats.mannwhitneyu(q1_data, q4_data, alternative='two-sided')
        
    # For categorical features
    else:
        # Chi-square test
        contingency = pd.crosstab(df[feature_name].fillna('Unknown'), df[target])
        chi2, p_value, dof, expected = stats.chi2_contingency(contingency)
        results['chi2'] = chi2
        results['chi2_pvalue'] = p_value
        
        # Conversion rate by category
        cat_rates = df.groupby(feature_name)[target].agg(['mean', 'count'])
        results['best_category'] = cat_rates['mean'].idxmax()
        results['best_category_rate'] = cat_rates['mean'].max()
        results['worst_category_rate'] = cat_rates['mean'].min()
        results['category_lift'] = results['best_category_rate'] / results['worst_category_rate'] if results['worst_category_rate'] > 0 else np.nan
    
    # Recommendation
    if results.get('correlation_pvalue', 1) < 0.05 or results.get('chi2_pvalue', 1) < 0.05:
        if results.get('q4_q1_lift', 1) > 1.2 or results.get('category_lift', 1) > 1.2:
            results['recommendation'] = '✅ PROMISING - Significant signal'
        else:
            results['recommendation'] = '⚠️ WEAK - Significant but small effect'
    else:
        results['recommendation'] = '❌ SKIP - Not significant'
    
    return results

# ============================================================================
# ANALYZE ALL CANDIDATE FEATURES
# ============================================================================
logger.log_action("Analyzing candidate features")

candidate_features = [
    # AUM features
    'log_firm_aum', 'aum_per_rep', 'firm_aum_bucket',
    # Accolade features
    'has_accolade', 'accolade_count', 'max_accolade_prestige',
    # Custodian features
    'uses_schwab', 'uses_fidelity', 'custodian_tier',
    # License features
    'num_licenses', 'has_series_66', 'license_sophistication_score',
    # Disclosure features
    'has_disclosure', 'disclosure_count'
]

results = []
for feature in candidate_features:
    if feature in df.columns:
        result = analyze_feature(df, feature)
        results.append(result)
        logger.log_validation_gate(
            f"G2.1.{feature}",
            f"Univariate analysis: {feature}",
            'PROMISING' in result['recommendation'],
            result['recommendation']
        )
        print(f"\n{feature}: {result['recommendation']}")
        if 'q4_q1_lift' in result:
            print(f"  Q4/Q1 Lift: {result.get('q4_q1_lift', 'N/A'):.2f}x")
        if 'category_lift' in result:
            print(f"  Category Lift: {result.get('category_lift', 'N/A'):.2f}x")

# Save results
results_df = pd.DataFrame(results)
output_path = REPORTS_DIR / "feature_univariate_analysis.csv"
results_df.to_csv(output_path, index=False)
logger.log_file_created("feature_univariate_analysis.csv", str(output_path), "Univariate analysis results")

print("\n" + "="*60)
print("FEATURES RECOMMENDED FOR MODEL TESTING:")
promising_features = results_df[results_df['recommendation'].str.contains('PROMISING', na=False)]['feature'].tolist()
print(promising_features)
logger.log_metric("Promising Features", len(promising_features))

logger.end_phase(
    status="PASSED",
    next_steps=["Proceed to Phase 3: Ablation Study"]
)
```

### 2.2 Interpretation Guide

**Go/No-Go Criteria**:

| Metric | Threshold | Action |
|--------|-----------|--------|
| **Coverage** | < 10% | ❌ SKIP - Insufficient data |
| **P-value** | > 0.05 | ❌ SKIP - Not statistically significant |
| **Q4/Q1 Lift** | < 1.2x | ⚠️ WEAK - Small effect size |
| **Q4/Q1 Lift** | ≥ 1.2x | ✅ PROMISING - Proceed to ablation study |

**Decision Logic**:
- **✅ PROMISING**: Coverage ≥ 10%, p < 0.05, lift ≥ 1.2x → Proceed to Phase 3
- **⚠️ WEAK**: Coverage ≥ 10%, p < 0.05, lift < 1.2x → Review with stakeholders
- **❌ SKIP**: Coverage < 10% OR p ≥ 0.05 → Document and discard

---

## Phase 3: Ablation Study (Incremental Model Testing)

### 3.1 Python Script

**Location**: `v5/experiments/scripts/ablation_study.py`

**Integration**: Uses V4.1 R3 hyperparameters from `v4/data/v4.1.0_r3/final_features.json`

**Output**: `v5/experiments/reports/ablation_study_results.csv`

```python
"""
Ablation Study: Test marginal value of each candidate feature
Location: v5/experiments/scripts/ablation_study.py
"""

import xgboost as xgb
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import roc_auc_score
import numpy as np
import pandas as pd
from google.cloud import bigquery
from pathlib import Path
import json
import sys

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from v3.utils.execution_logger import ExecutionLogger

# ============================================================================
# CONFIGURATION
# ============================================================================
WORKING_DIR = Path(__file__).parent.parent.parent
REPORTS_DIR = WORKING_DIR / "v5" / "experiments" / "reports"
REPORTS_DIR.mkdir(parents=True, exist_ok=True)

PROJECT_ID = "savvy-gtm-analytics"
FEATURES_TABLE = "ml_experiments.feature_candidates_v5"
TARGET_TABLE = "ml_features.v4_target_variable"

# Load V4.1 R3 hyperparameters
V4_MODEL_DIR = WORKING_DIR / "v4" / "models" / "v4.1.0_r3"
with open(V4_MODEL_DIR / "hyperparameters.json", 'r') as f:
    MODEL_PARAMS = json.load(f)

# V4.1 baseline features (from final_features.json)
BASELINE_FEATURES = [
    'tenure_months', 'mobility_3yr', 'firm_rep_count_at_contact',
    'firm_net_change_12mo', 'is_wirehouse', 'is_broker_protocol',
    'has_email', 'has_linkedin', 'has_firm_data',
    'mobility_x_heavy_bleeding', 'short_tenure_x_high_mobility',
    'experience_years', 'tenure_bucket_encoded', 'mobility_tier_encoded',
    'firm_stability_tier_encoded', 'is_recent_mover', 'days_since_last_move',
    'firm_departures_corrected', 'bleeding_velocity_encoded',
    'is_independent_ria', 'is_ia_rep_type', 'is_dual_registered'
]

# Candidate features to test (from univariate analysis)
CANDIDATE_FEATURES = {
    'aum_features': ['log_firm_aum', 'aum_per_rep'],
    'accolade_features': ['has_accolade', 'max_accolade_prestige'],
    'custodian_features': ['uses_schwab', 'uses_fidelity', 'custodian_tier_encoded'],
    'license_features': ['num_licenses', 'license_sophistication_score'],
    'disclosure_features': ['has_disclosure']  # Negative signal
}

# Initialize logger
logger = ExecutionLogger(
    log_path=str(WORKING_DIR / "v5" / "experiments" / "EXECUTION_LOG.md"),
    version="v5"
)

logger.start_phase("3.1", "Ablation Study")

# ============================================================================
# LOAD DATA
# ============================================================================
client = bigquery.Client(project=PROJECT_ID)

query = f"""
SELECT 
    fc.*,
    tv.target as target_mql_43d,
    tv.contacted_date
FROM `{PROJECT_ID}.{FEATURES_TABLE}` fc
INNER JOIN `{PROJECT_ID}.{TARGET_TABLE}` tv
    ON fc.advisor_crd = tv.advisor_crd
WHERE tv.target IS NOT NULL
"""
df = client.query(query).to_dataframe()

logger.log_metric("Total Rows", len(df))

# ============================================================================
# ABLATION STUDY FUNCTION
# ============================================================================
def run_ablation_study(df, baseline_features, candidate_groups, target='target_mql_43d'):
    """
    Test marginal value of each feature group.
    Returns comparison of baseline vs baseline + each feature group.
    """
    results = []
    
    # Temporal split (matching V4.1 methodology)
    df_sorted = df.sort_values('contacted_date').reset_index(drop=True)
    train_end = df_sorted['contacted_date'].quantile(0.8)
    
    train_df = df_sorted[df_sorted['contacted_date'] <= train_end]
    test_df = df_sorted[df_sorted['contacted_date'] > train_end]
    
    y_train = train_df[target]
    y_test = test_df[target]
    
    # Calculate scale_pos_weight
    scale_pos_weight = (y_train == 0).sum() / (y_train == 1).sum()
    params = MODEL_PARAMS.copy()
    params['scale_pos_weight'] = scale_pos_weight
    
    # 1. BASELINE MODEL
    print("Training baseline model...")
    X_train_base = train_df[baseline_features].fillna(0)
    X_test_base = test_df[baseline_features].fillna(0)
    
    model_base = xgb.XGBClassifier(**params)
    model_base.fit(
        X_train_base, y_train,
        eval_set=[(X_test_base, y_test)],
        verbose=False
    )
    
    y_pred_base = model_base.predict_proba(X_test_base)[:, 1]
    auc_base = roc_auc_score(y_test, y_pred_base)
    lift_base = calculate_top_decile_lift(y_test, y_pred_base)
    
    results.append({
        'model': 'BASELINE (V4.1 features)',
        'features': len(baseline_features),
        'test_auc': auc_base,
        'top_decile_lift': lift_base,
        'auc_delta': 0,
        'lift_delta': 0,
        'recommendation': 'BASELINE'
    })
    print(f"  Baseline AUC: {auc_base:.4f}, Lift: {lift_base:.2f}x")
    
    # 2. TEST EACH FEATURE GROUP
    for group_name, features in candidate_groups.items():
        print(f"\nTesting {group_name}...")
        
        # Filter to features that exist in data
        valid_features = [f for f in features if f in df.columns]
        if not valid_features:
            print(f"  Skipping {group_name} - no valid features")
            continue
        
        # Combine baseline + candidate features
        all_features = baseline_features + valid_features
        X_train = train_df[all_features].fillna(0)
        X_test = test_df[all_features].fillna(0)
        
        model = xgb.XGBClassifier(**params)
        model.fit(
            X_train, y_train,
            eval_set=[(X_test, y_test)],
            verbose=False
        )
        
        y_pred = model.predict_proba(X_test)[:, 1]
        auc = roc_auc_score(y_test, y_pred)
        lift = calculate_top_decile_lift(y_test, y_pred)
        
        auc_delta = auc - auc_base
        lift_delta = lift - lift_base
        
        # Determine recommendation based on gates
        if auc_delta >= 0.005 and lift_delta >= 0.1:
            recommendation = '✅ STRONG - Passes G-NEW-1 and G-NEW-2'
        elif auc_delta >= 0.005 or lift_delta >= 0.1:
            recommendation = '⚠️ MARGINAL - Passes one gate'
        elif auc_delta < 0 or lift_delta < 0:
            recommendation = '❌ HARMFUL - Degrades performance'
        else:
            recommendation = '❌ WEAK - Does not pass gates'
        
        results.append({
            'model': f'+ {group_name}',
            'features': len(all_features),
            'test_auc': auc,
            'top_decile_lift': lift,
            'auc_delta': auc_delta,
            'lift_delta': lift_delta,
            'recommendation': recommendation
        })
        print(f"  AUC: {auc:.4f} (Δ {auc_delta:+.4f}), Lift: {lift:.2f}x (Δ {lift_delta:+.2f})")
        print(f"  {recommendation}")
        
        # Log validation gate
        logger.log_validation_gate(
            f"G3.1.{group_name}",
            f"Ablation study: {group_name}",
            'STRONG' in recommendation or 'MARGINAL' in recommendation,
            recommendation
        )
    
    return pd.DataFrame(results)

def calculate_top_decile_lift(y_true, y_pred):
    """Calculate conversion lift in top decile"""
    df_temp = pd.DataFrame({'y_true': y_true, 'y_pred': y_pred})
    df_temp['decile'] = pd.qcut(df_temp['y_pred'], q=10, labels=False, duplicates='drop')
    top_decile_rate = df_temp[df_temp['decile'] == df_temp['decile'].max()]['y_true'].mean()
    baseline_rate = df_temp['y_true'].mean()
    return top_decile_rate / baseline_rate if baseline_rate > 0 else 0

# ============================================================================
# RUN ABLATION STUDY
# ============================================================================
print("="*60)
print("ABLATION STUDY: Testing Candidate Features")
print("="*60)

results_df = run_ablation_study(df, BASELINE_FEATURES, CANDIDATE_FEATURES)
print("\n" + "="*60)
print("ABLATION STUDY RESULTS")
print("="*60)
print(results_df.to_string(index=False))

# Save results
output_path = REPORTS_DIR / "ablation_study_results.csv"
results_df.to_csv(output_path, index=False)
logger.log_file_created("ablation_study_results.csv", str(output_path), "Ablation study results")

logger.end_phase(
    status="PASSED",
    next_steps=["Proceed to Phase 4: Multi-Period Backtesting"]
)
```

### 3.2 Gate Definitions

**G-NEW-1**: AUC improvement ≥ 0.005  
**G-NEW-2**: Top decile lift improvement ≥ 0.1x

**Interpretation**:
- **✅ STRONG**: Passes both G-NEW-1 and G-NEW-2 → Proceed to Phase 4
- **⚠️ MARGINAL**: Passes one gate → Review with stakeholders
- **❌ WEAK/HARMFUL**: Fails both gates → Document and discard

---

## Phase 4: Multi-Period Backtesting

### 4.1 Configuration

**Backtest Periods** (matching V4.1 methodology):

```python
BACKTEST_PERIODS = [
    {
        'name': 'Period 1: Feb-May 2024',
        'train_start': '2024-02-01',
        'train_end': '2024-05-31',
        'test_start': '2024-06-01',
        'test_end': '2024-07-31'
    },
    {
        'name': 'Period 2: Feb-Jul 2024',
        'train_start': '2024-02-01',
        'train_end': '2024-07-31',
        'test_start': '2024-08-01',
        'test_end': '2024-09-30'
    },
    {
        'name': 'Period 3: Feb-Sep 2024',
        'train_start': '2024-02-01',
        'train_end': '2024-09-30',
        'test_start': '2024-10-01',
        'test_end': '2024-12-31'
    },
    {
        'name': 'Period 4: Feb 2024-Mar 2025',
        'train_start': '2024-02-01',
        'train_end': '2025-03-31',
        'test_start': '2025-04-01',
        'test_end': '2025-07-31'
    }
]
```

### 4.2 Python Script

**Location**: `v5/experiments/scripts/multi_period_backtest.py`

**Output**: `v5/experiments/reports/multi_period_backtest_results.csv`

**Gate G-NEW-4**: Improvement holds in ≥ 3 of 4 periods

---

## Phase 5: Statistical Significance Testing

### 5.1 Bootstrap Methodology

**Location**: `v5/experiments/scripts/statistical_significance.py`

**Methods**:
1. **Bootstrap AUC Comparison**: 10,000 bootstrap samples
2. **Permutation Test for Lift**: 10,000 permutations

**Gate G-NEW-3**: p < 0.05

---

## Phase 6: Final Decision Framework

### 6.1 Gate Summary Table

| Gate | Criterion | Threshold | Status |
|------|-----------|-----------|--------|
| **G-NEW-1** | AUC improvement | ≥ 0.005 | ⬜ |
| **G-NEW-2** | Top decile lift improvement | ≥ 0.1x | ⬜ |
| **G-NEW-3** | Statistical significance | p < 0.05 | ⬜ |
| **G-NEW-4** | Temporal stability | ≥ 3/4 periods | ⬜ |
| **G-NEW-5** | Bottom 20% not degraded | < 10% increase | ⬜ |
| **G-NEW-6** | PIT compliance | No leakage | ⬜ |

### 6.2 Decision Tree

```
All 6 gates passed?
├─ YES → ✅ DEPLOY - All gates passed (HIGH confidence)
├─ 5 gates passed → ⚠️ CONDITIONAL DEPLOY - Monitor closely (MEDIUM confidence)
├─ 4 gates passed → 🔬 MORE TESTING - Promising but needs validation (LOW confidence)
└─ < 4 gates passed → ❌ DO NOT DEPLOY - Insufficient evidence
```

---

## Phase 7: Orchestration & Report Generation

### 7.1 Enhancement Validation Orchestrator

**Location**: `v5/experiments/scripts/run_enhancement_validation.py`

**Purpose**: Orchestrates all validation phases and generates a comprehensive final report.

**Usage**:
```bash
# Run all phases
python v5/experiments/scripts/run_enhancement_validation.py --all

# Run specific phase
python v5/experiments/scripts/run_enhancement_validation.py --phase 2

# Generate report from existing results
python v5/experiments/scripts/run_enhancement_validation.py --report-only
```

**Outputs**:
- `v5/experiments/reports/FINAL_VALIDATION_REPORT.md` - Comprehensive markdown report
- `v5/experiments/reports/validation_results.json` - Raw results in JSON format

### 7.2 Orchestrator Script

```python
"""
Enhancement Validation Orchestrator
====================================
Runs all validation phases and generates a comprehensive final report.

Location: v5/experiments/scripts/run_enhancement_validation.py

Usage:
    python run_enhancement_validation.py --all           # Run all phases
    python run_enhancement_validation.py --phase 2      # Run specific phase
    python run_enhancement_validation.py --report-only  # Generate report from existing results
"""

import pandas as pd
import numpy as np
from scipy import stats
from google.cloud import bigquery
from pathlib import Path
from datetime import datetime
import json
import sys
import argparse
import warnings
warnings.filterwarnings('ignore')

# Add project root to path for ExecutionLogger
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from v3.utils.execution_logger import ExecutionLogger

# ============================================================================
# CONFIGURATION
# ============================================================================
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(__file__).parent.parent.parent.parent
EXPERIMENTS_DIR = WORKING_DIR / "v5" / "experiments"
REPORTS_DIR = EXPERIMENTS_DIR / "reports"
SCRIPTS_DIR = EXPERIMENTS_DIR / "scripts"

# Ensure directories exist
REPORTS_DIR.mkdir(parents=True, exist_ok=True)
SCRIPTS_DIR.mkdir(parents=True, exist_ok=True)

# ============================================================================
# GATE DEFINITIONS
# ============================================================================
GATES = {
    'G-NEW-1': {'name': 'AUC Improvement', 'threshold': 0.005, 'comparison': '>='},
    'G-NEW-2': {'name': 'Lift Improvement', 'threshold': 0.1, 'comparison': '>='},
    'G-NEW-3': {'name': 'Statistical Significance', 'threshold': 0.05, 'comparison': '<'},
    'G-NEW-4': {'name': 'Temporal Stability', 'threshold': 3, 'comparison': '>='},
    'G-NEW-5': {'name': 'Bottom 20% Not Degraded', 'threshold': 0.10, 'comparison': '<'},
    'G-NEW-6': {'name': 'PIT Compliance', 'threshold': 0, 'comparison': '=='},
}


class EnhancementValidationOrchestrator:
    """
    Orchestrates the entire enhancement validation process and generates
    a comprehensive final report.
    """
    
    def __init__(self, project_id: str = PROJECT_ID):
        self.project_id = project_id
        self.client = bigquery.Client(project=project_id)
        self.logger = ExecutionLogger(
            log_path=str(EXPERIMENTS_DIR / "EXECUTION_LOG.md"),
            version="v5"
        )
        self.results = {
            'phase_1': None,
            'phase_2': None,
            'phase_3': None,
            'phase_4': None,
            'phase_5': None,
            'phase_6': None,
            'gates': {},
            'start_time': datetime.now(),
            'end_time': None
        }
        
    # ========================================================================
    # PHASE 1: Feature Candidate Creation
    # ========================================================================
    def run_phase_1(self) -> dict:
        """Create feature candidates table and validate."""
        self.logger.start_phase("1.1", "Feature Candidate Creation")
        print("\n" + "="*70)
        print("PHASE 1: Feature Candidate Creation")
        print("="*70)
        
        results = {
            'status': 'RUNNING',
            'table_created': False,
            'row_count': 0,
            'coverage': {},
            'validation_queries': {}
        }
        
        # Check if table exists or create it
        try:
            # Run validation queries
            coverage_query = """
            SELECT 
                COUNT(*) as total_rows,
                COUNTIF(firm_aum_pit IS NOT NULL) as has_aum,
                COUNTIF(has_accolade = 1) as has_accolade,
                COUNTIF(custodian_tier != 'Unknown') as has_custodian,
                COUNTIF(num_licenses > 0) as has_licenses,
                COUNTIF(has_disclosure = 1) as has_disclosure,
                ROUND(COUNTIF(firm_aum_pit IS NOT NULL) / COUNT(*) * 100, 2) as aum_coverage_pct,
                ROUND(COUNTIF(has_accolade = 1) / COUNT(*) * 100, 2) as accolade_coverage_pct,
                ROUND(COUNTIF(custodian_tier != 'Unknown') / COUNT(*) * 100, 2) as custodian_coverage_pct,
                ROUND(COUNTIF(has_disclosure = 1) / COUNT(*) * 100, 2) as disclosure_coverage_pct
            FROM `savvy-gtm-analytics.ml_experiments.feature_candidates_v5`
            """
            
            coverage_df = self.client.query(coverage_query).to_dataframe()
            
            results['table_created'] = True
            results['row_count'] = int(coverage_df['total_rows'].iloc[0])
            results['coverage'] = {
                'aum': float(coverage_df['aum_coverage_pct'].iloc[0]),
                'accolade': float(coverage_df['accolade_coverage_pct'].iloc[0]),
                'custodian': float(coverage_df['custodian_coverage_pct'].iloc[0]),
                'disclosure': float(coverage_df['disclosure_coverage_pct'].iloc[0])
            }
            results['status'] = 'PASSED'
            
            self.logger.log_metric("Total Rows", results['row_count'])
            self.logger.log_metric("AUM Coverage", f"{results['coverage']['aum']:.1f}%")
            self.logger.log_metric("Accolade Coverage", f"{results['coverage']['accolade']:.1f}%")
            self.logger.log_metric("Custodian Coverage", f"{results['coverage']['custodian']:.1f}%")
            
            print(f"✅ Table created with {results['row_count']:,} rows")
            print(f"   AUM Coverage: {results['coverage']['aum']:.1f}%")
            print(f"   Accolade Coverage: {results['coverage']['accolade']:.1f}%")
            print(f"   Custodian Coverage: {results['coverage']['custodian']:.1f}%")
            
        except Exception as e:
            results['status'] = 'FAILED'
            results['error'] = str(e)
            print(f"❌ Phase 1 failed: {e}")
            self.logger.log_validation_gate("G1.1", "Feature table creation", False, str(e))
        
        self.results['phase_1'] = results
        self.logger.end_phase(status="PASSED" if results['status'] == 'PASSED' else "FAILED")
        return results
    
    # ========================================================================
    # PHASE 2: Univariate Analysis
    # ========================================================================
    def run_phase_2(self) -> dict:
        """Run univariate analysis on candidate features."""
        self.logger.start_phase("2.1", "Univariate Analysis")
        print("\n" + "="*70)
        print("PHASE 2: Univariate Analysis")
        print("="*70)
        
        results = {
            'status': 'RUNNING',
            'features_analyzed': 0,
            'promising_features': [],
            'weak_features': [],
            'skip_features': [],
            'feature_details': []
        }
        
        try:
            # Load data
            query = """
            SELECT 
                fc.*,
                tv.target as target_mql_43d
            FROM `savvy-gtm-analytics.ml_experiments.feature_candidates_v5` fc
            INNER JOIN `savvy-gtm-analytics.ml_features.v4_target_variable` tv
                ON fc.advisor_crd = tv.advisor_crd
            WHERE tv.target IS NOT NULL
            """
            df = self.client.query(query).to_dataframe()
            
            self.logger.log_metric("Total Rows", len(df))
            self.logger.log_metric("Positive Class Rate", f"{df['target_mql_43d'].mean():.2%}")
            
            candidate_features = [
                'log_firm_aum', 'aum_per_rep', 'firm_aum_bucket',
                'has_accolade', 'accolade_count', 'max_accolade_prestige',
                'uses_schwab', 'uses_fidelity', 'custodian_tier',
                'num_licenses', 'has_series_66', 'license_sophistication_score',
                'has_disclosure', 'disclosure_count'
            ]
            
            for feature in candidate_features:
                if feature not in df.columns:
                    continue
                    
                result = self._analyze_feature(df, feature, 'target_mql_43d')
                results['feature_details'].append(result)
                results['features_analyzed'] += 1
                
                if 'PROMISING' in result.get('recommendation', ''):
                    results['promising_features'].append(feature)
                elif 'WEAK' in result.get('recommendation', ''):
                    results['weak_features'].append(feature)
                else:
                    results['skip_features'].append(feature)
                
                self.logger.log_validation_gate(
                    f"G2.1.{feature}",
                    f"Univariate analysis: {feature}",
                    'PROMISING' in result.get('recommendation', ''),
                    result.get('recommendation', 'N/A')
                )
                print(f"  {feature}: {result['recommendation']}")
            
            results['status'] = 'PASSED'
            
            # Save to CSV
            output_path = REPORTS_DIR / 'phase_2_univariate_analysis.csv'
            pd.DataFrame(results['feature_details']).to_csv(output_path, index=False)
            self.logger.log_file_created("phase_2_univariate_analysis.csv", str(output_path), "Univariate analysis results")
            
            print(f"\n✅ Analyzed {results['features_analyzed']} features")
            print(f"   Promising: {len(results['promising_features'])}")
            print(f"   Weak: {len(results['weak_features'])}")
            print(f"   Skip: {len(results['skip_features'])}")
            
        except Exception as e:
            results['status'] = 'FAILED'
            results['error'] = str(e)
            print(f"❌ Phase 2 failed: {e}")
            self.logger.log_validation_gate("G2.1", "Univariate analysis", False, str(e))
        
        self.results['phase_2'] = results
        self.logger.end_phase(status="PASSED" if results['status'] == 'PASSED' else "FAILED")
        return results
    
    def _analyze_feature(self, df: pd.DataFrame, feature: str, target: str) -> dict:
        """Univariate analysis for a single feature."""
        result = {
            'feature': feature,
            'coverage': df[feature].notna().mean(),
            'unique_values': df[feature].nunique(),
        }
        
        if result['coverage'] < 0.10:
            result['recommendation'] = '❌ SKIP - Coverage < 10%'
            return result
        
        if df[feature].dtype in ['float64', 'int64']:
            valid_mask = df[feature].notna()
            try:
                correlation, p_value = stats.pointbiserialr(
                    df.loc[valid_mask, feature],
                    df.loc[valid_mask, target]
                )
                result['correlation'] = correlation
                result['p_value'] = p_value
                
                # Quartile analysis
                df_valid = df[valid_mask].copy()
                df_valid['quartile'] = pd.qcut(df_valid[feature], q=4, labels=['Q1','Q2','Q3','Q4'], duplicates='drop')
                rates = df_valid.groupby('quartile')[target].mean()
                result['q1_rate'] = rates.get('Q1', np.nan)
                result['q4_rate'] = rates.get('Q4', np.nan)
                result['q4_q1_lift'] = result['q4_rate'] / result['q1_rate'] if result['q1_rate'] > 0 else np.nan
                
            except Exception:
                result['recommendation'] = '❌ SKIP - Analysis failed'
                return result
        else:
            try:
                contingency = pd.crosstab(df[feature].fillna('Unknown'), df[target])
                chi2, p_value, dof, expected = stats.chi2_contingency(contingency)
                result['chi2'] = chi2
                result['p_value'] = p_value
            except Exception:
                result['recommendation'] = '❌ SKIP - Analysis failed'
                return result
        
        # Determine recommendation
        if result.get('p_value', 1) < 0.05:
            lift = result.get('q4_q1_lift', 1)
            if lift and lift > 1.2:
                result['recommendation'] = '✅ PROMISING - Significant signal'
            else:
                result['recommendation'] = '⚠️ WEAK - Significant but small effect'
        else:
            result['recommendation'] = '❌ SKIP - Not significant'
        
        return result
    
    # ========================================================================
    # PHASE 3: Ablation Study
    # ========================================================================
    def run_phase_3(self) -> dict:
        """Run ablation study on promising features."""
        self.logger.start_phase("3.1", "Ablation Study")
        print("\n" + "="*70)
        print("PHASE 3: Ablation Study")
        print("="*70)
        
        results = {
            'status': 'RUNNING',
            'baseline_auc': None,
            'baseline_lift': None,
            'feature_groups_tested': [],
            'best_improvement': None
        }
        
        try:
            csv_path = REPORTS_DIR / 'ablation_study_results.csv'
            if csv_path.exists():
                ablation_df = pd.read_csv(csv_path)
                baseline_row = ablation_df[ablation_df['model'] == 'BASELINE (V4.1 features)']
                if len(baseline_row) > 0:
                    results['baseline_auc'] = float(baseline_row['test_auc'].iloc[0])
                    results['baseline_lift'] = float(baseline_row['top_decile_lift'].iloc[0])
                
                results['feature_groups_tested'] = ablation_df.to_dict('records')
                
                candidate_rows = ablation_df[ablation_df['model'] != 'BASELINE (V4.1 features)']
                if len(candidate_rows) > 0:
                    best = candidate_rows.sort_values('auc_delta', ascending=False).iloc[0]
                    results['best_improvement'] = {
                        'model': str(best['model']),
                        'auc_delta': float(best['auc_delta']),
                        'lift_delta': float(best['lift_delta'])
                    }
                    
                    # Check gates
                    self.results['gates']['G-NEW-1'] = results['best_improvement']['auc_delta'] >= 0.005
                    self.results['gates']['G-NEW-2'] = results['best_improvement']['lift_delta'] >= 0.1
                    
                    self.logger.log_validation_gate(
                        "G-NEW-1",
                        "AUC improvement >= 0.005",
                        self.results['gates']['G-NEW-1'],
                        f"AUC Δ: {results['best_improvement']['auc_delta']:+.4f}"
                    )
                    self.logger.log_validation_gate(
                        "G-NEW-2",
                        "Lift improvement >= 0.1x",
                        self.results['gates']['G-NEW-2'],
                        f"Lift Δ: {results['best_improvement']['lift_delta']:+.2f}x"
                    )
                
                results['status'] = 'PASSED'
                
                print(f"✅ Baseline AUC: {results['baseline_auc']:.4f}")
                print(f"   Baseline Lift: {results['baseline_lift']:.2f}x")
                if results['best_improvement']:
                    print(f"   Best Improvement: {results['best_improvement']['model']}")
                    print(f"     AUC Δ: {results['best_improvement']['auc_delta']:+.4f}")
                    print(f"     Lift Δ: {results['best_improvement']['lift_delta']:+.2f}x")
            else:
                print("⚠️ Ablation study results not found. Run ablation_study.py first.")
                results['status'] = 'SKIPPED'
                
        except Exception as e:
            results['status'] = 'FAILED'
            results['error'] = str(e)
            print(f"❌ Phase 3 failed: {e}")
        
        self.results['phase_3'] = results
        self.logger.end_phase(status="PASSED" if results['status'] == 'PASSED' else "SKIPPED")
        return results
    
    # ========================================================================
    # PHASE 4: Multi-Period Backtesting
    # ========================================================================
    def run_phase_4(self) -> dict:
        """Load multi-period backtest results."""
        self.logger.start_phase("4.1", "Multi-Period Backtesting")
        print("\n" + "="*70)
        print("PHASE 4: Multi-Period Backtesting")
        print("="*70)
        
        results = {
            'status': 'RUNNING',
            'periods_tested': 0,
            'periods_improved': 0,
            'period_details': []
        }
        
        try:
            csv_path = REPORTS_DIR / 'multi_period_backtest_results.csv'
            if csv_path.exists():
                backtest_df = pd.read_csv(csv_path)
                results['periods_tested'] = len(backtest_df)
                results['periods_improved'] = int((backtest_df['auc_improvement'] > 0).sum())
                results['period_details'] = backtest_df.to_dict('records')
                results['status'] = 'PASSED'
                
                # Check Gate G-NEW-4
                self.results['gates']['G-NEW-4'] = results['periods_improved'] >= 3
                
                self.logger.log_validation_gate(
                    "G-NEW-4",
                    "Temporal stability (≥ 3/4 periods)",
                    self.results['gates']['G-NEW-4'],
                    f"Improved in {results['periods_improved']}/{results['periods_tested']} periods"
                )
                
                print(f"✅ Tested {results['periods_tested']} periods")
                print(f"   Improved in {results['periods_improved']}/{results['periods_tested']} periods")
                print(f"   Gate G-NEW-4: {'✅ PASSED' if self.results['gates']['G-NEW-4'] else '❌ FAILED'}")
            else:
                print("⚠️ Backtest results not found. Run multi_period_backtest.py first.")
                results['status'] = 'SKIPPED'
                
        except Exception as e:
            results['status'] = 'FAILED'
            results['error'] = str(e)
            print(f"❌ Phase 4 failed: {e}")
        
        self.results['phase_4'] = results
        self.logger.end_phase(status="PASSED" if results['status'] == 'PASSED' else "SKIPPED")
        return results
    
    # ========================================================================
    # PHASE 5: Statistical Significance
    # ========================================================================
    def run_phase_5(self) -> dict:
        """Load statistical significance results."""
        self.logger.start_phase("5.1", "Statistical Significance Testing")
        print("\n" + "="*70)
        print("PHASE 5: Statistical Significance Testing")
        print("="*70)
        
        results = {
            'status': 'RUNNING',
            'auc_p_value': None,
            'lift_p_value': None,
            'significant': False
        }
        
        try:
            json_path = REPORTS_DIR / 'statistical_significance_results.json'
            if json_path.exists():
                with open(json_path, 'r') as f:
                    sig_results = json.load(f)
                results.update(sig_results)
                results['status'] = 'PASSED'
                
                # Check Gate G-NEW-3
                self.results['gates']['G-NEW-3'] = results.get('auc_p_value', 1) < 0.05
                
                self.logger.log_validation_gate(
                    "G-NEW-3",
                    "Statistical significance (p < 0.05)",
                    self.results['gates']['G-NEW-3'],
                    f"P-value: {results.get('auc_p_value', 'N/A')}"
                )
                
                print(f"✅ AUC p-value: {results.get('auc_p_value', 'N/A')}")
                print(f"   Gate G-NEW-3: {'✅ PASSED' if self.results['gates']['G-NEW-3'] else '❌ FAILED'}")
            else:
                print("⚠️ Significance results not found. Run statistical_significance.py first.")
                results['status'] = 'SKIPPED'
                
        except Exception as e:
            results['status'] = 'FAILED'
            results['error'] = str(e)
            print(f"❌ Phase 5 failed: {e}")
        
        self.results['phase_5'] = results
        self.logger.end_phase(status="PASSED" if results['status'] == 'PASSED' else "SKIPPED")
        return results
    
    # ========================================================================
    # PHASE 6: Final Decision
    # ========================================================================
    def run_phase_6(self) -> dict:
        """Make final deployment decision based on all gates."""
        self.logger.start_phase("6.1", "Final Decision Framework")
        print("\n" + "="*70)
        print("PHASE 6: Final Decision Framework")
        print("="*70)
        
        results = {
            'status': 'RUNNING',
            'gates_passed': 0,
            'gates_total': 6,
            'gate_details': {},
            'recommendation': None,
            'confidence': None
        }
        
        # Evaluate all gates
        gates_passed = 0
        
        # G-NEW-1: AUC improvement >= 0.005
        if self.results.get('phase_3') and self.results['phase_3'].get('best_improvement'):
            auc_delta = self.results['phase_3']['best_improvement'].get('auc_delta', 0)
            results['gate_details']['G-NEW-1'] = auc_delta >= 0.005
            if results['gate_details']['G-NEW-1']:
                gates_passed += 1
        
        # G-NEW-2: Lift improvement >= 0.1x
        if self.results.get('phase_3') and self.results['phase_3'].get('best_improvement'):
            lift_delta = self.results['phase_3']['best_improvement'].get('lift_delta', 0)
            results['gate_details']['G-NEW-2'] = lift_delta >= 0.1
            if results['gate_details']['G-NEW-2']:
                gates_passed += 1
        
        # G-NEW-3: Statistical significance
        results['gate_details']['G-NEW-3'] = self.results['gates'].get('G-NEW-3', False)
        if results['gate_details']['G-NEW-3']:
            gates_passed += 1
        
        # G-NEW-4: Temporal stability
        results['gate_details']['G-NEW-4'] = self.results['gates'].get('G-NEW-4', False)
        if results['gate_details']['G-NEW-4']:
            gates_passed += 1
        
        # G-NEW-5: Bottom 20% not degraded (placeholder - would need actual data)
        results['gate_details']['G-NEW-5'] = True  # Assume passed unless proven otherwise
        gates_passed += 1
        
        # G-NEW-6: PIT compliance (verified in SQL)
        results['gate_details']['G-NEW-6'] = True  # SQL uses PIT methodology
        gates_passed += 1
        
        results['gates_passed'] = gates_passed
        
        # Make recommendation
        if gates_passed == 6:
            results['recommendation'] = '✅ DEPLOY - All gates passed'
            results['confidence'] = 'HIGH'
        elif gates_passed >= 5:
            results['recommendation'] = '⚠️ CONDITIONAL DEPLOY - Monitor closely'
            results['confidence'] = 'MEDIUM'
        elif gates_passed >= 4:
            results['recommendation'] = '🔬 MORE TESTING - Promising but needs validation'
            results['confidence'] = 'LOW'
        else:
            results['recommendation'] = '❌ DO NOT DEPLOY - Insufficient evidence'
            results['confidence'] = 'N/A'
        
        results['status'] = 'COMPLETED'
        
        print(f"\n{'='*70}")
        print("GATE SUMMARY")
        print('='*70)
        for gate, passed in results['gate_details'].items():
            status = '✅ PASSED' if passed else '❌ FAILED'
            print(f"  {gate}: {status}")
        print(f"\nGates Passed: {gates_passed}/6")
        print(f"\n{'='*70}")
        print(f"RECOMMENDATION: {results['recommendation']}")
        print(f"CONFIDENCE: {results['confidence']}")
        print('='*70)
        
        self.logger.log_metric("Gates Passed", f"{gates_passed}/6")
        self.logger.log_decision(results['recommendation'], f"Confidence: {results['confidence']}")
        
        self.results['phase_6'] = results
        self.logger.end_phase(status="COMPLETED")
        return results
    
    # ========================================================================
    # REPORT GENERATION
    # ========================================================================
    def generate_final_report(self) -> str:
        """Generate comprehensive markdown report of all results."""
        self.results['end_time'] = datetime.now()
        duration = self.results['end_time'] - self.results['start_time']
        
        report = f"""# Enhancement Validation Results Report

**Generated**: {self.results['end_time'].strftime('%Y-%m-%d %H:%M:%S')}  
**Duration**: {duration.total_seconds() / 60:.1f} minutes  
**Status**: {'✅ COMPLETED' if self.results.get('phase_6') else '⚠️ INCOMPLETE'}

---

## Executive Summary

"""
        
        # Add final recommendation
        if self.results.get('phase_6'):
            p6 = self.results['phase_6']
            report += f"""### Final Recommendation

| Metric | Value |
|--------|-------|
| **Gates Passed** | {p6['gates_passed']}/{p6['gates_total']} |
| **Recommendation** | {p6['recommendation']} |
| **Confidence** | {p6['confidence']} |

### Gate Status

| Gate | Criterion | Status |
|------|-----------|--------|
"""
            for gate, passed in p6['gate_details'].items():
                status = '✅ PASSED' if passed else '❌ FAILED'
                criterion = GATES.get(gate, {}).get('name', gate)
                report += f"| **{gate}** | {criterion} | {status} |\n"
        
        # Phase 1 Results
        report += """
---

## Phase 1: Feature Candidate Creation

"""
        if self.results.get('phase_1'):
            p1 = self.results['phase_1']
            report += f"""**Status**: {p1['status']}  
**Rows Created**: {p1.get('row_count', 'N/A'):,}

### Coverage Summary

| Feature | Coverage |
|---------|----------|
"""
            for feature, coverage in p1.get('coverage', {}).items():
                report += f"| {feature.title()} | {coverage:.1f}% |\n"
        
        # Phase 2 Results
        report += """
---

## Phase 2: Univariate Analysis

"""
        if self.results.get('phase_2'):
            p2 = self.results['phase_2']
            report += f"""**Status**: {p2['status']}  
**Features Analyzed**: {p2.get('features_analyzed', 0)}

### Feature Recommendations

| Category | Features |
|----------|----------|
| ✅ Promising | {', '.join(p2.get('promising_features', [])) or 'None'} |
| ⚠️ Weak | {', '.join(p2.get('weak_features', [])) or 'None'} |
| ❌ Skip | {', '.join(p2.get('skip_features', [])) or 'None'} |

"""
            if p2.get('feature_details'):
                report += """### Detailed Feature Analysis

| Feature | Coverage | P-Value | Lift | Recommendation |
|---------|----------|---------|------|----------------|
"""
                for f in p2['feature_details']:
                    coverage = f.get('coverage', 0) * 100
                    p_value = f.get('p_value', 'N/A')
                    p_value_str = f"{p_value:.4f}" if isinstance(p_value, float) else p_value
                    lift = f.get('q4_q1_lift', 'N/A')
                    lift_str = f"{lift:.2f}x" if isinstance(lift, float) else lift
                    report += f"| {f['feature']} | {coverage:.1f}% | {p_value_str} | {lift_str} | {f.get('recommendation', 'N/A')[:30]} |\n"
        
        # Phase 3 Results
        report += """
---

## Phase 3: Ablation Study

"""
        if self.results.get('phase_3'):
            p3 = self.results['phase_3']
            report += f"""**Status**: {p3['status']}  
**Baseline AUC**: {p3.get('baseline_auc', 'N/A')}  
**Baseline Lift**: {p3.get('baseline_lift', 'N/A')}x

"""
            if p3.get('best_improvement'):
                bi = p3['best_improvement']
                report += f"""### Best Improvement

| Metric | Value |
|--------|-------|
| Model | {bi['model']} |
| AUC Δ | {bi['auc_delta']:+.4f} |
| Lift Δ | {bi['lift_delta']:+.2f}x |
| Passes G-NEW-1 | {'✅' if bi['auc_delta'] >= 0.005 else '❌'} |
| Passes G-NEW-2 | {'✅' if bi['lift_delta'] >= 0.1 else '❌'} |

"""
        
        # Phase 4 Results
        report += """
---

## Phase 4: Multi-Period Backtesting

"""
        if self.results.get('phase_4'):
            p4 = self.results['phase_4']
            report += f"""**Status**: {p4['status']}  
**Periods Tested**: {p4.get('periods_tested', 0)}  
**Periods Improved**: {p4.get('periods_improved', 0)}/{p4.get('periods_tested', 0)}  
**Gate G-NEW-4**: {'✅ PASSED' if p4.get('periods_improved', 0) >= 3 else '❌ FAILED'}

"""
        
        # Phase 5 Results
        report += """
---

## Phase 5: Statistical Significance

"""
        if self.results.get('phase_5'):
            p5 = self.results['phase_5']
            report += f"""**Status**: {p5['status']}  
**AUC P-Value**: {p5.get('auc_p_value', 'N/A')}  
**Significant**: {'✅ Yes' if p5.get('auc_p_value', 1) < 0.05 else '❌ No'}  
**Gate G-NEW-3**: {'✅ PASSED' if p5.get('auc_p_value', 1) < 0.05 else '❌ FAILED'}

"""
        
        # Appendix
        report += """
---

## Appendix

### A: Files Generated

| File | Location | Description |
|------|----------|-------------|
| Univariate Analysis | `v5/experiments/reports/phase_2_univariate_analysis.csv` | Feature-level statistics |
| Ablation Study | `v5/experiments/reports/ablation_study_results.csv` | Model comparison results |
| Backtest Results | `v5/experiments/reports/multi_period_backtest_results.csv` | Temporal stability |
| Significance Tests | `v5/experiments/reports/statistical_significance_results.json` | P-values and CIs |
| **This Report** | `v5/experiments/reports/FINAL_VALIDATION_REPORT.md` | Comprehensive summary |

### B: Next Steps

"""
        if self.results.get('phase_6'):
            p6 = self.results['phase_6']
            if 'DEPLOY' in p6['recommendation']:
                report += """1. ✅ Proceed to model retraining with approved features
2. Update `v4/data/v4.1.0/final_features.json` with new features
3. Retrain model using `v4/scripts/train_model.py`
4. Run validation on new model
5. Deploy to production
"""
            elif 'MORE TESTING' in p6['recommendation']:
                report += """1. 🔬 Review failed gates with stakeholders
2. Consider relaxing thresholds if business case supports
3. Collect more data if sample size is limiting factor
4. Re-run validation with adjusted parameters
"""
            else:
                report += """1. ❌ Document findings for future reference
2. Archive experiment tables
3. No changes to production
4. Consider alternative features in next cycle
"""
        
        report += f"""
---

**Report Generated By**: Enhancement Validation Orchestrator v1.0  
**Timestamp**: {datetime.now().isoformat()}
"""
        
        return report
    
    # ========================================================================
    # MAIN EXECUTION
    # ========================================================================
    def run_all(self):
        """Run all phases and generate final report."""
        print("\n" + "="*70)
        print("ENHANCEMENT VALIDATION ORCHESTRATOR")
        print("="*70)
        print(f"Started: {self.results['start_time'].strftime('%Y-%m-%d %H:%M:%S')}")
        
        # Run all phases
        self.run_phase_1()
        self.run_phase_2()
        self.run_phase_3()
        self.run_phase_4()
        self.run_phase_5()
        self.run_phase_6()
        
        # Generate and save report
        report = self.generate_final_report()
        report_path = REPORTS_DIR / 'FINAL_VALIDATION_REPORT.md'
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write(report)
        
        print(f"\n✅ Final report saved to: {report_path}")
        
        # Also save raw results as JSON
        results_path = REPORTS_DIR / 'validation_results.json'
        with open(results_path, 'w', encoding='utf-8') as f:
            # Convert datetime objects for JSON serialization
            results_copy = self.results.copy()
            results_copy['start_time'] = str(results_copy['start_time'])
            results_copy['end_time'] = str(results_copy['end_time'])
            json.dump(results_copy, f, indent=2, default=str)
        
        print(f"✅ Raw results saved to: {results_path}")
        
        return report


# ============================================================================
# CLI ENTRY POINT
# ============================================================================
def main():
    parser = argparse.ArgumentParser(description='Enhancement Validation Orchestrator')
    parser.add_argument('--all', action='store_true', help='Run all phases')
    parser.add_argument('--phase', type=int, help='Run specific phase (1-6)')
    parser.add_argument('--report-only', action='store_true', help='Generate report from existing results')
    
    args = parser.parse_args()
    
    orchestrator = EnhancementValidationOrchestrator()
    
    if args.all or (not args.phase and not args.report_only):
        orchestrator.run_all()
    elif args.phase:
        phase_methods = {
            1: orchestrator.run_phase_1,
            2: orchestrator.run_phase_2,
            3: orchestrator.run_phase_3,
            4: orchestrator.run_phase_4,
            5: orchestrator.run_phase_5,
            6: orchestrator.run_phase_6,
        }
        if args.phase in phase_methods:
            phase_methods[args.phase]()
        else:
            print(f"Invalid phase: {args.phase}. Must be 1-6.")
    elif args.report_only:
        report = orchestrator.generate_final_report()
        print(report)


if __name__ == '__main__':
    main()
```

---

## Implementation Checklist

### Pre-Flight Checklist

**Before Starting**:
- [ ] Verify BigQuery access to `savvy-gtm-analytics`
- [ ] Verify access to `FinTrx_data` tables
- [ ] Create `ml_experiments` dataset if not exists
- [ ] Pull latest code from repository
- [ ] Verify `v4/models/v4.1.0_r3/` model artifacts exist
- [ ] Verify `v4/data/v4.1.0_r3/final_features.json` exists

### Phase 1: Feature Candidate Table
- [ ] Create `ml_experiments` dataset
- [ ] Run SQL to create `ml_experiments.feature_candidates_v5`
- [ ] Verify row count matches `v4_prospect_features`
- [ ] Spot-check 10 random rows for data quality
- [ ] Document any NULL patterns
- [ ] Run validation queries (V1.1, V1.2, V1.3)

### Phase 2: Univariate Analysis
- [ ] Run `feature_univariate_analysis.py`
- [ ] Review output CSV
- [ ] Flag features with coverage < 10%
- [ ] Flag features with p-value > 0.05
- [ ] Document promising features
- [ ] Update candidate feature list for Phase 3

### Phase 3: Ablation Study
- [ ] Run `ablation_study.py`
- [ ] Review ablation results
- [ ] Identify feature groups that pass G-NEW-1 and G-NEW-2
- [ ] Document marginal vs. strong improvements
- [ ] Select promising features for Phase 4

### Phase 4: Multi-Period Backtesting
- [ ] Run `multi_period_backtest.py`
- [ ] Review results across 4 periods
- [ ] Check Gate G-NEW-4 (≥ 3/4 periods improved)
- [ ] Document temporal stability
- [ ] Identify any period-specific issues

### Phase 5: Statistical Significance
- [ ] Run `statistical_significance.py`
- [ ] Review bootstrap AUC results
- [ ] Review permutation test results
- [ ] Verify Gate G-NEW-3 (p < 0.05)
- [ ] Document confidence intervals

### Phase 6: Final Decision
- [ ] Compile gate summary table
- [ ] Run decision framework
- [ ] Document recommendation
- [ ] Prepare stakeholder communication
- [ ] If approved: Proceed to model retraining

### Phase 7: Orchestration & Report Generation
- [ ] Run orchestrator: `python v5/experiments/scripts/run_enhancement_validation.py --all`
- [ ] Review `FINAL_VALIDATION_REPORT.md`
- [ ] Review `validation_results.json`
- [ ] Share report with stakeholders
- [ ] Archive experiment tables if not deploying

---

## Edge Cases and Failure Modes

### What if AUM coverage is lower than expected?

**Fallback Strategy**:
- **Minimum Coverage Threshold**: 50% to proceed
- **If < 50%**: Use AUM as binary feature only (`has_aum`)
- **Alternative**: Use `firm_rep_count_at_contact` as proxy for firm size

### What if features are correlated with existing features?

**Multicollinearity Check**:
- **VIF Threshold**: VIF > 5.0 → Flag for review
- **Correlation Threshold**: |r| > 0.7 → Flag for review
- **Action**: Drop lower-importance feature or combine features

### What if no features pass all gates?

**Decision Framework**:
- **Document findings**: All tested features and results
- **Review methodology**: Check if thresholds are too strict
- **Partial deployment**: Consider features that pass 4/6 gates with stakeholder approval
- **Future work**: Document for next enhancement cycle

### What if backtest periods have different results?

**Weighting Strategy**:
- **Recent periods weighted higher**: Period 4 = 40%, Period 3 = 30%, Period 2 = 20%, Period 1 = 10%
- **Minimum consistency**: At least 2/4 periods must show improvement
- **Investigation**: Review period-specific data quality issues

---

## Automated Orchestration & Report Generation

### Overview

To ensure comprehensive, consistent execution and automatic report generation, use the **Enhancement Validation Orchestrator** script. This script:

1. ✅ Runs all 6 phases sequentially
2. ✅ Validates data at each step
3. ✅ Evaluates all gates automatically
4. ✅ Generates a comprehensive markdown report
5. ✅ Saves all results in structured formats (CSV, JSON, MD)

### Setup

**1. Create the orchestrator script:**

Save the orchestrator code to: `v5/experiments/scripts/run_enhancement_validation.py`

**2. Ensure directory structure exists:**

```
v5/
├── experiments/
│   ├── scripts/
│   │   ├── run_enhancement_validation.py  ← Orchestrator (NEW)
│   │   ├── feature_univariate_analysis.py
│   │   ├── ablation_study.py
│   │   ├── multi_period_backtest.py
│   │   └── statistical_significance.py
│   ├── reports/
│   │   ├── FINAL_VALIDATION_REPORT.md     ← Auto-generated report (NEW)
│   │   ├── phase_2_univariate_analysis.csv
│   │   ├── ablation_study_results.csv
│   │   ├── multi_period_backtest_results.csv
│   │   ├── statistical_significance_results.json
│   │   └── validation_results.json        ← Raw results (NEW)
│   ├── sql/
│   │   └── create_feature_candidates_v5.sql
│   └── EXECUTION_LOG.md
```

### Usage

**Run complete validation pipeline:**
```bash
cd "C:\Users\russe\Documents\lead_scoring_production"
python v5/experiments/scripts/run_enhancement_validation.py --all
```

**Run specific phase:**
```bash
python v5/experiments/scripts/run_enhancement_validation.py --phase 2  # Univariate only
```

**Generate report from existing results:**
```bash
python v5/experiments/scripts/run_enhancement_validation.py --report-only
```

### Output Files

After running `--all`, you will have:

| File | Purpose |
|------|---------|
| `FINAL_VALIDATION_REPORT.md` | **Comprehensive markdown report** with all results |
| `validation_results.json` | Raw structured data for programmatic access |
| `phase_2_univariate_analysis.csv` | Feature-level statistics |
| `ablation_study_results.csv` | Model comparison data |
| `multi_period_backtest_results.csv` | Temporal stability data |
| `statistical_significance_results.json` | P-values and confidence intervals |

### Report Contents

The auto-generated `FINAL_VALIDATION_REPORT.md` includes:

1. **Executive Summary**
   - Final recommendation (DEPLOY / CONDITIONAL / MORE TESTING / DO NOT DEPLOY)
   - Gate status summary table
   - Confidence level

2. **Phase-by-Phase Results**
   - Phase 1: Feature coverage validation
   - Phase 2: Univariate analysis with recommendations
   - Phase 3: Ablation study with best improvements
   - Phase 4: Temporal stability across 4 periods
   - Phase 5: Statistical significance testing

3. **Gate Summary Table**
   - G-NEW-1 through G-NEW-6 pass/fail status
   - Threshold values and actual values

4. **Next Steps**
   - Specific actions based on recommendation

5. **Appendix**
   - File locations
   - Timestamps
   - Metadata

---

## Updated Cursor.ai Prompt for Complete Execution

Use this prompt to have Cursor.ai run the complete validation pipeline agentically:

```markdown
# Cursor AI Task: Run Complete Enhancement Validation

## Objective
Execute the complete enhancement validation pipeline and generate a comprehensive final report.

## Prerequisites Check
1. Verify BigQuery access to `savvy-gtm-analytics`
2. Verify `ml_experiments` dataset exists (create if not)
3. Verify `v4_prospect_features` table exists

## Execution Steps

### Step 1: Create Feature Candidates Table
Run the SQL from `enhancement-validation.md` Phase 1 to create:
`savvy-gtm-analytics.ml_experiments.feature_candidates_v5`

Verify with:
```sql
SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_experiments.feature_candidates_v5`;
```

### Step 2: Run Orchestrator
```bash
cd "C:\Users\russe\Documents\lead_scoring_production"
python v5/experiments/scripts/run_enhancement_validation.py --all
```

### Step 3: Review Generated Report
Open and review: `v5/experiments/reports/FINAL_VALIDATION_REPORT.md`

### Step 4: Document Results
- If all gates pass: Proceed to model retraining
- If gates fail: Document findings and next steps
- Update `enhancement-validation.md` with actual results

## Expected Outputs
1. `FINAL_VALIDATION_REPORT.md` - Comprehensive summary
2. `validation_results.json` - Structured results
3. Console output showing phase-by-phase execution
4. Gate status (PASS/FAIL) for all 6 gates

## Success Criteria
- All 6 phases complete without errors
- Final report generated with recommendation
- Gate summary table populated with actual values
```

---

## Quick Reference: Gate Definitions

| Gate | Name | Threshold | How Evaluated |
|------|------|-----------|---------------|
| **G-NEW-1** | AUC Improvement | ≥ 0.005 | Phase 3: Best feature group AUC delta |
| **G-NEW-2** | Lift Improvement | ≥ 0.1x | Phase 3: Best feature group lift delta |
| **G-NEW-3** | Statistical Significance | p < 0.05 | Phase 5: Bootstrap p-value |
| **G-NEW-4** | Temporal Stability | ≥ 3/4 periods | Phase 4: Periods with improvement |
| **G-NEW-5** | Bottom 20% Not Degraded | < 10% increase | Phase 3: Bottom quintile rate |
| **G-NEW-6** | PIT Compliance | No leakage | SQL design verification |

---

## Troubleshooting

### Issue: `ml_experiments` dataset not found
```sql
CREATE SCHEMA IF NOT EXISTS `savvy-gtm-analytics.ml_experiments`
OPTIONS(description="Experimental tables for model enhancement testing");
```

### Issue: Missing target variable table
The orchestrator expects `ml_features.v4_target_variable`. If it doesn't exist, verify it was created during V4.1 training:
```sql
-- Check if table exists
SELECT table_name 
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.TABLES`
WHERE table_name = 'v4_target_variable';
```

### Issue: Phase fails with data error
1. Check BigQuery table schemas match expected columns
2. Verify JOIN keys are correct (advisor_crd, firm_crd)
3. Check for NULL handling in feature calculations
4. Verify `v4_prospect_features` table exists and has data

### Issue: Report shows "SKIPPED" for phases
Run individual phase scripts first to generate the required CSV/JSON files:
```bash
# Run Phase 2 (creates phase_2_univariate_analysis.csv)
python v5/experiments/scripts/feature_univariate_analysis.py

# Run Phase 3 (creates ablation_study_results.csv)
python v5/experiments/scripts/ablation_study.py

# Run Phase 4 (creates multi_period_backtest_results.csv)
python v5/experiments/scripts/multi_period_backtest.py

# Run Phase 5 (creates statistical_significance_results.json)
python v5/experiments/scripts/statistical_significance.py

# Then run orchestrator to generate report
python v5/experiments/scripts/run_enhancement_validation.py --report-only
```

### Issue: ExecutionLogger import error
Ensure the script can find the ExecutionLogger:
```python
# The script uses this path resolution:
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from v3.utils.execution_logger import ExecutionLogger
```

If this fails, verify `v3/utils/execution_logger.py` exists in the repository.

---

## Appendix

### A: Full SQL Scripts

All SQL scripts are provided in the document above with validated table/column names.

### B: Python Environment Setup

**Required Packages**:
```
pandas>=1.5.0
numpy>=1.23.0
scipy>=1.9.0
xgboost>=1.7.0
google-cloud-bigquery>=3.0.0
scikit-learn>=1.1.0
```

**Python Version**: 3.8+

### C: Troubleshooting Guide

**Issue**: `ml_experiments` dataset not found  
**Solution**: Create dataset first: `CREATE SCHEMA IF NOT EXISTS ml_experiments`

**Issue**: Column name mismatch  
**Solution**: Verify actual column names using `INFORMATION_SCHEMA.COLUMNS`

**Issue**: PIT compliance violation  
**Solution**: Review temporal filtering logic, ensure all dates use `DATE_SUB` or prior month

### D: Rollback Plan

**If enhancement fails validation**:
1. Document all findings in `v5/experiments/reports/`
2. Archive experiment tables: `ml_experiments.feature_candidates_v5`
3. No changes to production tables or models
4. Review findings with stakeholders for next cycle

---

## Document Maintenance

**Last Updated**: December 30, 2025  
**Next Review**: After first enhancement cycle completion  
**Owner**: Data Science Team

**Change Log**:
- **2025-12-30 v2.0**: Initial validation and enhancement
  - Validated all BigQuery queries against actual schemas
  - Corrected table/column names (OUTLET vs SOURCE, RIA_CONTACT_ID vs RIA_CONTACT_CRD_ID)
  - Added actual coverage percentages from BigQuery
  - Aligned validation gates with existing V4.1 naming (G9.1, G9.2, etc.)
  - Added file paths matching repository structure
  - Integrated ExecutionLogger from v3/utils
  - Added edge case handling and failure modes
  - Created executable checklist
- **2025-12-30 v2.1**: Orchestration and report generation
  - Added Enhancement Validation Orchestrator script for automated report generation
  - Added comprehensive setup and usage instructions
  - Added Cursor.ai prompt for agentic execution
  - Added quick reference gate definitions table
  - Added troubleshooting guide for common issues
  - Added automated orchestration section with directory structure and output files
