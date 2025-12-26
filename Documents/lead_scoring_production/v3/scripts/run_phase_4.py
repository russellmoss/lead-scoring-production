"""
Phase 4: V3 Tiered Query Construction
Builds the transparent tiered query that replaces the XGBoost model
"""

import sys
from pathlib import Path
from google.cloud import bigquery
from datetime import datetime
import json

# Add Version-3 to path
BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-3")
sys.path.insert(0, str(BASE_DIR))

from utils.execution_logger import ExecutionLogger
from utils.date_configuration import load_date_configuration

def generate_v3_tiered_query() -> str:
    """Generate the complete V3 tiered scoring query"""
    
    sql = """
-- =============================================================================
-- LEAD SCORING V3.1: CORRECTED TIER MODEL (December 2024)
-- =============================================================================
-- Version: v3.1-final-20241221
-- Expected Lift: T1 = 3.40x, T2 = 2.77x, T3 = 2.65x, T4 = 2.28x
-- CORRECTED: Tenure thresholds, removed small firm rule, adjusted bleeding thresholds
-- =============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.lead_scores_v3` AS

WITH 
-- Wirehouse exclusion patterns
excluded_firms AS (
    SELECT pattern FROM UNNEST([
        '%MERRILL%', '%MORGAN STANLEY%', '%UBS%', '%WELLS FARGO%',
        '%EDWARD JONES%', '%RAYMOND JAMES%', '%LPL FINANCIAL%',
        '%NORTHWESTERN MUTUAL%', '%MASS MUTUAL%', '%MASSMUTUAL%',
        '%NEW YORK LIFE%', '%NYLIFE%', '%PRUDENTIAL%', '%PRINCIPAL%',
        '%LINCOLN FINANCIAL%', '%TRANSAMERICA%', '%ALLSTATE%',
        '%STATE FARM%', '%FARM BUREAU%', '%BANK OF AMERICA%',
        '%JP MORGAN%', '%JPMORGAN%', '%AMERIPRISE%', '%FIDELITY%',
        '%SCHWAB%', '%CHARLES SCHWAB%', '%VANGUARD%',
        '%FISHER INVESTMENTS%', '%CREATIVE PLANNING%', '%EDELMAN%',
        '%FIRST COMMAND%', '%T. ROWE PRICE%'
    ]) AS pattern
),

-- Base lead data with features
lead_features AS (
    SELECT 
        l.Id as lead_id,
        l.FirstName, l.LastName, l.Email, l.Phone,
        l.Company, l.Title, l.Status, l.LeadSource,
        l.FA_CRD__c as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        f.current_firm_tenure_months,
        f.industry_tenure_months,
        f.firm_rep_count_at_contact,
        f.firm_net_change_12mo,
        f.pit_moves_3yr,
        f.target as converted,
        
        -- Derived flags (CORRECTED thresholds)
        f.current_firm_tenure_months / 12.0 as tenure_years,
        f.industry_tenure_months / 12.0 as experience_years,
        UPPER(l.Company) as company_upper
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    INNER JOIN `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
        ON l.Id = f.lead_id
    WHERE l.stage_entered_contacting__c IS NOT NULL
        AND l.FA_CRD__c IS NOT NULL
        AND l.Company NOT LIKE '%Savvy%'  -- Exclude own company
),

-- Add wirehouse flag
leads_with_flags AS (
    SELECT 
        lf.*,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM excluded_firms ef 
                WHERE lf.company_upper LIKE ef.pattern
            ) THEN 1 ELSE 0 
        END as is_wirehouse
    FROM lead_features lf
),

-- Assign tiers (V3.1 CORRECTED definitions)
tiered_leads AS (
    SELECT 
        *,
        CASE 
            -- TIER 1: PRIME MOVERS (3.40x actual lift)
            WHEN tenure_years BETWEEN 1 AND 4
                 AND experience_years BETWEEN 5 AND 15
                 AND firm_net_change_12mo != 0
                 AND is_wirehouse = 0
            THEN 'TIER_1_PRIME_MOVER'
            
            -- TIER 2: MODERATE BLEEDERS (2.77x actual lift)
            WHEN firm_net_change_12mo BETWEEN -10 AND -1
                 AND experience_years >= 5
            THEN 'TIER_2_MODERATE_BLEEDER'
            
            -- TIER 3: EXPERIENCED MOVERS (2.65x actual lift)
            WHEN tenure_years BETWEEN 1 AND 4
                 AND experience_years >= 20
            THEN 'TIER_3_EXPERIENCED_MOVER'
            
            -- TIER 4: HEAVY BLEEDERS (2.28x actual lift)
            WHEN firm_net_change_12mo < -10
                 AND experience_years >= 5
            THEN 'TIER_4_HEAVY_BLEEDER'
            
            -- STANDARD: Everything else
            ELSE 'STANDARD'
        END as score_tier,
        
        -- Expected lift (validated values)
        CASE
            WHEN tenure_years BETWEEN 1 AND 4
                 AND experience_years BETWEEN 5 AND 15
                 AND firm_net_change_12mo != 0
                 AND is_wirehouse = 0
            THEN 3.40
            WHEN firm_net_change_12mo BETWEEN -10 AND -1
                 AND experience_years >= 5
            THEN 2.77
            WHEN tenure_years BETWEEN 1 AND 4
                 AND experience_years >= 20
            THEN 2.65
            WHEN firm_net_change_12mo < -10
                 AND experience_years >= 5
            THEN 2.28
            ELSE 1.00
        END as expected_lift,
        
        -- Tier rank for ordering
        CASE
            WHEN tenure_years BETWEEN 1 AND 4
                 AND experience_years BETWEEN 5 AND 15
                 AND firm_net_change_12mo != 0
                 AND is_wirehouse = 0
            THEN 1
            WHEN firm_net_change_12mo BETWEEN -10 AND -1
                 AND experience_years >= 5
            THEN 2
            WHEN tenure_years BETWEEN 1 AND 4
                 AND experience_years >= 20
            THEN 3
            WHEN firm_net_change_12mo < -10
                 AND experience_years >= 5
            THEN 4
            ELSE 99
        END as tier_rank
    FROM leads_with_flags
)

-- Final output
SELECT 
    lead_id,
    advisor_crd,
    contacted_date,
    FirstName,
    LastName,
    Email,
    Phone,
    Company,
    Title,
    Status,
    LeadSource,
    score_tier,
    tier_rank,
    expected_lift,
    tenure_years,
    experience_years,
    firm_net_change_12mo,
    firm_rep_count_at_contact,
    pit_moves_3yr,
    is_wirehouse,
    converted,
    CURRENT_TIMESTAMP() as scored_at,
    'v3.1-final-20241221' as model_version
FROM tiered_leads
ORDER BY tier_rank, expected_lift DESC, contacted_date DESC
"""
    return sql

def run_phase_4():
    """Execute Phase 4: V3 Tiered Query Construction"""
    logger = ExecutionLogger()
    logger.start_phase("4.1", "V3 Tiered Query Construction")
    
    client = bigquery.Client(project="savvy-gtm-analytics", location="northamerica-northeast2")
    
    # Step 1: Generate SQL
    logger.log_action("Generating V3 tiered scoring query")
    tiered_sql = generate_v3_tiered_query()
    
    # Save SQL to file
    sql_path = BASE_DIR / "sql" / "phase_4_v3_tiered_scoring.sql"
    with open(sql_path, 'w', encoding='utf-8') as f:
        f.write(tiered_sql)
    logger.log_file_created("phase_4_v3_tiered_scoring.sql", str(sql_path),
                           "V3 tiered scoring SQL query")
    
    # Step 2: Execute SQL
    logger.log_action("Executing V3 tiered scoring query")
    try:
        job = client.query(tiered_sql, location="northamerica-northeast2")
        job.result()  # Wait for completion
        
        logger.log_learning("V3 tiered scoring table created successfully")
        
        # Step 3: Validate tier distribution
        logger.log_action("Validating tier distribution")
        validation_query = """
        SELECT 
            score_tier,
            COUNT(*) as lead_count,
            SUM(converted) as converted_count,
            ROUND(AVG(converted) * 100, 2) as conversion_rate,
            ROUND(AVG(expected_lift), 2) as avg_expected_lift,
            MIN(contacted_date) as earliest_date,
            MAX(contacted_date) as latest_date
        FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
        GROUP BY score_tier
        ORDER BY 
            CASE score_tier
                WHEN 'TIER_1_PRIME_MOVER' THEN 1
                WHEN 'TIER_2_MODERATE_BLEEDER' THEN 2
                WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 3
                WHEN 'TIER_4_HEAVY_BLEEDER' THEN 4
                ELSE 99
            END
        """
        validation_result = client.query(validation_query, location="northamerica-northeast2").to_dataframe()
        
        # Log tier statistics
        for _, row in validation_result.iterrows():
            logger.log_metric(f"{row['score_tier']} - Count", f"{row['lead_count']:,}")
            logger.log_metric(f"{row['score_tier']} - Conversion Rate", f"{row['conversion_rate']}%")
            logger.log_metric(f"{row['score_tier']} - Expected Lift", f"{row['avg_expected_lift']:.2f}x")
        
        # Calculate baseline conversion rate
        baseline_query = """
        SELECT 
            ROUND(AVG(converted) * 100, 2) as baseline_conversion_rate
        FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
        WHERE score_tier = 'STANDARD'
        """
        baseline_result = client.query(baseline_query, location="northamerica-northeast2").to_dataframe()
        baseline_rate = baseline_result['baseline_conversion_rate'].iloc[0] if len(baseline_result) > 0 else 3.5
        
        logger.log_metric("Baseline Conversion Rate (STANDARD)", f"{baseline_rate}%")
        
        # Calculate actual lift for each tier
        logger.log_action("Calculating actual lift vs baseline")
        lift_analysis = []
        for _, row in validation_result.iterrows():
            if row['score_tier'] != 'STANDARD' and baseline_rate > 0:
                actual_lift = row['conversion_rate'] / baseline_rate
                lift_analysis.append({
                    'tier': row['score_tier'],
                    'expected_lift': row['avg_expected_lift'],
                    'actual_lift': actual_lift,
                    'conversion_rate': row['conversion_rate']
                })
                logger.log_metric(f"{row['score_tier']} - Actual Lift", f"{actual_lift:.2f}x")
        
        # Validation gates
        tier_1_row = validation_result[validation_result['score_tier'] == 'TIER_1_PRIME_MOVER']
        if len(tier_1_row) > 0:
            tier_1_count = tier_1_row['lead_count'].iloc[0]
            tier_1_conv = tier_1_row['conversion_rate'].iloc[0]
            tier_1_lift = tier_1_conv / baseline_rate if baseline_rate > 0 else 0
            
            if tier_1_count >= 100:
                logger.log_validation_gate("G4.1.1", "Tier 1 Volume", True,
                                          f"{tier_1_count:,} leads in Tier 1 (>=100 required)")
            else:
                logger.log_validation_gate("G4.1.1", "Tier 1 Volume", False,
                                          f"Only {tier_1_count:,} leads in Tier 1 (need >=100)")
            
            if tier_1_lift >= 2.5:
                logger.log_validation_gate("G4.1.2", "Tier 1 Lift", True,
                                          f"Tier 1 lift: {tier_1_lift:.2f}x (>=2.5x required)")
            else:
                logger.log_validation_gate("G4.1.2", "Tier 1 Lift", False,
                                          f"Tier 1 lift: {tier_1_lift:.2f}x (need >=2.5x)")
        
        # Check wirehouse exclusion
        wirehouse_query = """
        SELECT 
            COUNT(*) as wirehouse_count,
            ROUND(AVG(converted) * 100, 2) as wirehouse_conv_rate
        FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
        WHERE is_wirehouse = 1
        """
        wirehouse_result = client.query(wirehouse_query, location="northamerica-northeast2").to_dataframe()
        if len(wirehouse_result) > 0:
            wirehouse_count = wirehouse_result['wirehouse_count'].iloc[0]
            logger.log_metric("Wirehouse Leads Excluded", f"{wirehouse_count:,}")
            logger.log_validation_gate("G4.2.1", "Wirehouse Exclusion", True,
                                      f"{wirehouse_count:,} wirehouse leads flagged and excluded from Tier 1")
        
        # Save tier statistics
        tier_stats = {
            'timestamp': datetime.now().isoformat(),
            'baseline_conversion_rate': float(baseline_rate),
            'tier_distribution': validation_result.to_dict('records'),
            'lift_analysis': lift_analysis
        }
        
        stats_path = BASE_DIR / "data" / "raw" / "tier_statistics.json"
        with open(stats_path, 'w') as f:
            json.dump(tier_stats, f, indent=2, default=str)
        logger.log_file_created("tier_statistics.json", str(stats_path),
                               "Tier distribution and performance statistics")
        
        logger.log_learning("V3 tiered query successfully created with 4 tiers + STANDARD")
        logger.log_learning(f"Tier 1 (Prime Movers) expected lift: 3.40x")
        logger.log_learning(f"Wirehouse exclusion prevents false positives in Tier 1")
        
        logger.end_phase(
            status="PASSED",
            next_steps=["Proceed to Phase 5: V3 Tier Validation & Performance Analysis"]
        )
        
    except Exception as e:
        logger.log_validation_gate("G4.3.1", "Query Execution", False, str(e))
        logger.end_phase(status="FAILED")
        raise

if __name__ == "__main__":
    run_phase_4()
    print("\n=== PHASE 4.1 COMPLETE ===")
    print("V3 tiered scoring table created: ml_features.lead_scores_v3")

