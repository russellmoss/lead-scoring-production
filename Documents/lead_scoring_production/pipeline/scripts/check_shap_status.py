"""Check SHAP scoring status and diversity."""
from google.cloud import bigquery
from datetime import datetime, timezone

client = bigquery.Client(project='savvy-gtm-analytics')

# Check last scored time
result = client.query("""
    SELECT 
        MAX(scored_at) as last_scored,
        COUNT(*) as total
    FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
""").result()
row = list(result)[0]

now = datetime.now(timezone.utc)
last = row.last_scored
if last:
    last_utc = last.replace(tzinfo=timezone.utc) if last.tzinfo is None else last
    diff_minutes = (now - last_utc).total_seconds() / 60
else:
    diff_minutes = 999

print(f"Last scored: {last}")
print(f"Minutes ago: {diff_minutes:.1f}")
print(f"Total scores: {row.total:,}")
print(f"Status: {'RECENT' if diff_minutes < 30 else 'OLD'}")

# Check SHAP diversity
result2 = client.query("""
    SELECT 
        COUNT(DISTINCT shap_top1_feature) as unique_top1,
        COUNT(*) as total
    FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
    WHERE shap_top1_feature IS NOT NULL
""").result()
row2 = list(result2)[0]

print(f"\nSHAP Diversity:")
print(f"  Unique top-1 features: {row2.unique_top1}")
print(f"  Total prospects: {row2.total:,}")
print(f"  Status: {'GOOD - Bug Fixed!' if row2.unique_top1 >= 10 else 'POOR - Still has bug'}")

# Show distribution
result3 = client.query("""
    SELECT 
        shap_top1_feature,
        COUNT(*) as count,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) as pct
    FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`
    WHERE shap_top1_feature IS NOT NULL
    GROUP BY shap_top1_feature
    ORDER BY count DESC
    LIMIT 10
""").result()

print(f"\nTop 10 SHAP Features Distribution:")
for r in result3:
    print(f"  {r.shap_top1_feature}: {r.count:,} ({r.pct}%)")

