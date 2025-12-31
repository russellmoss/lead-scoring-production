"""Calculate MD5 checksums for model files."""
import hashlib
from pathlib import Path

files = [
    'v4/models/v4.1.0_r3/model.pkl',
    'v4/models/v4.1.0_r3/model.json',
    'v4/models/v4.1.0_r3/hyperparameters.json',
    'v4/data/v4.1.0_r3/final_features.json'
]

for f in files:
    path = Path(f)
    if path.exists():
        md5 = hashlib.md5(path.read_bytes()).hexdigest()
        print(f"{f}: {md5}")
    else:
        print(f"{f}: NOT FOUND")

