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
import warnings
warnings.filterwarnings('ignore')

# Add project root to path for ExecutionLogger
WORKING_DIR = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(WORKING_DIR))
from v3.utils.execution_logger import ExecutionLogger

# ============================================================================
# CONFIGURATION
# ============================================================================
EXPERIMENTS_DIR = WORKING_DIR / "v5" / "experiments"
REPORTS_DIR = EXPERIMENTS_DIR / "reports"
REPORTS_DIR.mkdir(parents=True, exist_ok=True)

PROJECT_ID = "savvy-gtm-analytics"
FEATURES_TABLE = "ml_experiments.feature_candidates_v5"
TARGET_TABLE = "ml_features.v4_target_variable"  # V4 target variable table

# Initialize logger
logger = ExecutionLogger(
    log_path=str(EXPERIMENTS_DIR / "EXECUTION_LOG.md"),
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
        try:
            correlation, p_value = stats.pointbiserialr(
                df.loc[valid_mask, feature_name],
                df.loc[valid_mask, target]
            )
            results['correlation'] = correlation
            results['correlation_pvalue'] = p_value
        except Exception as e:
            results['correlation'] = np.nan
            results['correlation_pvalue'] = 1.0
            results['recommendation'] = f'SKIP - Analysis error: {str(e)[:50]}'
            return results
        
        # Conversion rate by quartile
        try:
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
                try:
                    _, results['quartile_pvalue'] = stats.mannwhitneyu(q1_data, q4_data, alternative='two-sided')
                except Exception:
                    results['quartile_pvalue'] = np.nan
            else:
                results['quartile_pvalue'] = np.nan
        except Exception as e:
            results['q1_rate'] = np.nan
            results['q4_rate'] = np.nan
            results['q4_q1_lift'] = np.nan
            results['quartile_pvalue'] = np.nan
        
    # For categorical features
    else:
        # Chi-square test
        try:
            contingency = pd.crosstab(df[feature_name].fillna('Unknown'), df[target])
            if len(contingency) > 1 and len(contingency.columns) > 1:
                chi2, p_value, dof, expected = stats.chi2_contingency(contingency)
                results['chi2'] = chi2
                results['chi2_pvalue'] = p_value
            else:
                results['chi2'] = np.nan
                results['chi2_pvalue'] = 1.0
        except Exception as e:
            results['chi2'] = np.nan
            results['chi2_pvalue'] = 1.0
        
        # Conversion rate by category
        try:
            cat_rates = df.groupby(feature_name)[target].agg(['mean', 'count'])
            results['best_category'] = cat_rates['mean'].idxmax()
            results['best_category_rate'] = cat_rates['mean'].max()
            results['worst_category_rate'] = cat_rates['mean'].min()
            results['category_lift'] = results['best_category_rate'] / results['worst_category_rate'] if results['worst_category_rate'] > 0 else np.nan
        except Exception as e:
            results['best_category'] = np.nan
            results['best_category_rate'] = np.nan
            results['worst_category_rate'] = np.nan
            results['category_lift'] = np.nan
    
    # Recommendation
    p_value = results.get('correlation_pvalue', results.get('chi2_pvalue', 1.0))
    lift = results.get('q4_q1_lift', results.get('category_lift', 1.0))
    
    if pd.notna(p_value) and p_value < 0.05:
        if pd.notna(lift) and lift > 1.2:
            results['recommendation'] = 'PROMISING - Significant signal'
        else:
            results['recommendation'] = 'WEAK - Significant but small effect'
    else:
        results['recommendation'] = 'SKIP - Not significant'
    
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
        print(f"\nAnalyzing {feature}...")
        result = analyze_feature(df, feature)
        results.append(result)
        logger.log_validation_gate(
            f"G2.1.{feature}",
            f"Univariate analysis: {feature}",
            'PROMISING' in result['recommendation'],
            result['recommendation']
        )
        print(f"  {feature}: {result['recommendation']}")
        if 'q4_q1_lift' in result and pd.notna(result.get('q4_q1_lift')):
            print(f"  Q4/Q1 Lift: {result['q4_q1_lift']:.2f}x")
        if 'category_lift' in result and pd.notna(result.get('category_lift')):
            print(f"  Category Lift: {result['category_lift']:.2f}x")
        if 'correlation_pvalue' in result and pd.notna(result.get('correlation_pvalue')):
            print(f"  P-value: {result['correlation_pvalue']:.4f}")
        if 'chi2_pvalue' in result and pd.notna(result.get('chi2_pvalue')):
            print(f"  Chi2 P-value: {result['chi2_pvalue']:.4f}")

# Save results
results_df = pd.DataFrame(results)
output_path = REPORTS_DIR / "phase_2_univariate_analysis.csv"
results_df.to_csv(output_path, index=False)
logger.log_file_created("phase_2_univariate_analysis.csv", str(output_path), "Univariate analysis results")

print("\n" + "="*60)
print("FEATURES RECOMMENDED FOR MODEL TESTING:")
promising_features = results_df[results_df['recommendation'].str.contains('PROMISING', na=False)]['feature'].tolist()
print(promising_features)
logger.log_metric("Promising Features", len(promising_features))

print("\n" + "="*60)
print("SUMMARY:")
print(f"Total features analyzed: {len(results)}")
print(f"Promising features: {len(promising_features)}")
print(f"Weak features: {len(results_df[results_df['recommendation'].str.contains('WEAK', na=False)])}")
print(f"Skipped features: {len(results_df[results_df['recommendation'].str.contains('SKIP', na=False)])}")

logger.end_phase(
    status="PASSED",
    next_steps=["Proceed to Phase 3: Ablation Study"]
)

print("\n[SUCCESS] Phase 2 complete! Results saved to:", output_path)

