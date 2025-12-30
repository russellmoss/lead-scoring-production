"""Check Alpha Zero LLC partner/founder leads."""
import pandas as pd

df = pd.read_csv(r'C:\Users\russe\Documents\lead_scoring_production\pipeline\exports\january_2026_lead_list_20251226.csv')

alpha_zero = df[
    (df['firm_crd'] == 319050) & 
    ((df['job_title'].str.contains('Partner', case=False, na=False)) | 
     (df['job_title'].str.contains('Founder', case=False, na=False)))
]

print('Alpha Zero LLC Partner/Founder Leads:')
print()
for _, row in alpha_zero.iterrows():
    print(f'{row["first_name"]} {row["last_name"]} ({row["job_title"]})')
    print(f'  SGA: {row["sga_owner"]}')
    print()

if len(alpha_zero) > 0:
    unique_sgas = alpha_zero['sga_owner'].nunique()
    if unique_sgas == 1:
        print(f'[OK] All {len(alpha_zero)} leads assigned to same SGA: {alpha_zero["sga_owner"].iloc[0]}')
    else:
        print(f'[ISSUE] Leads assigned to {unique_sgas} different SGAs: {", ".join(alpha_zero["sga_owner"].unique())}')

