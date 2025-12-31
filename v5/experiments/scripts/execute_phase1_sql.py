"""
Execute Phase 1: Create Feature Candidates Table
"""
import sys
from pathlib import Path
from google.cloud import bigquery

# Add project root to path
WORKING_DIR = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(WORKING_DIR))

PROJECT_ID = "savvy-gtm-analytics"
SQL_FILE = WORKING_DIR / "v5" / "experiments" / "sql" / "create_feature_candidates_v5.sql"

def main():
    client = bigquery.Client(project=PROJECT_ID)
    
    print(f"Reading SQL file: {SQL_FILE}")
    with open(SQL_FILE, 'r', encoding='utf-8') as f:
        sql = f.read()
    
    print(f"SQL length: {len(sql)} characters")
    print("Executing in BigQuery...")
    
    job = client.query(sql)
    result = job.result()  # Wait for completion
    
    print(f"[SUCCESS] Query completed!")
    print(f"   Job ID: {job.job_id}")
    print(f"   Total bytes processed: {job.total_bytes_processed:,}")
    
    # Verify table was created
    table_ref = client.get_table("savvy-gtm-analytics.ml_experiments.feature_candidates_v5")
    print(f"   Table created: {table_ref.full_table_id}")
    print(f"   Rows: {table_ref.num_rows:,}")
    print(f"   Size: {table_ref.num_bytes:,} bytes")

if __name__ == "__main__":
    main()

