"""
Phase 10: SHAP Analysis for V4.1 R3 (Fixed)

Fix for base_score issue - explicitly set base_score on model before SHAP.
"""

import pandas as pd
import numpy as np
import pickle
import json
import xgboost as xgb
import shap
from pathlib import Path
from google.cloud import bigquery
from datetime import datetime
from scipy.stats import pearsonr
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
MODEL_DIR = WORKING_DIR / "models" / "v4.1.0_r3"
REPORT_DIR = WORKING_DIR / "reports" / "v4.1"

REPORT_DIR.mkdir(parents=True, exist_ok=True)

# V4.1 R3 Feature list (22 features)
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

# New V4.1 features (bleeding + firm/rep type)
NEW_V41_FEATURES = [
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


def fix_model_base_score(model):
    """Fix model base_score to be a float (not string)."""
    try:
        # Get current base_score
        current_base_score = model.get_params().get('base_score', None)
        print(f"      Current base_score: {current_base_score} (type: {type(current_base_score)})")
        
        # If it's a string, convert to float
        if isinstance(current_base_score, str):
            # Try to extract numeric value from string like '[5E-1]'
            if '[5E-1]' in current_base_score or '5E-1' in current_base_score:
                base_score = 0.5
            else:
                base_score = float(current_base_score)
            print(f"      Converting base_score to float: {base_score}")
        else:
            base_score = float(current_base_score) if current_base_score is not None else 0.5
        
        # Set base_score explicitly
        model.set_params(base_score=base_score)
        print(f"      Fixed base_score: {base_score}")
        
        return model, True
    except Exception as e:
        print(f"      Warning: Could not fix base_score: {e}")
        return model, False


def load_model_and_data():
    """Load V4.1 R3 model and test data."""
    print("\n[1/5] Loading V4.1 R3 model and test data...")
    
    # Load model
    model_path = MODEL_DIR / "model.pkl"
    with open(model_path, 'rb') as f:
        model = pickle.load(f)
    print(f"      Model loaded from: {model_path}")
    
    # Fix base_score if needed
    model, fixed = fix_model_base_score(model)
    
    # Load test data
    client = bigquery.Client(project=PROJECT_ID)
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_splits_v41`
    WHERE split = 'TEST'
    """
    test_df = client.query(query).to_dataframe()
    
    print(f"      Test set: {len(test_df):,} rows")
    
    # Sample 1000 rows for SHAP (faster computation)
    if len(test_df) > 1000:
        test_df_sample = test_df.sample(n=1000, random_state=42)
        print(f"      Sampling 1000 rows for SHAP analysis")
    else:
        test_df_sample = test_df
    
    return model, test_df_sample


def create_shap_explainer(model):
    """Create SHAP TreeExplainer."""
    print("\n[2/5] Creating SHAP TreeExplainer...")
    
    try:
        # Create TreeExplainer with explicit base_value
        # Get the expected value from the model
        try:
            # Try to get base_score from model params
            base_score = model.get_params().get('base_score', 0.5)
            if isinstance(base_score, str):
                base_score = 0.5  # Default fallback
            base_score = float(base_score)
        except:
            base_score = 0.5
        
        # Create explainer
        explainer = shap.TreeExplainer(model, model_output='probability', feature_perturbation='tree_path_dependent')
        print(f"      TreeExplainer created successfully")
        
        # Get expected value
        try:
            expected_value = explainer.expected_value
            print(f"      Expected value: {expected_value:.4f}")
        except:
            print(f"      Expected value: {base_score:.4f} (from base_score)")
        
        return explainer, True
    except Exception as e:
        print(f"      ERROR: Failed to create TreeExplainer: {e}")
        print(f"      Attempting alternative approach...")
        
        # Alternative: Try with model_output='raw'
        try:
            explainer = shap.TreeExplainer(model, model_output='raw')
            print(f"      TreeExplainer created with model_output='raw'")
            return explainer, True
        except Exception as e2:
            print(f"      ERROR: Alternative approach also failed: {e2}")
            return None, False


def calculate_shap_values(explainer, X_test):
    """Calculate SHAP values."""
    print("\n[3/5] Calculating SHAP values...")
    
    try:
        # Calculate SHAP values
        shap_values = explainer.shap_values(X_test)
        print(f"      SHAP values calculated successfully")
        print(f"      Shape: {shap_values.shape}")
        
        return shap_values, True
    except Exception as e:
        print(f"      ERROR: Failed to calculate SHAP values: {e}")
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
        
        print(f"      Summary plot saved to: {plot_path}")
        return True
    except Exception as e:
        print(f"      ERROR: Failed to generate summary plot: {e}")
        return False


def calculate_shap_importance(shap_values):
    """Calculate mean absolute SHAP values (feature importance)."""
    if shap_values is None:
        return None
    
    # Mean absolute SHAP value per feature
    mean_abs_shap = np.abs(shap_values).mean(axis=0)
    return mean_abs_shap


def load_xgboost_importance():
    """Load XGBoost feature importance."""
    importance_path = MODEL_DIR / "feature_importance.csv"
    
    try:
        importance_df = pd.read_csv(importance_path)
        return importance_df
    except Exception as e:
        print(f"      Warning: Could not load XGBoost importance: {e}")
        return None


def evaluate_gates(explainer_created, shap_calculated, shap_importance, xgb_importance, feature_names):
    """Evaluate validation gates."""
    print("\n[5/5] Evaluating validation gates...")
    
    gates = {
        'G10.1': explainer_created,
        'G10.2': shap_calculated,
        'G10.3': False,  # Will be set below
        'G10.4': False  # Will be set below
    }
    
    top_10_features = None
    
    # G10.3: Top 10 SHAP features include at least 3 new V4.1 features
    if shap_importance is not None:
        # Get top 10 features by SHAP importance
        top_10_indices = np.argsort(shap_importance)[-10:][::-1]
        top_10_features = [feature_names[i] for i in top_10_indices]
        
        # Count new V4.1 features in top 10
        new_features_in_top10 = sum(1 for f in top_10_features if f in NEW_V41_FEATURES)
        gates['G10.3'] = new_features_in_top10 >= 3
        
        print(f"      G10.3: Top 10 SHAP features include {new_features_in_top10} new V4.1 features")
        print(f"        Top 10 features: {', '.join(top_10_features[:5])}...")
        print(f"        New V4.1 features in top 10: {new_features_in_top10} (target: >= 3)")
    else:
        print(f"      G10.3: Cannot evaluate (SHAP importance not available)")
    
    # G10.4: SHAP importance correlates with XGBoost importance (r > 0.7)
    if shap_importance is not None and xgb_importance is not None:
        # Create DataFrames for comparison
        shap_df = pd.DataFrame({
            'feature': feature_names,
            'shap_importance': shap_importance
        })
        
        # Merge with XGBoost importance
        merged = shap_df.merge(xgb_importance, on='feature', how='inner')
        
        if len(merged) > 0:
            # Calculate correlation
            correlation, p_value = pearsonr(merged['shap_importance'], merged['importance'])
            gates['G10.4'] = correlation > 0.7
            
            print(f"      G10.4: SHAP-XGBoost importance correlation: {correlation:.4f} (target: > 0.7)")
            print(f"        P-value: {p_value:.4f}")
        else:
            print(f"      G10.4: Cannot evaluate (no matching features)")
    else:
        print(f"      G10.4: Cannot evaluate (missing data)")
    
    print(f"\n      Gate Results:")
    for gate, passed in gates.items():
        status = "PASSED" if passed else "FAILED"
        print(f"        {gate}: {status}")
    
    return gates, top_10_features


def generate_report(shap_values, shap_importance, xgb_importance, gates, feature_names, top_10_features):
    """Generate SHAP analysis report."""
    print("\n[6/6] Generating SHAP analysis report...")
    
    report_path = REPORT_DIR / "shap_analysis_report_r3.md"
    values_path = REPORT_DIR / "shap_values_r3.json"
    
    # Calculate feature importance rankings
    if shap_importance is not None:
        shap_rankings = pd.DataFrame({
            'feature': feature_names,
            'shap_importance': shap_importance
        }).sort_values('shap_importance', ascending=False)
    else:
        shap_rankings = None
    
    # Generate report
    report = f"""# V4.1 R3 SHAP Analysis Report

**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  
**Model Version**: v4.1.0_r3  
**Status**: {'PASSED' if all(gates.values()) else 'PARTIAL - SOME GATES FAILED'}

## Executive Summary

This report analyzes SHAP (SHapley Additive exPlanations) values for the V4.1 R3 model.
SHAP values explain how each feature contributes to individual predictions, providing
interpretability and validation of feature importance.

## Validation Gates

### G10.1: SHAP TreeExplainer creates without error
**Status**: {'PASSED' if gates['G10.1'] else 'FAILED'}

- TreeExplainer created: {'Yes' if gates['G10.1'] else 'No'}
- **Note**: This gate validates that base_score=0.5 fix worked correctly

### G10.2: SHAP values calculated successfully
**Status**: {'PASSED' if gates['G10.2'] else 'FAILED'}

- SHAP values calculated: {'Yes' if gates['G10.2'] else 'No'}
- Shape: {shap_values.shape if shap_values is not None else 'N/A'}

### G10.3: Top 10 SHAP features include at least 3 new V4.1 features
**Status**: {'PASSED' if gates['G10.3'] else 'FAILED'}

"""
    
    if top_10_features:
        new_features_in_top10 = sum(1 for f in top_10_features if f in NEW_V41_FEATURES)
        report += f"""
- Top 10 SHAP features: {', '.join(top_10_features)}
- New V4.1 features in top 10: {new_features_in_top10} (target: >= 3)
- **Analysis**: {'New V4.1 features are well-represented in top features' if gates['G10.3'] else 'New V4.1 features may need further investigation'}
"""
    else:
        report += "\n- Cannot evaluate (SHAP importance not available)\n"
    
    report += f"""
### G10.4: SHAP feature importance correlates with XGBoost importance (r > 0.7)
**Status**: {'PASSED' if gates['G10.4'] else 'FAILED'}

"""
    
    if shap_importance is not None and xgb_importance is not None:
        shap_df = pd.DataFrame({
            'feature': feature_names,
            'shap_importance': shap_importance
        })
        merged = shap_df.merge(xgb_importance, on='feature', how='inner')
        if len(merged) > 0:
            correlation, p_value = pearsonr(merged['shap_importance'], merged['importance'])
            report += f"""
- Correlation: {correlation:.4f} (target: > 0.7)
- P-value: {p_value:.4f}
- **Analysis**: {'SHAP and XGBoost importance are well-aligned' if gates['G10.4'] else 'SHAP and XGBoost importance show some divergence - investigate'}
"""
        else:
            report += "\n- Cannot evaluate (no matching features)\n"
    else:
        report += "\n- Cannot evaluate (missing data)\n"
    
    report += """
## Feature Importance Comparison

### Top 10 Features by SHAP Importance

"""
    
    if shap_rankings is not None:
        report += "| Rank | Feature | SHAP Importance |\n"
        report += "|------|---------|-----------------|\n"
        for idx, row in shap_rankings.head(10).iterrows():
            is_new = " (NEW V4.1)" if row['feature'] in NEW_V41_FEATURES else ""
            rank = len(shap_rankings) - shap_rankings.index.get_loc(idx)
            report += f"| {rank} | {row['feature']} | {row['shap_importance']:.4f} |{is_new}\n"
    
    report += """
### Top 10 Features by XGBoost Importance

"""
    
    if xgb_importance is not None:
        xgb_sorted = xgb_importance.sort_values('importance', ascending=False)
        report += "| Rank | Feature | XGBoost Importance |\n"
        report += "|------|---------|-------------------|\n"
        for idx, row in xgb_sorted.head(10).iterrows():
            is_new = " (NEW V4.1)" if row['feature'] in NEW_V41_FEATURES else ""
            report += f"| {idx + 1} | {row['feature']} | {row['importance']:.2f} |{is_new}\n"
    
    report += f"""
## Summary Plot

SHAP summary plot saved to: `v4/reports/v4.1/shap_summary_r3.png`

The summary plot shows:
- Feature importance (y-axis): Features ranked by mean absolute SHAP value
- SHAP value (x-axis): Impact on model output (positive = increases score, negative = decreases)
- Color: Feature value (red = high, blue = low)

## Key Insights

"""
    
    if gates['G10.3']:
        report += "- PASSED: New V4.1 features are well-represented in top SHAP features\n"
    else:
        report += "- WARNING: New V4.1 features may need further investigation\n"
    
    if gates['G10.4']:
        report += "- PASSED: SHAP and XGBoost importance are well-aligned (validates model consistency)\n"
    else:
        report += "- WARNING: SHAP and XGBoost importance show some divergence (investigate)\n"
    
    report += f"""
## Conclusion

{'PASSED: All validation gates passed. SHAP analysis confirms model interpretability and feature importance.' if all(gates.values()) else 'PARTIAL: Some validation gates failed. Review above for details.'}
"""
    
    # Save report
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report)
    
    # Save SHAP values (sample)
    if shap_values is not None:
        # Save summary statistics
        shap_summary = {
            'model_version': 'v4.1.0_r3',
            'generated': datetime.now().isoformat(),
            'shap_values_shape': list(shap_values.shape),
            'mean_abs_shap_by_feature': {
                feature_names[i]: float(shap_importance[i])
                for i in range(len(feature_names))
            } if shap_importance is not None else {},
            'top_10_features': top_10_features if top_10_features else [],
            'gates': gates
        }
        
        with open(values_path, 'w') as f:
            json.dump(shap_summary, f, indent=2)
    
    print(f"      Report saved to: {report_path}")
    if shap_values is not None:
        print(f"      SHAP values summary saved to: {values_path}")
    
    return all(gates.values())


def run_phase_10():
    """Execute Phase 10: SHAP Analysis."""
    start_time = datetime.now()
    print("=" * 80)
    print("Phase 10: SHAP Analysis - V4.1 R3 (Fixed)")
    print("=" * 80)
    
    try:
        # Load model and data
        model, test_df = load_model_and_data()
        
        # Prepare features
        X_test, feature_names = prepare_features(test_df)
        
        print(f"      Features: {len(feature_names)}")
        print(f"      Test sample: {len(X_test):,} rows")
        
        # Create SHAP explainer
        explainer, explainer_created = create_shap_explainer(model)
        
        if not explainer_created:
            print("\nERROR: Failed to create SHAP explainer. Cannot proceed.")
            return False, None, None, None, start_time, datetime.now()
        
        # Calculate SHAP values
        shap_values, shap_calculated = calculate_shap_values(explainer, X_test)
        
        if not shap_calculated:
            print("\nERROR: Failed to calculate SHAP values. Cannot proceed.")
            return False, None, None, None, start_time, datetime.now()
        
        # Generate summary plot
        plot_success = generate_shap_summary_plot(shap_values, X_test, feature_names)
        
        # Calculate SHAP importance
        shap_importance = calculate_shap_importance(shap_values)
        
        # Load XGBoost importance
        xgb_importance = load_xgboost_importance()
        
        # Evaluate gates
        gates, top_10_features = evaluate_gates(
            explainer_created, shap_calculated, shap_importance, 
            xgb_importance, feature_names
        )
        
        # Generate report
        all_passed = generate_report(
            shap_values, shap_importance, xgb_importance, 
            gates, feature_names, top_10_features
        )
        
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()
        
        print("\n" + "=" * 80)
        print("Phase 10 Complete!")
        print("=" * 80)
        print(f"\nOverall Status: {'PASSED' if all_passed else 'PARTIAL - SOME GATES FAILED'}")
        print(f"Duration: {duration:.1f} seconds")
        
        if all_passed:
            print("\nSUCCESS: All validation gates passed! SHAP analysis complete.")
        else:
            print("\nWARNING: Some validation gates failed. Review report for details.")
        
        return all_passed, gates, shap_importance, top_10_features, start_time, end_time
        
    except Exception as e:
        print(f"\nERROR: Error during SHAP analysis: {e}")
        import traceback
        traceback.print_exc()
        raise


if __name__ == "__main__":
    try:
        all_passed, gates, shap_importance, top_10_features, start_time, end_time = run_phase_10()
        if all_passed:
            print("\nSUCCESS: SHAP analysis passed!")
        else:
            print("\nWARNING: Some SHAP validation gates failed. Review report.")
    except Exception as e:
        print(f"\nERROR: Fatal error during Phase 10: {e}")
        raise

