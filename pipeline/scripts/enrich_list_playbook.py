r"""
Enrich a list CSV with score_tier, v4_score, v4_percentile, narrative, grouping,
prospect_id, opportunity_id, disposition__c, closed_lost_details__c, closed_lost_reason__c.

Follows List Enrichment playbook: Phase 4 (lead scoring) + grouping (FinTrx firm) + Phase 5 (Salesforce).
Expects CSV to already have a CRD column (Phase 1–2 and Phase 3 can be run separately if needed).

Usage:
  python pipeline/scripts/enrich_list_playbook.py "C:\path\to\True advisors - Sheet1.csv"
  python pipeline/scripts/enrich_list_playbook.py <input_csv> [--output path] [--crd-column CRD]

Requires: google-cloud-bigquery, pandas. Auth: gcloud auth application-default login.
"""

import argparse
import csv
import re
from pathlib import Path

from google.cloud import bigquery
import pandas as pd

# Reuse scoring pipeline config
PROJECT_ID = "savvy-gtm-analytics"
DATASET = "ml_features"
STAGING_TABLE = "futureproof_crd_list"
JANUARY_SQL_PATH = Path(__file__).resolve().parents[1] / "sql" / "January_2026_Lead_List_V3_V4_Hybrid.sql"
DEFAULT_CRD_COLUMN = "CRD"

# Same final output + exclusion diagnostic as score_futureproof_csv
FINAL_SQL_SUFFIX = """,
-- ============================================================================
-- EXCLUSION DIAGNOSTIC
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

GROUPING_SALESFORCE_SQL = """
WITH
input_crds AS (
  SELECT DISTINCT SAFE_CAST(crd AS INT64) AS crd
  FROM `{project}.{dataset}.{table}`
  WHERE crd IS NOT NULL AND SAFE_CAST(crd AS INT64) IS NOT NULL
),
lead_one AS (
  SELECT
    SAFE_CAST(FA_CRD__c AS INT64) AS crd,
    Full_Prospect_ID__c AS prospect_id,
    Disposition__c AS disposition__c
  FROM (
    SELECT
      FA_CRD__c,
      Full_Prospect_ID__c,
      Disposition__c,
      ROW_NUMBER() OVER (PARTITION BY FA_CRD__c ORDER BY LastModifiedDate DESC NULLS LAST, Id) AS rn
    FROM `{project}.SavvyGTMData.Lead`
    WHERE IsDeleted = FALSE AND FA_CRD__c IS NOT NULL
  )
  WHERE rn = 1
),
opp_one AS (
  SELECT
    SAFE_CAST(FA_CRD__c AS INT64) AS crd,
    Full_Opportunity_ID__c AS opportunity_id,
    Closed_Lost_Details__c AS closed_lost_details__c,
    Closed_Lost_Reason__c AS closed_lost_reason__c
  FROM (
    SELECT
      FA_CRD__c,
      Full_Opportunity_ID__c,
      Closed_Lost_Details__c,
      Closed_Lost_Reason__c,
      ROW_NUMBER() OVER (PARTITION BY FA_CRD__c ORDER BY LastModifiedDate DESC NULLS LAST, Id) AS rn
    FROM `{project}.SavvyGTMData.Opportunity`
    WHERE IsDeleted = FALSE AND FA_CRD__c IS NOT NULL
  )
  WHERE rn = 1
)
SELECT
  i.crd,
  CASE
    WHEN f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH IS NOT NULL
         AND f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH <= 5
      THEN 'Independent advisor'
    WHEN (f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH IS NOT NULL
          AND f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH <= 15)
      OR (f.TOTAL_AUM IS NOT NULL AND f.TOTAL_AUM < 1000000000)
      THEN 'Small RIA'
    ELSE 'Everyone else'
  END AS `grouping`,
  l.prospect_id,
  o.opportunity_id,
  l.disposition__c,
  o.closed_lost_details__c,
  o.closed_lost_reason__c
FROM input_crds i
LEFT JOIN `{project}.FinTrx_data_CA.ria_contacts_current` c
  ON SAFE_CAST(ROUND(SAFE_CAST(c.RIA_CONTACT_CRD_ID AS FLOAT64), 0) AS INT64) = i.crd
LEFT JOIN `{project}.FinTrx_data_CA.ria_firms_current` f
  ON c.LATEST_REGISTERED_EMPLOYMENT_COMPANY_CRD_ID = f.CRD_ID
LEFT JOIN lead_one l ON i.crd = l.crd
LEFT JOIN opp_one o ON i.crd = o.crd
ORDER BY i.crd
"""


def load_january_sql() -> str:
    path = JANUARY_SQL_PATH
    if not path.is_file():
        raise FileNotFoundError(f"January SQL not found: {path}")
    sql = path.read_text(encoding="utf-8")
    sql = re.sub(
        r"CREATE\s+OR\s+REPLACE\s+TABLE\s+`[^`]+`\s+AS\s*\n+",
        "",
        sql,
        flags=re.IGNORECASE,
    )
    return sql


def inject_input_crds(sql: str) -> str:
    if "input_crds AS (" in sql:
        return sql
    input_crds_cte = """-- INPUT: CRD list from staging
input_crds AS (
  SELECT DISTINCT SAFE_CAST(crd AS INT64) AS crd
  FROM `savvy-gtm-analytics.ml_features.futureproof_crd_list`
  WHERE crd IS NOT NULL AND SAFE_CAST(crd AS INT64) IS NOT NULL
),

"""
    match = re.search(r"WITH\s*\n\s*-- =[^\n]*\n", sql)
    if not match:
        raise ValueError("Could not find WITH block start in January SQL")
    pos = match.end()
    return sql[:pos] + input_crds_cte + sql[pos:]


def inject_base_prospects_filter(sql: str) -> str:
    if "IN (SELECT crd FROM input_crds)" in sql:
        return sql
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
    return sql.replace(old, new)


def replace_tail_with_final_output(sql: str) -> str:
    marker = "\nranked_prospects AS ("
    idx = sql.find(marker)
    if idx == -1:
        raise ValueError("Could not find 'ranked_prospects AS (' in January SQL")
    return sql[:idx] + FINAL_SQL_SUFFIX


def build_scoring_query() -> str:
    sql = load_january_sql()
    sql = inject_input_crds(sql)
    sql = inject_base_prospects_filter(sql)
    sql = replace_tail_with_final_output(sql)
    return sql


def extract_rows_with_crd(path: Path, crd_column: str) -> list[tuple[int, dict]]:
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if crd_column not in (reader.fieldnames or []):
            raise SystemExit(
                f"CSV must have a column named '{crd_column}'. Found: {list(reader.fieldnames or [])}"
            )
        fieldnames = list(reader.fieldnames or [])
        for row in reader:
            raw = (row.get(crd_column) or "").strip().replace(",", "").replace("$", "")
            try:
                c = int(float(raw)) if raw else None
            except (ValueError, TypeError):
                c = None
            if c is not None:
                rows.append((c, dict(row)))
    return rows


def upload_crds_to_bq(client: bigquery.Client, crds: list[int]) -> None:
    table_id = f"{PROJECT_ID}.{DATASET}.{STAGING_TABLE}"
    schema = [bigquery.SchemaField("crd", "INTEGER", mode="REQUIRED")]
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition="WRITE_TRUNCATE",
        create_disposition="CREATE_IF_NEEDED",
    )
    df = pd.DataFrame({"crd": crds})
    client.load_table_from_dataframe(df, table_id, job_config=job_config).result()
    print(f"[INFO] Uploaded {len(crds)} CRDs to {table_id}")


def run_scoring_query(client: bigquery.Client) -> pd.DataFrame:
    query = build_scoring_query()
    print("[INFO] Running lead scoring (V3 + V4 + narrative)...")
    return client.query(query).to_dataframe()


def run_grouping_salesforce_query(client: bigquery.Client) -> pd.DataFrame:
    query = GROUPING_SALESFORCE_SQL.format(
        project=PROJECT_ID,
        dataset=DATASET,
        table=STAGING_TABLE,
    )
    print("[INFO] Running grouping + Salesforce lookup...")
    return client.query(query).to_dataframe()


def _safe_str(val) -> str:
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return ""
    return str(val).strip()


def main():
    parser = argparse.ArgumentParser(
        description="Enrich list CSV with score_tier, v4, narrative, grouping, Salesforce fields (playbook Phase 4+5)."
    )
    parser.add_argument("input_csv", type=Path, help="Path to CSV with CRD column.")
    parser.add_argument("--output", "-o", type=Path, default=None, help="Output CSV path.")
    parser.add_argument("--crd-column", default=DEFAULT_CRD_COLUMN, help=f"CRD column name (default: {DEFAULT_CRD_COLUMN}).")
    args = parser.parse_args()

    input_path = args.input_csv.resolve()
    if not input_path.is_file():
        raise SystemExit(f"Input file not found: {input_path}")

    output_path = args.output or input_path.parent / f"{input_path.stem}_enriched.csv"
    output_path = output_path.resolve()

    rows_with_crd = extract_rows_with_crd(input_path, args.crd_column)
    if not rows_with_crd:
        raise SystemExit("No valid CRD values found in CSV.")

    crds = list(dict.fromkeys(c for c, _ in rows_with_crd))
    print(f"[INFO] Loaded {len(rows_with_crd)} rows, {len(crds)} unique CRDs from {input_path}")

    client = bigquery.Client(project=PROJECT_ID)
    upload_crds_to_bq(client, crds)
    scores_df = run_scoring_query(client)
    group_sf_df = run_grouping_salesforce_query(client)

    score_by_crd = scores_df.set_index("crd").to_dict("index") if not scores_df.empty else {}
    group_sf_by_crd = group_sf_df.set_index("crd").to_dict("index") if not group_sf_df.empty else {}

    score_cols = ["score_tier", "v4_score", "v4_percentile", "narrative"]
    extra_cols = ["grouping", "prospect_id", "opportunity_id", "disposition__c", "closed_lost_details__c", "closed_lost_reason__c"]
    out_fieldnames = list(rows_with_crd[0][1].keys())
    for col in score_cols + extra_cols:
        if col not in out_fieldnames:
            out_fieldnames.append(col)

    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=out_fieldnames, extrasaction="ignore")
        writer.writeheader()
        for crd, row in rows_with_crd:
            out = dict(row)
            rec_score = score_by_crd.get(crd, {})
            rec_sf = group_sf_by_crd.get(crd, {})
            for col in score_cols:
                out[col] = _safe_str(rec_score.get(col, ""))
            for col in extra_cols:
                out[col] = _safe_str(rec_sf.get(col, ""))
            writer.writerow(out)

    print(f"[INFO] Wrote {len(rows_with_crd)} rows to {output_path}")
    with_tier = sum(1 for c, _ in rows_with_crd if score_by_crd.get(c, {}).get("score_tier"))
    print(f"[INFO] Rows with score_tier: {with_tier}")


if __name__ == "__main__":
    main()
