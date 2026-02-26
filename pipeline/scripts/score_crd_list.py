"""
Score a list of advisor CRDs from a CSV using BigQuery lookup.

Reads a CSV with a 'crd' column, looks up V3 score_tier and V4 score/percentile
from ml_features.lead_scores_v3_6 and ml_features.v4_prospect_scores,
writes a new CSV with scores appended.

Usage:
  python pipeline/scripts/score_crd_list.py input.csv [output.csv]
  python pipeline/scripts/score_crd_list.py --help

Requires: google-cloud-bigquery, pandas. Auth via gcloud auth application-default login.
"""

import argparse
import csv
from pathlib import Path

from google.cloud import bigquery

PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
CRD_COLUMN = "crd"  # expected column name in input CSV


def load_crds_from_csv(path: Path, crd_column: str = CRD_COLUMN) -> list[int]:
    """Read CRDs from CSV. Column can be 'crd' or any name via crd_column."""
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if crd_column not in reader.fieldnames:
            raise SystemExit(
                f"CSV must have a column named '{crd_column}'. Found: {reader.fieldnames}"
            )
        crds = []
        for row in reader:
            try:
                v = row.get(crd_column, "").strip()
                if v and v.isdigit():
                    crds.append(int(v))
            except (ValueError, TypeError):
                continue
    return list(dict.fromkeys(crds))  # unique, preserve order


def build_lookup_query(crds: list[int]) -> str:
    """Build query that looks up V3 tier and V4 score for given CRDs."""
    if not crds:
        raise ValueError("No valid CRDs to look up")
    crd_list = ",".join(str(c) for c in crds)
    return f"""
WITH your_crd_list AS (
  SELECT crd FROM UNNEST([{crd_list}]) AS crd
),
v3_latest AS (
  SELECT
    advisor_crd AS crd,
    score_tier,
    expected_conversion_rate,
    ROW_NUMBER() OVER (PARTITION BY advisor_crd ORDER BY contacted_date DESC) AS rn
  FROM `{PROJECT_ID}.{DATASET}.lead_scores_v3_6`
),
v3_one AS (
  SELECT crd, score_tier, expected_conversion_rate
  FROM v3_latest
  WHERE rn = 1
)
SELECT
  l.crd,
  v3.score_tier,
  v3.expected_conversion_rate AS v3_expected_rate_pct,
  v4.v4_score,
  v4.v4_percentile
FROM your_crd_list l
LEFT JOIN v3_one v3 ON l.crd = v3.crd
LEFT JOIN `{PROJECT_ID}.{DATASET}.v4_prospect_scores` v4 ON l.crd = v4.crd
ORDER BY v4.v4_percentile DESC, v3.score_tier
"""


def main():
    parser = argparse.ArgumentParser(
        description="Score advisor CRDs from CSV via BigQuery lookup."
    )
    parser.add_argument(
        "input_csv",
        type=Path,
        help="Input CSV with a 'crd' column (advisor CRD numbers).",
    )
    parser.add_argument(
        "output_csv",
        nargs="?",
        type=Path,
        default=None,
        help="Output CSV with scores. Default: input_scored.csv next to input.",
    )
    parser.add_argument(
        "--crd-column",
        default=CRD_COLUMN,
        help=f"Name of CRD column in input CSV (default: {CRD_COLUMN}).",
    )
    args = parser.parse_args()

    input_path = args.input_csv.resolve()
    if not input_path.is_file():
        raise SystemExit(f"Input file not found: {input_path}")

    output_path = args.output_csv
    if output_path is None:
        output_path = input_path.parent / f"{input_path.stem}_scored.csv"
    else:
        output_path = output_path.resolve()

    crds = load_crds_from_csv(input_path, args.crd_column)
    if not crds:
        raise SystemExit("No valid CRD values found in input CSV.")

    print(f"Loaded {len(crds)} CRDs from {input_path}")
    if len(crds) > 10000:
        print("Warning: >10k CRDs may hit query limits; consider using BQ staging table instead.")

    client = bigquery.Client(project=PROJECT_ID)
    query = build_lookup_query(crds)
    df_scores = client.query(query).to_dataframe()

    # Merge back with original CSV so we keep other columns and row order
    with open(input_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames)
        rows_orig = list(reader)

    score_cols = ["score_tier", "v3_expected_rate_pct", "v4_score", "v4_percentile"]
    for c in score_cols:
        if c not in fieldnames:
            fieldnames.append(c)

    score_by_crd = df_scores.set_index("crd").to_dict("index")

    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        crd_key = args.crd_column
        for row in rows_orig:
            try:
                c = int(row.get(crd_key, "").strip())
            except (ValueError, TypeError):
                c = None
            out = dict(row)
            if c is not None and c in score_by_crd:
                for k, v in score_by_crd[c].items():
                    out[k] = v
            else:
                for k in score_cols:
                    out.setdefault(k, "")
            writer.writerow(out)

    print(f"Wrote {len(rows_orig)} rows to {output_path}")


if __name__ == "__main__":
    main()
