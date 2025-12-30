# Recyclable Leads Pipeline Guide

**Purpose**: Generate monthly list of recyclable leads/opportunities for SGAs  
**Status**: ✅ Production  
**Version**: V2.1  
**Last Updated**: December 30, 2025

---

## Executive Summary

The Recyclable Leads Pipeline generates a **separate monthly list of 600 leads/opportunities** that SGAs can work in addition to the primary Provided Lead List. These are leads that were previously contacted but didn't convert, and are now eligible for re-engagement based on timing and model predictions.

**Key Insight**: People who **just changed firms** (< 2 years) are **NOT ready to move again**. They just settled in and need time to build relationships. The recyclable pool focuses on people who changed firms 2+ years ago or haven't changed firms but have high V4 scores (model predicts movement).

---

## Business Logic

### Priority Tiers

| Priority | Criteria | Rationale | Expected Conv |
|----------|----------|-----------|---------------|
| **P1** | "Timing" disposition + 180-365 days passed | They said timing was bad - try again | 6-8% |
| **P2** | High V4 (≥80%) + No firm change + Long tenure NOW | Model predicts movement, hasn't moved yet | 5-7% |
| **P3** | "No Response" + High V4 + 90-180 days | Good prospect who didn't engage before | 4-6% |
| **P4** | Changed firms **2-3 years ago** | Proven mover, may be getting restless | 4-5% |
| **P5** | Changed firms **3+ years ago** + V4≥60 | Definite mover, overdue for another change | 4-5% |
| **P6** | Standard recycle (other eligible) | General re-engagement pool | 3-4% |

### Critical Exclusions

| Exclusion | Reason |
|-----------|--------|
| Changed firms **< 2 years ago** | Just settled in, won't move again soon |
| No-go dispositions | Permanent disqualifications (see below) |
| DoNotCall = true | Opted out |
| Recently contacted (< 90 days) | Too soon to re-engage |

### No-Go Dispositions (Permanent DQ)

**Leads**:
- 'Not Interested in Moving'
- 'Not a Fit'
- 'No Book'
- 'Book Not Transferable'
- 'Restrictive Covenants'
- 'Bad Lead Provided'
- 'Wants Platform Only'
- 'AUM / Revenue too Low'

**Opportunities**:
- 'Savvy Declined - No Book of Business'
- 'Savvy Declined - Insufficient Revenue'
- 'Savvy Declined – Book Not Transferable'
- 'Savvy Declined - Poor Culture Fit'
- 'Savvy Declined - Compliance'
- 'Candidate Declined - Lost to Competitor'

### High Priority Recyclable Dispositions

**"Timing" Related** (Highest Priority):
- Lead: 'Timing'
- Opportunity: 'Candidate Declined - Timing', 'Candidate Declined - Fear of Change'

**General Recyclable** (Medium Priority):
- Lead: 'No Response', 'Auto-Closed by Operations', 'Other', 'No Show / Ghosted'
- Opportunity: 'No Longer Responsive', 'No Show – Intro Call', 'Other'

---

## Technical Implementation

### SQL File

**Location**: `pipeline/sql/recycling/recyclable_pool_master_v2.1.sql`

**Key Features**:
- Point-in-time (PIT) compliant employment history joins
- Fixed date type mismatches (DATE() casting)
- Fixed tenure calculations (calculate to CloseDate, not CURRENT_DATE)
- Field validation with COALESCE
- Priority logic using correct tenure fields

### Key SQL Logic

**Firm Change Detection**:
```sql
-- Find most recent firm change (if any)
WITH firm_changes AS (
    SELECT 
        advisor_crd,
        MAX(start_date) as last_firm_change_date,
        COUNT(DISTINCT firm_crd) - 1 as num_firm_changes
    FROM employment_history
    WHERE start_date <= CURRENT_DATE()
    GROUP BY advisor_crd
)
-- Exclude if changed firms < 2 years ago
WHERE last_firm_change_date < DATE_SUB(CURRENT_DATE(), INTERVAL 2 YEAR)
   OR last_firm_change_date IS NULL
```

**Priority Assignment**:
```sql
CASE 
    WHEN timing_disposition = 1 AND days_since_close BETWEEN 180 AND 365 THEN 'P1'
    WHEN v4_percentile >= 80 AND num_firm_changes = 0 AND tenure_years >= 3 THEN 'P2'
    WHEN no_response = 1 AND v4_percentile >= 70 AND days_since_contact BETWEEN 90 AND 180 THEN 'P3'
    WHEN years_since_firm_change BETWEEN 2 AND 3 THEN 'P4'
    WHEN years_since_firm_change >= 3 AND v4_percentile >= 60 THEN 'P5'
    ELSE 'P6'
END as priority_tier
```

---

## Monthly Execution

### Step 1: Generate Recyclable Pool

**SQL File**: `pipeline/sql/recycling/recyclable_pool_master_v2.1.sql`

**Output**: BigQuery table `ml_features.recyclable_pool_v2_1`

**Target Count**: 600 leads/opportunities

### Step 2: Export to CSV

**Script**: `pipeline/scripts/export_lead_list.py` (or similar)

**Output**: `pipeline/exports/[MONTH]_[YEAR]_recyclable_leads.csv`

### Step 3: Generate Report

**Report Location**: `pipeline/reports/recycling_analysis/[MONTH]_[YEAR]_recyclable_list_report.md`

**Report Contents**:
- Total leads generated
- Distribution by priority tier
- Distribution by disposition type
- Expected conversion rates by tier
- Exclusions summary

---

## Version History

### V2.1 (December 24, 2025)

**Fixes**:
- Fixed date type mismatches (DATE() casting)
- Fixed tenure calculations (calculate to CloseDate, not CURRENT_DATE)
- Added PIT-compliant employment history join
- Added field validation with COALESCE
- Fixed priority logic to use correct tenure fields

### V2.0 (December 24, 2025)

**Key Change**: Corrected firm change logic
- **WRONG** (V1): "Changed firms = hot lead, prioritize them"
- **CORRECT** (V2): Exclude recent movers (< 2 years), prioritize proven movers (2+ years ago)

### V1.0 (Earlier)

**Initial Version**: Basic recyclable logic without firm change filtering

---

## Expected Performance

**Blended Conversion Rate**: ~4-5% (vs 3.82% baseline)

**By Priority Tier**:
- P1: 6-8%
- P2: 5-7%
- P3: 4-6%
- P4: 4-5%
- P5: 4-5%
- P6: 3-4%

**Business Impact**: 600 additional leads per month with ~4.5% expected conversion = ~27 additional MQLs per month

---

## Maintenance

### Adding New Dispositions

**No-Go Dispositions**: Add to `nogo_lead_dispositions` or `nogo_opp_reasons` CTEs

**Timing Dispositions**: Add to `timing_lead_dispositions` or `timing_opp_reasons` CTEs

**General Recyclable**: Add to `general_recyclable_dispositions` or `general_recyclable_reasons` CTEs

### Adjusting Priority Logic

**Priority thresholds** are defined in the `priority_tier` CASE statement. Adjust based on:
- Historical conversion rates by tier
- Volume requirements
- SGA capacity

### Updating Firm Change Logic

**Current Rule**: Exclude if changed firms < 2 years ago

**To Adjust**: Modify the `min_years_since_firm_change` DECLARE variable (currently 2)

---

## Related Documentation

- `pipeline/Monthly_Recyclable_Lead_List_Generation_Guide_V2.md` - Detailed execution guide
- `pipeline/sql/recycling/recyclable_pool_master_v2.1.sql` - SQL implementation
- `MODEL_EVOLUTION_HISTORY.md` - Context on V4 model predictions

---

**Document Status**: Production  
**Maintained By**: Data Science Team  
**Last Review**: December 30, 2025

