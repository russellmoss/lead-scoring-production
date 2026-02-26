r"""
Score Futureproof CSV with full V3 tier + V4 (same logic as January/February lead list).

Reads a CSV with a CRD column, uploads CRDs to BigQuery staging table,
runs the same lead-list scoring pipeline (FinTrx + V3 tier logic + V4) restricted
to those CRDs, then merges score_tier and v4_score/v4_percentile back into the CSV.

Usage:
  python pipeline/scripts/score_futureproof_csv.py "path/to/futureproof_advisors.csv"
  python pipeline/scripts/score_futureproof_csv.py <path_to_csv> [--output path] [--crd-column CRD]

Requires: google-cloud-bigquery, pandas. Auth: gcloud auth application-default login.
"""

import argparse
import csv
import re
from pathlib import Path

from google.cloud import bigquery
import pandas as pd

PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
STAGING_TABLE = "futureproof_crd_list"
JANUARY_SQL_PATH = Path(__file__).resolve().parents[1] / "sql" / "January_2026_Lead_List_V3_V4_Hybrid.sql"

# Default CRD column name in CSV (your file uses "CRD")
DEFAULT_CRD_COLUMN = "CRD"

FINAL_SQL_SUFFIX = """,
-- ============================================================================
-- EXCLUSION DIAGNOSTIC: Actual reason per advisor (first match in pipeline order)
-- ============================================================================
exclusion_diagnostic AS (
  SELECT
    i.crd,
    CASE
      WHEN sp.crd IS NOT NULL THEN NULL
      WHEN c.RIA_CONTACT_CRD_ID IS NULL THEN 'Not in FinTrx ria_contacts_current'
      WHEN c.AGE_RANGE IN ('70-74', '75-79', '80-84', '85-89', '90-94', '95-99') THEN 'Age over 70'
      WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_CRIMINAL, FALSE) = TRUE THEN 'Has disclosure (criminal)'
      WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_REGULATORY_EVENT, FALSE) = TRUE THEN 'Has disclosure (regulatory)'
      WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_TERMINATION, FALSE) = TRUE THEN 'Has disclosure (termination)'
      WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_INVESTIGATION, FALSE) = TRUE THEN 'Has disclosure (investigation)'
      WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_CUSTOMER_DISPUTE, FALSE) = TRUE THEN 'Has disclosure (customer dispute)'
      WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_CIVIL_EVENT, FALSE) = TRUE THEN 'Has disclosure (civil)'
      WHEN COALESCE(c.CONTACT_HAS_DISCLOSED_BOND, FALSE) = TRUE THEN 'Has disclosure (bond)'
      WHEN (
        UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTIONS ADVISOR%'
        OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
        OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE ADVISOR%'
        OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS%'
        OR UPPER(c.TITLE_NAME) LIKE '%WHOLESALER%'
        OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE%'
        OR UPPER(c.TITLE_NAME) LIKE '%ASSISTANT%'
        OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE AGENT%'
        OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE%'
        OR UPPER(c.TITLE_NAME) LIKE '%CHIEF FINANCIAL OFFICER%'
        OR UPPER(c.TITLE_NAME) LIKE '%CFO%'
        OR UPPER(c.TITLE_NAME) LIKE '%CHIEF INVESTMENT OFFICER%'
        OR UPPER(c.TITLE_NAME) LIKE '%CIO%'
        OR UPPER(c.TITLE_NAME) LIKE '%VICE PRESIDENT%'
        OR UPPER(c.TITLE_NAME) LIKE '%VP %'
      ) THEN 'Title excluded'
      WHEN ef.firm_pattern IS NOT NULL OR ec.firm_crd IS NOT NULL THEN
        TRIM(CONCAT(
          'Firm excluded (', COALESCE(c.PRIMARY_FIRM_NAME, 'unknown'), '): ',
          CASE WHEN ef.firm_pattern IS NOT NULL
            THEN CONCAT('name matches pattern ', CHR(39), ef.firm_pattern, CHR(39), ' (wirehouse/BD/insurance).')
            ELSE '' END,
          CASE WHEN ef.firm_pattern IS NOT NULL AND ec.firm_crd IS NOT NULL THEN ' ' ELSE '' END,
          CASE WHEN ec.firm_crd IS NOT NULL
            THEN CONCAT('Firm CRD ', CAST(ec.firm_crd AS STRING), ' on exclusion list (e.g. Savvy, Ritholtz).')
            ELSE '' END
        ))
      WHEN bp.crd IS NULL THEN 'Excluded by base (other: e.g. producing advisor, required fields)'
      WHEN ep.crd IS NULL THEN
        CASE
          WHEN COALESCE(fm.turnover_pct, 0) >= 100 THEN 'Turnover 100%'
          WHEN fd.discretionary_ratio IS NOT NULL AND fd.discretionary_ratio < 0.5 THEN 'Low discretionary (<50%)'
          WHEN rp.crd IS NOT NULL THEN 'Recent promotee (<5yr tenure + mid/senior title)'
          ELSE 'Excluded at enrichment (other)'
        END
      WHEN v4.crd IS NULL THEN 'No V4 score in prospect table'
      WHEN v4.v4_percentile < 20 THEN 'V4 bottom 20% (deprioritized)'
      ELSE 'Excluded (unknown)'
    END AS exclusion_reason
  FROM input_crds i
  LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    ON c.RIA_CONTACT_CRD_ID IS NOT NULL
    AND SAFE_CAST(ROUND(SAFE_CAST(c.RIA_CONTACT_CRD_ID AS FLOAT64), 0) AS INT64) = i.crd
  LEFT JOIN excluded_firms ef ON UPPER(c.PRIMARY_FIRM_NAME) LIKE ef.firm_pattern
  LEFT JOIN excluded_firm_crds ec ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ec.firm_crd
  LEFT JOIN base_prospects bp ON bp.crd IS NOT NULL AND SAFE_CAST(ROUND(SAFE_CAST(bp.crd AS FLOAT64), 0) AS INT64) = i.crd
  LEFT JOIN firm_metrics fm ON bp.firm_crd = fm.firm_crd
  LEFT JOIN (
    SELECT CRD_ID AS firm_crd, SAFE_DIVIDE(DISCRETIONARY_AUM, TOTAL_AUM) AS discretionary_ratio
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current`
  ) fd ON bp.firm_crd = fd.firm_crd
  LEFT JOIN recent_promotee_exclusions rp ON rp.crd IS NOT NULL AND SAFE_CAST(ROUND(SAFE_CAST(rp.crd AS FLOAT64), 0) AS INT64) = i.crd
  LEFT JOIN enriched_prospects ep ON ep.crd IS NOT NULL AND SAFE_CAST(ROUND(SAFE_CAST(ep.crd AS FLOAT64), 0) AS INT64) = i.crd
  LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4
    ON v4.crd IS NOT NULL AND SAFE_CAST(ROUND(SAFE_CAST(v4.crd AS FLOAT64), 0) AS INT64) = i.crd
  LEFT JOIN scored_prospects sp ON sp.crd IS NOT NULL AND SAFE_CAST(ROUND(SAFE_CAST(sp.crd AS FLOAT64), 0) AS INT64) = i.crd
),
-- ============================================================================
-- FUTUREPROOF OUTPUT: score_tier, V4, narrative = V3 narrative or actual exclusion reason
-- ============================================================================
final_output AS (
  SELECT
    i.crd,
    sp.score_tier,
    COALESCE(sp.v4_score, v4.v4_score) AS v4_score,
    COALESCE(sp.v4_percentile, v4.v4_percentile) AS v4_percentile,
    CASE
      WHEN sp.v3_score_narrative IS NOT NULL AND TRIM(sp.v3_score_narrative) != '' THEN sp.v3_score_narrative
      ELSE CONCAT(
        COALESCE(excl.exclusion_reason, 'Excluded (unknown)'),
        CASE
          WHEN v4.crd IS NOT NULL AND excl.exclusion_reason != 'No V4 score in prospect table' AND excl.exclusion_reason != 'V4 bottom 20% (deprioritized)'
          THEN CONCAT(' Has V4 score (percentile ', CAST(v4.v4_percentile AS STRING), ').')
          ELSE ''
        END
      )
    END AS narrative
  FROM input_crds i
  LEFT JOIN scored_prospects sp ON sp.crd IS NOT NULL AND SAFE_CAST(ROUND(SAFE_CAST(sp.crd AS FLOAT64), 0) AS INT64) = i.crd
  LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` v4
    ON v4.crd IS NOT NULL AND SAFE_CAST(ROUND(SAFE_CAST(v4.crd AS FLOAT64), 0) AS INT64) = i.crd
  LEFT JOIN exclusion_diagnostic excl ON i.crd = excl.crd
)
SELECT * FROM final_output ORDER BY crd
"""


def load_january_sql() -> str:
    """Load January lead list SQL and strip CREATE TABLE so it's a plain query."""
    path = JANUARY_SQL_PATH
    if not path.is_file():
        raise FileNotFoundError(f"January SQL not found: {path}")
    sql = path.read_text(encoding="utf-8")
    # Remove CREATE OR REPLACE TABLE ... AS so we can run as SELECT
    sql = re.sub(
        r"CREATE\s+OR\s+REPLACE\s+TABLE\s+`[^`]+`\s+AS\s*\n+",
        "",
        sql,
        flags=re.IGNORECASE,
    )
    return sql


def inject_input_crds(sql: str) -> str:
    """Add input_crds CTE at the start of WITH."""
    if "input_crds AS (" in sql:
        return sql  # Already injected
    input_crds_cte = """-- INPUT: CRD list from staging (populated from CSV)
input_crds AS (
  SELECT DISTINCT SAFE_CAST(crd AS INT64) AS crd
  FROM `savvy-gtm-analytics.ml_features.futureproof_crd_list`
  WHERE crd IS NOT NULL AND SAFE_CAST(crd AS INT64) IS NOT NULL
),

"""
    # Insert after "WITH\n" and the *entire* first comment line (do not split "-- ===...")
    match = re.search(r"WITH\s*\n\s*-- =[^\n]*\n", sql)
    if not match:
        raise ValueError("Could not find WITH block start in January SQL")
    pos = match.end()
    sql = sql[:pos] + input_crds_cte + sql[pos:]
    return sql


def inject_base_prospects_filter(sql: str) -> str:
    """Restrict base_prospects to input CRDs only."""
    if "IN (SELECT crd FROM input_crds)" in sql:
        return sql
    # Match the closing of base_prospects WHERE clause (title exclusions)
    old = (
        "OR UPPER(c.TITLE_NAME) LIKE '%VP %'  -- VP with space to avoid false positives\n"
        "      )\n"
        "),"
    )
    new = (
        "OR UPPER(c.TITLE_NAME) LIKE '%VP %'  -- VP with space to avoid false positives\n"
        "      )\n"
        "      AND SAFE_CAST(ROUND(SAFE_CAST(c.RIA_CONTACT_CRD_ID AS FLOAT64), 0) AS INT64) IN (SELECT crd FROM input_crds)\n"
        "),"
    )
    if old not in sql:
        raise ValueError("Could not find base_prospects WHERE end to add input_crds filter")
    sql = sql.replace(old, new)
    return sql


def replace_tail_with_final_output(sql: str) -> str:
    """Replace from ranked_prospects AS to end with final_output + SELECT."""
    marker = "\nranked_prospects AS ("
    idx = sql.find(marker)
    if idx == -1:
        raise ValueError("Could not find 'ranked_prospects AS (' in January SQL")
    return sql[:idx] + FINAL_SQL_SUFFIX


def build_futureproof_query() -> str:
    """Build the full Futureproof scoring query from January SQL."""
    sql = load_january_sql()
    sql = inject_input_crds(sql)
    sql = inject_base_prospects_filter(sql)
    sql = replace_tail_with_final_output(sql)
    return sql


def extract_crds_from_csv(path: Path, crd_column: str) -> list[tuple[int, dict]]:
    """Read CSV and return list of (crd_int, full_row_dict) for merging later."""
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if crd_column not in reader.fieldnames:
            raise SystemExit(
                f"CSV must have a column named '{crd_column}'. Found: {list(reader.fieldnames)}"
            )
        for row in reader:
            raw = row.get(crd_column, "").strip().replace(",", "").replace("$", "")
            try:
                c = int(float(raw)) if raw else None
            except (ValueError, TypeError):
                c = None
            if c is not None:
                rows.append((c, dict(row)))
    return rows


def upload_crds_to_bq(client: bigquery.Client, crds: list[int]) -> None:
    """Create or overwrite staging table with CRD list."""
    table_id = f"{PROJECT_ID}.{DATASET}.{STAGING_TABLE}"
    schema = [bigquery.SchemaField("crd", "INTEGER", mode="REQUIRED")]
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition="WRITE_TRUNCATE",
        create_disposition="CREATE_IF_NEEDED",
    )
    df = pd.DataFrame({"crd": crds})
    job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
    job.result()
    print(f"[INFO] Uploaded {len(crds)} CRDs to {table_id}")


def run_scoring_query(client: bigquery.Client) -> pd.DataFrame:
    """Run Futureproof scoring query and return dataframe."""
    query = build_futureproof_query()
    print("[INFO] Running lead-list scoring (FinTrx + V3 tier + V4)...")
    df = client.query(query).to_dataframe()
    print(f"[INFO] Query returned {len(df)} rows")
    return df


def main():
    parser = argparse.ArgumentParser(
        description="Score Futureproof CSV with full V3 tier + V4 (same logic as lead list)."
    )
    parser.add_argument(
        "input_csv",
        type=Path,
        help="Path to CSV with advisor CRDs (e.g. Futureproof participants).",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        default=None,
        help="Output CSV path. Default: input path with _scored suffix.",
    )
    parser.add_argument(
        "--crd-column",
        default=DEFAULT_CRD_COLUMN,
        help=f"Name of CRD column in CSV (default: {DEFAULT_CRD_COLUMN}).",
    )
    args = parser.parse_args()

    input_path = args.input_csv.resolve()
    if not input_path.is_file():
        raise SystemExit(f"Input file not found: {input_path}")

    output_path = args.output
    if output_path is None:
        output_path = input_path.parent / f"{input_path.stem}_scored.csv"
    else:
        output_path = output_path.resolve()

    rows_with_crd = extract_crds_from_csv(input_path, args.crd_column)
    if not rows_with_crd:
        raise SystemExit("No valid CRD values found in CSV.")

    crds = [c for c, _ in rows_with_crd]
    unique_crds = list(dict.fromkeys(crds))
    print(f"[INFO] Loaded {len(rows_with_crd)} rows, {len(unique_crds)} unique CRDs from {input_path}")

    client = bigquery.Client(project=PROJECT_ID)
    upload_crds_to_bq(client, unique_crds)
    scores_df = run_scoring_query(client)

    # Merge back: fill score_tier, v4_score, v4_percentile, narrative from query (preserve input column order)
    score_by_crd = scores_df.set_index("crd").to_dict("index") if not scores_df.empty else {}
    out_fieldnames = list(rows_with_crd[0][1].keys())  # preserve input CSV column order (no duplicate columns)
    score_columns = ["score_tier", "v4_score", "v4_percentile", "narrative"]  # columns the BQ query returns

    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=out_fieldnames, extrasaction="ignore")
        writer.writeheader()
        for crd, row in rows_with_crd:
            out = dict(row)
            rec = score_by_crd.get(crd, {})
            for col in score_columns:
                if col in out_fieldnames:
                    out[col] = rec.get(col, "")
            writer.writerow(out)

    print(f"[INFO] Wrote {len(rows_with_crd)} rows to {output_path}")
    if score_by_crd:
        with_tier = sum(1 for c, _ in rows_with_crd if score_by_crd.get(c, {}).get("score_tier"))
        print(f"[INFO] Rows with score_tier: {with_tier} (rest have V4 only or no match in FinTrx)")


if __name__ == "__main__":
    main()
