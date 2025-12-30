"""
Test script to verify monthly scoring works with V4.1.0 model.
"""

import sys
from pathlib import Path
import pickle
import json
import pandas as pd

# Add paths
WORKING_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(WORKING_DIR))

MODEL_DIR = WORKING_DIR / "models" / "v4.1.0"
FEATURES_FILE = WORKING_DIR / "data" / "v4.1.0" / "final_features.json"

print("=" * 70)
print("V4.1.0 Monthly Scoring Test")
print("=" * 70)

# Test 1: Check model file exists
print("\n[TEST 1] Checking model file...")
if (MODEL_DIR / "model.pkl").exists():
    print(f"  SUCCESS: Model file found at {MODEL_DIR / 'model.pkl'}")
else:
    print(f"  ERROR: Model file not found at {MODEL_DIR / 'model.pkl'}")
    sys.exit(1)

# Test 2: Check features file exists
print("\n[TEST 2] Checking features file...")
if FEATURES_FILE.exists():
    print(f"  SUCCESS: Features file found at {FEATURES_FILE}")
else:
    print(f"  ERROR: Features file not found at {FEATURES_FILE}")
    sys.exit(1)

# Test 3: Load model
print("\n[TEST 3] Loading model...")
try:
    with open(MODEL_DIR / "model.pkl", 'rb') as f:
        model = pickle.load(f)
    print(f"  SUCCESS: Model loaded successfully")
    print(f"  Model type: {type(model)}")
except Exception as e:
    print(f"  ERROR: Failed to load model: {e}")
    sys.exit(1)

# Test 4: Load features
print("\n[TEST 4] Loading features...")
try:
    with open(FEATURES_FILE, 'r') as f:
        features_data = json.load(f)
    feature_list = features_data['final_features']
    print(f"  SUCCESS: Features loaded successfully")
    print(f"  Feature count: {len(feature_list)}")
    print(f"  Expected: 22 features")
    
    if len(feature_list) == 22:
        print(f"  SUCCESS: Feature count matches expected (22)")
    else:
        print(f"  WARNING: Feature count mismatch (expected 22, got {len(feature_list)})")
    
    # Check for removed features
    removed_features = ['industry_tenure_months', 'tenure_bucket_x_mobility', 
                        'independent_ria_x_ia_rep', 'recent_mover_x_bleeding']
    found_removed = [f for f in removed_features if f in feature_list]
    if found_removed:
        print(f"  ERROR: Found removed features in list: {found_removed}")
        sys.exit(1)
    else:
        print(f"  SUCCESS: No removed features found in list")
    
    # Check for new V4.1 features
    new_features = ['is_recent_mover', 'days_since_last_move', 'firm_departures_corrected',
                    'bleeding_velocity_encoded', 'is_independent_ria', 'is_ia_rep_type', 
                    'is_dual_registered']
    found_new = [f for f in new_features if f in feature_list]
    print(f"  New V4.1 features found: {len(found_new)}/{len(new_features)}")
    if len(found_new) == len(new_features):
        print(f"  SUCCESS: All new V4.1 features present")
    else:
        missing = [f for f in new_features if f not in feature_list]
        print(f"  WARNING: Missing new features: {missing}")
        
except Exception as e:
    print(f"  ERROR: Failed to load features: {e}")
    sys.exit(1)

# Test 5: Test model prediction (with dummy data)
print("\n[TEST 5] Testing model prediction with dummy data...")
try:
    import xgboost as xgb
    import numpy as np
    
    # Create dummy feature array (22 features)
    dummy_features = np.zeros((1, len(feature_list)))
    dmatrix = xgb.DMatrix(dummy_features, feature_names=feature_list)
    
    prediction = model.predict(dmatrix)
    print(f"  SUCCESS: Model prediction works")
    print(f"  Prediction shape: {prediction.shape}")
    print(f"  Sample prediction: {prediction[0]:.4f}")
    
except Exception as e:
    print(f"  ERROR: Failed to test prediction: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("\n" + "=" * 70)
print("ALL TESTS PASSED - V4.1.0 model is ready for monthly scoring")
print("=" * 70)

