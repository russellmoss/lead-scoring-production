# Lead List Generation Guide (V3.2.1)

**Last Updated:** January 2025  
**Model Version:** V3.2.1_12212025 (with CFP and Series 65 certification tiers)

---

## Quick Start

### Option 1: Use the Reusable Template (Recommended)

1. **Open:** `sql/generate_lead_list_v3.2.1.sql`
2. **Replace placeholders:**
   - `{TABLE_NAME}` → Your table name (e.g., `february_2026_lead_list`)
   - `{LEAD_LIMIT}` → Number of leads (default: `2400`)
   - `{RECYCLABLE_DAYS}` → Days threshold for re-engagement (default: `180`)
3. **Execute in BigQuery**

### Option 2: Use Existing Monthly Query

If you have a monthly query (like `January_2026_Lead_List_Query_V3.2.sql`), you can:
- Copy it and update the table name
- Update the model version references if needed
- Execute in BigQuery

---

## What Gets Included

### 1. New Prospects (Not in Salesforce)
- Advisors from FINTRX `ria_contacts_current` who are NOT in Salesforce
- Excludes wirehouses and collapsed firms
- Prioritized over recyclable leads

### 2. Recyclable Leads (Re-engagement)
- Leads in Salesforce with **180+ days** since last SMS/Call activity
- **Not DNC** (Do Not Call = false)
- **Not in bad status** (excludes: Closed, Converted, Dead, Unqualified, etc.)
- Only includes leads that can be re-engaged

### 3. Tier Scoring (V3.2.1)
- **Tier 1A:** CFP holders at bleeding firms (16.44% conversion)
- **Tier 1B:** Series 65 only (pure RIA) meeting Tier 1 criteria (16.48% conversion)
- **Tier 1:** Standard Prime Movers (13.21% conversion)
- **Tier 2-5:** Other priority tiers
- **Standard:** Baseline (3.82% conversion)

### 4. Firm Diversity Cap
- Maximum **50 leads per firm** (ensures diversity)
- Prevents over-concentration in single firms

---

## Ranking Logic

Leads are ranked by:

1. **Source Priority:**
   - New prospects = Priority 1
   - Recyclable leads = Priority 2

2. **Tier Priority:**
   - Tier 1A (CFP) = Rank 1
   - Tier 1B (Series 65) = Rank 2
   - Tier 1 (Standard) = Rank 3
   - Tier 2-5 = Ranks 4-7
   - Standard = Rank 8

3. **Firm Bleeding:**
   - More negative `firm_net_change_12mo` = higher priority
   - Indicates more unstable firms

4. **Within Firm:**
   - New prospects prioritized over recyclable
   - Then by tier priority
   - Then by CRD (for consistency)

---

## Output Table Structure

| Column | Description |
|--------|-------------|
| `advisor_crd` | Advisor CRD number |
| `salesforce_lead_id` | Salesforce Lead ID (if recyclable) |
| `first_name`, `last_name`, `email`, `phone` | Contact information |
| `firm_name`, `firm_crd` | Firm information |
| `firm_rep_count` | Current firm size |
| `firm_net_change_12mo` | Net change in advisors (negative = bleeding) |
| `tenure_years`, `industry_tenure_years` | Experience metrics |
| `score_tier` | Tier assignment (TIER_1A_PRIME_MOVER_CFP, etc.) |
| `priority_rank` | Numeric priority (1-8, lower = higher priority) |
| `expected_conversion_rate` | Expected conversion rate (0.1644 = 16.44%) |
| `score_narrative` | **Detailed explanation for SGAs** - includes certification context |
| `has_cfp`, `has_series_65_only`, `has_series_7`, `has_cfa` | Certification flags |
| `prospect_type` | NEW_PROSPECT or IN_SALESFORCE |
| `lead_source_description` | Human-readable source description |
| `list_rank` | Final ranking (1 to {LEAD_LIMIT}) |
| `generated_at` | Timestamp of generation |

---

## Best Practices

### 1. Frequency
- **Monthly:** Generate new list at start of each month
- **Weekly:** Optional refresh for high-volume teams
- **Ad-hoc:** Generate for special campaigns

### 2. Lead Limit
- **2,400 leads/month:** Standard for ~80 leads/day
- **Adjust based on:** Team size, conversion rates, capacity

### 3. Recyclable Days Threshold
- **180 days:** Standard (6 months)
- **90 days:** More aggressive re-engagement
- **365 days:** Conservative (1 year)

### 4. Table Naming
- Use format: `{month}_{year}_lead_list` (e.g., `february_2026_lead_list`)
- Makes it easy to track historical lists

### 5. Validation
After generating, check:
```sql
-- Tier distribution
SELECT 
    score_tier,
    COUNT(*) as lead_count,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_rate_pct
FROM `savvy-gtm-analytics.ml_features.{YOUR_TABLE_NAME}`
GROUP BY score_tier
ORDER BY 
    CASE score_tier
        WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
        WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
        WHEN 'TIER_1_PRIME_MOVER' THEN 3
        ELSE 99
    END;

-- Source breakdown
SELECT 
    prospect_type,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as pct
FROM `savvy-gtm-analytics.ml_features.{YOUR_TABLE_NAME}`
GROUP BY prospect_type;

-- Certification flags
SELECT 
    COUNT(*) as total,
    SUM(has_cfp) as with_cfp,
    SUM(has_series_65_only) as with_series65_only,
    SUM(has_series_7) as with_series7,
    SUM(has_cfa) as with_cfa
FROM `savvy-gtm-analytics.ml_features.{YOUR_TABLE_NAME}`;
```

---

## Using the Generated List

### 1. Export to CSV
```sql
-- Export for Salesforce import or outreach tools
SELECT * 
FROM `savvy-gtm-analytics.ml_features.{YOUR_TABLE_NAME}`
ORDER BY list_rank;
```

### 2. Connect to Dashboard
- Use the table in Looker/Data Studio
- Filter by `score_tier` for tier-specific views
- Use `score_narrative` for SGA context

### 3. Salesforce Integration
- Use `salesforce_lead_id` to update existing leads
- Use `advisor_crd` to create new leads
- Map `score_tier` to `Lead_Score_Tier__c`
- Map `score_narrative` to `Lead_Tier_Explanation__c`

---

## Troubleshooting

### Issue: No leads in output
- **Check:** Are there new prospects in FINTRX?
- **Check:** Are recyclable leads meeting the 180-day threshold?
- **Check:** Are firms being excluded (wirehouses, collapsed firms)?

### Issue: Too many leads from one firm
- **Check:** Firm diversity cap (should be max 50 per firm)
- **Verify:** `rank_within_firm <= 50` filter is working

### Issue: Missing certification tiers
- **Verify:** Certification detection logic is working
- **Check:** `has_cfp` and `has_series_65_only` flags are populated
- **Note:** Not all leads will have certifications

### Issue: Recyclable leads not appearing
- **Check:** Last activity date calculation
- **Verify:** Lead status is not excluded
- **Verify:** `DoNotCall` is false

---

## Example: Generate February 2026 List

```sql
-- Step 1: Open generate_lead_list_v3.2.1.sql
-- Step 2: Replace:
--   {TABLE_NAME} → february_2026_lead_list
--   {LEAD_LIMIT} → 2400
--   {RECYCLABLE_DAYS} → 180
-- Step 3: Execute in BigQuery
-- Step 4: Validate results
```

---

## Related Resources

- **Model Report:** `VERSION_3_MODEL_REPORT.md`
- **Model Registry:** `models/model_registry_v3.json`
- **Production View:** `ml_features.lead_scores_v3_current`
- **SGA Dashboard:** `ml_features.sga_priority_leads_v3`

---

## Support

For questions or issues:
1. Check the model registry for tier definitions
2. Review the tier explanations in `score_narrative` column
3. Validate against production view: `ml_features.lead_scores_v3_current`

