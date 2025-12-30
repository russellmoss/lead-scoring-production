"""
Phase 6: XGBoost Model Training

This script:
1. Loads train/test splits and final features
2. Trains XGBoost model with regularization
3. Evaluates performance metrics
4. Checks for overfitting
5. Saves model artifacts
"""

import sys
import json
import pickle
import numpy as np
import pandas as pd
from pathlib import Path
from datetime import datetime
from sklearn.metrics import roc_auc_score, average_precision_score, roc_curve, precision_recall_curve
import xgboost as xgb

# Add project root to path
sys.path.insert(0, str(Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")))

# Import utilities and constants
from utils.execution_logger import ExecutionLogger
from config.constants import (
    BASE_DIR,
    ModelConfig,
    PerformanceGates,
    OverfittingGates,
    BASELINE_CONVERSION_RATE
)

def calculate_top_n_lift(y_true, y_pred, n_percent=10):
    """Calculate lift in top N% of predictions."""
    # Get top N% threshold
    threshold = np.percentile(y_pred, 100 - n_percent)
    
    # Top N% predictions
    top_n_mask = y_pred >= threshold
    top_n_conversion = y_true[top_n_mask].mean()
    
    # Overall conversion
    overall_conversion = y_true.mean()
    
    if overall_conversion == 0:
        return None
    
    lift = top_n_conversion / overall_conversion
    return lift

def prepare_features(df, feature_list):
    """Prepare features for XGBoost (handle categoricals)."""
    X = df[feature_list].copy()
    
    # Identify categorical features
    categorical_features = []
    for feat in feature_list:
        if df[feat].dtype == 'object' or df[feat].dtype.name == 'category':
            categorical_features.append(feat)
    
    # Convert categoricals to codes (XGBoost can handle them)
    for feat in categorical_features:
        if feat in X.columns:
            X[feat] = X[feat].astype('category').cat.codes
    
    # Fill any remaining NaN with 0 (shouldn't happen after Phase 2, but safety)
    X = X.fillna(0)
    
    return X, categorical_features

def run_phase_6() -> bool:
    """Execute Phase 6: Model Training."""
    
    logger = ExecutionLogger(BASE_DIR)
    logger.start_phase("6", "XGBoost Model Training")
    
    # Track all gates
    all_blocking_gates_passed = True
    
    # =========================================================================
    # STEP 6.1: Load Split Data
    # =========================================================================
    logger.log_action("Loading train/test splits and final features")
    
    try:
        # Load splits
        train_df = pd.read_csv(BASE_DIR / "data" / "splits" / "train.csv")
        test_df = pd.read_csv(BASE_DIR / "data" / "splits" / "test.csv")
        
        logger.log_metric("Train Size", f"{len(train_df):,} rows")
        logger.log_metric("Test Size", f"{len(test_df):,} rows")
        
        # Load final features
        with open(BASE_DIR / "data" / "processed" / "final_features.json", 'r') as f:
            final_features_data = json.load(f)
            final_features = final_features_data['final_features']
        
        logger.log_metric("Final Features Count", f"{len(final_features)}")
        
        # Prepare features
        X_train, cat_features = prepare_features(train_df, final_features)
        X_test, _ = prepare_features(test_df, final_features)
        
        # Extract target
        y_train = train_df['target'].values
        y_test = test_df['target'].values
        
        logger.log_metric("Train Conversion Rate", f"{y_train.mean()*100:.2f}%")
        logger.log_metric("Test Conversion Rate", f"{y_test.mean()*100:.2f}%")
        
        if cat_features:
            logger.log_action(f"Categorical features: {', '.join(cat_features)}")
        
    except Exception as e:
        logger.log_error(f"Failed to load data: {str(e)}", exception=e)
        status = logger.end_phase()
        return False
    
    # =========================================================================
    # STEP 6.2: Calculate Class Weight
    # =========================================================================
    logger.log_action("Calculating class weight (scale_pos_weight)")
    
    try:
        negative_count = (y_train == 0).sum()
        positive_count = (y_train == 1).sum()
        
        scale_pos_weight = negative_count / positive_count if positive_count > 0 else 1.0
        
        logger.log_metric("Negative Class Count", f"{negative_count:,}")
        logger.log_metric("Positive Class Count", f"{positive_count:,}")
        logger.log_metric("scale_pos_weight", f"{scale_pos_weight:.2f}")
        
    except Exception as e:
        logger.log_error(f"Failed to calculate class weight: {str(e)}", exception=e)
        scale_pos_weight = 1.0
    
    # =========================================================================
    # STEP 6.3: Configure Model Parameters
    # =========================================================================
    logger.log_action("Configuring XGBoost model parameters")
    
    try:
        model_params = {
            'objective': ModelConfig.OBJECTIVE,
            'eval_metric': ModelConfig.EVAL_METRIC,
            'random_state': ModelConfig.RANDOM_STATE,
            'max_depth': ModelConfig.MAX_DEPTH,
            'min_child_weight': ModelConfig.MIN_CHILD_WEIGHT,
            'gamma': ModelConfig.GAMMA,
            'subsample': ModelConfig.SUBSAMPLE,
            'colsample_bytree': ModelConfig.COLSAMPLE_BYTREE,
            'reg_alpha': ModelConfig.REG_ALPHA,
            'reg_lambda': ModelConfig.REG_LAMBDA,
            'learning_rate': ModelConfig.LEARNING_RATE,
            'scale_pos_weight': scale_pos_weight,
            'tree_method': 'hist',  # Faster training
            'verbosity': 0  # Suppress XGBoost warnings
        }
        
        logger.log_action("Model Parameters:")
        for key, value in model_params.items():
            logger.log_metric(f"  {key}", str(value))
        
    except Exception as e:
        logger.log_error(f"Failed to configure model: {str(e)}", exception=e)
        status = logger.end_phase()
        return False
    
    # =========================================================================
    # STEP 6.4: Train with Early Stopping
    # =========================================================================
    logger.log_action("Training XGBoost model with early stopping")
    
    try:
        # Create DMatrix for XGBoost
        dtrain = xgb.DMatrix(X_train, label=y_train)
        dtest = xgb.DMatrix(X_test, label=y_test)
        
        # Training with early stopping
        evals = [(dtrain, 'train'), (dtest, 'test')]
        
        logger.log_action("Training model...")
        model = xgb.train(
            params=model_params,
            dtrain=dtrain,
            num_boost_round=ModelConfig.N_ESTIMATORS,
            evals=evals,
            early_stopping_rounds=ModelConfig.EARLY_STOPPING_ROUNDS,
            verbose_eval=10  # Print every 10 rounds
        )
        
        best_iteration = model.best_iteration
        best_score = model.best_score
        
        logger.log_metric("Best Iteration", f"{best_iteration}")
        logger.log_metric("Best Score", f"{best_score:.4f}")
        
        # Gate G6.1: Early stopping triggered before max rounds (WARNING)
        gate_6_1 = best_iteration < ModelConfig.N_ESTIMATORS
        logger.log_gate(
            "G6.1", "Early Stopping",
            passed=gate_6_1,
            expected=f"Stopped before {ModelConfig.N_ESTIMATORS} rounds",
            actual=f"Stopped at iteration {best_iteration}"
        )
        
        if not gate_6_1:
            logger.log_warning(
                "Early stopping did not trigger - model trained for full rounds",
                action_taken="Monitor for overfitting"
            )
        
    except Exception as e:
        logger.log_error(f"Failed to train model: {str(e)}", exception=e)
        status = logger.end_phase()
        return False
    
    # =========================================================================
    # STEP 6.5: Evaluate Performance
    # =========================================================================
    logger.log_action("Evaluating model performance")
    
    try:
        # Get predictions
        y_train_pred = model.predict(dtrain)
        y_test_pred = model.predict(dtest)
        
        # Calculate metrics for train
        train_auc_roc = roc_auc_score(y_train, y_train_pred)
        train_auc_pr = average_precision_score(y_train, y_train_pred)
        train_lift_10 = calculate_top_n_lift(y_train, y_train_pred, n_percent=10)
        train_lift_5 = calculate_top_n_lift(y_train, y_train_pred, n_percent=5)
        
        # Calculate metrics for test
        test_auc_roc = roc_auc_score(y_test, y_test_pred)
        test_auc_pr = average_precision_score(y_test, y_test_pred)
        test_lift_10 = calculate_top_n_lift(y_test, y_test_pred, n_percent=10)
        test_lift_5 = calculate_top_n_lift(y_test, y_test_pred, n_percent=5)
        
        logger.log_action("Train Performance:")
        logger.log_metric("  AUC-ROC", f"{train_auc_roc:.4f}")
        logger.log_metric("  AUC-PR", f"{train_auc_pr:.4f}")
        logger.log_metric("  Top 10% Lift", f"{train_lift_10:.2f}x" if train_lift_10 else "N/A")
        logger.log_metric("  Top 5% Lift", f"{train_lift_5:.2f}x" if train_lift_5 else "N/A")
        
        logger.log_action("Test Performance:")
        logger.log_metric("  AUC-ROC", f"{test_auc_roc:.4f}")
        logger.log_metric("  AUC-PR", f"{test_auc_pr:.4f}")
        logger.log_metric("  Top 10% Lift", f"{test_lift_10:.2f}x" if test_lift_10 else "N/A")
        logger.log_metric("  Top 5% Lift", f"{test_lift_5:.2f}x" if test_lift_5 else "N/A")
        
    except Exception as e:
        logger.log_error(f"Failed to evaluate performance: {str(e)}", exception=e)
        train_auc_roc = test_auc_roc = 0.0
        train_lift_10 = test_lift_10 = None
    
    # =========================================================================
    # STEP 6.6: Check for Overfitting
    # =========================================================================
    logger.log_action("Checking for overfitting")
    
    try:
        # Calculate gaps
        lift_gap = train_lift_10 - test_lift_10 if (train_lift_10 and test_lift_10) else None
        auc_gap = train_auc_roc - test_auc_roc
        
        logger.log_metric("Train-Test Lift Gap", f"{lift_gap:.2f}x" if lift_gap is not None else "N/A")
        logger.log_metric("Train-Test AUC Gap", f"{auc_gap:.4f}")
        
        # Gate G6.2: Lift gap <= 0.5x (BLOCKING)
        gate_6_2 = (lift_gap is None) or (lift_gap <= OverfittingGates.MAX_TRAIN_TEST_LIFT_GAP)
        logger.log_gate(
            "G6.2", "Lift Gap (Overfitting Check)",
            passed=gate_6_2,
            expected=f"Lift gap <= {OverfittingGates.MAX_TRAIN_TEST_LIFT_GAP}x",
            actual=f"{lift_gap:.2f}x" if lift_gap is not None else "N/A"
        )
        
        if not gate_6_2:
            logger.log_error(
                f"Lift gap ({lift_gap:.2f}x) exceeds threshold ({OverfittingGates.MAX_TRAIN_TEST_LIFT_GAP}x)",
                exception=None
            )
            all_blocking_gates_passed = False
        
        # Gate G6.3: AUC gap <= 0.05 (WARNING)
        gate_6_3 = auc_gap <= OverfittingGates.MAX_TRAIN_TEST_AUC_GAP
        logger.log_gate(
            "G6.3", "AUC Gap (Overfitting Check)",
            passed=gate_6_3,
            expected=f"AUC gap <= {OverfittingGates.MAX_TRAIN_TEST_AUC_GAP}",
            actual=f"{auc_gap:.4f}"
        )
        
        if not gate_6_3:
            logger.log_warning(
                f"AUC gap ({auc_gap:.4f}) exceeds threshold ({OverfittingGates.MAX_TRAIN_TEST_AUC_GAP})",
                action_taken="Monitor - may indicate slight overfitting"
            )
        
        # Performance gates
        gate_perf_auc = test_auc_roc >= PerformanceGates.MIN_AUC_ROC
        gate_perf_aucpr = test_auc_pr >= PerformanceGates.MIN_AUC_PR
        gate_perf_lift = (test_lift_10 is not None) and (test_lift_10 >= PerformanceGates.MIN_TOP_DECILE_LIFT)
        
        logger.log_gate(
            "G6.4", "Test AUC-ROC",
            passed=gate_perf_auc,
            expected=f">= {PerformanceGates.MIN_AUC_ROC}",
            actual=f"{test_auc_roc:.4f}"
        )
        
        logger.log_gate(
            "G6.5", "Test AUC-PR",
            passed=gate_perf_aucpr,
            expected=f">= {PerformanceGates.MIN_AUC_PR}",
            actual=f"{test_auc_pr:.4f}"
        )
        
        logger.log_gate(
            "G6.6", "Test Top 10% Lift",
            passed=gate_perf_lift,
            expected=f">= {PerformanceGates.MIN_TOP_DECILE_LIFT}x",
            actual=f"{test_lift_10:.2f}x" if test_lift_10 else "N/A"
        )
        
    except Exception as e:
        logger.log_error(f"Failed overfitting check: {str(e)}", exception=e)
        gate_6_2 = gate_6_3 = False
        all_blocking_gates_passed = False
    
    # =========================================================================
    # STEP 6.7: Save Model Artifacts
    # =========================================================================
    logger.log_action("Saving model artifacts")
    
    try:
        model_dir = BASE_DIR / "models" / "v4.0.0"
        model_dir.mkdir(parents=True, exist_ok=True)
        
        # Save model as pickle
        model_pkl_path = model_dir / "model.pkl"
        with open(model_pkl_path, 'wb') as f:
            pickle.dump(model, f)
        logger.log_file_created("model.pkl", str(model_pkl_path))
        
        # Save model as XGBoost native format
        model_json_path = model_dir / "model.json"
        model.save_model(str(model_json_path))
        logger.log_file_created("model.json", str(model_json_path))
        
        # Save feature importance
        feature_importance = model.get_score(importance_type='gain')
        importance_df = pd.DataFrame({
            'feature': list(feature_importance.keys()),
            'importance': list(feature_importance.values())
        }).sort_values('importance', ascending=False)
        
        importance_path = model_dir / "feature_importance.csv"
        importance_df.to_csv(importance_path, index=False)
        logger.log_file_created("feature_importance.csv", str(importance_path))
        
        logger.log_action("Top 10 Features by Importance:")
        for idx, row in importance_df.head(10).iterrows():
            logger.log_metric(f"  {row['feature']}", f"{row['importance']:.2f}")
        
        # Save training metrics
        training_metrics = {
            'train_auc_roc': float(train_auc_roc),
            'train_auc_pr': float(train_auc_pr),
            'train_lift_10': float(train_lift_10) if train_lift_10 else None,
            'train_lift_5': float(train_lift_5) if train_lift_5 else None,
            'test_auc_roc': float(test_auc_roc),
            'test_auc_pr': float(test_auc_pr),
            'test_lift_10': float(test_lift_10) if test_lift_10 else None,
            'test_lift_5': float(test_lift_5) if test_lift_5 else None,
            'lift_gap': float(lift_gap) if lift_gap is not None else None,
            'auc_gap': float(auc_gap),
            'best_iteration': int(best_iteration),
            'best_score': float(best_score),
            'scale_pos_weight': float(scale_pos_weight),
            'n_features': len(final_features),
            'train_size': len(train_df),
            'test_size': len(test_df),
            'train_conv_rate': float(y_train.mean()),
            'test_conv_rate': float(y_test.mean()),
            'generated': datetime.now().isoformat()
        }
        
        metrics_path = model_dir / "training_metrics.json"
        with open(metrics_path, 'w') as f:
            json.dump(training_metrics, f, indent=2)
        logger.log_file_created("training_metrics.json", str(metrics_path))
        
    except Exception as e:
        logger.log_error(f"Failed to save artifacts: {str(e)}", exception=e)
    
    # =========================================================================
    # PHASE SUMMARY
    # =========================================================================
    status = logger.end_phase(next_steps=["Phase 7: Overfitting Detection"])
    
    return all_blocking_gates_passed and status in ["PASSED", "PASSED WITH WARNINGS"]


if __name__ == "__main__":
    success = run_phase_6()
    sys.exit(0 if success else 1)

