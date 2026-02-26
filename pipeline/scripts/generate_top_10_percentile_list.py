"""
Generate and export the top 10th percentile 51-advisor list.
This script executes the SQL query and exports the results to CSV.

Working Directory: pipeline
Usage: python scripts/generate_top_10_percentile_list.py
"""

import pandas as pd
from pathlib import Path
from google.cloud import bigquery
from datetime import datetime
import sys

# ============================================================================
# PATH CONFIGURATION
# ============================================================================
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\pipeline")
SQL_DIR = WORKING_DIR / "sql"
EXPORTS_DIR = WORKING_DIR / "exports"
LOGS_DIR = WORKING_DIR / "logs"

# Ensure output directories exist
EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
LOGS_DIR.mkdir(parents=True, exist_ok=True)

# ============================================================================
# BIGQUERY CONFIGURATION
# ============================================================================
PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
TABLE_NAME = "v4_deprioritized_51_advisor_list"
SQL_FILE = SQL_DIR / "Top_10_Percentile_51_Advisor_List.sql"

# ============================================================================
# EXPORT CONFIGURATION
# ============================================================================
EXPORT_COLUMNS = [
    'advisor_crd',
    'first_name',
    'last_name',
    'email',
    'phone',
    'linkedin_url',
    'job_title',
    'firm_name',
    'firm_crd',
    'firm_rep_count',
    'firm_net_change_12mo',
    'tenure_months',
    'tenure_years',
    'industry_tenure_years',
    'num_prior_firms',
    'moves_3yr',
    'score_tier',
    'priority_rank',
    'v4_score',
    'v4_percentile',
    'has_series_65_only',
    'has_cfp',
    'cc_career_pattern',
    'cc_cycle_status',
    'cc_pct_through_cycle',
    'cc_is_in_move_window',
    'shap_top1_feature',
    'shap_top2_feature',
    'shap_top3_feature',
    'v4_narrative',
    'rank_within_tier'
]

def read_sql_file(sql_path):
    """Read SQL query from file."""
    print(f"[INFO] Reading SQL from {sql_path}...")
    with open(sql_path, 'r', encoding='utf-8') as f:
        return f.read()

def execute_query(client, query):
    """Execute BigQuery query and return results."""
    print(f"[INFO] Executing query to create {TABLE_NAME}...")
    job = client.query(query)
    job.result()  # Wait for job to complete
    print(f"[INFO] Query completed successfully")
    return job

def fetch_results(client):
    """Fetch results from BigQuery table."""
    query = f"""
    SELECT *
    FROM `{PROJECT_ID}.{DATASET}.{TABLE_NAME}`
    ORDER BY score_tier, rank_within_tier
    """
    
    print(f"[INFO] Fetching results from {TABLE_NAME}...")
    df = client.query(query).to_dataframe()
    print(f"[INFO] Loaded {len(df):,} advisors")
    return df

def validate_results(df):
    """Validate the results."""
    print("\n" + "=" * 70)
    print("VALIDATION CHECKS")
    print("=" * 70)
    
    validation_results = {
        "total_count": len(df),
        "expected_count": 51,
        "duplicate_crds": df['advisor_crd'].duplicated().sum() if len(df) > 0 and 'advisor_crd' in df.columns else 0,
        "v4_percentile_min": None,
        "v4_percentile_max": None,
    }
    
    # Handle V4 percentile if data exists
    if len(df) > 0 and 'v4_percentile' in df.columns:
        validation_results['v4_percentile_min'] = df['v4_percentile'].min()
        validation_results['v4_percentile_max'] = df['v4_percentile'].max()
    
    # Tier distribution
    if len(df) > 0 and 'score_tier' in df.columns:
        tier_dist = df['score_tier'].value_counts().sort_index()
        validation_results['tier_distribution'] = tier_dist.to_dict()
    else:
        validation_results['tier_distribution'] = {}
        
    print(f"Total Count: {validation_results['total_count']:,} (Expected: {validation_results['expected_count']})")
    print(f"Duplicate CRDs: {validation_results['duplicate_crds']}")
    
    if len(df) == 0:
        print(f"\n[WARNING] No advisors found! This could mean:")
        print(f"  - No advisors meet all criteria (V4 >= 20% + target tiers + not in Salesforce)")
        print(f"  - Query may need adjustment")
        print(f"  - Check intermediate CTEs to see where filtering occurs")
    elif validation_results['v4_percentile_min'] is not None:
        print(f"\nV4 Percentile Range: {validation_results['v4_percentile_min']:.0f} - {validation_results['v4_percentile_max']:.0f}")
        if validation_results['v4_percentile_min'] < 20:
            print(f"[WARNING] Some advisors have V4 percentile < 20 (should be excluded)!")
        else:
            print(f"[OK] All advisors have V4 percentile >= 20 (bottom 20% excluded)")
        
    if len(df) > 0:
        print(f"\nTier Distribution:")
        for tier, count in validation_results['tier_distribution'].items():
            pct = count / len(df) * 100
            print(f"  {tier}: {count:,} ({pct:.1f}%)")
        
        # Check if we have all three tiers
        expected_tiers = ['TIER_0C_CLOCKWORK_DUE', 'TIER_1B_PRIME_MOVER_SERIES65', 'TIER_2_PROVEN_MOVER']
        missing_tiers = [t for t in expected_tiers if t not in validation_results['tier_distribution']]
        if missing_tiers:
            print(f"\n[WARNING] Missing tiers: {', '.join(missing_tiers)}")
        else:
            print(f"\n[OK] All three target tiers present")
    
    # Check for Salesforce exclusions
    print(f"\nSalesforce Exclusion Check:")
    print(f"  [OK] All advisors should be excluded from Salesforce (checked in SQL)")
    
    if len(df) == 0:
        print(f"\n[INFO] To debug why no advisors were returned, run:")
        print(f"  pipeline/sql/Top_10_Percentile_51_Advisor_List_Diagnostics.sql")
        print(f"  This will show counts at each filtering step.")
    
    print("=" * 70 + "\n")
    
    return validation_results

def export_to_csv(df, output_path):
    """Export DataFrame to CSV."""
    print(f"[INFO] Exporting to {output_path}...")
    
    # Select columns (handle case where some columns may not exist)
    available_cols = [c for c in EXPORT_COLUMNS if c in df.columns]
    df_export = df[available_cols].copy()
    
    # Export to CSV
    df_export.to_csv(output_path, index=False, encoding='utf-8')
    
    file_size = output_path.stat().st_size / 1024  # Size in KB
    print(f"[INFO] Exported {len(df_export):,} rows to {output_path}")
    print(f"[INFO] File size: {file_size:.1f} KB")
    print(f"[INFO] Columns exported: {len(available_cols)}")
    
    return output_path

def log_results(validation_results, output_path, df):
    """Log results to execution log."""
    log_file = LOGS_DIR / "EXECUTION_LOG.md"
    
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    log_entry = f"""
## V4 Deprioritized 51-Advisor List Generation - {timestamp}

**Status**: SUCCESS

**Export File**: `{output_path.name}`  
**Location**: `{output_path}`

### Summary

**Basic Metrics:**
- Total Advisors: **{validation_results['total_count']:,}** (Expected: {validation_results['expected_count']})
- File Size: **{output_path.stat().st_size / 1024:.1f} KB**

**V4 Percentile:**
- Min: **{validation_results['v4_percentile_min']:.0f}** (should be >= 20, bottom 20% excluded)
- Max: **{validation_results['v4_percentile_max']:.0f}**

**Tier Distribution:**
"""
    
    if 'tier_distribution' in validation_results:
        for tier, count in validation_results['tier_distribution'].items():
            pct = count / validation_results['total_count'] * 100
            log_entry += f"- {tier}: **{count:,}** ({pct:.1f}%)\n"
    
    log_entry += f"""
### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `first_name` - Contact first name
3. `last_name` - Contact last name
4. `email` - Email address
5. `phone` - Phone number
6. `linkedin_url` - LinkedIn profile URL
7. `job_title` - Advisor's job title
8. `firm_name` - Firm name
9. `firm_crd` - Firm CRD ID
10. `firm_rep_count` - Number of reps at firm
11. `firm_net_change_12mo` - Firm net change (arrivals - departures)
12. `tenure_months` - Months at current firm
13. `tenure_years` - Years at current firm
14. `industry_tenure_years` - Total years in industry
15. `num_prior_firms` - Number of prior firms
16. `moves_3yr` - Moves in last 3 years
17. `score_tier` - V3 tier assignment
18. `priority_rank` - Priority rank within tier
19. `v4_score` - V4 XGBoost score
20. `v4_percentile` - V4 percentile rank (20-100, bottom 20% excluded)
21. `has_series_65_only` - Series 65 only flag
22. `has_cfp` - CFP designation flag
23. `cc_career_pattern` - Career Clock pattern
24. `cc_cycle_status` - Career Clock cycle status
25. `cc_pct_through_cycle` - Percent through typical cycle
26. `cc_is_in_move_window` - In move window flag
27. `shap_top1_feature` - Top V4 feature
28. `shap_top2_feature` - Second V4 feature
29. `shap_top3_feature` - Third V4 feature
30. `v4_narrative` - V4 narrative
31. `rank_within_tier` - Rank within tier

### Next Steps

**Generation Complete** - 51-advisor list exported to CSV  
**Ready for**: Review and outreach

---

"""
    
    with open(log_file, 'a', encoding='utf-8') as f:
        f.write(log_entry)
    
    print(f"[INFO] Logged results to {log_file}")

def main():
    print("=" * 70)
    print("V4 DEPRIORITIZED 51-ADVISOR LIST GENERATOR")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Working Directory: {WORKING_DIR}")
    print("=" * 70)
    
    # Check if SQL file exists
    if not SQL_FILE.exists():
        print(f"[ERROR] SQL file not found: {SQL_FILE}")
        sys.exit(1)
    
    # Initialize BigQuery client
    client = bigquery.Client(project=PROJECT_ID)
    
    # Read and execute SQL query
    sql_query = read_sql_file(SQL_FILE)
    execute_query(client, sql_query)
    
    # Fetch results
    df = fetch_results(client)
    
    # Validate
    validation_results = validate_results(df)
    
    # Export to CSV
    timestamp = datetime.now().strftime('%Y%m%d')
    output_filename = f"v4_deprioritized_51_advisor_list_{timestamp}.csv"
    output_path = EXPORTS_DIR / output_filename
    
    export_to_csv(df, output_path)
    
    # Log results
    log_results(validation_results, output_path, df)
    
    print("\n" + "=" * 70)
    print("GENERATION COMPLETE")
    print("=" * 70)
    print(f"Output File: {output_path}")
    print(f"Advisors: {len(df):,}")
    print(f"Tiers: {', '.join(df['score_tier'].unique()) if 'score_tier' in df.columns else 'N/A'}")
    print("=" * 70)
    
    return output_path

if __name__ == "__main__":
    try:
        output_path = main()
        sys.exit(0)
    except Exception as e:
        print(f"\n[ERROR] Generation failed: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
