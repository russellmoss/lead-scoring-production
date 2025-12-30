"""
V4.1.0 Salesforce Sync Script

Syncs V4.1.0 lead scores from BigQuery to Salesforce Lead records.

REQUIREMENTS:
- Salesforce credentials (username, password, security_token) or OAuth
- simple-salesforce package: pip install simple-salesforce
- Google Cloud credentials for BigQuery access

USAGE:
    python v4/scripts/v4.1/salesforce_sync_v41.py

SALESFORCE FIELDS (must exist in Salesforce):
- V4_Score__c (Number, 18, 2) - Raw prediction (0-1)
- V4_Score_Percentile__c (Number, 18, 0) - Percentile rank (1-100)
- V4_Deprioritize__c (Checkbox) - TRUE if bottom 20% (percentile <= 20)
- V4_Model_Version__c (Text, 50) - Model version ('v4.1.0')
- V4_Scored_At__c (DateTime) - Timestamp of scoring
"""

import sys
from pathlib import Path
from datetime import datetime
import pandas as pd
from google.cloud import bigquery
import json

# Add project to path
WORKING_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(WORKING_DIR))

# Try to import simple-salesforce (optional - only needed if actually syncing)
try:
    from simple_salesforce import Salesforce
    SALESFORCE_AVAILABLE = True
except ImportError:
    SALESFORCE_AVAILABLE = False
    print("[WARNING] simple-salesforce not installed. Install with: pip install simple-salesforce")

# ============================================================================
# CONFIGURATION
# ============================================================================
PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
SCORES_TABLE = "v4_daily_scores_v41"  # V4.1.0 table

# Salesforce field mappings
SALESFORCE_FIELDS = {
    'V4_Score__c': 'v4_score',  # Number (18, 2)
    'V4_Score_Percentile__c': 'v4_percentile',  # Number (18, 0)
    'V4_Deprioritize__c': 'v4_deprioritize',  # Checkbox
    'V4_Model_Version__c': 'model_version',  # Text (50)
    'V4_Scored_At__c': 'scored_at'  # DateTime
}

# Thresholds
DEPRIORITIZE_PERCENTILE = 20

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def verify_salesforce_fields(sf):
    """
    Verify that required Salesforce fields exist.
    
    Returns:
        dict: Field verification results
    """
    print("\n[VERIFY] Checking Salesforce fields...")
    
    required_fields = list(SALESFORCE_FIELDS.keys())
    results = {}
    
    try:
        # Get Lead object description
        lead_desc = sf.Lead.describe()
        existing_fields = {field['name'] for field in lead_desc['fields']}
        
        for sf_field in required_fields:
            exists = sf_field in existing_fields
            results[sf_field] = exists
            status = "EXISTS" if exists else "MISSING"
            print(f"  {sf_field}: {status}")
            
            if not exists:
                print(f"    ⚠️  Field must be created in Salesforce:")
                print(f"       - Object: Lead")
                print(f"       - Field Name: {sf_field}")
                if sf_field == 'V4_Score__c':
                    print(f"       - Type: Number (18, 2)")
                elif sf_field == 'V4_Score_Percentile__c':
                    print(f"       - Type: Number (18, 0)")
                elif sf_field == 'V4_Deprioritize__c':
                    print(f"       - Type: Checkbox")
                elif sf_field == 'V4_Model_Version__c':
                    print(f"       - Type: Text (50)")
                elif sf_field == 'V4_Scored_At__c':
                    print(f"       - Type: DateTime")
        
        all_exist = all(results.values())
        if all_exist:
            print("  ✅ All required fields exist in Salesforce")
        else:
            missing = [f for f, exists in results.items() if not exists]
            print(f"  ❌ Missing fields: {', '.join(missing)}")
            print("  ⚠️  Create these fields before running sync")
        
        return results
        
    except Exception as e:
        print(f"  ❌ Error checking fields: {e}")
        return {field: False for field in required_fields}


def fetch_scores_from_bigquery(client, limit=None):
    """
    Fetch scores from BigQuery v4_daily_scores_v41 table.
    
    Note: This assumes scores have been calculated and stored.
    If scores are not yet calculated, use lead_scorer_v4.py first.
    """
    print("\n[FETCH] Fetching scores from BigQuery...")
    
    query = f"""
    SELECT 
        ds.lead_id,
        ds.advisor_crd,
        ds.model_version,
        ds.scored_at,
        -- Note: Scores need to be calculated first using lead_scorer_v4.py
        -- For now, this query structure is ready for when scores are added
        CURRENT_TIMESTAMP() as sync_timestamp
    FROM `{PROJECT_ID}.{DATASET}.{SCORES_TABLE}` ds
    WHERE ds.model_version = 'v4.1.0'
      -- Only sync leads that are still in "Contacting" stage
      AND ds.lead_id IN (
          SELECT Id 
          FROM `{PROJECT_ID}.SavvyGTMData.Lead`
          WHERE Stage_Entered_Call_Scheduled__c IS NULL
            AND stage_entered_contacting__c IS NOT NULL
      )
    ORDER BY ds.scored_at DESC
    """
    
    if limit:
        query += f" LIMIT {limit}"
    
    try:
        df = client.query(query).to_dataframe()
        print(f"  ✅ Fetched {len(df):,} leads from BigQuery")
        return df
    except Exception as e:
        print(f"  ❌ Error fetching scores: {e}")
        return pd.DataFrame()


def prepare_salesforce_payload(df):
    """
    Prepare DataFrame for Salesforce update.
    
    Note: This assumes scores are in the DataFrame.
    If scores are not yet calculated, this will need to be updated.
    """
    print("\n[PREPARE] Preparing Salesforce payload...")
    
    if len(df) == 0:
        print("  ⚠️  No leads to sync")
        return pd.DataFrame()
    
    # Map fields for Salesforce
    payload = pd.DataFrame()
    payload['Id'] = df['lead_id']
    
    # Note: These fields need to be populated after scores are calculated
    # For now, using placeholders
    if 'v4_score' in df.columns:
        payload['V4_Score__c'] = df['v4_score']
    else:
        print("  ⚠️  v4_score not found - scores need to be calculated first")
        payload['V4_Score__c'] = None
    
    if 'v4_percentile' in df.columns:
        payload['V4_Score_Percentile__c'] = df['v4_percentile']
        payload['V4_Deprioritize__c'] = df['v4_percentile'] <= DEPRIORITIZE_PERCENTILE
    else:
        print("  ⚠️  v4_percentile not found - percentiles need to be calculated first")
        payload['V4_Score_Percentile__c'] = None
        payload['V4_Deprioritize__c'] = False
    
    payload['V4_Model_Version__c'] = 'v4.1.0'
    
    if 'scored_at' in df.columns:
        payload['V4_Scored_At__c'] = pd.to_datetime(df['scored_at'])
    else:
        payload['V4_Scored_At__c'] = datetime.now()
    
    print(f"  ✅ Prepared {len(payload):,} records for Salesforce sync")
    return payload


def sync_to_salesforce(sf, payload, dry_run=True):
    """
    Sync scores to Salesforce.
    
    Args:
        sf: Salesforce connection object
        payload: DataFrame with Lead updates
        dry_run: If True, only validate without updating
    """
    if len(payload) == 0:
        print("\n[SYNC] No records to sync")
        return
    
    print(f"\n[SYNC] {'DRY RUN: ' if dry_run else ''}Syncing to Salesforce...")
    
    if dry_run:
        print(f"  ✅ DRY RUN: Would update {len(payload):,} Lead records")
        print(f"  Sample records:")
        print(payload.head(5).to_string())
        return
    
    if not SALESFORCE_AVAILABLE:
        print("  ❌ simple-salesforce not available - cannot sync")
        return
    
    try:
        # Convert DataFrame to list of dicts for bulk update
        records = payload.to_dict('records')
        
        # Remove None values
        records = [{k: v for k, v in record.items() if v is not None} for record in records]
        
        # Bulk update (Salesforce allows up to 200 records per batch)
        batch_size = 200
        total_updated = 0
        
        for i in range(0, len(records), batch_size):
            batch = records[i:i+batch_size]
            result = sf.bulk.Lead.update(batch)
            
            # Check for errors
            errors = [r for r in result if not r['success']]
            if errors:
                print(f"  ⚠️  {len(errors)} errors in batch {i//batch_size + 1}")
                for error in errors[:5]:  # Show first 5 errors
                    print(f"     Lead {error.get('id', 'unknown')}: {error.get('errors', [])}")
            else:
                total_updated += len(batch)
                print(f"  ✅ Updated batch {i//batch_size + 1}: {len(batch)} records")
        
        print(f"  ✅ Successfully updated {total_updated:,} Lead records")
        
    except Exception as e:
        print(f"  ❌ Error syncing to Salesforce: {e}")
        import traceback
        traceback.print_exc()


def main():
    """Main execution function."""
    print("=" * 70)
    print("V4.1.0 SALESFORCE SYNC")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)
    
    # Initialize BigQuery client
    print("\n[INIT] Initializing BigQuery client...")
    try:
        bq_client = bigquery.Client(project=PROJECT_ID)
        print("  ✅ BigQuery client initialized")
    except Exception as e:
        print(f"  ❌ Error initializing BigQuery: {e}")
        return
    
    # Initialize Salesforce connection (if available)
    sf = None
    if SALESFORCE_AVAILABLE:
        print("\n[INIT] Initializing Salesforce connection...")
        print("  ⚠️  Salesforce credentials required")
        print("  ⚠️  Set environment variables or update script with credentials")
        print("  ⚠️  For now, running in verification mode only")
        # Uncomment and configure when ready:
        # sf = Salesforce(
        #     username='your_username',
        #     password='your_password',
        #     security_token='your_token'
        # )
    
    # Step 1: Verify Salesforce fields (if Salesforce connection available)
    if sf:
        field_results = verify_salesforce_fields(sf)
        if not all(field_results.values()):
            print("\n⚠️  Some Salesforce fields are missing. Create them before syncing.")
            return
    else:
        print("\n[VERIFY] Salesforce connection not available - skipping field verification")
        print("  ⚠️  Fields to verify manually in Salesforce:")
        for field in SALESFORCE_FIELDS.keys():
            print(f"     - {field}")
    
    # Step 2: Fetch scores from BigQuery
    df_scores = fetch_scores_from_bigquery(bq_client, limit=100)  # Limit for testing
    
    if len(df_scores) == 0:
        print("\n⚠️  No scores found in BigQuery")
        print("  ⚠️  Scores need to be calculated first using lead_scorer_v4.py")
        return
    
    # Step 3: Prepare Salesforce payload
    payload = prepare_salesforce_payload(df_scores)
    
    if len(payload) == 0:
        print("\n⚠️  No payload prepared - check if scores are calculated")
        return
    
    # Step 4: Sync to Salesforce (dry run by default)
    sync_to_salesforce(sf, payload, dry_run=True)
    
    print("\n" + "=" * 70)
    print("SYNC COMPLETE (DRY RUN)")
    print("=" * 70)
    print("\nNext steps:")
    print("1. Calculate scores using lead_scorer_v4.py")
    print("2. Store scores in BigQuery (add to v4_daily_scores_v41 or separate scores table)")
    print("3. Verify Salesforce fields exist")
    print("4. Configure Salesforce credentials in this script")
    print("5. Run sync with dry_run=False")


if __name__ == "__main__":
    main()

