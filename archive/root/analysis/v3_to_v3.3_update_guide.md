# V3.2 → V3.3 Model Update: Bleeding Signal Refinement

## Cursor.ai Implementation Guide

**Purpose:** Update the V3.2 lead scoring model to incorporate findings from the bleeding signal analysis. This guide edits existing files only — no new files are created.

**Key Changes:**
1. Remove TIER_5_HEAVY_BLEEDER (converts at 3.27%, below 3.82% baseline)
2. Use inferred departures (60-90 days fresher signal)
3. Tighten TIER_3_MODERATE_BLEEDER threshold (3-15 departures, not 1-10)
4. Add bleeding velocity detection (accelerating bleeding = better signal)
5. Update tier narratives with corrected conversion rates

**Files to Modify:**
- `v3/sql/generate_lead_list_v3.2.1.sql` → Main query updates
- `v3/models/model_registry_v3.json` → Version bump and change log
- `v3/VERSION_3_MODEL_REPORT.md` → Documentation updates
- `README.md` → Add change log entry

---

## PRE-FLIGHT: Verify Current State

### Prompt 0.1: Verify File Locations and Current Version

```
Before making any changes, verify the current state of the V3.2 model files. 

1. Check that these files exist:
   - v3/sql/generate_lead_list_v3.2.1.sql
   - v3/models/model_registry_v3.json
   - v3/VERSION_3_MODEL_REPORT.md
   - README.md

2. Read the current model_registry_v3.json to confirm current version is V3.2.4

3. Search for "TIER_5_HEAVY_BLEEDER" in generate_lead_list_v3.2.1.sql to confirm it exists

4. Search for "firm_departures" CTE to understand current bleeding calculation

Report what you find before proceeding.
```

### Prompt 0.2: Create Backup References

```
Before editing, document the current state by noting:

1. Current version string in model_registry_v3.json
2. Current TIER_5 criteria in generate_lead_list_v3.2.1.sql
3. Current firm_departures CTE logic
4. Current TIER_3 threshold values

Store these in memory so we can reference them in the README changelog.
```

---

## PHASE 1: Update Firm Departures to Use Inferred Approach

### Prompt 1.1: Update firm_departures CTE

```
In v3/sql/generate_lead_list_v3.2.1.sql, find the firm_departures CTE and update it to use the inferred departure approach.

CURRENT CODE (find this pattern):
```

```sql
-- ============================================================================
-- F. FIRM DEPARTURES (12 months) - from employment history
-- ============================================================================
firm_departures AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY 1
),
```

```
REPLACE WITH (inferred departures - 60-90 days fresher):
```

```sql
-- ============================================================================
-- F. FIRM DEPARTURES (12 months) - INFERRED from START_DATE at new firm
-- V3.3 UPDATE: Use PRIMARY_FIRM_START_DATE to infer departures 60-90 days faster
-- When advisor starts at Firm B, we infer they departed Firm A on same date
-- ============================================================================
firm_departures AS (
    SELECT
        SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT c.RIA_CONTACT_CRD_ID) as departures_12mo
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON c.RIA_CONTACT_CRD_ID = eh.RIA_CONTACT_CRD_ID
        -- Ensure we're looking at a DIFFERENT firm (not current employer)
        AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != SAFE_CAST(c.PRIMARY_FIRM AS INT64)
    WHERE c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND c.PRIMARY_FIRM IS NOT NULL
      -- Take most recent prior employer only
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.RIA_CONTACT_CRD_ID 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
    GROUP BY 1
),
```

```
After making this change, verify the CTE compiles by checking for syntax errors.
```

### Prompt 1.2: Add Bleeding Velocity CTE

```
In v3/sql/generate_lead_list_v3.2.1.sql, add a NEW CTE after firm_departures to calculate bleeding velocity. This detects firms where bleeding is ACCELERATING (better signal than absolute count).

Find the firm_arrivals CTE and ADD THIS NEW CTE between firm_departures and firm_arrivals:
```

```sql
-- ============================================================================
-- F2. FIRM DEPARTURES - 90 DAY WINDOWS FOR VELOCITY CALCULATION
-- V3.3 UPDATE: Detect ACCELERATING bleeding (firms entering bleeding phase)
-- ============================================================================
firm_departures_velocity AS (
    SELECT
        SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        -- Recent 90 days
        COUNT(DISTINCT CASE 
            WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN c.RIA_CONTACT_CRD_ID 
        END) as departures_90d,
        -- Prior 90 days (91-180 days ago)
        COUNT(DISTINCT CASE 
            WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
                 AND c.PRIMARY_FIRM_START_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN c.RIA_CONTACT_CRD_ID 
        END) as departures_prior_90d
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON c.RIA_CONTACT_CRD_ID = eh.RIA_CONTACT_CRD_ID
        AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != SAFE_CAST(c.PRIMARY_FIRM AS INT64)
    WHERE c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
      AND c.PRIMARY_FIRM IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.RIA_CONTACT_CRD_ID 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
    GROUP BY 1
),
```

### Prompt 1.3: Update firm_metrics CTE to Include Velocity

```
In v3/sql/generate_lead_list_v3.2.1.sql, find the firm_metrics CTE and update it to include the bleeding velocity signal.

FIND THIS PATTERN (the firm_metrics CTE):
```

```sql
firm_metrics AS (
    SELECT
        h.firm_crd,
        h.current_reps as firm_rep_count,
        COALESCE(d.departures_12mo, 0) as departures_12mo,
        COALESCE(a.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(a.arrivals_12mo, 0) - COALESCE(d.departures_12mo, 0) as firm_net_change_12mo,
```

```
UPDATE TO (add velocity fields):
```

```sql
firm_metrics AS (
    SELECT
        h.firm_crd,
        h.current_reps as firm_rep_count,
        COALESCE(d.departures_12mo, 0) as departures_12mo,
        COALESCE(a.arrivals_12mo, 0) as arrivals_12mo,
        COALESCE(a.arrivals_12mo, 0) - COALESCE(d.departures_12mo, 0) as firm_net_change_12mo,
        -- V3.3: Bleeding velocity fields
        COALESCE(dv.departures_90d, 0) as departures_90d,
        COALESCE(dv.departures_prior_90d, 0) as departures_prior_90d,
        -- Velocity classification
        CASE 
            WHEN COALESCE(dv.departures_prior_90d, 0) = 0 
                 AND COALESCE(dv.departures_90d, 0) >= 3 
            THEN 'ACCELERATING'
            WHEN COALESCE(dv.departures_90d, 0) > COALESCE(dv.departures_prior_90d, 0) * 1.5 
            THEN 'ACCELERATING'
            WHEN COALESCE(dv.departures_90d, 0) < COALESCE(dv.departures_prior_90d, 0) * 0.5 
            THEN 'DECELERATING'
            ELSE 'STEADY'
        END as bleeding_velocity,
```

```
Also add the JOIN to the firm_departures_velocity CTE:
```

```sql
    FROM firm_headcount h
    LEFT JOIN firm_departures d ON h.firm_crd = d.firm_crd
    LEFT JOIN firm_departures_velocity dv ON h.firm_crd = dv.firm_crd  -- V3.3: Add velocity join
    LEFT JOIN firm_arrivals a ON h.firm_crd = a.firm_crd
```

---

## PHASE 2: Remove TIER_5_HEAVY_BLEEDER

### Prompt 2.1: Remove TIER_5 from Tier Assignment Logic

```
In v3/sql/generate_lead_list_v3.2.1.sql, find and REMOVE the TIER_5_HEAVY_BLEEDER case statement.

FIND THIS PATTERN (the TIER_5 assignment):
```

```sql
            WHEN (firm_net_change_12mo <= -10
                  AND industry_tenure_years >= 5) THEN
                CONCAT(
                    'The firm ', firm_name, ' is experiencing significant turmoil, ',
                    'losing ', CAST(ABS(firm_net_change_12mo) AS STRING), ' advisors (net) in the past 12 months. ',
                    first_name, ', with ', CAST(industry_tenure_years AS STRING), ' years of experience, likely has a portable book ',
                    'and is watching the workplace destabilize. ',
                    'Heavy Bleeder tier with 7.27% expected conversion (1.90x baseline).'
                )
```

```
DELETE THIS ENTIRE WHEN CLAUSE. 

The data shows HEAVY_BLEEDING firms convert at 3.27% (BELOW the 3.82% baseline). This tier was hurting performance. Advisors at these firms will now fall through to STANDARD tier.

After deletion, verify the CASE statement still has valid syntax (proper WHEN...THEN...ELSE structure).
```

### Prompt 2.2: Remove TIER_5 from Priority Ranking

```
In v3/sql/generate_lead_list_v3.2.1.sql, find the priority_rank CASE statement and remove TIER_5 references.

FIND patterns like:
```

```sql
CASE score_tier
    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
    WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
    WHEN 'TIER_1_PRIME_MOVER' THEN 3
    WHEN 'TIER_1F_HV_WEALTH_BLEEDER' THEN 4
    WHEN 'TIER_2_PROVEN_MOVER' THEN 5
    WHEN 'TIER_3_MODERATE_BLEEDER' THEN 6
    WHEN 'TIER_4_EXPERIENCED_MOVER' THEN 7
    WHEN 'TIER_5_HEAVY_BLEEDER' THEN 8  -- REMOVE THIS LINE
```

```
Remove the TIER_5_HEAVY_BLEEDER line from all priority ranking CASE statements in the file. Search for all occurrences.
```

### Prompt 2.3: Verify TIER_5 Removal

```
Search the entire file v3/sql/generate_lead_list_v3.2.1.sql for any remaining references to:
- TIER_5
- HEAVY_BLEEDER
- "Heavy Bleeder"

Report all occurrences found. All should be removed except for comments explaining why it was removed.

Add a comment where TIER_5 used to be:
```

```sql
            -- V3.3 UPDATE: TIER_5_HEAVY_BLEEDER REMOVED
            -- Analysis showed heavy bleeding firms (16+ departures) convert at 3.27%
            -- This is BELOW the 3.82% baseline, so this tier was counterproductive
            -- Advisors at heavily bleeding firms now fall to STANDARD tier
```

---

## PHASE 3: Update TIER_3_MODERATE_BLEEDER Threshold

### Prompt 3.1: Tighten TIER_3 Threshold

```
In v3/sql/generate_lead_list_v3.2.1.sql, find the TIER_3_MODERATE_BLEEDER logic and update the threshold.

FIND THIS PATTERN:
```

```sql
            WHEN (firm_net_change_12mo BETWEEN -10 AND -1
                  AND industry_tenure_years >= 5) THEN
                CONCAT(
                    'The firm ', firm_name, ' has experienced moderate advisor departures ',
```

```
UPDATE TO (tighten threshold to -15 to -3, add velocity check):
```

```sql
            -- V3.3 UPDATE: Tightened threshold (-15 to -3) and added velocity boost
            -- Analysis: Moderate bleeding (5.43%) outperforms heavy bleeding (3.27%)
            -- Sweet spot is 3-15 departures, preferably with accelerating velocity
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN
                CONCAT(
                    'The firm ', firm_name, ' has experienced moderate advisor departures ',
                    '(net change: ', CAST(firm_net_change_12mo AS STRING), ') in the past year. ',
                    CASE WHEN bleeding_velocity = 'ACCELERATING' 
                         THEN 'Bleeding is accelerating - advisors are actively evaluating options. '
                         ELSE '' 
                    END,
                    first_name, ', with ', CAST(industry_tenure_years AS STRING), ' years of experience, is likely having conversations ',
                    'with departing colleagues and hearing about opportunities elsewhere. ',
                    'Moderate Bleeder tier with 5.43% expected conversion (1.42x baseline).'
                )
```

### Prompt 3.2: Add TIER_3A for Accelerating Bleeding

```
In v3/sql/generate_lead_list_v3.2.1.sql, add a NEW tier variant for accelerating bleeding firms. This should be inserted BEFORE the regular TIER_3 check.

ADD THIS NEW TIER (insert before the standard TIER_3_MODERATE_BLEEDER):
```

```sql
            -- V3.3 NEW: TIER_3A - Accelerating Bleeding (highest value moderate bleeder)
            -- Firms that just started bleeding are in the "what's happening?" phase
            -- Advisors are most receptive during this uncertainty window
            WHEN (firm_net_change_12mo BETWEEN -15 AND -3
                  AND bleeding_velocity = 'ACCELERATING'
                  AND industry_tenure_years >= 5
                  AND is_wirehouse = 0) THEN
                CONCAT(
                    'The firm ', firm_name, ' has recently started experiencing advisor departures ',
                    '(net change: ', CAST(firm_net_change_12mo AS STRING), ', accelerating in last 90 days). ',
                    'This is the optimal window - ', first_name, ' is watching colleagues leave and evaluating options. ',
                    'Accelerating Bleeder tier - prioritize outreach. ',
                    'Expected conversion ~6% (estimated 1.57x baseline).'
                )
```

```
Also add TIER_3A to the score_tier assignment logic and priority ranking.
```

---

## PHASE 4: Update enriched_prospects CTE

### Prompt 4.1: Add Velocity Fields to enriched_prospects

```
In v3/sql/generate_lead_list_v3.2.1.sql, find the enriched_prospects CTE and add the new velocity fields.

FIND the SELECT statement in enriched_prospects that includes firm_net_change_12mo:
```

```sql
        fm.firm_net_change_12mo,
        fm.turnover_pct,
```

```
ADD these new fields after turnover_pct:
```

```sql
        fm.firm_net_change_12mo,
        fm.turnover_pct,
        -- V3.3: Bleeding velocity fields
        fm.departures_90d,
        fm.departures_prior_90d,
        fm.bleeding_velocity,
```

---

## PHASE 5: Update Model Registry

### Prompt 5.1: Update model_registry_v3.json

```
Open v3/models/model_registry_v3.json and update to V3.3.

FIND the current version info:
```

```json
{
  "model_id": "lead-scoring-v3.2.4",
  "model_version": "V3.2.4_12232025_INSURANCE_EXCLUSIONS",
```

```
UPDATE TO:
```

```json
{
  "model_id": "lead-scoring-v3.3.0",
  "model_version": "V3.3.0_12302025_BLEEDING_SIGNAL_REFINEMENT",
  "model_type": "rules-based-tiers",
  "status": "production",
  "created_date": "2025-12-21",
  "updated_date": "2025-12-30",
  "changes_from_v3.2.4": [
    "REMOVED: TIER_5_HEAVY_BLEEDER - Analysis showed 3.27% conversion (BELOW 3.82% baseline)",
    "UPDATED: Firm departures now use inferred approach (START_DATE at new firm) for 60-90 days fresher signal",
    "UPDATED: TIER_3_MODERATE_BLEEDER threshold tightened from -10 to -1 → -15 to -3",
    "ADDED: TIER_3A_ACCELERATING_BLEEDER for firms with accelerating bleeding velocity",
    "ADDED: bleeding_velocity field (ACCELERATING/STEADY/DECELERATING) to detect firms entering bleeding phase",
    "RATIONALE: Heavy bleeding firms have already lost best advisors; moderate bleeding with acceleration is the optimal signal",
    "VALIDATION: Moderate bleeding converts at 5.43% (1.42x baseline) vs heavy bleeding at 3.27% (0.86x baseline)"
  ],
```

### Prompt 5.2: Update Tier Definitions in Registry

```
In v3/models/model_registry_v3.json, update the tier definitions section.

FIND the tier_definitions section and UPDATE:
```

```json
  "tier_definitions": {
    "TIER_1A_PRIME_MOVER_CFP": {
      "conversion_rate": "16.44%",
      "lift": "4.30x",
      "criteria": "CFP holder + Prime Mover criteria"
    },
    "TIER_1B_PRIME_MOVER_SERIES65": {
      "conversion_rate": "16.48%",
      "lift": "4.31x",
      "criteria": "Series 65 only + Prime Mover criteria"
    },
    "TIER_1_PRIME_MOVER": {
      "conversion_rate": "13.21%",
      "lift": "3.46x",
      "criteria": "Tenure 1-4yr, industry 5-15yr, non-wirehouse, firm instability"
    },
    "TIER_1F_HV_WEALTH_BLEEDER": {
      "conversion_rate": "12.78%",
      "lift": "3.35x",
      "criteria": "High-value wealth title + bleeding firm (moderate only in V3.3)"
    },
    "TIER_2_PROVEN_MOVER": {
      "conversion_rate": "8.59%",
      "lift": "2.25x",
      "criteria": "3+ prior firms, 5+ years experience"
    },
    "TIER_3A_ACCELERATING_BLEEDER": {
      "conversion_rate": "~6.00%",
      "lift": "~1.57x",
      "criteria": "V3.3 NEW: Firm with 3-15 departures AND accelerating velocity",
      "note": "Estimated - to be validated after deployment"
    },
    "TIER_3_MODERATE_BLEEDER": {
      "conversion_rate": "5.43%",
      "lift": "1.42x",
      "criteria": "V3.3 UPDATED: Firm with 3-15 departures (was 1-10), 5+ years experience"
    },
    "TIER_4_EXPERIENCED_MOVER": {
      "conversion_rate": "11.54%",
      "lift": "3.02x",
      "criteria": "20+ year veteran, moved 1-4 years ago"
    },
    "TIER_5_HEAVY_BLEEDER": {
      "status": "REMOVED_V3.3",
      "conversion_rate": "3.27%",
      "lift": "0.86x",
      "note": "Removed in V3.3 - converts BELOW baseline. Advisors fall to STANDARD."
    },
    "STANDARD": {
      "conversion_rate": "3.82%",
      "lift": "1.0x",
      "criteria": "Does not meet any priority tier criteria"
    }
  },
```

---

## PHASE 6: Update VERSION_3_MODEL_REPORT.md

### Prompt 6.1: Add V3.3 Section to Report

```
Open v3/VERSION_3_MODEL_REPORT.md and add a new section documenting the V3.3 changes.

FIND the executive summary section and UPDATE the version info:
```

```markdown
**Model Version:** V3.3.0_12302025_BLEEDING_SIGNAL_REFINEMENT  
**Original Development Date:** December 21, 2025  
**Last Updated:** December 30, 2025 (V3.3: Bleeding signal refinement based on conversion analysis)  
```

```
ADD a new section after the executive summary titled "V3.3 Changes":
```

```markdown
---

## V3.3 Changes: Bleeding Signal Refinement

**Release Date:** December 30, 2025

### Background

Analysis of the bleeding signal revealed critical insights:

| Bleeding Category | Leads | Conversion Rate | vs Baseline |
|-------------------|-------|-----------------|-------------|
| STABLE | 13,016 | 5.47% | 1.43x ✅ |
| MODERATE_BLEEDING | 1,767 | 5.43% | 1.42x ✅ |
| LOW_BLEEDING | 2,149 | 5.35% | 1.40x ✅ |
| HEAVY_BLEEDING | 25,084 | **3.27%** | **0.86x ❌** |

**Key Finding:** Heavy bleeding firms convert BELOW baseline. The best advisors leave bleeding firms first; by the time a firm is heavily bleeding, the opportunity has passed.

### Changes Made

#### 1. TIER_5_HEAVY_BLEEDER Removed
- **Reason:** 3.27% conversion rate is below the 3.82% baseline
- **Impact:** Advisors at heavily bleeding firms (16+ departures) now fall to STANDARD tier
- **Expected Result:** Stop prioritizing leads that convert below average

#### 2. Inferred Departures Approach Implemented
- **Change:** Firm departures now calculated using `PRIMARY_FIRM_START_DATE` at new firm
- **Reason:** Detects bleeding 60-90 days faster than waiting for `END_DATE` backfill
- **Validation:** Median gap between inferred and actual END_DATE is only 8 days

#### 3. TIER_3 Threshold Tightened
- **Before:** Firms with net change -10 to -1
- **After:** Firms with net change -15 to -3
- **Reason:** Sweet spot is 3-15 departures; fewer than 3 is noise, more than 15 is too late

#### 4. Bleeding Velocity Signal Added
- **New Field:** `bleeding_velocity` (ACCELERATING/STEADY/DECELERATING)
- **Logic:** Compares departures in last 90 days vs prior 90 days
- **Use:** Firms with ACCELERATING bleeding are prioritized (entering the "should I go?" phase)

#### 5. TIER_3A_ACCELERATING_BLEEDER Added
- **Criteria:** Moderate bleeding (3-15 departures) + accelerating velocity
- **Expected Conversion:** ~6% (estimated, to be validated)
- **Rationale:** Catch firms entering the bleeding phase, not already heavily bleeding

### Tier Hierarchy (V3.3)

| Rank | Tier | Conversion | Status |
|------|------|------------|--------|
| 1 | TIER_1A_CFP | 16.44% | Unchanged |
| 2 | TIER_1B_SERIES65 | 16.48% | Unchanged |
| 3 | TIER_1_PRIME_MOVER | 13.21% | Unchanged |
| 4 | TIER_1F_HV_WEALTH | 12.78% | Unchanged |
| 5 | TIER_2_PROVEN_MOVER | 8.59% | Unchanged |
| 6 | TIER_3A_ACCELERATING | ~6.0% | **NEW** |
| 7 | TIER_3_MODERATE | 5.43% | Threshold updated |
| 8 | TIER_4_EXPERIENCED | 11.54% | Unchanged |
| ~~9~~ | ~~TIER_5_HEAVY~~ | ~~3.27%~~ | **REMOVED** |

---
```

---

## PHASE 7: Update README.md

### Prompt 7.1: Add Change Log Entry to README

```
Open README.md in the repository root and add a change log entry for V3.3.

FIND the change log section (or create one if it doesn't exist) and ADD:
```

```markdown
## Change Log

### V3.3.0 - December 30, 2025 - Bleeding Signal Refinement

**Summary:** Major refinement to bleeding signal based on comprehensive conversion analysis.

#### Key Changes

1. **REMOVED TIER_5_HEAVY_BLEEDER**
   - Analysis showed heavy bleeding firms convert at 3.27% (BELOW 3.82% baseline)
   - Root cause: Best advisors leave first; by heavy bleeding phase, opportunity passed
   - Impact: ~25,000 leads will now fall to STANDARD instead of priority tier

2. **Implemented Inferred Departures**
   - Now use `PRIMARY_FIRM_START_DATE` to infer departures from prior firm
   - Provides 60-90 day fresher signal than waiting for `END_DATE` backfill
   - Validation: Median gap between inferred and actual date is only 8 days

3. **Tightened TIER_3 Threshold**
   - Changed from -10 to -1 → -15 to -3 (net change)
   - Sweet spot: 3-15 departures indicates "conversations happening" without "too late"

4. **Added Bleeding Velocity**
   - New signal: ACCELERATING / STEADY / DECELERATING
   - Compares last 90 days vs prior 90 days
   - Accelerating = firm just started bleeding = optimal outreach window

5. **Added TIER_3A_ACCELERATING_BLEEDER**
   - Moderate bleeding + accelerating velocity
   - Estimated 6% conversion (to be validated)
   - Catch advisors in "should I go?" phase

#### Data Supporting These Changes

| Signal | Conversion | Decision |
|--------|------------|----------|
| Heavy Bleeding (16+ departures) | 3.27% | Remove tier (below baseline) |
| Moderate Bleeding (3-15) | 5.43% | Keep tier, tighten threshold |
| Low Bleeding (1-3) | 5.35% | Falls to moderate or stable |
| Stable (0) | 5.47% | Baseline comparison |
| Baseline (all leads) | 3.82% | Reference point |

#### Files Modified

- `v3/sql/generate_lead_list_v3.2.1.sql` → `generate_lead_list_v3.3.0.sql`
  - Updated firm_departures CTE (inferred approach)
  - Added firm_departures_velocity CTE
  - Removed TIER_5_HEAVY_BLEEDER
  - Updated TIER_3 threshold
  - Added TIER_3A_ACCELERATING_BLEEDER

- `v3/models/model_registry_v3.json`
  - Version bump to V3.3.0
  - Updated tier definitions
  - Added change log

- `v3/VERSION_3_MODEL_REPORT.md`
  - Added V3.3 changes section
  - Updated tier hierarchy

#### Validation Plan

1. Deploy V3.3 for January 2026 lead list
2. Track conversion rates by tier for 90 days
3. Validate TIER_3A conversion estimate (~6%)
4. Compare V3.3 vs V3.2 tier distributions

#### Rollback Plan

If V3.3 underperforms:
1. Revert to V3.2.4 SQL
2. File preserved at `v3/sql/generate_lead_list_v3.2.1.sql.bak`

---
```

---

## PHASE 8: Rename SQL File and Create Backup

### Prompt 8.1: Create Backup and Rename

```
1. Create a backup of the current SQL file:
   - Copy v3/sql/generate_lead_list_v3.2.1.sql to v3/sql/generate_lead_list_v3.2.1.sql.bak

2. Rename the updated file:
   - Rename v3/sql/generate_lead_list_v3.2.1.sql to v3/sql/generate_lead_list_v3.3.0.sql

3. Update any references to the old filename in:
   - v3/docs/LEAD_LIST_GENERATION_GUIDE.md
   - Any other files that reference the SQL file
```

---

## PHASE 9: Verification and Testing

### Prompt 9.1: Syntax Verification

```
Run a syntax check on the updated SQL by executing a dry run in BigQuery.

Open v3/sql/generate_lead_list_v3.3.0.sql and:

1. Wrap the entire query in a CTE that limits results:
```

```sql
-- Syntax verification - limit to 100 rows
WITH full_query AS (
    -- [paste entire query here]
)
SELECT * FROM full_query LIMIT 100;
```

```
2. Execute in BigQuery and verify:
   - No syntax errors
   - Query compiles successfully
   - Returns expected columns

Report any errors found.
```

### Prompt 9.2: Verify Tier Distribution

```
After the syntax check passes, run a tier distribution analysis to verify the changes are working:
```

```sql
-- V3.3 Tier Distribution Check
WITH tier_counts AS (
    SELECT 
        score_tier,
        COUNT(*) as lead_count,
        COUNT(CASE WHEN bleeding_velocity = 'ACCELERATING' THEN 1 END) as accelerating_count
    FROM (
        -- [Use the full V3.3 query here, limited to a sample]
        -- Add LIMIT 50000 to the final SELECT for testing
    )
    GROUP BY 1
)
SELECT 
    score_tier,
    lead_count,
    accelerating_count,
    ROUND(lead_count * 100.0 / SUM(lead_count) OVER (), 2) as pct_of_total
FROM tier_counts
ORDER BY lead_count DESC;
```

```
Verify:
1. TIER_5_HEAVY_BLEEDER does NOT appear in results
2. TIER_3A_ACCELERATING_BLEEDER appears (should be subset of TIER_3)
3. TIER_3_MODERATE_BLEEDER count is lower than V3.2 (tighter threshold)
4. No unexpected NULL or empty tier values
```

### Prompt 9.3: Compare Bleeding Calculation

```
Verify the inferred departures approach is working by comparing to old method:
```

```sql
-- Compare OLD vs NEW departure calculation for top firms
WITH old_method AS (
    SELECT
        SAFE_CAST(PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT RIA_CONTACT_CRD_ID) as departures_old
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      AND PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
    GROUP BY 1
),
new_method AS (
    SELECT
        SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT c.RIA_CONTACT_CRD_ID) as departures_new
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON c.RIA_CONTACT_CRD_ID = eh.RIA_CONTACT_CRD_ID
        AND SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) != SAFE_CAST(c.PRIMARY_FIRM AS INT64)
    WHERE c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.RIA_CONTACT_CRD_ID 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
    GROUP BY 1
)
SELECT 
    COALESCE(o.firm_crd, n.firm_crd) as firm_crd,
    COALESCE(o.departures_old, 0) as departures_old,
    COALESCE(n.departures_new, 0) as departures_new,
    COALESCE(n.departures_new, 0) - COALESCE(o.departures_old, 0) as difference
FROM old_method o
FULL OUTER JOIN new_method n ON o.firm_crd = n.firm_crd
ORDER BY ABS(COALESCE(n.departures_new, 0) - COALESCE(o.departures_old, 0)) DESC
LIMIT 20;
```

```
Verify:
1. New method shows departure counts (not all zeros)
2. Differences exist between methods (expected due to fresher signal)
3. No obvious data quality issues
```

### Prompt 9.4: Verify Velocity Calculation

```
Verify the bleeding velocity calculation is working:
```

```sql
-- Check bleeding velocity distribution
SELECT 
    bleeding_velocity,
    COUNT(DISTINCT firm_crd) as firms,
    AVG(departures_90d) as avg_recent_departures,
    AVG(departures_prior_90d) as avg_prior_departures
FROM (
    SELECT
        SAFE_CAST(eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID AS INT64) as firm_crd,
        COUNT(DISTINCT CASE 
            WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN c.RIA_CONTACT_CRD_ID 
        END) as departures_90d,
        COUNT(DISTINCT CASE 
            WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
                 AND c.PRIMARY_FIRM_START_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            THEN c.RIA_CONTACT_CRD_ID 
        END) as departures_prior_90d,
        CASE 
            WHEN COUNT(DISTINCT CASE 
                WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
                     AND c.PRIMARY_FIRM_START_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                THEN c.RIA_CONTACT_CRD_ID END) = 0 
                AND COUNT(DISTINCT CASE 
                    WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                    THEN c.RIA_CONTACT_CRD_ID END) >= 3 
            THEN 'ACCELERATING'
            WHEN COUNT(DISTINCT CASE 
                WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                THEN c.RIA_CONTACT_CRD_ID END) > 
                COUNT(DISTINCT CASE 
                    WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
                         AND c.PRIMARY_FIRM_START_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                    THEN c.RIA_CONTACT_CRD_ID END) * 1.5 
            THEN 'ACCELERATING'
            WHEN COUNT(DISTINCT CASE 
                WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                THEN c.RIA_CONTACT_CRD_ID END) < 
                COUNT(DISTINCT CASE 
                    WHEN c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
                         AND c.PRIMARY_FIRM_START_DATE < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                    THEN c.RIA_CONTACT_CRD_ID END) * 0.5 
            THEN 'DECELERATING'
            ELSE 'STEADY'
        END as bleeding_velocity
    FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON c.RIA_CONTACT_CRD_ID = eh.RIA_CONTACT_CRD_ID
    WHERE c.PRIMARY_FIRM_START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.RIA_CONTACT_CRD_ID 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
    GROUP BY 1
)
GROUP BY 1
ORDER BY 1;
```

```
Verify:
1. All three velocity categories appear (ACCELERATING, STEADY, DECELERATING)
2. ACCELERATING firms have higher recent departures than prior
3. Distribution looks reasonable (most should be STEADY)
```

---

## PHASE 10: Final Documentation Update

### Prompt 10.1: Update Comments in SQL File

```
Add a header comment block to the top of v3/sql/generate_lead_list_v3.3.0.sql:
```

```sql
-- ============================================================================
-- LEAD LIST GENERATION QUERY - VERSION 3.3.0
-- ============================================================================
-- 
-- Version: V3.3.0_12302025_BLEEDING_SIGNAL_REFINEMENT
-- Author: Lead Scoring Team
-- Date: December 30, 2025
--
-- CHANGES FROM V3.2.4:
-- 1. REMOVED TIER_5_HEAVY_BLEEDER (converted at 3.27%, below baseline)
-- 2. Implemented inferred departures (60-90 days fresher signal)
-- 3. Tightened TIER_3 threshold from -10/-1 to -15/-3
-- 4. Added bleeding_velocity field (ACCELERATING/STEADY/DECELERATING)
-- 5. Added TIER_3A_ACCELERATING_BLEEDER for optimal timing
--
-- KEY INSIGHT:
-- Heavy bleeding firms have already lost their best advisors.
-- Moderate bleeding with accelerating velocity catches advisors
-- in the "should I go?" decision phase.
--
-- VALIDATION DATA:
-- | Bleeding Category | Conversion | Lift |
-- |-------------------|------------|------|
-- | MODERATE_BLEEDING | 5.43%      | 1.42x|
-- | HEAVY_BLEEDING    | 3.27%      | 0.86x| <- REMOVED
-- | BASELINE          | 3.82%      | 1.0x |
--
-- ============================================================================
```

### Prompt 10.2: Final Verification Checklist

```
Before marking V3.3 as complete, verify all changes:

□ firm_departures CTE uses inferred approach (PRIMARY_FIRM_START_DATE)
□ firm_departures_velocity CTE exists and calculates 90-day windows
□ firm_metrics CTE includes bleeding_velocity field
□ TIER_5_HEAVY_BLEEDER removed from tier assignment
□ TIER_5 removed from priority ranking
□ TIER_3 threshold updated to -15 to -3
□ TIER_3A_ACCELERATING_BLEEDER added
□ enriched_prospects includes velocity fields
□ model_registry_v3.json updated to V3.3.0
□ VERSION_3_MODEL_REPORT.md has V3.3 section
□ README.md has change log entry
□ SQL file renamed to generate_lead_list_v3.3.0.sql
□ Backup created at generate_lead_list_v3.2.1.sql.bak
□ Syntax verification passed
□ Tier distribution looks correct
□ Velocity calculation verified

Report completion status for each item.
```

---

## Summary: Files Modified

| File | Changes |
|------|---------|
| `v3/sql/generate_lead_list_v3.3.0.sql` | Inferred departures, velocity, remove TIER_5, update TIER_3, add TIER_3A |
| `v3/models/model_registry_v3.json` | Version bump, tier definitions, change log |
| `v3/VERSION_3_MODEL_REPORT.md` | V3.3 changes section |
| `README.md` | Change log entry |
| `v3/sql/generate_lead_list_v3.2.1.sql.bak` | Backup of previous version |

## Expected Outcomes

1. **TIER_5 leads → STANDARD:** ~25,000 leads that were incorrectly prioritized will now be standard
2. **Fresher bleeding signal:** Detect moderate bleeding 60-90 days earlier
3. **Better targeting:** Focus on firms entering bleeding phase, not already heavily bleeding
4. **New TIER_3A:** Capture the optimal "should I go?" window with accelerating velocity

## Post-Deployment Validation

Track these metrics for 90 days after V3.3 deployment:
1. TIER_3A conversion rate (target: ~6%)
2. TIER_3 conversion rate (should remain ~5.4%)
3. STANDARD conversion rate (may increase slightly due to former TIER_5 leads)
4. Overall priority tier performance vs V3.2
