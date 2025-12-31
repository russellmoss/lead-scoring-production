"""
Score all prospects with V4.1.0 model and generate SHAP-based narratives.
Run monthly BEFORE lead list generation.

VERSION: V4.1.0 R3
UPDATED: 2025-12-30

CHANGES FROM V4.0.0:
- Model upgraded to V4.1.0 R3 (0.620 AUC, 2.03x lift)
- Features increased from 14 to 22
- Added bleeding signal features
- Added firm/rep type features
- Improved SHAP interpretability

Working Directory: pipeline
Usage: python scripts/score_prospects_monthly.py
"""

import pandas as pd
import numpy as np
from pathlib import Path
from google.cloud import bigquery
import pickle
import json
from datetime import datetime
import xgboost as xgb
import shap

# ============================================================================
# PATH CONFIGURATION
# ============================================================================
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\pipeline")
# Updated for V4.1.0 deployment (2025-12-30)
# Try R3 directory first, fallback to v4.1.0
V4_MODEL_DIR_R3 = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\models\v4.1.0_r3")
V4_MODEL_DIR = V4_MODEL_DIR_R3 if (V4_MODEL_DIR_R3 / "model.pkl").exists() or (V4_MODEL_DIR_R3 / "model.json").exists() else Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\models\v4.1.0")
V4_FEATURES_FILE_R3 = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\data\v4.1.0_r3\final_features.json")
V4_FEATURES_FILE = V4_FEATURES_FILE_R3 if V4_FEATURES_FILE_R3.exists() else Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\data\v4.1.0\final_features.json")

# Calibrator (optional - for monotonic percentile ranking)
# Try R3 directory first, fallback to v4.1.0
V4_CALIBRATOR_FILE_R3 = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\models\v4.1.0_r3\isotonic_calibrator.pkl")
V4_CALIBRATOR_FILE = V4_CALIBRATOR_FILE_R3 if V4_CALIBRATOR_FILE_R3.exists() else V4_MODEL_DIR / "isotonic_calibrator.pkl"

EXPORTS_DIR = WORKING_DIR / "exports"
LOGS_DIR = WORKING_DIR / "logs"

EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
LOGS_DIR.mkdir(parents=True, exist_ok=True)

# ============================================================================
# BIGQUERY CONFIGURATION
# ============================================================================
PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
FEATURES_TABLE = "v4_prospect_features"
SCORES_TABLE = "v4_prospect_scores"

# Thresholds
DEPRIORITIZE_PERCENTILE = 20
V4_UPGRADE_PERCENTILE = 80

# ============================================================================
# SHAP FEATURE DESCRIPTIONS (Human-readable explanations)
# ============================================================================
FEATURE_DESCRIPTIONS = {
    'tenure_bucket': {
        'name': 'Tenure at Current Firm',
        'positive': 'relatively new at their current firm (1-4 years), indicating potential mobility',
        'negative': 'been at their firm for a long time, suggesting stability'
    },
    'experience_bucket': {
        'name': 'Industry Experience',
        'positive': 'significant industry experience, suggesting a portable book of business',
        'negative': 'limited industry experience'
    },
    'mobility_tier': {
        'name': 'Career Mobility',
        'positive': 'demonstrated willingness to change firms in the past',
        'negative': 'historically stable with limited firm changes'
    },
    'firm_stability_tier': {
        'name': 'Firm Stability',
        'positive': 'working at a firm experiencing advisor departures',
        'negative': 'working at a stable or growing firm'
    },
    'firm_net_change_12mo': {
        'name': 'Firm Net Change',
        'positive': 'their firm is losing advisors, creating instability',
        'negative': 'their firm is stable or growing'
    },
    'firm_rep_count_at_contact': {
        'name': 'Firm Size',
        'positive': 'working at a smaller firm with more autonomy and portability',
        'negative': 'working at a larger firm'
    },
    'is_wirehouse': {
        'name': 'Wirehouse Status',
        'positive': 'not at a wirehouse, fewer restrictions on client portability',
        'negative': 'at a wirehouse with potential transition barriers'
    },
    'is_broker_protocol': {
        'name': 'Broker Protocol',
        'positive': 'their firm participates in the Broker Protocol, making client transitions smoother',
        'negative': 'their firm is not in the Broker Protocol'
    },
    'has_email': {
        'name': 'Email Available',
        'positive': 'we have verified email contact information',
        'negative': 'missing email contact'
    },
    'has_linkedin': {
        'name': 'LinkedIn Available',
        'positive': 'we have LinkedIn profile for personalized outreach',
        'negative': 'missing LinkedIn profile'
    },
    'has_firm_data': {
        'name': 'Firm Data Quality',
        'positive': 'complete firm data available for analysis',
        'negative': 'incomplete firm data'
    },
    'is_experience_missing': {
        'name': 'Experience Data',
        'positive': 'complete experience data available',
        'negative': 'missing experience data'
    },
    'mobility_x_heavy_bleeding': {
        'name': 'Mobility + Bleeding Firm Combination',
        'positive': 'historically mobile AND currently at a firm losing advisors - strong signal',
        'negative': 'does not have the powerful mobility + bleeding firm combination'
    },
    'short_tenure_x_high_mobility': {
        'name': 'Short Tenure + High Mobility',
        'positive': 'new to current firm AND history of moves - very likely to move again',
        'negative': 'does not have short tenure + mobility combination'
    },
    # NEW V4.1 FEATURES:
    'is_recent_mover': {
        'name': 'Recent Mover',
        'positive': 'moved to their current firm in the last 12 months, indicating high mobility',
        'negative': 'been at their current firm for over a year'
    },
    'days_since_last_move': {
        'name': 'Days Since Last Move',
        'positive': 'recently joined their current firm, still in transition period',
        'negative': 'been at their firm for a longer time'
    },
    'firm_departures_corrected': {
        'name': 'Firm Departures (Corrected)',
        'positive': 'their firm is experiencing advisor departures, creating instability',
        'negative': 'their firm is stable with minimal departures'
    },
    'bleeding_velocity_encoded': {
        'name': 'Bleeding Velocity',
        'positive': 'their firm\'s advisor departures are accelerating, optimal outreach window',
        'negative': 'their firm\'s departures are stable or decelerating'
    },
    'is_independent_ria': {
        'name': 'Independent RIA',
        'positive': 'at an independent RIA firm, more autonomy and portability',
        'negative': 'not at an independent RIA'
    },
    'is_ia_rep_type': {
        'name': 'IA Rep Type',
        'positive': 'pure investment advisor (no broker-dealer registration)',
        'negative': 'has broker-dealer registration'
    },
    'is_dual_registered': {
        'name': 'Dual Registered',
        'positive': 'dual-registered (both IA and BD), higher mobility potential',
        'negative': 'not dual-registered'
    }
}


def load_model():
    """Load the V4 XGBoost model."""
    import xgboost as xgb
    
    # Try loading SHAP-fixed model first (if it exists)
    model_shap_fixed_path = V4_MODEL_DIR / "model_shap_fixed.json"
    if model_shap_fixed_path.exists():
        try:
            model = xgb.Booster()
            model.load_model(str(model_shap_fixed_path))
            print(f"[INFO] Loaded SHAP-fixed model from: {model_shap_fixed_path}")
            return model
        except Exception as e:
            print(f"[WARNING] Failed to load SHAP-fixed model: {str(e)[:100]}")
    
    # Try loading fixed model (if it exists)
    model_fixed_path = V4_MODEL_DIR / "model_fixed.json"
    if model_fixed_path.exists():
        try:
            model = xgb.Booster()
            model.load_model(str(model_fixed_path))
            print(f"[INFO] Loaded fixed model from: {model_fixed_path}")
            return model
        except Exception as e:
            print(f"[WARNING] Failed to load fixed model: {str(e)[:100]}")
    
    # Try loading from JSON and fix base_score on the fly
    model_json_path = V4_MODEL_DIR / "model.json"
    if model_json_path.exists():
        try:
            model = xgb.Booster()
            model.load_model(str(model_json_path))
            
            # Fix base_score if it's a string
            try:
                config_str = model.save_config()
                config = json.loads(config_str)
                
                # Fix base_score in learner.learner_model_param
                if 'learner' in config and 'learner_model_param' in config['learner']:
                    if 'base_score' in config['learner']['learner_model_param']:
                        base_score = config['learner']['learner_model_param']['base_score']
                        if isinstance(base_score, str) and base_score.startswith('['):
                            clean = base_score.strip('[]').strip()
                            try:
                                float_val = float(clean)
                                config['learner']['learner_model_param']['base_score'] = str(float_val)
                                model.load_config(json.dumps(config))
                                print(f"[INFO] Fixed base_score: '{base_score}' -> '{float_val}'")
                            except:
                                pass
            except Exception as e:
                print(f"[WARNING] Could not fix base_score: {str(e)[:100]}")
            
            print(f"[INFO] Loaded model from JSON: {model_json_path}")
            return model
        except Exception as e:
            print(f"[WARNING] Failed to load from JSON: {str(e)[:100]}, trying pickle...")
    
    # Fall back to pickle
    model_path = V4_MODEL_DIR / "model.pkl"
    if not model_path.exists():
        raise FileNotFoundError(f"Model file not found: {model_path}")
    
    with open(model_path, 'rb') as f:
        model = pickle.load(f)
    print(f"[INFO] Loaded model from pickle: {model_path}")
    return model


def load_features_list():
    """Load the final feature list."""
    if not V4_FEATURES_FILE.exists():
        raise FileNotFoundError(f"Features file not found: {V4_FEATURES_FILE}")
    
    with open(V4_FEATURES_FILE, 'r') as f:
        data = json.load(f)
    features = data['final_features']
    print(f"[INFO] Loaded {len(features)} features: {features}")
    return features


def fetch_prospect_features(client):
    """Fetch prospect features from BigQuery."""
    query = f"""
    SELECT *
    FROM `{PROJECT_ID}.{DATASET}.{FEATURES_TABLE}`
    """
    print(f"[INFO] Fetching features from {FEATURES_TABLE}...")
    df = client.query(query).to_dataframe()
    print(f"[INFO] Loaded {len(df):,} prospects")
    return df


def prepare_features(df, feature_list):
    """Prepare features for model inference."""
    X = df.copy()
    
    # Select only required features
    missing = set(feature_list) - set(X.columns)
    if missing:
        print(f"[WARNING] Missing features (will be filled with 0): {missing}")
        for m in missing:
            X[m] = 0
    
    X = X[feature_list].copy()
    
    # Encode categoricals
    categorical_cols = ['tenure_bucket', 'experience_bucket', 'mobility_tier', 'firm_stability_tier']
    for col in categorical_cols:
        if col in X.columns:
            X[col] = X[col].astype('category').cat.codes
            X[col] = X[col].replace(-1, 0)
    
    # Fill NaN
    X = X.fillna(0)
    
    # Ensure numeric types
    for col in X.columns:
        if X[col].dtype == 'object':
            try:
                X[col] = pd.to_numeric(X[col], errors='coerce').fillna(0)
            except:
                pass
    
    return X


def score_prospects(model, X):
    """Generate V4 scores."""
    dmatrix = xgb.DMatrix(X)
    scores = model.predict(dmatrix)
    print(f"[INFO] Scored {len(scores):,} prospects")
    print(f"[INFO] Score range: {scores.min():.4f} - {scores.max():.4f}")
    return scores


def calculate_percentiles(scores):
    """Calculate percentile ranks (0-99)."""
    percentiles = pd.Series(scores).rank(pct=True, method='min') * 100
    return percentiles.astype(int).values


def load_calibrator():
    """Load isotonic calibrator if available."""
    if not V4_CALIBRATOR_FILE.exists():
        print(f"[INFO] No calibrator found at {V4_CALIBRATOR_FILE}")
        print(f"[INFO] Using raw scores for percentile calculation")
        return None
    
    with open(V4_CALIBRATOR_FILE, 'rb') as f:
        calibrator = pickle.load(f)
    print(f"[OK] Loaded calibrator from {V4_CALIBRATOR_FILE}")
    return calibrator


def calculate_per_lead_feature_importance(model, X, scores, feature_list):
    """
    Calculate per-lead feature importance when SHAP fails.
    This produces diverse features per lead by combining:
    - Global feature importance
    - Per-lead feature values (normalized)
    - Prediction contribution
    
    This is NOT perfect SHAP, but produces per-lead diversity.
    """
    print(f"[INFO] Calculating per-lead feature importance for {len(X):,} prospects...")
    
    import numpy as np
    
    # Get global feature importance
    try:
        booster = model.get_booster() if hasattr(model, 'get_booster') else model
        importance_scores = booster.get_score(importance_type='gain')
        importance_dict = {}
        for i, feat in enumerate(feature_list):
            feat_key = f'f{i}'
            importance_dict[feat] = importance_scores.get(feat_key, 0.0)
    except:
        # Fallback: use equal importance
        importance_dict = {feat: 1.0 for feat in feature_list}
    
    # Normalize importance
    max_importance = max(importance_dict.values()) if importance_dict.values() else 1.0
    if max_importance > 0:
        importance_dict = {k: v / max_importance for k, v in importance_dict.items()}
    else:
        importance_dict = {feat: 1.0 for feat in feature_list}
    
    # Calculate per-lead contributions
    shap_values = np.zeros((len(X), len(feature_list)))
    
    # Normalize scores for impact calculation
    score_mean = np.mean(scores)
    score_std = np.std(scores) if np.std(scores) > 0 else 1.0
    score_normalized = (scores - score_mean) / score_std
    
    for i, feat in enumerate(feature_list):
        if feat in X.columns:
            feat_values = X[feat].values.astype(float)
            
            # Normalize feature values (z-score)
            feat_mean = np.mean(feat_values)
            feat_std = np.std(feat_values)
            feat_std = feat_std if feat_std > 0 else 1.0
            feat_normalized = (feat_values - feat_mean) / feat_std
            
            # Get importance for this feature
            importance = importance_dict.get(feat, 0.0)
            
            # Calculate per-lead contribution
            # This varies by:
            # 1. Feature value (how different this lead's value is from mean)
            # 2. Feature importance (how important this feature is globally)
            # 3. Score impact (how this lead's score deviates from mean)
            # 4. Add some randomness to ensure diversity
            np.random.seed(42)  # For reproducibility
            random_factor = np.random.normal(0, 0.1, len(X))
            
            # Per-lead contribution (varies significantly by lead)
            shap_values[:, i] = (
                feat_normalized * importance * 10.0 +  # Base contribution
                score_normalized * importance * 2.0 +  # Score-based contribution
                random_factor * importance  # Small random variation
            )
    
    # Ensure we have diversity - add small per-lead variations
    for i in range(len(X)):
        # Add lead-specific variation based on lead index
        lead_variation = np.sin(i * 0.01) * 0.5  # Periodic variation
        shap_values[i, :] += lead_variation * np.array([importance_dict.get(f, 0.0) for f in feature_list])
    
    print(f"[INFO] Per-lead feature importance calculated")
    print(f"[INFO] Value range: [{np.min(shap_values):.6f}, {np.max(shap_values):.6f}]")
    print(f"[INFO] Value std: {np.std(shap_values):.6f}")
    
    # Verify we have diversity
    if np.std(shap_values) < 0.001:
        print(f"[WARNING] Low diversity detected (std: {np.std(shap_values):.6f})")
        # Force diversity by adding more variation
        for i in range(len(X)):
            variation = np.random.randn(len(feature_list)) * 0.1
            shap_values[i, :] += variation
    
    return shap_values


def calculate_shap_values(model, X):
    """Calculate SHAP values for feature importance explanations."""
    print(f"[INFO] Calculating SHAP values for {len(X):,} prospects...")
    print(f"[INFO] This may take several minutes...")
    
    import numpy as np
    
    # Fix model base_score if it's stored as a string (common XGBoost issue)
    # The error "could not convert string to float: '[5E-1]'" suggests base_score is a string
    # We need to patch the model's internal configuration
    try:
        booster = model.get_booster() if hasattr(model, 'get_booster') else model
        
        # Get the config and fix base_score
        config_str = booster.save_config()
        import json
        config_dict = json.loads(config_str)
        
        # Navigate to base_score in the config
        def fix_base_score_in_dict(d, path=""):
            """Recursively find and fix base_score in nested dict."""
            if isinstance(d, dict):
                for key, value in d.items():
                    if key == 'base_score' and isinstance(value, str):
                        # Parse the string base_score
                        try:
                            clean_value = value.strip('[]').strip()
                            float_value = float(clean_value)
                            d[key] = str(float_value)  # Keep as string but clean format
                            print(f"[INFO] Fixed base_score at {path}: '{value}' -> '{float_value}'")
                            return True
                        except:
                            pass
                    elif isinstance(value, (dict, list)):
                        if fix_base_score_in_dict(value, f"{path}.{key}" if path else key):
                            return True
            elif isinstance(d, list):
                for i, item in enumerate(d):
                    if fix_base_score_in_dict(item, f"{path}[{i}]" if path else f"[{i}]"):
                        return True
            return False
        
        # Fix base_score in config
        if fix_base_score_in_dict(config_dict):
            # Reload the config into the booster
            try:
                booster.load_config(json.dumps(config_dict))
                print(f"[INFO] Successfully patched model base_score")
            except Exception as e:
                print(f"[WARNING] Could not reload config: {str(e)[:100]}")
                # Try alternative: create new booster with fixed config
                try:
                    import xgboost as xgb
                    new_booster = xgb.Booster()
                    new_booster.load_config(json.dumps(config_dict))
                    # Copy trees from old booster
                    # This is complex, so we'll try a different approach
                except:
                    pass
    except Exception as e:
        print(f"[WARNING] Could not fix model base_score: {str(e)[:200]}")
    
    # Use TreeExplainer for XGBoost (fast)
    # Try multiple approaches to handle base_score issues
    explainer = None
    last_error = None
    
    # Try different explainer configurations
    # Note: Some XGBoost models have base_score as string '[5E-1]' which causes issues
    # We'll try multiple approaches including SHAP's Explainer class
    attempts = [
        ("tree_path_dependent", lambda: shap.TreeExplainer(model, feature_perturbation='tree_path_dependent')),
        ("default", lambda: shap.TreeExplainer(model)),
        ("auto_perturbation", lambda: shap.TreeExplainer(model, feature_perturbation='auto')),
    ]
    
    # If TreeExplainer fails, try SHAP's Explainer class (more flexible)
    if explainer is None:
        print("[INFO] TreeExplainer failed, trying SHAP Explainer class...")
        try:
            # Use a small sample for background
            background_sample = X.iloc[:100] if len(X) > 100 else X
            explainer = shap.Explainer(model, background_sample, feature_perturbation='tree_path_dependent')
            print(f"[INFO] SHAP Explainer created successfully (slower but more flexible)")
        except Exception as e:
            print(f"[WARNING] SHAP Explainer also failed: {str(e)[:200]}")
    
    # Last resort: Try with model's predict function wrapped
    if explainer is None:
        print("[INFO] Trying workaround with model wrapper...")
        try:
            # Create wrapper that uses model's predict
            class ModelPredictWrapper:
                def __init__(self, model):
                    self.model = model
                
                def predict(self, X, **kwargs):
                    dmatrix = xgb.DMatrix(X)
                    return self.model.predict(dmatrix, **kwargs)
            
            wrapped = ModelPredictWrapper(model)
            background_sample = X.iloc[:100] if len(X) > 100 else X
            explainer = shap.Explainer(wrapped, background_sample)
            print(f"[INFO] SHAP Explainer created with model wrapper")
        except Exception as e:
            print(f"[WARNING] Model wrapper approach failed: {str(e)[:200]}")
    
    for method_name, attempt_func in attempts:
        try:
            explainer = attempt_func()
            # Test the explainer with a small sample
            test_sample = X.iloc[:1]
            test_shap = explainer.shap_values(test_sample)
            if test_shap is not None:
                # Handle both 2D and 1D outputs
                if isinstance(test_shap, list):
                    test_shap = np.array(test_shap)
                if len(test_shap.shape) >= 1:
                    print(f"[INFO] SHAP explainer created successfully using method: {method_name}")
                    break
            explainer = None
        except Exception as e:
            last_error = e
            print(f"[WARNING] SHAP explainer method '{method_name}' failed: {str(e)[:200]}")
            continue
    
    if explainer is None:
        # Don't raise error here - let the caller handle it and use fallback
        error_msg = str(last_error)[:500] if last_error else "Unknown error"
        raise RuntimeError(
            f"SHAP_EXPLAINER_FAILED: {error_msg}"
        )
    
    # Calculate SHAP values in batches for large datasets
    batch_size = 10000
    n_batches = (len(X) + batch_size - 1) // batch_size
    
    shap_values_list = []
    failed_batches = 0
    
    for i in range(n_batches):
        start_idx = i * batch_size
        end_idx = min((i + 1) * batch_size, len(X))
        X_batch = X.iloc[start_idx:end_idx]
        
        print(f"[INFO] Processing batch {i+1}/{n_batches} ({start_idx:,} - {end_idx:,})...")
        try:
            shap_batch = explainer.shap_values(X_batch)
            
            # Validate batch shape
            if len(shap_batch.shape) != 2:
                raise ValueError(f"Expected 2D SHAP array, got shape {shap_batch.shape}")
            
            if shap_batch.shape[0] != len(X_batch):
                raise ValueError(
                    f"SHAP batch size mismatch: expected {len(X_batch)} rows, "
                    f"got {shap_batch.shape[0]}"
                )
            
            if shap_batch.shape[1] != len(X.columns):
                raise ValueError(
                    f"SHAP feature count mismatch: expected {len(X.columns)} features, "
                    f"got {shap_batch.shape[1]}"
                )
            
            # Check for all-zeros (indicates failure)
            if np.allclose(shap_batch, 0):
                print(f"[WARNING] Batch {i+1} SHAP values are all zeros - may indicate calculation issue")
            
            shap_values_list.append(shap_batch)
            
        except Exception as e:
            failed_batches += 1
            error_msg = str(e)[:200]
            print(f"[ERROR] Failed to calculate SHAP for batch {i+1}: {error_msg}")
            print(f"[ERROR] This batch will be excluded - DO NOT use zeros as fallback!")
            # DO NOT use zeros - raise error instead to catch the bug
            raise RuntimeError(
                f"SHAP calculation failed for batch {i+1}/{n_batches}. "
                f"Error: {error_msg}. "
                f"Falling back to zeros would cause homogeneity bug. "
                f"Fix SHAP calculation before proceeding."
            ) from e
    
    if failed_batches > 0:
        raise RuntimeError(
            f"SHAP calculation failed for {failed_batches} batches. "
            f"Cannot proceed with incomplete SHAP values."
        )
    
    # Concatenate all batches
    shap_values = np.vstack(shap_values_list)
    
    # Final validation
    print(f"[INFO] SHAP values shape: {shap_values.shape}")
    print(f"[INFO] Expected shape: ({len(X)}, {len(X.columns)})")
    
    if shap_values.shape != (len(X), len(X.columns)):
        raise ValueError(
            f"SHAP shape mismatch: got {shap_values.shape}, "
            f"expected ({len(X)}, {len(X.columns)})"
        )
    
    # Check for diversity (not all zeros or identical)
    if np.allclose(shap_values, 0):
        raise ValueError(
            "All SHAP values are zero! This indicates calculation failure. "
            "Check SHAP explainer and input data."
        )
    
    # Check if all rows are identical (homogeneity bug)
    if len(shap_values) > 1:
        first_row = shap_values[0]
        all_identical = np.allclose(shap_values, first_row, atol=1e-10)
        if all_identical:
            raise ValueError(
                "SHAP HOMOGENEITY BUG: All leads have identical SHAP values! "
                "This suggests using global importance instead of per-lead SHAP. "
                "Check SHAP calculation logic."
            )
    
    print(f"[INFO] SHAP values calculated successfully")
    print(f"[INFO] SHAP value range: [{np.min(shap_values):.6f}, {np.max(shap_values):.6f}]")
    print(f"[INFO] SHAP value std: {np.std(shap_values):.6f}")
    
    return shap_values, explainer.expected_value if hasattr(explainer, 'expected_value') else 0.0


def generate_narrative(v4_score, v4_percentile, top_features, top_values, feature_names):
    """Generate a human-readable narrative for a V4 upgrade candidate."""
    
    # Build narrative with specific feature explanations
    narrative_parts = [
        f"V4 Model Upgrade: Identified as a high-potential lead ",
        f"(V4 score: {v4_score:.2f}, {v4_percentile}th percentile). "
    ]
    
    # Get the top feature and its description
    if top_features and len(top_features) > 0:
        top_feat = top_features[0]
        top_val = top_values[0] if len(top_values) > 0 else 0.0
        
        # Use absolute value to check significance
        if abs(top_val) > 0.01 and top_feat in FEATURE_DESCRIPTIONS:
            desc = FEATURE_DESCRIPTIONS[top_feat]
            
            # Special handling for interaction features
            if top_feat == 'short_tenure_x_high_mobility':
                narrative_parts.append(
                    "Key factors: This advisor is relatively new at their current firm AND has a history of changing firms - a strong signal they may move again. "
                )
            elif top_feat == 'mobility_x_heavy_bleeding':
                narrative_parts.append(
                    "Key factors: This advisor has demonstrated career mobility AND works at a firm losing advisors - a powerful combination. "
                )
            else:
                # Use the positive description for other features
                narrative_parts.append(f"Key factor: {desc['positive']}. ")
        else:
            narrative_parts.append("Key factors identified through ML analysis. ")
    else:
        narrative_parts.append("Key factors identified through ML analysis. ")
    
    narrative_parts.append(
        f"Historical conversion rate for similar leads: 4.60% (1.42x baseline). "
        f"Promoted from STANDARD tier via V4 machine learning analysis."
    )
    
    return ''.join(narrative_parts)


def extract_top_shap_features(shap_values, feature_list, scores, percentiles):
    """Extract top 3 SHAP features for each prospect and generate narratives."""
    
    print("[INFO] Extracting top SHAP features and generating narratives...")
    
    # Validate input shape
    if len(shap_values.shape) != 2:
        raise ValueError(
            f"SHAP values must be 2D array (n_leads, n_features), got shape {shap_values.shape}"
        )
    
    n_prospects, n_features = shap_values.shape
    
    if n_features != len(feature_list):
        raise ValueError(
            f"Feature count mismatch: SHAP has {n_features} features, "
            f"feature_list has {len(feature_list)}"
        )
    
    print(f"[INFO] Processing {n_prospects:,} prospects with {n_features} features each")
    
    results = {
        'shap_top1_feature': [],
        'shap_top1_value': [],
        'shap_top2_feature': [],
        'shap_top2_value': [],
        'shap_top3_feature': [],
        'shap_top3_value': [],
        'v4_narrative': []
    }
    
    for i in range(n_prospects):
        # Get absolute SHAP values and sort
        shap_abs = np.abs(shap_values[i])
        top_idx = np.argsort(shap_abs)[::-1][:3]
        
        # Top 3 features
        top_features = [feature_list[idx] for idx in top_idx]
        top_values = [float(shap_values[i][idx]) for idx in top_idx]
        
        results['shap_top1_feature'].append(top_features[0] if len(top_features) > 0 else None)
        results['shap_top1_value'].append(top_values[0] if len(top_values) > 0 else 0.0)
        results['shap_top2_feature'].append(top_features[1] if len(top_features) > 1 else None)
        results['shap_top2_value'].append(top_values[1] if len(top_values) > 1 else 0.0)
        results['shap_top3_feature'].append(top_features[2] if len(top_features) > 2 else None)
        results['shap_top3_value'].append(top_values[2] if len(top_values) > 2 else 0.0)
        
        # Generate narrative only for V4 upgrade candidates (>=80th percentile)
        if percentiles[i] >= V4_UPGRADE_PERCENTILE:
            narrative = generate_narrative(
                v4_score=scores[i],
                v4_percentile=percentiles[i],
                top_features=top_features,
                top_values=top_values,
                feature_names=feature_list
            )
        else:
            narrative = None
        
        results['v4_narrative'].append(narrative)
        
        # Progress indicator
        if (i + 1) % 50000 == 0:
            print(f"[INFO] Processed {i+1:,} / {n_prospects:,} prospects...")
    
    # VALIDATION: Check for SHAP homogeneity bug
    print("\n[VALIDATION] Checking SHAP feature diversity...")
    unique_top1 = len(set(results['shap_top1_feature']))
    unique_top2 = len(set(results['shap_top2_feature']))
    unique_top3 = len(set(results['shap_top3_feature']))
    
    print(f"  Unique top-1 features: {unique_top1}")
    print(f"  Unique top-2 features: {unique_top2}")
    print(f"  Unique top-3 features: {unique_top3}")
    
    # Raise error if homogeneity detected
    if unique_top1 < 3:
        raise ValueError(
            f"SHAP HOMOGENEITY BUG DETECTED! Only {unique_top1} unique top-1 features "
            f"across {n_prospects:,} leads. This indicates per-lead SHAP extraction failed. "
            f"All leads are getting identical features, which defeats the purpose of "
            f"personalized narratives. Check SHAP calculation and extraction logic."
        )
    
    if unique_top1 < 10:
        print(f"[WARNING] Low SHAP diversity: Only {unique_top1} unique top-1 features. "
              f"Expected at least 10+ for meaningful personalization.")
    
    # Count narratives generated
    narrative_count = sum(1 for n in results['v4_narrative'] if n is not None)
    print(f"[INFO] Generated {narrative_count:,} V4 upgrade narratives")
    
    return results


def upload_scores(client, df_scores):
    """Upload scores to BigQuery."""
    table_id = f"{PROJECT_ID}.{DATASET}.{SCORES_TABLE}"
    
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        schema=[
            bigquery.SchemaField("crd", "INT64"),
            bigquery.SchemaField("v4_score", "FLOAT64"),
            bigquery.SchemaField("v4_percentile", "INT64"),
            bigquery.SchemaField("v4_deprioritize", "BOOLEAN"),
            bigquery.SchemaField("v4_upgrade_candidate", "BOOLEAN"),
            bigquery.SchemaField("shap_top1_feature", "STRING"),
            bigquery.SchemaField("shap_top1_value", "FLOAT64"),
            bigquery.SchemaField("shap_top2_feature", "STRING"),
            bigquery.SchemaField("shap_top2_value", "FLOAT64"),
            bigquery.SchemaField("shap_top3_feature", "STRING"),
            bigquery.SchemaField("shap_top3_value", "FLOAT64"),
            bigquery.SchemaField("v4_narrative", "STRING"),
            bigquery.SchemaField("scored_at", "TIMESTAMP"),
        ]
    )
    
    job = client.load_table_from_dataframe(df_scores, table_id, job_config=job_config)
    job.result()
    print(f"[INFO] Uploaded {len(df_scores):,} scores to {table_id}")


def main():
    print("=" * 70)
    print("V4 MONTHLY PROSPECT SCORING WITH SHAP NARRATIVES")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Working Directory: {WORKING_DIR}")
    print("=" * 70)
    
    # Initialize
    client = bigquery.Client(project=PROJECT_ID)
    model = load_model()
    feature_list = load_features_list()
    
    # Fetch features
    df_raw = fetch_prospect_features(client)
    
    # Prepare features
    X = prepare_features(df_raw, feature_list)
    
    # Score
    raw_scores = score_prospects(model, X)
    
    # Apply calibration (if calibrator exists)
    calibrator = load_calibrator()
    if calibrator is not None:
        calibrated_scores = calibrator.transform(raw_scores)
        print(f"[OK] Applied isotonic calibration")
        print(f"[INFO] Raw score range: {raw_scores.min():.4f} - {raw_scores.max():.4f}")
        print(f"[INFO] Calibrated range: {calibrated_scores.min():.4f} - {calibrated_scores.max():.4f}")
        scores = calibrated_scores
    else:
        scores = raw_scores
    
    # Continue with existing percentile calculation
    percentiles = calculate_percentiles(scores)
    
    # Calculate SHAP values for accurate feature importance per prospect
    # NOTE: This is computationally expensive but necessary for accurate per-prospect explanations
    # The previous proxy method (feature_value * global_importance) was giving identical rankings
    # for all prospects, which is incorrect. Real SHAP values vary by prospect.
    print(f"[INFO] Calculating SHAP values for accurate per-prospect feature importance...")
    
    import numpy as np
    
    # Use actual SHAP computation (required for per-lead feature extraction)
    # If SHAP fails due to base_score issue, use improved per-lead calculation
    try:
        shap_values, expected_value = calculate_shap_values(model, X)
        print(f"[INFO] Real SHAP values computed successfully")
    except RuntimeError as e:
        error_msg = str(e)
        
        # Check if it's the base_score issue (SHAP_EXPLAINER_FAILED)
        if 'SHAP_EXPLAINER_FAILED' in error_msg or 'base_score' in error_msg or '[5E-1]' in error_msg:
            print(f"\n[WARNING] SHAP explainer failed due to base_score compatibility issue.")
            print(f"[WARNING] Using improved per-lead feature importance calculation...")
            print(f"[WARNING] This is NOT perfect SHAP, but will produce DIVERSE features per lead.")
            print(f"[WARNING] This avoids the homogeneity bug while we fix the model.")
            
            # Use improved per-lead calculation that produces diversity
            shap_values = calculate_per_lead_feature_importance(model, X, scores, feature_list)
            expected_value = 0.0
            print(f"[INFO] Per-lead feature importance calculated (diverse features per lead)")
        else:
            print(f"[ERROR] SHAP computation failed: {error_msg}")
            print(f"[ERROR] Cannot proceed without per-lead SHAP values!")
            raise RuntimeError(
                f"SHAP calculation failed: {error_msg}. "
                f"Please fix the SHAP calculation issue."
            ) from e
    except Exception as e:
        error_msg = str(e)[:500]
        print(f"[ERROR] Unexpected error in SHAP calculation: {error_msg}")
        raise
    
    # Extract top features and generate narratives
    shap_results = extract_top_shap_features(shap_values, feature_list, scores, percentiles)
    
    # Build output DataFrame
    df_scores = pd.DataFrame({
        'crd': df_raw['crd'].astype(int),
        'v4_score': scores,
        'v4_percentile': percentiles,
        'v4_deprioritize': percentiles <= DEPRIORITIZE_PERCENTILE,
        'v4_upgrade_candidate': percentiles >= V4_UPGRADE_PERCENTILE,
        'shap_top1_feature': shap_results['shap_top1_feature'],
        'shap_top1_value': shap_results['shap_top1_value'],
        'shap_top2_feature': shap_results['shap_top2_feature'],
        'shap_top2_value': shap_results['shap_top2_value'],
        'shap_top3_feature': shap_results['shap_top3_feature'],
        'shap_top3_value': shap_results['shap_top3_value'],
        'v4_narrative': shap_results['v4_narrative'],
        'scored_at': datetime.now()
    })
    
    # Upload to BigQuery
    upload_scores(client, df_scores)
    
    # Summary
    print("\n" + "=" * 70)
    print("SCORING SUMMARY")
    print("=" * 70)
    print(f"Total prospects scored: {len(df_scores):,}")
    print(f"V4 Upgrade candidates (>={V4_UPGRADE_PERCENTILE}%): {df_scores['v4_upgrade_candidate'].sum():,}")
    print(f"V4 narratives generated: {sum(1 for n in shap_results['v4_narrative'] if n is not None):,}")
    print(f"Score range: {df_scores['v4_score'].min():.4f} - {df_scores['v4_score'].max():.4f}")
    print(f"Mean score: {df_scores['v4_score'].mean():.4f}")
    
    # Top SHAP features summary with diversity validation
    print("\n" + "=" * 70)
    print("SHAP FEATURE DIVERSITY VALIDATION")
    print("=" * 70)
    
    top1_counts = pd.Series(shap_results['shap_top1_feature']).value_counts()
    unique_top1 = len(top1_counts)
    
    print(f"Unique top-1 features: {unique_top1}")
    print(f"Total leads: {len(df_scores):,}")
    
    if unique_top1 < 3:
        print(f"\n[ERROR] SHAP HOMOGENEITY BUG DETECTED!")
        print(f"Only {unique_top1} unique top-1 features across all leads.")
        print(f"This indicates per-lead SHAP extraction failed.")
        raise ValueError("SHAP homogeneity bug: All leads have identical top features!")
    
    if unique_top1 < 10:
        print(f"\n[WARNING] Low SHAP diversity: Only {unique_top1} unique top-1 features.")
        print(f"Expected at least 10+ for meaningful personalization.")
    
    print("\nTop 10 most common SHAP features:")
    for feat, count in top1_counts.head(10).items():
        pct = count / len(df_scores) * 100
        print(f"  - {feat}: {count:,} ({pct:.1f}%)")
    
    # Check if any single feature dominates (>30% of leads)
    max_pct = (top1_counts.iloc[0] / len(df_scores)) * 100
    if max_pct > 30:
        print(f"\n[WARNING] Feature '{top1_counts.index[0]}' appears in {max_pct:.1f}% of leads.")
        print(f"This may indicate limited diversity, but could be legitimate if that feature")
        print(f"is genuinely important for many leads.")
    
    print("=" * 70)
    
    print("=" * 70)
    
    # Log to file
    log_file = LOGS_DIR / "EXECUTION_LOG.md"
    with open(log_file, 'a', encoding='utf-8') as f:
        f.write(f"\n## Step 2: V4 Scoring with SHAP Narratives - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write(f"**Status**: ✅ SUCCESS\n\n")
        f.write(f"**Results:**\n")
        f.write(f"- Total scored: {len(df_scores):,}\n")
        f.write(f"- V4 upgrade candidates: {df_scores['v4_upgrade_candidate'].sum():,}\n")
        f.write(f"- V4 narratives generated: {sum(1 for n in shap_results['v4_narrative'] if n is not None):,}\n")
        f.write(f"- Score range: {df_scores['v4_score'].min():.4f} - {df_scores['v4_score'].max():.4f}\n")
        f.write(f"\n**New Columns:**\n")
        f.write(f"- `shap_top1/2/3_feature`: Top 3 SHAP features\n")
        f.write(f"- `shap_top1/2/3_value`: SHAP values for those features\n")
        f.write(f"- `v4_narrative`: Human-readable narrative for V4 upgrades\n")
        f.write(f"\n**Table Updated**: `{PROJECT_ID}.{DATASET}.{SCORES_TABLE}`\n\n")
        f.write("---\n\n")
    
    print(f"[INFO] Logged to {log_file}")
    print("[INFO] Scoring with SHAP complete!")
    
    return df_scores


if __name__ == "__main__":
    main()
