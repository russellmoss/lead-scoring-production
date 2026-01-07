"""Debug the base_score issue."""
import pickle
from pathlib import Path

MODEL_PATH = Path(__file__).parent.parent / "models" / "v4.2.0" / "model.pkl"

with open(MODEL_PATH, 'rb') as f:
    model = pickle.load(f)

booster = model.get_booster()

# Check attributes
print("Booster attributes:")
attrs = booster.attributes()
for key, value in attrs.items():
    print(f"  {key}: {value} (type: {type(value)})")

# Check model base_score
print(f"\nModel base_score: {model.base_score} (type: {type(model.base_score)})")

# Try to fix it
print("\nAttempting to fix...")
try:
    if 'base_score' in attrs:
        bs = attrs['base_score']
        print(f"  Current base_score in attrs: {bs}")
        if isinstance(bs, str):
            # Parse
            clean = bs.replace('[', '').replace(']', '')
            parsed = float(clean)
            print(f"  Parsed value: {parsed}")
            booster.set_attr(base_score=str(parsed))
            print(f"  Set to: {parsed}")
            
            # Verify
            new_attrs = booster.attributes()
            print(f"  New base_score: {new_attrs.get('base_score')}")
except Exception as e:
    print(f"  Error: {e}")
    import traceback
    traceback.print_exc()
