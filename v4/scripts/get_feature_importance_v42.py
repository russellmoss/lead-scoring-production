"""
Quick script to extract feature importance from trained V4.2.0 model
"""
import json
import pickle
import pandas as pd
from pathlib import Path

BASE_DIR = Path(__file__).parent.parent
MODELS_DIR = BASE_DIR / "models" / "v4.2.0"
DATA_DIR = BASE_DIR / "data" / "v4.2.0"

# Load model
model_path = MODELS_DIR / "model.pkl"
with open(model_path, 'rb') as f:
    model = pickle.load(f)

# Load feature list
features_json = DATA_DIR / "final_features.json"
with open(features_json, 'r') as f:
    features_config = json.load(f)
    feature_list = features_config['final_features']

# Get importance
importance = model.get_score(importance_type='gain')

# Map to feature names
importance_data = []
for k, v in importance.items():
    if k.startswith('f') and k[1:].isdigit():
        idx = int(k[1:])
        if idx < len(feature_list):
            importance_data.append({
                'feature': feature_list[idx],
                'importance': v
            })

if not importance_data:
    print("[WARNING] No importance data extracted. Trying weight method...")
    importance = model.get_score(importance_type='weight')
    for k, v in importance.items():
        if k.startswith('f') and k[1:].isdigit():
            idx = int(k[1:])
            if idx < len(feature_list):
                importance_data.append({
                    'feature': feature_list[idx],
                    'importance': v
                })

if not importance_data:
    print("[ERROR] Could not extract feature importance from model")
    importance_df = pd.DataFrame(columns=['feature', 'importance'])
else:
    importance_df = pd.DataFrame(importance_data)
    if len(importance_df) > 0:
        importance_df = importance_df.sort_values('importance', ascending=False)

print("Top 15 Features by Importance:")
print(importance_df.head(15).to_string(index=False))

cc_features = importance_df[importance_df['feature'].str.startswith('cc_')]
print(f"\nCareer Clock Features:")
print(cc_features.to_string(index=False))

# Save
importance_df.to_csv(MODELS_DIR / "feature_importance.csv", index=False)
print(f"\nSaved to: {MODELS_DIR / 'feature_importance.csv'}")
