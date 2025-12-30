"""Create a properly fixed model for SHAP by reading and rewriting the JSON."""
import json
import xgboost as xgb
from pathlib import Path

model_json_path = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\models\v4.0.0\model.json")
fixed_path = model_json_path.parent / "model_shap_fixed.json"

print(f"Reading {model_json_path}...")
with open(model_json_path, 'r', encoding='utf-8') as f:
    model_data = json.load(f)

# Fix base_score in the JSON structure
def fix_all_base_scores(obj):
    """Fix all base_score occurrences."""
    fixed = False
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key == 'base_score' and isinstance(value, str):
                if value.startswith('[') or value == '[5E-1]':
                    clean = value.strip('[]').strip()
                    try:
                        float_val = float(clean)
                        obj[key] = str(float_val)
                        print(f"Fixed base_score: '{value}' -> '{float_val}'")
                        fixed = True
                    except:
                        pass
            elif isinstance(value, (dict, list)):
                if fix_all_base_scores(value):
                    fixed = True
    elif isinstance(obj, list):
        for item in obj:
            if fix_all_base_scores(item):
                fixed = True
    return fixed

print("Fixing base_score in JSON...")
if fix_all_base_scores(model_data):
    print(f"\nSaving fixed model to {fixed_path}...")
    with open(fixed_path, 'w', encoding='utf-8') as f:
        json.dump(model_data, f, indent=2)
    
    # Test loading it
    print("Testing fixed model...")
    test_model = xgb.Booster()
    test_model.load_model(str(fixed_path))
    
    # Check config
    config = json.loads(test_model.save_config())
    bs = config.get('learner', {}).get('learner_model_param', {}).get('base_score', 'NOT_FOUND')
    print(f"Config base_score after load: '{bs}'")
    
    if bs != '[5E-1]' and bs != 'NOT_FOUND':
        print("✓ Model fixed successfully!")
    else:
        print("✗ Model still has issue - may need to retrain or use different approach")
else:
    print("No base_score found to fix")

