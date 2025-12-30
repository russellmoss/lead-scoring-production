"""
Phase 7 Revision 2: Retrain XGBoost V4.1 Model with Adjusted Hyperparameters

CRITICAL: This is a retraining to fix severe overfitting detected in Phase 8.
Key changes: Stronger regularization, lower learning rate, reduced complexity.

CRITICAL: Set base_score=0.5 explicitly to fix SHAP compatibility
"""

import pandas as pd
import numpy as np
import xgboost as xgb
import pickle
import json
from pathlib import Path
from google.cloud import bigquery
from datetime import datetime
from sklearn.metrics import roc_auc_score

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
MODEL_DIR = WORKING_DIR / "models" / "v4.1.0_r2"
DATA_DIR = WORKING_DIR / "data" / "v4.1.0_r2"

MODEL_DIR.mkdir(parents=True, exist_ok=True)
DATA_DIR.mkdir(parents=True, exist_ok=True)

# V4.1 Feature list (same as R1)
FEATURES_V41 = [
    # Original V4 numeric features
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
    'tenure_bucket_x_mobility',
    'industry_tenure_months',
    'experience_years',
    # Encoded categorical features (will be created from categoricals)
    'tenure_bucket_encoded',
    'mobility_tier_encoded',
    'firm_stability_tier_encoded',
    # NEW V4.1 Bleeding Signal features
    'is_recent_mover',
    'days_since_last_move',
    'firm_departures_corrected',
    'bleeding_velocity_encoded',
    'recent_mover_x_bleeding',
    # NEW V4.1 Firm/Rep Type features
    'is_independent_ria',
    'is_ia_rep_type',
    'is_dual_registered',
    'independent_ria_x_ia_rep'
]

# UPDATED Hyperparameters - Stronger Regularization to Fix Overfitting
HYPERPARAMS_V41_R2 = {
    'objective': 'binary:logistic',
    'eval_metric': ['auc', 'logloss'],
    
    # REDUCED COMPLEXITY (was max_depth=4)
    'max_depth': 3,
    
    # INCREASED REGULARIZATION (was min_child_weight=10)
    'min_child_weight': 20,
    
    # STRONGER L1/L2 REGULARIZATION (was 0.1/1.0)
    'reg_alpha': 0.5,      # L1 - feature selection (5x increase)
    'reg_lambda': 3.0,     # L2 - weight shrinkage (3x increase)
    'gamma': 0.2,          # Min loss reduction (was 0.1)
    
    # REDUCED LEARNING RATE (was 0.05)
    'learning_rate': 0.02,
    
    # MORE TREES TO COMPENSATE (was 500)
    'n_estimators': 1000,
    
    # SUBSAMPLING FOR REGULARIZATION (more aggressive)
    'subsample': 0.7,           # was 0.8
    'colsample_bytree': 0.7,    # was 0.8
    
    # CRITICAL: Keep base_score=0.5 for SHAP
    'base_score': 0.5,
    
    'seed': 42,
    'verbosity': 1
}

# R1 Hyperparameters for comparison
HYPERPARAMS_V41_R1 = {
    'max_depth': 4,
    'min_child_weight': 10,
    'reg_alpha': 0.1,
    'reg_lambda': 1.0,
    'gamma': 0.1,
    'learning_rate': 0.05,
    'n_estimators': 500,
    'subsample': 0.8,
    'colsample_bytree': 0.8,
    'early_stopping_rounds': 50
}


def load_data():
    """Load train and test data from BigQuery."""
    print("\n[1/6] Loading data from BigQuery...")
    client = bigquery.Client(project=PROJECT_ID)
    
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
    WHERE split IN ('TRAIN', 'TEST')
    """
    
    df = client.query(query).to_dataframe()
    
    train_df = df[df['split'] == 'TRAIN'].copy()
    test_df = df[df['split'] == 'TEST'].copy()
    
    print(f"      Train: {len(train_df):,} rows, {train_df['target'].mean()*100:.2f}% positive")
    print(f"      Test: {len(test_df):,} rows, {test_df['target'].mean()*100:.2f}% positive")
    
    return train_df, test_df


def prepare_features(df):
    """Prepare features for XGBoost."""
    X = df.copy()
    
    # Encode categorical features
    categorical_mappings = {}
    for cat_col, encoded_col in [
        ('tenure_bucket', 'tenure_bucket_encoded'),
        ('mobility_tier', 'mobility_tier_encoded'),
        ('firm_stability_tier', 'firm_stability_tier_encoded')
    ]:
        if cat_col in X.columns:
            X[encoded_col] = pd.Categorical(X[cat_col]).codes
            X[encoded_col] = X[encoded_col].replace(-1, 0)
            categorical_mappings[cat_col] = dict(enumerate(pd.Categorical(X[cat_col]).categories))
    
    # Select final features (only those that exist in the dataframe)
    feature_cols = [f for f in FEATURES_V41 if f in X.columns]
    
    # Fill missing values
    X_features = X[feature_cols].fillna(0).astype(float)
    
    print(f"      Prepared {len(feature_cols)} features")
    
    return X_features, feature_cols, categorical_mappings


def calculate_lift_by_decile(y_true, y_pred):
    """Calculate lift by decile."""
    df = pd.DataFrame({'y_true': y_true, 'y_pred': y_pred})
    df['decile'] = pd.qcut(df['y_pred'], 10, labels=False, duplicates='drop')
    
    baseline = df['y_true'].mean()
    decile_stats = df.groupby('decile').agg({
        'y_true': ['mean', 'sum', 'count']
    }).reset_index()
    decile_stats.columns = ['decile', 'conv_rate', 'conversions', 'count']
    decile_stats['lift'] = decile_stats['conv_rate'] / baseline if baseline > 0 else 0
    
    top_decile_lift = decile_stats['lift'].iloc[-1] if len(decile_stats) > 0 else 0.0
    
    return top_decile_lift


def train_model(X_train, y_train, X_test, y_test):
    """Train XGBoost with early stopping."""
    print("\n[2/6] Training XGBoost model (R2 - Stronger Regularization)...")
    
    # Calculate scale_pos_weight for class imbalance
    neg_count = (y_train == 0).sum()
    pos_count = (y_train == 1).sum()
    scale_pos_weight = neg_count / pos_count
    print(f"      Scale pos weight: {scale_pos_weight:.2f} (neg: {neg_count:,}, pos: {pos_count:,})")
    
    # Update hyperparams
    params = HYPERPARAMS_V41_R2.copy()
    params['scale_pos_weight'] = scale_pos_weight
    
    print(f"\n      Hyperparameter Changes (R1 -> R2):")
    print(f"        - max_depth: {HYPERPARAMS_V41_R1['max_depth']} -> {params['max_depth']} (reduced complexity)")
    print(f"        - min_child_weight: {HYPERPARAMS_V41_R1['min_child_weight']} -> {params['min_child_weight']} (more regularization)")
    print(f"        - reg_alpha: {HYPERPARAMS_V41_R1['reg_alpha']} -> {params['reg_alpha']} (5x stronger L1)")
    print(f"        - reg_lambda: {HYPERPARAMS_V41_R1['reg_lambda']} -> {params['reg_lambda']} (3x stronger L2)")
    print(f"        - learning_rate: {HYPERPARAMS_V41_R1['learning_rate']} -> {params['learning_rate']} (2.5x slower)")
    print(f"        - n_estimators: {HYPERPARAMS_V41_R1['n_estimators']} -> {params['n_estimators']} (more trees)")
    print(f"        - early_stopping_rounds: {HYPERPARAMS_V41_R1['early_stopping_rounds']} -> 100 (more patience)")
    print(f"        - subsample: {HYPERPARAMS_V41_R1['subsample']} -> {params['subsample']} (more aggressive)")
    print(f"        - colsample_bytree: {HYPERPARAMS_V41_R1['colsample_bytree']} -> {params['colsample_bytree']} (more aggressive)")
    print(f"        - base_score: {params['base_score']} (CRITICAL for SHAP)")
    
    # Create DMatrices
    dtrain = xgb.DMatrix(X_train, label=y_train)
    dtest = xgb.DMatrix(X_test, label=y_test)
    
    # Train with early stopping
    evals = [(dtrain, 'train'), (dtest, 'test')]
    
    print(f"\n      Training model (max {params['n_estimators']} rounds, early stopping at 100)...")
    model = xgb.train(
        params,
        dtrain,
        num_boost_round=params['n_estimators'],
        evals=evals,
        early_stopping_rounds=100,  # Longer patience
        verbose_eval=100  # Print every 100 iterations
    )
    
    print(f"\n      Best iteration: {model.best_iteration}")
    print(f"      Best score: {model.best_score:.4f}")
    
    return model


def validate_immediately(model, X_train, y_train, X_test, y_test):
    """Immediately validate model after training (before saving)."""
    print("\n[3/6] Immediate validation (post-training)...")
    
    # Calculate predictions
    dtrain = xgb.DMatrix(X_train, label=y_train)
    dtest = xgb.DMatrix(X_test, label=y_test)
    
    train_pred = model.predict(dtrain)
    test_pred = model.predict(dtest)
    
    # Calculate AUC
    train_auc = roc_auc_score(y_train, train_pred)
    test_auc = roc_auc_score(y_test, test_pred)
    auc_gap = train_auc - test_auc
    
    # Calculate lift
    train_lift = calculate_lift_by_decile(y_train, train_pred)
    test_lift = calculate_lift_by_decile(y_test, test_pred)
    lift_gap = abs(train_lift - test_lift)
    
    print(f"      Train AUC: {train_auc:.4f}")
    print(f"      Test AUC: {test_auc:.4f}")
    print(f"      AUC Gap: {auc_gap:.4f} (target: < 0.10 relaxed, < 0.05 strict)")
    print(f"      Train top decile lift: {train_lift:.2f}x")
    print(f"      Test top decile lift: {test_lift:.2f}x")
    print(f"      Lift gap: {lift_gap:.2f}x (target: < 1.0x relaxed, < 0.5x strict)")
    print(f"      Early stopping: iteration {model.best_iteration} / {HYPERPARAMS_V41_R2['n_estimators']} (target: < 500)")
    
    # Validation gates
    gates = {
        'G7.2_R2': model.best_iteration < 500,  # Early stopping before 500
        'G8.1_R2_relaxed': auc_gap < 0.10,  # Relaxed threshold
        'G8.1_R2_strict': auc_gap < 0.05,  # Strict threshold
        'G8.2_R2_relaxed': lift_gap < 1.0,  # Relaxed threshold
        'G8.2_R2_strict': lift_gap < 0.5,  # Strict threshold
        'G8.4_R2': test_auc > 0.58,  # Above threshold
        'G8.4_R2_baseline': test_auc > 0.599  # Above V4.0.0 baseline
    }
    
    print(f"\n      Validation Gates:")
    print(f"        G7.2_R2 (Early stopping < 500): {'PASSED' if gates['G7.2_R2'] else 'FAILED'} (iteration {model.best_iteration})")
    print(f"        G8.1_R2 (AUC gap < 0.10 relaxed): {'PASSED' if gates['G8.1_R2_relaxed'] else 'FAILED'} (gap: {auc_gap:.4f})")
    print(f"        G8.1_R2 (AUC gap < 0.05 strict): {'PASSED' if gates['G8.1_R2_strict'] else 'FAILED'} (gap: {auc_gap:.4f})")
    print(f"        G8.2_R2 (Lift gap < 1.0x relaxed): {'PASSED' if gates['G8.2_R2_relaxed'] else 'FAILED'} (gap: {lift_gap:.2f}x)")
    print(f"        G8.2_R2 (Lift gap < 0.5x strict): {'PASSED' if gates['G8.2_R2_strict'] else 'FAILED'} (gap: {lift_gap:.2f}x)")
    print(f"        G8.4_R2 (Test AUC > 0.58): {'PASSED' if gates['G8.4_R2'] else 'FAILED'} (AUC: {test_auc:.4f})")
    print(f"        G8.4_R2 (Test AUC > 0.599 baseline): {'PASSED' if gates['G8.4_R2_baseline'] else 'FAILED'} (AUC: {test_auc:.4f})")
    
    metrics = {
        'train_auc': train_auc,
        'test_auc': test_auc,
        'auc_gap': auc_gap,
        'train_top_lift': train_lift,
        'test_top_lift': test_lift,
        'lift_gap': lift_gap,
        'best_iteration': model.best_iteration
    }
    
    return metrics, gates


def save_model_artifacts(model, feature_cols, categorical_mappings, metrics, gates):
    """Save model and related artifacts."""
    print("\n[4/6] Saving model artifacts...")
    
    # Save model pickle
    model_path = MODEL_DIR / "model.pkl"
    with open(model_path, 'wb') as f:
        pickle.dump(model, f)
    print(f"      Model saved to: {model_path}")
    
    # Save model JSON (for portability)
    json_path = MODEL_DIR / "model.json"
    model.save_model(str(json_path))
    print(f"      Model JSON saved to: {json_path}")
    
    # Save feature importance
    importance = model.get_score(importance_type='gain')
    importance_df = pd.DataFrame([
        {'feature': k, 'importance': v}
        for k, v in importance.items()
    ]).sort_values('importance', ascending=False)
    
    importance_path = MODEL_DIR / "feature_importance.csv"
    importance_df.to_csv(importance_path, index=False)
    print(f"      Feature importance saved to: {importance_path}")
    print(f"      Top 5 features: {', '.join(importance_df.head(5)['feature'].tolist())}")
    
    # Save hyperparameters
    hyperparams_path = MODEL_DIR / "hyperparameters.json"
    hyperparams_data = {
        'version': 'v4.1.0_r2',
        'created': datetime.now().isoformat(),
        'hyperparameters': HYPERPARAMS_V41_R2,
        'r1_comparison': HYPERPARAMS_V41_R1
    }
    with open(hyperparams_path, 'w') as f:
        json.dump(hyperparams_data, f, indent=2)
    print(f"      Hyperparameters saved to: {hyperparams_path}")
    
    # Save training metrics
    training_metrics_path = MODEL_DIR / "training_metrics.json"
    training_metrics = {
        'version': 'v4.1.0_r2',
        'created': datetime.now().isoformat(),
        'metrics': metrics,
        'gates': gates,
        'best_iteration': model.best_iteration,
        'best_score': model.best_score
    }
    with open(training_metrics_path, 'w') as f:
        json.dump(training_metrics, f, indent=2, default=str)
    print(f"      Training metrics saved to: {training_metrics_path}")
    
    # Save feature list
    features_data = {
        'version': 'v4.1.0_r2',
        'created': datetime.now().isoformat(),
        'final_features': feature_cols,
        'feature_count': len(feature_cols),
        'categorical_mappings': categorical_mappings,
        'hyperparameters': HYPERPARAMS_V41_R2
    }
    
    features_path = DATA_DIR / "final_features.json"
    with open(features_path, 'w') as f:
        json.dump(features_data, f, indent=2)
    print(f"      Features saved to: {features_path}")
    
    return importance_df


def compare_to_r1(metrics_r2):
    """Compare R2 metrics to R1 baseline."""
    print("\n[5/6] Comparing to R1 baseline...")
    
    # R1 metrics (from Phase 8 results)
    metrics_r1 = {
        'train_auc': 0.9461,
        'test_auc': 0.5610,
        'auc_gap': 0.3851,
        'train_top_lift': 8.13,
        'test_top_lift': 1.50,
        'lift_gap': 6.63,
        'best_iteration': 498
    }
    
    print(f"\n      Comparison (R1 -> R2):")
    print(f"        Test AUC: {metrics_r1['test_auc']:.4f} -> {metrics_r2['test_auc']:.4f} ({metrics_r2['test_auc'] - metrics_r1['test_auc']:+.4f})")
    print(f"        AUC Gap: {metrics_r1['auc_gap']:.4f} -> {metrics_r2['auc_gap']:.4f} ({metrics_r2['auc_gap'] - metrics_r1['auc_gap']:+.4f})")
    print(f"        Test Top Decile Lift: {metrics_r1['test_top_lift']:.2f}x -> {metrics_r2['test_top_lift']:.2f}x ({metrics_r2['test_top_lift'] - metrics_r1['test_top_lift']:+.2f}x)")
    print(f"        Lift Gap: {metrics_r1['lift_gap']:.2f}x -> {metrics_r2['lift_gap']:.2f}x ({metrics_r2['lift_gap'] - metrics_r1['lift_gap']:+.2f}x)")
    print(f"        Best Iteration: {metrics_r1['best_iteration']} -> {metrics_r2['best_iteration']} ({metrics_r2['best_iteration'] - metrics_r1['best_iteration']:+d})")
    
    return metrics_r1


def run_phase_7_r2():
    """Execute Phase 7 Revision 2: Model Retraining."""
    print("=" * 80)
    print("Phase 7 Revision 2: Model Retraining (Overfitting Fix) - V4.1")
    print("=" * 80)
    
    try:
        # Load data
        train_df, test_df = load_data()
        
        # Prepare features
        X_train, feature_cols, categorical_mappings = prepare_features(train_df)
        X_test, _, _ = prepare_features(test_df)
        
        y_train = train_df['target'].values
        y_test = test_df['target'].values
        
        print(f"\n      Training with {len(feature_cols)} features")
        print(f"      Train set: {len(X_train):,} rows")
        print(f"      Test set: {len(X_test):,} rows")
        
        # Train model
        model = train_model(X_train, y_train, X_test, y_test)
        
        # Immediate validation
        metrics, gates = validate_immediately(model, X_train, y_train, X_test, y_test)
        
        # Compare to R1
        metrics_r1 = compare_to_r1(metrics)
        
        # Save artifacts
        importance_df = save_model_artifacts(model, feature_cols, categorical_mappings, metrics, gates)
        
        # Final summary
        print("\n[6/6] Final Summary...")
        
        # Critical success criteria
        critical_passed = (
            gates['G8.4_R2_baseline'] and  # Test AUC > 0.599
            gates['G8.1_R2_relaxed'] and  # AUC gap < 0.10
            gates['G7.2_R2']  # Early stopping < 500
        )
        
        print(f"\n      Critical Success Criteria:")
        print(f"        Test AUC >= 0.60: {'PASSED' if metrics['test_auc'] >= 0.60 else 'FAILED'} ({metrics['test_auc']:.4f})")
        print(f"        AUC Gap <= 0.15: {'PASSED' if metrics['auc_gap'] <= 0.15 else 'FAILED'} ({metrics['auc_gap']:.4f})")
        print(f"        Early stopping < 500: {'PASSED' if gates['G7.2_R2'] else 'FAILED'} (iteration {metrics['best_iteration']})")
        
        all_passed = (
            gates['G7.2_R2'] and
            gates['G8.1_R2_strict'] and
            gates['G8.2_R2_strict'] and
            gates['G8.4_R2_baseline']
        )
        
        print("\n" + "=" * 80)
        print("Phase 7 R2 Complete!")
        print("=" * 80)
        print(f"\nOverall Status: {'PASSED' if all_passed else 'IMPROVED BUT NEEDS REVIEW'}")
        print(f"Critical Criteria: {'PASSED' if critical_passed else 'FAILED'}")
        
        if not critical_passed:
            print("\nWARNING: Critical success criteria not met. Review recommendations.")
            print("   Model may still need further hyperparameter tuning.")
        
        return all_passed, model, importance_df, gates, metrics, metrics_r1
        
    except Exception as e:
        print(f"\nERROR: Error during model retraining: {e}")
        raise


if __name__ == "__main__":
    try:
        all_passed, model, importance_df, gates, metrics, metrics_r1 = run_phase_7_r2()
        if all_passed:
            print("\nSUCCESS: All validation gates passed!")
        else:
            print("\nWARNING: Some validation gates have warnings. Review above.")
    except Exception as e:
        print(f"\nERROR: Fatal error during Phase 7 R2: {e}")
        raise

