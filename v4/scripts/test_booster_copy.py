"""Test creating a new booster with fixed base_score."""
import pickle
import shap
import json
from pathlib import Path

MODEL_PATH = Path(__file__).parent.parent / "models" / "v4.2.0" / "model.pkl"

with open(MODEL_PATH, 'rb') as f:
    model = pickle.load(f)

booster = model.get_booster()

# Save to JSON
print("Saving to JSON...")
json_path = MODEL_PATH.with_suffix('.temp.json')
booster.save_model(str(json_path))

# Load JSON and fix
print("Fixing base_score in JSON...")
with open(json_path, 'r') as f:
    json_data = json.load(f)

lmp = json_data.get('learner', {}).get('learner_model_param', {})
if 'base_score' in lmp:
    bs = lmp['base_score']
    print(f"  Original: {bs}")
    if isinstance(bs, str) and '[' in bs:
        clean = bs.replace('[', '').replace(']', '').strip()
        parsed = float(clean)
        lmp['base_score'] = str(parsed)
        print(f"  Fixed to: {parsed}")

# Save fixed JSON
with open(json_path, 'w') as f:
    json.dump(json_data, f)

# Create new booster from fixed JSON
print("Creating new booster from fixed JSON...")
import xgboost as xgb
new_booster = xgb.Booster()
new_booster.load_model(str(json_path))

# Verify
config_str = new_booster.save_config()
config = json.loads(config_str)
lmp2 = config.get('learner', {}).get('learner_model_param', {})
print(f"  New booster base_score: {lmp2.get('base_score')}")

# Try SHAP
print("\nTrying SHAP with new booster...")
try:
    explainer = shap.TreeExplainer(new_booster)
    print("SUCCESS!")
except Exception as e:
    print(f"FAILED: {e}")
    import traceback
    traceback.print_exc()

# Cleanup
import os
os.unlink(json_path)
