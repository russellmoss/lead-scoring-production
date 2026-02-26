# Top 10th Percentile 51-Advisor List - Quick Start Guide

## Overview

This methodology generates a curated list of **51 advisors** that are:
- In the **top 10th percentile of V4 scores** (`v4_percentile >= 90`)
- In one of three specific V3 tiers:
  - `TIER_0C_CLOCKWORK_DUE` (~17 advisors)
  - `TIER_1B_PRIME_MOVER_SERIES65` (~17 advisors)
  - `TIER_2_PROVEN_MOVER` (~17 advisors)
- **Not already in Salesforce** (excluded via BigQuery check)

## Quick Start

### Step 1: Run SQL Query

**File**: `pipeline/sql/Top_10_Percentile_51_Advisor_List.sql`

Execute in BigQuery Console:
```sql
-- Creates: ml_features.top_10_percentile_51_advisor_list
```

### Step 2: Export to CSV

**File**: `pipeline/scripts/generate_top_10_percentile_list.py`

```bash
cd pipeline
python scripts/generate_top_10_percentile_list.py
```

**Output**: `pipeline/exports/top_10_percentile_51_advisor_list_YYYYMMDD.csv`

## Distribution Logic

The query uses a smart distribution algorithm:

1. **Initial Quota**: Takes up to 17 advisors from each tier (ranked by V4 percentile)
2. **Gap Filling**: If one tier has fewer than 17 available, fills remaining slots from other tiers
3. **Final Count**: Always produces exactly 51 advisors (or fewer if total available < 51)

## Tier Definitions

### TIER_0C_CLOCKWORK_DUE
- Predictable career pattern (Career Clock)
- Currently in move window (70-130% through typical tenure)
- Not a wirehouse
- **Expected Conversion**: 5.07%

### TIER_1B_PRIME_MOVER_SERIES65
- Series 65 only (no Series 7)
- Prime Mover criteria (1-3 years tenure, 5-15 years experience, firm bleeding)
- **Expected Conversion**: 5.49%

### TIER_2_PROVEN_MOVER
- 3+ prior firms
- 5+ years industry experience
- **Expected Conversion**: 5.2%

## Exclusions Applied

Same as January lead list:
- ✅ Salesforce exclusions (by CRD matching)
- ✅ Age over 70
- ✅ Regulatory/legal disclosures
- ✅ Wirehouses and excluded firms
- ✅ Non-producing titles (paraplanner, assistant, etc.)

## Validation

After running, verify:
- [ ] Total advisors: 51 (or fewer if not enough available)
- [ ] All advisors: `v4_percentile >= 90`
- [ ] No duplicate CRDs
- [ ] All advisors not in Salesforce

## Files Created

1. **SQL Query**: `pipeline/sql/Top_10_Percentile_51_Advisor_List.sql`
2. **Python Script**: `pipeline/scripts/generate_top_10_percentile_list.py`
3. **Full Guide**: `pipeline/docs/TOP_10_PERCENTILE_51_ADVISOR_LIST_GUIDE.md`
4. **This Summary**: `pipeline/docs/TOP_10_PERCENTILE_51_ADVISOR_LIST_SUMMARY.md`

## Next Steps

1. Review the generated CSV
2. Import into Salesforce or other CRM
3. Begin targeted outreach
4. Track conversion rates to validate performance
