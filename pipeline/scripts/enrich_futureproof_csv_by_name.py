r"""
Enrich Futureproof CSV with FinTrx data by matching on name (for rows with no CRD).

For rows that don't have a CRD (already matched via LinkedIn), tries to find exactly one
person in FinTrx_data_CA.ria_contacts_current by first + last name. Uses:
  CONTACT_FIRST_NAME, CONTACT_LAST_NAME, RIA_CONTACT_PREFERRED_NAME, RIA_CONTACT_FIRST_NAME_OTHER.

- If exactly one match: fills CRD, PRIMARY_FIRM_TOTAL_AUM, REP_AUM, PRODUCING_ADVISOR;
  puts FinTrx LINKEDIN_PROFILE_URL in column D (linkedin); adds "matched on name" = TRUE,
  name_match_note = "".
- If multiple matches: does not fill CRD/AUM; sets "matched on name" = TRUE,
  name_match_note = "(multiple matches)".
- If zero matches: "matched on name" = FALSE, name_match_note = "".

Does not alter any row that already has a CRD (those were LinkedIn-matched and are trusted).

Reference: Wayne Anderman (CRD 1271816) and Rich Allridge (CRD 6121407) are single matches
in FinTrx by name (Wayne Anderman; Richard Allridge).

Usage:
  python pipeline/scripts/enrich_futureproof_csv_by_name.py "C:\Users\russe\Documents\lead_scoring_production\futureproof_FINAL_2056_participants - Futureproof advisors.csv"
  python pipeline/scripts/enrich_futureproof_csv_by_name.py <csv_path> [--output <path>] [--dry-run]

Requires: google-cloud-bigquery. Auth: gcloud auth application-default login.
"""

import argparse
import csv
import re
from pathlib import Path

from google.cloud import bigquery

PROJECT_ID = "savvy-gtm-analytics"
FINTRX_DATASET = "FinTrx_data_CA"
CONTACTS_TABLE = "ria_contacts_current"
FIRMS_TABLE = "ria_firms_current"

# Column names in CSV (order must match)
COL_FIRM = "firm"
COL_NAME = "name"
COL_TITLE = "title"
COL_LINKEDIN = "linkedin"
COL_CRD = "CRD"
COL_PRIMARY_FIRM_TOTAL_AUM = "PRIMARY_FIRM_TOTAL_AUM"
COL_REP_AUM = "REP_AUM"
COL_PRODUCING_ADVISOR = "PRODUCING_ADVISOR"
COL_MATCHED_ON_NAME = "matched on name"
COL_NAME_MATCH_NOTE = "name_match_note"


def _parse_name(full_name: str) -> tuple[str, str]:
    """Split 'First Last' or 'First Middle Last' -> (first_name, last_name). First word = first, rest = last."""
    s = (full_name or "").strip()
    if not s:
        return "", ""
    parts = s.split()
    if len(parts) == 1:
        return parts[0], ""
    return parts[0], " ".join(parts[1:]).strip()


def _has_crd(row: dict, crd_col: str) -> bool:
    """True if row has a non-empty CRD value."""
    v = (row.get(crd_col) or "").strip()
    if not v:
        return False
    # Reject placeholder or non-numeric
    try:
        int(float(v))
        return True
    except (ValueError, TypeError):
        return False


def _format_currency(val) -> str:
    """Format number as $X,XXX,XXX.XX for CSV."""
    if val is None:
        return ""
    try:
        n = float(val)
        return f"${n:,.2f}"
    except (TypeError, ValueError):
        return str(val) if val else ""


def _query_name_matches(client: bigquery.Client, first_name: str, last_name: str, full_name: str) -> list[dict]:
    """Return list of FinTrx contact rows matching this name (0, 1, or many)."""
    first = (first_name or "").strip().lower()
    last = (last_name or "").strip().lower()
    full = (full_name or "").strip().lower()
    if not last:
        return []

    contacts = f"`{PROJECT_ID}.{FINTRX_DATASET}.{CONTACTS_TABLE}`"
    firms = f"`{PROJECT_ID}.{FINTRX_DATASET}.{FIRMS_TABLE}`"

    sql = f"""
    SELECT
      c.RIA_CONTACT_CRD_ID AS crd,
      c.LINKEDIN_PROFILE_URL AS linkedin_profile_url,
      c.REP_AUM AS rep_aum,
      c.PRODUCING_ADVISOR AS producing_advisor,
      COALESCE(c.PRIMARY_FIRM_TOTAL_AUM, f.TOTAL_AUM) AS primary_firm_total_aum
    FROM {contacts} c
    LEFT JOIN {firms} f ON c.PRIMARY_FIRM = f.CRD_ID
    WHERE LOWER(TRIM(c.CONTACT_LAST_NAME)) = @last
      AND (
        LOWER(TRIM(c.CONTACT_FIRST_NAME)) = @first
        OR LOWER(TRIM(COALESCE(c.RIA_CONTACT_FIRST_NAME_OTHER, c.CONTACT_FIRST_NAME))) = @first
        OR LOWER(TRIM(c.RIA_CONTACT_PREFERRED_NAME)) = @full
      )
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("first", "STRING", first),
            bigquery.ScalarQueryParameter("last", "STRING", last),
            bigquery.ScalarQueryParameter("full", "STRING", full),
        ]
    )
    rows = list(client.query(sql, job_config=job_config).result())
    return [dict(r) for r in rows]


def run(csv_path: Path, output_path: Path | None, dry_run: bool) -> None:
    csv_path = Path(csv_path)
    output_path = output_path or csv_path.parent / (csv_path.stem + "_enriched_by_name.csv")

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames or [])
        rows = list(reader)

    # Add new columns if not present
    if COL_MATCHED_ON_NAME not in fieldnames:
        fieldnames.append(COL_MATCHED_ON_NAME)
    if COL_NAME_MATCH_NOTE not in fieldnames:
        fieldnames.append(COL_NAME_MATCH_NOTE)

    client = bigquery.Client(project=PROJECT_ID)
    name_col = COL_NAME
    crd_col = COL_CRD

    no_crd_indices = [i for i, row in enumerate(rows) if not _has_crd(row, crd_col)]
    print(f"Rows without CRD: {len(no_crd_indices)} of {len(rows)}")

    for i in no_crd_indices:
        row = rows[i]
        full_name = (row.get(name_col) or "").strip()
        first_name, last_name = _parse_name(full_name)
        row[COL_MATCHED_ON_NAME] = ""
        row[COL_NAME_MATCH_NOTE] = ""

        if not last_name:
            row[COL_MATCHED_ON_NAME] = "FALSE"
            continue

        matches = _query_name_matches(client, first_name, last_name, full_name)

        if len(matches) == 0:
            row[COL_MATCHED_ON_NAME] = "FALSE"
        elif len(matches) == 1:
            m = matches[0]
            row[COL_CRD] = str(int(m["crd"])) if m.get("crd") is not None else ""
            row[COL_PRIMARY_FIRM_TOTAL_AUM] = _format_currency(m.get("primary_firm_total_aum"))
            row[COL_REP_AUM] = _format_currency(m.get("rep_aum"))
            row[COL_PRODUCING_ADVISOR] = "TRUE" if m.get("producing_advisor") else "FALSE"
            if m.get("linkedin_profile_url"):
                row[COL_LINKEDIN] = (m.get("linkedin_profile_url") or "").strip()
            row[COL_MATCHED_ON_NAME] = "TRUE"
        else:
            row[COL_MATCHED_ON_NAME] = "TRUE"
            row[COL_NAME_MATCH_NOTE] = "(multiple matches)"

    if dry_run:
        print("Dry run: not writing. Sample of changes (first 5 no-CRD rows):")
        for i in no_crd_indices[:5]:
            r = rows[i]
            print(f"  {r.get(name_col)} -> CRD={r.get(crd_col)} matched={r.get(COL_MATCHED_ON_NAME)} note={r.get(COL_NAME_MATCH_NOTE)}")
        return

    with open(output_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print(f"Wrote {output_path}")


def main():
    p = argparse.ArgumentParser(description="Enrich Futureproof CSV by matching on name in FinTrx (rows with no CRD).")
    p.add_argument("csv_path", type=Path, help="Path to Futureproof CSV")
    p.add_argument("--output", "-o", type=Path, default=None, help="Output CSV path (default: <csv_stem>_enriched_by_name.csv)")
    p.add_argument("--dry-run", action="store_true", help="Do not write; print sample of no-CRD rows")
    args = p.parse_args()
    run(args.csv_path, args.output, args.dry_run)


if __name__ == "__main__":
    main()
