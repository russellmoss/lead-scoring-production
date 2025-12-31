"""
Multi-Period Backtesting: Test temporal stability of enhancements
Location: v5/experiments/scripts/multi_period_backtest.py
"""

import xgboost as xgb
from sklearn.metrics import roc_auc_score, average_precision_score
import numpy as np
import pandas as pd
from google.cloud import bigquery
from pathlib import Path
import json
import sys
import warnings
warnings.filterwarnings('ignore')

# Add project root to path
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
TARGET_TABLE = "ml_features.v4_target_variable"

# Load V4.1 R3 hyperparameters
V4_MODEL_DIR = WORKING_DIR / "v4" / "models" / "v4.1.0_r3"
with open(V4_MODEL_DIR / "hyperparameters.json", 'r') as f:
    MODEL_PARAMS = json.load(f)['hyperparameters']

# Load V4.1 R3 feature list and categorical mappings
V4_FEATURES_FILE = WORKING_DIR / "v4" / "data" / "v4.1.0_r3" / "final_features.json"
with open(V4_FEATURES_FILE, 'r') as f:
    v4_features_data = json.load(f)

BASELINE_FEATURES = v4_features_data['final_features']
CATEGORICAL_MAPPINGS = v4_features_data.get('categorical_mappings', {})

# Backtest periods (matching V4.1 methodology)
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

# Candidate features to test (from Phase 2 - even though they failed Phase 3, test for completeness)
CANDIDATE_FEATURES = ['firm_aum_bucket', 'has_accolade']

# Initialize logger
logger = ExecutionLogger(
    log_path=str(EXPERIMENTS_DIR / "EXECUTION_LOG.md"),
    version="v5"
)

logger.start_phase("4.1", "Multi-Period Backtesting")

# ============================================================================
# HELPER FUNCTIONS (from ablation_study.py)
# ============================================================================
def encode_categorical_features(df, categorical_mappings):
    """Encode categorical features using V4.1 mappings."""
    df_encoded = df.copy()
    
    for cat_col, mapping in categorical_mappings.items():
        if cat_col in df_encoded.columns:
            reverse_mapping = {v: int(k) for k, v in mapping.items()}
            encoded_col = f"{cat_col}_encoded"
            df_encoded[encoded_col] = df_encoded[cat_col].map(reverse_mapping).fillna(0).astype(int)
    
    if 'firm_aum_bucket' in df_encoded.columns:
        aum_mapping = {
            'Unknown': 0,
            'Small (<$100M)': 1,
            'Mid ($100M-$500M)': 2,
            'Large ($500M-$1B)': 3,
            'Very Large (>$1B)': 4
        }
        df_encoded['firm_aum_bucket_encoded'] = df_encoded['firm_aum_bucket'].map(aum_mapping).fillna(0).astype(int)
    
    return df_encoded

def prepare_features(df, feature_list):
    """Prepare features for model training."""
    df_prep = df.copy()
    df_prep = encode_categorical_features(df_prep, CATEGORICAL_MAPPINGS)
    
    final_features = []
    for feat in feature_list:
        if f"{feat}_encoded" in df_prep.columns:
            final_features.append(f"{feat}_encoded")
        elif feat in df_prep.columns:
            final_features.append(feat)
        elif feat.replace('_encoded', '') in df_prep.columns:
            base_feat = feat.replace('_encoded', '')
            if base_feat == 'firm_aum_bucket':
                aum_mapping = {
                    'Unknown': 0,
                    'Small (<$100M)': 1,
                    'Mid ($100M-$500M)': 2,
                    'Large ($500M-$1B)': 3,
                    'Very Large (>$1B)': 4
                }
                df_prep[f"{base_feat}_encoded"] = df_prep[base_feat].map(aum_mapping).fillna(0).astype(int)
                final_features.append(f"{base_feat}_encoded")
            else:
                final_features.append(base_feat)
    
    X = df_prep[final_features].copy()
    numeric_cols = X.select_dtypes(include=[np.number]).columns
    X[numeric_cols] = X[numeric_cols].fillna(0)
    
    for col in X.columns:
        if X[col].dtype == 'object':
            X[col] = pd.to_numeric(X[col], errors='coerce').fillna(0).astype(int)
    
    return X, final_features

def calculate_top_decile_lift(y_true, y_pred):
    """Calculate conversion lift in top decile"""
    df_temp = pd.DataFrame({'y_true': y_true, 'y_pred': y_pred})
    df_temp['decile'] = pd.qcut(df_temp['y_pred'], q=10, labels=False, duplicates='drop')
    top_decile_rate = df_temp[df_temp['decile'] == df_temp['decile'].max()]['y_true'].mean()
    baseline_rate = df_temp['y_true'].mean()
    return top_decile_rate / baseline_rate if baseline_rate > 0 else 0

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
df['contacted_date'] = pd.to_datetime(df['contacted_date'])

logger.log_metric("Total Rows", len(df))
logger.log_metric("Date Range", f"{df['contacted_date'].min().date()} to {df['contacted_date'].max().date()}")

# ============================================================================
# MULTI-PERIOD BACKTESTING
# ============================================================================
def run_period_backtest(df, period, baseline_features, candidate_features, target='target_mql_43d'):
    """Run backtest for a single period."""
    train_start = pd.to_datetime(period['train_start'])
    train_end = pd.to_datetime(period['train_end'])
    test_start = pd.to_datetime(period['test_start'])
    test_end = pd.to_datetime(period['test_end'])
    
    # Filter data for this period
    train_df = df[(df['contacted_date'] >= train_start) & (df['contacted_date'] <= train_end)].copy()
    test_df = df[(df['contacted_date'] >= test_start) & (df['contacted_date'] <= test_end)].copy()
    
    if len(train_df) < 100 or len(test_df) < 50:
        return None
    
    y_train = train_df[target].values
    y_test = test_df[target].values
    
    # Calculate scale_pos_weight
    scale_pos_weight = (y_train == 0).sum() / (y_train == 1).sum() if (y_train == 1).sum() > 0 else 1.0
    params = MODEL_PARAMS.copy()
    params['scale_pos_weight'] = scale_pos_weight
    params['early_stopping_rounds'] = 150
    params['n_estimators'] = 2000
    
    results = {
        'period': period['name'],
        'train_start': period['train_start'],
        'train_end': period['train_end'],
        'test_start': period['test_start'],
        'test_end': period['test_end'],
        'train_rows': len(train_df),
        'test_rows': len(test_df)
    }
    
    # BASELINE MODEL
    X_train_base, base_feature_list = prepare_features(train_df, baseline_features)
    X_test_base, _ = prepare_features(test_df, baseline_features)
    common_features = list(set(X_train_base.columns) & set(X_test_base.columns))
    X_train_base = X_train_base[common_features]
    X_test_base = X_test_base[common_features]
    
    model_base = xgb.XGBClassifier(**params)
    model_base.fit(X_train_base, y_train, eval_set=[(X_test_base, y_test)], verbose=False)
    y_pred_base = model_base.predict_proba(X_test_base)[:, 1]
    auc_base = roc_auc_score(y_test, y_pred_base)
    lift_base = calculate_top_decile_lift(y_test, y_pred_base)
    
    results['baseline_auc'] = auc_base
    results['baseline_lift'] = lift_base
    
    # ENHANCED MODEL (baseline + candidate features)
    all_features = baseline_features + [f for f in candidate_features if f in df.columns]
    X_train_enh, _ = prepare_features(train_df, all_features)
    X_test_enh, _ = prepare_features(test_df, all_features)
    common_features_enh = list(set(X_train_enh.columns) & set(X_test_enh.columns))
    X_train_enh = X_train_enh[common_features_enh]
    X_test_enh = X_test_enh[common_features_enh]
    
    model_enh = xgb.XGBClassifier(**params)
    model_enh.fit(X_train_enh, y_train, eval_set=[(X_test_enh, y_test)], verbose=False)
    y_pred_enh = model_enh.predict_proba(X_test_enh)[:, 1]
    auc_enh = roc_auc_score(y_test, y_pred_enh)
    lift_enh = calculate_top_decile_lift(y_test, y_pred_enh)
    
    results['enhanced_auc'] = auc_enh
    results['enhanced_lift'] = lift_enh
    results['auc_improvement'] = auc_enh - auc_base
    results['lift_improvement'] = lift_enh - lift_base
    results['auc_improved'] = 1 if results['auc_improvement'] > 0 else 0
    results['lift_improved'] = 1 if results['lift_improvement'] > 0 else 0
    
    return results

# ============================================================================
# RUN ALL PERIODS
# ============================================================================
print("="*60)
print("MULTI-PERIOD BACKTESTING")
print("="*60)
print(f"Testing {len(BACKTEST_PERIODS)} periods")
print(f"Candidate features: {CANDIDATE_FEATURES}")

all_results = []
for period in BACKTEST_PERIODS:
    print(f"\n{'='*60}")
    print(f"Testing {period['name']}...")
    print('='*60)
    
    result = run_period_backtest(df, period, BASELINE_FEATURES, CANDIDATE_FEATURES)
    if result:
        all_results.append(result)
        print(f"  Train: {result['train_rows']} rows, Test: {result['test_rows']} rows")
        print(f"  Baseline AUC: {result['baseline_auc']:.4f}, Lift: {result['baseline_lift']:.2f}x")
        print(f"  Enhanced AUC: {result['enhanced_auc']:.4f}, Lift: {result['enhanced_lift']:.2f}x")
        print(f"  AUC Improvement: {result['auc_improvement']:+.4f}")
        print(f"  Lift Improvement: {result['lift_improvement']:+.2f}x")
        print(f"  Improved: {'YES' if result['auc_improved'] else 'NO'}")
    else:
        print(f"  Skipped - insufficient data")

# Save results
if all_results:
    results_df = pd.DataFrame(all_results)
    output_path = REPORTS_DIR / "multi_period_backtest_results.csv"
    results_df.to_csv(output_path, index=False)
    logger.log_file_created("multi_period_backtest_results.csv", str(output_path), "Multi-period backtest results")
    
    periods_improved = results_df['auc_improved'].sum()
    periods_tested = len(results_df)
    
    logger.log_metric("Periods Tested", periods_tested)
    logger.log_metric("Periods Improved", periods_improved)
    logger.log_validation_gate(
        "G-NEW-4",
        "Temporal stability (>= 3/4 periods)",
        periods_improved >= 3,
        f"Improved in {periods_improved}/{periods_tested} periods"
    )
    
    print("\n" + "="*60)
    print("MULTI-PERIOD BACKTEST SUMMARY")
    print("="*60)
    print(f"Periods tested: {periods_tested}")
    print(f"Periods improved: {periods_improved}")
    print(f"Gate G-NEW-4: {'PASSED' if periods_improved >= 3 else 'FAILED'}")
    print("\nDetailed results:")
    print(results_df[['period', 'baseline_auc', 'enhanced_auc', 'auc_improvement', 'auc_improved']].to_string(index=False))
else:
    print("\n[WARNING] No periods had sufficient data for backtesting")

logger.end_phase(
    status="PASSED",
    next_steps=["Proceed to Phase 5: Statistical Significance Testing"]
)

print("\n[SUCCESS] Phase 4 complete! Results saved to:", REPORTS_DIR / "multi_period_backtest_results.csv")

