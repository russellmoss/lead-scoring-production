"""
Phase 2: Point-in-Time Feature Engineering

This script:
1. Executes the feature engineering SQL
2. Validates outputs for leakage and completeness
3. Creates feature summary for Phase 3 audit
"""

import sys
import json
from pathlib import Path
from datetime import datetime
import pandas as pd
import numpy as np
from scipy.stats import pearsonr

# Add project root to path
sys.path.insert(0, str(Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")))

# Import utilities and constants
from utils.execution_logger import ExecutionLogger
from config.constants import (
    BASE_DIR,
    PROJECT_ID,
    LOCATION,
    DATASET_ML,
    DATASET_FINTRX,
    DATASET_SALESFORCE
)

from google.cloud import bigquery


def run_phase_2() -> bool:
    """Execute Phase 2: Point-in-Time Feature Engineering."""
    
    logger = ExecutionLogger(BASE_DIR)
    logger.start_phase("2", "Point-in-Time Feature Engineering")
    
    # Track all gates
    all_blocking_gates_passed = True
    
    # Initialize BigQuery client
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    
    # =========================================================================
    # STEP 2.1: Execute Feature Engineering SQL
    # =========================================================================
    logger.log_action("Executing feature engineering SQL")
    
    sql_file = BASE_DIR / "sql" / "phase_2_feature_engineering.sql"
    
    if not sql_file.exists():
        logger.log_error(f"SQL file not found: {sql_file}")
        all_blocking_gates_passed = False
        status = logger.end_phase()
        return False
    
    # Read SQL file
    with open(sql_file, 'r', encoding='utf-8') as f:
        sql_query = f.read()
    
    logger.log_action(f"Read SQL file: {sql_file.name}")
    logger.log_action("Executing query against BigQuery...")
    
    try:
        # Execute query
        job = client.query(sql_query, location=LOCATION)
        job.result()  # Wait for job to complete
        
        logger.log_metric("BigQuery Job", "Completed successfully")
        logger.log_file_created(
            "v4_features_pit",
            f"BigQuery: {PROJECT_ID}.{DATASET_ML}.v4_features_pit"
        )
        
    except Exception as e:
        logger.log_error(f"Failed to execute SQL query: {str(e)}", exception=e)
        all_blocking_gates_passed = False
        status = logger.end_phase()
        return False
    
    # =========================================================================
    # STEP 2.2: Validate Feature Count
    # =========================================================================
    logger.log_action("Validating feature count")
    
    try:
        # Get column count (excluding metadata columns)
        query = f"""
        SELECT column_name
        FROM `{PROJECT_ID}.{DATASET_ML}.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name = 'v4_features_pit'
        ORDER BY ordinal_position
        """
        
        columns_df = client.query(query).to_dataframe()
        
        # Exclude metadata columns
        metadata_cols = ['lead_id', 'advisor_crd', 'contacted_date', 'target', 
                        'lead_source_grouped', 'firm_crd', 'firm_name', 
                        'feature_extraction_timestamp']
        feature_columns = [col for col in columns_df['column_name'].tolist() 
                          if col not in metadata_cols]
        
        feature_count = len(feature_columns)
        logger.log_metric("Total Features", f"{feature_count}")
        logger.log_metric("Feature Columns", ", ".join(feature_columns[:10]) + 
                         ("..." if len(feature_columns) > 10 else ""))
        
        # Gate G2.1: >= 15 features created (WARNING)
        gate_2_1 = feature_count >= 15
        logger.log_gate(
            "G2.1", "Feature Count",
            passed=gate_2_1,
            expected=">= 15 features",
            actual=f"{feature_count} features"
        )
        
        if not gate_2_1:
            logger.log_warning(
                f"Feature count ({feature_count}) below recommended threshold (15)",
                action_taken="Continue but note limited feature set"
            )
        
    except Exception as e:
        logger.log_error(f"Failed to validate feature count: {str(e)}", exception=e)
        feature_count = 0
        feature_columns = []
    
    # =========================================================================
    # STEP 2.3: PIT Compliance Check
    # =========================================================================
    logger.log_action("Checking PIT compliance (suspicious correlations)")
    
    try:
        # Load feature data
        query = f"""
        SELECT *
        FROM `{PROJECT_ID}.{DATASET_ML}.v4_features_pit`
        LIMIT 50000
        """
        
        df = client.query(query).to_dataframe()
        logger.log_dataframe_summary(df, "Feature Data")
        
        # Calculate correlations with target for numeric features
        numeric_features = df.select_dtypes(include=[np.number]).columns.tolist()
        # Exclude metadata columns
        numeric_features = [f for f in numeric_features 
                          if f not in ['lead_id', 'advisor_crd', 'firm_crd', 'target']]
        
        suspicious_features = []
        correlations = {}
        
        for feature in numeric_features:
            if feature in df.columns and df[feature].notna().sum() > 100:  # Need sufficient data
                # Calculate correlation
                valid_mask = df[feature].notna() & df['target'].notna()
                if valid_mask.sum() > 100:
                    corr, p_value = pearsonr(
                        df.loc[valid_mask, feature],
                        df.loc[valid_mask, 'target']
                    )
                    correlations[feature] = {
                        'correlation': corr,
                        'p_value': p_value,
                        'n_valid': valid_mask.sum()
                    }
                    
                    # Flag suspiciously high correlation (>0.3)
                    if abs(corr) > 0.3:
                        suspicious_features.append({
                            'feature': feature,
                            'correlation': corr,
                            'p_value': p_value
                        })
        
        logger.log_metric("Features Analyzed", f"{len(correlations)}")
        logger.log_metric("Suspicious Features", f"{len(suspicious_features)}")
        
        if suspicious_features:
            logger.log_action("Suspicious Features (potential leakage):")
            for sf in suspicious_features:
                logger.log_metric(
                    f"{sf['feature']}",
                    f"Correlation: {sf['correlation']:.3f}, p-value: {sf['p_value']:.4f}"
                )
        
        # Gate G2.2: No features with suspiciously high correlation (>0.3) (BLOCKING)
        gate_2_2 = len(suspicious_features) == 0
        logger.log_gate(
            "G2.2", "PIT Compliance (No Suspicious Correlations)",
            passed=gate_2_2,
            expected="0 features with |correlation| > 0.3",
            actual=f"{len(suspicious_features)} suspicious features"
        )
        
        if not gate_2_2:
            logger.log_error(
                f"Found {len(suspicious_features)} features with suspiciously high correlation (>0.3)",
                action_taken="INVESTIGATE: These may indicate data leakage"
            )
            all_blocking_gates_passed = False
        
    except Exception as e:
        logger.log_error(f"Failed PIT compliance check: {str(e)}", exception=e)
        gate_2_2 = False
        all_blocking_gates_passed = False
        correlations = {}
        suspicious_features = []
    
    # =========================================================================
    # STEP 2.4: Null Rate Analysis
    # =========================================================================
    logger.log_action("Analyzing null rates")
    
    try:
        # Calculate null rates for all features
        null_rates = {}
        high_null_features = []
        
        for feature in feature_columns:
            if feature in df.columns:
                null_count = df[feature].isna().sum()
                null_rate = null_count / len(df)
                null_rates[feature] = null_rate
                
                if null_rate > 0.50:
                    high_null_features.append({
                        'feature': feature,
                        'null_rate': null_rate,
                        'null_count': null_count
                    })
        
        logger.log_metric("Features with Null Data", f"{len([f for f in null_rates.values() if f > 0])}")
        
        if high_null_features:
            logger.log_action("Features with >50% null rate:")
            for hf in high_null_features:
                logger.log_metric(
                    f"{hf['feature']}",
                    f"{hf['null_rate']*100:.1f}% null ({hf['null_count']:,} missing)"
                )
        
        # Gate G2.3: No feature with >50% null rate (WARNING)
        gate_2_3 = len(high_null_features) == 0
        logger.log_gate(
            "G2.3", "Null Rate Check",
            passed=gate_2_3,
            expected="0 features with >50% null rate",
            actual=f"{len(high_null_features)} features with >50% null"
        )
        
        if not gate_2_3:
            logger.log_warning(
                f"Found {len(high_null_features)} features with >50% null rate",
                action_taken="Continue but note sparsity - may need special handling"
            )
        
    except Exception as e:
        logger.log_error(f"Failed null rate analysis: {str(e)}", exception=e)
        gate_2_3 = True  # Don't block on this
        null_rates = {}
        high_null_features = []
    
    # =========================================================================
    # STEP 2.5: Validate Interaction Features
    # =========================================================================
    logger.log_action("Validating interaction features")
    
    try:
        interaction_features = [
            'mobility_x_heavy_bleeding',
            'short_tenure_x_high_mobility',
            'tenure_bucket_x_mobility'
        ]
        
        interaction_validation = {}
        
        for int_feature in interaction_features:
            if int_feature in df.columns:
                # Check that interaction is binary (0 or 1) for first two
                if int_feature in ['mobility_x_heavy_bleeding', 'short_tenure_x_high_mobility']:
                    unique_vals = df[int_feature].dropna().unique()
                    is_binary = set(unique_vals).issubset({0, 1})
                    interaction_validation[int_feature] = {
                        'exists': True,
                        'is_binary': is_binary,
                        'unique_values': sorted(unique_vals.tolist()),
                        'count_positive': int(df[int_feature].sum()) if is_binary else None
                    }
                else:
                    # tenure_bucket_x_mobility is numeric
                    interaction_validation[int_feature] = {
                        'exists': True,
                        'is_binary': False,
                        'min': float(df[int_feature].min()),
                        'max': float(df[int_feature].max()),
                        'mean': float(df[int_feature].mean())
                    }
                
                logger.log_metric(
                    f"{int_feature}",
                    f"Exists: True, Positive cases: {interaction_validation[int_feature].get('count_positive', 'N/A')}"
                )
            else:
                interaction_validation[int_feature] = {'exists': False}
                logger.log_warning(f"Interaction feature {int_feature} not found in data")
        
        # Gate G2.4: All interaction features calculated correctly (WARNING)
        all_interactions_exist = all(v.get('exists', False) for v in interaction_validation.values())
        gate_2_4 = all_interactions_exist
        logger.log_gate(
            "G2.4", "Interaction Features",
            passed=gate_2_4,
            expected="All 3 interaction features present",
            actual=f"{sum(1 for v in interaction_validation.values() if v.get('exists', False))}/3 present"
        )
        
        if not gate_2_4:
            logger.log_warning(
                "Some interaction features missing or incorrectly calculated",
                action_taken="Review SQL logic"
            )
        
    except Exception as e:
        logger.log_error(f"Failed interaction feature validation: {str(e)}", exception=e)
        gate_2_4 = True  # Don't block on this
        interaction_validation = {}
    
    # =========================================================================
    # STEP 2.6: Row Count Preservation
    # =========================================================================
    logger.log_action("Validating row count preservation")
    
    try:
        # Get row counts
        query_target = f"""
        SELECT COUNT(*) as cnt
        FROM `{PROJECT_ID}.{DATASET_ML}.v4_target_variable`
        WHERE target IS NOT NULL
        """
        
        query_features = f"""
        SELECT COUNT(*) as cnt
        FROM `{PROJECT_ID}.{DATASET_ML}.v4_features_pit`
        """
        
        query_duplicates = f"""
        SELECT 
            lead_id,
            COUNT(*) as cnt
        FROM `{PROJECT_ID}.{DATASET_ML}.v4_features_pit`
        GROUP BY lead_id
        HAVING COUNT(*) > 1
        """
        
        target_count = list(client.query(query_target).result())[0].cnt
        feature_count_rows = list(client.query(query_features).result())[0].cnt
        
        # Check for duplicate lead_ids
        duplicates_df = client.query(query_duplicates).to_dataframe()
        duplicate_count = len(duplicates_df)
        
        logger.log_metric("Target Table Rows", f"{target_count:,}")
        logger.log_metric("Feature Table Rows", f"{feature_count_rows:,}")
        logger.log_metric("Duplicate lead_ids", f"{duplicate_count}")
        
        if duplicate_count > 0:
            logger.log_warning(
                f"Found {duplicate_count} duplicate lead_ids in feature table",
                action_taken="INVESTIGATE: SQL joins may be creating duplicates"
            )
        
        # Gate G2.5: Same row count as target table (BLOCKING)
        gate_2_5 = target_count == feature_count_rows
        logger.log_gate(
            "G2.5", "Row Count Preservation",
            passed=gate_2_5,
            expected=f"{target_count:,} rows",
            actual=f"{feature_count_rows:,} rows"
        )
        
        if not gate_2_5:
            logger.log_error(
                f"Row count mismatch: Target={target_count:,}, Features={feature_count_rows:,}"
            )
            logger.log_warning(
                "Row count mismatch detected",
                action_taken="INVESTIGATE: Possible duplicate leads or data issue"
            )
            all_blocking_gates_passed = False
        
    except Exception as e:
        logger.log_error(f"Failed row count validation: {str(e)}", exception=e)
        gate_2_5 = False
        all_blocking_gates_passed = False
    
    # =========================================================================
    # STEP 2.7: Feature Summary
    # =========================================================================
    logger.log_action("Creating feature summary")
    
    try:
        # Calculate summary statistics for each feature
        feature_summary = []
        
        for feature in feature_columns:
            if feature in df.columns:
                summary = {
                    'feature_name': feature,
                    'null_rate': null_rates.get(feature, df[feature].isna().sum() / len(df)),
                    'n_valid': df[feature].notna().sum(),
                    'n_null': df[feature].isna().sum()
                }
                
                # Numeric statistics
                if df[feature].dtype in [np.int64, np.float64]:
                    valid_data = df[feature].dropna()
                    if len(valid_data) > 0:
                        summary['mean'] = float(valid_data.mean())
                        summary['std'] = float(valid_data.std())
                        summary['min'] = float(valid_data.min())
                        summary['max'] = float(valid_data.max())
                        
                        # Correlation with target
                        if 'target' in df.columns:
                            valid_mask = df[feature].notna() & df['target'].notna()
                            if valid_mask.sum() > 10:
                                corr, _ = pearsonr(
                                    df.loc[valid_mask, feature],
                                    df.loc[valid_mask, 'target']
                                )
                                summary['correlation_with_target'] = float(corr)
                            else:
                                summary['correlation_with_target'] = None
                        else:
                            summary['correlation_with_target'] = None
                    else:
                        summary['mean'] = None
                        summary['std'] = None
                        summary['correlation_with_target'] = None
                else:
                    # Categorical
                    summary['mean'] = None
                    summary['std'] = None
                    summary['correlation_with_target'] = None
                    summary['n_unique'] = int(df[feature].nunique())
                
                feature_summary.append(summary)
        
        # Create DataFrame and save
        summary_df = pd.DataFrame(feature_summary)
        csv_path = BASE_DIR / "data" / "processed" / "feature_summary.csv"
        summary_df.to_csv(csv_path, index=False)
        
        logger.log_file_created("feature_summary.csv", str(csv_path))
        logger.log_metric("Features Summarized", f"{len(feature_summary)}")
        
        # Log top features by correlation
        numeric_summary = summary_df[summary_df['correlation_with_target'].notna()].copy()
        if len(numeric_summary) > 0:
            numeric_summary = numeric_summary.sort_values('correlation_with_target', key=abs, ascending=False)
            logger.log_action("Top 5 Features by |Correlation| with Target:")
            for _, row in numeric_summary.head(5).iterrows():
                logger.log_metric(
                    f"{row['feature_name']}",
                    f"Correlation: {row['correlation_with_target']:.3f}"
                )
        
    except Exception as e:
        logger.log_error(f"Failed to create feature summary: {str(e)}", exception=e)
    
    # =========================================================================
    # PHASE SUMMARY
    # =========================================================================
    status = logger.end_phase(next_steps=["Phase 3: Leakage Audit"])
    
    return all_blocking_gates_passed and status in ["PASSED", "PASSED WITH WARNINGS"]


if __name__ == "__main__":
    success = run_phase_2()
    sys.exit(0 if success else 1)

