"""
Lead List Generator Script (V3.2.1)
Automates generation of monthly lead lists from production model
"""

import sys
from pathlib import Path
from datetime import datetime
from google.cloud import bigquery
import re

# Add Version-3 to path
BASE_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(BASE_DIR))

def generate_lead_list_sql(
    table_name: str,
    lead_limit: int = 2400,
    recyclable_days: int = 180
) -> str:
    """
    Generate SQL for creating a lead list table
    
    Args:
        table_name: Output table name (e.g., 'february_2026_lead_list')
        lead_limit: Maximum number of leads to include (default: 2400)
        recyclable_days: Days threshold for recyclable leads (default: 180)
    
    Returns:
        Complete SQL query as string
    """
    
    # Read the template
    template_path = BASE_DIR / "sql" / "generate_lead_list_v3.2.1.sql"
    
    if not template_path.exists():
        raise FileNotFoundError(f"Template not found: {template_path}")
    
    with open(template_path, 'r', encoding='utf-8') as f:
        sql_template = f.read()
    
    # Replace placeholders
    sql = sql_template.replace('{TABLE_NAME}', table_name)
    sql = sql.replace('{LEAD_LIMIT}', str(lead_limit))
    sql = sql.replace('{RECYCLABLE_DAYS}', str(recyclable_days))
    
    return sql


def generate_lead_list(
    table_name: str,
    lead_limit: int = 2400,
    recyclable_days: int = 180,
    execute: bool = True,
    project_id: str = "savvy-gtm-analytics"
) -> str:
    """
    Generate and optionally execute lead list creation
    
    Args:
        table_name: Output table name
        lead_limit: Maximum number of leads
        recyclable_days: Days threshold for recyclable leads
        execute: If True, execute the query in BigQuery
        project_id: BigQuery project ID
    
    Returns:
        SQL query string
    """
    
    print(f"Generating lead list: {table_name}")
    print(f"  Lead limit: {lead_limit}")
    print(f"  Recyclable days: {recyclable_days}")
    
    sql = generate_lead_list_sql(table_name, lead_limit, recyclable_days)
    
    if execute:
        print(f"\nExecuting query in BigQuery...")
        client = bigquery.Client(project=project_id)
        
        job_config = bigquery.QueryJobConfig(
            use_legacy_sql=False,
            write_disposition='WRITE_TRUNCATE'  # Replace existing table
        )
        
        job = client.query(sql, job_config=job_config)
        job.result()  # Wait for completion
        
        print(f"✅ Lead list created: {table_name}")
        print(f"   Table: {project_id}.ml_features.{table_name}")
        
        # Get row count
        count_query = f"""
        SELECT COUNT(*) as row_count
        FROM `{project_id}.ml_features.{table_name}`
        """
        result = client.query(count_query).result()
        row_count = list(result)[0].row_count
        print(f"   Rows: {row_count:,}")
        
    else:
        print(f"\nSQL generated (not executed)")
        print(f"  To execute, run this SQL in BigQuery:")
        print(f"  Table: {project_id}.ml_features.{table_name}")
    
    return sql


def main():
    """CLI interface for lead list generation"""
    
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Generate lead lists from V3.2.1 production model'
    )
    parser.add_argument(
        'table_name',
        help='Output table name (e.g., february_2026_lead_list)'
    )
    parser.add_argument(
        '--limit',
        type=int,
        default=2400,
        help='Maximum number of leads (default: 2400)'
    )
    parser.add_argument(
        '--recyclable-days',
        type=int,
        default=180,
        help='Days threshold for recyclable leads (default: 180)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Generate SQL without executing'
    )
    parser.add_argument(
        '--project',
        default='savvy-gtm-analytics',
        help='BigQuery project ID (default: savvy-gtm-analytics)'
    )
    
    args = parser.parse_args()
    
    generate_lead_list(
        table_name=args.table_name,
        lead_limit=args.limit,
        recyclable_days=args.recyclable_days,
        execute=not args.dry_run,
        project_id=args.project
    )


if __name__ == '__main__':
    main()

