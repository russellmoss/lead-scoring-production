# Career Clock Feature Implementation Guide

**Version**: V3.4.0  
**Created**: January 2026  
**Purpose**: Add Career Clock (individual advisor timing) features to V3 lead scoring  
**Expected Impact**: +15-20% MQL improvement, new top tiers at 15-16% conversion

---

## Overview

This guide implements the "Career Clock" feature discovery:
- **Clockwork advisors** (20% of population) have predictable career patterns
- **"In Window"** timing signal achieves 10-16% conversion (vs 3% baseline)
- **"Too Early"** signal identifies 9,000+ leads to deprioritize

### Key Combinations Discovered

| Combination | Conv Rate | Lift | Action |
|-------------|-----------|------|--------|
| T1 + In_Window | 16.13% | 5.89x | New TIER_0A |
| Small Firm + In_Window | 15.46% | 5.64x | New TIER_0B |
| STANDARD + In_Window | 11.76% | 4.29x | New TIER_0C |
| Any + Too_Early | 3.14% | 1.14x | Deprioritize |

---

## Pre-Implementation Checklist

- [ ] Backup current production SQL files
- [ ] Verify BigQuery access to `savvy-gtm-analytics`
- [ ] Confirm Python environment has `google-cloud-bigquery`
- [ ] Review current V3.3 tier performance baseline

---

# STEP 1: Add Career Clock Features to Feature Engineering

## Cursor Prompt 1.1: Update Feature Engineering SQL

```
@workspace Update the lead scoring feature engineering to add Career Clock features.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v3/sql/lead_scoring_features_pit.sql`
2. Add a new CTE called `career_clock_features` that calculates:
   - `tenure_cv`: Coefficient of variation of prior job tenures (STDDEV/AVG)
   - `avg_prior_tenure_months`: Average tenure at prior firms
   - `pct_through_cycle`: current_firm_tenure / avg_prior_tenure
   - `is_in_move_window`: Boolean (tenure_cv < 0.5 AND pct_through_cycle BETWEEN 0.7 AND 1.3)
   - `is_too_early`: Boolean (tenure_cv < 0.5 AND pct_through_cycle < 0.7)
   - `career_pattern`: Categorical ('Clockwork', 'Semi_Predictable', 'Variable', 'Chaotic', 'No_Pattern')
   - `months_until_window`: How many months until advisor enters their move window
3. Join this CTE to the final feature output
4. DO NOT remove any existing features
5. Add comments explaining Career Clock methodology

VALIDATION: The new CTE should use only PIT-compliant data (employment history with dates <= contacted_date)

After making changes, show me the new CTE and the updated final SELECT statement.
```

## Code Snippet 1.1: Career Clock CTE

Add this CTE to `v3/sql/lead_scoring_features_pit.sql` after the `employment_features_supplement` CTE:

```sql
-- ========================================================================
-- CAREER CLOCK: Individual advisor timing pattern features
-- ========================================================================
-- METHODOLOGY:
-- 1. Calculate coefficient of variation (CV) of prior job tenures
-- 2. CV < 0.3 = "Clockwork" (highly predictable pattern)
-- 3. CV 0.3-0.5 = "Semi-Predictable" 
-- 4. CV >= 0.5 = Variable/Chaotic (can't reliably predict timing)
-- 5. "In Window" = advisor is 70-130% through their typical tenure cycle
-- 
-- KEY FINDINGS:
-- - T1 + In_Window: 16.13% conversion (5.89x lift)
-- - Small Firm + In_Window: 15.46% conversion (5.64x lift)
-- - STANDARD + In_Window: 11.76% conversion (4.29x lift)
-- - Any + Too_Early: 3.14% conversion (waste of outreach)
-- ========================================================================
career_clock_raw AS (
    SELECT 
        lb.lead_id,
        lb.advisor_crd,
        lb.contacted_date,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as prior_firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as prior_start,
        eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE as prior_end,
        DATE_DIFF(
            eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
            eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE,
            MONTH
        ) as prior_tenure_months
    FROM lead_base lb
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON lb.advisor_crd = eh.RIA_CONTACT_CRD_ID
    WHERE eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
      -- PIT: Only completed jobs before contact date
      AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < lb.contacted_date
      -- Valid tenure (> 0 months)
      AND DATE_DIFF(eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                    eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) > 0
),

career_clock_stats AS (
    SELECT
        lead_id,
        advisor_crd,
        contacted_date,
        COUNT(*) as completed_jobs,
        AVG(prior_tenure_months) as avg_prior_tenure_months,
        STDDEV(prior_tenure_months) as tenure_stddev,
        SAFE_DIVIDE(STDDEV(prior_tenure_months), AVG(prior_tenure_months)) as tenure_cv,
        MIN(prior_tenure_months) as min_prior_tenure,
        MAX(prior_tenure_months) as max_prior_tenure
    FROM career_clock_raw
    GROUP BY lead_id, advisor_crd, contacted_date
    HAVING COUNT(*) >= 2  -- Need 2+ completed jobs to detect pattern
),

career_clock_features AS (
    SELECT
        afv.lead_id,
        afv.advisor_crd,
        afv.current_firm_tenure_months,
        
        -- Raw stats
        COALESCE(ccs.completed_jobs, 0) as cc_completed_jobs,
        ccs.avg_prior_tenure_months as cc_avg_prior_tenure_months,
        ccs.tenure_stddev as cc_tenure_stddev,
        ccs.tenure_cv as cc_tenure_cv,
        
        -- Career Pattern Classification
        CASE
            WHEN ccs.tenure_cv IS NULL THEN 'No_Pattern'
            WHEN ccs.tenure_cv < 0.3 THEN 'Clockwork'
            WHEN ccs.tenure_cv < 0.5 THEN 'Semi_Predictable'
            WHEN ccs.tenure_cv < 0.8 THEN 'Variable'
            ELSE 'Chaotic'
        END as cc_career_pattern,
        
        -- Percent through personal cycle
        SAFE_DIVIDE(afv.current_firm_tenure_months, ccs.avg_prior_tenure_months) as cc_pct_through_cycle,
        
        -- Move Window Status (for predictable advisors only)
        CASE
            WHEN ccs.tenure_cv IS NULL THEN 'Unknown'
            WHEN ccs.tenure_cv >= 0.5 THEN 'Unpredictable'
            WHEN SAFE_DIVIDE(afv.current_firm_tenure_months, ccs.avg_prior_tenure_months) < 0.7 THEN 'Too_Early'
            WHEN SAFE_DIVIDE(afv.current_firm_tenure_months, ccs.avg_prior_tenure_months) BETWEEN 0.7 AND 1.3 THEN 'In_Window'
            ELSE 'Overdue'
        END as cc_cycle_status,
        
        -- Boolean flags for tier logic
        CASE
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(afv.current_firm_tenure_months, ccs.avg_prior_tenure_months) BETWEEN 0.7 AND 1.3
            THEN TRUE
            ELSE FALSE
        END as cc_is_in_move_window,
        
        CASE
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(afv.current_firm_tenure_months, ccs.avg_prior_tenure_months) < 0.7
            THEN TRUE
            ELSE FALSE
        END as cc_is_too_early,
        
        -- Months until move window (for nurture timing)
        CASE
            WHEN ccs.tenure_cv < 0.5 AND ccs.avg_prior_tenure_months IS NOT NULL
            THEN GREATEST(0, CAST(ccs.avg_prior_tenure_months * 0.7 - afv.current_firm_tenure_months AS INT64))
            ELSE NULL
        END as cc_months_until_window
        
    FROM advisor_features_virtual afv
    LEFT JOIN career_clock_stats ccs 
        ON afv.lead_id = ccs.lead_id 
        AND afv.advisor_crd = ccs.advisor_crd
)
```

## Code Snippet 1.2: Update Final SELECT

Update the final SELECT in `lead_scoring_features_pit.sql` to include Career Clock features:

```sql
-- Add to final SELECT statement (inside the SELECT list):

    -- Career Clock Features (V3.4.0)
    ccf.cc_completed_jobs,
    ccf.cc_avg_prior_tenure_months,
    ccf.cc_tenure_stddev,
    ccf.cc_tenure_cv,
    ccf.cc_career_pattern,
    ccf.cc_pct_through_cycle,
    ccf.cc_cycle_status,
    ccf.cc_is_in_move_window,
    ccf.cc_is_too_early,
    ccf.cc_months_until_window,

-- Add to final FROM/JOIN clause:
LEFT JOIN career_clock_features ccf ON af.lead_id = ccf.lead_id
```

## Verification Gate 1.1

```
@workspace Run verification for Career Clock feature engineering.

TASK:
1. Connect to BigQuery and run this validation query against the updated feature table:

```sql
-- VALIDATION QUERY 1.1: Career Clock Feature Distribution
SELECT 
    cc_career_pattern,
    cc_cycle_status,
    COUNT(*) as leads,
    ROUND(AVG(CAST(target AS INT64)) * 100, 2) as conv_rate_pct,
    ROUND(AVG(cc_pct_through_cycle), 2) as avg_pct_through_cycle
FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`
WHERE cc_career_pattern IS NOT NULL
GROUP BY cc_career_pattern, cc_cycle_status
ORDER BY cc_career_pattern, cc_cycle_status;
```

EXPECTED RESULTS:
- Clockwork + In_Window: ~6-10% conversion
- Semi_Predictable + In_Window: ~10-12% conversion
- Any + Too_Early: ~3% conversion

2. Verify row count matches before and after:
```sql
SELECT COUNT(*) as total_rows,
       COUNTIF(cc_career_pattern IS NOT NULL) as has_career_clock,
       COUNTIF(cc_is_in_move_window = TRUE) as in_window_count,
       COUNTIF(cc_is_too_early = TRUE) as too_early_count
FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`;
```

EXPECTED:
- in_window_count: ~700-900 leads
- too_early_count: ~9,000-10,000 leads

If validation passes, proceed to Step 2.
If validation fails, debug the CTE joins and date filters.
```

---

# STEP 2: Update V3 Tier Logic with Career Clock Tiers

## Cursor Prompt 2.1: Add Career Clock Tiers to Tier Scoring SQL

```
@workspace Update V3 tier scoring to add Career Clock-based tiers.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v3/sql/phase_4_v3_tiered_scoring.sql`
2. Add three new top-priority tiers BEFORE existing TIER_1A:
   
   - TIER_0A_PRIME_MOVER_DUE: T1 criteria + In_Window (16.13% conv, 5.89x lift)
   - TIER_0B_SMALL_FIRM_DUE: Small firm (<=10 reps) + In_Window (15.46% conv, 5.64x lift)  
   - TIER_0C_CLOCKWORK_DUE: Any predictable advisor In_Window (11.76% conv, 4.29x lift)

3. Add deprioritization tier at END:
   - TIER_NURTURE_TOO_EARLY: Predictable advisor + Too_Early + Not heavy bleeding

4. Update expected_conversion_rate and expected_lift CASE statements
5. Update priority_rank CASE statement (0A=1, 0B=2, 0C=3, then existing tiers shift down)
6. Update tier_explanation CASE statement with Career Clock explanations
7. Add comments explaining Career Clock methodology

IMPORTANT: Preserve ALL existing tier logic - these are ADDITIONS, not replacements.

Show me the updated CASE statement for score_tier assignment.
```

## Code Snippet 2.1: New Tier Logic

Add to the tier assignment CASE statement in `phase_4_v3_tiered_scoring.sql`:

```sql
-- TIER ASSIGNMENT with Career Clock (V3.4.0)
-- Priority Order: 0A > 0B > 0C > 1A > 1B > ... > STANDARD > NURTURE_TOO_EARLY

CASE
    -- ================================================================
    -- TIER 0: CAREER CLOCK PRIORITY TIERS (V3.4.0)
    -- These are advisors with predictable patterns who are "due" to move
    -- ================================================================
    
    -- TIER_0A: Prime Mover + In Move Window (16.13% conversion, 5.89x lift)
    -- Combines T1 criteria with Career Clock timing signal
    WHEN cc_is_in_move_window = TRUE
         AND current_firm_tenure_months BETWEEN 12 AND 48
         AND industry_tenure_months BETWEEN 60 AND 180
         AND firm_net_change_12mo != 0
         AND is_wirehouse = FALSE
    THEN 'TIER_0A_PRIME_MOVER_DUE'
    
    -- TIER_0B: Small Firm + In Move Window (15.46% conversion, 5.64x lift)
    -- Small firm advisors who are personally "due" to move
    WHEN cc_is_in_move_window = TRUE
         AND firm_rep_count_at_contact <= 10
         AND is_wirehouse = FALSE
    THEN 'TIER_0B_SMALL_FIRM_DUE'
    
    -- TIER_0C: Clockwork Due (11.76% conversion, 4.29x lift)
    -- Any predictable advisor in their move window (rescues STANDARD leads)
    WHEN cc_is_in_move_window = TRUE
         AND is_wirehouse = FALSE
    THEN 'TIER_0C_CLOCKWORK_DUE'
    
    -- ================================================================
    -- EXISTING TIER 1 TIERS (preserved from V3.3)
    -- ================================================================
    
    -- TIER_1B_PRIME_ZERO_FRICTION (existing highest - now 4th priority)
    WHEN has_series_65_only = TRUE
         AND has_portable_custodian = TRUE
         AND firm_rep_count_at_contact <= 10
         AND firm_net_change_12mo < 0
         AND has_cfp = FALSE
         AND is_wirehouse = FALSE
    THEN 'TIER_1B_PRIME_ZERO_FRICTION'
    
    -- [... REST OF EXISTING TIERS UNCHANGED ...]
    
    -- ================================================================
    -- DEPRIORITIZATION: Too Early (V3.4.0)
    -- Predictable advisors contacted before their typical move window
    -- These should be nurtured, not actively pursued
    -- ================================================================
    
    -- Check AFTER all priority tiers, BEFORE STANDARD
    WHEN cc_is_too_early = TRUE
         AND firm_net_change_12mo >= -10  -- Not at a heavy bleeding firm (those convert anyway)
    THEN 'TIER_NURTURE_TOO_EARLY'
    
    -- STANDARD: Everything else
    ELSE 'STANDARD'
    
END as score_tier
```

## Code Snippet 2.2: Update Expected Conversion Rates

Add to the expected_conversion_rate CASE statement:

```sql
-- Expected Conversion Rate (V3.4.0 with Career Clock)
CASE score_tier
    -- Career Clock Tiers (V3.4.0)
    WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 0.1613      -- 16.13%
    WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 0.1546       -- 15.46%
    WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 0.1176        -- 11.76%
    
    -- Existing Tiers (unchanged)
    WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 0.1364  -- 13.64%
    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 0.10        -- 10.00%
    -- [... rest unchanged ...]
    
    -- Deprioritization Tier
    WHEN 'TIER_NURTURE_TOO_EARLY' THEN 0.0314       -- 3.14%
    
    ELSE 0.0382  -- STANDARD baseline
END as expected_conversion_rate,

-- Expected Lift (V3.4.0)
CASE score_tier
    WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 5.89
    WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 5.64
    WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 4.29
    WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 3.57
    -- [... rest unchanged ...]
    WHEN 'TIER_NURTURE_TOO_EARLY' THEN 1.14
    ELSE 1.00
END as expected_lift,

-- Priority Rank (V3.4.0 - Career Clock tiers are highest)
CASE score_tier
    WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1           -- NEW: Highest
    WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2            -- NEW
    WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3             -- NEW
    WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 4       -- Was 1
    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 5           -- Was 2
    WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 6       -- Was 3
    -- [... shift all existing ranks by +3 ...]
    WHEN 'TIER_NURTURE_TOO_EARLY' THEN 98           -- NEW: Near bottom
    WHEN 'STANDARD' THEN 99
    ELSE 100
END as priority_rank
```

## Code Snippet 2.3: Update Tier Explanations

Add to the tier_explanation CASE statement:

```sql
-- Tier Explanations (V3.4.0)
CASE score_tier
    WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 
        'HIGHEST PRIORITY: This advisor matches Prime Mover criteria (1-4yr tenure, 5-15yr experience, ' ||
        'firm instability) AND has a predictable career pattern showing they are currently in their ' ||
        'typical "move window" (70-130% through their average tenure cycle). Historical conversion: 16.13%.'
    
    WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN
        'HIGHEST PRIORITY: This advisor is at a small firm (≤10 reps) AND has a predictable career ' ||
        'pattern showing they are currently in their typical "move window". Small firm advisors have ' ||
        'portable books and this timing signal indicates high receptivity. Historical conversion: 15.46%.'
    
    WHEN 'TIER_0C_CLOCKWORK_DUE' THEN
        'HIGH PRIORITY: This advisor has a predictable career pattern (consistent tenure lengths) and ' ||
        'is currently in their typical "move window" (70-130% through their average tenure cycle). ' ||
        'Even without other priority signals, timing alone makes them 4.3x more likely to convert. ' ||
        'Historical conversion: 11.76%.'
    
    WHEN 'TIER_NURTURE_TOO_EARLY' THEN
        'NURTURE - DO NOT ACTIVELY PURSUE: This advisor has a predictable career pattern but is ' ||
        'TOO EARLY in their cycle (less than 70% through typical tenure). Contacting now wastes ' ||
        'outreach - they convert at only 3.14%. Add to nurture sequence and revisit in ' ||
        CAST(cc_months_until_window AS STRING) || ' months when they enter their move window.'
    
    -- [... existing explanations unchanged ...]
END as tier_explanation
```

## Verification Gate 2.1

```
@workspace Run verification for Career Clock tier logic.

TASK:
1. After deploying updated tier logic to BigQuery, run this validation:

```sql
-- VALIDATION QUERY 2.1: New Tier Distribution
SELECT 
    score_tier,
    COUNT(*) as leads,
    SUM(CASE WHEN target = 1 THEN 1 ELSE 0 END) as conversions,
    ROUND(AVG(CAST(target AS FLOAT64)) * 100, 2) as actual_conv_rate,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_rate,
    ROUND(AVG(expected_lift), 2) as expected_lift
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_4`
GROUP BY score_tier
ORDER BY 
    CASE 
        WHEN score_tier LIKE 'TIER_0%' THEN 0 
        WHEN score_tier LIKE 'TIER_1%' THEN 1
        WHEN score_tier LIKE 'TIER_2%' THEN 2
        WHEN score_tier = 'TIER_NURTURE_TOO_EARLY' THEN 8
        ELSE 9
    END,
    score_tier;
```

EXPECTED RESULTS:
- TIER_0A_PRIME_MOVER_DUE: ~50-70 leads, ~16% conversion
- TIER_0B_SMALL_FIRM_DUE: ~80-100 leads, ~15% conversion
- TIER_0C_CLOCKWORK_DUE: ~60-80 leads, ~11% conversion
- TIER_NURTURE_TOO_EARLY: ~8,000-10,000 leads, ~3% conversion

2. Verify no regression in existing tiers:
```sql
-- Compare V3.3 vs V3.4 tier overlap
SELECT 
    v33.score_tier as v33_tier,
    v34.score_tier as v34_tier,
    COUNT(*) as leads
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_3` v33
INNER JOIN `savvy-gtm-analytics.ml_features.lead_scores_v3_4` v34
    ON v33.lead_id = v34.lead_id
GROUP BY v33.score_tier, v34.score_tier
ORDER BY leads DESC
LIMIT 20;
```

If validation passes, proceed to Step 3.
```

---

# STEP 3: Update Pipeline SQL for Lead List Generation

## Cursor Prompt 3.1: Update Hybrid Lead List SQL

```
@workspace Update the January 2026 lead list SQL to incorporate Career Clock tiers.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
2. Update the tier logic to include Career Clock tiers (TIER_0A, 0B, 0C)
3. Add handling for TIER_NURTURE_TOO_EARLY:
   - Option A: Exclude from main list entirely
   - Option B: Include but flag for nurture sequence
   - IMPLEMENT OPTION A (exclude from active lead list)
4. Update tier quotas to allocate leads to new tiers
5. Update tier display names and narratives
6. Add Career Clock columns to output: cc_career_pattern, cc_cycle_status, cc_months_until_window
7. Update comments to reflect V3.4.0

IMPORTANT: 
- Preserve V4 deprioritization logic (bottom 20% filter)
- Preserve SGA assignment logic
- Preserve deduplication logic

Show me the updated tier CTE and the final SELECT statement.
```

## Code Snippet 3.1: Update Tier Logic in Pipeline SQL

Update the tier scoring CTE in `January_2026_Lead_List_V3_V4_Hybrid.sql`:

```sql
-- ============================================================================
-- V3.4.0 TIER SCORING WITH CAREER CLOCK
-- ============================================================================
v3_tier_scoring AS (
    SELECT
        p.*,
        
        -- Career Clock Features (calculated inline)
        ccs.tenure_cv as cc_tenure_cv,
        ccs.avg_tenure_months as cc_avg_prior_tenure_months,
        SAFE_DIVIDE(p.tenure_months, ccs.avg_tenure_months) as cc_pct_through_cycle,
        
        CASE
            WHEN ccs.tenure_cv IS NULL THEN 'No_Pattern'
            WHEN ccs.tenure_cv < 0.3 THEN 'Clockwork'
            WHEN ccs.tenure_cv < 0.5 THEN 'Semi_Predictable'
            WHEN ccs.tenure_cv < 0.8 THEN 'Variable'
            ELSE 'Chaotic'
        END as cc_career_pattern,
        
        CASE
            WHEN ccs.tenure_cv IS NULL THEN 'Unknown'
            WHEN ccs.tenure_cv >= 0.5 THEN 'Unpredictable'
            WHEN SAFE_DIVIDE(p.tenure_months, ccs.avg_tenure_months) < 0.7 THEN 'Too_Early'
            WHEN SAFE_DIVIDE(p.tenure_months, ccs.avg_tenure_months) BETWEEN 0.7 AND 1.3 THEN 'In_Window'
            ELSE 'Overdue'
        END as cc_cycle_status,
        
        -- Boolean flags
        CASE
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(p.tenure_months, ccs.avg_tenure_months) BETWEEN 0.7 AND 1.3
            THEN TRUE ELSE FALSE
        END as cc_is_in_move_window,
        
        CASE
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(p.tenure_months, ccs.avg_tenure_months) < 0.7
            THEN TRUE ELSE FALSE
        END as cc_is_too_early,
        
        -- Months until window
        CASE
            WHEN ccs.tenure_cv < 0.5 AND ccs.avg_tenure_months IS NOT NULL
            THEN GREATEST(0, CAST(ccs.avg_tenure_months * 0.7 AS INT64) - p.tenure_months)
            ELSE NULL
        END as cc_months_until_window,
        
        -- V3.4.0 TIER ASSIGNMENT
        CASE
            -- TIER 0: Career Clock Priority Tiers
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(p.tenure_months, ccs.avg_tenure_months) BETWEEN 0.7 AND 1.3
                 AND p.tenure_months BETWEEN 12 AND 48
                 AND p.experience_months BETWEEN 60 AND 180
                 AND p.firm_net_change_12mo != 0
                 AND p.is_wirehouse = FALSE
            THEN 'TIER_0A_PRIME_MOVER_DUE'
            
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(p.tenure_months, ccs.avg_tenure_months) BETWEEN 0.7 AND 1.3
                 AND p.firm_rep_count <= 10
                 AND p.is_wirehouse = FALSE
            THEN 'TIER_0B_SMALL_FIRM_DUE'
            
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(p.tenure_months, ccs.avg_tenure_months) BETWEEN 0.7 AND 1.3
                 AND p.is_wirehouse = FALSE
            THEN 'TIER_0C_CLOCKWORK_DUE'
            
            -- [EXISTING TIER 1+ LOGIC HERE - UNCHANGED]
            
            -- NURTURE: Too Early (EXCLUDED from active list)
            WHEN ccs.tenure_cv < 0.5 
                 AND SAFE_DIVIDE(p.tenure_months, ccs.avg_tenure_months) < 0.7
                 AND p.firm_net_change_12mo >= -10
            THEN 'TIER_NURTURE_TOO_EARLY'
            
            ELSE 'STANDARD'
        END as score_tier
        
    FROM scored_prospects p
    LEFT JOIN career_clock_stats ccs ON p.crd = ccs.advisor_crd
),

-- Career Clock Stats CTE (add before v3_tier_scoring)
career_clock_stats AS (
    SELECT
        RIA_CONTACT_CRD_ID as advisor_crd,
        AVG(DATE_DIFF(
            PREVIOUS_REGISTRATION_COMPANY_END_DATE,
            PREVIOUS_REGISTRATION_COMPANY_START_DATE,
            MONTH
        )) as avg_tenure_months,
        SAFE_DIVIDE(
            STDDEV(DATE_DIFF(
                PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                MONTH
            )),
            AVG(DATE_DIFF(
                PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                PREVIOUS_REGISTRATION_COMPANY_START_DATE,
                MONTH
            ))
        ) as tenure_cv
    FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    WHERE PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
      AND PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
      AND DATE_DIFF(PREVIOUS_REGISTRATION_COMPANY_END_DATE,
                    PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) > 0
    GROUP BY RIA_CONTACT_CRD_ID
    HAVING COUNT(*) >= 2
)
```

## Code Snippet 3.2: Update Final Lead List Filter

```sql
-- ============================================================================
-- FINAL LEAD LIST (V3.4.0)
-- Excludes TIER_NURTURE_TOO_EARLY from active outreach
-- ============================================================================
final_lead_list AS (
    SELECT *
    FROM sga_assigned_leads
    WHERE score_tier != 'TIER_NURTURE_TOO_EARLY'  -- V3.4.0: Exclude too-early leads
      AND v4_deprioritize = FALSE                  -- V4: Exclude bottom 20%
)

-- Output columns (add Career Clock fields)
SELECT
    -- Existing columns...
    lead_id,
    crd,
    first_name,
    last_name,
    company,
    score_tier,
    tier_display,
    expected_conversion_rate,
    expected_lift,
    priority_rank,
    
    -- Career Clock columns (V3.4.0)
    cc_career_pattern,
    cc_cycle_status,
    cc_pct_through_cycle,
    cc_months_until_window,
    
    -- V4 columns...
    v4_score,
    v4_percentile,
    
    -- Narrative (updated for Career Clock)
    CASE 
        WHEN score_tier = 'TIER_0A_PRIME_MOVER_DUE' THEN
            'HIGHEST PRIORITY - Career Clock: ' || first_name || ' matches Prime Mover criteria AND ' ||
            'is currently in their personal "move window" (' || 
            CAST(ROUND(cc_pct_through_cycle * 100) AS STRING) || '% through typical tenure cycle). ' ||
            'Pattern: ' || cc_career_pattern || '. Historical conversion: 16.13%.'
        WHEN score_tier = 'TIER_0B_SMALL_FIRM_DUE' THEN
            'HIGHEST PRIORITY - Career Clock: ' || first_name || ' is at a small firm AND ' ||
            'is currently in their personal "move window" (' ||
            CAST(ROUND(cc_pct_through_cycle * 100) AS STRING) || '% through typical tenure cycle). ' ||
            'Pattern: ' || cc_career_pattern || '. Historical conversion: 15.46%.'
        WHEN score_tier = 'TIER_0C_CLOCKWORK_DUE' THEN
            'HIGH PRIORITY - Career Clock: ' || first_name || ' has a predictable career pattern and ' ||
            'is currently in their personal "move window". Even without other signals, ' ||
            'timing alone makes them 4.3x more likely to convert. Historical conversion: 11.76%.'
        -- [Existing narratives for other tiers...]
        ELSE tier_narrative
    END as tier_narrative,
    
    sga_name,
    assigned_at
    
FROM final_lead_list
ORDER BY sga_name, priority_rank, v4_percentile DESC;
```

## Code Snippet 3.3: Create Nurture List Output

```sql
-- ============================================================================
-- NURTURE LIST: Too-Early Leads for Future Outreach (V3.4.0)
-- These leads should be contacted when they enter their move window
-- ============================================================================
CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.nurture_list_too_early` AS

SELECT
    crd,
    first_name,
    last_name,
    company,
    email,
    cc_career_pattern,
    cc_cycle_status,
    cc_pct_through_cycle,
    cc_months_until_window,
    DATE_ADD(CURRENT_DATE(), INTERVAL cc_months_until_window MONTH) as estimated_window_entry_date,
    cc_avg_prior_tenure_months,
    current_firm_tenure_months,
    'Predictable advisor contacted too early in cycle. Will enter move window in ' ||
    CAST(cc_months_until_window AS STRING) || ' months.' as nurture_reason,
    CURRENT_TIMESTAMP() as created_at
    
FROM sga_assigned_leads
WHERE score_tier = 'TIER_NURTURE_TOO_EARLY'
ORDER BY cc_months_until_window ASC;  -- Soonest to enter window first
```

## Verification Gate 3.1

```
@workspace Run verification for updated pipeline SQL.

TASK:
1. Run the updated lead list query and verify:

```sql
-- VALIDATION 3.1: Lead List Tier Distribution
SELECT 
    score_tier,
    COUNT(*) as leads,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv,
    COUNT(DISTINCT sga_name) as sgas_covered
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
GROUP BY score_tier
ORDER BY 
    MIN(priority_rank);
```

EXPECTED:
- TIER_0A: 5-15 leads
- TIER_0B: 10-25 leads
- TIER_0C: 10-20 leads
- No TIER_NURTURE_TOO_EARLY in output (filtered)

2. Verify nurture list was created:
```sql
SELECT 
    COUNT(*) as nurture_leads,
    AVG(cc_months_until_window) as avg_months_until_window,
    MIN(estimated_window_entry_date) as soonest_window_entry
FROM `savvy-gtm-analytics.ml_features.nurture_list_too_early`;
```

EXPECTED:
- ~8,000-10,000 leads in nurture list
- avg_months_until_window: 12-24 months

3. Verify Career Clock columns in output:
```sql
SELECT 
    cc_career_pattern,
    cc_cycle_status,
    COUNT(*) as leads
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE cc_career_pattern IS NOT NULL
GROUP BY cc_career_pattern, cc_cycle_status
ORDER BY leads DESC;
```

If all validations pass, proceed to Step 4.
```

---

# STEP 4: Deploy to BigQuery

## Cursor Prompt 4.1: Deploy Feature Engineering Updates

```
@workspace Deploy the updated feature engineering SQL to BigQuery.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v3/sql/lead_scoring_features_pit.sql`
2. Connect to BigQuery project `savvy-gtm-analytics`
3. Execute the query to recreate the feature table with Career Clock features
4. The table should be: `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`
5. Log execution details to `pipeline/logs/EXECUTION_LOG.md`

EXECUTION COMMAND:
```python
from google.cloud import bigquery
client = bigquery.Client(project='savvy-gtm-analytics')

# Read SQL file
with open('v3/sql/lead_scoring_features_pit.sql', 'r') as f:
    sql = f.read()

# Execute
job = client.query(sql)
result = job.result()
print(f"Feature table updated: {job.total_bytes_processed / 1e9:.2f} GB processed")
```

LOG FORMAT for EXECUTION_LOG.md:
```markdown
## Step 4.1: Deploy Feature Engineering (Career Clock)

**Executed:** [TIMESTAMP]
**Status:** ✅ SUCCESS / ❌ FAILED
**Table:** `ml_features.lead_scoring_features_pit`

**New Features Added:**
- cc_completed_jobs
- cc_avg_prior_tenure_months
- cc_tenure_cv
- cc_career_pattern
- cc_pct_through_cycle
- cc_cycle_status
- cc_is_in_move_window
- cc_is_too_early
- cc_months_until_window

**Row Count:** [X]
**Career Clock Coverage:** [X]% of leads have pattern data
```

After deployment, run validation query and report results.
```

## Cursor Prompt 4.2: Deploy Tier Scoring Updates

```
@workspace Deploy the updated tier scoring SQL to BigQuery.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v3/sql/phase_4_v3_tiered_scoring.sql`
2. Update the CREATE TABLE statement to use version suffix:
   - Table name: `ml_features.lead_scores_v3_4`
3. Execute to create the new scoring table
4. After validation, update the production view to point to v3.4:
   ```sql
   CREATE OR REPLACE VIEW `ml_features.lead_scores_v3_production` AS
   SELECT * FROM `ml_features.lead_scores_v3_4`;
   ```
5. Log execution to `pipeline/logs/EXECUTION_LOG.md`

VALIDATION after deployment:
```sql
-- Count by new tiers
SELECT score_tier, COUNT(*) 
FROM `ml_features.lead_scores_v3_4`
WHERE score_tier LIKE 'TIER_0%' OR score_tier = 'TIER_NURTURE_TOO_EARLY'
GROUP BY score_tier;
```

LOG FORMAT:
```markdown
## Step 4.2: Deploy Tier Scoring V3.4.0

**Executed:** [TIMESTAMP]
**Status:** ✅ SUCCESS
**Table:** `ml_features.lead_scores_v3_4`

**New Tiers Added:**
| Tier | Count | Expected Conv |
|------|-------|---------------|
| TIER_0A_PRIME_MOVER_DUE | [X] | 16.13% |
| TIER_0B_SMALL_FIRM_DUE | [X] | 15.46% |
| TIER_0C_CLOCKWORK_DUE | [X] | 11.76% |
| TIER_NURTURE_TOO_EARLY | [X] | 3.14% |

**Production View Updated:** ✅
```
```

## Cursor Prompt 4.3: Deploy Pipeline Lead List Updates

```
@workspace Deploy the updated lead list pipeline to BigQuery.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
2. Execute to create/update:
   - `ml_features.january_2026_lead_list` (main lead list)
   - `ml_features.nurture_list_too_early` (nurture list)
3. Verify lead counts and tier distribution
4. Log execution to `pipeline/logs/EXECUTION_LOG.md`

VALIDATION:
```sql
-- Main list summary
SELECT 
    'Active Lead List' as list_type,
    COUNT(*) as total_leads,
    COUNT(DISTINCT sga_name) as sgas,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_expected_conv
FROM `ml_features.january_2026_lead_list`
UNION ALL
SELECT 
    'Nurture List (Too Early)',
    COUNT(*),
    NULL,
    3.14
FROM `ml_features.nurture_list_too_early`;
```

LOG FORMAT:
```markdown
## Step 4.3: Deploy Lead List Pipeline V3.4.0

**Executed:** [TIMESTAMP]
**Status:** ✅ SUCCESS

**Active Lead List:**
- Total Leads: [X]
- SGAs Covered: [X]
- Tier 0 Leads: [X] (Career Clock priority)
- Expected Conversion: [X]%

**Nurture List (Too Early):**
- Total Leads: [X]
- Avg Months Until Window: [X]

**Career Clock Impact:**
- Leads promoted to Tier 0: [X]
- Leads moved to nurture: [X]
- Net active list change: [X]
```
```

---

# STEP 5: Update Documentation

## Cursor Prompt 5.1: Update VERSION_3_MODEL_REPORT.md

```
@workspace Update the V3 model report with Career Clock documentation.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `v3/VERSION_3_MODEL_REPORT.md`
2. Add a new section "## V3.4.0: Career Clock Feature (January 2026)" after the existing version sections
3. Document:
   - Discovery process and hypothesis
   - Validation results (pattern distribution, conversion rates)
   - New tier definitions (TIER_0A, 0B, 0C, NURTURE_TOO_EARLY)
   - Expected impact
   - Technical implementation details
4. Update the "Current Production" version at top of doc to V3.4.0
5. Update the tier performance table with new tiers

Add this content:
```

## Code Snippet 5.1: V3 Model Report Update

Add to `v3/VERSION_3_MODEL_REPORT.md`:

```markdown
---

## V3.4.0: Career Clock Feature (January 2026)

### Discovery Summary

Analysis revealed that ~20% of financial advisors have **predictable career patterns** - they change firms at consistent intervals. By identifying these "Clockwork" advisors and determining where they are in their personal career cycle, we can dramatically improve conversion rates.

### Key Finding: Timing Matters as Much as Profile

The same advisor converts at **2-3x different rates** depending on where they are in their personal career cycle:

| Timing Status | Definition | Conversion | Lift |
|---------------|------------|------------|------|
| **In Window** | 70-130% through typical tenure | 10-16% | 4-6x |
| **Too Early** | <70% through typical tenure | 3.14% | 1.1x |
| **Overdue** | >130% through typical tenure | 5-8% | 2x |

### Advisor Pattern Distribution

| Pattern Type | CV Range | % of Advisors | Predictability |
|--------------|----------|---------------|----------------|
| Clockwork | <0.3 | 20% | High |
| Semi-Predictable | 0.3-0.5 | 14% | Medium |
| Variable | 0.5-0.8 | 30% | Low |
| Chaotic | >0.8 | 36% | None |

### New Tiers Added

#### TIER_0A_PRIME_MOVER_DUE (16.13% conversion, 5.89x lift)
**Criteria:**
- Matches T1 Prime Mover criteria (1-4yr tenure, 5-15yr experience, firm instability)
- AND has predictable career pattern (tenure CV < 0.5)
- AND is currently in move window (70-130% through typical cycle)

**Rationale:** Combines the best static profile with optimal timing signal.

#### TIER_0B_SMALL_FIRM_DUE (15.46% conversion, 5.64x lift)
**Criteria:**
- Small firm (≤10 reps)
- AND has predictable career pattern
- AND is currently in move window

**Rationale:** Small firm advisors have portable books; timing signal amplifies this.

#### TIER_0C_CLOCKWORK_DUE (11.76% conversion, 4.29x lift)
**Criteria:**
- Has predictable career pattern
- AND is currently in move window
- No other tier qualifications required

**Rationale:** "Rescues" STANDARD leads who have no priority signals but optimal timing.

#### TIER_NURTURE_TOO_EARLY (3.14% conversion, 1.14x lift)
**Criteria:**
- Has predictable career pattern
- AND is too early in cycle (<70% through)
- AND not at heavy bleeding firm (those convert anyway)

**Action:** Exclude from active outreach, add to nurture sequence with `cc_months_until_window` as recontact date.

### Technical Implementation

**New Features Added to Feature Engineering:**
- `cc_tenure_cv`: Coefficient of variation of prior job tenures
- `cc_avg_prior_tenure_months`: Average tenure at prior firms
- `cc_pct_through_cycle`: Current tenure / average prior tenure
- `cc_career_pattern`: Categorical (Clockwork/Semi_Predictable/Variable/Chaotic/No_Pattern)
- `cc_cycle_status`: Categorical (In_Window/Too_Early/Overdue/Unpredictable/Unknown)
- `cc_is_in_move_window`: Boolean flag for tier logic
- `cc_is_too_early`: Boolean flag for deprioritization
- `cc_months_until_window`: Months until advisor enters their move window

**Data Source:** `contact_registered_employment_history` - completed job tenures only

### Expected Impact

| Metric | Before V3.4 | After V3.4 | Change |
|--------|-------------|------------|--------|
| Highest Tier Conv | 13.64% | 16.13% | +18% |
| New Top Tier Leads | 0 | ~50-100 | +50-100 |
| Leads Deprioritized | 0 | ~9,000 | -9,000 |
| Expected Overall Conv | 4.61% | 5.2-5.5%* | +15% |

*Estimate based on tier redistribution

### Validation Results

**Tier × Career Clock Cross-Analysis:**

| V3 Tier | In_Window Conv | Too_Early Conv | Lift from Timing |
|---------|----------------|----------------|------------------|
| T1_PRIME_MOVER | 16.13% | 0.0% | ∞ (Too_Early = 0) |
| STANDARD | 11.76% | 3.14% | +274% |
| T3_HEAVY_BLEEDER | 6.98% | 10.45% | -33% (exception) |

**Key Insight:** Heavy bleeding firms are the exception - advisors convert even when "too early" because the firm crisis overrides personal timing.

---
```

## Cursor Prompt 5.2: Update README.md

```
@workspace Update the main README with Career Clock summary.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `README.md`
2. Update the "Current Production" section to reference V3.4.0
3. Add Career Clock to the feature summary
4. Update the model performance table
5. Add Career Clock to the "Key Innovations" list

Find the "V4.1.0 R3 Model" section and add a similar section for V3.4.0 below it.
Update any references to "V3.3" to "V3.4" where appropriate.
```

## Code Snippet 5.2: README Update

Add to `README.md` after the V4.1.0 R3 section:

```markdown
---

## V3.4.0: Career Clock Feature (January 2026)

### The Discovery

Analysis of 350,000+ advisor employment histories revealed that **20% of advisors have predictable career patterns** - they change firms at consistent intervals (coefficient of variation < 0.5).

**The Insight:** The SAME advisor converts at 2-3x different rates depending on WHERE they are in their personal career cycle.

### New Tiers

| Tier | Criteria | Conversion | Lift |
|------|----------|------------|------|
| **TIER_0A_PRIME_MOVER_DUE** | T1 + In Move Window | 16.13% | 5.89x |
| **TIER_0B_SMALL_FIRM_DUE** | Small Firm + In Window | 15.46% | 5.64x |
| **TIER_0C_CLOCKWORK_DUE** | Any + In Move Window | 11.76% | 4.29x |
| **TIER_NURTURE_TOO_EARLY** | Predictable + Too Early | 3.14% | 1.14x |

### Key Features

- `cc_tenure_cv`: Pattern consistency (lower = more predictable)
- `cc_pct_through_cycle`: Where they are in their personal clock
- `cc_is_in_move_window`: Optimal timing flag
- `cc_months_until_window`: When to recontact nurture leads

### Impact

- **New highest tier** at 16.13% conversion (was 13.64%)
- **~9,000 leads deprioritized** to nurture sequence
- **~100 STANDARD leads rescued** at 11.76% conversion
- **Expected +15-20% MQL improvement**

---
```

## Cursor Prompt 5.3: Update Execution Log

```
@workspace Create execution log entry for Career Clock implementation.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Open `pipeline/logs/EXECUTION_LOG.md`
2. Add a comprehensive entry for the V3.4.0 Career Clock implementation
3. Include all deployment steps, validation results, and any issues encountered

Use this template and fill in actual values after each deployment step:
```

## Code Snippet 5.3: Execution Log Entry

Add to `pipeline/logs/EXECUTION_LOG.md`:

```markdown
---

# V3.4.0 Career Clock Implementation - [DATE]

## Overview

Implemented Career Clock feature based on analysis showing 20% of advisors have predictable career patterns. Added 3 new priority tiers and 1 nurture tier.

## Execution Steps

### Step 1: Feature Engineering Update
**Executed:** [TIMESTAMP]  
**Status:** ✅ SUCCESS  
**File:** `v3/sql/lead_scoring_features_pit.sql`  
**Table:** `ml_features.lead_scoring_features_pit`

**New Features Added:**
| Feature | Type | Description |
|---------|------|-------------|
| cc_tenure_cv | FLOAT | Coefficient of variation of prior tenures |
| cc_avg_prior_tenure_months | FLOAT | Average tenure at prior firms |
| cc_pct_through_cycle | FLOAT | Current / average tenure ratio |
| cc_career_pattern | STRING | Clockwork/Semi_Predictable/Variable/Chaotic |
| cc_cycle_status | STRING | In_Window/Too_Early/Overdue/Unpredictable |
| cc_is_in_move_window | BOOLEAN | Optimal timing flag |
| cc_is_too_early | BOOLEAN | Deprioritization flag |
| cc_months_until_window | INT | Months until move window |

**Validation Results:**
```
Pattern Distribution:
- Clockwork: X leads (X%)
- Semi_Predictable: X leads (X%)
- Variable: X leads (X%)
- Chaotic: X leads (X%)
- No_Pattern: X leads (X%)

In_Window Count: X leads
Too_Early Count: X leads
```

### Step 2: Tier Scoring Update
**Executed:** [TIMESTAMP]  
**Status:** ✅ SUCCESS  
**File:** `v3/sql/phase_4_v3_tiered_scoring.sql`  
**Table:** `ml_features.lead_scores_v3_4`

**New Tiers Added:**
| Tier | Count | Conversions | Conv Rate | Expected |
|------|-------|-------------|-----------|----------|
| TIER_0A_PRIME_MOVER_DUE | X | X | X% | 16.13% |
| TIER_0B_SMALL_FIRM_DUE | X | X | X% | 15.46% |
| TIER_0C_CLOCKWORK_DUE | X | X | X% | 11.76% |
| TIER_NURTURE_TOO_EARLY | X | X | X% | 3.14% |

**Production View Updated:** ✅ `ml_features.lead_scores_v3_production`

### Step 3: Pipeline Lead List Update
**Executed:** [TIMESTAMP]  
**Status:** ✅ SUCCESS  
**File:** `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Active Lead List:**
- Total Leads: X
- Career Clock Tier 0 Leads: X
- Expected Overall Conversion: X%

**Nurture List Created:**
- Table: `ml_features.nurture_list_too_early`
- Total Leads: X
- Avg Months Until Window: X

### Step 4: Documentation Updates
**Files Updated:**
- ✅ `v3/VERSION_3_MODEL_REPORT.md` - Added V3.4.0 section
- ✅ `README.md` - Updated current production version
- ✅ `pipeline/logs/EXECUTION_LOG.md` - This entry

## Validation Summary

### Gate 1: Feature Engineering ✅
- [X] Career Clock features calculated correctly
- [X] Row count unchanged from V3.3
- [X] ~20% of leads have Clockwork/Semi_Predictable patterns

### Gate 2: Tier Scoring ✅
- [X] New tiers populated with expected counts
- [X] No regression in existing tier performance
- [X] Priority ranks updated correctly

### Gate 3: Lead List Pipeline ✅
- [X] TIER_NURTURE_TOO_EARLY excluded from active list
- [X] Nurture list created with recontact dates
- [X] Career Clock columns in output

### Gate 4: Documentation ✅
- [X] V3.4.0 documented in model report
- [X] README updated
- [X] Execution log complete

## Issues Encountered

[Document any issues and resolutions here]

## Rollback Plan

If issues are discovered post-deployment:

1. **Revert tier scoring:**
   ```sql
   CREATE OR REPLACE VIEW `ml_features.lead_scores_v3_production` AS
   SELECT * FROM `ml_features.lead_scores_v3_3`;
   ```

2. **Revert lead list:**
   - Re-run previous version of `January_2026_Lead_List_V3_V4_Hybrid.sql`

3. **Revert features:**
   - Re-run previous version of `lead_scoring_features_pit.sql`

## Next Steps

1. [ ] Monitor January 2026 lead list performance
2. [ ] Track conversion rates by Career Clock tier
3. [ ] Evaluate nurture list recontact effectiveness
4. [ ] Consider adding Career Clock features to V4.1 model

---

**Implementation Completed:** [TIMESTAMP]  
**Implemented By:** [NAME]  
**Reviewed By:** [NAME]  
**Model Version:** V3.4.0
```

---

# STEP 6: Final Validation and Monitoring Setup

## Cursor Prompt 6.1: Create Monitoring Query

```
@workspace Create a monitoring query for Career Clock tier performance.

WORKING DIRECTORY: C:\Users\russe\Documents\lead_scoring_production

TASK:
1. Create a new file `pipeline/sql/monitor_career_clock_performance.sql`
2. This query should be run weekly to track:
   - Conversion rates by Career Clock tier
   - Comparison to expected rates
   - Nurture list progression (leads entering their move window)
3. Add instructions for scheduling this as a recurring report
```

## Code Snippet 6.1: Monitoring Query

Create `pipeline/sql/monitor_career_clock_performance.sql`:

```sql
-- ============================================================================
-- CAREER CLOCK PERFORMANCE MONITORING
-- Run weekly to track V3.4.0 tier performance
-- ============================================================================

-- 1. TIER PERFORMANCE vs EXPECTED
SELECT 
    'Career Clock Tier Performance' as report_section,
    score_tier,
    COUNT(*) as leads_contacted,
    SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as conversions,
    ROUND(AVG(CASE WHEN mql_date IS NOT NULL THEN 1.0 ELSE 0.0 END) * 100, 2) as actual_conv_rate,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_rate,
    ROUND(
        (AVG(CASE WHEN mql_date IS NOT NULL THEN 1.0 ELSE 0.0 END) - AVG(expected_conversion_rate)) 
        / AVG(expected_conversion_rate) * 100, 
    1) as pct_vs_expected
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` l
LEFT JOIN `savvy-gtm-analytics.salesforce_data.leads` sf ON l.crd = sf.FA_CRD__c
WHERE score_tier LIKE 'TIER_0%'
   OR score_tier IN ('TIER_1A_PRIME_MOVER_CFP', 'TIER_1B_PRIME_ZERO_FRICTION', 'STANDARD')
GROUP BY score_tier
ORDER BY MIN(priority_rank);

-- 2. NURTURE LIST: LEADS ENTERING MOVE WINDOW
SELECT 
    'Nurture List - Entering Window' as report_section,
    COUNT(*) as total_nurture_leads,
    COUNTIF(estimated_window_entry_date <= CURRENT_DATE()) as entered_window,
    COUNTIF(estimated_window_entry_date BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY)) as entering_next_30_days,
    COUNTIF(estimated_window_entry_date BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 90 DAY)) as entering_next_90_days
FROM `savvy-gtm-analytics.ml_features.nurture_list_too_early`;

-- 3. CAREER CLOCK PATTERN VALIDATION
SELECT
    'Career Clock Pattern Validation' as report_section,
    cc_career_pattern,
    cc_cycle_status,
    COUNT(*) as leads,
    SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as conversions,
    ROUND(AVG(CASE WHEN mql_date IS NOT NULL THEN 1.0 ELSE 0.0 END) * 100, 2) as conv_rate
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` l
LEFT JOIN `savvy-gtm-analytics.salesforce_data.leads` sf ON l.crd = sf.FA_CRD__c
WHERE cc_career_pattern IS NOT NULL
GROUP BY cc_career_pattern, cc_cycle_status
ORDER BY cc_career_pattern, 
    CASE cc_cycle_status WHEN 'In_Window' THEN 1 WHEN 'Too_Early' THEN 2 ELSE 3 END;

-- 4. ALERT: Tiers underperforming by >20%
SELECT 
    'ALERT: Underperforming Tiers' as report_section,
    score_tier,
    actual_conv_rate,
    expected_conv_rate,
    pct_vs_expected
FROM (
    SELECT 
        score_tier,
        ROUND(AVG(CASE WHEN mql_date IS NOT NULL THEN 1.0 ELSE 0.0 END) * 100, 2) as actual_conv_rate,
        ROUND(AVG(expected_conversion_rate) * 100, 2) as expected_conv_rate,
        ROUND(
            (AVG(CASE WHEN mql_date IS NOT NULL THEN 1.0 ELSE 0.0 END) - AVG(expected_conversion_rate)) 
            / AVG(expected_conversion_rate) * 100, 
        1) as pct_vs_expected
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list` l
    LEFT JOIN `savvy-gtm-analytics.salesforce_data.leads` sf ON l.crd = sf.FA_CRD__c
    WHERE score_tier LIKE 'TIER_0%' OR score_tier LIKE 'TIER_1%'
    GROUP BY score_tier
    HAVING COUNT(*) >= 10  -- Only tiers with sufficient sample
)
WHERE pct_vs_expected < -20;
```

## Verification Gate 6.1: Final System Check

```
@workspace Run final system validation for Career Clock implementation.

TASK:
Execute this comprehensive validation script:

```python
"""
V3.4.0 Career Clock - Final Validation Script
Run after all deployment steps complete
"""

from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='savvy-gtm-analytics')

print("=" * 60)
print("V3.4.0 CAREER CLOCK - FINAL VALIDATION")
print("=" * 60)

# Test 1: Feature table has Career Clock columns
print("\n[TEST 1] Feature Table Schema...")
query = """
SELECT column_name 
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'lead_scoring_features_pit'
  AND column_name LIKE 'cc_%'
"""
result = client.query(query).to_dataframe()
cc_columns = result['column_name'].tolist()
expected_columns = ['cc_tenure_cv', 'cc_avg_prior_tenure_months', 'cc_pct_through_cycle',
                   'cc_career_pattern', 'cc_cycle_status', 'cc_is_in_move_window', 
                   'cc_is_too_early', 'cc_months_until_window']
missing = set(expected_columns) - set(cc_columns)
if missing:
    print(f"  ❌ FAILED: Missing columns: {missing}")
else:
    print(f"  ✅ PASSED: All {len(expected_columns)} Career Clock columns present")

# Test 2: New tiers exist in scoring table
print("\n[TEST 2] New Tiers in Scoring Table...")
query = """
SELECT score_tier, COUNT(*) as cnt
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_4`
WHERE score_tier LIKE 'TIER_0%' OR score_tier = 'TIER_NURTURE_TOO_EARLY'
GROUP BY score_tier
"""
result = client.query(query).to_dataframe()
print(result.to_string(index=False))
if len(result) >= 4:
    print("  ✅ PASSED: All new tiers present")
else:
    print("  ❌ FAILED: Missing tiers")

# Test 3: Lead list excludes NURTURE tier
print("\n[TEST 3] Lead List Excludes Nurture Tier...")
query = """
SELECT COUNTIF(score_tier = 'TIER_NURTURE_TOO_EARLY') as nurture_in_list
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
"""
result = client.query(query).to_dataframe()
nurture_count = result['nurture_in_list'].iloc[0]
if nurture_count == 0:
    print(f"  ✅ PASSED: No nurture leads in active list")
else:
    print(f"  ❌ FAILED: {nurture_count} nurture leads in active list")

# Test 4: Nurture list exists
print("\n[TEST 4] Nurture List Created...")
query = """
SELECT COUNT(*) as nurture_leads,
       AVG(cc_months_until_window) as avg_months
FROM `savvy-gtm-analytics.ml_features.nurture_list_too_early`
"""
result = client.query(query).to_dataframe()
print(f"  Nurture leads: {result['nurture_leads'].iloc[0]:,}")
print(f"  Avg months until window: {result['avg_months'].iloc[0]:.1f}")
if result['nurture_leads'].iloc[0] > 5000:
    print("  ✅ PASSED: Nurture list populated")
else:
    print("  ⚠️ WARNING: Nurture list smaller than expected")

# Test 5: Career Clock columns in lead list output
print("\n[TEST 5] Career Clock Columns in Lead List...")
query = """
SELECT 
    COUNTIF(cc_career_pattern IS NOT NULL) as has_pattern,
    COUNTIF(cc_cycle_status IS NOT NULL) as has_status,
    COUNT(*) as total
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
"""
result = client.query(query).to_dataframe()
coverage = result['has_pattern'].iloc[0] / result['total'].iloc[0] * 100
print(f"  Career Clock coverage: {coverage:.1f}%")
if coverage > 10:
    print("  ✅ PASSED: Career Clock data in output")
else:
    print("  ⚠️ WARNING: Low Career Clock coverage")

print("\n" + "=" * 60)
print("VALIDATION COMPLETE")
print("=" * 60)
```

All tests should pass before considering deployment complete.
```

---

# Summary: Quick Reference

## Files Modified

| File | Changes |
|------|---------|
| `v3/sql/lead_scoring_features_pit.sql` | Added Career Clock CTEs and features |
| `v3/sql/phase_4_v3_tiered_scoring.sql` | Added TIER_0A/0B/0C and NURTURE tiers |
| `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql` | Added Career Clock logic, nurture list |
| `v3/VERSION_3_MODEL_REPORT.md` | Documented V3.4.0 |
| `README.md` | Updated production version |
| `pipeline/logs/EXECUTION_LOG.md` | Added execution record |

## Files Created

| File | Purpose |
|------|---------|
| `pipeline/sql/monitor_career_clock_performance.sql` | Weekly monitoring query |

## BigQuery Tables Updated

| Table | Action |
|-------|--------|
| `ml_features.lead_scoring_features_pit` | Added 10 Career Clock columns |
| `ml_features.lead_scores_v3_4` | Created with new tiers |
| `ml_features.lead_scores_v3_production` | View updated to v3.4 |
| `ml_features.january_2026_lead_list` | Updated with Career Clock |
| `ml_features.nurture_list_too_early` | Created |

## Expected Outcomes

- **New highest tier**: 16.13% conversion (TIER_0A)
- **~50-100 leads** in Career Clock priority tiers
- **~9,000 leads** moved to nurture sequence
- **~15-20% improvement** in expected MQL rate
