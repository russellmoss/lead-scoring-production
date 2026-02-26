# Top 10th Percentile 51-Advisor List Generation Guide

## Overview

This guide provides step-by-step instructions for generating a curated list of 51 advisors that meet the following criteria:

1. **Top 10th Percentile V4 Score**: `v4_percentile >= 90`
2. **Specific V3 Tiers**: 
   - `TIER_0C_CLOCKWORK_DUE` (~17 advisors)
   - `TIER_1B_PRIME_MOVER_SERIES65` (~17 advisors)
   - `TIER_2_PROVEN_MOVER` (~17 advisors)
3. **Not in Salesforce**: Excludes advisors already in Salesforce (checked against BigQuery)
4. **Standard Exclusions**: Age over 70, disclosures, wirehouses, etc.

## Methodology

### Step 1: Prerequisites

Ensure the following are in place:

- ✅ V4 prospect scores table exists: `ml_features.v4_prospect_scores`
- ✅ Excluded firms table exists: `ml_features.excluded_firms`
- ✅ Excluded firm CRDs table exists: `ml_features.excluded_firm_crds`
- ✅ BigQuery access configured
- ✅ Python environment with `google-cloud-bigquery` and `pandas`

### Step 2: Execute SQL Query

**File**: `pipeline/sql/Top_10_Percentile_51_Advisor_List.sql`

**What It Does**:
1. Excludes advisors already in Salesforce (by CRD matching)
2. Applies standard exclusions (age, disclosures, wirehouses, etc.)
3. Enriches with advisor history, firm metrics, and certifications
4. Filters to top 10th percentile V4 scores (`v4_percentile >= 90`)
5. Applies V3 tier logic for the three target tiers:
   - **TIER_0C_CLOCKWORK_DUE**: Predictable advisors in move window
   - **TIER_1B_PRIME_MOVER_SERIES65**: Series 65 only + Prime Mover criteria
   - **TIER_2_PROVEN_MOVER**: 3+ prior firms
6. Ranks within each tier by V4 percentile (highest first)
7. Distributes 51 advisors (~17 per tier, adjusting if one tier doesn't have enough)

**Execution**:
```sql
-- Run in BigQuery Console
-- Location: northamerica-northeast2 (Toronto)
-- Creates: ml_features.top_10_percentile_51_advisor_list
```

**Validation Query**:
```sql
SELECT 
    score_tier,
    COUNT(*) as count,
    MIN(v4_percentile) as min_v4,
    MAX(v4_percentile) as max_v4,
    AVG(v4_percentile) as avg_v4
FROM `savvy-gtm-analytics.ml_features.top_10_percentile_51_advisor_list`
GROUP BY score_tier
ORDER BY score_tier;
```

**Expected Results**:
- Total advisors: 51
- All advisors: `v4_percentile >= 90`
- Distribution: ~17 per tier (may vary if one tier has fewer available)

### Step 3: Export to CSV

**File**: `pipeline/scripts/generate_top_10_percentile_list.py`

**What It Does**:
1. Executes the SQL query (if not already run)
2. Fetches results from BigQuery
3. Validates data quality (count, V4 percentile, tier distribution)
4. Exports to CSV with all required columns
5. Logs results to `pipeline/logs/EXECUTION_LOG.md`

**Execution**:
```bash
cd pipeline
python scripts/generate_top_10_percentile_list.py
```

**Output File**: `pipeline/exports/top_10_percentile_51_advisor_list_YYYYMMDD.csv`

**CSV Columns** (31 total):
- `advisor_crd`: FINTRX CRD ID
- `first_name`: Contact first name
- `last_name`: Contact last name
- `email`: Email address
- `phone`: Phone number
- `linkedin_url`: LinkedIn profile URL
- `job_title`: Advisor's job title
- `firm_name`: Firm name
- `firm_crd`: Firm CRD ID
- `firm_rep_count`: Number of reps at firm
- `firm_net_change_12mo`: Firm net change (arrivals - departures)
- `tenure_months`: Months at current firm
- `tenure_years`: Years at current firm
- `industry_tenure_years`: Total years in industry
- `num_prior_firms`: Number of prior firms
- `moves_3yr`: Moves in last 3 years
- `score_tier`: V3 tier assignment
- `priority_rank`: Priority rank within tier
- `v4_score`: V4 XGBoost score
- `v4_percentile`: V4 percentile rank (90-100)
- `has_series_65_only`: Series 65 only flag
- `has_cfp`: CFP designation flag
- `cc_career_pattern`: Career Clock pattern
- `cc_cycle_status`: Career Clock cycle status
- `cc_pct_through_cycle`: Percent through typical cycle
- `cc_is_in_move_window`: In move window flag
- `shap_top1_feature`: Top V4 feature
- `shap_top2_feature`: Second V4 feature
- `shap_top3_feature`: Third V4 feature
- `v4_narrative`: V4 narrative
- `rank_within_tier`: Rank within tier

## Tier Definitions

### TIER_0C_CLOCKWORK_DUE
**Criteria**:
- Career Clock: Predictable pattern (`cc_tenure_cv < 0.5`)
- In move window: 70-130% through typical tenure cycle
- Not a wirehouse

**Expected Conversion**: 5.07% (1.33x lift vs baseline)

### TIER_1B_PRIME_MOVER_SERIES65
**Criteria**:
- Series 65 only (no Series 7)
- Prime Mover criteria:
  - Tenure: 1-3 years at firm
  - Industry tenure: 5-15 years
  - Firm net change < 0 (bleeding)
  - Firm size <= 50 reps OR firm size <= 10 reps
  - Not a wirehouse
- OR: Tenure 1-4 years + industry 5-15 years + firm bleeding + not wirehouse

**Expected Conversion**: 5.49%

### TIER_2_PROVEN_MOVER
**Criteria**:
- 3+ prior firms (`num_prior_firms >= 3`)
- Industry tenure >= 5 years

**Expected Conversion**: 5.2%

## Distribution Logic

The query uses a smart distribution algorithm:

1. **Initial Quota**: Attempts to take 17 from each tier
2. **Capacity Check**: If a tier has fewer than 17 available, takes all available
3. **Redistribution**: If one tier has fewer than 17, distributes the remaining slots across other tiers that have capacity
4. **Final Count**: Always produces exactly 51 advisors (or fewer if total available < 51)

## Exclusions Applied

The query applies the same exclusions as the January lead list:

1. **Salesforce Exclusions**: Advisors already in Salesforce (by CRD matching)
2. **Age Exclusions**: Advisors over 70 years old
3. **Disclosure Exclusions**: 
   - CRIMINAL
   - REGULATORY_EVENT
   - TERMINATION
   - INVESTIGATION
   - CUSTOMER_DISPUTE
   - CIVIL_EVENT
   - BOND
4. **Firm Exclusions**: Wirehouses and excluded firms (from `ml_features.excluded_firms` and `ml_features.excluded_firm_crds`)
5. **Title Exclusions**: Paraplanner, assistant, operations, compliance, etc.

## Validation Checklist

After running the query, verify:

- [ ] Total advisors: 51 (or fewer if not enough available)
- [ ] All advisors: `v4_percentile >= 90`
- [ ] All three tiers present (may have 0 if no matches)
- [ ] No duplicate CRDs
- [ ] All advisors not in Salesforce (verify manually if needed)
- [ ] Distribution: ~17 per tier (may vary)

## Troubleshooting

### Issue: Fewer than 51 advisors returned

**Possible Causes**:
1. Not enough advisors in top 10th percentile meeting tier criteria
2. Too many exclusions (Salesforce, age, disclosures, etc.)

**Solutions**:
1. Check available count per tier:
   ```sql
   SELECT 
       score_tier,
       COUNT(*) as available
   FROM `savvy-gtm-analytics.ml_features.top_10_percentile_51_advisor_list`
   GROUP BY score_tier;
   ```
2. Consider lowering V4 percentile threshold (e.g., 85th percentile)
3. Review exclusions to see if any can be relaxed

### Issue: One tier has 0 advisors

**Possible Causes**:
1. No advisors in that tier meet the top 10th percentile requirement
2. All advisors in that tier are already in Salesforce

**Solutions**:
1. Check if tier exists in broader population:
   ```sql
   -- Check TIER_0C_CLOCKWORK_DUE availability
   SELECT COUNT(*) 
   FROM [full query without V4 filter]
   WHERE score_tier = 'TIER_0C_CLOCKWORK_DUE';
   ```
2. Consider adjusting tier criteria if too restrictive
3. The distribution algorithm will automatically allocate more to other tiers

### Issue: V4 percentile < 90 for some advisors

**Possible Causes**:
1. Query logic error
2. V4 scores not updated

**Solutions**:
1. Verify V4 scores are up to date:
   ```sql
   SELECT 
       MIN(v4_percentile) as min_pct,
       MAX(v4_percentile) as max_pct
   FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores`;
   ```
2. Check query WHERE clause includes `v4_percentile >= 90`

## Next Steps

After generating the list:

1. **Review**: Manually review the list for quality
2. **Export**: CSV is ready for import into Salesforce or other systems
3. **Outreach**: Use the list for targeted outreach campaigns
4. **Track**: Monitor conversion rates to validate tier performance

## Related Documentation

- [January Lead List Generation Guide](../README.md#step-4-generate-base-lead-list-query-1)
- [V3 Tier Definitions](../../v3/VERSION_3_MODEL_REPORT.md)
- [V4 Model Documentation](../../v4/README.md)
- [Career Clock Methodology](../../pipeline/docs/CAREER_CLOCK_METHODOLOGY.md)
