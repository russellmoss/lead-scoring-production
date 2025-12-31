"""
Fit Isotonic Calibrator for V4.1 R3 Model
==========================================
One-time script to create calibrator. Run once, then archive.

Location: v4/calibration/fit_isotonic_calibrator.py
Output: v4/models/v4.1.0_r3/isotonic_calibrator.pkl

Usage: python v4/calibration/fit_isotonic_calibrator.py
"""

import pickle
import json
import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.isotonic import IsotonicRegression
from google.cloud import bigquery
from pathlib import Path
from datetime import datetime

# ============================================================================
# CONFIGURATION - DO NOT MODIFY PATHS
# ============================================================================
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production")
# IMPORTANT: Use paths discovered in Step 0.5
# Default to R3, but will fallback if not found
MODEL_DIR = WORKING_DIR / "v4" / "models" / "v4.1.0_r3"
DATA_DIR = WORKING_DIR / "v4" / "data" / "v4.1.0_r3"
CALIBRATION_DIR = WORKING_DIR / "v4" / "calibration"

# Verify paths exist, fallback to v4.1.0 if needed
if not MODEL_DIR.exists():
    MODEL_DIR = WORKING_DIR / "v4" / "models" / "v4.1.0"
    print(f"[INFO] Using alternate model directory: {MODEL_DIR}")

if not DATA_DIR.exists():
    DATA_DIR = WORKING_DIR / "v4" / "data" / "v4.1.0"
    print(f"[INFO] Using alternate data directory: {DATA_DIR}")

# Ensure calibration directory exists
CALIBRATION_DIR.mkdir(parents=True, exist_ok=True)

# BigQuery
PROJECT_ID = "savvy-gtm-analytics"
# Updated query to use correct table: v4_prospect_features (has all features + crd)
# Join with v4_target_variable to get target_mql_43d (which is stored as 'target')
TEST_DATA_QUERY = """
SELECT 
    f.crd,
    t.target as target_mql_43d,
    t.contacted_date,
    -- All 22 V4.1 features
    f.tenure_months,
    f.mobility_3yr,
    f.firm_rep_count_at_contact,
    f.firm_net_change_12mo,
    f.is_wirehouse,
    f.is_broker_protocol,
    f.has_email,
    f.has_linkedin,
    f.has_firm_data,
    f.mobility_x_heavy_bleeding,
    f.short_tenure_x_high_mobility,
    f.experience_years,
    f.tenure_bucket,
    f.mobility_tier,
    f.firm_stability_tier,
    f.is_recent_mover,
    f.days_since_last_move,
    f.firm_departures_corrected,
    f.bleeding_velocity_encoded,
    f.is_independent_ria,
    f.is_ia_rep_type,
    f.is_dual_registered
FROM `savvy-gtm-analytics.ml_features.v4_prospect_features` f
JOIN `savvy-gtm-analytics.ml_features.v4_target_variable` t
    ON f.crd = t.advisor_crd
WHERE t.contacted_date >= '2024-10-01'  -- Test period only
  AND t.target IS NOT NULL  -- Ensure target is available
"""

# Feature list - Will be loaded dynamically in main() to avoid import-time failures
FEATURES = None  # Set to None at module level, loaded in main()


def load_model():
    """Load V4.1 R3 model (read-only)."""
    # Try R3 directory first
    model_json_path = MODEL_DIR / "model.json"
    model_pkl_path = MODEL_DIR / "model.pkl"
    
    # If R3 directory doesn't exist, try v4.1.0 directory
    if not model_json_path.exists() and not model_pkl_path.exists():
        alt_model_dir = WORKING_DIR / "v4" / "models" / "v4.1.0"
        model_json_path = alt_model_dir / "model.json"
        model_pkl_path = alt_model_dir / "model.pkl"
        print(f"[INFO] R3 directory not found, trying {alt_model_dir}")
    
    # Try JSON first (preferred for XGBoost)
    if model_json_path.exists():
        model = xgb.Booster()
        model.load_model(str(model_json_path))
        print(f"[OK] Loaded model from {model_json_path}")
        return model
    
    # Fall back to pickle
    if model_pkl_path.exists():
        with open(model_pkl_path, 'rb') as f:
            model = pickle.load(f)
        print(f"[OK] Loaded model from {model_pkl_path}")
        return model
    
    raise FileNotFoundError(f"No model file found in {MODEL_DIR} or v4/models/v4.1.0/")


def load_test_data():
    """Load test data from BigQuery."""
    print("[INFO] Loading test data from BigQuery...")
    client = bigquery.Client(project=PROJECT_ID)
    df = client.query(TEST_DATA_QUERY).to_dataframe()
    print(f"[OK] Loaded {len(df):,} test records")
    return df


def prepare_features(df):
    """Prepare features for model inference."""
    global FEATURES
    
    if FEATURES is None:
        raise ValueError("FEATURES not loaded. Call main() to load features first.")
    
    X = df.copy()
    
    # Encode categorical columns (matching final_features.json)
    # Load mappings from final_features.json to ensure consistency
    features_file = DATA_DIR / "final_features.json"
    if not features_file.exists():
        features_file = WORKING_DIR / "v4" / "data" / "v4.1.0" / "final_features.json"
    
    with open(features_file, 'r') as f:
        features_data = json.load(f)
    
    categorical_mappings_raw = features_data.get('categorical_mappings', {})
    
    # Reverse mappings: string -> int (for encoding)
    categorical_mappings = {}
    if 'tenure_bucket' in categorical_mappings_raw:
        # tenure_bucket: {"0": "0-12", "1": "12-24", "2": "120+", "3": "24-48", "4": "48-120", "5": "Unknown"}
        categorical_mappings['tenure_bucket'] = {v: int(k) for k, v in categorical_mappings_raw['tenure_bucket'].items()}
    if 'mobility_tier' in categorical_mappings_raw:
        # mobility_tier: {"0": "High_Mobility", "1": "Low_Mobility", "2": "Stable"}
        categorical_mappings['mobility_tier'] = {v: int(k) for k, v in categorical_mappings_raw['mobility_tier'].items()}
    if 'firm_stability_tier' in categorical_mappings_raw:
        # firm_stability_tier: {"0": "Growing", "1": "Heavy_Bleeding", "2": "Light_Bleeding", "3": "Stable", "4": "Unknown"}
        categorical_mappings['firm_stability_tier'] = {v: int(k) for k, v in categorical_mappings_raw['firm_stability_tier'].items()}
    
    # Create encoded versions
    if 'tenure_bucket' in X.columns:
        X['tenure_bucket_encoded'] = X['tenure_bucket'].map(categorical_mappings.get('tenure_bucket', {})).fillna(0).astype(int)
    if 'mobility_tier' in X.columns:
        X['mobility_tier_encoded'] = X['mobility_tier'].map(categorical_mappings.get('mobility_tier', {})).fillna(0).astype(int)
    if 'firm_stability_tier' in X.columns:
        X['firm_stability_tier_encoded'] = X['firm_stability_tier'].map(categorical_mappings.get('firm_stability_tier', {})).fillna(0).astype(int)
    
    # Select only required features
    available_features = [f for f in FEATURES if f in X.columns]
    missing_features = [f for f in FEATURES if f not in X.columns]
    
    if missing_features:
        print(f"[WARNING] Missing features: {missing_features}")
        for f in missing_features:
            X[f] = 0
    
    X = X[FEATURES].fillna(0)
    return X


def main():
    global FEATURES
    
    print("=" * 70)
    print("ISOTONIC CALIBRATOR FITTING")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)
    
    # Load features dynamically (avoid import-time failures)
    features_file = DATA_DIR / "final_features.json"
    if not features_file.exists():
        # Try alternate path
        alt_data_dir = WORKING_DIR / "v4" / "data" / "v4.1.0"
        features_file = alt_data_dir / "final_features.json"
        if not features_file.exists():
            raise FileNotFoundError(f"final_features.json not found in {DATA_DIR} or {alt_data_dir}")
    
    with open(features_file, 'r') as f:
        features_data = json.load(f)
    FEATURES = features_data['final_features']
    print(f"[OK] Loaded {len(FEATURES)} features from {features_file}")
    
    # Load model (read-only)
    model = load_model()
    
    # Load test data
    df = load_test_data()
    
    # Prepare features
    X = prepare_features(df)
    y = df['target_mql_43d'].values
    
    print(f"[INFO] Feature matrix shape: {X.shape}")
    print(f"[INFO] Target: {y.sum()} positives / {len(y)} total ({y.mean()*100:.2f}%)")
    
    # Get raw predictions
    print("[INFO] Generating raw predictions...")
    dmatrix = xgb.DMatrix(X, feature_names=FEATURES)
    y_pred_raw = model.predict(dmatrix)
    
    print(f"[INFO] Raw prediction range: {y_pred_raw.min():.4f} - {y_pred_raw.max():.4f}")
    
    # Fit isotonic calibrator
    print("[INFO] Fitting isotonic regression calibrator...")
    calibrator = IsotonicRegression(out_of_bounds='clip')
    calibrator.fit(y_pred_raw, y)
    
    # Verify monotonicity
    test_inputs = np.linspace(y_pred_raw.min(), y_pred_raw.max(), 100)
    test_outputs = calibrator.transform(test_inputs)
    is_monotonic = all(test_outputs[i] <= test_outputs[i+1] for i in range(len(test_outputs)-1))
    
    print(f"[INFO] Calibrator is monotonic: {is_monotonic}")
    if not is_monotonic:
        raise ValueError("Calibrator is not monotonic! This should not happen.")
    
    # Get calibrated predictions
    y_pred_calibrated = calibrator.transform(y_pred_raw)
    print(f"[INFO] Calibrated prediction range: {y_pred_calibrated.min():.4f} - {y_pred_calibrated.max():.4f}")
    
    # Save calibrator
    calibrator_path = MODEL_DIR / "isotonic_calibrator.pkl"
    with open(calibrator_path, 'wb') as f:
        pickle.dump(calibrator, f)
    
    print(f"\n[SUCCESS] Calibrator saved to: {calibrator_path}")
    
    # Create metadata
    metadata = {
        "created": datetime.now().isoformat(),
        "model_version": "v4.1.0_r3",
        "test_samples": len(y),
        "positive_samples": int(y.sum()),
        "raw_pred_min": float(y_pred_raw.min()),
        "raw_pred_max": float(y_pred_raw.max()),
        "calibrated_pred_min": float(y_pred_calibrated.min()),
        "calibrated_pred_max": float(y_pred_calibrated.max()),
        "is_monotonic": is_monotonic
    }
    
    metadata_path = MODEL_DIR / "calibrator_metadata.json"
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print(f"[SUCCESS] Metadata saved to: {metadata_path}")
    
    # Summary
    print("\n" + "=" * 70)
    print("CALIBRATION COMPLETE")
    print("=" * 70)
    print(f"Calibrator: {calibrator_path}")
    print(f"Metadata: {metadata_path}")
    print(f"Monotonic: {is_monotonic}")
    print("=" * 70)
    
    return calibrator


if __name__ == "__main__":
    main()

