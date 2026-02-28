"""Run March 2026 lead list validation queries and print results."""
from pathlib import Path
from google.cloud import bigquery

PROJECT_ID = "savvy-gtm-analytics"
SCRIPT_DIR = Path(__file__).resolve().parent
SQL_DIR = SCRIPT_DIR.parent / "sql"

def main():
    client = bigquery.Client(project=PROJECT_ID)

    # Total count
    total_sql = (SQL_DIR / "_validation_march_total.sql").read_text(encoding="utf-8")
    total_rows = list(client.query(total_sql).result())
    print("Total leads:", total_rows[0].total_leads)

    # Tier breakdown
    tier_sql = (SQL_DIR / "_validation_march_2026.sql").read_text(encoding="utf-8")
    print("\nTier breakdown:")
    print("-" * 70)
    for row in client.query(tier_sql).result():
        print(f"  {row.score_tier}: {row.lead_count} ({row.pct_of_total}%)  avg_conv={row.avg_expected_conv_pct}%")
    print("-" * 70)

if __name__ == "__main__":
    main()
