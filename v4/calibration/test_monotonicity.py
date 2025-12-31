"""Test isotonic calibrator monotonicity."""
import pickle
import numpy as np
from pathlib import Path

MODEL_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4\models\v4.1.0_r3")

# Load calibrator
with open(MODEL_DIR / "isotonic_calibrator.pkl", 'rb') as f:
    calibrator = pickle.load(f)

# Test monotonicity
test_inputs = np.array([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9])
test_outputs = calibrator.transform(test_inputs)

print("Input  -> Output")
for i, o in zip(test_inputs, test_outputs):
    print(f"{i:.2f}   -> {o:.4f}")

# Verify monotonic
is_monotonic = all(test_outputs[i] <= test_outputs[i+1] for i in range(len(test_outputs)-1))
print(f"\nMonotonic: {is_monotonic}")
assert is_monotonic, "FAILED: Calibrator is not monotonic!"
print("[OK] Monotonicity test PASSED")

