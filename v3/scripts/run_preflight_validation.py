"""
Phase 0.0 Preflight Validation
Runs all preflight checks before proceeding with data work.
"""

import sys
from pathlib import Path

# Add Version-3 to path
BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-3")
sys.path.insert(0, str(BASE_DIR))

from utils.execution_logger import ExecutionLogger
from google.cloud import bigquery

def run_preflight_validation():
    """Run all preflight validation checks."""
    logger = ExecutionLogger()
    logger.start_phase("0.0-PREFLIGHT", "Preflight Validation")
    
    client = bigquery.Client(project="savvy-gtm-analytics", location="northamerica-northeast2")
    all_passed = True
    
    # Check 1: Region Validation
    logger.log_action("Checking dataset locations are in Toronto region")
    try:
        query = """
        SELECT
          schema_name AS dataset,
          location
        FROM `savvy-gtm-analytics.region-northamerica-northeast2.INFORMATION_SCHEMA.SCHEMATA`
        WHERE schema_name IN ('FinTrx_data_CA', 'SavvyGTMData', 'ml_features')
        """
        result = client.query(query, location="northamerica-northeast2").to_dataframe()
        
        all_in_toronto = all(result['location'] == 'northamerica-northeast2')
        if all_in_toronto:
            logger.log_validation_gate("PREFLIGHT-1", "Region Validation", True, 
                                      f"All datasets in Toronto: {', '.join(result['dataset'].tolist())}")
        else:
            logger.log_validation_gate("PREFLIGHT-1", "Region Validation", False, 
                                      f"Some datasets not in Toronto: {result}")
            all_passed = False
    except Exception as e:
        logger.log_validation_gate("PREFLIGHT-1", "Region Validation", False, str(e))
        all_passed = False
    
    # Check 2: Table Access
    logger.log_action("Checking read access to source tables")
    try:
        query = """
        SELECT 
          table_schema,
          table_name,
          'ACCESSIBLE' as access_status
        FROM `savvy-gtm-analytics.FinTrx_data_CA.INFORMATION_SCHEMA.TABLES`
        WHERE table_name IN ('contact_registered_employment_history', 'Firm_historicals', 'ria_contacts_current')
        UNION ALL
        SELECT 
          table_schema,
          table_name,
          'ACCESSIBLE' as access_status
        FROM `savvy-gtm-analytics.SavvyGTMData.INFORMATION_SCHEMA.TABLES`
        WHERE table_name = 'Lead'
        """
        result = client.query(query, location="northamerica-northeast2").to_dataframe()
        
        expected_tables = {'contact_registered_employment_history', 'Firm_historicals', 'ria_contacts_current', 'Lead'}
        found_tables = set(result['table_name'].tolist())
        
        if expected_tables.issubset(found_tables):
            logger.log_validation_gate("PREFLIGHT-2", "Table Access", True, 
                                      f"All required tables accessible: {', '.join(found_tables)}")
        else:
            missing = expected_tables - found_tables
            logger.log_validation_gate("PREFLIGHT-2", "Table Access", False, 
                                      f"Missing tables: {missing}")
            all_passed = False
    except Exception as e:
        logger.log_validation_gate("PREFLIGHT-2", "Table Access", False, str(e))
        all_passed = False
    
    # Check 3: Table Creation Permissions (dry run)
    logger.log_action("Testing table creation permissions (dry run)")
    try:
        query = "CREATE TABLE IF NOT EXISTS `savvy-gtm-analytics.ml_features.test_permissions` (id INT64) AS SELECT 1"
        job_config = bigquery.QueryJobConfig(dry_run=True)
        job = client.query(query, job_config=job_config, location="northamerica-northeast2")
        
        if job.ddl_operation_performed == "CREATE":
            logger.log_validation_gate("PREFLIGHT-3", "Table Creation Permissions", True, 
                                      "Dry run succeeded - can create tables")
        else:
            logger.log_validation_gate("PREFLIGHT-3", "Table Creation Permissions", False, 
                                      "Dry run did not indicate CREATE permission")
            all_passed = False
    except Exception as e:
        logger.log_validation_gate("PREFLIGHT-3", "Table Creation Permissions", False, str(e))
        all_passed = False
    
    # End phase
    status = "PASSED" if all_passed else "FAILED"
    logger.end_phase(
        status=status,
        next_steps=["Proceed to Phase 0.1: Data Landscape Assessment"] if all_passed else ["Fix permission issues before proceeding"]
    )
    
    return all_passed

if __name__ == "__main__":
    success = run_preflight_validation()
    sys.exit(0 if success else 1)

