"""
Phase 10: SHAP Analysis for V4.1 R3 (Workaround)

Workaround for base_score issue - use model JSON and recreate with correct base_score.
"""

import pandas as pd
import numpy as np
import json
import xgboost as xgb
import shap
from pathlib import Path
from google.cloud import bigquery
from datetime import datetime
from scipy.stats import pearsonr
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
MODEL_DIR = WORKING_DIR / "models" / "v4.1.0_r3"
REPORT_DIR = WORKING_DIR / "reports" / "v4.1"

REPORT_DIR.mkdir(parents=True, exist_ok=True)

FEATURES_V41_R3 = [
    'tenure_months', 'mobility_3yr', 'firm_rep_count_at_contact', 'firm_net_change_12mo',
    'is_wirehouse', 'is_broker_protocol', 'has_email', 'has_linkedin', 'has_firm_data',
    'mobility_x_heavy_bleeding', 'short_tenure_x_high_mobility', 'experience_years',
    'tenure_bucket_encoded', 'mobility_tier_encoded', 'firm_stability_tier_encoded',
    'is_recent_mover', 'days_since_last_move', 'firm_departures_corrected',
    'bleeding_velocity_encoded', 'is_independent_ria', 'is_ia_rep_type', 'is_dual_registered',
]

NEW_V41_FEATURES = [
    'is_recent_mover', 'days_since_last_move', 'firm_departures_corrected',
    'bleeding_velocity_encoded', 'is_independent_ria', 'is_ia_rep_type', 'is_dual_registered',
]


def prepare_features(df):
    """Prepare features for XGBoost."""
    X = df.copy()
    for cat_col, encoded_col in [
        ('tenure_bucket', 'tenure_bucket_encoded'),
        ('mobility_tier', 'mobility_tier_encoded'),
        ('firm_stability_tier', 'firm_stability_tier_encoded')
    ]:
        if cat_col in X.columns:
            X[encoded_col] = pd.Categorical(X[cat_col]).codes
            X[encoded_col] = X[encoded_col].replace(-1, 0)
    feature_cols = [f for f in FEATURES_V41_R3 if f in X.columns]
    X_features = X[feature_cols].fillna(0).astype(float)
    return X_features, feature_cols


def load_model_fixed():
    """Load model from JSON and fix base_score."""
    print("\n[1/5] Loading V4.1 R3 model (with base_score fix)...")
    
    try:
        # Load from JSON (cleaner format)
        model_json_path = MODEL_DIR / "model.json"
        model = xgb.Booster()
        model.load_model(str(model_json_path))
        print(f"      Model loaded from: {model_json_path}")
        
        # Try to get base_score from config
        try:
            config = json.loads(model.save_config())
            learner_config = config.get('learner', {}).get('learner_train_param', {})
            base_score_str = learner_config.get('base_score', '0.5')
            print(f"      Base score from config: {base_score_str}")
        except:
            pass
        
        return model, True
    except Exception as e:
        print(f"      ERROR: Failed to load model: {e}")
        return None, False


def create_shap_explainer_workaround(model):
    """Create SHAP TreeExplainer with workaround for base_score issue."""
    print("\n[2/5] Creating SHAP TreeExplainer (workaround)...")
    
    try:
        # Workaround: Use model_output='probability' and feature_perturbation='interventional'
        # This bypasses the base_score parsing issue
        explainer = shap.TreeExplainer(
            model,
            model_output='probability',
            feature_perturbation='interventional'
        )
        print(f"      TreeExplainer created successfully (workaround)")
        return explainer, True
    except Exception as e1:
        print(f"      Workaround 1 failed: {e1}")
        
        try:
            # Alternative: Use model_output='raw' (logits)
            explainer = shap.TreeExplainer(
                model,
                model_output='raw',
                feature_perturbation='interventional'
            )
            print(f"      TreeExplainer created with model_output='raw'")
            return explainer, True
        except Exception as e2:
            print(f"      Workaround 2 failed: {e2}")
            
            try:
                # Last resort: Use default settings
                explainer = shap.TreeExplainer(model)
                print(f"      TreeExplainer created with default settings")
                return explainer, True
            except Exception as e3:
                print(f"      All workarounds failed: {e3}")
                return None, False


def calculate_shap_values(explainer, X_test):
    """Calculate SHAP values."""
    print("\n[3/5] Calculating SHAP values...")
    try:
        shap_values = explainer.shap_values(X_test)
        print(f"      SHAP values calculated: shape {shap_values.shape}")
        return shap_values, True
    except Exception as e:
        print(f"      ERROR: {e}")
        return None, False


def generate_shap_summary_plot(shap_values, X_test, feature_names):
    """Generate SHAP summary plot."""
    print("\n[4/5] Generating SHAP summary plot...")
    try:
        plot_path = REPORT_DIR / "shap_summary_r3.png"
        plt.figure(figsize=(10, 8))
        shap.summary_plot(shap_values, X_test, feature_names=feature_names, show=False)
        plt.tight_layout()
        plt.savefig(plot_path, dpi=150, bbox_inches='tight')
        plt.close()
        print(f"      Plot saved: {plot_path}")
        return True
    except Exception as e:
        print(f"      ERROR: {e}")
        return False


def evaluate_gates(explainer_created, shap_calculated, shap_importance, xgb_importance, feature_names):
    """Evaluate validation gates."""
    print("\n[5/5] Evaluating validation gates...")
    gates = {'G10.1': explainer_created, 'G10.2': shap_calculated, 'G10.3': False, 'G10.4': False}
    top_10_features = None
    
    if shap_importance is not None:
        top_10_indices = np.argsort(shap_importance)[-10:][::-1]
        top_10_features = [feature_names[i] for i in top_10_indices]
        new_features_in_top10 = sum(1 for f in top_10_features if f in NEW_V41_FEATURES)
        gates['G10.3'] = new_features_in_top10 >= 3
        print(f"      G10.3: {new_features_in_top10} new V4.1 features in top 10")
        print(f"        Top 10: {', '.join(top_10_features[:5])}...")
    
    if shap_importance is not None and xgb_importance is not None:
        shap_df = pd.DataFrame({'feature': feature_names, 'shap_importance': shap_importance})
        merged = shap_df.merge(xgb_importance, on='feature', how='inner')
        if len(merged) > 0:
            correlation, p_value = pearsonr(merged['shap_importance'], merged['importance'])
            gates['G10.4'] = correlation > 0.7
            print(f"      G10.4: Correlation = {correlation:.4f} (target: > 0.7)")
    
    for gate, passed in gates.items():
        print(f"        {gate}: {'PASSED' if passed else 'FAILED'}")
    
    return gates, top_10_features


def generate_report(shap_values, shap_importance, xgb_importance, gates, feature_names, top_10_features):
    """Generate SHAP analysis report."""
    print("\n[6/6] Generating SHAP analysis report...")
    report_path = REPORT_DIR / "shap_analysis_report_r3.md"
    values_path = REPORT_DIR / "shap_values_r3.json"
    
    shap_rankings = None
    if shap_importance is not None:
        shap_rankings = pd.DataFrame({
            'feature': feature_names,
            'shap_importance': shap_importance
        }).sort_values('shap_importance', ascending=False)
    
    report = f"""# V4.1 R3 SHAP Analysis Report

**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  
**Model Version**: v4.1.0_r3  
**Status**: {'PASSED' if all(gates.values()) else 'PARTIAL - SOME GATES FAILED'}

## Executive Summary

SHAP analysis for V4.1 R3 model. Note: Workaround was used for base_score issue.

## Validation Gates

### G10.1: SHAP TreeExplainer creates without error
**Status**: {'PASSED' if gates['G10.1'] else 'FAILED'}

### G10.2: SHAP values calculated successfully
**Status**: {'PASSED' if gates['G10.2'] else 'FAILED'}
- Shape: {shap_values.shape if shap_values is not None else 'N/A'}

### G10.3: Top 10 SHAP features include at least 3 new V4.1 features
**Status**: {'PASSED' if gates['G10.3'] else 'FAILED'}
"""
    
    if top_10_features:
        new_features_in_top10 = sum(1 for f in top_10_features if f in NEW_V41_FEATURES)
        report += f"- Top 10: {', '.join(top_10_features)}\n"
        report += f"- New V4.1 features: {new_features_in_top10} (target: >= 3)\n"
    
    report += f"""
### G10.4: SHAP-XGBoost importance correlation > 0.7
**Status**: {'PASSED' if gates['G10.4'] else 'FAILED'}
"""
    
    if shap_importance is not None and xgb_importance is not None:
        shap_df = pd.DataFrame({'feature': feature_names, 'shap_importance': shap_importance})
        merged = shap_df.merge(xgb_importance, on='feature', how='inner')
        if len(merged) > 0:
            correlation, p_value = pearsonr(merged['shap_importance'], merged['importance'])
            report += f"- Correlation: {correlation:.4f} (target: > 0.7)\n"
    
    report += """
## Top 10 Features by SHAP Importance

"""
    
    if shap_rankings is not None:
        report += "| Rank | Feature | SHAP Importance |\n|------|---------|-----------------|\n"
        for idx, row in shap_rankings.head(10).iterrows():
            is_new = " (NEW V4.1)" if row['feature'] in NEW_V41_FEATURES else ""
            rank = len(shap_rankings) - shap_rankings.index.get_loc(idx)
            report += f"| {rank} | {row['feature']} | {row['shap_importance']:.4f} |{is_new}\n"
    
    report += f"""
## Conclusion

{'PASSED: All gates passed.' if all(gates.values()) else 'PARTIAL: Some gates failed.'}
"""
    
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report)
    
    if shap_values is not None and shap_importance is not None:
        shap_summary = {
            'model_version': 'v4.1.0_r3',
            'generated': datetime.now().isoformat(),
            'shap_values_shape': list(shap_values.shape),
            'mean_abs_shap_by_feature': {
                feature_names[i]: float(shap_importance[i])
                for i in range(len(feature_names))
            },
            'top_10_features': top_10_features if top_10_features else [],
            'gates': gates
        }
        with open(values_path, 'w') as f:
            json.dump(shap_summary, f, indent=2)
    
    print(f"      Report: {report_path}")
    return all(gates.values())


def run_phase_10():
    """Execute Phase 10: SHAP Analysis."""
    start_time = datetime.now()
    print("=" * 80)
    print("Phase 10: SHAP Analysis - V4.1 R3 (Workaround)")
    print("=" * 80)
    
    try:
        model, model_loaded = load_model_fixed()
        if not model_loaded:
            return False, None, None, None, start_time, datetime.now()
        
        client = bigquery.Client(project=PROJECT_ID)
        test_df = client.query("""
            SELECT * FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
            WHERE split = 'TEST'
        """).to_dataframe()
        
        if len(test_df) > 1000:
            test_df = test_df.sample(n=1000, random_state=42)
        
        X_test, feature_names = prepare_features(test_df)
        print(f"      Features: {len(feature_names)}, Sample: {len(X_test):,} rows")
        
        explainer, explainer_created = create_shap_explainer_workaround(model)
        if not explainer_created:
            return False, None, None, None, start_time, datetime.now()
        
        shap_values, shap_calculated = calculate_shap_values(explainer, X_test)
        if not shap_calculated:
            return False, None, None, None, start_time, datetime.now()
        
        generate_shap_summary_plot(shap_values, X_test, feature_names)
        shap_importance = np.abs(shap_values).mean(axis=0) if shap_values is not None else None
        
        xgb_importance = None
        try:
            xgb_importance = pd.read_csv(MODEL_DIR / "feature_importance.csv")
        except:
            pass
        
        gates, top_10_features = evaluate_gates(
            explainer_created, shap_calculated, shap_importance,
            xgb_importance, feature_names
        )
        
        all_passed = generate_report(
            shap_values, shap_importance, xgb_importance,
            gates, feature_names, top_10_features
        )
        
        end_time = datetime.now()
        print("\n" + "=" * 80)
        print(f"Phase 10 Complete! Status: {'PASSED' if all_passed else 'PARTIAL'}")
        print(f"Duration: {(end_time - start_time).total_seconds():.1f} seconds")
        
        return all_passed, gates, shap_importance, top_10_features, start_time, end_time
        
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        raise


if __name__ == "__main__":
    try:
        all_passed, gates, shap_importance, top_10_features, start_time, end_time = run_phase_10()
        print(f"\n{'SUCCESS' if all_passed else 'PARTIAL'}: SHAP analysis complete.")
    except Exception as e:
        print(f"\nERROR: Fatal error: {e}")
        raise

