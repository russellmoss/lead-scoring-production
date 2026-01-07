"""Fix the base_score in the V4.2.0 model to work with SHAP."""
import pickle
from pathlib import Path

MODEL_PATH = Path(__file__).parent.parent / "models" / "v4.2.0" / "model.pkl"
BACKUP_PATH = Path(__file__).parent.parent / "models" / "v4.2.0" / "model_backup.pkl"

# Load model
print("Loading model...")
with open(MODEL_PATH, 'rb') as f:
    model = pickle.load(f)

# Backup
print("Creating backup...")
with open(BACKUP_PATH, 'wb') as f:
    pickle.dump(model, f)

# Fix base_score in booster
booster = model.get_booster()
try:
    # Get current base_score
    params = booster.attributes
    print(f"Current base_score attribute: {params.get('base_score', 'not found')}")
    
    # Set base_score to float 0.5
    booster.set_attr(base_score='0.5')
    print("Set base_score to 0.5")
    
    # Save fixed model
    print("Saving fixed model...")
    with open(MODEL_PATH, 'wb') as f:
        pickle.dump(model, f)
    
    print("Model fixed successfully!")
except Exception as e:
    print(f"Error fixing model: {e}")
