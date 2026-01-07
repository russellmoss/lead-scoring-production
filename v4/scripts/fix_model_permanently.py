"""Permanently fix the base_score in the model file."""
import pickle
import json
import tempfile
from pathlib import Path

MODEL_PATH = Path(__file__).parent.parent / "models" / "v4.2.0" / "model.pkl"
BACKUP_PATH = Path(__file__).parent.parent / "models" / "v4.2.0" / "model_backup.pkl"

print("Loading model...")
with open(MODEL_PATH, 'rb') as f:
    model = pickle.load(f)

# Backup
print("Creating backup...")
with open(BACKUP_PATH, 'wb') as f:
    pickle.dump(model, f)

booster = model.get_booster()

# Save to JSON
print("Saving to JSON...")
json_path = MODEL_PATH.with_suffix('.json')
booster.save_model(str(json_path))

# Fix in JSON
print("Fixing base_score in JSON...")
with open(json_path, 'r') as f:
    json_data = json.load(f)

# Navigate to base_score
if 'learner' in json_data and 'learner_model_param' in json_data['learner']:
    lmp = json_data['learner']['learner_model_param']
    if 'base_score' in lmp:
        bs = lmp['base_score']
        print(f"  Found base_score: {bs}")
        if isinstance(bs, str) and '[' in bs:
            clean = bs.replace('[', '').replace(']', '').strip()
            parsed = float(clean)
            lmp['base_score'] = str(parsed)
            print(f"  Fixed to: {parsed}")
            
            # Save fixed JSON
            with open(json_path, 'w') as f:
                json.dump(json_data, f)
            
            # Reload from JSON
            print("Reloading from fixed JSON...")
            booster.load_model(str(json_path))
            
            # Verify
            config_str = booster.save_config()
            config = json.loads(config_str)
            lmp2 = config['learner']['learner_model_param']
            print(f"  Verified base_score: {lmp2.get('base_score')}")
            
            # Save fixed model
            print("Saving fixed model...")
            with open(MODEL_PATH, 'wb') as f:
                pickle.dump(model, f)
            
            print("Model fixed successfully!")
        else:
            print(f"  base_score is already correct: {bs}")
    else:
        print("  base_score not found in config")
else:
    print("  Could not find learner_model_param in JSON")
