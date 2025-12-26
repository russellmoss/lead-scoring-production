# Partner/Founder SGA Assignment Logic

## 🎯 **PURPOSE**

Ensure that all leads with "partner" or "founder" in their job title from the same firm are assigned to the **same SGA**. This prevents multiple SGAs from reaching out to the same firm's leadership team, which could cause confusion and reduce conversion rates.

## 📊 **EXAMPLE**

**Before Fix:**
- Eric Mechler (Founder, Managing Partner) → Alpha Zero LLC → Assigned to Eleni Stefanopoulos
- Jordan Grabowski (Founder & Managing Partner) → Alpha Zero LLC → Assigned to Helen Kamens
- **Problem**: Two SGAs reaching out to the same firm's leadership

**After Fix:**
- Eric Mechler (Founder, Managing Partner) → Alpha Zero LLC → Assigned to Eleni Stefanopoulos
- Jordan Grabowski (Founder & Managing Partner) → Alpha Zero LLC → Assigned to Eleni Stefanopoulos (same SGA)
- **Solution**: Both leads assigned to the highest-ranked lead's SGA

## ✅ **IMPLEMENTATION**

### 1. SQL Query Changes

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Added CTEs**:

1. **`leads_assigned`** (modified):
   - Added `is_partner_founder` flag (case-insensitive check for "PARTNER" or "FOUNDER" in job_title)

2. **`partner_founder_groups`** (new):
   - Groups partner/founder leads by `firm_crd`
   - Identifies the SGA assigned to the highest-ranked (lowest `overall_rank`) lead in each firm group
   - This SGA becomes the "group SGA" for all partner/founder leads from that firm

3. **`leads_with_partner_founder_fix`** (new):
   - Updates SGA assignment for partner/founder leads
   - If lead is partner/founder AND has a group SGA, use the group SGA
   - Otherwise, keep the original round-robin assignment

**Logic**:
```sql
-- Flag partner/founder leads
CASE 
    WHEN UPPER(COALESCE(job_title, '')) LIKE '%PARTNER%' 
         OR UPPER(COALESCE(job_title, '')) LIKE '%FOUNDER%' 
    THEN 1 
    ELSE 0 
END as is_partner_founder

-- Get group SGA (highest-ranked lead's SGA)
FIRST_VALUE(assigned_sga_num) OVER (
    PARTITION BY firm_crd
    ORDER BY overall_rank
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
) as group_sga_num

-- Apply group SGA to partner/founder leads
CASE 
    WHEN is_partner_founder = 1 AND group_sga_num IS NOT NULL 
    THEN group_sga_num
    ELSE assigned_sga_num
END as final_assigned_sga_num
```

## 🔍 **VALIDATION QUERIES**

### Check Partner/Founder Leads by Firm
```sql
SELECT 
    firm_crd,
    firm_name,
    COUNT(*) as partner_founder_count,
    COUNT(DISTINCT sga_owner) as unique_sgas,
    STRING_AGG(DISTINCT sga_owner, ', ') as assigned_sgas
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
WHERE UPPER(COALESCE(job_title, '')) LIKE '%PARTNER%'
   OR UPPER(COALESCE(job_title, '')) LIKE '%FOUNDER%'
GROUP BY firm_crd, firm_name
HAVING COUNT(*) > 1  -- Only show firms with multiple partner/founder leads
ORDER BY partner_founder_count DESC;
-- Expected: All leads from same firm should have same sga_owner
```

### Verify Alpha Zero LLC Example
```sql
SELECT 
    advisor_crd,
    first_name,
    last_name,
    job_title,
    firm_name,
    firm_crd,
    sga_owner,
    sga_id,
    overall_rank
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
WHERE firm_crd = 319050  -- Alpha Zero LLC
ORDER BY overall_rank;
-- Expected: Both Eric Mechler and Jordan Grabowski should have same sga_owner
```

## 📈 **EXPECTED RESULTS**

### Before Fix:
- Multiple partner/founder leads from same firm → Different SGAs
- Risk of duplicate outreach and confusion

### After Fix:
- All partner/founder leads from same firm → Same SGA
- Single point of contact for firm leadership
- Better coordination and higher conversion rates

## 🚀 **NEXT STEPS**

1. **Re-run Step 3** (Lead list generation) to apply partner/founder grouping
2. **Validate** using queries above
3. **Re-run Step 4** (Export) to generate new CSV with corrected SGA assignments

## 📝 **FILES MODIFIED**

1. `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
   - Added `is_partner_founder` flag to `leads_assigned` CTE
   - Added `partner_founder_groups` CTE
   - Added `leads_with_partner_founder_fix` CTE
   - Updated `leads_with_sga` to use `leads_with_partner_founder_fix`

2. `pipeline/January_2026_Lead_List_V3_V4_Hybrid.sql`
   - Same changes as above (kept in sync)

## ⚠️ **NOTES**

- **Case-insensitive matching**: "Partner", "partner", "PARTNER", "Founder", "founder", "FOUNDER" all match
- **Partial matching**: "Managing Partner", "Co-Founder", "Founding Partner" all match
- **Highest-ranked lead**: The lead with the lowest `overall_rank` (best quality) determines the group SGA
- **Non-partner/founder leads**: Unaffected by this logic, still use round-robin assignment

