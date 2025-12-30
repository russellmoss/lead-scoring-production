"""
Phase 8: Overfitting Detection for V4.1
Check for overfitting indicators and validate model generalization.
"""

import pandas as pd
import numpy as np
import pickle
import xgboost as xgb
from sklearn.metrics import roc_auc_score, average_precision_score
from sklearn.model_selection import cross_val_score, StratifiedKFold
from pathlib import Path
from google.cloud import bigquery
import json
from datetime import datetime

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
MODEL_DIR = WORKING_DIR / "models" / "v4.1.0"
REPORT_DIR = WORKING_DIR / "reports" / "v4.1"

REPORT_DIR.mkdir(parents=True, exist_ok=True)

# Feature list (same as Phase 7)
FEATURES_V41 = [
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
    'tenure_bucket_encoded',
    'mobility_tier_encoded',
    'firm_stability_tier_encoded',
    'is_recent_mover',
    'days_since_last_move',
    'firm_departures_corrected',
    'bleeding_velocity_encoded',
    'recent_mover_x_bleeding',
    'is_independent_ria',
    'is_ia_rep_type',
    'is_dual_registered',
    'independent_ria_x_ia_rep'
]


def load_model_and_data():
    """Load V4.1 model and train/test data."""
    print("\n[1/5] Loading model and data...")
    
    # Load model
    model_path = MODEL_DIR / "model.pkl"
    with open(model_path, 'rb') as f:
        model = pickle.load(f)
    print(f"      Model loaded from: {model_path}")
    
    # Load data
    client = bigquery.Client(project=PROJECT_ID)
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
    WHERE split IN ('TRAIN', 'TEST')
    """
    df = client.query(query).to_dataframe()
    print(f"      Data loaded: {len(df):,} rows")
    
    return model, df


def prepare_features(df):
    """Prepare features for XGBoost (same logic as Phase 7)."""
    X = df.copy()
    
    # Encode categorical features
    for cat_col, encoded_col in [
        ('tenure_bucket', 'tenure_bucket_encoded'),
        ('mobility_tier', 'mobility_tier_encoded'),
        ('firm_stability_tier', 'firm_stability_tier_encoded')
    ]:
        if cat_col in X.columns:
            X[encoded_col] = pd.Categorical(X[cat_col]).codes
            X[encoded_col] = X[encoded_col].replace(-1, 0)
    
    # Select final features
    feature_cols = [f for f in FEATURES_V41 if f in X.columns]
    X_features = X[feature_cols].fillna(0).astype(float)
    
    return X_features, feature_cols


def calculate_lift_by_decile(y_true, y_pred):
    """Calculate lift by decile."""
    df = pd.DataFrame({'y_true': y_true, 'y_pred': y_pred})
    
    # Create deciles (10 equal-sized bins)
    df['decile'] = pd.qcut(df['y_pred'], 10, labels=False, duplicates='drop')
    
    baseline = df['y_true'].mean()
    decile_stats = df.groupby('decile').agg({
        'y_true': ['mean', 'sum', 'count']
    }).reset_index()
    decile_stats.columns = ['decile', 'conv_rate', 'conversions', 'count']
    decile_stats['lift'] = decile_stats['conv_rate'] / baseline if baseline > 0 else 0
    
    return decile_stats, baseline


def run_cross_validation(X, y, n_splits=5):
    """Run stratified k-fold cross-validation."""
    print("\n[4/5] Running cross-validation...")
    
    from xgboost import XGBClassifier
    
    # Calculate scale_pos_weight
    neg_count = (y == 0).sum()
    pos_count = (y == 1).sum()
    scale_pos_weight = neg_count / pos_count if pos_count > 0 else 1.0
    
    model = XGBClassifier(
        max_depth=4,
        min_child_weight=10,
        gamma=0.1,
        subsample=0.8,
        colsample_bytree=0.8,
        reg_alpha=0.1,
        reg_lambda=1.0,
        learning_rate=0.05,
        n_estimators=100,  # Reduced for CV speed
        base_score=0.5,
        scale_pos_weight=scale_pos_weight,
        use_label_encoder=False,
        eval_metric='logloss',
        random_state=42
    )
    
    cv = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=42)
    scores = cross_val_score(model, X, y, cv=cv, scoring='roc_auc', n_jobs=1)
    
    print(f"      CV scores: {scores}")
    print(f"      CV mean: {scores.mean():.4f}, std: {scores.std():.4f}")
    
    return scores


def generate_report(metrics, gates_results):
    """Generate overfitting report."""
    print("\n[5/5] Generating report...")
    
    report_path = REPORT_DIR / "overfitting_report.md"
    results_path = REPORT_DIR / "overfitting_results.json"
    
    all_passed = all(gates_results.values())
    
    report = f"""# V4.1 Overfitting Detection Report

**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  
**Status**: {'PASSED' if all_passed else 'FAILED - OVERFITTING DETECTED'}

## Executive Summary

This report analyzes overfitting indicators for the V4.1 XGBoost model.
Overfitting occurs when a model performs well on training data but poorly on test data,
indicating it has memorized training patterns rather than learning generalizable rules.

## Performance Metrics

| Metric | Train | Test | Gap | Threshold | Status |
|--------|-------|------|-----|-----------|--------|
| AUC-ROC | {metrics['train_auc']:.4f} | {metrics['test_auc']:.4f} | {metrics['auc_gap']:.4f} | < 0.05 | {'[PASS]' if gates_results['G8.1'] else '[FAIL]'} |
| Top Decile Lift | {metrics['train_top_lift']:.2f}x | {metrics['test_top_lift']:.2f}x | {metrics['lift_gap']:.2f}x | < 0.5x | {'[PASS]' if gates_results['G8.2'] else '[FAIL]'} |
| AUC-PR (Train) | {metrics.get('train_auc_pr', 0):.4f} | {metrics.get('test_auc_pr', 0):.4f} | - | - | - |

## Cross-Validation Results

- **Mean AUC**: {metrics['cv_mean']:.4f}
- **Std AUC**: {metrics['cv_std']:.4f}
- **Threshold**: std < 0.03
- **Status**: {'[PASS] Stable' if gates_results['G8.3'] else '[FAIL] Unstable'}

## Validation Gates

### G8.1: Train-Test AUC gap < 0.05
**Status**: {'[PASS] PASSED' if gates_results['G8.1'] else '[FAIL] FAILED'}

- Train AUC: {metrics['train_auc']:.4f}
- Test AUC: {metrics['test_auc']:.4f}
- Gap: {metrics['auc_gap']:.4f}
- Threshold: < 0.05

{'**⚠️ CRITICAL**: Large AUC gap indicates significant overfitting. Model is memorizing training patterns.' if not gates_results['G8.1'] else ''}

### G8.2: Train-Test top decile lift gap < 0.5x
**Status**: {'[PASS] PASSED' if gates_results['G8.2'] else '[FAIL] FAILED'}

- Train top decile lift: {metrics['train_top_lift']:.2f}x
- Test top decile lift: {metrics['test_top_lift']:.2f}x
- Gap: {metrics['lift_gap']:.2f}x
- Threshold: < 0.5x

### G8.3: Cross-validation AUC std < 0.03
**Status**: {'[PASS] PASSED' if gates_results['G8.3'] else '[FAIL] FAILED'}

- CV mean AUC: {metrics['cv_mean']:.4f}
- CV std AUC: {metrics['cv_std']:.4f}
- Threshold: std < 0.03

### G8.4: Test AUC > 0.58 (meaningful signal)
**Status**: {'[PASS] PASSED' if gates_results['G8.4'] else '[FAIL] FAILED'}

- Test AUC: {metrics['test_auc']:.4f}
- Threshold: > 0.58
- V4.0.0 baseline: 0.599

{'**⚠️ CRITICAL**: Test AUC is below threshold and below V4.0.0 baseline. Model may not be ready for deployment.' if not gates_results['G8.4'] else ''}

## Lift Analysis by Decile

### Train Set
{metrics.get('train_lift_table', 'N/A')}

### Test Set
{metrics.get('test_lift_table', 'N/A')}

## Recommendations

"""
    
    if not gates_results['G8.1']:
        report += """### Overfitting Detected (G8.1 Failed)

**Issue**: Large train-test AUC gap ({:.4f}) indicates significant overfitting.

**Recommended Actions**:
1. **Increase regularization**:
   - Increase `reg_alpha` from 0.1 to 0.3
   - Increase `reg_lambda` from 1.0 to 2.0
   
2. **Reduce learning rate**:
   - Decrease `learning_rate` from 0.05 to 0.03
   - Increase `n_estimators` to 800 to compensate
   
3. **Increase early stopping**:
   - Increase `early_stopping_rounds` from 50 to 100
   
4. **Reduce model complexity**:
   - Decrease `max_depth` from 4 to 3
   - Increase `min_child_weight` from 10 to 15

""".format(metrics['auc_gap'])
    
    if not gates_results['G8.4']:
        report += """### Low Test Performance (G8.4 Failed)

**Issue**: Test AUC ({:.4f}) is below threshold (0.58) and below V4.0.0 baseline (0.599).

**Recommended Actions**:
1. Review feature engineering - may need additional features
2. Check for data quality issues
3. Consider ensemble methods
4. Retrain with adjusted hyperparameters (see G8.1 recommendations)

""".format(metrics['test_auc'])
    
    if all_passed:
        report += "All validation gates passed. Model shows good generalization.\n"
    
    report += f"""
## Conclusion

{'✅ No overfitting detected. Model shows good generalization to test set.' if all_passed else '⚠️ Overfitting detected. Review recommendations above and consider retraining with adjusted hyperparameters.'}
"""
    
    # Save report
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report)
    
    # Save JSON results
    results = {
        'audit_date': datetime.now().isoformat(),
        'metrics': metrics,
        'gates': gates_results,
        'all_passed': all_passed
    }
    
    with open(results_path, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    
    print(f"      Report saved to: {report_path}")
    print(f"      Results saved to: {results_path}")
    
    return all_passed


def run_phase_8():
    """Execute Phase 8: Overfitting Detection."""
    print("=" * 80)
    print("Phase 8: Overfitting Detection - V4.1")
    print("=" * 80)
    
    try:
        # Load model and data
        model, df = load_model_and_data()
        
        # Split data
        train_df = df[df['split'] == 'TRAIN'].copy()
        test_df = df[df['split'] == 'TEST'].copy()
        
        print(f"\n      Train: {len(train_df):,} rows")
        print(f"      Test: {len(test_df):,} rows")
        
        # Prepare features
        print("\n[2/5] Preparing features...")
        X_train, feature_cols = prepare_features(train_df)
        X_test, _ = prepare_features(test_df)
        y_train = train_df['target'].values
        y_test = test_df['target'].values
        
        print(f"      Features: {len(feature_cols)}")
        
        # Calculate predictions
        print("\n[3/5] Calculating predictions and metrics...")
        dtrain = xgb.DMatrix(X_train, label=y_train)
        dtest = xgb.DMatrix(X_test, label=y_test)
        
        train_pred = model.predict(dtrain)
        test_pred = model.predict(dtest)
        
        # Calculate AUC
        train_auc = roc_auc_score(y_train, train_pred)
        test_auc = roc_auc_score(y_test, test_pred)
        auc_gap = train_auc - test_auc
        
        # Calculate AUC-PR
        train_auc_pr = average_precision_score(y_train, train_pred)
        test_auc_pr = average_precision_score(y_test, test_pred)
        
        print(f"      Train AUC: {train_auc:.4f}")
        print(f"      Test AUC: {test_auc:.4f}")
        print(f"      AUC Gap: {auc_gap:.4f}")
        
        # Calculate lift by decile
        train_lift_df, train_baseline = calculate_lift_by_decile(y_train, train_pred)
        test_lift_df, test_baseline = calculate_lift_by_decile(y_test, test_pred)
        
        train_top_lift = train_lift_df['lift'].iloc[-1] if len(train_lift_df) > 0 else 0.0
        test_top_lift = test_lift_df['lift'].iloc[-1] if len(test_lift_df) > 0 else 0.0
        lift_gap = abs(train_top_lift - test_top_lift)
        
        print(f"      Train top decile lift: {train_top_lift:.2f}x")
        print(f"      Test top decile lift: {test_top_lift:.2f}x")
        print(f"      Lift gap: {lift_gap:.2f}x")
        
        # Create lift tables for report
        train_lift_table = train_lift_df.to_string(index=False) if len(train_lift_df) > 0 else "N/A"
        test_lift_table = test_lift_df.to_string(index=False) if len(test_lift_df) > 0 else "N/A"
        
        # Cross-validation
        cv_scores = run_cross_validation(X_train, y_train, n_splits=5)
        cv_mean = cv_scores.mean()
        cv_std = cv_scores.std()
        
        # Compile metrics
        metrics = {
            'train_auc': train_auc,
            'test_auc': test_auc,
            'auc_gap': auc_gap,
            'train_auc_pr': train_auc_pr,
            'test_auc_pr': test_auc_pr,
            'train_top_lift': train_top_lift,
            'test_top_lift': test_top_lift,
            'lift_gap': lift_gap,
            'train_baseline': train_baseline,
            'test_baseline': test_baseline,
            'cv_mean': cv_mean,
            'cv_std': cv_std,
            'cv_scores': cv_scores.tolist(),
            'train_lift_table': train_lift_table,
            'test_lift_table': test_lift_table
        }
        
        # Evaluate gates
        gates_results = {
            'G8.1': metrics['auc_gap'] < 0.05,
            'G8.2': metrics['lift_gap'] < 0.5,
            'G8.3': metrics['cv_std'] < 0.03,
            'G8.4': metrics['test_auc'] > 0.58
        }
        
        print("\n      Gate Results:")
        for gate, passed in gates_results.items():
            status = "PASSED" if passed else "FAILED"
            print(f"        {gate}: {status}")
        
        # Generate report
        all_passed = generate_report(metrics, gates_results)
        
        print("\n" + "=" * 80)
        print("Phase 8 Complete!")
        print("=" * 80)
        print(f"\nOverall Status: {'PASSED' if all_passed else 'FAILED - OVERFITTING DETECTED'}")
        
        if not all_passed:
            print("\nWARNING: Overfitting detected. Review recommendations in the report.")
            print("Consider retraining with adjusted hyperparameters.")
        
        return all_passed, metrics, gates_results
        
    except Exception as e:
        print(f"\nERROR: Error during overfitting detection: {e}")
        raise


if __name__ == "__main__":
    try:
        all_passed, metrics, gates = run_phase_8()
        if all_passed:
            print("\nSUCCESS: No overfitting detected!")
        else:
            print("\nWARNING: Overfitting detected. Review report for recommendations.")
    except Exception as e:
        print(f"\nERROR: Fatal error during Phase 8: {e}")
        raise

