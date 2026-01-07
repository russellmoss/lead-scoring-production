"""Test if JSON model works with SHAP."""
import xgboost as xgb
import shap
from pathlib import Path

MODEL_PATH = Path("v4/models/v4.2.0/model.json")

print("Loading model from JSON...")
model = xgb.XGBClassifier()
model.load_model(str(MODEL_PATH))

print("Testing SHAP TreeExplainer...")
try:
    explainer = shap.TreeExplainer(model)
    print("[SUCCESS] SHAP TreeExplainer initialized successfully!")
    
    # Test with dummy data
    import pandas as pd
    import numpy as np
    
    # Create dummy feature data (23 features for V4.2.0)
    dummy_data = pd.DataFrame([{
        'tenure_months': 24, 'mobility_3yr': 2, 'firm_rep_count_at_contact': 15,
        'firm_net_change_12mo': -5, 'is_wirehouse': 0, 'is_broker_protocol': 1,
        'has_email': 1, 'has_linkedin': 1, 'has_firm_data': 1,
        'mobility_x_heavy_bleeding': 1, 'short_tenure_x_high_mobility': 1,
        'experience_years': 12, 'tenure_bucket_encoded': 1, 'mobility_tier_encoded': 2,
        'firm_stability_tier_encoded': 2, 'is_recent_mover': 1, 'days_since_last_move': 180,
        'firm_departures_corrected': 5, 'bleeding_velocity_encoded': 2,
        'is_independent_ria': 1, 'is_ia_rep_type': 0, 'is_dual_registered': 0,
        'age_bucket_encoded': 1
    }])
    
    shap_values = explainer.shap_values(dummy_data)
    print(f"[SUCCESS] SHAP values calculated! Shape: {np.array(shap_values).shape}")
    
except Exception as e:
    print(f"[ERROR] SHAP failed: {e}")
    import traceback
    traceback.print_exc()
