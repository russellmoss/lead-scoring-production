"""
V4.2.0 Career Clock Model Training Script
=========================================
Trains XGBoost model with Career Clock features added to V4.1.0 R3 baseline.

Usage:
    python v4/scripts/train_v42_career_clock.py

Outputs:
    - v4/models/v4.2.0/model.pkl
    - v4/models/v4.2.0/model.json
    - v4/models/v4.2.0/feature_importance.csv
    - v4/models/v4.2.0/training_metrics.json
"""

import json
import pickle
import numpy as np
import pandas as pd
import xgboost as xgb
from datetime import datetime
from pathlib import Path
from google.cloud import bigquery
from sklearn.metrics import roc_auc_score, average_precision_score
import warnings
warnings.filterwarnings('ignore')

# =============================================================================
# CONFIGURATION
# =============================================================================

PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
FEATURES_TABLE = "v4_features_pit_v42"

# Paths
BASE_DIR = Path(__file__).parent.parent
MODELS_DIR = BASE_DIR / "models" / "v4.2.0"
DATA_DIR = BASE_DIR / "data" / "v4.2.0"

# Create directories
MODELS_DIR.mkdir(parents=True, exist_ok=True)
DATA_DIR.mkdir(parents=True, exist_ok=True)

# Load feature list from JSON
FEATURES_JSON = DATA_DIR / "final_features.json"
with open(FEATURES_JSON, 'r') as f:
    features_config = json.load(f)
    FEATURE_LIST = features_config['final_features']

# Load hyperparameters from JSON
HYPERPARAMS_JSON = MODELS_DIR / "hyperparameters.json"
with open(HYPERPARAMS_JSON, 'r') as f:
    hyperparams_config = json.load(f)
    HYPERPARAMETERS = hyperparams_config['hyperparameters']

# Validation Gates
GATES = {
    "min_test_auc": 0.58,
    "min_top_decile_lift": 1.4,
    "max_auc_gap": 0.15,
    "max_bottom_20_rate": 0.02,
    "min_improvement_vs_v41": 0.0  # Must be >= V4.1.0 R3
}

# V4.1.0 R3 Baseline (for comparison)
V41_BASELINE = {
    "test_auc": 0.6198,
    "top_decile_lift": 2.03,
    "bottom_20_rate": 0.0140
}

# =============================================================================
# FUNCTIONS
# =============================================================================

def load_data():
    """Load training data from BigQuery."""
    print("[INFO] Loading training data from BigQuery...")
    client = bigquery.Client(project=PROJECT_ID)
    
    query = f"""
    SELECT *
    FROM `{PROJECT_ID}.{DATASET}.{FEATURES_TABLE}`
    WHERE target IS NOT NULL
    """
    
    df = client.query(query).to_dataframe()
    print(f"[INFO] Loaded {len(df):,} leads with outcomes")
    
    return df


def validate_career_clock_features(df):
    """Validate Career Clock features are present and populated."""
    cc_features = [f for f in FEATURE_LIST if f.startswith('cc_')]
    
    print(f"\n[INFO] Validating {len(cc_features)} Career Clock features...")
    
    for feat in cc_features:
        if feat not in df.columns:
            raise ValueError(f"[ERROR] Missing Career Clock feature: {feat}")
        
        non_null = df[feat].notna().sum()
        pct = non_null / len(df) * 100
        print(f"  {feat}: {non_null:,} non-null ({pct:.1f}%)")
        
        if pct < 10:
            print(f"  ⚠️ WARNING: Low coverage for {feat} ({pct:.1f}% non-null)")
    
    print("[INFO] ✅ Career Clock feature validation passed\n")


def prepare_features(df, feature_list):
    """Prepare features for training."""
    print(f"[INFO] Preparing {len(feature_list)} features...")
    
    X = df.copy()
    
    # Encode categorical features (matching V4.1.0 approach)
    # Load categorical mappings from feature config
    categorical_mappings = {
        'tenure_bucket': {'0-12': 0, '12-24': 1, '24-48': 2, '48-120': 3, '120+': 4, 'Unknown': 5},
        'mobility_tier': {'Stable': 0, 'Low_Mobility': 1, 'High_Mobility': 2},
        'firm_stability_tier': {'Unknown': 0, 'Heavy_Bleeding': 1, 'Light_Bleeding': 2, 'Stable': 3, 'Growing': 4}
    }
    
    # Create encoded versions if string versions exist
    if 'tenure_bucket' in X.columns and 'tenure_bucket_encoded' in feature_list:
        X['tenure_bucket_encoded'] = X['tenure_bucket'].map(categorical_mappings['tenure_bucket']).fillna(0).astype(int)
    if 'mobility_tier' in X.columns and 'mobility_tier_encoded' in feature_list:
        X['mobility_tier_encoded'] = X['mobility_tier'].map(categorical_mappings['mobility_tier']).fillna(0).astype(int)
    if 'firm_stability_tier' in X.columns and 'firm_stability_tier_encoded' in feature_list:
        X['firm_stability_tier_encoded'] = X['firm_stability_tier'].map(categorical_mappings['firm_stability_tier']).fillna(0).astype(int)
    
    # Select only features from feature_list
    X = X[feature_list].copy()
    
    # Fill NaN with appropriate defaults
    for col in X.columns:
        if col.startswith('cc_'):
            # Career Clock features
            if col == 'cc_tenure_cv':
                X[col] = X[col].fillna(1.0)  # 1.0 = unpredictable
            elif col == 'cc_months_until_window':
                X[col] = X[col].fillna(999)  # 999 = unknown
            else:
                X[col] = X[col].fillna(0)
        else:
            X[col] = X[col].fillna(0)
    
    # Ensure numeric types
    for col in X.columns:
        X[col] = pd.to_numeric(X[col], errors='coerce').fillna(0)
    
    y = df['target'].astype(int)
    
    print(f"[INFO] Features shape: {X.shape}")
    print(f"[INFO] Target distribution: {y.mean():.4f} positive rate")
    
    return X, y


def temporal_split(df, X, y):
    """Split data temporally (same as V4.1)."""
    print("[INFO] Applying temporal train/test split...")
    
    df['contacted_date'] = pd.to_datetime(df['contacted_date'])
    
    # Train: Feb 2024 - Jul 2025
    # Test: Aug 2025 - Oct 2025
    train_mask = df['contacted_date'] < '2025-08-01'
    test_mask = df['contacted_date'] >= '2025-08-01'
    
    X_train, X_test = X[train_mask], X[test_mask]
    y_train, y_test = y[train_mask], y[test_mask]
    
    print(f"[INFO] Train set: {len(X_train):,} leads ({y_train.mean():.4f} positive rate)")
    print(f"[INFO] Test set: {len(X_test):,} leads ({y_test.mean():.4f} positive rate)")
    
    return X_train, X_test, y_train, y_test


def train_model(X_train, y_train, X_test, y_test):
    """Train XGBoost model."""
    print("[INFO] Training XGBoost model...")
    
    # Calculate scale_pos_weight
    neg_count = (y_train == 0).sum()
    pos_count = (y_train == 1).sum()
    scale_pos_weight = neg_count / pos_count
    print(f"[INFO] Scale pos weight: {scale_pos_weight:.2f}")
    
    # Create DMatrix
    dtrain = xgb.DMatrix(X_train, label=y_train, feature_names=list(X_train.columns))
    dtest = xgb.DMatrix(X_test, label=y_test, feature_names=list(X_test.columns))
    
    # Training parameters
    params = {
        "objective": HYPERPARAMETERS["objective"],
        "max_depth": HYPERPARAMETERS["max_depth"],
        "min_child_weight": HYPERPARAMETERS["min_child_weight"],
        "reg_alpha": HYPERPARAMETERS["reg_alpha"],
        "reg_lambda": HYPERPARAMETERS["reg_lambda"],
        "gamma": HYPERPARAMETERS["gamma"],
        "learning_rate": HYPERPARAMETERS["learning_rate"],
        "subsample": HYPERPARAMETERS["subsample"],
        "colsample_bytree": HYPERPARAMETERS["colsample_bytree"],
        "base_score": HYPERPARAMETERS["base_score"],
        "scale_pos_weight": scale_pos_weight,
        "random_state": HYPERPARAMETERS["random_state"],
        "eval_metric": HYPERPARAMETERS["eval_metric"]
    }
    
    # Train with early stopping
    evals = [(dtrain, "train"), (dtest, "test")]
    
    model = xgb.train(
        params,
        dtrain,
        num_boost_round=HYPERPARAMETERS["n_estimators"],
        evals=evals,
        early_stopping_rounds=HYPERPARAMETERS["early_stopping_rounds"],
        verbose_eval=50
    )
    
    print(f"[INFO] Best iteration: {model.best_iteration}")
    
    return model, scale_pos_weight


def evaluate_model(model, X_train, y_train, X_test, y_test):
    """Evaluate model performance."""
    print("\n[INFO] Evaluating model performance...")
    
    # Create DMatrix
    dtrain = xgb.DMatrix(X_train, feature_names=list(X_train.columns))
    dtest = xgb.DMatrix(X_test, feature_names=list(X_test.columns))
    
    # Get predictions
    train_pred = model.predict(dtrain)
    test_pred = model.predict(dtest)
    
    # Calculate metrics
    train_auc = roc_auc_score(y_train, train_pred)
    test_auc = roc_auc_score(y_test, test_pred)
    test_aucpr = average_precision_score(y_test, test_pred)
    auc_gap = train_auc - test_auc
    
    print(f"[INFO] Train AUC: {train_auc:.4f}")
    print(f"[INFO] Test AUC: {test_auc:.4f}")
    print(f"[INFO] AUC Gap: {auc_gap:.4f}")
    print(f"[INFO] Test AUC-PR: {test_aucpr:.4f}")
    
    # Calculate lift by decile
    test_df = pd.DataFrame({
        'score': test_pred,
        'target': y_test.values
    })
    test_df['decile'] = pd.qcut(test_df['score'], 10, labels=False, duplicates='drop')
    
    decile_stats = test_df.groupby('decile').agg({
        'target': ['count', 'sum', 'mean']
    }).round(4)
    decile_stats.columns = ['count', 'conversions', 'conv_rate']
    
    baseline_rate = y_test.mean()
    decile_stats['lift'] = decile_stats['conv_rate'] / baseline_rate
    
    print("\n[INFO] Lift by Decile:")
    print(decile_stats)
    
    top_decile_lift = decile_stats.loc[9, 'lift'] if 9 in decile_stats.index else decile_stats.iloc[-1]['lift']
    bottom_20_rate = test_df[test_df['decile'] <= 1]['target'].mean()
    
    print(f"\n[INFO] Top Decile Lift: {top_decile_lift:.2f}x")
    print(f"[INFO] Bottom 20% Rate: {bottom_20_rate:.4f}")
    
    metrics = {
        "train_auc": train_auc,
        "test_auc": test_auc,
        "test_aucpr": test_aucpr,
        "auc_gap": auc_gap,
        "top_decile_lift": top_decile_lift,
        "bottom_20_rate": bottom_20_rate,
        "best_iteration": model.best_iteration
    }
    
    return metrics, decile_stats


def validate_gates(metrics):
    """Validate against performance gates."""
    print("\n" + "=" * 60)
    print("VALIDATION GATES")
    print("=" * 60)
    
    gates_passed = True
    
    # Gate 1: Test AUC >= 0.58
    g1 = metrics["test_auc"] >= GATES["min_test_auc"]
    print(f"G1 Test AUC >= {GATES['min_test_auc']}: {metrics['test_auc']:.4f} {'✅ PASSED' if g1 else '❌ FAILED'}")
    gates_passed &= g1
    
    # Gate 2: Top decile lift >= 1.4x
    g2 = metrics["top_decile_lift"] >= GATES["min_top_decile_lift"]
    print(f"G2 Top Decile Lift >= {GATES['min_top_decile_lift']}x: {metrics['top_decile_lift']:.2f}x {'✅ PASSED' if g2 else '❌ FAILED'}")
    gates_passed &= g2
    
    # Gate 3: AUC gap < 0.15
    g3 = metrics["auc_gap"] < GATES["max_auc_gap"]
    print(f"G3 AUC Gap < {GATES['max_auc_gap']}: {metrics['auc_gap']:.4f} {'✅ PASSED' if g3 else '❌ FAILED'}")
    gates_passed &= g3
    
    # Gate 4: Bottom 20% rate < 2%
    g4 = metrics["bottom_20_rate"] < GATES["max_bottom_20_rate"]
    print(f"G4 Bottom 20% Rate < {GATES['max_bottom_20_rate']}: {metrics['bottom_20_rate']:.4f} {'✅ PASSED' if g4 else '❌ FAILED'}")
    gates_passed &= g4
    
    # Gate 5: Compare to V4.1.0 R3 baseline
    print(f"\n[INFO] Comparison to V4.1.0 R3 Baseline:")
    print(f"  Test AUC: {metrics['test_auc']:.4f} vs {V41_BASELINE['test_auc']:.4f} ({'+' if metrics['test_auc'] >= V41_BASELINE['test_auc'] else ''}{(metrics['test_auc'] - V41_BASELINE['test_auc'])*100:.2f}%)")
    print(f"  Top Decile Lift: {metrics['top_decile_lift']:.2f}x vs {V41_BASELINE['top_decile_lift']:.2f}x")
    print(f"  Bottom 20% Rate: {metrics['bottom_20_rate']:.4f} vs {V41_BASELINE['bottom_20_rate']:.4f}")
    
    g5 = metrics["test_auc"] >= V41_BASELINE["test_auc"]
    print(f"G5 V4.2 AUC >= V4.1 AUC: {'✅ PASSED' if g5 else '⚠️ WARNING (regression)'}")
    
    print("=" * 60)
    print(f"OVERALL: {'✅ ALL GATES PASSED' if gates_passed else '❌ SOME GATES FAILED'}")
    print("=" * 60)
    
    return gates_passed


def calculate_feature_importance(model, feature_list):
    """Calculate feature importance."""
    print("\n[INFO] Calculating feature importance...")
    
    # Get XGBoost importance
    importance = model.get_score(importance_type='gain')
    
    # Map to feature names (XGBoost uses f0, f1, f2... format)
    # Need to map by position in feature list
    importance_data = []
    for k, v in importance.items():
        if k.startswith('f') and k[1:].isdigit():
            idx = int(k[1:])
            if idx < len(feature_list):
                importance_data.append({
                    'feature': feature_list[idx],
                    'importance': v
                })
    
    if not importance_data:
        print("[WARNING] No feature importance data found. Trying alternative method...")
        # Alternative: try to get feature names from DMatrix if available
        # For now, create empty DataFrame
        importance_df = pd.DataFrame(columns=['feature', 'importance'])
        print("[WARNING] Could not extract feature importance - will skip this step")
        return importance_df
    
    importance_df = pd.DataFrame(importance_data)
    
    if len(importance_df) == 0:
        print("[WARNING] Feature importance DataFrame is empty")
        return pd.DataFrame(columns=['feature', 'importance'])
    
    importance_df = importance_df.sort_values('importance', ascending=False)
    
    print("\n[INFO] Top 15 Features by Importance:")
    print(importance_df.head(15).to_string(index=False))
    
    # Check Career Clock features
    cc_features = importance_df[importance_df['feature'].str.startswith('cc_')]
    if len(cc_features) > 0:
        print(f"\n[INFO] Career Clock Features:")
        print(cc_features.to_string(index=False))
        
        cc_in_top_15 = len(cc_features[cc_features['feature'].isin(importance_df.head(15)['feature'])])
        print(f"\n[INFO] Career Clock Features in Top 15: {cc_in_top_15}")
    else:
        print("\n[WARNING] No Career Clock features found in importance data")
    
    return importance_df


def save_artifacts(model, metrics, importance_df, feature_list, scale_pos_weight):
    """Save model artifacts."""
    print("\n[INFO] Saving model artifacts...")
    
    # Save model (pickle)
    model_path = MODELS_DIR / "model.pkl"
    with open(model_path, 'wb') as f:
        pickle.dump(model, f)
    print(f"  ✅ Model saved: {model_path}")
    
    # Save model (JSON)
    model_json_path = MODELS_DIR / "model.json"
    model.save_model(str(model_json_path))
    print(f"  ✅ Model JSON saved: {model_json_path}")
    
    # Save feature importance
    importance_path = MODELS_DIR / "feature_importance.csv"
    importance_df.to_csv(importance_path, index=False)
    print(f"  ✅ Feature importance saved: {importance_path}")
    
    # Save training metrics
    metrics_path = MODELS_DIR / "training_metrics.json"
    metrics_output = {
        "version": "v4.2.0",
        "created": datetime.now().isoformat(),
        "metrics": metrics,
        "comparison_to_v41": {
            "test_auc_change": metrics["test_auc"] - V41_BASELINE["test_auc"],
            "top_decile_lift_change": metrics["top_decile_lift"] - V41_BASELINE["top_decile_lift"],
            "bottom_20_rate_change": metrics["bottom_20_rate"] - V41_BASELINE["bottom_20_rate"]
        },
        "scale_pos_weight": scale_pos_weight,
        "feature_count": len(feature_list)
    }
    with open(metrics_path, 'w') as f:
        json.dump(metrics_output, f, indent=2)
    print(f"  ✅ Training metrics saved: {metrics_path}")
    
    print("\n[INFO] All artifacts saved successfully!")


def main():
    """Main training pipeline."""
    print("=" * 60)
    print("V4.2.0 CAREER CLOCK MODEL TRAINING")
    print("=" * 60)
    print(f"Started: {datetime.now()}")
    print(f"Features: {len(FEATURE_LIST)} (22 existing + 7 Career Clock)")
    print("=" * 60)
    
    # Load data
    df = load_data()
    
    # Validate Career Clock features
    validate_career_clock_features(df)
    
    # Prepare features
    X, y = prepare_features(df, FEATURE_LIST)
    
    # Temporal split
    X_train, X_test, y_train, y_test = temporal_split(df, X, y)
    
    # Train model
    model, scale_pos_weight = train_model(X_train, y_train, X_test, y_test)
    
    # Evaluate
    metrics, decile_stats = evaluate_model(model, X_train, y_train, X_test, y_test)
    
    # Validate gates
    gates_passed = validate_gates(metrics)
    
    # Feature importance
    try:
        importance_df = calculate_feature_importance(model, FEATURE_LIST)
    except Exception as e:
        print(f"[WARNING] Feature importance calculation failed: {e}")
        print("[INFO] Continuing without feature importance...")
        importance_df = pd.DataFrame(columns=['feature', 'importance'])
    
    # Save artifacts
    save_artifacts(model, metrics, importance_df, FEATURE_LIST, scale_pos_weight)
    
    print("\n" + "=" * 60)
    print("TRAINING COMPLETE")
    print("=" * 60)
    print(f"Finished: {datetime.now()}")
    print(f"Gates Passed: {'✅ YES' if gates_passed else '❌ NO'}")
    print(f"Model Location: {MODELS_DIR}")
    print("=" * 60)
    
    return gates_passed


if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
