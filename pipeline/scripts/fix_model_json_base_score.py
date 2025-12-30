"""Fix base_score in model.json file directly."""
import json
from pathlib import Path

model_json_path = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\models\v4.0.0\model.json")

print(f"Loading {model_json_path}...")
with open(model_json_path, 'r', encoding='utf-8') as f:
    model_data = json.load(f)

def fix_base_score_in_dict(obj, path=""):
    """Recursively find and fix base_score."""
    fixed = False
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key == 'base_score' and isinstance(value, str) and value.startswith('['):
                print(f"Found base_score at {path}: '{value}'")
                try:
                    clean = value.strip('[]').strip()
                    float_val = float(clean)
                    obj[key] = str(float_val)
                    print(f"  Fixed to: '{float_val}'")
                    fixed = True
                except Exception as e:
                    print(f"  Error: {e}")
            elif isinstance(value, (dict, list)):
                if fix_base_score_in_dict(value, f"{path}.{key}" if path else key):
                    fixed = True
    elif isinstance(obj, list):
        for i, item in enumerate(obj):
            if fix_base_score_in_dict(item, f"{path}[{i}]" if path else f"[{i}]"):
                fixed = True
    return fixed

if fix_base_score_in_dict(model_data):
    # Save fixed model
    fixed_path = model_json_path.parent / "model_fixed.json"
    with open(fixed_path, 'w', encoding='utf-8') as f:
        json.dump(model_data, f, indent=2)
    print(f"\nSaved fixed model to: {fixed_path}")
    
    # Test loading it
    import xgboost as xgb
    try:
        test_model = xgb.Booster()
        test_model.load_model(str(fixed_path))
        print("✓ Fixed model loads successfully")
        
        # Test SHAP
        import shap
        try:
            explainer = shap.TreeExplainer(test_model, feature_perturbation='tree_path_dependent')
            print("✓ SHAP explainer created successfully!")
        except Exception as e:
            print(f"✗ SHAP explainer still fails: {e}")
    except Exception as e:
        print(f"✗ Error loading fixed model: {e}")
else:
    print("Could not find base_score to fix")

