"""Calculate expected conversion rate for January 2026 lead list."""
from google.cloud import bigquery

client = bigquery.Client(project='savvy-gtm-analytics')

# Historical conversion rates (from V3 validation and V4 upgrade analysis)
HISTORICAL_RATES = {
    'TIER_1A_PRIME_MOVER_CFP': 0.1644,      # 16.44%
    'TIER_1B_PRIME_MOVER_SERIES65': 0.1648,  # 16.48%
    'TIER_1_PRIME_MOVER': 0.1321,            # 13.21%
    'TIER_1F_HV_WEALTH_BLEEDER': 0.1278,     # 12.78%
    'TIER_2_PROVEN_MOVER': 0.0859,           # 8.59%
    'TIER_3_MODERATE_BLEEDER': 0.0952,       # 9.52%
    'TIER_4_EXPERIENCED_MOVER': 0.1154,      # 11.54%
    'TIER_5_HEAVY_BLEEDER': 0.0727,          # 7.27%
    'V4_UPGRADE': 0.0460,                     # 4.60% (STANDARD leads with V4 >= 80th percentile)
    'STANDARD': 0.0382                        # 3.82% baseline
}

# Get tier distribution from current lead list
query = """
SELECT 
    score_tier,
    COUNT(*) as count,
    ROUND(AVG(expected_rate_pct), 2) as avg_expected_rate
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY score_tier
ORDER BY 
    CASE score_tier
        WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
        WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
        WHEN 'TIER_1_PRIME_MOVER' THEN 3
        WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
        WHEN 'TIER_2_PROVEN_MOVER' THEN 5
        WHEN 'V4_UPGRADE' THEN 6
        ELSE 7
    END
"""

print("=" * 70)
print("JANUARY 2026 LEAD LIST - EXPECTED CONVERSION RATE CALCULATION")
print("=" * 70)
print()

result = client.query(query).result()
rows = list(result)

total_leads = sum(row.count for row in rows)
weighted_sum = 0
total_expected_conversions = 0

print("Tier Distribution and Expected Conversion Rates:")
print()
print(f"{'Tier':<35} {'Count':<10} {'% of Total':<12} {'Historical Rate':<18} {'Expected Conv':<15}")
print("-" * 90)

for row in rows:
    pct = (row.count / total_leads) * 100
    historical_rate = HISTORICAL_RATES.get(row.score_tier, 0.0382)
    expected_conversions = row.count * historical_rate
    weighted_sum += expected_conversions
    total_expected_conversions += expected_conversions
    
    print(f"{row.score_tier:<35} {row.count:<10,} {pct:>6.1f}%      {historical_rate*100:>6.2f}%            {expected_conversions:>6.1f}")

print("-" * 90)
print(f"{'TOTAL':<35} {total_leads:<10,} {'100.0%':<12} {'Weighted Avg':<18} {total_expected_conversions:>6.1f}")
print()

overall_rate = (weighted_sum / total_leads) * 100

print("=" * 70)
print("EXPECTED CONVERSION RATE SUMMARY")
print("=" * 70)
print()
print(f"Total Leads: {total_leads:,}")
print(f"Weighted Average Expected Conversion Rate: {overall_rate:.2f}%")
print(f"Expected Conversions (MQLs): {total_expected_conversions:.1f}")
print(f"Expected Conversions (rounded): {round(total_expected_conversions)}")
print()

# Compare to baseline
baseline_rate = 0.0382  # 3.82%
lift = overall_rate / (baseline_rate * 100)
print(f"Baseline Conversion Rate (STANDARD tier): {baseline_rate*100:.2f}%")
print(f"Expected Lift vs Baseline: {lift:.2f}x")
print()

# Monthly and quarterly projections
monthly_conversions = total_expected_conversions
quarterly_conversions = monthly_conversions * 3

print("=" * 70)
print("PROJECTIONS")
print("=" * 70)
print()
print(f"Monthly Expected Conversions: {monthly_conversions:.1f} MQLs")
print(f"Quarterly Expected Conversions: {quarterly_conversions:.1f} MQLs")
print()

# Confidence intervals (assuming binomial distribution)
import math
std_error = math.sqrt(total_leads * (overall_rate/100) * (1 - overall_rate/100))
confidence_95_low = total_expected_conversions - 1.96 * (std_error / total_leads * total_leads)
confidence_95_high = total_expected_conversions + 1.96 * (std_error / total_leads * total_leads)

print("=" * 70)
print("95% CONFIDENCE INTERVAL (Binomial Approximation)")
print("=" * 70)
print()
print(f"Expected Conversions: {total_expected_conversions:.1f}")
print(f"95% CI Lower Bound: {confidence_95_low:.1f} MQLs")
print(f"95% CI Upper Bound: {confidence_95_high:.1f} MQLs")
print(f"Range: {confidence_95_high - confidence_95_low:.1f} MQLs")
print()

