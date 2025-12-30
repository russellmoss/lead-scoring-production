"""Fix XGBoost model base_score issue for SHAP compatibility."""
import xgboost as xgb
import json
from pathlib import Path

model_json_path = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\models\v4.0.0\model.json")
model_pkl_path = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\models\v4.0.0\model.pkl")

print("Loading model...")
model = xgb.Booster()
model.load_model(str(model_json_path))

print("Getting config...")
config_str = model.save_config()
config = json.loads(config_str)

# Find base_score in the config
def find_and_fix_base_score(obj, path=""):
    """Recursively find and fix base_score."""
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key == 'base_score' and isinstance(value, str):
                print(f"Found base_score at {path}: '{value}'")
                try:
                    # Clean and convert
                    clean = value.strip('[]').strip()
                    float_val = float(clean)
                    obj[key] = str(float_val)  # Keep as string but clean
                    print(f"  Fixed to: '{float_val}'")
                    return True
                except Exception as e:
                    print(f"  Error fixing: {e}")
            elif isinstance(value, (dict, list)):
                if find_and_fix_base_score(value, f"{path}.{key}" if path else key):
                    return True
    elif isinstance(obj, list):
        for i, item in enumerate(obj):
            if find_and_fix_base_score(item, f"{path}[{i}]" if path else f"[{i}]"):
                return True
    return False

if find_and_fix_base_score(config):
    print("\nReloading model with fixed config...")
    try:
        # Create a new model with the fixed config
        new_model = xgb.Booster()
        new_model.load_config(json.dumps(config))
        
        # Copy the tree structure from the old model
        # Get the model JSON and update it
        model_json_str = model.save_model('')
        model_json = json.loads(model_json_str)
        
        # Update base_score in the model JSON as well
        if 'learner' in model_json and 'learner_model_param' in model_json['learner']:
            if 'base_score' in model_json['learner']['learner_model_param']:
                old_bs = model_json['learner']['learner_model_param']['base_score']
                if isinstance(old_bs, str) and old_bs.startswith('['):
                    clean = old_bs.strip('[]').strip()
                    model_json['learner']['learner_model_param']['base_score'] = str(float(clean))
                    print(f"Also fixed base_score in model JSON: '{old_bs}' -> '{model_json['learner']['learner_model_param']['base_score']}'")
        
        # Save the fixed model JSON
        fixed_path = model_json_path.parent / "model_fixed.json"
        with open(fixed_path, 'w') as f:
            json.dump(model_json, f)
        print(f"Saved fixed model JSON to: {fixed_path}")
        
        # Also try to load it back and save as XGBoost format
        try:
            test_model = xgb.Booster()
            test_model.load_model(str(fixed_path))
            # Save in XGBoost binary format too
            fixed_bin_path = model_json_path.parent / "model_fixed.bin"
            test_model.save_model(str(fixed_bin_path))
            print(f"Also saved as binary: {fixed_bin_path}")
        except:
            pass
            
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
else:
    print("Could not find base_score in config")

