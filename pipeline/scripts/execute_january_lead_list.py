import sys
from pathlib import Path
from google.cloud import bigquery

# Add the project root to the Python path
WORKING_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(WORKING_DIR))

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
SQL_FILE_PATH = WORKING_DIR / "pipeline" / "sql" / "January_2026_Lead_List_V3_V4_Hybrid.sql"

def execute_bigquery_sql(sql_file_path):
    """Executes a SQL file in BigQuery."""
    client = bigquery.Client(project=PROJECT_ID)
    
    with open(sql_file_path, 'r', encoding='utf-8') as f:
        sql = f.read()
    
    print(f"Executing {sql_file_path.name} in BigQuery...")
    print(f"SQL file: {sql_file_path}")
    print(f"SQL length: {len(sql)} characters")
    
    job = client.query(sql)
    job.result()  # Waits for the query to finish
    
    print("Query completed successfully!")
    print(f"Job ID: {job.job_id}")
    print(f"Total bytes processed: {job.total_bytes_processed}")
    print(f"Total bytes billed: {job.total_bytes_billed}")
    
    # Get table info
    destination_table = job.destination
    if destination_table:
        table = client.get_table(destination_table)
        print(f"\nTable created/updated: {table.full_table_id}")
        print(f"Rows: {table.num_rows:,}")
        print(f"Size: {table.num_bytes:,} bytes")

if __name__ == "__main__":
    execute_bigquery_sql(SQL_FILE_PATH)

