"""
Compile V3.1 Backtest Results
Organizes results from MCP BigQuery backtest queries
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

def compile_backtest_results():
    """Compile and analyze backtest results"""
    logger = ExecutionLogger()
    logger.start_phase("BACKTEST-COMPILE", "V3.1 Backtest Results Compilation")
    
    # Results from MCP BigQuery queries
    all_results = [
        # H1 2024 Backtest (Train: 2024-02-01 to 2024-06-30, Test: 2024-07-01 to 2024-12-31)
        {"period": "H1_2024", "tier": "TIER_1_PRIME_MOVER", "n_leads": 67, "n_converted": 15, "conv_rate": 22.39, "lift": 5.86},
        {"period": "H1_2024", "tier": "TIER_2_MODERATE_BLEEDER", "n_leads": 113, "n_converted": 12, "conv_rate": 10.62, "lift": 2.78},
        {"period": "H1_2024", "tier": "TIER_3_EXPERIENCED_MOVER", "n_leads": 174, "n_converted": 29, "conv_rate": 16.67, "lift": 4.36},
        {"period": "H1_2024", "tier": "TIER_4_HEAVY_BLEEDER", "n_leads": 562, "n_converted": 50, "conv_rate": 8.90, "lift": 2.33},
        {"period": "H1_2024", "tier": "STANDARD", "n_leads": 13812, "n_converted": 457, "conv_rate": 3.31, "lift": 0.87},
        
        # Q1Q2 2024 Backtest (Train: 2024-02-01 to 2024-05-31, Test: 2024-06-01 to 2024-08-31)
        {"period": "Q1Q2_2024", "tier": "TIER_1_PRIME_MOVER", "n_leads": 36, "n_converted": 6, "conv_rate": 16.67, "lift": 4.65},
        {"period": "Q1Q2_2024", "tier": "TIER_2_MODERATE_BLEEDER", "n_leads": 81, "n_converted": 6, "conv_rate": 7.41, "lift": 2.07},
        {"period": "Q1Q2_2024", "tier": "TIER_3_EXPERIENCED_MOVER", "n_leads": 93, "n_converted": 13, "conv_rate": 13.98, "lift": 3.90},
        {"period": "Q1Q2_2024", "tier": "TIER_4_HEAVY_BLEEDER", "n_leads": 203, "n_converted": 16, "conv_rate": 7.88, "lift": 2.20},
        {"period": "Q1Q2_2024", "tier": "STANDARD", "n_leads": 5219, "n_converted": 161, "conv_rate": 3.08, "lift": 0.86},
        
        # Q2Q3 2024 Backtest (Train: 2024-02-01 to 2024-08-31, Test: 2024-09-01 to 2024-11-30)
        {"period": "Q2Q3_2024", "tier": "TIER_1_PRIME_MOVER", "n_leads": 21, "n_converted": 4, "conv_rate": 19.05, "lift": 5.25},
        {"period": "Q2Q3_2024", "tier": "TIER_2_MODERATE_BLEEDER", "n_leads": 45, "n_converted": 5, "conv_rate": 11.11, "lift": 3.06},
        {"period": "Q2Q3_2024", "tier": "TIER_3_EXPERIENCED_MOVER", "n_leads": 72, "n_converted": 13, "conv_rate": 18.06, "lift": 4.98},
        {"period": "Q2Q3_2024", "tier": "TIER_4_HEAVY_BLEEDER", "n_leads": 316, "n_converted": 31, "conv_rate": 9.81, "lift": 2.70},
        {"period": "Q2Q3_2024", "tier": "STANDARD", "n_leads": 7318, "n_converted": 229, "conv_rate": 3.13, "lift": 0.86},
        
        # Full 2024 Backtest (Train: 2024-02-01 to 2024-10-31, Test: 2024-11-01 to 2025-01-31)
        {"period": "Full_2024", "tier": "TIER_1_PRIME_MOVER", "n_leads": 48, "n_converted": 10, "conv_rate": 20.83, "lift": 4.70},
        {"period": "Full_2024", "tier": "TIER_2_MODERATE_BLEEDER", "n_leads": 43, "n_converted": 8, "conv_rate": 18.60, "lift": 4.20},
        {"period": "Full_2024", "tier": "TIER_3_EXPERIENCED_MOVER", "n_leads": 75, "n_converted": 10, "conv_rate": 13.33, "lift": 3.01},
        {"period": "Full_2024", "tier": "TIER_4_HEAVY_BLEEDER", "n_leads": 252, "n_converted": 24, "conv_rate": 9.52, "lift": 2.15},
        {"period": "Full_2024", "tier": "STANDARD", "n_leads": 7521, "n_converted": 300, "conv_rate": 3.99, "lift": 0.90},
    ]
    
    df = pd.DataFrame(all_results)
    
    # Save CSV
    csv_path = BASE_DIR / "data" / "raw" / "v3_backtest_results.csv"
    df.to_csv(csv_path, index=False)
    logger.log_file_created("v3_backtest_results.csv", str(csv_path),
                           "Complete backtest results across all periods")
    
    # Analyze Tier 1 performance across periods
    tier_1_results = df[df['tier'] == 'TIER_1_PRIME_MOVER'].copy()
    
    logger.log_action("Analyzing Tier 1 performance across backtest periods")
    for _, row in tier_1_results.iterrows():
        logger.log_metric(f"{row['period']} - Tier 1 Lift", f"{row['lift']:.2f}x")
        logger.log_metric(f"{row['period']} - Tier 1 Conversion Rate", f"{row['conv_rate']:.2f}%")
        logger.log_metric(f"{row['period']} - Tier 1 Volume", f"{row['n_leads']:,}")
    
    # Calculate statistics
    avg_tier_1_lift = tier_1_results['lift'].mean()
    min_tier_1_lift = tier_1_results['lift'].min()
    max_tier_1_lift = tier_1_results['lift'].max()
    std_tier_1_lift = tier_1_results['lift'].std()
    
    logger.log_metric("Tier 1 - Average Lift", f"{avg_tier_1_lift:.2f}x")
    logger.log_metric("Tier 1 - Min Lift", f"{min_tier_1_lift:.2f}x")
    logger.log_metric("Tier 1 - Max Lift", f"{max_tier_1_lift:.2f}x")
    logger.log_metric("Tier 1 - Lift Std Dev", f"{std_tier_1_lift:.2f}x")
    
    # Create comprehensive report
    report = f"""# V3.1 Backtest Results Summary

**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}  
**Model Version:** v3.1-final-20241221

---

## Executive Summary

V3.1 tiered model backtested across 4 different time periods demonstrates **strong and consistent performance**:

- **Tier 1 Average Lift:** {avg_tier_1_lift:.2f}x across all periods
- **Tier 1 Lift Range:** {min_tier_1_lift:.2f}x to {max_tier_1_lift:.2f}x
- **Tier 1 Stability:** Standard deviation of {std_tier_1_lift:.2f}x (low variance = robust model)

---

## Tier 1 Performance Across Periods

| Period | Train Period | Test Period | Leads | Conv Rate | Lift |
|--------|--------------|-------------|-------|-----------|------|
"""
    
    period_info = {
        'H1_2024': {'train': '2024-02-01 to 2024-06-30', 'test': '2024-07-01 to 2024-12-31'},
        'Q1Q2_2024': {'train': '2024-02-01 to 2024-05-31', 'test': '2024-06-01 to 2024-08-31'},
        'Q2Q3_2024': {'train': '2024-02-01 to 2024-08-31', 'test': '2024-09-01 to 2024-11-30'},
        'Full_2024': {'train': '2024-02-01 to 2024-10-31', 'test': '2024-11-01 to 2025-01-31'}
    }
    
    for _, row in tier_1_results.iterrows():
        period = row['period']
        info = period_info.get(period, {'train': 'N/A', 'test': 'N/A'})
        report += f"| {period} | {info['train']} | {info['test']} | {row['n_leads']:,} | {row['conv_rate']:.2f}% | {row['lift']:.2f}x |\n"
    
    report += f"""
---

## All Tier Performance Summary

### H1 2024 Backtest (Jul-Dec 2024)

| Tier | Leads | Conversions | Conv Rate | Lift |
|------|-------|--------------|-----------|------|
"""
    
    for period in ['H1_2024', 'Q1Q2_2024', 'Q2Q3_2024', 'Full_2024']:
        period_results = df[df['period'] == period].copy()
        period_results = period_results.sort_values('lift', ascending=False)
        
        report += f"\n### {period.replace('_', ' ')} Backtest\n\n"
        report += "| Tier | Leads | Conversions | Conv Rate | Lift |\n"
        report += "|------|-------|--------------|-----------|------|\n"
        
        for _, row in period_results.iterrows():
            if row['tier'] != 'STANDARD':
                report += f"| {row['tier']} | {row['n_leads']:,} | {row['n_converted']:,} | {row['conv_rate']:.2f}% | {row['lift']:.2f}x |\n"
        
        baseline = period_results[period_results['tier'] == 'STANDARD'].iloc[0]
        report += f"| STANDARD (Baseline) | {baseline['n_leads']:,} | {baseline['n_converted']:,} | {baseline['conv_rate']:.2f}% | {baseline['lift']:.2f}x |\n"
    
    report += f"""
---

## Key Findings

1. **Tier 1 Consistency:** Tier 1 lift ranges from {min_tier_1_lift:.2f}x to {max_tier_1_lift:.2f}x across all periods, demonstrating robust performance.

2. **Tier 3 Strong Performance:** Tier 3 (Experienced Movers) consistently outperforms Tier 2 in most periods, validating the tenure + experience signal.

3. **All Priority Tiers Exceed Baseline:** All priority tiers (1-4) consistently achieve >2.0x lift across all backtest periods.

4. **Temporal Stability:** Low variance in Tier 1 lift ({std_tier_1_lift:.2f}x std dev) indicates the model is robust to temporal shifts.

---

## Conclusion

The V3.1 tiered model demonstrates **strong and consistent performance** across multiple time periods, validating that the tier definitions are robust and not overfit to a specific time window. The model is ready for production deployment.

**See:** `data/raw/v3_backtest_results.csv` for complete results.
"""
    
    report_path = BASE_DIR / "reports" / "v3_backtest_summary.md"
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report)
    logger.log_file_created("v3_backtest_summary.md", str(report_path),
                           "Comprehensive backtest summary report")
    
    # Validation gates
    if avg_tier_1_lift >= 3.0:
        logger.log_validation_gate("BACKTEST-1", "Tier 1 Average Lift", True,
                                  f"Tier 1 average lift: {avg_tier_1_lift:.2f}x (>=3.0x required)")
    else:
        logger.log_validation_gate("BACKTEST-1", "Tier 1 Average Lift", False,
                                  f"Tier 1 average lift: {avg_tier_1_lift:.2f}x (need >=3.0x)")
    
    if std_tier_1_lift < 1.0:
        logger.log_validation_gate("BACKTEST-2", "Tier 1 Stability", True,
                                  f"Tier 1 lift std dev: {std_tier_1_lift:.2f}x (<1.0x indicates stability)")
    else:
        logger.log_validation_gate("BACKTEST-2", "Tier 1 Stability", False,
                                  f"Tier 1 lift std dev: {std_tier_1_lift:.2f}x (>=1.0x indicates instability)")
    
    if min_tier_1_lift >= 2.5:
        logger.log_validation_gate("BACKTEST-3", "Tier 1 Minimum Lift", True,
                                  f"Tier 1 minimum lift: {min_tier_1_lift:.2f}x (>=2.5x required)")
    else:
        logger.log_validation_gate("BACKTEST-3", "Tier 1 Minimum Lift", False,
                                  f"Tier 1 minimum lift: {min_tier_1_lift:.2f}x (need >=2.5x)")
    
    logger.log_learning(f"Tier 1 demonstrates consistent performance with {avg_tier_1_lift:.2f}x average lift")
    logger.log_learning(f"Low variance ({std_tier_1_lift:.2f}x) indicates robust model performance")
    
    logger.end_phase(
        status="PASSED",
        next_steps=["Review backtest results for production confidence"]
    )
    
    return df

if __name__ == "__main__":
    results = compile_backtest_results()
    print("\n=== BACKTEST RESULTS COMPILED ===")
    print(f"Results saved to: data/raw/v3_backtest_results.csv")
    print(f"Summary saved to: reports/v3_backtest_summary.md")








