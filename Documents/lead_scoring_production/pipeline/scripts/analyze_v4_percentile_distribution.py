"""Analyze V4 percentile distribution in lead list."""
from google.cloud import bigquery

client = bigquery.Client(project='savvy-gtm-analytics')

# Overall distribution
query1 = """
SELECT 
    COUNT(*) as total,
    MIN(v4_percentile) as min_pct,
    MAX(v4_percentile) as max_pct,
    ROUND(AVG(v4_percentile), 1) as avg_pct,
    APPROX_QUANTILES(v4_percentile, 100)[OFFSET(50)] as median_pct,
    APPROX_QUANTILES(v4_percentile, 100)[OFFSET(25)] as p25,
    APPROX_QUANTILES(v4_percentile, 100)[OFFSET(10)] as p10,
    APPROX_QUANTILES(v4_percentile, 100)[OFFSET(5)] as p5
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
"""

print("=" * 70)
print("V4 PERCENTILE DISTRIBUTION ANALYSIS")
print("=" * 70)
print()

result1 = client.query(query1).result()
row1 = list(result1)[0]

print(f"Overall Statistics:")
print(f"  Total leads: {row1.total:,}")
print(f"  Min: {row1.min_pct}th percentile")
print(f"  Max: {row1.max_pct}th percentile")
print(f"  Average: {row1.avg_pct}th percentile")
print(f"  Median: {row1.median_pct}th percentile")
print(f"  25th percentile: {row1.p25}th percentile")
print(f"  10th percentile: {row1.p10}th percentile")
print(f"  5th percentile: {row1.p5}th percentile")
print()

# Distribution by buckets
query2 = """
SELECT 
    CASE 
        WHEN v4_percentile >= 90 THEN '90-100'
        WHEN v4_percentile >= 80 THEN '80-89'
        WHEN v4_percentile >= 70 THEN '70-79'
        WHEN v4_percentile >= 60 THEN '60-69'
        WHEN v4_percentile >= 50 THEN '50-59'
        WHEN v4_percentile >= 40 THEN '40-49'
        WHEN v4_percentile >= 30 THEN '30-39'
        WHEN v4_percentile >= 20 THEN '20-29'
        ELSE '<20'
    END as v4_bucket,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) as pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
GROUP BY v4_bucket
ORDER BY 
    CASE v4_bucket
        WHEN '90-100' THEN 1
        WHEN '80-89' THEN 2
        WHEN '70-79' THEN 3
        WHEN '60-69' THEN 4
        WHEN '50-59' THEN 5
        WHEN '40-49' THEN 6
        WHEN '30-39' THEN 7
        WHEN '20-29' THEN 8
        ELSE 9
    END
"""

print("Distribution by Percentile Buckets:")
print()
result2 = client.query(query2).result()
for row in result2:
    print(f"  {row.v4_bucket}th percentile: {row.count:,} ({row.pct}%)")
print()

# By tier
query3 = """
SELECT 
    score_tier as final_tier,
    COUNT(*) as count,
    ROUND(AVG(v4_percentile), 1) as avg_v4_pct,
    MIN(v4_percentile) as min_v4_pct,
    MAX(v4_percentile) as max_v4_pct,
    APPROX_QUANTILES(v4_percentile, 100)[OFFSET(10)] as p10_v4
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

print("V4 Percentile by Tier:")
print()
result3 = client.query(query3).result()
for row in result3:
    print(f"{row.final_tier}:")
    print(f"  Count: {row.count:,}")
    print(f"  Avg V4: {row.avg_v4_pct}th percentile")
    print(f"  Range: {row.min_v4_pct}-{row.max_v4_pct}th percentile")
    print(f"  10th percentile: {row.p10_v4}th percentile")
    print()

# Find leads with low V4 scores
query4 = """
SELECT 
    COUNT(*) as low_v4_count,
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`) as pct
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
WHERE v4_percentile < 50
"""

print("=" * 70)
print("LOW V4 PERCENTILE ANALYSIS")
print("=" * 70)
print()

result4 = client.query(query4).result()
row4 = list(result4)[0]
print(f"Leads with V4 < 50th percentile: {row4.low_v4_count:,} ({row4.pct:.1f}%)")
print()

if row4.low_v4_count > 0:
    query5 = """
    SELECT 
        score_tier as final_tier,
        COUNT(*) as count,
        ROUND(AVG(v4_percentile), 1) as avg_v4_pct,
        MIN(v4_percentile) as min_v4_pct
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
    WHERE v4_percentile < 50
    GROUP BY score_tier
    ORDER BY count DESC
    """
    
    print("Low V4 leads by tier:")
    result5 = client.query(query5).result()
    for row in result5:
        print(f"  {row.final_tier}: {row.count:,} leads (avg: {row.avg_v4_pct}th, min: {row.min_v4_pct}th)")
    print()

# Recommendations
print("=" * 70)
print("RECOMMENDATIONS")
print("=" * 70)
print()

if row1.min_pct < 50:
    print(f"[CONSIDER] Minimum V4 percentile is {row1.min_pct}th - consider adding filter")
    print(f"  Historical data shows bottom 20% converts at 1.33% (vs 3.20% baseline)")
    print(f"  Bottom 30% converts at 1.67% (0.52x lift)")
    print()
    print("  Suggested filters:")
    print("  - Option 1: Exclude V4 < 50th percentile (bottom half)")
    print("  - Option 2: Exclude V4 < 60th percentile (more aggressive)")
    print("  - Option 3: Exclude V4 < 70th percentile (very aggressive)")
    print()
else:
    print(f"[OK] Minimum V4 percentile is {row1.min_pct}th - already filtering low scores")
    print()

if row1.p10 < 70:
    print(f"[CONSIDER] 10th percentile is {row1.p10}th - bottom 10% may need filtering")
else:
    print(f"[OK] 10th percentile is {row1.p10}th - good distribution")
    print()

