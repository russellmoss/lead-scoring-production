"""
Export january_2026_lead_list from BigQuery to CSV.

Run from repository root after Phase 6 and Phase 7:
  python pipeline/scripts/export_lead_list.py

Output: pipeline/exports/January_2026_lead_list_YYYYMMDD.csv
"""

from pathlib import Path
from google.cloud import bigquery
from datetime import datetime

PROJECT_ID = "savvy-gtm-analytics"
TABLE_ID = "savvy-gtm-analytics.ml_features.january_2026_lead_list"
LOCATION = "northamerica-northeast2"

def main():
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    exports_dir = repo_root / "pipeline" / "exports"
    exports_dir.mkdir(parents=True, exist_ok=True)

    date_str = datetime.now().strftime("%Y%m%d")
    out_file = exports_dir / f"January_2026_lead_list_{date_str}.csv"

    print("=" * 60)
    print("EXPORT LEAD LIST TO CSV")
    print("=" * 60)
    print(f"Table: {TABLE_ID}")
    print(f"Output: {out_file}")
    print()

    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    query = f"SELECT * FROM `{TABLE_ID}` ORDER BY list_rank, priority_rank, advisor_crd"
    df = client.query(query, location=LOCATION).to_dataframe()
    df.to_csv(out_file, index=False, date_format="%Y-%m-%d %H:%M:%S")
    print(f"[OK] Exported {len(df):,} rows to {out_file}")
    print("=" * 60)

if __name__ == "__main__":
    main()
