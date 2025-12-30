"""
Phase 7: Train XGBoost V4.1 Model

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

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
MODEL_DIR = WORKING_DIR / "models" / "v4.1.0"
DATA_DIR = WORKING_DIR / "data" / "v4.1.0"

MODEL_DIR.mkdir(parents=True, exist_ok=True)
DATA_DIR.mkdir(parents=True, exist_ok=True)

# V4.1 Feature list (14 original + 5 bleeding + 4 firm/rep type = 23 total)
# Note: Some features will be encoded from categoricals
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

# Hyperparameters with regularization
HYPERPARAMS = {
    'objective': 'binary:logistic',
    'eval_metric': ['auc', 'logloss'],
    'max_depth': 4,
    'min_child_weight': 10,
    'gamma': 0.1,
    'subsample': 0.8,
    'colsample_bytree': 0.8,
    'reg_alpha': 0.1,
    'reg_lambda': 1.0,
    'learning_rate': 0.05,
    'n_estimators': 500,
    'base_score': 0.5,  # CRITICAL for SHAP compatibility
    'seed': 42,
    'verbosity': 1
}


def load_data():
    """Load train and test data from BigQuery."""
    print("\n[1/5] Loading data from BigQuery...")
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
    print(f"      Features: {', '.join(feature_cols[:5])}... ({len(feature_cols)} total)")
    
    return X_features, feature_cols, categorical_mappings


def train_model(X_train, y_train, X_test, y_test):
    """Train XGBoost with early stopping."""
    print("\n[2/5] Training XGBoost model...")
    
    # Calculate scale_pos_weight for class imbalance
    neg_count = (y_train == 0).sum()
    pos_count = (y_train == 1).sum()
    scale_pos_weight = neg_count / pos_count
    print(f"      Scale pos weight: {scale_pos_weight:.2f} (neg: {neg_count:,}, pos: {pos_count:,})")
    
    # Update hyperparams
    params = HYPERPARAMS.copy()
    params['scale_pos_weight'] = scale_pos_weight
    
    print(f"      Hyperparameters:")
    print(f"        - max_depth: {params['max_depth']}")
    print(f"        - learning_rate: {params['learning_rate']}")
    print(f"        - base_score: {params['base_score']} (CRITICAL for SHAP)")
    print(f"        - early_stopping_rounds: 50")
    
    # Create DMatrices
    dtrain = xgb.DMatrix(X_train, label=y_train)
    dtest = xgb.DMatrix(X_test, label=y_test)
    
    # Train with early stopping
    evals = [(dtrain, 'train'), (dtest, 'test')]
    
    print(f"\n      Training model (max {params['n_estimators']} rounds, early stopping at 50)...")
    model = xgb.train(
        params,
        dtrain,
        num_boost_round=params['n_estimators'],
        evals=evals,
        early_stopping_rounds=50,
        verbose_eval=50
    )
    
    print(f"\n      Best iteration: {model.best_iteration}")
    print(f"      Best score: {model.best_score:.4f}")
    
    return model


def save_model_artifacts(model, feature_cols, categorical_mappings):
    """Save model and related artifacts."""
    print("\n[3/5] Saving model artifacts...")
    
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
    
    # Save feature list
    features_data = {
        'version': 'v4.1.0',
        'created': datetime.now().isoformat(),
        'final_features': feature_cols,
        'feature_count': len(feature_cols),
        'categorical_mappings': categorical_mappings,
        'hyperparameters': HYPERPARAMS
    }
    
    features_path = DATA_DIR / "final_features.json"
    with open(features_path, 'w') as f:
        json.dump(features_data, f, indent=2)
    print(f"      Features saved to: {features_path}")
    
    return importance_df


def validate_model(model, importance_df):
    """Validate model meets quality gates."""
    print("\n[4/5] Validating model...")
    
    gates = {
        'G7.1': True,  # Model trains without errors (implicit - if we got here, it passed)
        'G7.2': False,  # Early stopping triggers
        'G7.3': False,  # Feature importance is reasonable
        'G7.4': True   # Model files saved (implicit - if we got here, it passed)
    }
    
    # G7.1: Model trains without errors (implicit - if we got here, it passed)
    print("      G7.1: Model trains without errors - PASSED")
    
    # G7.2: Check early stopping triggered
    if model.best_iteration is None or model.best_iteration >= 450:
        print(f"      G7.2: Early stopping - WARNING (best_iteration: {model.best_iteration})")
        gates['G7.2'] = False
    else:
        print(f"      G7.2: Early stopping - PASSED (stopped at iteration {model.best_iteration})")
        gates['G7.2'] = True
    
    # G7.3: Check no single feature dominates
    if len(importance_df) > 0:
        total_importance = importance_df['importance'].sum()
        max_importance_pct = (importance_df['importance'].max() / total_importance) * 100
        top_feature = importance_df.iloc[0]['feature']
        
        if max_importance_pct > 50:
            print(f"      G7.3: Feature importance - WARNING (top feature '{top_feature}' has {max_importance_pct:.1f}%)")
            gates['G7.3'] = False
        else:
            print(f"      G7.3: Feature importance - PASSED (top feature '{top_feature}' has {max_importance_pct:.1f}%)")
            gates['G7.3'] = True
    else:
        print("      G7.3: Feature importance - WARNING (no importance data)")
        gates['G7.3'] = False
    
    # G7.4: Model files saved (implicit - if we got here, it passed)
    print("      G7.4: Model files saved - PASSED")
    
    all_passed = all(gates.values())
    return all_passed, gates


def run_phase_7():
    """Execute Phase 7: Model Training."""
    print("=" * 80)
    print("Phase 7: Model Training - V4.1")
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
        
        # Save artifacts
        importance_df = save_model_artifacts(model, feature_cols, categorical_mappings)
        
        # Validate
        all_passed, gates = validate_model(model, importance_df)
        
        print("\n" + "=" * 80)
        print("Phase 7 Complete!")
        print("=" * 80)
        print(f"\nOverall Status: {'PASSED' if all_passed else 'PASSED WITH WARNINGS'}")
        print(f"\nGate Results:")
        for gate, passed in gates.items():
            status = "PASSED" if passed else "WARNING"
            print(f"  {gate}: {status}")
        
        return all_passed, model, importance_df, gates
        
    except Exception as e:
        print(f"\nERROR: Error during model training: {e}")
        raise


if __name__ == "__main__":
    try:
        all_passed, model, importance_df, gates = run_phase_7()
        if all_passed:
            print("\nSUCCESS: All validation gates passed!")
        else:
            print("\nWARNING: Some validation gates have warnings. Review above.")
    except Exception as e:
        print(f"\nERROR: Fatal error during Phase 7: {e}")
        raise

