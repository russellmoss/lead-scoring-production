"""
V4.1.0 Complete Scoring and Salesforce Sync Workflow

This script:
1. Fetches features from v4_daily_scores_v41
2. Scores leads using V4.1.0 model
3. Calculates percentiles and deprioritize flags
4. Syncs scores to Salesforce

REQUIREMENTS:
- Google Cloud credentials for BigQuery
- Salesforce credentials (optional - for actual sync)
- simple-salesforce package (optional - for actual sync)

USAGE:
    python v4/scripts/v4.1/score_and_sync_v41.py [--dry-run] [--limit N]
"""

import sys
from pathlib import Path
from datetime import datetime
import pandas as pd
from google.cloud import bigquery
import argparse

# Add project to path
WORKING_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(WORKING_DIR))

# Import V4.1.0 scorer
import importlib.util
spec = importlib.util.spec_from_file_location("lead_scorer_v4", WORKING_DIR / "inference" / "lead_scorer_v4.py")
lead_scorer_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lead_scorer_module)
LeadScorerV4 = lead_scorer_module.LeadScorerV4

# ============================================================================
# CONFIGURATION
# ============================================================================
PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
FEATURES_TABLE = "v4_daily_scores_v41"  # V4.1.0 table
SCORES_OUTPUT_TABLE = "v4_lead_scores_v41"  # Output table for scores

DEPRIORITIZE_PERCENTILE = 20

# Salesforce field mappings
SALESFORCE_FIELDS = {
    'V4_Score__c': 'v4_score',
    'V4_Score_Percentile__c': 'v4_percentile',
    'V4_Deprioritize__c': 'v4_deprioritize',
    'V4_Model_Version__c': 'model_version',
    'V4_Scored_At__c': 'scored_at'
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def fetch_features(client, limit=None):
    """Fetch features from v4_production_features_v41 (view with all features)."""
    print("\n[FETCH] Fetching features from BigQuery...")
    
    # Query the view which has all features including numeric versions
    query = f"""
    SELECT 
        pf.lead_id,
        pf.advisor_crd,
        pf.prediction_date,
        -- Numeric features (required by model)
        pf.tenure_months,
        pf.experience_years,
        pf.mobility_3yr,
        pf.firm_rep_count_at_contact,
        pf.firm_net_change_12mo,
        -- Categorical features (will be encoded)
        pf.tenure_bucket,
        pf.experience_bucket,
        pf.is_experience_missing,
        pf.mobility_tier,
        pf.firm_stability_tier,
        -- Binary features
        pf.has_firm_data,
        pf.is_wirehouse,
        pf.is_broker_protocol,
        pf.has_email,
        pf.has_linkedin,
        pf.mobility_x_heavy_bleeding,
        pf.short_tenure_x_high_mobility,
        -- V4.1.0 new features
        pf.is_recent_mover,
        pf.days_since_last_move,
        pf.firm_departures_corrected,
        pf.bleeding_velocity_encoded,
        pf.is_independent_ria,
        pf.is_ia_rep_type,
        pf.is_dual_registered
    FROM `{PROJECT_ID}.{DATASET}.v4_production_features_v41` pf
    WHERE pf.lead_id IN (
          SELECT Id 
          FROM `{PROJECT_ID}.SavvyGTMData.Lead`
          WHERE Stage_Entered_Call_Scheduled__c IS NULL
            AND stage_entered_contacting__c IS NOT NULL
      )
    ORDER BY pf.feature_extraction_timestamp DESC
    """
    
    if limit:
        query += f" LIMIT {limit}"
    
    try:
        df = client.query(query).to_dataframe()
        print(f"  [OK] Fetched {len(df):,} leads with features")
        return df
    except Exception as e:
        print(f"  [ERROR] Error fetching features: {e}")
        import traceback
        traceback.print_exc()
        return pd.DataFrame()


def prepare_features_for_scoring(df_features):
    """Prepare features for scoring by encoding categoricals."""
    df = df_features.copy()
    
    # Encode categorical features (matching training)
    categorical_mappings = {
        'tenure_bucket': {'0-12': 0, '12-24': 1, '24-48': 2, '48-120': 3, '120+': 4, 'Unknown': 5},
        'mobility_tier': {'Stable': 0, 'Low_Mobility': 1, 'High_Mobility': 2},
        'firm_stability_tier': {'Unknown': 0, 'Heavy_Bleeding': 1, 'Light_Bleeding': 2, 'Stable': 3, 'Growing': 4}
    }
    
    # Create encoded versions
    if 'tenure_bucket' in df.columns:
        df['tenure_bucket_encoded'] = df['tenure_bucket'].map(categorical_mappings['tenure_bucket']).fillna(0).astype(int)
    if 'mobility_tier' in df.columns:
        df['mobility_tier_encoded'] = df['mobility_tier'].map(categorical_mappings['mobility_tier']).fillna(0).astype(int)
    if 'firm_stability_tier' in df.columns:
        df['firm_stability_tier_encoded'] = df['firm_stability_tier'].map(categorical_mappings['firm_stability_tier']).fillna(0).astype(int)
    
    # Fill missing numeric values
    numeric_cols = ['tenure_months', 'experience_years', 'mobility_3yr', 'firm_rep_count_at_contact', 
                    'firm_net_change_12mo', 'days_since_last_move', 'firm_departures_corrected']
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0)
    
    # Fill missing binary values
    binary_cols = ['is_experience_missing', 'has_firm_data', 'is_wirehouse', 'is_broker_protocol',
                   'has_email', 'has_linkedin', 'mobility_x_heavy_bleeding', 'short_tenure_x_high_mobility',
                   'is_recent_mover', 'bleeding_velocity_encoded', 'is_independent_ria', 'is_ia_rep_type',
                   'is_dual_registered']
    for col in binary_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0).astype(int)
    
    return df


def score_leads(scorer, df_features):
    """Score leads using V4.1.0 model."""
    print("\n[SCORE] Scoring leads with V4.1.0 model...")
    
    if len(df_features) == 0:
        print("  [WARNING] No leads to score")
        return pd.DataFrame()
    
    try:
        # Prepare features (encode categoricals)
        df_prepared = prepare_features_for_scoring(df_features)
        
        # Score leads
        scores = scorer.score_leads(df_prepared)
        print(f"  [OK] Scored {len(scores):,} leads")
        print(f"  Score range: {scores.min():.4f} - {scores.max():.4f}")
        print(f"  Score mean: {scores.mean():.4f}")
        
        # Calculate percentiles
        percentiles = scorer.get_percentiles(scores)
        print(f"  [OK] Calculated percentiles")
        print(f"  Percentile range: {percentiles.min()} - {percentiles.max()}")
        
        # Calculate deprioritize flags
        deprioritize = scorer.get_deprioritize_flags(percentiles, threshold=DEPRIORITIZE_PERCENTILE)
        deprioritize_count = deprioritize.sum()
        print(f"  [OK] Calculated deprioritize flags")
        print(f"  Deprioritized leads: {deprioritize_count:,} ({deprioritize_count/len(deprioritize)*100:.1f}%)")
        
        # Combine results
        df_results = df_features[['lead_id', 'advisor_crd']].copy()
        df_results['v4_score'] = scores
        df_results['v4_percentile'] = percentiles
        df_results['v4_deprioritize'] = deprioritize
        df_results['model_version'] = 'v4.1.0'
        df_results['scored_at'] = datetime.now()
        
        return df_results
        
    except Exception as e:
        print(f"  [ERROR] Error scoring leads: {e}")
        import traceback
        traceback.print_exc()
        return pd.DataFrame()


def save_scores_to_bigquery(client, df_scores):
    """Save scores to BigQuery."""
    print("\n[SAVE] Saving scores to BigQuery...")
    
    if len(df_scores) == 0:
        print("  [WARNING] No scores to save")
        return
    
    table_id = f"{PROJECT_ID}.{DATASET}.{SCORES_OUTPUT_TABLE}"
    
    # Configure job
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        schema=[
            bigquery.SchemaField("lead_id", "STRING"),
            bigquery.SchemaField("advisor_crd", "INTEGER"),
            bigquery.SchemaField("v4_score", "FLOAT64"),
            bigquery.SchemaField("v4_percentile", "INTEGER"),
            bigquery.SchemaField("v4_deprioritize", "BOOLEAN"),
            bigquery.SchemaField("model_version", "STRING"),
            bigquery.SchemaField("scored_at", "TIMESTAMP"),
        ]
    )
    
    try:
        job = client.load_table_from_dataframe(df_scores, table_id, job_config=job_config)
        job.result()
        print(f"  [OK] Saved {len(df_scores):,} scores to {table_id}")
        return True
    except Exception as e:
        print(f"  [ERROR] Error saving scores: {e}")
        import traceback
        traceback.print_exc()
        return False


def prepare_salesforce_payload(df_scores):
    """Prepare DataFrame for Salesforce update."""
    print("\n[PREPARE] Preparing Salesforce payload...")
    
    if len(df_scores) == 0:
        print("  [WARNING] No scores to sync")
        return pd.DataFrame()
    
    payload = pd.DataFrame()
    payload['Id'] = df_scores['lead_id']
    payload['V4_Score__c'] = df_scores['v4_score']
    payload['V4_Score_Percentile__c'] = df_scores['v4_percentile']
    payload['V4_Deprioritize__c'] = df_scores['v4_deprioritize']
    payload['V4_Model_Version__c'] = 'v4.1.0'
    payload['V4_Scored_At__c'] = pd.to_datetime(df_scores['scored_at'])
    
    print(f"  [OK] Prepared {len(payload):,} records for Salesforce")
    return payload


def sync_to_salesforce(payload, dry_run=True):
    """Sync scores to Salesforce."""
    if len(payload) == 0:
        print("\n[SYNC] No records to sync")
        return
    
    print(f"\n[SYNC] {'DRY RUN: ' if dry_run else ''}Syncing to Salesforce...")
    
    # Try to import simple-salesforce
    try:
        from simple_salesforce import Salesforce
    except ImportError:
        print("  [WARNING] simple-salesforce not installed")
        print("  [WARNING] Install with: pip install simple-salesforce")
        print("  [WARNING] For now, skipping Salesforce sync")
        print(f"  [DRY RUN] Would sync {len(payload):,} records")
        return
    
    if dry_run:
        print(f"  [DRY RUN] Would update {len(payload):,} Lead records")
        print(f"  Sample records:")
        print(payload.head(5).to_string())
        return
    
    # Check for credentials
    import os
    sf_username = os.getenv('SALESFORCE_USERNAME')
    sf_password = os.getenv('SALESFORCE_PASSWORD')
    sf_token = os.getenv('SALESFORCE_SECURITY_TOKEN')
    
    if not all([sf_username, sf_password, sf_token]):
        print("  [WARNING] Salesforce credentials not found")
        print("  [WARNING] Set: SALESFORCE_USERNAME, SALESFORCE_PASSWORD, SALESFORCE_SECURITY_TOKEN")
        print(f"  [DRY RUN] Would sync {len(payload):,} records")
        return
    
    # Connect and sync
    try:
        sf = Salesforce(
            username=sf_username,
            password=sf_password,
            security_token=sf_token
        )
        
        # Convert to records
        records = payload.to_dict('records')
        records = [{k: v for k, v in record.items() if pd.notna(v)} for record in records]
        
        # Bulk update
        batch_size = 200
        total_updated = 0
        
        for i in range(0, len(records), batch_size):
            batch = records[i:i+batch_size]
            result = sf.bulk.Lead.update(batch)
            
            errors = [r for r in result if not r['success']]
            if errors:
                print(f"  [WARNING] {len(errors)} errors in batch {i//batch_size + 1}")
            else:
                total_updated += len(batch)
                print(f"  [OK] Updated batch {i//batch_size + 1}: {len(batch)} records")
        
        print(f"  [OK] Successfully updated {total_updated:,} Lead records")
        
    except Exception as e:
        print(f"  [ERROR] Error syncing to Salesforce: {e}")
        import traceback
        traceback.print_exc()


def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(description='V4.1.0 Scoring and Salesforce Sync')
    parser.add_argument('--dry-run', action='store_true', help='Dry run mode (no Salesforce updates)')
    parser.add_argument('--limit', type=int, help='Limit number of leads to process (for testing)')
    parser.add_argument('--no-salesforce', action='store_true', help='Skip Salesforce sync')
    args = parser.parse_args()
    
    print("=" * 70)
    print("V4.1.0 SCORING AND SALESFORCE SYNC")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)
    
    # Initialize
    print("\n[INIT] Initializing...")
    try:
        bq_client = bigquery.Client(project=PROJECT_ID)
        scorer = LeadScorerV4()
        print("  [OK] BigQuery client initialized")
        print("  [OK] V4.1.0 scorer loaded")
    except Exception as e:
        print(f"  [ERROR] Error initializing: {e}")
        import traceback
        traceback.print_exc()
        return
    
    # Step 1: Fetch features
    df_features = fetch_features(bq_client, limit=args.limit)
    
    if len(df_features) == 0:
        print("\n[WARNING] No leads found to score")
        return
    
    # Step 2: Score leads
    df_scores = score_leads(scorer, df_features)
    
    if len(df_scores) == 0:
        print("\n[WARNING] No scores generated")
        return
    
    # Step 3: Save scores to BigQuery
    save_success = save_scores_to_bigquery(bq_client, df_scores)
    
    # Step 4: Sync to Salesforce (if not skipped)
    if not args.no_salesforce:
        payload = prepare_salesforce_payload(df_scores)
        sync_to_salesforce(payload, dry_run=args.dry_run)
    else:
        print("\n[SYNC] Salesforce sync skipped (--no-salesforce flag)")
    
    print("\n" + "=" * 70)
    print("WORKFLOW COMPLETE")
    print("=" * 70)
    print(f"\nSummary:")
    print(f"  - Leads scored: {len(df_scores):,}")
    print(f"  - Scores saved to BigQuery: {'Yes' if save_success else 'No'}")
    print(f"  - Salesforce sync: {'Dry run' if args.dry_run else 'Completed' if not args.no_salesforce else 'Skipped'}")


if __name__ == "__main__":
    main()

