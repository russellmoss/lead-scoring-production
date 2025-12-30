"""Verify that split files contain all final features."""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")))

import json
import pandas as pd

# Load final features
with open('data/processed/final_features.json', 'r') as f:
    final_data = json.load(f)
    final_features = final_data['final_features']

# Load train data
train = pd.read_csv('data/splits/train.csv')

# Metadata columns to exclude
metadata_cols = [
    'lead_id', 'advisor_crd', 'contacted_date', 'target', 
    'lead_source_grouped', 'firm_crd', 'firm_name', 
    'split', 'cv_fold', 'feature_extraction_timestamp'
]

# Get feature columns from train
train_features = [c for c in train.columns if c not in metadata_cols]

print("=" * 70)
print("FINAL FEATURES VERIFICATION")
print("=" * 70)
print(f"\nFinal features (from JSON): {len(final_features)}")
print(f"Train features (from CSV): {len(train_features)}")

print(f"\nFinal features list:")
for f in sorted(final_features):
    print(f"  - {f}")

# Check for missing/extra
missing = set(final_features) - set(train_features)
extra = set(train_features) - set(final_features)

print(f"\n" + "=" * 70)
if missing:
    print(f"[WARNING] MISSING from train: {missing}")
else:
    print("[OK] All final features present in train data")

if extra:
    print(f"[INFO] Extra in train (will be ignored in Phase 6): {len(extra)} features")
    print(f"   {sorted(list(extra))[:5]}{'...' if len(extra) > 5 else ''}")
else:
    print("[OK] No extra features (perfect match)")

print("=" * 70)

