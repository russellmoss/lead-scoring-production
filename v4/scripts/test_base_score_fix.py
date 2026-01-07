"""Test if base_score fix works."""
import pickle
import shap
from pathlib import Path

MODEL_PATH = Path(__file__).parent.parent / "models" / "v4.2.0" / "model.pkl"

with open(MODEL_PATH, 'rb') as f:
    model = pickle.load(f)

booster = model.get_booster()

# Check config
config_str = booster.save_config()
import json
config = json.loads(config_str)

print("Before fix:")
lmp = config['learner']['learner_model_param']
print(f"  base_score: {lmp.get('base_score')}")

# Fix it
if 'base_score' in lmp:
    bs = lmp['base_score']
    if isinstance(bs, str) and '[' in bs:
        clean = bs.replace('[', '').replace(']', '').strip()
        parsed = float(clean)
        lmp['base_score'] = str(parsed)
        booster.load_config(json.dumps(config))
        print(f"  Fixed: {bs} -> {parsed}")

# Verify
config_str2 = booster.save_config()
config2 = json.loads(config_str2)
lmp2 = config2['learner']['learner_model_param']
print(f"\nAfter fix:")
print(f"  base_score: {lmp2.get('base_score')}")

# Try SHAP
print("\nTrying SHAP TreeExplainer...")
try:
    explainer = shap.TreeExplainer(booster)
    print("SUCCESS: SHAP TreeExplainer initialized!")
except Exception as e:
    print(f"FAILED: {e}")
    import traceback
    traceback.print_exc()
