"""
Phase 3: Data Export & Preparation
Export feature data from BigQuery to local files for model training.
"""

import pandas as pd
from google.cloud import bigquery
from pathlib import Path
import json
from datetime import datetime

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
TABLE = "v4_features_pit_v41"
BASE_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
DATA_DIR = BASE_DIR / "data" / "v4.1.0"
DATA_DIR.mkdir(parents=True, exist_ok=True)

# V4.1 Features (23 total)
FEATURES_V41 = [
    # Original V4 features (14)
    'tenure_months',
    'tenure_bucket',
    'is_tenure_missing',
    'industry_tenure_months',
    'experience_years',
    'experience_bucket',
    'is_experience_missing',
    'mobility_3yr',
    'mobility_tier',
    'firm_net_change_12mo',
    'firm_stability_tier',
    'is_wirehouse',
    'is_broker_protocol',
    'has_firm_data',
    
    # V4.1 Bleeding Signal Features (5)
    'is_recent_mover',
    'days_since_last_move',
    'firm_departures_corrected',
    'bleeding_velocity_encoded',
    'recent_mover_x_bleeding',
    
    # V4.1 Firm/Rep Type Features (4)
    'is_independent_ria',
    'is_ia_rep_type',
    'is_dual_registered',
    'independent_ria_x_ia_rep',
]


def export_data():
    """Export feature data from BigQuery to local files."""
    print("=" * 80)
    print("Phase 3: Data Export & Preparation")
    print("=" * 80)
    
    # Initialize BigQuery client
    client = bigquery.Client(project=PROJECT_ID)
    
    # Query to export all feature data
    query = f"""
    SELECT 
        lead_id,
        advisor_crd,
        contacted_date,
        target,
        tenure_months,
        tenure_bucket,
        is_tenure_missing,
        industry_tenure_months,
        experience_years,
        experience_bucket,
        is_experience_missing,
        mobility_3yr,
        mobility_tier,
        firm_rep_count_at_contact,
        firm_rep_count_12mo_ago,
        firm_departures_12mo,
        firm_arrivals_12mo,
        firm_net_change_12mo,
        firm_stability_tier,
        has_firm_data,
        is_wirehouse,
        is_broker_protocol,
        has_email,
        has_linkedin,
        has_fintrx_match,
        has_employment_history,
        is_linkedin_sourced,
        is_provided_list,
        mobility_x_heavy_bleeding,
        short_tenure_x_high_mobility,
        tenure_bucket_x_mobility,
        is_recent_mover,
        days_since_last_move,
        firm_departures_corrected,
        bleeding_velocity_encoded,
        recent_mover_x_bleeding,
        is_independent_ria,
        is_ia_rep_type,
        is_dual_registered,
        independent_ria_x_ia_rep
    FROM `{PROJECT_ID}.{DATASET}.{TABLE}`
    WHERE target IS NOT NULL
    ORDER BY contacted_date
    """
    
    print(f"\n[1/4] Querying BigQuery table: {DATASET}.{TABLE}")
    print(f"      Project: {PROJECT_ID}")
    
    # Execute query and download to DataFrame
    print("\n[2/4] Downloading data from BigQuery...")
    df = client.query(query).to_dataframe()
    
    print(f"      Downloaded {len(df):,} rows, {len(df.columns)} columns")
    print(f"      Date range: {df['contacted_date'].min()} to {df['contacted_date'].max()}")
    print(f"      Conversion rate: {df['target'].mean()*100:.2f}%")
    
    # Validate feature columns
    print("\n[3/4] Validating features...")
    missing_features = [f for f in FEATURES_V41 if f not in df.columns]
    if missing_features:
        print(f"      WARNING: Missing features: {missing_features}")
    else:
        print(f"      OK: All {len(FEATURES_V41)} V4.1 features present")
    
    # Check for NULL values in features
    null_counts = df[FEATURES_V41].isnull().sum()
    null_features = null_counts[null_counts > 0]
    if len(null_features) > 0:
        print(f"      WARNING: NULL values found in:")
        for feat, count in null_features.items():
            print(f"         - {feat}: {count:,} NULLs ({count/len(df)*100:.2f}%)")
    else:
        print(f"      OK: No NULL values in features")
    
    # Save to Parquet (recommended for large datasets)
    parquet_path = DATA_DIR / "v4_features_v41.parquet"
    print(f"\n[4/4] Saving data to {parquet_path}...")
    df.to_parquet(parquet_path, index=False, engine='pyarrow')
    print(f"      OK: Saved {parquet_path.stat().st_size / 1024 / 1024:.2f} MB")
    
    # Also save to CSV for easy inspection (smaller sample)
    csv_path = DATA_DIR / "v4_features_v41_sample.csv"
    print(f"      Saving sample to {csv_path}...")
    df.head(1000).to_csv(csv_path, index=False)
    print(f"      OK: Saved sample (1,000 rows)")
    
    # Save feature list
    features_path = DATA_DIR / "features_v41.json"
    with open(features_path, 'w') as f:
        json.dump({
            'features': FEATURES_V41,
            'total_count': len(FEATURES_V41),
            'export_date': datetime.now().isoformat(),
            'row_count': len(df),
            'columns': list(df.columns)
        }, f, indent=2)
    print(f"      OK: Saved feature list to {features_path}")
    
    # Generate summary statistics
    summary = {
        'export_date': datetime.now().isoformat(),
        'total_rows': len(df),
        'total_features': len(FEATURES_V41),
        'date_range': {
            'min': str(df['contacted_date'].min()),
            'max': str(df['contacted_date'].max())
        },
        'target_stats': {
            'positive_count': int(df['target'].sum()),
            'negative_count': int((df['target'] == 0).sum()),
            'conversion_rate': float(df['target'].mean())
        },
        'feature_stats': {}
    }
    
    # Add feature statistics
    for feat in FEATURES_V41:
        if feat in df.columns:
            summary['feature_stats'][feat] = {
                'null_count': int(df[feat].isnull().sum()),
                'null_pct': float(df[feat].isnull().mean() * 100),
                'mean': float(df[feat].mean()) if df[feat].dtype in ['int64', 'float64'] else None,
                'std': float(df[feat].std()) if df[feat].dtype in ['int64', 'float64'] else None
            }
    
    summary_path = DATA_DIR / "export_summary.json"
    with open(summary_path, 'w') as f:
        json.dump(summary, f, indent=2)
    print(f"      OK: Saved summary to {summary_path}")
    
    print("\n" + "=" * 80)
    print("Phase 3 Complete!")
    print("=" * 80)
    print(f"\nData exported to: {DATA_DIR}")
    print(f"  - Full dataset: v4_features_v41.parquet ({len(df):,} rows)")
    print(f"  - Sample: v4_features_v41_sample.csv (1,000 rows)")
    print(f"  - Feature list: features_v41.json")
    print(f"  - Summary: export_summary.json")
    
    return df, summary


if __name__ == "__main__":
    try:
        df, summary = export_data()
        print(f"\nSUCCESS: Successfully exported {len(df):,} rows")
    except Exception as e:
        print(f"\nERROR: Error during export: {e}")
        raise

