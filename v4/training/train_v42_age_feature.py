"""
V4.2.0 Model Training Script - Age Bucket Feature Addition
==========================================================
Run this script to train V4.2.0 with age_bucket as 23rd feature.
"""

import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.metrics import roc_auc_score, average_precision_score
import shap
import pickle
import json
from datetime import datetime
from google.cloud import bigquery
import os

# Configuration
MODEL_VERSION = "v4.2.0"
OUTPUT_DIR = f"v4/models/{MODEL_VERSION}"
REPORTS_DIR = "v4/reports/v4.2"

# Create directories
os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(REPORTS_DIR, exist_ok=True)

# V4.2.0 Features (23 total - was 22 in V4.1.0)
# Based on v4.1.0_r3 final_features.json + age_bucket_encoded
FEATURES_V42 = [
    # Original V4 features (12)
    'tenure_months',
    'mobility_3yr',
    'firm_rep_count_at_contact',
    'firm_net_change_12mo',
    'is_wirehouse',
    'is_broker_protocol',
    'has_email',
    'has_linkedin',
    'has_firm_data',
    'mobility_x_heavy_bleeding',
    'short_tenure_x_high_mobility',
    'experience_years',
    # Encoded categoricals (3)
    'tenure_bucket_encoded',
    'mobility_tier_encoded',
    'firm_stability_tier_encoded',
    # V4.1 Bleeding features (4)
    'is_recent_mover',
    'days_since_last_move',
    'firm_departures_corrected',
    'bleeding_velocity_encoded',
    # V4.1 Firm/Rep type features (3)
    'is_independent_ria',
    'is_ia_rep_type',
    'is_dual_registered',
    # V4.2.0 NEW: Age feature (1)
    'age_bucket_encoded'  # NEW!
]

# Hyperparameters (same as V4.1.0)
HYPERPARAMETERS = {
    "max_depth": 2,
    "min_child_weight": 30,
    "reg_alpha": 1.0,
    "reg_lambda": 5.0,
    "gamma": 0.3,
    "learning_rate": 0.01,
    "n_estimators": 2000,
    "early_stopping_rounds": 150,
    "subsample": 0.6,
    "colsample_bytree": 0.6,
    "base_score": 0.5,
    "scale_pos_weight": 41.0,  # Class imbalance ratio
    "objective": "binary:logistic",
    "eval_metric": "auc",
    "random_state": 42
}

def load_training_data():
    """Load training data from BigQuery."""
    client = bigquery.Client(project='savvy-gtm-analytics')
    
    query = """
    SELECT 
        f.*,
        s.split,
        CASE WHEN f.target = 1 THEN 1 ELSE 0 END as target_binary
    FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v42` f
    JOIN `savvy-gtm-analytics.ml_features.v4_splits_v41` s 
        ON f.lead_id = s.lead_id
    WHERE s.split IN ('TRAIN', 'TEST')
    """
    
    df = client.query(query).to_dataframe()
    print(f"Loaded {len(df)} rows")
    print(f"Train: {len(df[df['split'] == 'TRAIN'])}, Test: {len(df[df['split'] == 'TEST'])}")
    return df


def encode_categorical_features(df):
    """Encode categorical string features to numeric codes."""
    # Categorical mappings (from V4.1.0)
    categorical_mappings = {
        'tenure_bucket': {'0-12': 0, '12-24': 1, '24-48': 2, '48-120': 3, '120+': 4, 'Unknown': 5},
        'mobility_tier': {'Stable': 0, 'Low_Mobility': 1, 'High_Mobility': 2},
        'firm_stability_tier': {'Unknown': 0, 'Heavy_Bleeding': 1, 'Light_Bleeding': 2, 'Stable': 3, 'Growing': 4}
    }
    
    df = df.copy()
    
    # Create encoded versions
    if 'tenure_bucket' in df.columns:
        df['tenure_bucket_encoded'] = df['tenure_bucket'].map(categorical_mappings['tenure_bucket']).fillna(0).astype(int)
    
    if 'mobility_tier' in df.columns:
        df['mobility_tier_encoded'] = df['mobility_tier'].map(categorical_mappings['mobility_tier']).fillna(0).astype(int)
    
    if 'firm_stability_tier' in df.columns:
        df['firm_stability_tier_encoded'] = df['firm_stability_tier'].map(categorical_mappings['firm_stability_tier']).fillna(0).astype(int)
    
    return df


def train_model(df):
    """Train XGBoost model with V4.2.0 features."""
    
    # Encode categorical features
    df = encode_categorical_features(df)
    
    # Split data
    train_df = df[df['split'] == 'TRAIN'].copy()
    test_df = df[df['split'] == 'TEST'].copy()
    
    # Prepare features
    X_train = train_df[FEATURES_V42].copy()
    y_train = train_df['target_binary']
    X_test = test_df[FEATURES_V42].copy()
    y_test = test_df['target_binary']
    
    # Fill any remaining NaN
    X_train = X_train.fillna(0)
    X_test = X_test.fillna(0)
    
    # Ensure numeric types
    for col in FEATURES_V42:
        X_train[col] = pd.to_numeric(X_train[col], errors='coerce').fillna(0)
        X_test[col] = pd.to_numeric(X_test[col], errors='coerce').fillna(0)
    
    print(f"\nFeature count: {len(FEATURES_V42)}")
    print(f"Training samples: {len(X_train)}, positives: {y_train.sum()}")
    print(f"Test samples: {len(X_test)}, positives: {y_test.sum()}")
    
    # Check for missing age_bucket values
    print(f"\nAge bucket distribution (train):")
    print(X_train['age_bucket_encoded'].value_counts().sort_index())
    
    # Train XGBoost
    model = xgb.XGBClassifier(**HYPERPARAMETERS)
    
    model.fit(
        X_train, y_train,
        eval_set=[(X_train, y_train), (X_test, y_test)],
        verbose=100
    )
    
    # Predictions
    y_train_pred = model.predict_proba(X_train)[:, 1]
    y_test_pred = model.predict_proba(X_test)[:, 1]
    
    # Metrics
    train_auc = roc_auc_score(y_train, y_train_pred)
    test_auc = roc_auc_score(y_test, y_test_pred)
    test_ap = average_precision_score(y_test, y_test_pred)
    
    print(f"\n{'='*50}")
    print(f"V4.2.0 TRAINING RESULTS")
    print(f"{'='*50}")
    print(f"Train AUC-ROC: {train_auc:.4f}")
    print(f"Test AUC-ROC:  {test_auc:.4f}")
    print(f"Test AUC-PR:   {test_ap:.4f}")
    print(f"Overfitting Gap: {train_auc - test_auc:.4f}")
    print(f"{'='*50}")
    
    return model, {
        'train_auc': train_auc,
        'test_auc': test_auc,
        'test_ap': test_ap,
        'overfitting_gap': train_auc - test_auc,
        'X_train': X_train,
        'X_test': X_test,
        'y_train': y_train,
        'y_test': y_test,
        'y_test_pred': y_test_pred
    }


def validate_gates(metrics):
    """
    CRITICAL: Validate improvement gates.
    Returns (passed, gate_results)
    """
    V41_TEST_AUC = 0.620
    V41_TOP_DECILE_LIFT = 2.03
    MAX_OVERFIT_GAP = 0.15
    
    gates = {}
    
    # Gate 1: Test AUC >= V4.1.0
    gates['G1_AUC'] = {
        'criterion': f'Test AUC >= {V41_TEST_AUC}',
        'actual': metrics['test_auc'],
        'passed': metrics['test_auc'] >= V41_TEST_AUC,
        'improvement': f"+{(metrics['test_auc'] - V41_TEST_AUC)*100:.2f}%" if metrics['test_auc'] >= V41_TEST_AUC else f"{(metrics['test_auc'] - V41_TEST_AUC)*100:.2f}%"
    }
    
    # Gate 3: Overfitting check
    gates['G3_OVERFIT'] = {
        'criterion': f'Overfitting gap < {MAX_OVERFIT_GAP}',
        'actual': metrics['overfitting_gap'],
        'passed': metrics['overfitting_gap'] < MAX_OVERFIT_GAP
    }
    
    # Print results
    print(f"\n{'='*50}")
    print("VALIDATION GATES")
    print(f"{'='*50}")
    
    all_passed = True
    for gate_name, result in gates.items():
        status = "PASSED" if result['passed'] else "FAILED"
        print(f"{gate_name}: {status}")
        print(f"  Criterion: {result['criterion']}")
        print(f"  Actual: {result['actual']:.4f}")
        if not result['passed']:
            all_passed = False
    
    print(f"{'='*50}")
    if all_passed:
        print("ALL GATES PASSED - OK to proceed with deployment")
    else:
        print("GATE(S) FAILED - DO NOT DEPLOY")
    print(f"{'='*50}")
    
    return all_passed, gates


def calculate_lift_by_decile(y_true, y_pred):
    """Calculate lift by decile for Gate 2."""
    df = pd.DataFrame({'y_true': y_true, 'y_pred': y_pred})
    df['decile'] = pd.qcut(df['y_pred'], 10, labels=False, duplicates='drop')
    
    baseline_rate = y_true.mean()
    
    lift_df = df.groupby('decile').agg({
        'y_true': ['count', 'sum', 'mean']
    }).reset_index()
    lift_df.columns = ['decile', 'count', 'conversions', 'conv_rate']
    lift_df['lift'] = lift_df['conv_rate'] / baseline_rate
    
    # Top decile is decile 9 (0-indexed, highest scores)
    top_decile_lift = lift_df[lift_df['decile'] == lift_df['decile'].max()]['lift'].values[0]
    
    return lift_df, top_decile_lift


def calculate_shap_importance(model, X_train):
    """Calculate SHAP feature importance, fallback to gain if SHAP fails."""
    print("\nCalculating feature importance...")
    
    try:
        # Try SHAP first
        print("Attempting SHAP calculation...")
        explainer = shap.TreeExplainer(model)
        shap_values = explainer.shap_values(X_train.sample(min(1000, len(X_train)), random_state=42))
        
        # Feature importance from SHAP
        importance_df = pd.DataFrame({
            'feature': FEATURES_V42,
            'importance': np.abs(shap_values).mean(axis=0)
        }).sort_values('importance', ascending=False)
        
        return importance_df, shap_values, explainer
    except Exception as e:
        print(f"SHAP calculation failed: {e}")
        print("Falling back to XGBoost gain-based importance...")
        
        # Fallback to gain-based importance
        importance_dict = model.get_booster().get_score(importance_type='gain')
        
        # Map feature indices to names
        feature_importance = []
        for i, feat in enumerate(FEATURES_V42):
            # XGBoost uses f0, f1, f2... format
            key = f'f{i}'
            importance = importance_dict.get(key, 0.0)
            feature_importance.append({
                'feature': feat,
                'importance': importance
            })
        
        importance_df = pd.DataFrame(feature_importance).sort_values('importance', ascending=False)
        
        return importance_df, None, None


def save_model_artifacts(model, metrics, gates, importance_df, lift_df):
    """Save all model artifacts."""
    
    # 1. Save model
    model.save_model(f"{OUTPUT_DIR}/model.json")
    # Save model in XGBoost native JSON format (fixes base_score SHAP issue)
    model.save_model(f"{OUTPUT_DIR}/model.json")
    print(f"[INFO] Saved model to {OUTPUT_DIR}/model.json (XGBoost native format)")
    
    # Also save as pickle for backward compatibility (but mark as legacy)
    with open(f"{OUTPUT_DIR}/model_legacy.pkl", 'wb') as f:
        pickle.dump(model, f)
    print(f"[INFO] Saved legacy pickle to {OUTPUT_DIR}/model_legacy.pkl")
    
    # 2. Save hyperparameters
    with open(f"{OUTPUT_DIR}/hyperparameters.json", 'w') as f:
        json.dump(HYPERPARAMETERS, f, indent=2)
    
    # 3. Save training metrics
    training_metrics = {
        'model_version': MODEL_VERSION,
        'trained_at': datetime.now().isoformat(),
        'features': FEATURES_V42,
        'feature_count': len(FEATURES_V42),
        'train_auc_roc': round(metrics['train_auc'], 4),
        'test_auc_roc': round(metrics['test_auc'], 4),
        'test_auc_pr': round(metrics['test_ap'], 4),
        'overfitting_gap': round(metrics['overfitting_gap'], 4),
        'baseline_comparison': {
            'v41_test_auc': 0.620,
            'v42_test_auc': round(metrics['test_auc'], 4),
            'improvement': round((metrics['test_auc'] - 0.620) * 100, 2)
        },
        'gates_passed': all(g['passed'] for g in gates.values()),
        'gate_results': {k: {kk: (str(vv) if isinstance(vv, bool) else (str(vv) if not isinstance(vv, (int, float, str)) else vv)) for kk, vv in v.items()} for k, v in gates.items()}
    }
    with open(f"{OUTPUT_DIR}/training_metrics.json", 'w') as f:
        json.dump(training_metrics, f, indent=2)
    
    # 4. Save feature importance
    importance_df.to_csv(f"{OUTPUT_DIR}/feature_importance.csv", index=False)
    importance_df.to_csv(f"{REPORTS_DIR}/shap_importance.csv", index=False)
    
    # 5. Save lift by decile
    lift_df.to_csv(f"{REPORTS_DIR}/lift_by_decile.csv", index=False)
    
    print(f"\nArtifacts saved to {OUTPUT_DIR}/")
    print(f"Reports saved to {REPORTS_DIR}/")


def main():
    """Main training pipeline."""
    print("="*60)
    print(f"V4.2.0 MODEL TRAINING - AGE BUCKET FEATURE")
    print(f"Started: {datetime.now().isoformat()}")
    print("="*60)
    
    # Step 1: Load data
    print("\n[1/5] Loading training data...")
    df = load_training_data()
    
    # Step 2: Train model
    print("\n[2/5] Training XGBoost model...")
    model, metrics = train_model(df)
    
    # Step 3: Calculate lift by decile
    print("\n[3/5] Calculating lift by decile...")
    lift_df, top_decile_lift = calculate_lift_by_decile(
        metrics['y_test'], 
        metrics['y_test_pred']
    )
    metrics['top_decile_lift'] = top_decile_lift
    print(f"Top Decile Lift: {top_decile_lift:.2f}x")
    print(lift_df.to_string(index=False))
    
    # Step 4: Validate gates
    print("\n[4/5] Validating improvement gates...")
    all_passed, gates = validate_gates(metrics)
    
    # Add Gate 2 (top decile lift) 
    gates['G2_LIFT'] = {
        'criterion': 'Top Decile Lift >= 2.03x',
        'actual': top_decile_lift,
        'passed': top_decile_lift >= 2.03
    }
    
    if not gates['G2_LIFT']['passed']:
        print(f"G2_LIFT FAILED: {top_decile_lift:.2f}x < 2.03x")
        all_passed = False
    
    # Step 5: Calculate SHAP & save (only if gates pass)
    if all_passed:
        print("\n[5/5] Calculating SHAP importance and saving artifacts...")
        importance_df, shap_values, explainer = calculate_shap_importance(
            model, metrics['X_train']
        )
        
        # Check age feature importance (Gate 4 - warning only)
        age_importance = importance_df[importance_df['feature'] == 'age_bucket_encoded']['importance'].values[0]
        age_rank = importance_df[importance_df['feature'] == 'age_bucket_encoded'].index[0] + 1
        print(f"\nAge feature importance: {age_importance:.4f} (rank #{age_rank}/{len(FEATURES_V42)})")
        
        if age_importance <= 0:
            print("WARNING: Age feature has zero or negative importance - may not be useful")
        
        save_model_artifacts(model, metrics, gates, importance_df, lift_df)
        
        print("\n" + "="*60)
        print("V4.2.0 TRAINING COMPLETE - READY FOR DEPLOYMENT")
        print("="*60)
        
        return True, metrics, gates
    else:
        print("\n" + "="*60)
        print("V4.2.0 TRAINING COMPLETE - DO NOT DEPLOY")
        print("Age feature does not improve model performance.")
        print("Recommendation: Keep V4.1.0 in production.")
        print("="*60)
        
        return False, metrics, gates


if __name__ == "__main__":
    success, metrics, gates = main()
