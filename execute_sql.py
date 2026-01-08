"""Execute SQL files using BigQuery MCP"""
from google.cloud import bigquery
from pathlib import Path
import sys

def execute_sql_file(sql_file_path, project_id='savvy-gtm-analytics'):
    """Execute a SQL file in BigQuery"""
    client = bigquery.Client(project=project_id)
    
    sql_path = Path(sql_file_path)
    if not sql_path.exists():
        print(f"Error: File not found: {sql_file_path}")
        return False
    
    print(f"Reading SQL file: {sql_file_path}")
    sql = sql_path.read_text(encoding='utf-8')
    
    print(f"Executing SQL query...")
    try:
        job = client.query(sql)
        job.result()  # Wait for completion
        print(f"[OK] Query executed successfully!")
        if hasattr(job, 'num_dml_affected_rows') and job.num_dml_affected_rows:
            print(f"   Rows affected: {job.num_dml_affected_rows:,}")
        return True
    except Exception as e:
        print(f"[ERROR] Error executing query: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python execute_sql.py <sql_file_path>")
        sys.exit(1)
    
    sql_file = sys.argv[1]
    success = execute_sql_file(sql_file)
    sys.exit(0 if success else 1)
