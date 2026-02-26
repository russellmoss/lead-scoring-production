"""Build P column (grouping) for Futureproof advisors from Extract_Lookup data."""
import json
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
EXTRACT_PATH = r"C:\Users\russe\.cursor\projects\c-Users-russe-Documents-lead-scoring-production\agent-tools\444dd25d-404c-472a-a946-56d5bed6f60e.txt"
CRDS_PATH = os.path.join(SCRIPT_DIR, "futureproof_crds.json")

def main():
    with open(EXTRACT_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    rows = data.get("values", [])
    crd_to_grouping = {str(row[0]): row[15] for row in rows[1:] if len(row) > 15}

    with open(CRDS_PATH, "r", encoding="utf-8") as f:
        crds = json.load(f)

    result = [[crd_to_grouping.get(str(crd[0]), "")] for crd in crds]
    print(json.dumps(result))

if __name__ == "__main__":
    main()
