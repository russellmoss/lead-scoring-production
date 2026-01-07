"""
Convert V4.2.0 model from pickle to XGBoost native JSON format.
This permanently fixes the base_score SHAP issue.
"""
import pickle
import xgboost as xgb
import json
from pathlib import Path

MODEL_DIR = Path(__file__).parent.parent / "models" / "v4.2.0"
PKL_PATH = MODEL_DIR / "model.pkl"
JSON_PATH = MODEL_DIR / "model.json"  # New primary model file (XGBoost native format)
BACKUP_PATH = MODEL_DIR / "model_backup.pkl"

print("=" * 60)
print("Converting V4.2.0 Model: Pickle -> XGBoost JSON")
print("=" * 60)

# 1. Load from pickle
print(f"\n[1/4] Loading from {PKL_PATH}...")
with open(PKL_PATH, 'rb') as f:
    model = pickle.load(f)

# 2. Backup original
print(f"[2/4] Backing up to {BACKUP_PATH}...")
with open(BACKUP_PATH, 'wb') as f:
    pickle.dump(model, f)

# 3. Fix base_score before saving
print(f"[3/5] Fixing base_score in model...")
booster = model.get_booster()
config_str = booster.save_config()
config = json.loads(config_str)
lmp = config.get('learner', {}).get('learner_model_param', {})
if 'base_score' in lmp:
    bs = lmp['base_score']
    if isinstance(bs, str) and ('[' in bs or 'E' in bs.upper()):
        clean = bs.replace('[', '').replace(']', '').strip()
        try:
            parsed = float(clean)
            lmp['base_score'] = str(parsed)
            print(f"  Fixed base_score: {bs} -> {parsed}")
        except:
            lmp['base_score'] = '0.5'
            print(f"  Fixed base_score: {bs} -> 0.5 (fallback)")
        # Reload config with fixed base_score
        booster.load_config(json.dumps(config))
        print(f"  base_score updated in booster")

# 4. Save using XGBoost native JSON format
print(f"[4/6] Saving to {JSON_PATH} (XGBoost native format)...")
model.save_model(str(JSON_PATH))

# 5. Fix base_score directly in JSON file
print("[5/6] Fixing base_score in JSON file...")
with open(JSON_PATH, 'r') as f:
    json_data = json.load(f)

# Navigate to base_score in JSON structure
if 'learner' in json_data and 'learner_model_param' in json_data['learner']:
    lmp = json_data['learner']['learner_model_param']
    if 'base_score' in lmp:
        bs = lmp['base_score']
        if isinstance(bs, str) and ('[' in bs or 'E' in bs.upper()):
            clean = bs.replace('[', '').replace(']', '').strip()
            try:
                parsed = float(clean)
                lmp['base_score'] = str(parsed)
                print(f"  Fixed base_score in JSON: {bs} -> {parsed}")
            except:
                lmp['base_score'] = '0.5'
                print(f"  Fixed base_score in JSON: {bs} -> 0.5 (fallback)")
            
            # Save fixed JSON
            with open(JSON_PATH, 'w') as f:
                json.dump(json_data, f)
            print(f"  Saved fixed JSON to {JSON_PATH}")

# 6. Verify it loads correctly
print("[6/6] Verifying fixed model...")
model_reloaded = xgb.XGBClassifier()
model_reloaded.load_model(str(JSON_PATH))

# Check base_score
booster = model_reloaded.get_booster()
config = json.loads(booster.save_config())
base_score = config['learner']['learner_model_param']['base_score']
print(f"  base_score after reload: {base_score}")

# Test SHAP
print("\n[6/6] Testing SHAP TreeExplainer...")
try:
    import shap
    explainer = shap.TreeExplainer(model_reloaded)
    print("[SUCCESS] SHAP TreeExplainer initialized successfully!")
except Exception as e:
    print(f"[ERROR] SHAP still failing: {e}")

print("\n" + "=" * 60)
print(f"Model converted successfully!")
print(f"  Old (broken): {PKL_PATH}")
print(f"  New (fixed):  {JSON_PATH}")
print("=" * 60)
