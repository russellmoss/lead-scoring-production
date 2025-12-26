"""Test if we can create SHAP explainer with the model."""
import xgboost as xgb
import shap
import json
from pathlib import Path

model_path = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\models\v4.0.0\model.json")

print("Loading model...")
model = xgb.Booster()
model.load_model(str(model_path))

print("Getting config...")
config_str = model.save_config()
config = json.loads(config_str)

# Find base_score in config
def find_base_score(obj, path=""):
    """Find base_score."""
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key == 'base_score':
                print(f"Found base_score at {path}: '{value}' (type: {type(value).__name__})")
            elif isinstance(value, (dict, list)):
                find_base_score(value, f"{path}.{key}" if path else key)
    elif isinstance(obj, list):
        for i, item in enumerate(obj):
            find_base_score(item, f"{path}[{i}]" if path else f"[{i}]")

print("\nSearching for base_score in config:")
find_base_score(config)

# Try to fix it
print("\nAttempting to fix...")
def fix_base_score(obj):
    """Fix base_score recursively."""
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key == 'base_score' and isinstance(value, str) and value.startswith('['):
                clean = value.strip('[]').strip()
                try:
                    float_val = float(clean)
                    obj[key] = str(float_val)
                    print(f"Fixed: '{value}' -> '{float_val}'")
                    return True
                except:
                    pass
            elif isinstance(value, (dict, list)):
                if fix_base_score(value):
                    return True
    elif isinstance(obj, list):
        for item in obj:
            if fix_base_score(item):
                return True
    return False

if fix_base_score(config):
    print("\nReloading config...")
    model.load_config(json.dumps(config))
    print("Config reloaded")

# Try to fix it in the model's internal structure directly
print("\nAttempting to fix in model's internal structure...")
try:
    # Get the model's internal dict representation
    model_dict = model.get_dump(dump_format='json')
    # This doesn't work, let's try a different approach
    
    # Try to set base_score via booster attributes
    booster = model
    try:
        # Get the raw model bytes and parse
        import io
        model_bytes = booster.save_raw()
        # This is complex, let's try setting it via the config and saving/reloading
        print("Saving model with fixed config...")
        temp_path = Path("temp_model_fixed.json")
        booster.save_model(str(temp_path))
        
        # Reload it
        new_model = xgb.Booster()
        new_model.load_model(str(temp_path))
        model = new_model
        print("Model reloaded with fixed config")
        temp_path.unlink()  # Clean up
    except Exception as e:
        print(f"Could not fix via save/reload: {e}")
except Exception as e:
    print(f"Could not access model internals: {e}")

print("\nTesting SHAP explainer creation...")
try:
    explainer = shap.TreeExplainer(model, feature_perturbation='tree_path_dependent')
    print("SUCCESS! SHAP explainer created!")
except Exception as e:
    print(f"FAILED: {e}")
    print("\nTrying alternative: Use model's get_dump to create a clean model...")
    # Alternative: Create a wrapper that fixes base_score on the fly
    try:
        # Monkey-patch the model's get_dump to return fixed base_score
        original_get_dump = model.get_dump
        
        def patched_get_dump(*args, **kwargs):
            dumps = original_get_dump(*args, **kwargs)
            # This won't work either...
            return dumps
        
        # Actually, let's try using the model's save_model and load_model cycle
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            temp_path = f.name
        model.save_model(temp_path)
        
        # Read, fix, and reload
        with open(temp_path, 'r') as f:
            model_json = json.load(f)
        if 'learner' in model_json and 'learner_model_param' in model_json['learner']:
            if model_json['learner']['learner_model_param'].get('base_score') == '[5E-1]':
                model_json['learner']['learner_model_param']['base_score'] = '0.5'
                with open(temp_path, 'w') as f:
                    json.dump(model_json, f)
        
        new_model = xgb.Booster()
        new_model.load_model(temp_path)
        import os
        os.unlink(temp_path)
        
        explainer = shap.TreeExplainer(new_model, feature_perturbation='tree_path_dependent')
        print("SUCCESS! SHAP explainer created with fixed model!")
    except Exception as e2:
        print(f"Alternative also failed: {e2}")
        import traceback
        traceback.print_exc()

