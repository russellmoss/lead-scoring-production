"""Execute v4_prospect_features.sql in BigQuery"""
import sys
from pathlib import Path
from google.cloud import bigquery

# Add project root to path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

# Read SQL file
sql_file = project_root / "pipeline" / "sql" / "v4_prospect_features.sql"
with open(sql_file, 'r', encoding='utf-8') as f:
    sql = f.read()

# Execute query
print("Executing v4_prospect_features.sql in BigQuery...")
print(f"SQL file: {sql_file}")
print(f"SQL length: {len(sql)} characters")

client = bigquery.Client(project="savvy-gtm-analytics")
job = client.query(sql)
result = job.result()

print(f"\nQuery completed successfully!")
print(f"Job ID: {job.job_id}")
print(f"Total bytes processed: {job.total_bytes_processed:,}")
print(f"Total bytes billed: {job.total_bytes_billed:,}")

# Check table
table_ref = client.get_table("savvy-gtm-analytics.ml_features.v4_prospect_features")
print(f"\nTable created/updated: ml_features.v4_prospect_features")
print(f"Rows: {table_ref.num_rows:,}")
print(f"Size: {table_ref.num_bytes:,} bytes")

