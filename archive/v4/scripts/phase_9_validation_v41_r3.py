"""
Phase 9: Model Validation for V4.1 R3
Validate model performance and compare to V4.0.0 baseline.
"""

import pandas as pd
import numpy as np
import pickle
import json
import xgboost as xgb
from sklearn.metrics import roc_auc_score, average_precision_score, precision_recall_curve
from pathlib import Path
from google.cloud import bigquery
from datetime import datetime

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
MODEL_DIR = WORKING_DIR / "models" / "v4.1.0_r3"
REPORT_DIR = WORKING_DIR / "reports" / "v4.1"
V4_BASELINE_PATH = WORKING_DIR / "models" / "v4.0.0" / "training_metrics.json"

REPORT_DIR.mkdir(parents=True, exist_ok=True)

# V4.1 R3 Feature list (22 features - reduced from 26)
FEATURES_V41_R3 = [
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
    'tenure_bucket_encoded',
    'mobility_tier_encoded',
    'firm_stability_tier_encoded',
    'is_recent_mover',
    'days_since_last_move',
    'firm_departures_corrected',
    'bleeding_velocity_encoded',
    'is_independent_ria',
    'is_ia_rep_type',
    'is_dual_registered',
]


def prepare_features(df):
    """Prepare features for XGBoost (same logic as Phase 7 R3)."""
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
    
    # Select final features (only 22 features)
    feature_cols = [f for f in FEATURES_V41_R3 if f in X.columns]
    X_features = X[feature_cols].fillna(0).astype(float)
    
    return X_features, feature_cols


def calculate_lift_by_decile(y_true, y_pred):
    """Calculate detailed lift by decile."""
    df = pd.DataFrame({'y_true': y_true, 'y_pred': y_pred})
    df['decile'] = pd.qcut(df['y_pred'], 10, labels=False, duplicates='drop')
    
    baseline = df['y_true'].mean()
    
    decile_stats = df.groupby('decile').agg({
        'y_true': ['mean', 'sum', 'count'],
        'y_pred': 'mean'
    }).reset_index()
    
    decile_stats.columns = ['decile', 'conv_rate', 'conversions', 'count', 'avg_score']
    decile_stats['lift'] = decile_stats['conv_rate'] / baseline if baseline > 0 else 0
    decile_stats['baseline'] = baseline
    decile_stats = decile_stats.sort_values('decile')
    
    return decile_stats, baseline


def calculate_precision_recall_at_thresholds(y_true, y_pred, thresholds):
    """Calculate precision and recall at various thresholds."""
    results = []
    for threshold in thresholds:
        y_pred_binary = (y_pred >= threshold).astype(int)
        tp = ((y_true == 1) & (y_pred_binary == 1)).sum()
        fp = ((y_true == 0) & (y_pred_binary == 1)).sum()
        fn = ((y_true == 1) & (y_pred_binary == 0)).sum()
        
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0
        
        results.append({
            'threshold': threshold,
            'precision': precision,
            'recall': recall,
            'true_positives': int(tp),
            'false_positives': int(fp),
            'false_negatives': int(fn)
        })
    
    return pd.DataFrame(results)


def load_model_and_data():
    """Load V4.1 R3 model and test data."""
    print("\n[1/5] Loading V4.1 R3 model and test data...")
    
    # Load model
    model_path = MODEL_DIR / "model.pkl"
    with open(model_path, 'rb') as f:
        model = pickle.load(f)
    print(f"      Model loaded from: {model_path}")
    
    # Load test data
    client = bigquery.Client(project=PROJECT_ID)
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
    WHERE split = 'TEST'
    """
    test_df = client.query(query).to_dataframe()
    
    print(f"      Test set: {len(test_df):,} rows, {test_df['target'].mean()*100:.2f}% positive")
    
    return model, test_df


def load_v4_baseline_metrics():
    """Load V4.0.0 baseline metrics."""
    print("\n[2/5] Loading V4.0.0 baseline metrics...")
    
    try:
        with open(V4_BASELINE_PATH, 'r') as f:
            v4_metrics = json.load(f)
        
        baseline = {
            'test_auc_roc': v4_metrics.get('test_auc_roc', 0.599),
            'test_auc_pr': v4_metrics.get('test_auc_pr', 0.043),
            'test_lift_10': v4_metrics.get('test_lift_10', 1.51),
            'test_conv_rate': v4_metrics.get('test_conv_rate', 0.032)
        }
        
        print(f"      V4.0.0 baseline loaded:")
        print(f"        Test AUC-ROC: {baseline['test_auc_roc']:.4f}")
        print(f"        Test AUC-PR: {baseline['test_auc_pr']:.4f}")
        print(f"        Top decile lift: {baseline['test_lift_10']:.2f}x")
        
        return baseline
    except Exception as e:
        print(f"      Warning: Could not load V4.0.0 metrics: {e}")
        print(f"      Using default baseline: AUC=0.599")
        return {
            'test_auc_roc': 0.599,
            'test_auc_pr': 0.043,
            'test_lift_10': 1.51,
            'test_conv_rate': 0.032
        }


def calculate_metrics(model, test_df):
    """Calculate all performance metrics."""
    print("\n[3/5] Calculating performance metrics...")
    
    # Prepare features
    X_test, feature_cols = prepare_features(test_df)
    y_test = test_df['target'].values
    
    print(f"      Features: {len(feature_cols)}")
    
    # Get predictions
    dtest = xgb.DMatrix(X_test, label=y_test)
    y_pred = model.predict(dtest)
    
    # Calculate AUC metrics
    auc_roc = roc_auc_score(y_test, y_pred)
    auc_pr = average_precision_score(y_test, y_pred)
    
    print(f"      AUC-ROC: {auc_roc:.4f}")
    print(f"      AUC-PR: {auc_pr:.4f}")
    
    # Calculate lift by decile
    lift_df, baseline = calculate_lift_by_decile(y_test, y_pred)
    top_decile_lift = lift_df['lift'].iloc[-1] if len(lift_df) > 0 else 0.0
    bottom_20_pct_lift = lift_df.head(2)['lift'].mean() if len(lift_df) >= 2 else 0.0
    bottom_20_pct_conv_rate = lift_df.head(2)['conv_rate'].mean() if len(lift_df) >= 2 else 0.0
    
    print(f"      Top decile lift: {top_decile_lift:.2f}x")
    print(f"      Bottom 20% conversion rate: {bottom_20_pct_conv_rate:.4f} ({bottom_20_pct_conv_rate*100:.2f}%)")
    
    # Calculate precision-recall at various thresholds
    thresholds = [0.01, 0.02, 0.03, 0.05, 0.10, 0.20, 0.30, 0.50]
    pr_at_thresholds = calculate_precision_recall_at_thresholds(y_test, y_pred, thresholds)
    
    metrics = {
        'auc_roc': auc_roc,
        'auc_pr': auc_pr,
        'top_decile_lift': top_decile_lift,
        'bottom_20_pct_lift': bottom_20_pct_lift,
        'bottom_20_pct_conv_rate': bottom_20_pct_conv_rate,
        'baseline_conv_rate': baseline,
        'test_size': len(test_df),
        'test_conversions': int(y_test.sum()),
        'test_conv_rate': baseline,
        'lift_by_decile': lift_df.to_dict('records'),
        'precision_recall_at_thresholds': pr_at_thresholds.to_dict('records')
    }
    
    return metrics, lift_df, pr_at_thresholds


def evaluate_gates(metrics, baseline):
    """Evaluate validation gates."""
    print("\n[4/5] Evaluating validation gates...")
    
    gates = {
        'G9.1': metrics['auc_roc'] >= 0.58,
        'G9.2': metrics['top_decile_lift'] >= 1.4,
        'G9.3': metrics['auc_roc'] >= baseline['test_auc_roc'],
        'G9.4': metrics['bottom_20_pct_conv_rate'] < 0.02
    }
    
    print(f"      G9.1 (Test AUC-ROC >= 0.58): {'PASSED' if gates['G9.1'] else 'FAILED'} ({metrics['auc_roc']:.4f})")
    print(f"      G9.2 (Top decile lift >= 1.4x): {'PASSED' if gates['G9.2'] else 'FAILED'} ({metrics['top_decile_lift']:.2f}x)")
    print(f"      G9.3 (V4.1 AUC >= V4.0.0 AUC): {'PASSED' if gates['G9.3'] else 'FAILED'} ({metrics['auc_roc']:.4f} >= {baseline['test_auc_roc']:.4f})")
    print(f"      G9.4 (Bottom 20% conv rate < 2%): {'PASSED' if gates['G9.4'] else 'FAILED'} ({metrics['bottom_20_pct_conv_rate']*100:.2f}%)")
    
    return gates


def generate_report(metrics, baseline, gates, lift_df, pr_at_thresholds):
    """Generate comprehensive validation report."""
    print("\n[5/5] Generating validation report...")
    
    report_path = REPORT_DIR / "model_validation_report_r3.md"
    results_path = REPORT_DIR / "validation_results_r3.json"
    lift_csv_path = REPORT_DIR / "lift_by_decile_r3.csv"
    
    all_passed = all(gates.values())
    
    # Comparison table
    comparison_table = f"""
| Metric | V4.0.0 Baseline | V4.1 R3 | Change | Status |
|--------|-----------------|---------|--------|--------|
| Test AUC-ROC | {baseline['test_auc_roc']:.4f} | {metrics['auc_roc']:.4f} | {metrics['auc_roc'] - baseline['test_auc_roc']:+.4f} | {'✅ Improved' if metrics['auc_roc'] >= baseline['test_auc_roc'] else '❌ Worse'} |
| Test AUC-PR | {baseline['test_auc_pr']:.4f} | {metrics['auc_pr']:.4f} | {metrics['auc_pr'] - baseline['test_auc_pr']:+.4f} | {'✅ Improved' if metrics['auc_pr'] >= baseline['test_auc_pr'] else '❌ Worse'} |
| Top Decile Lift | {baseline['test_lift_10']:.2f}x | {metrics['top_decile_lift']:.2f}x | {metrics['top_decile_lift'] - baseline['test_lift_10']:+.2f}x | {'✅ Improved' if metrics['top_decile_lift'] >= baseline['test_lift_10'] else '❌ Worse'} |
| Test Conv Rate | {baseline['test_conv_rate']*100:.2f}% | {metrics['test_conv_rate']*100:.2f}% | {(metrics['test_conv_rate'] - baseline['test_conv_rate'])*100:+.2f}% | - |
"""
    
    report = f"""# V4.1 R3 Model Validation Report

**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  
**Model Version**: v4.1.0_r3  
**Status**: {'✅ PASSED - READY FOR DEPLOYMENT' if all_passed else '⚠️ SOME GATES FAILED'}

## Executive Summary

This report validates the performance of the V4.1 R3 model and compares it to the V4.0.0 baseline.
R3 was trained with feature selection (22 features) and stronger regularization to address overfitting.

{comparison_table}

## Performance Metrics

### AUC Metrics

- **AUC-ROC**: {metrics['auc_roc']:.4f} (Target: ≥ 0.58, Baseline: {baseline['test_auc_roc']:.4f})
- **AUC-PR**: {metrics['auc_pr']:.4f} (Baseline: {baseline['test_auc_pr']:.4f})

### Lift Analysis

- **Top Decile Lift**: {metrics['top_decile_lift']:.2f}x (Target: ≥ 1.4x, Baseline: {baseline['test_lift_10']:.2f}x)
- **Bottom 20% Conversion Rate**: {metrics['bottom_20_pct_conv_rate']*100:.2f}% (Target: < 2%)
- **Baseline Conversion Rate**: {metrics['baseline_conv_rate']*100:.2f}%

### Test Set Summary

- **Total Rows**: {metrics['test_size']:,}
- **Conversions**: {metrics['test_conversions']:,}
- **Conversion Rate**: {metrics['test_conv_rate']*100:.2f}%

## Lift by Decile

| Decile | Avg Score | Conversions | Count | Conv Rate | Lift |
|--------|-----------|-------------|-------|------------|------|
"""
    
    for _, row in lift_df.iterrows():
        report += f"| {int(row['decile'])} | {row['avg_score']:.4f} | {int(row['conversions'])} | {int(row['count'])} | {row['conv_rate']*100:.2f}% | {row['lift']:.2f}x |\n"
    
    report += f"""
## Precision-Recall at Thresholds

| Threshold | Precision | Recall | TP | FP | FN |
|-----------|-----------|--------|----|----|----|
"""
    
    for _, row in pr_at_thresholds.iterrows():
        report += f"| {row['threshold']:.2f} | {row['precision']:.4f} | {row['recall']:.4f} | {row['true_positives']} | {row['false_positives']} | {row['false_negatives']} |\n"
    
    report += f"""
## Validation Gates

### G9.1: Test AUC-ROC >= 0.58
**Status**: {'✅ PASSED' if gates['G9.1'] else '❌ FAILED'}

- Test AUC-ROC: {metrics['auc_roc']:.4f}
- Threshold: ≥ 0.58

### G9.2: Top Decile Lift >= 1.4x
**Status**: {'✅ PASSED' if gates['G9.2'] else '❌ FAILED'}

- Top Decile Lift: {metrics['top_decile_lift']:.2f}x
- Threshold: ≥ 1.4x

### G9.3: V4.1 AUC >= V4.0.0 AUC (Improvement)
**Status**: {'✅ PASSED' if gates['G9.3'] else '❌ FAILED - CRITICAL'}

- V4.1 R3 AUC: {metrics['auc_roc']:.4f}
- V4.0.0 Baseline AUC: {baseline['test_auc_roc']:.4f}
- Improvement: {metrics['auc_roc'] - baseline['test_auc_roc']:+.4f}

{'**⚠️ CRITICAL**: V4.1 R3 performs worse than V4.0.0 baseline. DO NOT DEPLOY.' if not gates['G9.3'] else '**✅ SUCCESS**: V4.1 R3 exceeds V4.0.0 baseline.'}

### G9.4: Bottom 20% Conversion Rate < 2%
**Status**: {'✅ PASSED' if gates['G9.4'] else '❌ FAILED'}

- Bottom 20% Conversion Rate: {metrics['bottom_20_pct_conv_rate']*100:.2f}%
- Threshold: < 2%

## Recommendation

"""
    
    if all_passed:
        report += """✅ **PROCEED TO DEPLOYMENT** - All validation gates passed.

The V4.1 R3 model:
- Exceeds V4.0.0 baseline performance
- Shows strong predictive signal (AUC-ROC = {:.4f})
- Demonstrates effective lift (top decile = {:.2f}x)
- Effectively deprioritizes low-value leads (bottom 20% < 2%)

**Next Steps:**
1. Proceed to Phase 10: SHAP Analysis
2. Prepare deployment artifacts
3. Update model registry
""".format(metrics['auc_roc'], metrics['top_decile_lift'])
    else:
        report += """⚠️ **REVIEW REQUIRED** - Some validation gates failed.

**Failed Gates:**
"""
        for gate, passed in gates.items():
            if not passed:
                report += f"- {gate}\n"
        
        report += """
**Recommendation:**
- Review failed gates and determine if they are blocking for deployment
- Consider if relaxed thresholds are acceptable
- Document limitations before proceeding
"""
    
    # Save report
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report)
    
    # Save JSON results
    results = {
        'model_version': 'v4.1.0_r3',
        'generated': datetime.now().isoformat(),
        'metrics': metrics,
        'baseline': baseline,
        'gates': gates,
        'all_passed': all_passed
    }
    
    with open(results_path, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    
    # Save lift CSV
    lift_df.to_csv(lift_csv_path, index=False)
    
    print(f"      Report saved to: {report_path}")
    print(f"      Results saved to: {results_path}")
    print(f"      Lift CSV saved to: {lift_csv_path}")
    
    return all_passed


def run_phase_9():
    """Execute Phase 9: Model Validation."""
    start_time = datetime.now()
    print("=" * 80)
    print("Phase 9: Model Validation - V4.1 R3")
    print("=" * 80)
    
    try:
        # Load model and data
        model, test_df = load_model_and_data()
        
        # Load baseline
        baseline = load_v4_baseline_metrics()
        
        # Calculate metrics
        metrics, lift_df, pr_at_thresholds = calculate_metrics(model, test_df)
        
        # Evaluate gates
        gates = evaluate_gates(metrics, baseline)
        
        # Generate report
        all_passed = generate_report(metrics, baseline, gates, lift_df, pr_at_thresholds)
        
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()
        
        print("\n" + "=" * 80)
        print("Phase 9 Complete!")
        print("=" * 80)
        print(f"\nOverall Status: {'PASSED' if all_passed else 'SOME GATES FAILED'}")
        print(f"Duration: {duration:.1f} seconds")
        
        if all_passed:
            print("\nSUCCESS: All validation gates passed! Model is ready for deployment.")
        else:
            print("\nWARNING: Some validation gates failed. Review report for details.")
        
        return all_passed, metrics, baseline, gates, start_time, end_time
        
    except Exception as e:
        print(f"\nERROR: Error during model validation: {e}")
        raise


if __name__ == "__main__":
    try:
        all_passed, metrics, baseline, gates, start_time, end_time = run_phase_9()
        if all_passed:
            print("\nSUCCESS: Model validation passed!")
        else:
            print("\nWARNING: Some validation gates failed. Review report.")
    except Exception as e:
        print(f"\nERROR: Fatal error during Phase 9: {e}")
        raise

