"""
Ablation Study: Test marginal value of each candidate feature
Location: v5/experiments/scripts/ablation_study.py
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

# V4.1 baseline features (from final_features.json)
BASELINE_FEATURES = v4_features_data['final_features']

# Categorical mappings from V4.1
CATEGORICAL_MAPPINGS = v4_features_data.get('categorical_mappings', {})

# Candidate features to test (from Phase 2 univariate analysis - only promising ones)
CANDIDATE_FEATURES = {
    'firm_aum_bucket': ['firm_aum_bucket'],  # Categorical - needs encoding
    'has_accolade': ['has_accolade'],  # Binary - ready to use
    'combined_promising': ['firm_aum_bucket', 'has_accolade']  # Test both together
}

# Initialize logger
logger = ExecutionLogger(
    log_path=str(EXPERIMENTS_DIR / "EXECUTION_LOG.md"),
    version="v5"
)

logger.start_phase("3.1", "Ablation Study")

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
def encode_categorical_features(df, categorical_mappings):
    """Encode categorical features using V4.1 mappings."""
    df_encoded = df.copy()
    
    # Encode existing V4.1 categoricals
    for cat_col, mapping in categorical_mappings.items():
        if cat_col in df_encoded.columns:
            # Reverse mapping: string -> int
            reverse_mapping = {v: int(k) for k, v in mapping.items()}
            encoded_col = f"{cat_col}_encoded"
            df_encoded[encoded_col] = df_encoded[cat_col].map(reverse_mapping).fillna(0).astype(int)
    
    # Encode firm_aum_bucket (new feature)
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
    """Prepare features for model training, handling encoding and missing values."""
    df_prep = df.copy()
    
    # Encode categorical features FIRST (before selecting)
    df_prep = encode_categorical_features(df_prep, CATEGORICAL_MAPPINGS)
    
    # Build final feature list (replace categorical names with encoded versions)
    final_features = []
    for feat in feature_list:
        # Check for encoded version first
        if f"{feat}_encoded" in df_prep.columns:
            final_features.append(f"{feat}_encoded")
        elif feat in df_prep.columns:
            final_features.append(feat)
        elif feat.replace('_encoded', '') in df_prep.columns:
            # Feature exists without _encoded suffix, check if we need to encode it
            base_feat = feat.replace('_encoded', '')
            if base_feat in ['tenure_bucket', 'mobility_tier', 'firm_stability_tier', 'firm_aum_bucket']:
                # Should have been encoded, use encoded version
                if f"{base_feat}_encoded" in df_prep.columns:
                    final_features.append(f"{base_feat}_encoded")
                else:
                    # Encode on the fly
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
    
    # Select and fill missing values
    X = df_prep[final_features].copy()
    
    # Fill numeric columns
    numeric_cols = X.select_dtypes(include=[np.number]).columns
    X[numeric_cols] = X[numeric_cols].fillna(0)
    
    # Convert any remaining object columns to numeric (shouldn't happen after encoding)
    for col in X.columns:
        if X[col].dtype == 'object':
            # Try to convert to numeric first
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

logger.log_metric("Total Rows", len(df))
logger.log_metric("Positive Class Rate", df['target_mql_43d'].mean())

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
    
    train_df = df_sorted[df_sorted['contacted_date'] <= train_end].copy()
    test_df = df_sorted[df_sorted['contacted_date'] > train_end].copy()
    
    y_train = train_df[target].values
    y_test = test_df[target].values
    
    logger.log_metric("Train Rows", len(train_df))
    logger.log_metric("Test Rows", len(test_df))
    
    # Calculate scale_pos_weight
    scale_pos_weight = (y_train == 0).sum() / (y_train == 1).sum()
    params = MODEL_PARAMS.copy()
    params['scale_pos_weight'] = scale_pos_weight
    params['early_stopping_rounds'] = 150
    params['n_estimators'] = 2000
    
    # 1. BASELINE MODEL
    print("\n" + "="*60)
    print("Training baseline model (V4.1 features only)...")
    print("="*60)
    
    X_train_base, base_feature_list = prepare_features(train_df, baseline_features)
    X_test_base, _ = prepare_features(test_df, baseline_features)
    
    # Ensure same features in train and test
    common_features = list(set(X_train_base.columns) & set(X_test_base.columns))
    X_train_base = X_train_base[common_features]
    X_test_base = X_test_base[common_features]
    
    model_base = xgb.XGBClassifier(**params)
    model_base.fit(
        X_train_base, y_train,
        eval_set=[(X_test_base, y_test)],
        verbose=False
    )
    
    y_pred_base = model_base.predict_proba(X_test_base)[:, 1]
    auc_base = roc_auc_score(y_test, y_pred_base)
    pr_auc_base = average_precision_score(y_test, y_pred_base)
    lift_base = calculate_top_decile_lift(y_test, y_pred_base)
    
    results.append({
        'model': 'BASELINE (V4.1 features)',
        'features': len(common_features),
        'test_auc': auc_base,
        'test_pr_auc': pr_auc_base,
        'top_decile_lift': lift_base,
        'auc_delta': 0,
        'lift_delta': 0,
        'recommendation': 'BASELINE'
    })
    print(f"  Baseline AUC: {auc_base:.4f}, PR-AUC: {pr_auc_base:.4f}, Lift: {lift_base:.2f}x")
    
    # 2. TEST EACH FEATURE GROUP
    for group_name, features in candidate_groups.items():
        print(f"\n{'='*60}")
        print(f"Testing {group_name}...")
        print('='*60)
        
        # Filter to features that exist in data
        valid_features = [f for f in features if f in df.columns]
        if not valid_features:
            print(f"  Skipping {group_name} - no valid features")
            continue
        
        # Combine baseline + candidate features
        all_features = baseline_features + valid_features
        X_train, train_feature_list = prepare_features(train_df, all_features)
        X_test, _ = prepare_features(test_df, all_features)
        
        # Ensure same features in train and test
        common_features = list(set(X_train.columns) & set(X_test.columns))
        X_train = X_train[common_features]
        X_test = X_test[common_features]
        
        model = xgb.XGBClassifier(**params)
        model.fit(
            X_train, y_train,
            eval_set=[(X_test, y_test)],
            verbose=False
        )
        
        y_pred = model.predict_proba(X_test)[:, 1]
        auc = roc_auc_score(y_test, y_pred)
        pr_auc = average_precision_score(y_test, y_pred)
        lift = calculate_top_decile_lift(y_test, y_pred)
        
        auc_delta = auc - auc_base
        lift_delta = lift - lift_base
        
        # Determine recommendation based on gates
        if auc_delta >= 0.005 and lift_delta >= 0.1:
            recommendation = 'STRONG - Passes G-NEW-1 and G-NEW-2'
        elif auc_delta >= 0.005 or lift_delta >= 0.1:
            recommendation = 'MARGINAL - Passes one gate'
        elif auc_delta < 0 or lift_delta < 0:
            recommendation = 'HARMFUL - Degrades performance'
        else:
            recommendation = 'WEAK - Does not pass gates'
        
        results.append({
            'model': f'+ {group_name}',
            'features': len(common_features),
            'test_auc': auc,
            'test_pr_auc': pr_auc,
            'top_decile_lift': lift,
            'auc_delta': auc_delta,
            'lift_delta': lift_delta,
            'recommendation': recommendation
        })
        print(f"  AUC: {auc:.4f} (Delta {auc_delta:+.4f})")
        print(f"  PR-AUC: {pr_auc:.4f}")
        print(f"  Lift: {lift:.2f}x (Delta {lift_delta:+.2f})")
        print(f"  Recommendation: {recommendation}")
        
        # Log validation gate
        logger.log_validation_gate(
            f"G3.1.{group_name}",
            f"Ablation study: {group_name}",
            'STRONG' in recommendation or 'MARGINAL' in recommendation,
            recommendation
        )
    
    return pd.DataFrame(results)

# ============================================================================
# RUN ABLATION STUDY
# ============================================================================
print("="*60)
print("ABLATION STUDY: Testing Candidate Features")
print("="*60)
print(f"Baseline features: {len(BASELINE_FEATURES)}")
print(f"Candidate feature groups: {list(CANDIDATE_FEATURES.keys())}")

results_df = run_ablation_study(df, BASELINE_FEATURES, CANDIDATE_FEATURES)

print("\n" + "="*60)
print("ABLATION STUDY RESULTS")
print("="*60)
print(results_df.to_string(index=False))

# Save results
output_path = REPORTS_DIR / "ablation_study_results.csv"
results_df.to_csv(output_path, index=False)
logger.log_file_created("ablation_study_results.csv", str(output_path), "Ablation study results")

# Find best improvement
if len(results_df) > 1:
    best = results_df[results_df['model'] != 'BASELINE (V4.1 features)'].sort_values('auc_delta', ascending=False).iloc[0]
    logger.log_metric("Best AUC Improvement", best['auc_delta'])
    logger.log_metric("Best Lift Improvement", best['lift_delta'])
    logger.log_metric("Best Model", best['model'])

logger.end_phase(
    status="PASSED",
    next_steps=["Proceed to Phase 4: Multi-Period Backtesting"]
)

print("\n[SUCCESS] Phase 3 complete! Results saved to:", output_path)

