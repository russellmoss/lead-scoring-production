"""Validate that partner/founder leads from same firm are assigned to same SGA."""
from google.cloud import bigquery

client = bigquery.Client(project='savvy-gtm-analytics')

# Check firms with multiple partner/founder leads
query = """
SELECT 
    firm_crd,
    firm_name,
    COUNT(*) as count,
    COUNT(DISTINCT sga_owner) as unique_sgas,
    STRING_AGG(DISTINCT sga_owner, ', ' ORDER BY sga_owner) as assigned_sgas
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
WHERE UPPER(COALESCE(job_title, '')) LIKE '%PARTNER%'
   OR UPPER(COALESCE(job_title, '')) LIKE '%FOUNDER%'
GROUP BY firm_crd, firm_name
HAVING COUNT(*) > 1
ORDER BY count DESC
"""

print("Validating Partner/Founder SGA Grouping...")
print("=" * 60)
result = client.query(query).result()
rows = list(result)

print(f"\nFirms with multiple partner/founder leads: {len(rows)}")
print()

all_ok = True
for row in rows:
    status = "[OK]" if row.unique_sgas == 1 else "[ISSUE]"
    if row.unique_sgas > 1:
        all_ok = False
    print(f"{row.firm_name} (CRD: {row.firm_crd})")
    print(f"  Leads: {row.count}, SGAs: {row.unique_sgas} - {status}")
    if row.unique_sgas > 1:
        print(f"  Multiple SGAs: {row.assigned_sgas}")
    print()

# Check Alpha Zero LLC specifically
print("=" * 60)
print("Alpha Zero LLC (CRD: 319050) - Detailed Check:")
print()

query2 = """
SELECT 
    advisor_crd,
    first_name,
    last_name,
    job_title,
    firm_name,
    firm_crd,
    sga_owner,
    sga_id,
    list_rank
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
WHERE firm_crd = 319050
  AND (UPPER(COALESCE(job_title, '')) LIKE '%PARTNER%'
       OR UPPER(COALESCE(job_title, '')) LIKE '%FOUNDER%')
ORDER BY list_rank
"""

result2 = client.query(query2).result()
rows2 = list(result2)

if len(rows2) > 0:
    sgas = set(r.sga_owner for r in rows2)
    print(f"  Found {len(rows2)} partner/founder leads")
    print(f"  Assigned to {len(sgas)} SGA(s): {', '.join(sorted(sgas))}")
    print()
    for row in rows2:
        print(f"  {row.first_name} {row.last_name}")
        print(f"    Title: {row.job_title}")
        print(f"    SGA: {row.sga_owner}, Rank: {row.list_rank}")
        print()
    
    if len(sgas) == 1:
        print("  [OK] All partner/founder leads assigned to same SGA")
    else:
        print(f"  [ISSUE] Leads assigned to {len(sgas)} different SGAs")
        all_ok = False
else:
    print("  No partner/founder leads found for this firm")

print("=" * 60)
if all_ok:
    print("[PASS] VALIDATION PASSED: All partner/founder leads from same firm have same SGA")
else:
    print("[FAIL] VALIDATION FAILED: Some firms have partner/founder leads assigned to different SGAs")

