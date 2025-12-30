"""
Execute the optimized lead list SQL query in BigQuery
"""

from pathlib import Path
from google.cloud import bigquery
from datetime import datetime

PROJECT_ID = "savvy-gtm-analytics"
LOCATION = "northamerica-northeast2"

print("=" * 70)
print("EXECUTING OPTIMIZED LEAD LIST SQL QUERY")
print("=" * 70)
print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print()

# Read SQL file
sql_file = Path(r"C:\Users\russe\Documents\lead_scoring_production\pipeline\sql\January_2026_Lead_List_V3_V4_Hybrid.sql")
print(f"[INFO] Reading SQL file: {sql_file}")
with open(sql_file, 'r', encoding='utf-8') as f:
    sql_query = f.read()

print(f"[INFO] SQL query length: {len(sql_query):,} characters")
print()

# Initialize BigQuery client
print(f"[INFO] Initializing BigQuery client (project: {PROJECT_ID}, location: {LOCATION})")
client = bigquery.Client(project=PROJECT_ID, location=LOCATION)

# Execute query
print("[INFO] Executing SQL query in BigQuery...")
print("  This may take several minutes...")
print()

try:
    job = client.query(sql_query, location=LOCATION)
    result = job.result()  # Wait for completion
    
    print("[OK] Query completed successfully!")
    print()
    print(f"[INFO] Table created/updated: savvy-gtm-analytics.ml_features.january_2026_lead_list_v4")
    print()
    print("Next steps:")
    print("  1. Run: python pipeline/scripts/export_lead_list.py")
    print("  2. Review the exported CSV file")
    print()
    
except Exception as e:
    print(f"[ERROR] Query failed: {e}")
    import traceback
    traceback.print_exc()
    raise

print("=" * 70)
print("SQL EXECUTION COMPLETE")
print("=" * 70)

