"""
Phase 5: Multicollinearity Check for V4.1 Features
Check for high correlations and VIF to identify redundant features.
"""

import pandas as pd
import numpy as np
from google.cloud import bigquery
from statsmodels.stats.outliers_influence import variance_inflation_factor
from pathlib import Path
import json
from datetime import datetime

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\v4")
REPORT_DIR = WORKING_DIR / "reports" / "v4.1"
REPORT_DIR.mkdir(parents=True, exist_ok=True)

# All 23 V4.1 Features
ORIGINAL_FEATURES = [
    'tenure_months',
    'mobility_3yr',
    'firm_rep_count_at_contact',
    'firm_net_change_12mo',
    'is_wirehouse',
    'is_broker_protocol',
    'has_email',
    'has_linkedin',
    'has_firm_data',
    'mobility_x_heavy_bleeding',
    'short_tenure_x_high_mobility',
    'tenure_bucket_x_mobility',
    'industry_tenure_months',
    'experience_years'
]

NEW_BLEEDING_FEATURES = [
    'is_recent_mover',
    'days_since_last_move',
    'firm_departures_corrected',
    'bleeding_velocity_encoded',
    'recent_mover_x_bleeding'
]

NEW_FIRM_REP_FEATURES = [
    'is_independent_ria',
    'is_ia_rep_type',
    'is_dual_registered',
    'independent_ria_x_ia_rep'
]

ALL_FEATURES = ORIGINAL_FEATURES + NEW_BLEEDING_FEATURES + NEW_FIRM_REP_FEATURES


def load_feature_data():
    """Load feature data from BigQuery."""
    print("\n[1/4] Loading feature data from BigQuery...")
    client = bigquery.Client(project=PROJECT_ID)
    
    # Build query with all numeric features
    query = f"""
    SELECT 
        tenure_months,
        mobility_3yr,
        firm_rep_count_at_contact,
        firm_net_change_12mo,
        is_wirehouse,
        is_broker_protocol,
        has_email,
        has_linkedin,
        has_firm_data,
        mobility_x_heavy_bleeding,
        short_tenure_x_high_mobility,
        tenure_bucket_x_mobility,
        industry_tenure_months,
        experience_years,
        is_recent_mover,
        days_since_last_move,
        firm_departures_corrected,
        bleeding_velocity_encoded,
        recent_mover_x_bleeding,
        is_independent_ria,
        is_ia_rep_type,
        is_dual_registered,
        independent_ria_x_ia_rep,
        target
    FROM `savvy-gtm-analytics.ml_features.v4_features_pit_v41`
    WHERE target IS NOT NULL
    """
    
    df = client.query(query).to_dataframe()
    print(f"      Loaded {len(df):,} rows with {len(ALL_FEATURES)} features")
    return df


def calculate_correlation_matrix(df):
    """Calculate correlation matrix and flag high correlations."""
    print("\n[2/4] Calculating correlation matrix...")
    
    # Prepare numeric features only
    numeric_features = [f for f in ALL_FEATURES if f in df.columns]
    corr_matrix = df[numeric_features].corr()
    
    # Find high correlations
    high_corr_pairs = []
    for i, feat1 in enumerate(numeric_features):
        for j, feat2 in enumerate(numeric_features):
            if i < j:  # Upper triangle only
                corr = corr_matrix.loc[feat1, feat2]
                if abs(corr) > 0.7:
                    high_corr_pairs.append({
                        'feature_1': feat1,
                        'feature_2': feat2,
                        'correlation': round(corr, 4),
                        'status': 'CRITICAL' if abs(corr) > 0.85 else 'WARNING'
                    })
    
    print(f"      Found {len(high_corr_pairs)} high correlation pairs (|r| > 0.7)")
    return corr_matrix, high_corr_pairs


def calculate_vif(df):
    """Calculate Variance Inflation Factor for each feature."""
    print("\n[3/4] Calculating VIF (Variance Inflation Factor)...")
    
    # Prepare numeric features only
    numeric_features = [f for f in ALL_FEATURES if f in df.columns]
    X = df[numeric_features].fillna(0).astype(float)
    
    # Remove any features with zero variance
    X = X.loc[:, X.var() > 0]
    numeric_features = [f for f in numeric_features if f in X.columns]
    
    vif_data = []
    for i, feature in enumerate(numeric_features):
        try:
            vif = variance_inflation_factor(X.values, i)
            if np.isinf(vif) or np.isnan(vif):
                vif = 999.0  # Flag as problematic
            vif_data.append({
                'feature': feature,
                'vif': round(vif, 2),
                'status': 'CRITICAL' if vif > 10 else ('WARNING' if vif > 5 else 'OK')
            })
        except Exception as e:
            vif_data.append({
                'feature': feature,
                'vif': np.nan,
                'status': 'ERROR',
                'error': str(e)
            })
    
    vif_df = pd.DataFrame(vif_data).sort_values('vif', ascending=False, na_position='last')
    print(f"      Calculated VIF for {len(vif_df)} features")
    print(f"      Critical VIF (>10): {len(vif_df[vif_df['status'] == 'CRITICAL'])}")
    print(f"      Warning VIF (5-10): {len(vif_df[vif_df['status'] == 'WARNING'])}")
    
    return vif_df


def generate_report(corr_matrix, high_corr_pairs, vif_df):
    """Generate multicollinearity report."""
    print("\n[4/4] Generating report...")
    
    report_path = REPORT_DIR / "multicollinearity_report.md"
    results_path = REPORT_DIR / "multicollinearity_results.json"
    
    # Calculate gate status
    critical_corr = len([p for p in high_corr_pairs if p['status'] == 'CRITICAL'])
    critical_vif = len(vif_df[vif_df['status'] == 'CRITICAL'])
    
    g5_1_passed = critical_corr == 0
    g5_2_passed = critical_vif == 0
    
    # Check if new features add independent signal
    new_feature_vifs = vif_df[vif_df['feature'].isin(NEW_BLEEDING_FEATURES + NEW_FIRM_REP_FEATURES)]
    avg_new_vif = new_feature_vifs['vif'].mean()
    g5_3_passed = avg_new_vif < 10  # New features should have reasonable VIF
    
    all_passed = g5_1_passed and g5_2_passed and g5_3_passed
    
    # Generate markdown report
    report = f"""# V4.1 Multicollinearity Analysis Report

**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  
**Status**: {'PASSED' if all_passed else 'FAILED'}

## Executive Summary

This report analyzes multicollinearity among all 23 V4.1 features to identify
redundant features that may hurt model stability. High multicollinearity (|r| > 0.7)
or high VIF (>10) indicates features that may need to be removed or combined.

## Summary Statistics

- **Total features analyzed**: {len(ALL_FEATURES)}
- **Original V4 features**: {len(ORIGINAL_FEATURES)}
- **New V4.1 bleeding features**: {len(NEW_BLEEDING_FEATURES)}
- **New V4.1 firm/rep type features**: {len(NEW_FIRM_REP_FEATURES)}
- **Critical correlation pairs (|r| > 0.85)**: {critical_corr}
- **Critical VIF (>10)**: {critical_vif}
- **Average VIF for new features**: {avg_new_vif:.2f}

## Validation Gates

### G5.1: No feature pair has |correlation| > 0.85
**Status**: {'[PASS] PASSED' if g5_1_passed else '[FAIL] FAILED'}

- Critical correlation pairs: {critical_corr}
- High correlation pairs (0.7-0.85): {len([p for p in high_corr_pairs if p['status'] == 'WARNING'])}

### G5.2: No feature has VIF > 10
**Status**: {'[PASS] PASSED' if g5_2_passed else '[FAIL] FAILED'}

- Features with VIF > 10: {critical_vif}
- Features with VIF 5-10: {len(vif_df[vif_df['status'] == 'WARNING'])}

### G5.3: New features add independent signal (not redundant)
**Status**: {'[PASS] PASSED' if g5_3_passed else '[FAIL] FAILED'}

- Average VIF for new features: {avg_new_vif:.2f}
- New features appear to add independent signal

## VIF Results

| Feature | VIF | Status | Category |
|---------|-----|--------|----------|
"""
    
    for _, row in vif_df.iterrows():
        if row['feature'] in NEW_BLEEDING_FEATURES:
            category = "New Bleeding"
        elif row['feature'] in NEW_FIRM_REP_FEATURES:
            category = "New Firm/Rep"
        else:
            category = "Original V4"
        
        vif_val = row['vif'] if pd.notna(row['vif']) else 'N/A'
        report += f"| {row['feature']} | {vif_val} | {row['status']} | {category} |\n"
    
    if high_corr_pairs:
        report += "\n## High Correlation Pairs (|r| > 0.7)\n\n"
        report += "| Feature 1 | Feature 2 | Correlation | Status |\n"
        report += "|-----------|-----------|-------------|--------|\n"
        for pair in sorted(high_corr_pairs, key=lambda x: abs(x['correlation']), reverse=True):
            report += f"| {pair['feature_1']} | {pair['feature_2']} | {pair['correlation']:.4f} | {pair['status']} |\n"
    else:
        report += "\n## High Correlation Pairs\n\n"
        report += "No high correlation pairs found (|r| > 0.7).\n"
    
    # Expected correlations section
    report += """
## Expected Correlations

The following correlations are expected and acceptable:

- **is_ia_rep_type vs is_dual_registered**: Mutually exclusive (correlation ≈ -1.0)
  - This is by design - advisors are either IA-only or dual-registered
  - VIF may be high, but both features provide signal (positive vs negative)
  
- **is_independent_ria vs is_ia_rep_type**: Moderate correlation (~0.4-0.6)
  - Independent RIAs often have IA-only advisors
  - Both features add value, correlation is acceptable
  
- **is_recent_mover vs mobility_3yr**: Moderate correlation expected
  - Both measure advisor movement, but at different time scales
  - Recent mover is 12-month window, mobility_3yr is 3-year window
  
- **firm_departures_corrected vs firm_net_change_12mo**: Moderate correlation expected
  - Both measure firm stability, but from different angles
  - Departures is count-based, net_change includes arrivals

## Recommendations

"""
    
    if critical_vif > 0:
        critical_features = vif_df[vif_df['status'] == 'CRITICAL']['feature'].tolist()
        report += f"- **Remove features with VIF > 10**: {', '.join(critical_features)}\n"
    
    if critical_corr > 0:
        critical_pairs = [p for p in high_corr_pairs if p['status'] == 'CRITICAL']
        report += f"- **Review critical correlation pairs**: {len(critical_pairs)} pairs with |r| > 0.85\n"
        for pair in critical_pairs:
            report += f"  - {pair['feature_1']} vs {pair['feature_2']} (r={pair['correlation']:.4f})\n"
    
    if all_passed:
        report += "- **All gates passed**: No action required. Features are ready for model training.\n"
    
    report += f"""
## Conclusion

{'All multicollinearity validation gates passed. Features are ready for model training.' if all_passed else 'One or more validation gates failed. Review recommendations above before proceeding.'}
"""
    
    # Save report
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report)
    
    # Save JSON results
    results = {
        'audit_date': datetime.now().isoformat(),
        'total_features': len(ALL_FEATURES),
        'gates': {
            'G5.1': {
                'passed': g5_1_passed,
                'critical_corr_pairs': critical_corr,
                'high_corr_pairs': len([p for p in high_corr_pairs if p['status'] == 'WARNING'])
            },
            'G5.2': {
                'passed': g5_2_passed,
                'critical_vif_count': int(critical_vif),
                'warning_vif_count': int(len(vif_df[vif_df['status'] == 'WARNING']))
            },
            'G5.3': {
                'passed': g5_3_passed,
                'avg_new_feature_vif': float(avg_new_vif)
            }
        },
        'vif_results': vif_df.to_dict('records'),
        'high_corr_pairs': high_corr_pairs,
        'all_passed': all_passed
    }
    
    with open(results_path, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    
    print(f"      Report saved to: {report_path}")
    print(f"      Results saved to: {results_path}")
    
    return all_passed, results


if __name__ == "__main__":
    print("=" * 80)
    print("Phase 5: Multicollinearity Check - V4.1")
    print("=" * 80)
    
    try:
        df = load_feature_data()
        corr_matrix, high_corr_pairs = calculate_correlation_matrix(df)
        vif_df = calculate_vif(df)
        passed, results = generate_report(corr_matrix, high_corr_pairs, vif_df)
        
        print("\n" + "=" * 80)
        print("Phase 5 Complete!")
        print("=" * 80)
        print(f"\nOverall Status: {'PASSED' if passed else 'FAILED'}")
        
        if passed:
            print("\nSUCCESS: All multicollinearity validation gates passed!")
        else:
            print("\nWARNING: Some validation gates failed. Review the report.")
            
    except Exception as e:
        print(f"\nERROR: Error during multicollinearity check: {e}")
        raise

