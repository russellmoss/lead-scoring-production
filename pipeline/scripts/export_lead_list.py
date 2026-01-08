"""
Export lead list from BigQuery to CSV for Salesforce import.
Run after Step 3 (hybrid lead list generation with V4 upgrade path).

UPDATED: Includes V4 upgrade tracking column

Working Directory: Lead_List_Generation
Usage: python scripts/export_lead_list.py
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
TABLE_NAME = "january_2026_lead_list"
EXCLUDED_TABLE_NAME = "january_2026_excluded_v3_v4_disagreement"

# ============================================================================
# EXPORT CONFIGURATION (UPDATED - includes V4 upgrade columns)
# ============================================================================
EXPORT_COLUMNS = [
    'advisor_crd',
    'salesforce_lead_id',
    'first_name',
    'last_name',
    'job_title',
    'email',
    'phone',
    'linkedin_url',
    'firm_name',
    'firm_crd',
    'score_tier',
    'original_v3_tier',
    'expected_rate_pct',
    'score_narrative',
    'v4_score',
    'v4_percentile',
    'is_high_v4_standard',
    'v4_status',
    'shap_top1_feature',
    'shap_top2_feature',
    'shap_top3_feature',
    'prospect_type',
    'sga_owner',                # NEW! SGA assignment
    'sga_id',                   # NEW! SGA Salesforce ID
    'list_rank'
]

def fetch_lead_list(client):
    """Fetch lead list from BigQuery."""
    query = f"""
    SELECT *
    FROM `{PROJECT_ID}.{DATASET}.{TABLE_NAME}`
    ORDER BY list_rank
    """
    
    print(f"[INFO] Fetching lead list from {TABLE_NAME}...")
    df = client.query(query).to_dataframe()
    print(f"[INFO] Loaded {len(df):,} leads")
    return df

def fetch_excluded_leads(client):
    """Fetch excluded V3/V4 disagreement leads from BigQuery."""
    # First try the excluded table (created by separate SQL script)
    query = f"""
    SELECT *
    FROM `{PROJECT_ID}.{DATASET}.{EXCLUDED_TABLE_NAME}`
    ORDER BY score_tier, v4_percentile
    """
    
    print(f"[INFO] Fetching excluded leads from {EXCLUDED_TABLE_NAME}...")
    try:
        df = client.query(query).to_dataframe()
        if len(df) > 0:
            print(f"[INFO] Loaded {len(df):,} excluded leads from table")
            return df
        else:
            print(f"[INFO] Excluded table exists but is empty (filter working correctly)")
            # Try to calculate from v4 scores to get actual excluded leads
            return calculate_excluded_from_scores(client)
    except Exception as e:
        # If table doesn't exist, calculate from v4 scores
        print(f"[INFO] Excluded table not found, calculating from v4 scores...")
        return calculate_excluded_from_scores(client)

def calculate_excluded_from_scores(client):
    """Calculate excluded leads by querying v4 scores and applying tier logic."""
    # This query identifies leads that match exclusion criteria by querying
    # the v4_prospect_scores and reconstructing which would be Tier 1
    # NOTE: This is an approximation - for exact list, need to capture during main query
    query = f"""
    WITH tier1_leads AS (
        SELECT 
            c.RIA_CONTACT_CRD_ID as crd,
            c.CONTACT_FIRST_NAME as first_name,
            c.CONTACT_LAST_NAME as last_name,
            c.EMAIL as email,
            COALESCE(c.MOBILE_PHONE_NUMBER, c.OFFICE_PHONE_NUMBER) as phone,
            c.PRIMARY_FIRM_NAME as firm_name,
            SAFE_CAST(c.PRIMARY_FIRM AS INT64) as firm_crd,
            -- Simplified tier logic to identify Tier 1 leads
            CASE 
                WHEN (DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, YEAR) BETWEEN 1 AND 4 
                      AND DATE_DIFF(CURRENT_DATE(), COALESCE(am.career_start_date, c.PRIMARY_FIRM_START_DATE), YEAR) >= 5 
                      AND COALESCE(fm.firm_net_change_12mo, 0) < 0 
                      AND (c.CONTACT_BIO LIKE '%CFP%' OR c.TITLE_NAME LIKE '%CFP%')
                      AND SAFE_CAST(c.PRIMARY_FIRM AS INT64) NOT IN (318493, 168652)) 
                THEN 'TIER_1A_PRIME_MOVER_CFP'
                WHEN (DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, YEAR) BETWEEN 1 AND 3 
                      AND DATE_DIFF(CURRENT_DATE(), COALESCE(am.career_start_date, c.PRIMARY_FIRM_START_DATE), YEAR) BETWEEN 5 AND 15 
                      AND COALESCE(fm.firm_net_change_12mo, 0) < 0 
                      AND c.REP_LICENSES LIKE '%Series 65%' 
                      AND c.REP_LICENSES NOT LIKE '%Series 7%'
                      AND SAFE_CAST(c.PRIMARY_FIRM AS INT64) NOT IN (318493, 168652)) 
                THEN 'TIER_1B_PRIME_MOVER_SERIES65'
                WHEN (DATE_DIFF(CURRENT_DATE(), c.PRIMARY_FIRM_START_DATE, YEAR) BETWEEN 1 AND 3 
                      AND DATE_DIFF(CURRENT_DATE(), COALESCE(am.career_start_date, c.PRIMARY_FIRM_START_DATE), YEAR) BETWEEN 5 AND 15 
                      AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                      AND SAFE_CAST(c.PRIMARY_FIRM AS INT64) NOT IN (318493, 168652)) 
                THEN 'TIER_1_PRIME_MOVER'
                WHEN ((UPPER(c.TITLE_NAME) LIKE '%WEALTH MANAGER%'
                       OR UPPER(c.TITLE_NAME) LIKE '%DIRECTOR%WEALTH%'
                       OR UPPER(c.TITLE_NAME) LIKE '%SENIOR WEALTH ADVISOR%')
                      AND COALESCE(fm.firm_net_change_12mo, 0) < 0
                      AND SAFE_CAST(c.PRIMARY_FIRM AS INT64) NOT IN (318493, 168652)) 
                THEN 'TIER_1F_HV_WEALTH_BLEEDER'
                ELSE NULL
            END as score_tier,
            sf.Id as existing_lead_id
        FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        LEFT JOIN (
            SELECT RIA_CONTACT_CRD_ID as crd, MIN(PREVIOUS_REGISTRATION_COMPANY_START_DATE) as career_start_date
            FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
            GROUP BY RIA_CONTACT_CRD_ID
        ) am ON c.RIA_CONTACT_CRD_ID = am.crd
        LEFT JOIN (
            SELECT
                h.firm_crd,
                COALESCE(a.arrivals_12mo, 0) - COALESCE(d.departures_12mo, 0) as firm_net_change_12mo
            FROM (
                SELECT SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd, COUNT(DISTINCT RIA_CONTACT_CRD_ID) as current_reps
                FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
                WHERE PRIMARY_FIRM IS NOT NULL
                GROUP BY PRIMARY_FIRM
            ) h
            LEFT JOIN (
                SELECT SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd, COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
                FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
                WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
                GROUP BY 1
            ) d ON h.firm_crd = d.firm_crd
            LEFT JOIN (
                SELECT SAFE_CAST(PRIMARY_FIRM AS INT64) as firm_crd, COUNT(DISTINCT RIA_CONTACT_CRD_ID) as arrivals_12mo
                FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
                WHERE PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
                GROUP BY 1
            ) a ON h.firm_crd = a.firm_crd
            WHERE h.current_reps >= 20
        ) fm ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = fm.firm_crd
        LEFT JOIN (
            SELECT DISTINCT 
                SAFE_CAST(REGEXP_REPLACE(CAST(FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as crd,
                Id
            FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
            WHERE FA_CRD__c IS NOT NULL AND IsDeleted = false
        ) sf ON c.RIA_CONTACT_CRD_ID = sf.crd
        WHERE c.PRODUCING_ADVISOR = TRUE
          AND c.CONTACT_FIRST_NAME IS NOT NULL
          AND c.CONTACT_LAST_NAME IS NOT NULL
    )
    SELECT 
        t1.crd as advisor_crd,
        t1.existing_lead_id as salesforce_lead_id,
        t1.first_name,
        t1.last_name,
        CONCAT(t1.first_name, ' ', t1.last_name) as name,
        t1.email,
        t1.phone,
        t1.firm_name,
        t1.firm_crd,
        t1.score_tier,
        t1.score_tier as final_tier,
        ROUND(v4.v4_score, 4) as v4_score,
        v4.v4_percentile,
        0.0 as expected_rate_pct,  -- Would need to calculate from tier
                'V3_V4_DISAGREEMENT: Tier 1 with V4 < 70th percentile' as exclusion_reason
    FROM tier1_leads t1
    INNER JOIN `{PROJECT_ID}.{DATASET}.v4_prospect_scores` v4 ON t1.crd = v4.crd
    WHERE t1.score_tier IS NOT NULL
      AND v4.v4_percentile < 70
    ORDER BY t1.score_tier, v4.v4_percentile
    """
    
    try:
        df = client.query(query).to_dataframe()
        if len(df) > 0:
            print(f"[INFO] Calculated {len(df):,} excluded leads from v4 scores")
        return df
    except Exception as e:
        print(f"[WARNING] Could not calculate excluded leads: {str(e)[:200]}")
        return pd.DataFrame()

def validate_export(df, df_excluded=None):
    """Validate the exported data."""
    if df_excluded is None:
        df_excluded = pd.DataFrame()
    
    print("\n" + "=" * 70)
    print("VALIDATION CHECKS")
    print("=" * 70)
    
    # Check if is_high_v4_standard column exists
    has_high_v4_col = 'is_high_v4_standard' in df.columns
    high_v4_standard_count = df['is_high_v4_standard'].sum() if has_high_v4_col else 0
    # Also check for legacy is_v4_upgrade column for backward compatibility
    has_v4_upgrade_col = 'is_v4_upgrade' in df.columns
    v4_upgrade_count = df['is_v4_upgrade'].sum() if has_v4_upgrade_col else 0
    
    validation_results = {
        "row_count": len(df),
        "expected_rows": 2400,
        "duplicate_crds": df['advisor_crd'].duplicated().sum(),
        "has_job_title": df['job_title'].notna().sum() if 'job_title' in df.columns else 0,
        "has_narrative": df['score_narrative'].notna().sum() if 'score_narrative' in df.columns else 0,
        "has_linkedin": (df['linkedin_url'].notna() & (df['linkedin_url'] != '')).sum(),
        "high_v4_standard_count": high_v4_standard_count,
        "v4_upgrade_count": v4_upgrade_count,  # Legacy support
    }
    
    validation_results['job_title_pct'] = validation_results['has_job_title'] / len(df) * 100 if len(df) > 0 else 0
    validation_results['narrative_pct'] = validation_results['has_narrative'] / len(df) * 100 if len(df) > 0 else 0
    validation_results['linkedin_pct'] = validation_results['has_linkedin'] / len(df) * 100 if len(df) > 0 else 0
    validation_results['high_v4_standard_pct'] = validation_results['high_v4_standard_count'] / len(df) * 100 if len(df) > 0 else 0
    validation_results['v4_upgrade_pct'] = validation_results['v4_upgrade_count'] / len(df) * 100 if len(df) > 0 else 0  # Legacy
    
    # Print validation results
    print(f"Row Count: {validation_results['row_count']:,}")
    print(f"Duplicate CRDs: {validation_results['duplicate_crds']}")
    
    print(f"\nJob Title Coverage: {validation_results['has_job_title']:,} ({validation_results['job_title_pct']:.1f}%)")
    print(f"Narrative Coverage: {validation_results['has_narrative']:,} ({validation_results['narrative_pct']:.1f}%)")
    print(f"LinkedIn Coverage: {validation_results['has_linkedin']:,} ({validation_results['linkedin_pct']:.1f}%)")
    
    if high_v4_standard_count > 0:
        print(f"\nHigh-V4 STANDARD (Backfill): {validation_results['high_v4_standard_count']:,} ({validation_results['high_v4_standard_pct']:.1f}%)")
    if v4_upgrade_count > 0:
        print(f"Legacy V4 Upgrades: {validation_results['v4_upgrade_count']:,} ({validation_results['v4_upgrade_pct']:.1f}%) [Note: V4_UPGRADE tier removed in optimization]")
    
    # Check for excluded firms
    savvy_count = len(df[df['firm_crd'] == 318493]) if 'firm_crd' in df.columns else 0
    ritholtz_count = len(df[df['firm_crd'] == 168652]) if 'firm_crd' in df.columns else 0
    
    print(f"\nExcluded Firm Check:")
    print(f"  Savvy (CRD 318493): {savvy_count} {'[OK]' if savvy_count == 0 else '[FAIL]'}")
    print(f"  Ritholtz (CRD 168652): {ritholtz_count} {'[OK]' if ritholtz_count == 0 else '[FAIL]'}")
    
    # Tier distribution
    print(f"\nTier Distribution:")
    if 'score_tier' in df.columns:
        tier_dist = df['score_tier'].value_counts().sort_index()
        for tier, count in tier_dist.items():
            pct = count / len(df) * 100
            print(f"  {tier}: {count:,} ({pct:.1f}%)")
    
    # Check for V3/V4 disagreement leads (should be 0 in final list)
    if 'score_tier' in df.columns and 'v4_percentile' in df.columns:
        tier1_tiers = ['TIER_1B_PRIME_ZERO_FRICTION', 'TIER_1A_PRIME_MOVER_CFP', 
                      'TIER_1G_ENHANCED_SWEET_SPOT', 'TIER_1B_PRIME_MOVER_SERIES65',
                      'TIER_1G_GROWTH_STAGE', 'TIER_1_PRIME_MOVER', 'TIER_1F_HV_WEALTH_BLEEDER']
        disagreement_count = len(df[
            df['score_tier'].isin(tier1_tiers) & 
            (df['v4_percentile'] < 70)
        ])
        if disagreement_count > 0:
            print(f"\n[WARNING] {disagreement_count} Tier 1 leads with V4 < 70th percentile found in final list!")
        else:
            print(f"\n[OK] V3/V4 Disagreement Filter: All Tier 1 leads have V4 >= 70th percentile")
    
    # Show excluded leads summary
    if len(df_excluded) > 0:
        print(f"\n[INFO] V3/V4 Disagreement Exclusions:")
        print(f"  Total Excluded: {len(df_excluded):,} leads")
        if 'score_tier' in df_excluded.columns:
            excluded_by_tier = df_excluded['score_tier'].value_counts().sort_index()
            print(f"  Excluded by Tier:")
            for tier, count in excluded_by_tier.items():
                print(f"    {tier}: {count:,}")
        if 'name' in df_excluded.columns or ('first_name' in df_excluded.columns and 'last_name' in df_excluded.columns):
            print(f"  Sample Excluded Leads:")
            sample_size = min(5, len(df_excluded))
            for idx in range(sample_size):
                if 'name' in df_excluded.columns:
                    name = df_excluded.iloc[idx]['name']
                else:
                    name = f"{df_excluded.iloc[idx]['first_name']} {df_excluded.iloc[idx]['last_name']}"
                tier = df_excluded.iloc[idx].get('score_tier', 'N/A')
                v4_pct = df_excluded.iloc[idx].get('v4_percentile', 'N/A')
                print(f"    - {name} ({tier}, V4: {v4_pct}th percentile)")
    
    # SGA distribution
    if 'sga_owner' in df.columns:
        print(f"\nSGA Distribution:")
        sga_dist = df['sga_owner'].value_counts().sort_index()
        total_sgas = len(sga_dist)
        expected_per_sga = len(df) / total_sgas if total_sgas > 0 else 0
        
        print(f"  Total SGAs: {total_sgas}")
        print(f"  Expected per SGA: {expected_per_sga:.0f} leads")
        print(f"  Actual distribution:")
        for sga, count in sga_dist.items():
            diff = count - expected_per_sga
            print(f"    {sga}: {count:,} leads ({diff:+.0f} from expected)")
        
        # Check balance
        min_count = sga_dist.min()
        max_count = sga_dist.max()
        print(f"\n  Balance: Min={min_count}, Max={max_count}, Diff={max_count-min_count}")
        
        # Average expected conversion rate per SGA
        print(f"\n  Avg Expected Conversion Rate by SGA:")
        for sga in sga_dist.index:
            sga_leads = df[df['sga_owner'] == sga]
            if len(sga_leads) > 0 and 'expected_rate_pct' in sga_leads.columns:
                avg_rate = sga_leads['expected_rate_pct'].mean()
                print(f"    {sga}: {avg_rate:.2f}%")
    
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

def log_results(validation_results, output_path, df, df_excluded=None, excluded_path=None):
    """Log export results to execution log."""
    log_file = LOGS_DIR / "EXECUTION_LOG.md"
    
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    savvy_count = len(df[df['firm_crd'] == 318493]) if 'firm_crd' in df.columns else 0
    ritholtz_count = len(df[df['firm_crd'] == 168652]) if 'firm_crd' in df.columns else 0
    
    log_entry = f"""
## Step 4: Export Lead List to CSV - {timestamp}

**Status**: SUCCESS

**Export File**: `{output_path.name}`  
**Location**: `{output_path}`

### Export Summary

**Basic Metrics:**
- Total Rows: **{validation_results['row_count']:,}**
- File Size: **{output_path.stat().st_size / 1024:.1f} KB**

**New Features:**
- Job Title Coverage: **{validation_results['has_job_title']:,}** ({validation_results['job_title_pct']:.1f}%)
- Narrative Coverage: **{validation_results['has_narrative']:,}** ({validation_results['narrative_pct']:.1f}%)
- LinkedIn Coverage: **{validation_results['has_linkedin']:,}** ({validation_results['linkedin_pct']:.1f}%)

**V4 Upgrade Path:**
- High-V4 STANDARD (Backfill): **{validation_results['high_v4_standard_count']:,}** ({validation_results['high_v4_standard_pct']:.1f}%)
- Legacy V4 Upgrades: **{validation_results['v4_upgrade_count']:,}** ({validation_results['v4_upgrade_pct']:.1f}%) [Note: V4_UPGRADE tier removed in optimization]

**Firm Exclusions:**
- Savvy (CRD 318493): **{savvy_count}** {'EXCLUDED' if savvy_count == 0 else 'PRESENT'}
- Ritholtz (CRD 168652): **{ritholtz_count}** {'EXCLUDED' if ritholtz_count == 0 else 'PRESENT'}

**Tier Distribution:**
"""
    
    if 'score_tier' in df.columns:
        tier_dist = df['score_tier'].value_counts().sort_index()
        for tier, count in tier_dist.items():
            pct = count / len(df) * 100
            marker = " [BACKFILL]" if tier == 'STANDARD_HIGH_V4' else (" [LEGACY]" if tier == 'V4_UPGRADE' else "")
            log_entry += f"- {tier}: **{count:,}** ({pct:.1f}%){marker}\n"
    
    # Add excluded leads info
    if df_excluded is not None and len(df_excluded) > 0:
        log_entry += f"""
**V3/V4 Disagreement Exclusions:**
- Excluded Leads: **{len(df_excluded):,}** (Tier 1 with V4 < 70th percentile)
- Exclusion File: **{excluded_path.name if excluded_path else 'N/A'}**
"""
        if 'score_tier' in df_excluded.columns:
            log_entry += "\n**Excluded by Tier:**\n"
            excluded_by_tier = df_excluded['score_tier'].value_counts().sort_index()
            for tier, count in excluded_by_tier.items():
                log_entry += f"- {tier}: **{count:,}**\n"
    
    log_entry += f"""
### Export Columns

The CSV includes the following columns:
1. `advisor_crd` - FINTRX CRD ID
2. `salesforce_lead_id` - Salesforce Lead ID (if exists)
3. `first_name` - Contact first name
4. `last_name` - Contact last name
5. `job_title` - **NEW!** Advisor's job title from FINTRX
6. `email` - Email address
7. `phone` - Phone number
8. `linkedin_url` - LinkedIn profile URL
9. `firm_name` - Firm name
10. `firm_crd` - Firm CRD ID
11. `score_tier` - Final tier (V3 tier or STANDARD_HIGH_V4 for backfill)
12. `original_v3_tier` - Original V3 tier (STANDARD for backfill leads)
13. `expected_rate_pct` - Expected conversion rate (%)
14. `score_narrative` - **NEW!** Human-readable explanation (V3 rules or V4 SHAP)
15. `v4_score` - V4 XGBoost score
16. `v4_percentile` - V4 percentile rank (1-100)
17. `is_high_v4_standard` - **1 = High-V4 STANDARD (backfill), 0 = V3 tier lead**
18. `v4_status` - Description of V4 status
19. `shap_top1_feature` - **NEW!** Most important ML feature
20. `shap_top2_feature` - **NEW!** Second most important feature
21. `shap_top3_feature` - **NEW!** Third most important feature
22. `prospect_type` - NEW_PROSPECT or recyclable
23. `list_rank` - Overall ranking in list

### Next Steps

**Step 4 Complete** - Lead list exported to CSV with SHAP narratives, job titles, and firm exclusions  
**Ready for**: Salesforce import and SDR outreach

---

"""
    
    with open(log_file, 'a', encoding='utf-8') as f:
        f.write(log_entry)
    
    print(f"[INFO] Logged results to {log_file}")

def main():
    print("=" * 70)
    print("EXPORT LEAD LIST TO CSV (V4 UPGRADE PATH)")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Working Directory: {WORKING_DIR}")
    print("=" * 70)
    
    # Initialize BigQuery client
    client = bigquery.Client(project=PROJECT_ID)
    
    # Fetch data
    df = fetch_lead_list(client)
    
    # Fetch excluded leads
    df_excluded = fetch_excluded_leads(client)
    
    # Validate
    validation_results = validate_export(df, df_excluded)
    
    # Export main lead list to CSV
    timestamp = datetime.now().strftime('%Y%m%d')
    output_filename = f"january_2026_lead_list_{timestamp}.csv"
    output_path = EXPORTS_DIR / output_filename
    
    export_to_csv(df, output_path)
    
    # Export excluded leads to CSV
    if len(df_excluded) > 0:
        excluded_filename = f"excluded_v3_v4_disagreement_leads_{timestamp}.csv"
        excluded_path = EXPORTS_DIR / excluded_filename
        
        # Select columns for excluded leads export
        excluded_columns = [
            'advisor_crd', 'salesforce_lead_id', 'name', 'first_name', 'last_name',
            'email', 'phone', 'firm_name', 'firm_crd', 'score_tier', 
            'original_v3_tier', 'v4_score', 'v4_percentile', 
            'expected_rate_pct', 'exclusion_reason'
        ]
        
        # Only export columns that exist
        available_cols = [col for col in excluded_columns if col in df_excluded.columns]
        df_excluded_export = df_excluded[available_cols].copy()
        
        df_excluded_export.to_csv(excluded_path, index=False)
        print(f"[INFO] Exported {len(df_excluded):,} excluded leads to {excluded_path}")
        print(f"[INFO] File size: {excluded_path.stat().st_size / 1024:.1f} KB")
    else:
        excluded_path = None
    
    # Log results
    log_results(validation_results, output_path, df, df_excluded, excluded_path)
    
    print("\n" + "=" * 70)
    print("EXPORT COMPLETE")
    print("=" * 70)
    print(f"Main Lead List: {output_path}")
    print(f"Rows: {len(df):,}")
    if excluded_path:
        print(f"\nExcluded Leads: {excluded_path}")
        print(f"Rows: {len(df_excluded):,}")
    print(f"Includes: job_title, score_narrative, SHAP features")
    print("=" * 70)
    
    return output_path

if __name__ == "__main__":
    try:
        output_path = main()
        sys.exit(0)
    except Exception as e:
        print(f"\n[ERROR] Export failed: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)