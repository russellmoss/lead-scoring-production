"""Verify SHAP diversity in exported lead list."""
import pandas as pd
from pathlib import Path

csv_path = Path(r"C:\Users\russe\Documents\lead_scoring_production\pipeline\exports\january_2026_lead_list_20251226.csv")

print(f"Reading {csv_path}...")
df = pd.read_csv(csv_path)

print(f"\nTotal leads: {len(df):,}")
print(f"Unique SHAP top-1 features: {df['shap_top1_feature'].nunique()}")
print(f"Unique SHAP top-2 features: {df['shap_top2_feature'].nunique()}")
print(f"Unique SHAP top-3 features: {df['shap_top3_feature'].nunique()}")

print(f"\nTop 10 SHAP Top-1 Features:")
top1_dist = df['shap_top1_feature'].value_counts().head(10)
for feat, count in top1_dist.items():
    pct = (count / len(df)) * 100
    print(f"  {feat}: {count:,} ({pct:.1f}%)")

print(f"\nDiversity Status: {'GOOD - Bug Fixed!' if df['shap_top1_feature'].nunique() >= 10 else 'POOR - Still has bug'}")

