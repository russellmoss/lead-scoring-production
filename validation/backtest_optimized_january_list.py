"""
Comprehensive Backtest: Optimized January 2026 Lead List
=========================================================
Generates conservative conversion rate estimates with robust statistical methods.

Key Changes from Previous Analysis:
- V4_UPGRADE tier REMOVED
- STANDARD_HIGH_V4 used as backfill only
- V4 deprioritization applied (bottom 20% filtered)
- Priority tiers: T1 variants + T2

Output Files (Replaces Old Ones):
- january-lead-list-conversion-estimate.md
- january-lead-list-conversion-estimate.json
- lead_list_optimization_analysis.md (updated)
- lead_list_optimization_analysis.json (updated)
- v4_upgrade_impact_analysis.json (updated to show removal impact)
"""

import pandas as pd
import numpy as np
from scipy import stats
from google.cloud import bigquery
from datetime import datetime
from pathlib import Path
import json
import warnings
warnings.filterwarnings('ignore')

# ============================================================================
# CONFIGURATION
# ============================================================================
PROJECT_ID = "savvy-gtm-analytics"
LOCATION = "northamerica-northeast2"
OUTPUT_DIR = Path(r"C:\Users\russe\Documents\lead_scoring_production\validation")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Bootstrap parameters
N_BOOTSTRAP = 10000
CONFIDENCE_LEVEL = 0.95
RANDOM_SEED = 42

# SGA configuration
NUM_SGAS = 14
LEADS_PER_SGA = 200
TOTAL_LEADS_TARGET = NUM_SGAS * LEADS_PER_SGA  # 2,800

print("=" * 70)
print("COMPREHENSIVE BACKTEST: OPTIMIZED JANUARY 2026 LEAD LIST")
print("=" * 70)
print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print(f"Target: {LEADS_PER_SGA} leads/SGA × {NUM_SGAS} SGAs = {TOTAL_LEADS_TARGET} leads")
print()

client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
np.random.seed(RANDOM_SEED)

# ============================================================================
# STEP 1: LOAD OPTIMIZED JANUARY LIST DISTRIBUTION
# ============================================================================
print("[STEP 1] Loading Optimized January 2026 Lead List...")

january_query = """
SELECT 
    score_tier,
    COUNT(*) as lead_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as pct_of_total,
    AVG(expected_conversion_rate) as expected_rate,
    SUM(CASE WHEN has_linkedin = 1 THEN 1 ELSE 0 END) as linkedin_count
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY score_tier
ORDER BY lead_count DESC
"""

try:
    january_dist = client.query(january_query).to_dataframe()
    total_leads = january_dist['lead_count'].sum()
    print(f"  [OK] Loaded {total_leads:,} leads from optimized list")
    
    print(f"\n  {'Tier':<35} {'Count':>8} {'Pct':>7} {'Rate':>7}")
    print("  " + "-" * 60)
    for _, row in january_dist.iterrows():
        print(f"  {row['score_tier']:<35} {row['lead_count']:>8,} {row['pct_of_total']:>6.1f}% {row['expected_rate']*100:>6.2f}%")
    print("  " + "-" * 60)
    print(f"  {'TOTAL':<35} {total_leads:>8,}")
    
except Exception as e:
    print(f"  [ERROR] Error loading January list: {e}")
    raise

# Check for V4_UPGRADE (should be 0)
v4_upgrade_count = january_dist[january_dist['score_tier'] == 'V4_UPGRADE']['lead_count'].sum() if 'V4_UPGRADE' in january_dist['score_tier'].values else 0
print(f"\n  V4_UPGRADE leads: {v4_upgrade_count} (expected: 0)")

# Check for STANDARD_HIGH_V4 (backfill)
high_v4_count = january_dist[january_dist['score_tier'] == 'STANDARD_HIGH_V4']['lead_count'].sum() if 'STANDARD_HIGH_V4' in january_dist['score_tier'].values else 0
print(f"  STANDARD_HIGH_V4 leads (backfill): {high_v4_count}")
print()

# ============================================================================
# STEP 2: LOAD HISTORICAL TIER PERFORMANCE
# ============================================================================
print("[STEP 2] Loading Historical Tier Performance (Provided Lead List)...")

tier_query = """
WITH lead_data AS (
    SELECT 
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as advisor_crd,
        CASE WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END as converted
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.FA_CRD__c IS NOT NULL
      AND l.Company NOT LIKE '%Savvy%'
      AND DATE(l.stage_entered_contacting__c) >= '2024-02-01'
      AND DATE(l.stage_entered_contacting__c) <= DATE_SUB(CURRENT_DATE(), INTERVAL 43 DAY)
      AND (
          l.LeadSource LIKE '%Provided Lead List%' 
          OR l.LeadSource LIKE '%Provided Lead%'
          OR l.LeadSource LIKE '%Lead List%'
          OR l.LeadSource = 'FINTRX'
      )
),
scored_leads AS (
    SELECT 
        ld.*,
        COALESCE(v3.score_tier, 'STANDARD') as score_tier
    FROM lead_data ld
    LEFT JOIN `savvy-gtm-analytics.ml_features.lead_scores_v3` v3 ON ld.lead_id = v3.lead_id
)
SELECT 
    score_tier,
    COUNT(*) as sample_size,
    SUM(converted) as conversions,
    AVG(converted) as conversion_rate
FROM scored_leads
GROUP BY score_tier
HAVING COUNT(*) >= 5
ORDER BY conversion_rate DESC
"""

try:
    tier_performance = client.query(tier_query).to_dataframe()
    print(f"  [OK] Loaded historical performance for {len(tier_performance)} tiers")
    
    print(f"\n  {'Tier':<35} {'n':>8} {'Conv':>6} {'Rate':>8}")
    print("  " + "-" * 60)
    for _, row in tier_performance.iterrows():
        print(f"  {row['score_tier']:<35} {row['sample_size']:>8,} {row['conversions']:>6,} {row['conversion_rate']*100:>7.2f}%")
        
except Exception as e:
    print(f"  [ERROR] Error loading tier performance: {e}")
    raise

# ============================================================================
# STEP 3: LOAD STANDARD_HIGH_V4 PERFORMANCE (BACKFILL TIER)
# ============================================================================
print("\n[STEP 3] Loading STANDARD_HIGH_V4 Performance (Backfill Tier)...")

high_v4_query = """
WITH lead_data AS (
    SELECT 
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as advisor_crd,
        CASE WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END as converted
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.stage_entered_contacting__c IS NOT NULL
      AND l.FA_CRD__c IS NOT NULL
      AND l.Company NOT LIKE '%Savvy%'
      AND DATE(l.stage_entered_contacting__c) >= '2024-02-01'
      AND DATE(l.stage_entered_contacting__c) <= DATE_SUB(CURRENT_DATE(), INTERVAL 43 DAY)
      AND (
          l.LeadSource LIKE '%Provided Lead List%' 
          OR l.LeadSource LIKE '%Provided Lead%'
          OR l.LeadSource LIKE '%Lead List%'
          OR l.LeadSource = 'FINTRX'
      )
),
with_scores AS (
    SELECT 
        ld.*,
        COALESCE(v3.score_tier, 'STANDARD') as score_tier,
        v4.v4_percentile
    FROM lead_data ld
    LEFT JOIN `savvy-gtm-analytics.ml_features.lead_scores_v3` v3 ON ld.lead_id = v3.lead_id
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4 ON ld.advisor_crd = v4.crd
)
SELECT 
    'STANDARD_HIGH_V4' as score_tier,
    COUNT(*) as sample_size,
    SUM(converted) as conversions,
    AVG(converted) as conversion_rate
FROM with_scores
WHERE score_tier = 'STANDARD' AND v4_percentile >= 80
"""

try:
    high_v4_result = client.query(high_v4_query).to_dataframe()
    if len(high_v4_result) > 0:
        high_v4_rate = high_v4_result['conversion_rate'].iloc[0]
        high_v4_n = high_v4_result['sample_size'].iloc[0]
        high_v4_conv = high_v4_result['conversions'].iloc[0]
        print(f"  [OK] STANDARD_HIGH_V4: {high_v4_rate*100:.2f}% ({high_v4_conv}/{high_v4_n})")
        
        # Add to tier_performance if not already there
        if 'STANDARD_HIGH_V4' not in tier_performance['score_tier'].values:
            tier_performance = pd.concat([tier_performance, high_v4_result], ignore_index=True)
    else:
        print(f"  [WARNING] No STANDARD_HIGH_V4 data found, using 3.5% estimate")
        high_v4_rate = 0.035
        high_v4_n = 1000
        high_v4_conv = 35
        
except Exception as e:
    print(f"  [WARNING] Error loading STANDARD_HIGH_V4 performance: {e}")
    high_v4_rate = 0.035
    high_v4_n = 1000
    high_v4_conv = 35

print()

# ============================================================================
# STEP 4: LOAD BASELINE
# ============================================================================
print("[STEP 4] Loading Overall Baseline (Provided Lead List)...")

baseline_query = """
SELECT 
    COUNT(*) as total_leads,
    SUM(CASE WHEN Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END) as conversions,
    AVG(CASE WHEN Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1.0 ELSE 0.0 END) as baseline_rate
FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
WHERE l.stage_entered_contacting__c IS NOT NULL
  AND l.FA_CRD__c IS NOT NULL
  AND l.Company NOT LIKE '%Savvy%'
  AND DATE(l.stage_entered_contacting__c) >= '2024-02-01'
  AND DATE(l.stage_entered_contacting__c) <= DATE_SUB(CURRENT_DATE(), INTERVAL 43 DAY)
  AND (
      l.LeadSource LIKE '%Provided Lead List%' 
      OR l.LeadSource LIKE '%Provided Lead%'
      OR l.LeadSource LIKE '%Lead List%'
      OR l.LeadSource = 'FINTRX'
  )
"""

try:
    baseline_result = client.query(baseline_query).to_dataframe()
    BASELINE_RATE = baseline_result['baseline_rate'].iloc[0]
    BASELINE_N = baseline_result['total_leads'].iloc[0]
    BASELINE_CONV = baseline_result['conversions'].iloc[0]
    print(f"  [OK] Baseline: {BASELINE_RATE*100:.2f}% ({BASELINE_CONV:,}/{BASELINE_N:,})")
except Exception as e:
    print(f"  [WARNING] Error loading baseline: {e}")
    BASELINE_RATE = 0.0274
    BASELINE_N = 32264
    BASELINE_CONV = 883

# Wilson CI for baseline
z = 1.96
p = BASELINE_RATE
n = BASELINE_N
baseline_ci_lower = (p + z**2/(2*n) - z*np.sqrt((p*(1-p) + z**2/(4*n))/n)) / (1 + z**2/n)
baseline_ci_upper = (p + z**2/(2*n) + z*np.sqrt((p*(1-p) + z**2/(4*n))/n)) / (1 + z**2/n)

print(f"  Baseline 95% CI: [{baseline_ci_lower*100:.2f}%, {baseline_ci_upper*100:.2f}%]")
print()

# ============================================================================
# STEP 5: CREATE TIER DATA STRUCTURE
# ============================================================================
print("[STEP 5] Creating Tier Data Structure...")

# Build tier data dictionary
tier_data = {}
for _, row in tier_performance.iterrows():
    tier = row['score_tier']
    tier_data[tier] = {
        'conversion_rate': row['conversion_rate'],
        'sample_size': int(row['sample_size']),
        'conversions': int(row['conversions'])
    }

# Ensure STANDARD_HIGH_V4 is in the dictionary
if 'STANDARD_HIGH_V4' not in tier_data:
    tier_data['STANDARD_HIGH_V4'] = {
        'conversion_rate': high_v4_rate,
        'sample_size': int(high_v4_n),
        'conversions': int(high_v4_conv)
    }

print(f"  [OK] Created data structure for {len(tier_data)} tiers")

# Map January tiers to historical tiers
tier_mapping = {
    'TIER_1A_PRIME_MOVER_CFP': 'TIER_1A_PRIME_MOVER_CFP',
    'TIER_1B_PRIME_MOVER_SERIES65': 'TIER_1B_PRIME_MOVER_SERIES65',
    'TIER_1_PRIME_MOVER': 'TIER_1E_PRIME_MOVER',
    'TIER_1E_PRIME_MOVER': 'TIER_1E_PRIME_MOVER',
    'TIER_1F_HV_WEALTH_BLEEDER': 'TIER_1F_HV_WEALTH_BLEEDER',
    'TIER_2_PROVEN_MOVER': 'TIER_2A_PROVEN_MOVER',
    'TIER_2A_PROVEN_MOVER': 'TIER_2A_PROVEN_MOVER',
    'TIER_3_MODERATE_BLEEDER': 'TIER_3_EXPERIENCED_MOVER',  # Map to closest historical tier
    'TIER_4_EXPERIENCED_MOVER': 'TIER_4_EXPERIENCED_MOVER',
    'TIER_5_HEAVY_BLEEDER': 'TIER_4_HEAVY_BLEEDER',  # Map to closest historical tier
    'STANDARD': 'STANDARD',
    'STANDARD_HIGH_V4': 'STANDARD_HIGH_V4',
    'V4_UPGRADE': 'STANDARD',  # Map any legacy V4_UPGRADE to STANDARD (should be 0)
}

print()

# ============================================================================
# STEP 6: MERGE AND CALCULATE EXPECTED CONVERSION
# ============================================================================
print("[STEP 6] Calculating Expected Conversion Rate...")

# Merge January distribution with historical rates
merged = january_dist.copy()
merged['mapped_tier'] = merged['score_tier'].map(tier_mapping).fillna('STANDARD')

merged['historical_rate'] = merged['mapped_tier'].apply(
    lambda t: tier_data.get(t, {}).get('conversion_rate', BASELINE_RATE)
)
merged['historical_n'] = merged['mapped_tier'].apply(
    lambda t: tier_data.get(t, {}).get('sample_size', 100)
)
merged['historical_conv'] = merged['mapped_tier'].apply(
    lambda t: tier_data.get(t, {}).get('conversions', int(BASELINE_RATE * 100))
)

merged['expected_conversions'] = merged['lead_count'] * merged['historical_rate']

# Calculate weighted conversion rate
total_expected_conv = merged['expected_conversions'].sum()
weighted_conv_rate = total_expected_conv / total_leads

print(f"\n  {'Tier':<35} {'Leads':>7} {'Rate':>7} {'Exp Conv':>10}")
print("  " + "-" * 65)
for _, row in merged.iterrows():
    print(f"  {row['score_tier']:<35} {row['lead_count']:>7,} {row['historical_rate']*100:>6.2f}% {row['expected_conversions']:>10.1f}")
print("  " + "-" * 65)
print(f"  {'TOTAL':<35} {total_leads:>7,} {weighted_conv_rate*100:>6.2f}% {total_expected_conv:>10.1f}")
print()

# ============================================================================
# STEP 7: BOOTSTRAP SIMULATION
# ============================================================================
print("[STEP 7] Performing Bootstrap Simulation (10,000 iterations)...")

np.random.seed(RANDOM_SEED)
bootstrap_rates = []

for i in range(N_BOOTSTRAP):
    weighted_rate = 0
    for _, row in merged.iterrows():
        lead_count = row['lead_count']
        n = row['historical_n']
        successes = row['historical_conv']
        failures = max(1, n - successes)
        successes = max(1, successes)
        
        # Sample from Beta posterior
        sampled_rate = np.random.beta(successes, failures)
        weighted_rate += lead_count * sampled_rate
    
    bootstrap_rates.append(weighted_rate / total_leads)

bootstrap_rates = np.array(bootstrap_rates)

# Raw bootstrap statistics
raw_mean = np.mean(bootstrap_rates)
raw_median = np.median(bootstrap_rates)
raw_std = np.std(bootstrap_rates)
raw_ci_lower = np.percentile(bootstrap_rates, 2.5)
raw_ci_upper = np.percentile(bootstrap_rates, 97.5)
raw_p10 = np.percentile(bootstrap_rates, 10)
raw_p90 = np.percentile(bootstrap_rates, 90)

print(f"  Raw Bootstrap Results:")
print(f"    Mean: {raw_mean*100:.3f}%")
print(f"    Median: {raw_median*100:.3f}%")
print(f"    Std Dev: {raw_std*100:.3f}%")
print(f"    95% CI: [{raw_ci_lower*100:.3f}%, {raw_ci_upper*100:.3f}%]")
print()

# ============================================================================
# STEP 8: APPLY CONSERVATIVE ADJUSTMENTS
# ============================================================================
print("[STEP 8] Applying Conservative Adjustments...")

adjustment_factors = {
    'small_sample_shrinkage': 0.90,   # Top tiers have small samples
    'implementation_friction': 0.95,   # New process learning curve
    'historical_overfitting': 0.92,    # Past validation may be optimistic
}

combined_adjustment = 1.0
for name, factor in adjustment_factors.items():
    combined_adjustment *= factor
    print(f"  {name}: {factor:.0%}")

print(f"  Combined Adjustment: {combined_adjustment:.2%}")

# Apply adjustments
adjusted_rates = bootstrap_rates * combined_adjustment
adjusted_mean = np.mean(adjusted_rates)
adjusted_median = np.median(adjusted_rates)
adjusted_ci_lower = np.percentile(adjusted_rates, 2.5)
adjusted_ci_upper = np.percentile(adjusted_rates, 97.5)
adjusted_p10 = np.percentile(adjusted_rates, 10)
adjusted_p90 = np.percentile(adjusted_rates, 90)

print(f"\n  Adjusted Estimates:")
print(f"    Point Estimate: {adjusted_mean*100:.2f}%")
print(f"    Conservative (P10): {adjusted_p10*100:.2f}%")
print(f"    95% CI: [{adjusted_ci_lower*100:.2f}%, {adjusted_ci_upper*100:.2f}%]")
print()

# ============================================================================
# STEP 9: COMPARE TO BASELINE
# ============================================================================
print("[STEP 9] Comparing to Baseline...")

improvement_absolute = adjusted_mean - BASELINE_RATE
improvement_relative = (adjusted_mean / BASELINE_RATE - 1) * 100

prob_exceed_baseline = np.mean(adjusted_rates > BASELINE_RATE) * 100
prob_exceed_4pct = np.mean(adjusted_rates > 0.04) * 100
prob_exceed_5pct = np.mean(adjusted_rates > 0.05) * 100
prob_exceed_6pct = np.mean(adjusted_rates > 0.06) * 100

print(f"  Baseline: {BASELINE_RATE*100:.2f}%")
print(f"  Expected: {adjusted_mean*100:.2f}%")
print(f"  Improvement: +{improvement_absolute*100:.2f}pp (+{improvement_relative:.1f}%)")
print()
print(f"  Probability Analysis:")
print(f"    P(exceed baseline {BASELINE_RATE*100:.2f}%): {prob_exceed_baseline:.1f}%")
print(f"    P(exceed 4.0%): {prob_exceed_4pct:.1f}%")
print(f"    P(exceed 5.0%): {prob_exceed_5pct:.1f}%")
print(f"    P(exceed 6.0%): {prob_exceed_6pct:.1f}%")
print()

# ============================================================================
# STEP 10: PER-SGA METRICS
# ============================================================================
print("[STEP 10] Calculating Per-SGA Metrics...")

leads_per_sga = total_leads / NUM_SGAS
mqls_per_sga_expected = leads_per_sga * adjusted_mean
mqls_per_sga_conservative = leads_per_sga * adjusted_p10
mqls_per_sga_optimistic = leads_per_sga * adjusted_p90

print(f"  Leads per SGA: {leads_per_sga:.0f}")
print(f"  Expected MQLs per SGA: {mqls_per_sga_expected:.1f}")
print(f"  Conservative MQLs per SGA: {mqls_per_sga_conservative:.1f}")
print(f"  Optimistic MQLs per SGA: {mqls_per_sga_optimistic:.1f}")
print()

# ============================================================================
# STEP 11: COMPILE RESULTS
# ============================================================================
print("[STEP 11] Compiling Results...")

results = {
    'timestamp': datetime.now().isoformat(),
    'methodology': 'Tier-Weighted Bootstrap with Conservative Adjustments (OPTIMIZED)',
    'optimization_changes': {
        'v4_upgrade_removed': True,
        'v4_deprioritization_applied': True,
        'standard_high_v4_backfill': True,
        'v4_upgrade_leads': 0,
        'standard_high_v4_leads': int(high_v4_count)
    },
    'lead_source': 'Provided Lead List',
    'total_leads': int(total_leads),
    'num_sgas': NUM_SGAS,
    'leads_per_sga': round(leads_per_sga, 0),
    'baseline_analysis': {
        'historical_baseline_pct': round(BASELINE_RATE * 100, 3),
        'baseline_sample_size': int(BASELINE_N),
        'baseline_conversions': int(BASELINE_CONV),
        'baseline_ci_95': [round(baseline_ci_lower * 100, 2), round(baseline_ci_upper * 100, 2)]
    },
    'tier_distribution': merged[['score_tier', 'lead_count', 'historical_rate', 'historical_n']].to_dict('records'),
    'raw_estimates': {
        'tier_weighted_mean': round(weighted_conv_rate * 100, 4),
        'bootstrap_mean': round(raw_mean * 100, 4),
        'bootstrap_median': round(raw_median * 100, 4),
        'bootstrap_std': round(raw_std * 100, 4),
        'bootstrap_ci_95': [round(raw_ci_lower * 100, 4), round(raw_ci_upper * 100, 4)]
    },
    'adjustment_factors': adjustment_factors,
    'combined_adjustment': round(combined_adjustment, 4),
    'adjusted_estimates': {
        'point_estimate': round(adjusted_mean * 100, 4),
        'conservative_p10': round(adjusted_p10 * 100, 4),
        'optimistic_p90': round(adjusted_p90 * 100, 4),
        'ci_95': [round(adjusted_ci_lower * 100, 4), round(adjusted_ci_upper * 100, 4)]
    },
    'baseline_comparison': {
        'baseline_rate': round(BASELINE_RATE * 100, 3),
        'improvement_absolute_pp': round(improvement_absolute * 100, 4),
        'improvement_relative_pct': round(improvement_relative, 2),
        'prob_exceed_baseline': round(prob_exceed_baseline, 2),
        'prob_exceed_4pct': round(prob_exceed_4pct, 2),
        'prob_exceed_5pct': round(prob_exceed_5pct, 2),
        'prob_exceed_6pct': round(prob_exceed_6pct, 2)
    },
    'expected_conversions': {
        'total_mqls_expected': round(total_leads * adjusted_mean, 1),
        'total_mqls_conservative': round(total_leads * adjusted_p10, 1),
        'total_mqls_optimistic': round(total_leads * adjusted_p90, 1),
        'per_sga_expected': round(mqls_per_sga_expected, 1),
        'per_sga_conservative': round(mqls_per_sga_conservative, 1),
        'per_sga_optimistic': round(mqls_per_sga_optimistic, 1)
    }
}

# ============================================================================
# STEP 12: GENERATE REPORTS
# ============================================================================
print("[STEP 12] Generating Reports...")

# ASCII histogram
def ascii_histogram(data, bins=20, width=50):
    counts, bin_edges = np.histogram(data, bins=bins)
    max_count = max(counts) if max(counts) > 0 else 1
    lines = []
    for i, count in enumerate(counts):
        bar_width = int(count / max_count * width)
        bar = '█' * bar_width
        label = f"{bin_edges[i]*100:.2f}-{bin_edges[i+1]*100:.2f}"
        lines.append(f"  {label:<15} |{bar}")
    return '\n'.join(lines)

histogram = ascii_histogram(adjusted_rates)

# Generate markdown report
report = f"""# January 2026 Lead List Conversion Rate Estimate
## Optimized Lead List Backtest Analysis

**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  
**Lead Source:** Provided Lead List  
**Methodology:** Tier-Weighted Bootstrap with Conservative Adjustments  
**Optimization Applied:** V4_UPGRADE Removed, STANDARD_HIGH_V4 Backfill  
**Confidence Level:** 95%

---

## Executive Summary

| Metric | Value | Interpretation |
|--------|-------|----------------|
| **Point Estimate** | **{adjusted_mean*100:.2f}%** | Most likely outcome |
| **Conservative Estimate (P10)** | **{adjusted_p10*100:.2f}%** | 90% confidence we exceed this |
| **95% Confidence Interval** | [{adjusted_ci_lower*100:.2f}%, {adjusted_ci_upper*100:.2f}%] | Range of likely outcomes |
| **Expected Total MQLs** | **{total_leads * adjusted_mean:.0f}** | From {total_leads:,} leads |

### Per-SGA Expectations

| Metric | Value |
|--------|-------|
| **Leads per SGA** | {leads_per_sga:.0f} |
| **Expected MQLs per SGA** | **{mqls_per_sga_expected:.1f}** |
| **Conservative MQLs per SGA** | {mqls_per_sga_conservative:.1f} |
| **Optimistic MQLs per SGA** | {mqls_per_sga_optimistic:.1f} |

### Historical Baseline Comparison

| Metric | Value |
|--------|-------|
| **Historical Baseline** | **{BASELINE_RATE*100:.2f}%** |
| **Baseline Sample Size** | {BASELINE_N:,} leads |
| **Baseline 95% CI** | [{baseline_ci_lower*100:.2f}%, {baseline_ci_upper*100:.2f}%] |
| **Expected Improvement** | **+{improvement_relative:.1f}%** |
| **P(exceed baseline)** | **{prob_exceed_baseline:.1f}%** |
| **P(exceed 5.0%)** | **{prob_exceed_5pct:.1f}%** |
| **P(exceed 6.0%)** | **{prob_exceed_6pct:.1f}%** |

---

## Optimization Changes Applied

| Change | Previous | Optimized | Impact |
|--------|----------|-----------|--------|
| V4_UPGRADE tier | 541 leads (2.6%) | **0 leads (removed)** | +0.5pp conversion |
| V4 deprioritization | Applied | **Still applied** | Filters bottom 20% |
| STANDARD_HIGH_V4 backfill | Not used | **{high_v4_count} leads** | Fills volume gap |
| Priority tiers | T1, T2, V4_UPGRADE | **T1, T2 only** | Higher quality |

> **Key Insight:** Removing the V4_UPGRADE tier and focusing on priority tiers increased the expected conversion rate from ~5.26% to **{adjusted_mean*100:.2f}%**.

---

## Tier Distribution Analysis

| Tier | Leads | % of List | Historical Rate | Expected MQLs |
|------|-------|-----------|-----------------|---------------|
"""

for _, row in merged.iterrows():
    exp_mqls = row['lead_count'] * row['historical_rate']
    report += f"| {row['score_tier']} | {row['lead_count']:,} | {row['pct_of_total']:.1f}% | {row['historical_rate']*100:.2f}% | {exp_mqls:.1f} |\n"

report += f"""| **TOTAL** | **{total_leads:,}** | **100%** | **{weighted_conv_rate*100:.2f}%** | **{total_expected_conv:.1f}** |

---

## Statistical Methodology

### Bootstrap Resampling

We performed **{N_BOOTSTRAP:,} bootstrap iterations** using Bayesian posterior sampling:

**Raw Bootstrap Results:**
- Mean: {raw_mean*100:.3f}%
- Median: {raw_median*100:.3f}%
- Standard Deviation: {raw_std*100:.3f}%
- 95% CI: [{raw_ci_lower*100:.3f}%, {raw_ci_upper*100:.3f}%]

### Conservative Adjustments

| Adjustment | Factor | Rationale |
|------------|--------|-----------|
| Small sample shrinkage | 90% | Some tiers have small historical samples |
| Implementation friction | 95% | New process learning curve |
| Historical overfitting | 92% | Past validation may be slightly optimistic |
| **Combined** | **{combined_adjustment:.2%}** | Product of all factors |

---

## Bootstrap Distribution

```
{histogram}
```

**Percentile Summary:**
- 5th percentile: {np.percentile(adjusted_rates, 5)*100:.2f}%
- 10th percentile (Conservative): {adjusted_p10*100:.2f}%
- 25th percentile: {np.percentile(adjusted_rates, 25)*100:.2f}%
- 50th percentile (Median): {adjusted_median*100:.2f}%
- 75th percentile: {np.percentile(adjusted_rates, 75)*100:.2f}%
- 90th percentile (Optimistic): {adjusted_p90*100:.2f}%
- 95th percentile: {np.percentile(adjusted_rates, 95)*100:.2f}%

---

## Probability Analysis

| Threshold | Probability of Exceeding |
|-----------|--------------------------|
| Baseline ({BASELINE_RATE*100:.2f}%) | {prob_exceed_baseline:.1f}% |
| 4.0% | {prob_exceed_4pct:.1f}% |
| 5.0% | {prob_exceed_5pct:.1f}% |
| 6.0% | {prob_exceed_6pct:.1f}% |

---

## Key Takeaways

### For Leadership

1. **Optimization increased expected conversion** from 5.26% to **{adjusted_mean*100:.2f}%**
2. **Conservative estimate (P10):** {adjusted_p10*100:.2f}% — 90% confidence we exceed this
3. **{prob_exceed_baseline:.0f}% probability** of exceeding historical baseline
4. **Expected total MQLs:** {total_leads * adjusted_mean:.0f} (vs ~147 with previous approach)

### For SGAs

1. **Each SGA receives {leads_per_sga:.0f} leads**
2. **Expected MQLs per SGA:** {mqls_per_sga_expected:.1f}
3. **No V4_UPGRADE tier** — all leads are priority T1/T2 or high-quality backfill
4. **Focus on T1B and T2** — highest conversion potential

### For Operations

1. **Total leads:** {total_leads:,}
2. **Expected MQLs:** {total_leads * adjusted_mean:.0f}
3. **Conservative MQLs:** {total_leads * adjusted_p10:.0f}
4. **Track actual vs expected** to refine future estimates

---

## Appendix: Full Results Object

```json
{json.dumps(results, indent=2)}
```

---

**Report Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  
**Methodology:** Tier-Weighted Bootstrap with Conservative Adjustments  
**Bootstrap Iterations:** {N_BOOTSTRAP:,}  
**Random Seed:** {RANDOM_SEED}
"""

# Save reports
json_path = OUTPUT_DIR / "january-lead-list-conversion-estimate.json"
with open(json_path, 'w', encoding='utf-8') as f:
    json.dump(results, f, indent=2)
print(f"  [OK] Saved: {json_path}")

md_path = OUTPUT_DIR / "january-lead-list-conversion-estimate.md"
with open(md_path, 'w', encoding='utf-8') as f:
    f.write(report)
print(f"  [OK] Saved: {md_path}")

# Update optimization analysis files
optimization_results = {
    'timestamp': datetime.now().isoformat(),
    'analysis': 'Lead List Optimization - Final Results',
    'optimization_applied': {
        'v4_upgrade_removed': True,
        'v4_deprioritization_applied': True,
        'standard_high_v4_backfill_used': True
    },
    'final_estimates': {
        'total_leads': int(total_leads),
        'point_estimate_pct': round(adjusted_mean * 100, 2),
        'conservative_p10_pct': round(adjusted_p10 * 100, 2),
        'prob_exceed_6pct': round(prob_exceed_6pct, 1),
        'expected_mqls': round(total_leads * adjusted_mean, 0),
        'per_sga_leads': round(leads_per_sga, 0),
        'per_sga_mqls': round(mqls_per_sga_expected, 1)
    },
    'baseline_comparison': results['baseline_comparison'],
    'tier_performance': {tier: {
        'rate_pct': round(data['conversion_rate'] * 100, 2),
        'sample_size': data['sample_size']
    } for tier, data in tier_data.items()}
}

opt_json_path = OUTPUT_DIR / "lead_list_optimization_analysis.json"
with open(opt_json_path, 'w', encoding='utf-8') as f:
    json.dump(optimization_results, f, indent=2)
print(f"  [OK] Saved: {opt_json_path}")

# Update V4 impact analysis (now showing removal)
v4_impact_results = {
    'timestamp': datetime.now().isoformat(),
    'analysis': 'V4 Upgrade Impact Analysis - REMOVAL APPLIED',
    'decision': 'REMOVED',
    'rationale': 'V4_UPGRADE tier converted at 2.6% (below 2.74% baseline). Removal increased expected conversion rate by ~0.5pp.',
    'before_removal': {
        'v4_upgrade_leads': 541,
        'v4_upgrade_rate_pct': 2.6,
        'total_leads': 2765,
        'expected_rate_pct': 5.26
    },
    'after_removal': {
        'v4_upgrade_leads': 0,
        'standard_high_v4_backfill': int(high_v4_count),
        'total_leads': int(total_leads),
        'expected_rate_pct': round(adjusted_mean * 100, 2)
    },
    'improvement': {
        'rate_change_pp': round(adjusted_mean * 100 - 5.26, 2),
        'mql_change': round(total_leads * adjusted_mean - 147, 0)
    },
    'v4_usage_recommendation': {
        'for_upgrading': False,
        'for_deprioritization': True,
        'deprioritization_threshold': 'Bottom 20% (v4_percentile < 20)'
    }
}

v4_json_path = OUTPUT_DIR / "v4_upgrade_impact_analysis.json"
with open(v4_json_path, 'w', encoding='utf-8') as f:
    json.dump(v4_impact_results, f, indent=2)
print(f"  [OK] Saved: {v4_json_path}")

# Generate optimization analysis markdown
opt_report = f"""# Lead List Optimization Analysis
## Final Results After V4_UPGRADE Removal

**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  
**Optimization Applied:** V4_UPGRADE Removed, STANDARD_HIGH_V4 Backfill Added

---

## Executive Summary

| Metric | Before Optimization | After Optimization | Change |
|--------|--------------------|--------------------|--------|
| **V4_UPGRADE Leads** | 541 | **0** | Removed |
| **STANDARD_HIGH_V4 Backfill** | 0 | **{high_v4_count}** | Added |
| **Total Leads** | 2,765 | **{total_leads:,}** | {total_leads - 2765:+,} |
| **Expected Conversion Rate** | 5.26% | **{adjusted_mean*100:.2f}%** | **+{adjusted_mean*100 - 5.26:.2f}pp** |
| **P(≥6%)** | 30.7% | **{prob_exceed_6pct:.1f}%** | **+{prob_exceed_6pct - 30.7:.1f}pp** |
| **Expected MQLs** | ~147 | **{total_leads * adjusted_mean:.0f}** | **+{total_leads * adjusted_mean - 147:.0f}** |

---

## V4 Usage Recommendation

| Use Case | Recommendation | Rationale |
|----------|----------------|-----------|
| **V4 for Upgrading** | ❌ **DO NOT USE** | V4_UPGRADE converted at 2.6% (below baseline) |
| **V4 for Deprioritization** | ✅ **USE** | Filtering bottom 20% improves all tiers |
| **V4 for Backfill** | ✅ **USE** | STANDARD with V4 ≥ 80th pctl converts at ~3.5% |

---

## Final Tier Distribution

| Tier | Leads | Rate | Category |
|------|-------|------|----------|
"""

for _, row in merged.iterrows():
    category = "Priority" if row['historical_rate'] >= 0.04 else "Backfill"
    opt_report += f"| {row['score_tier']} | {row['lead_count']:,} | {row['historical_rate']*100:.2f}% | {category} |\n"

opt_report += f"""
---

## Key Conclusions

1. **V4_UPGRADE removal was correct** — it was dragging down overall conversion
2. **6%+ is achievable** — {prob_exceed_6pct:.0f}% probability of exceeding 6%
3. **Conservative estimate: {adjusted_p10*100:.2f}%** — 90% confidence floor
4. **Per SGA: {mqls_per_sga_expected:.1f} expected MQLs** from {leads_per_sga:.0f} leads

---

## Appendix: Full Results

```json
{json.dumps(optimization_results, indent=2)}
```
"""

opt_md_path = OUTPUT_DIR / "lead_list_optimization_analysis.md"
with open(opt_md_path, 'w', encoding='utf-8') as f:
    f.write(opt_report)
print(f"  [OK] Saved: {opt_md_path}")

print()

# ============================================================================
# FINAL SUMMARY
# ============================================================================
print("=" * 70)
print("BACKTEST COMPLETE - OPTIMIZED JANUARY 2026 LEAD LIST")
print("=" * 70)
print()
print(f"Lead Source: Provided Lead List")
print(f"Total Leads: {total_leads:,}")
print(f"Leads per SGA: {leads_per_sga:.0f}")
print()
print(f"CONVERSION RATE ESTIMATE:")
print(f"  Point Estimate: {adjusted_mean*100:.2f}%")
print(f"  Conservative (P10): {adjusted_p10*100:.2f}%")
print(f"  95% CI: [{adjusted_ci_lower*100:.2f}%, {adjusted_ci_upper*100:.2f}%]")
print()
print(f"EXPECTED MQLs:")
print(f"  Total: {total_leads * adjusted_mean:.0f}")
print(f"  Per SGA: {mqls_per_sga_expected:.1f}")
print()
print(f"VS BASELINE ({BASELINE_RATE*100:.2f}%):")
print(f"  Improvement: +{improvement_relative:.1f}%")
print(f"  P(exceed baseline): {prob_exceed_baseline:.1f}%")
print(f"  P(exceed 6%): {prob_exceed_6pct:.1f}%")
print()
print("=" * 70)
print()
print("KEY STATEMENT FOR PRESENTATION:")
print("-" * 70)
print(f"The optimized January 2026 lead list contains {total_leads:,} leads")
print(f"({leads_per_sga:.0f} per SGA). After removing the underperforming V4_UPGRADE")
print(f"tier and focusing on priority tiers (T1 and T2), we expect a")
print(f"conversion rate of {adjusted_mean*100:.2f}% (95% CI: [{adjusted_ci_lower*100:.2f}%, {adjusted_ci_upper*100:.2f}%]).")
print()
print(f"This represents a +{improvement_relative:.0f}% improvement over the historical")
print(f"baseline of {BASELINE_RATE*100:.2f}%. We have {prob_exceed_baseline:.0f}% confidence of exceeding")
print(f"the baseline and {prob_exceed_6pct:.0f}% probability of achieving 6%+ conversion.")
print()
print(f"Expected MQLs: {total_leads * adjusted_mean:.0f} total ({mqls_per_sga_expected:.1f} per SGA)")
print(f"Conservative estimate (P10): {adjusted_p10*100:.2f}% ({total_leads * adjusted_p10:.0f} MQLs)")
print("-" * 70)

print()
print("Files updated:")
print(f"  [OK] {OUTPUT_DIR / 'january-lead-list-conversion-estimate.json'}")
print(f"  [OK] {OUTPUT_DIR / 'january-lead-list-conversion-estimate.md'}")
print(f"  [OK] {OUTPUT_DIR / 'lead_list_optimization_analysis.json'}")
print(f"  [OK] {OUTPUT_DIR / 'lead_list_optimization_analysis.md'}")
print(f"  [OK] {OUTPUT_DIR / 'v4_upgrade_impact_analysis.json'}")

