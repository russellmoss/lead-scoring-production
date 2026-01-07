"""Test direct patching of booster internal structure."""
import pickle
import shap
import json
from pathlib import Path

MODEL_PATH = Path(__file__).parent.parent / "models" / "v4.2.0" / "model.pkl"

with open(MODEL_PATH, 'rb') as f:
    model = pickle.load(f)

booster = model.get_booster()

# Try to access internal _Booster object
print("Trying to patch internal structure...")
try:
    # XGBoost booster has a handle attribute that points to the C++ object
    # We can't directly modify C++ objects, but we can try to modify the Python wrapper
    
    # Method: Replace the save_config method to return fixed config
    original_save_config = booster.save_config
    
    def fixed_save_config():
        config_str = original_save_config()
        import json
        config = json.loads(config_str)
        
        # Fix base_score
        lmp = config.get('learner', {}).get('learner_model_param', {})
        if 'base_score' in lmp:
            bs = lmp['base_score']
            print(f"  Found base_score in config: {bs}")
            if isinstance(bs, str) and '[' in bs:
                clean = bs.replace('[', '').replace(']', '').strip()
                parsed = float(clean)
                lmp['base_score'] = str(parsed)
                print(f"  Fixed to: {parsed}")
        
        return json.dumps(config)
    
    booster.save_config = fixed_save_config
    
    # Verify patch works
    test_config = booster.save_config()
    test_config_dict = json.loads(test_config)
    test_lmp = test_config_dict.get('learner', {}).get('learner_model_param', {})
    print(f"  Verified base_score after patch: {test_lmp.get('base_score')}")
    
    # Try SHAP
    print("\nTrying SHAP TreeExplainer with patched save_config...")
    explainer = shap.TreeExplainer(booster)
    print("SUCCESS!")
    
except Exception as e:
    print(f"FAILED: {e}")
    import traceback
    traceback.print_exc()
