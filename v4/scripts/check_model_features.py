"""Check what features are actually in the V4.2.0 model."""
import pickle
from pathlib import Path

MODEL_PATH = Path(__file__).parent.parent / "models" / "v4.2.0" / "model.pkl"

with open(MODEL_PATH, 'rb') as f:
    model = pickle.load(f)

booster = model.get_booster()
importance = booster.get_score(importance_type='gain')

print(f"Model has {len(importance)} features")
print("\nFeature keys in model:")
for key in sorted(importance.keys()):
    print(f"  {key}: {importance[key]}")
