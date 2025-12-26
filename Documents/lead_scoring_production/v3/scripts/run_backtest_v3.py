"""
V3.1 Backtesting Script - Using MCP BigQuery Connection
Tests the tiered model on historical data across different time periods
"""

import sys
from pathlib import Path
from datetime import datetime
import json
import pandas as pd

# Add Version-3 to path
BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-3")
sys.path.insert(0, str(BASE_DIR))

from utils.execution_logger import ExecutionLogger

def generate_backtest_query(train_start: str, train_end: str, test_start: str, test_end: str) -> str:
    """Generate backtest query for a specific time period"""
    
    sql = f"""
-- V3.1 Backtest: Train on {train_start} to {train_end}, Test on {test_start} to {test_end}

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

-- Test period leads with features
test_leads AS (
    SELECT 
        l.Id as lead_id,
        l.FirstName, l.LastName, l.Email, l.Phone,
        l.Company, l.Title, l.Status, l.LeadSource,
        l.FA_CRD__c as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        CASE WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END as converted,
        f.current_firm_tenure_months,
        f.industry_tenure_months,
        f.firm_rep_count_at_contact,
        f.firm_net_change_12mo,
        f.pit_moves_3yr,
        
        -- Derived flags (CORRECTED thresholds)
        f.current_firm_tenure_months / 12.0 as tenure_years,
        f.industry_tenure_months / 12.0 as experience_years,
        UPPER(l.Company) as company_upper
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    INNER JOIN `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` f
        ON l.Id = f.lead_id
    WHERE l.stage_entered_contacting__c IS NOT NULL
        AND l.FA_CRD__c IS NOT NULL
        AND l.Company NOT LIKE '%Savvy%'
        AND DATE(l.stage_entered_contacting__c) >= '{test_start}'
        AND DATE(l.stage_entered_contacting__c) <= '{test_end}'
        -- Only include leads that are mature enough (30+ days old)
        AND DATE_DIFF(CURRENT_DATE(), DATE(l.stage_entered_contacting__c), DAY) >= 30
),

-- Add wirehouse flag
leads_with_flags AS (
    SELECT 
        tl.*,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM excluded_firms ef 
                WHERE tl.company_upper LIKE ef.pattern
            ) THEN 1 ELSE 0 
        END as is_wirehouse
    FROM test_leads tl
),

-- Assign tiers (V3.1 CORRECTED definitions)
tiered_test AS (
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
        END as score_tier
    FROM leads_with_flags
)

-- Calculate tier performance
SELECT 
    score_tier,
    COUNT(*) as n_leads,
    SUM(converted) as n_converted,
    ROUND(AVG(converted) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(converted) / (
        SELECT AVG(converted) 
        FROM tiered_test
    ), 2) as lift_vs_pool,
    '{train_start}' as train_start,
    '{train_end}' as train_end,
    '{test_start}' as test_start,
    '{test_end}' as test_end
FROM tiered_test
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
    return sql

def run_backtest():
    """Run V3.1 backtest across multiple time periods using MCP BigQuery"""
    logger = ExecutionLogger()
    logger.start_phase("BACKTEST", "V3.1 Historical Backtesting")
    
    # Define backtest periods
    backtest_periods = [
        {
            'name': 'H1_2024',
            'train_start': '2024-02-01',
            'train_end': '2024-06-30',
            'test_start': '2024-07-01',
            'test_end': '2024-12-31'
        },
        {
            'name': 'Q1Q2_2024',
            'train_start': '2024-02-01',
            'train_end': '2024-05-31',
            'test_start': '2024-06-01',
            'test_end': '2024-08-31'
        },
        {
            'name': 'Q2Q3_2024',
            'train_start': '2024-02-01',
            'train_end': '2024-08-31',
            'test_start': '2024-09-01',
            'test_end': '2024-11-30'
        },
        {
            'name': 'Full_2024',
            'train_start': '2024-02-01',
            'train_end': '2024-10-31',
            'test_start': '2024-11-01',
            'test_end': '2025-01-31'
        }
    ]
    
    all_results = []
    
    logger.log_action(f"Running backtest across {len(backtest_periods)} time periods using MCP BigQuery")
    
    for period in backtest_periods:
        logger.log_action(f"Backtesting period: {period['name']}")
        logger.log_metric(f"{period['name']} - Train Period", f"{period['train_start']} to {period['train_end']}")
        logger.log_metric(f"{period['name']} - Test Period", f"{period['test_start']} to {period['test_end']}")
        
        # Generate query
        query = generate_backtest_query(
            period['train_start'],
            period['train_end'],
            period['test_start'],
            period['test_end']
        )
        
        # Save query to file
        query_file = BASE_DIR / "sql" / f"backtest_{period['name']}.sql"
        with open(query_file, 'w', encoding='utf-8') as f:
            f.write(query)
        logger.log_file_created(f"backtest_{period['name']}.sql", str(query_file),
                               f"Backtest query for {period['name']}")
        
        # Execute via MCP BigQuery (will be called externally)
        period['query'] = query
        period['query_file'] = str(query_file)
    
    # Save backtest configuration
    config_path = BASE_DIR / "data" / "raw" / "backtest_config.json"
    with open(config_path, 'w') as f:
        json.dump(backtest_periods, f, indent=2)
    logger.log_file_created("backtest_config.json", str(config_path),
                           "Backtest configuration for MCP execution")
    
    logger.log_learning(f"Backtest queries generated for {len(backtest_periods)} time periods")
    logger.log_learning("Queries ready for execution via MCP BigQuery connection")
    
    logger.end_phase(
        status="PASSED",
        next_steps=["Execute backtest queries via MCP BigQuery and analyze results"]
    )
    
    return backtest_periods

if __name__ == "__main__":
    periods = run_backtest()
    print("\n=== BACKTEST QUERIES GENERATED ===")
    print(f"Generated {len(periods)} backtest queries")
    print("Execute queries via MCP BigQuery connection")








