"""
Regenerate V4.2.0 Feature Importance with Actual Values

Uses native XGBoost get_score() to get gain-based importance.
Model uses feature names directly, not f0, f1, etc.
"""

import pandas as pd
import pickle
from pathlib import Path

# Paths
MODEL_PATH = Path(__file__).parent.parent / "models" / "v4.2.0" / "model.pkl"
OUTPUT_DIR = Path(__file__).parent.parent / "models" / "v4.2.0"
REPORTS_DIR = Path(__file__).parent.parent / "reports" / "v4.2"

def main():
    print("=" * 70)
    print("V4.2.0 Feature Importance Regeneration")
    print("=" * 70)
    
    # Load model
    if not MODEL_PATH.exists():
        raise FileNotFoundError(f"Model file not found: {MODEL_PATH}")
    
    print(f"\n[1/3] Loading model from {MODEL_PATH}...")
    with open(MODEL_PATH, 'rb') as f:
        model = pickle.load(f)
    
    # Get native XGBoost importance
    print("\n[2/3] Extracting feature importance (gain-based)...")
    booster = model.get_booster()
    importance_gain = booster.get_score(importance_type='gain')
    
    print(f"  Found {len(importance_gain)} features in model")
    
    # Convert to DataFrame (model uses feature names directly)
    importance_data = []
    for feat_name, gain_value in importance_gain.items():
        importance_data.append({
            'feature': feat_name,
            'gain': gain_value
        })
    
    importance_df = pd.DataFrame(importance_data)
    
    # Calculate percentages
    total_gain = importance_df['gain'].sum()
    if total_gain > 0:
        importance_df['gain_pct'] = (importance_df['gain'] / total_gain * 100).round(2)
    else:
        importance_df['gain_pct'] = 0.0
    
    # Sort and rank
    importance_df = importance_df.sort_values('gain', ascending=False).reset_index(drop=True)
    importance_df['rank'] = range(1, len(importance_df) + 1)
    
    # Reorder columns
    importance_df = importance_df[['rank', 'feature', 'gain', 'gain_pct']]
    
    # Save
    print("\n[3/3] Saving feature importance...")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    
    output_path = OUTPUT_DIR / "feature_importance.csv"
    reports_path = REPORTS_DIR / "feature_importance_corrected.csv"
    
    importance_df.to_csv(output_path, index=False)
    importance_df.to_csv(reports_path, index=False)
    
    print(f"\nSaved to: {output_path}")
    print(f"Saved to: {reports_path}")
    
    # Display results
    print("\n" + "=" * 70)
    print("Global Feature Importance (Gain-based):")
    print("=" * 70)
    print(importance_df.to_string(index=False))
    
    # Check age specifically
    age_row = importance_df[importance_df['feature'] == 'age_bucket_encoded']
    if len(age_row) > 0:
        age_row = age_row.iloc[0]
        print(f"\nAge Feature: Rank #{int(age_row['rank'])}, Gain: {age_row['gain']:.2f} ({age_row['gain_pct']}%)")
    else:
        print("\nWARNING: Age feature not found in importance data")
    
    print("\n" + "=" * 70)
    print("Feature importance regeneration complete!")
    print("=" * 70)

if __name__ == "__main__":
    main()
