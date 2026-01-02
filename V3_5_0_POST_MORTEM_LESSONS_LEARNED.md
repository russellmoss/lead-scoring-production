# V3.5.0 M&A Tiers - Post-Mortem & Lessons Learned

**Document Version**: 1.1  
**Created**: January 2, 2026  
**Last Updated**: January 2, 2026  
**Author**: Lead Scoring Team  
**Status**: 📋 LESSONS LEARNED - DO NOT REPEAT THESE MISTAKES  

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Timeline of Events](#2-timeline-of-events)
3. [Problem #1: BigQuery CTE Scoping Issues](#3-problem-1-bigquery-cte-scoping-issues)
4. [Problem #2: Data Type Mismatches](#4-problem-2-data-type-mismatches)
5. [Problem #3: Overly Restrictive Rep Cap](#5-problem-3-overly-restrictive-rep-cap)
6. [Problem #4: Missing Tiers in ORDER BY Clauses](#6-problem-4-missing-tiers-in-order-by-clauses)
7. [Problem #5: Exclusion List Conflicts](#7-problem-5-exclusion-list-conflicts)
8. [Problem #6: Silent Failures with No Errors](#8-problem-6-silent-failures-with-no-errors)
9. [Problem #7: Diagnostic Queries vs Actual Results Mismatch](#9-problem-7-diagnostic-queries-vs-actual-results-mismatch)
10. [Problem #8: Complexity Creep](#10-problem-8-complexity-creep)
11. [Problem #9: Inadequate Pre-Implementation Testing](#11-problem-9-inadequate-pre-implementation-testing)
12. [Problem #10: Debug Column Overload](#12-problem-10-debug-column-overload)
13. [Problem #11: EXISTS Subquery False Confidence](#13-problem-11-exists-subquery-false-confidence)
14. [Problem #12: Not Checking BigQuery Execution Logs Early](#14-problem-12-not-checking-bigquery-execution-logs-early)
15. [Problem #13: The "Works in Isolation" Trap](#15-problem-13-the-works-in-isolation-trap)
16. [Problem #14: Not Knowing When to Stop](#16-problem-14-not-knowing-when-to-stop)
17. [Problem #15: The Value of Clean Reverts](#17-problem-15-the-value-of-clean-reverts)
18. [Root Cause Analysis Summary](#18-root-cause-analysis-summary)
19. [What We Should Have Done Differently](#19-what-we-should-have-done-differently)
20. [Checklist for Future Implementations](#20-checklist-for-future-implementations)
21. [Appendix: Failed Code Examples](#21-appendix-failed-code-examples)

---

## 1. Executive Summary

### What Happened

We attempted to add M&A Active Tiers to V3.5.0 lead scoring. Despite multiple implementation attempts and debugging sessions spanning an entire day, **0 M&A advisors appeared in the final lead list**.

### The Irony

- Diagnostic queries showed **2,198 M&A advisors should qualify**
- The M&A table had **66 firms** and **4,318 advisors**
- JOINs worked perfectly **in isolation**
- But the final table had **0 M&A leads**

### Ultimate Outcome

After ~8+ hours of debugging, we reverted to the pre-V3.5.0 codebase. The feature was not deployed.

### Key Lesson

**Complex CTE chains in BigQuery are unreliable for critical business logic.** A simpler architecture (pre-built tables with simple JOINs) would have avoided all these issues.

### Related Documentation

For the correct implementation approach, see: **`V3_5_0_MA_TIER_COMPREHENSIVE_IMPLEMENTATION_GUIDE.md`**

---

## 2. Timeline of Events

| Time | Event | Outcome |
|------|-------|---------|
| **Morning** | Initial V3.5.0 implementation with M&A CTEs | Table created, 0 M&A leads |
| **+1 hour** | Added SAFE_CAST for data type issues | Still 0 M&A leads |
| **+2 hours** | Fixed FULL OUTER JOIN in firm_metrics | Still 0 M&A leads |
| **+3 hours** | Moved M&A tiers before Career Clock in CASE | Still 0 M&A leads |
| **+4 hours** | Added M&A exemption to excluded_firms filter | Still 0 M&A leads |
| **+5 hours** | Added M&A exemption to excluded_firm_crds filter | Still 0 M&A leads |
| **+6 hours** | Removed 200-rep cap on M&A exemption | Still 0 M&A leads |
| **+7 hours** | Added debug columns throughout pipeline | All debug columns = 0 or NULL |
| **+8 hours** | Ran diagnostic queries showing JOIN works | Diagnostic: 2,198 ✅, Actual: 0 ❌ |
| **+8.5 hours** | Identified CTE scoping as likely root cause | Too late to fix properly |
| **End of day** | Reverted to pre-V3.5.0 codebase | Feature not deployed |

### Pattern Observed

Each "fix" addressed a symptom, not the root cause. The root cause (CTE scoping/evaluation issues) was only identified at the end after all other possibilities were exhausted.

---

## 3. Problem #1: BigQuery CTE Scoping Issues

### What Happened

We defined a CTE `ma_target_firms` early in the query and referenced it in multiple places:

```sql
-- Defined at line 215
ma_target_firms AS (
    SELECT firm_crd, ma_status, ...
    FROM `ml_features.active_ma_target_firms`
    WHERE ma_status IN ('HOT', 'ACTIVE')
),

-- Referenced at line 241 (firm_metrics)
FULL OUTER JOIN ma_target_firms ma ON h.firm_crd = ma.firm_crd

-- Referenced at line 303 (base_prospects)
LEFT JOIN ma_target_firms ma_check ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ma_check.firm_crd

-- Referenced at line 423 (enriched_prospects)
LEFT JOIN ma_target_firms ma ON bp.firm_crd = ma.firm_crd
```

### The Problem

Despite the CTE being defined before all references, **the JOINs returned 0 matches** in the actual query execution. When we ran the same JOIN logic in isolation (not as part of the 1,400-line query), it worked perfectly.

### Evidence

| Test | Result |
|------|--------|
| CTE definition correct | ✅ Valid SQL |
| CTE order correct (defined before use) | ✅ Line 215 before 241, 303, 423 |
| JOIN works in isolation | ✅ 2,225 matches |
| JOIN works in full query | ❌ 0 matches |

### Why This Happens

BigQuery's query optimizer can:
1. Reorder CTE evaluation in unexpected ways
2. Apply predicates that filter out rows before JOINs
3. Have scoping issues when CTEs reference other CTEs
4. Behave differently for complex queries vs simple ones

### Lesson Learned

> **NEVER rely on CTEs for critical business logic that must work reliably.**
> 
> Use pre-built materialized tables instead. They can be verified independently before use.

### What We Should Have Done

```sql
-- WRONG: CTE reference (unreliable)
LEFT JOIN ma_target_firms ma_check ON ...

-- RIGHT: Direct table reference (reliable)
LEFT JOIN `ml_features.ma_eligible_advisors` ma ON ...
```

---

## 4. Problem #2: Data Type Mismatches

### What Happened

The `firm_crd` column had different data types across tables:

| Table | Column | Data Type |
|-------|--------|-----------|
| `active_ma_target_firms` | firm_crd | STRING (or unknown) |
| `ria_contacts_current` | PRIMARY_FIRM | STRING |
| `firm_headcount` (CTE) | firm_crd | INT64 |

### The Problem

When JOINing STRING to INT64, BigQuery:
- Sometimes does implicit casting (works)
- Sometimes returns 0 matches (fails silently)
- Never throws an error

### Evidence

```sql
-- This returned 0 matches in the full query
LEFT JOIN ma_target_firms ma_check 
    ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ma_check.firm_crd
    -- ma_check.firm_crd might be STRING!
```

### The Fix We Tried

```sql
-- Added SAFE_CAST in CTE definition
ma_target_firms AS (
    SELECT 
        SAFE_CAST(firm_crd AS INT64) as firm_crd,  -- Explicit cast
        ...
)
```

### Why It Didn't Help

The data type fix was correct, but it was masked by the larger CTE scoping issue. Even with correct data types, the CTE reference still returned 0 matches.

### Lesson Learned

> **Always verify data types BEFORE writing JOINs.**
> 
> Run this query for every table involved:
> ```sql
> SELECT column_name, data_type
> FROM `project.dataset.INFORMATION_SCHEMA.COLUMNS`
> WHERE table_name = 'your_table' AND column_name = 'join_column';
> ```

### Prevention Checklist

- [ ] Check data types of all JOIN columns before implementation
- [ ] Use explicit SAFE_CAST on both sides of JOIN if types differ
- [ ] Test JOIN in isolation before embedding in complex query
- [ ] Verify JOIN returns expected row count

---

## 5. Problem #3: Overly Restrictive Rep Cap

### What Happened

We added a 200-rep cap on the M&A exemption as a "safety measure":

```sql
AND (
    df.firm_rep_count <= 50                    -- Normal exclusion
    OR (
        df.score_tier LIKE 'TIER_MA%'          -- M&A exemption
        AND df.firm_rep_count <= 200           -- ← THE PROBLEM
    )
)
```

### The Problem

This cap excluded **94% of M&A advisors**:

| Population | Count | Percentage |
|------------|-------|------------|
| Total M&A advisors | 2,225 | 100% |
| At firms >200 reps | 2,095 | **94%** |
| At firms ≤200 reps | 130 | 6% |

### The Irony

Commonwealth (our validation case) had **~2,500 reps**. Our "safety cap" would have excluded the very advisors that validated the M&A signal!

### Why We Added It

Fear of accidentally including mega-firms (wirehouses, LPL itself). But this fear was unfounded because:
1. Wirehouses already excluded by `is_wirehouse = 0` in tier criteria
2. Serial acquirers (LPL, etc.) excluded in `active_ma_target_firms` table
3. Investment banks and PE firms excluded in source table

### The Fix

Remove the cap entirely:

```sql
AND (
    df.firm_rep_count <= 50                    -- Normal exclusion
    OR df.score_tier LIKE 'TIER_MA%'           -- M&A exemption (no cap)
)
```

### Lesson Learned

> **"Safety measures" that block 94% of your target population aren't safety measures—they're feature killers.**
> 
> When adding caps or limits:
> 1. Calculate what percentage of target population is affected
> 2. If >50% blocked, the cap is too restrictive
> 3. Trust existing safeguards before adding new ones

---

## 6. Problem #4: Missing Tiers in ORDER BY Clauses

### What Happened

We added M&A tiers to the tier assignment logic but forgot to add them to the ORDER BY clauses used for deduplication and prioritization.

### The Code (Before Fix)

```sql
-- deduplicated_before_quotas ORDER BY (line 1152)
CASE tl.final_tier
    WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 1
    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 2
    WHEN 'TIER_1G_ENHANCED_SWEET_SPOT' THEN 3
    -- ... more tiers ...
    WHEN 'STANDARD_HIGH_V4' THEN 10
END
-- ❌ MISSING: TIER_0A, TIER_0B, TIER_0C, TIER_MA_ACTIVE_PRIME, TIER_MA_ACTIVE
```

### The Problem

When a tier is missing from the ORDER BY CASE statement, BigQuery assigns it `NULL` priority. NULL values sort unpredictably, causing:
1. M&A leads to be deprioritized (sorted to end)
2. M&A leads to be deduplicated away in favor of lower-priority tiers
3. M&A leads to miss their tier quotas

### Locations That Needed Updates

| CTE | Line | Status |
|-----|------|--------|
| `deduplicated_before_quotas` | ~1152 | ❌ Missing M&A tiers |
| `linkedin_prioritized` (ORDER BY) | ~1179 | ❌ Missing M&A tiers |
| `linkedin_prioritized` (no_linkedin_rank) | ~1203 | ✅ Had M&A tiers |
| `scored_prospects` (priority_rank) | ~678 | ✅ Had M&A tiers |

### The Fix

Add all tiers to every ORDER BY:

```sql
CASE tl.final_tier
    -- Career Clock (highest)
    WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
    WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
    WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
    -- M&A Tiers
    WHEN 'TIER_MA_ACTIVE_PRIME' THEN 4
    WHEN 'TIER_MA_ACTIVE' THEN 5
    -- Zero Friction & Priority
    WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 6
    -- ... etc ...
END
```

### Lesson Learned

> **When adding a new tier, search for ALL ORDER BY clauses that reference tier names.**
> 
> Use this search pattern:
> ```
> WHEN.*TIER_.*THEN
> ```
> 
> Every match needs the new tier added.

### Prevention Checklist

- [ ] Search entire SQL file for `WHEN.*TIER_.*THEN`
- [ ] Add new tier to EVERY matching location
- [ ] Verify order is correct (highest priority = lowest number)
- [ ] Test that new tier leads appear in expected position

---

## 7. Problem #5: Exclusion List Conflicts

### What Happened

M&A target firms were matching exclusion patterns, and our exemption logic wasn't working correctly.

### The Exclusion Lists

1. **`excluded_firms`** - Pattern-based exclusions (e.g., `%MERRILL%`, `%MORGAN STANLEY%`)
2. **`excluded_firm_crds`** - Specific CRD exclusions (e.g., Savvy's own firm, partner firms)

### The Problem

Our M&A exemption was added to `excluded_firms` but not `excluded_firm_crds`:

```sql
-- We had this:
AND (ef.firm_pattern IS NULL OR ma_check.firm_crd IS NOT NULL)  -- ✅ Pattern exemption

-- But forgot this:
AND ec.firm_crd IS NULL  -- ❌ No M&A exemption for CRD exclusions!
```

### The Fix

```sql
-- Both exclusion types need M&A exemption:
AND (ef.firm_pattern IS NULL OR ma_check.firm_crd IS NOT NULL)  -- Pattern exemption
AND (ec.firm_crd IS NULL OR ma_check.firm_crd IS NOT NULL)      -- CRD exemption
```

### Why This Was Hard to Debug

The `excluded_firm_crds` table is small (2-3 firms), so we didn't think M&A firms would be in it. But during testing, some M&A firms were added to the exclusion list for other reasons.

### Lesson Learned

> **Every filter in a WHERE clause is a potential blocker.**
> 
> When adding exemption logic:
> 1. List ALL filters in the WHERE clause
> 2. Determine which ones need exemptions
> 3. Add exemption to EVERY relevant filter
> 4. Test with a known M&A advisor CRD to verify they pass

### Diagnostic Query

```sql
-- Check if M&A firms are in exclusion lists
SELECT 
    ma.firm_crd,
    ma.firm_name,
    CASE WHEN ef.firm_pattern IS NOT NULL THEN 'IN_EXCLUDED_FIRMS' ELSE 'OK' END as pattern_status,
    CASE WHEN ec.firm_crd IS NOT NULL THEN 'IN_EXCLUDED_CRDS' ELSE 'OK' END as crd_status
FROM `ml_features.active_ma_target_firms` ma
LEFT JOIN excluded_firms ef ON UPPER(ma.firm_name) LIKE ef.firm_pattern
LEFT JOIN excluded_firm_crds ec ON ma.firm_crd = ec.firm_crd
WHERE ef.firm_pattern IS NOT NULL OR ec.firm_crd IS NOT NULL;
```

---

## 8. Problem #6: Silent Failures with No Errors

### What Happened

The query ran successfully every time. No errors, no warnings. Just wrong results.

### The Symptoms

| Indicator | Expected | Actual |
|-----------|----------|--------|
| Query status | Success | ✅ Success |
| Error messages | None | ✅ None |
| Table created | Yes | ✅ Yes |
| Row count | ~2,800 | ✅ 2,800 |
| M&A leads | 150-700 | ❌ 0 |

### Why This Is Dangerous

- **No feedback loop**: Query appears to work perfectly
- **Hard to detect**: Unless you specifically check for M&A leads, you'd never know
- **False confidence**: "The query ran fine" gives false sense of security

### The Root Cause

BigQuery doesn't warn when:
- JOINs return 0 matches (might be intentional)
- CTEs return 0 rows (might be intentional)
- CASE statements fall through to ELSE (might be intentional)

### Lesson Learned

> **"No errors" ≠ "Correct results"**
> 
> For every new feature, create explicit verification queries that:
> 1. Check expected row counts
> 2. Verify new columns have non-NULL values
> 3. Confirm new tiers are populated
> 4. Run BEFORE considering implementation complete

### Mandatory Verification Pattern

```sql
-- After every table creation, run:
SELECT 
    'Total Rows' as check, COUNT(*) as value,
    CASE WHEN COUNT(*) BETWEEN 2500 AND 3500 THEN '✅' ELSE '❌' END as status
FROM `ml_features.january_2026_lead_list`
UNION ALL
SELECT 
    'M&A Leads', COUNTIF(score_tier LIKE 'TIER_MA%'),
    CASE WHEN COUNTIF(score_tier LIKE 'TIER_MA%') > 0 THEN '✅' ELSE '❌' END
FROM `ml_features.january_2026_lead_list`
UNION ALL
SELECT 
    'M&A Fields Not NULL', COUNTIF(is_at_ma_target_firm IS NOT NULL),
    CASE WHEN COUNTIF(is_at_ma_target_firm IS NOT NULL) > 0 THEN '✅' ELSE '❌' END
FROM `ml_features.january_2026_lead_list`;
```

---

## 9. Problem #7: Diagnostic Queries vs Actual Results Mismatch

### What Happened

We wrote diagnostic queries that showed the logic SHOULD work:

```sql
-- Diagnostic: Test JOIN in isolation
SELECT COUNT(*) 
FROM ria_contacts_current c
JOIN active_ma_target_firms ma ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = SAFE_CAST(ma.firm_crd AS INT64)
WHERE ma.ma_status IN ('HOT', 'ACTIVE');
-- Result: 2,225 ✅

-- But actual table:
SELECT COUNTIF(is_at_ma_target_firm = 1) FROM january_2026_lead_list;
-- Result: 0 ❌
```

### The Disconnect

| Diagnostic Query | Result | Conclusion |
|------------------|--------|------------|
| M&A firms exist | 66 firms | ✅ Data present |
| M&A advisors exist | 4,318 | ✅ Data present |
| JOIN works | 2,225 matches | ✅ JOIN logic correct |
| Would pass filters | 2,198 | ✅ Filters work |
| **Actual table** | **0 M&A leads** | ❌ **Something else wrong** |

### Why This Happened

The diagnostic queries tested **individual components** in isolation. But the actual query was a **1,400-line behemoth** where:
- CTEs interacted in unexpected ways
- BigQuery optimizer reordered operations
- Predicates were pushed down unpredictably

### The False Confidence Trap

Each diagnostic query said "this part works" → We concluded "everything works" → But the whole was not equal to the sum of its parts.

### Lesson Learned

> **Isolated component tests don't prove integrated system works.**
> 
> You must test the ACTUAL query output, not simulations of it.

### Better Diagnostic Approach

Instead of testing components, add debug columns to the actual query:

```sql
-- Add to actual query, not separate diagnostic:
SELECT 
    *,
    -- Debug: Did M&A JOIN work?
    CASE WHEN ma.firm_crd IS NOT NULL THEN 'JOIN_WORKED' ELSE 'JOIN_FAILED' END as debug_ma_join,
    -- Debug: What filter excluded this?
    CASE 
        WHEN ef.firm_pattern IS NOT NULL THEN 'EXCLUDED_BY_PATTERN'
        WHEN ec.firm_crd IS NOT NULL THEN 'EXCLUDED_BY_CRD'
        ELSE 'PASSED_FILTERS'
    END as debug_filter_status
FROM base_prospects bp
...
```

Then query the actual output table for debug values.

---

## 10. Problem #8: Complexity Creep

### What Happened

The implementation grew more complex with each "fix":

| Iteration | Lines Added | Complexity |
|-----------|-------------|------------|
| Initial M&A CTE | +30 | Low |
| M&A tier logic | +50 | Medium |
| M&A exemptions | +20 | Medium |
| Debug columns | +40 | High |
| More exemptions | +30 | High |
| Order BY fixes | +20 | High |
| **Total** | **+190 lines** | **Very High** |

### The Problem

Each fix addressed a symptom, adding complexity without solving the root cause. By the end:
- The query was 1,543 lines
- M&A logic was scattered across 8 different CTEs
- Debug columns obscured the actual logic
- No one could understand the full picture

### The Complexity Spiral

```
Problem detected → Add fix → Fix doesn't work → 
Add another fix → Still doesn't work → 
Add debug columns → Can't interpret them → 
Add more fixes → Query becomes unmaintainable → 
Revert everything
```

### Lesson Learned

> **If you've added 3+ fixes and it still doesn't work, STOP.**
> 
> The architecture is wrong. Step back and redesign.

### The 3-Fix Rule

1. **First fix**: Address the obvious issue
2. **Second fix**: Address a secondary issue
3. **Third fix**: If still broken, STOP and reconsider architecture

After 3 fixes, you're likely treating symptoms, not the disease.

---

## 11. Problem #9: Inadequate Pre-Implementation Testing

### What Happened

We jumped straight into implementation without verifying prerequisites:

| Should Have Tested | When | Did We? |
|--------------------|------|---------|
| Data types match | Before writing JOINs | ❌ No |
| M&A table has data | Before implementation | ⚠️ Partially |
| JOIN works in context | Before embedding in query | ❌ No |
| All CTEs accessible | Before running full query | ❌ No |
| Exclusion conflicts | Before adding exemptions | ❌ No |

### The Cost

~8 hours of debugging that could have been avoided with ~30 minutes of pre-implementation testing.

### What Pre-Implementation Testing Should Look Like

```sql
-- TEST 1: Data exists
SELECT COUNT(*) FROM active_ma_target_firms WHERE ma_status IN ('HOT', 'ACTIVE');
-- Must be > 0

-- TEST 2: Data types
SELECT 
    (SELECT data_type FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'active_ma_target_firms' AND column_name = 'firm_crd') as ma_type,
    (SELECT data_type FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'ria_contacts_current' AND column_name = 'PRIMARY_FIRM') as contact_type;
-- Must be compatible

-- TEST 3: JOIN works
SELECT COUNT(*) 
FROM ria_contacts_current c
JOIN active_ma_target_firms ma ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = SAFE_CAST(ma.firm_crd AS INT64);
-- Must be > 0

-- TEST 4: No exclusion conflicts
SELECT COUNT(*) 
FROM active_ma_target_firms ma
JOIN excluded_firms ef ON UPPER(ma.firm_name) LIKE ef.firm_pattern;
-- Note how many need exemptions

-- TEST 5: Tier logic preview
SELECT 
    CASE WHEN UPPER(c.TITLE_NAME) LIKE '%PRESIDENT%' THEN 'PRIME' ELSE 'STANDARD' END as tier,
    COUNT(*)
FROM ria_contacts_current c
JOIN active_ma_target_firms ma ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = SAFE_CAST(ma.firm_crd AS INT64)
GROUP BY 1;
-- Must show both tiers
```

### Lesson Learned

> **30 minutes of testing saves 8 hours of debugging.**
> 
> Create a standard pre-implementation test suite and run it EVERY time.

---

## 12. Problem #10: Debug Column Overload

### What Happened

We added debug columns to track where M&A advisors were being lost:

```sql
-- Debug columns added:
debug_base_prospects_filter_status
debug_excluded_firm_pattern
debug_ma_check_firm_crd
debug_ma_join_worked
debug_ma_firm_crd
debug_ma_status_at_ep
debug_bp_firm_crd
debug_ma_flag_at_v4
debug_ma_status_at_v4
debug_ma_flag_at_ranked
debug_ma_status_at_ranked
debug_ma_category_at_ranked
debug_ma_flag_at_diversity
debug_ma_diversity_status
-- ... and more
```

### The Problem

- **Too many columns**: 15+ debug columns made output unreadable
- **All showed the same thing**: Every debug column was 0 or NULL
- **No additional insight**: If the JOIN failed early, all downstream debug columns are useless
- **Obscured the logic**: Actual business logic buried under debug noise

### What Debug Columns Told Us

| Debug Column | Value | Insight |
|--------------|-------|---------|
| debug_ma_check_firm_crd | NULL (all rows) | JOIN failed in base_prospects |
| debug_ma_join_worked | 0 (all rows) | Confirms JOIN failed |
| debug_ma_flag_at_v4 | 0 (all rows) | No insight (downstream of failure) |
| debug_ma_flag_at_ranked | 0 (all rows) | No insight (downstream of failure) |

Once we knew the JOIN failed in `base_prospects`, 80% of debug columns were redundant.

### Better Debug Strategy

**Staged debugging** - one debug point at a time:

```sql
-- STAGE 1: Debug only base_prospects
-- Add debug columns only to base_prospects
-- Run query, check results
-- If 0 M&A advisors, stop here and fix

-- STAGE 2: Debug enriched_prospects (only if Stage 1 passes)
-- Add debug columns to enriched_prospects
-- Run query, check results

-- STAGE 3: Debug scored_prospects (only if Stage 2 passes)
-- ... and so on
```

### Lesson Learned

> **Debug one stage at a time, not the entire pipeline.**
> 
> If early stages fail, debugging later stages is pointless.

### Debug Column Best Practices

1. **Maximum 3-5 debug columns per debugging session**
2. **Remove debug columns once issue is found**
3. **Stage debugging: early CTEs first, later CTEs only if needed**
4. **Use meaningful names**: `debug_ma_join_base_prospects` not `debug_bp_firm_crd`

---

## 13. Problem #11: EXISTS Subquery False Confidence

### What Happened

After CTE JOINs failed, we tried using EXISTS subqueries in WHERE clauses:

```sql
-- Attempted fix: Use EXISTS instead of JOIN
AND (
    ef.firm_pattern IS NULL 
    OR EXISTS (
        SELECT 1 FROM ma_target_firms ma_exempt
        WHERE ma_exempt.firm_crd = SAFE_CAST(c.PRIMARY_FIRM AS INT64)
    )
)
```

### The Test Results

| Test | Result |
|------|--------|
| EXISTS works in isolation | ✅ 2,225 matches |
| EXISTS syntax is correct | ✅ Valid SQL |
| EXISTS in full query | ❌ Still 0 matches |

### Why It Didn't Work

Even though EXISTS worked perfectly in isolation, when embedded in the 1,400-line query:
- BigQuery optimizer may have pushed predicates down before EXISTS evaluation
- EXISTS subquery may have been evaluated in unexpected order
- The CTE reference within EXISTS may have had the same scoping issues

### The Pattern

```
CTE JOIN → 0 matches (but works in isolation)
↓
Try inline subquery → 0 matches (but works in isolation)
↓
Try EXISTS subquery → 0 matches (but works in isolation)
↓
Conclusion: The problem isn't the syntax, it's the query complexity
```

### Lesson Learned

> **If multiple syntax approaches all work in isolation but fail in the full query, the problem is architectural, not syntactic.**
> 
> Stop trying new syntax. Redesign the architecture.

### When to Stop Trying Syntax Fixes

After 3 different syntax approaches fail:
1. ✅ First approach (CTE JOIN)
2. ✅ Second approach (inline subquery)
3. ✅ Third approach (EXISTS)
4. ❌ **STOP** - Architecture is the problem

---

## 14. Problem #12: Not Checking BigQuery Execution Logs Early

### What Happened

We spent ~7 hours debugging before checking BigQuery execution logs for warnings or optimization hints.

### What We Should Have Checked

BigQuery execution logs can reveal:
- Query optimization warnings
- Predicate pushdown decisions
- JOIN reordering
- CTE evaluation order
- Performance bottlenecks that might indicate logic issues

### How to Check Execution Logs

**Via BigQuery Console:**
1. Go to BigQuery Console → Job History
2. Find the table creation job
3. Click "View Details"
4. Check "Execution Details" tab for warnings

**Via CLI:**
```bash
bq show -j PROJECT_ID:REGION.JOB_ID
```

**Via MCP (if available):**
```python
# Check job details for warnings
job = client.get_job(job_id)
if job.errors:
    print("Errors:", job.errors)
if job.statistics.query:
    print("Query stats:", job.statistics.query)
```

### Why We Didn't Check Earlier

- Assumed "no errors" meant "no issues"
- Focused on SQL syntax, not execution behavior
- Didn't realize BigQuery optimizer could silently change behavior

### Lesson Learned

> **Check execution logs FIRST, not last.**
> 
> BigQuery execution logs can reveal optimization decisions that explain why logic works in isolation but fails in production.

### Execution Log Checklist

- [ ] Check for warnings (not just errors)
- [ ] Review query plan for unexpected reordering
- [ ] Look for predicate pushdown that might filter too early
- [ ] Check for JOIN reordering that might affect results
- [ ] Verify CTE evaluation order matches expectations

---

## 15. Problem #13: The "Works in Isolation" Trap

### What Happened

Every diagnostic query we wrote worked perfectly:

```sql
-- Test 1: JOIN works
SELECT COUNT(*) FROM contacts c
JOIN ma_target_firms ma ON c.firm_crd = ma.firm_crd;
-- Result: 2,225 ✅

-- Test 2: EXISTS works
SELECT COUNT(*) FROM contacts c
WHERE EXISTS (SELECT 1 FROM ma_target_firms ma WHERE ma.firm_crd = c.firm_crd);
-- Result: 2,225 ✅

-- Test 3: WHERE clause works
SELECT COUNT(*) FROM contacts c
JOIN ma_target_firms ma ON c.firm_crd = ma.firm_crd
WHERE c.producing_advisor = TRUE;
-- Result: 2,198 ✅

-- But actual query:
SELECT COUNT(*) FROM january_2026_lead_list WHERE is_at_ma_target_firm = 1;
-- Result: 0 ❌
```

### The False Confidence

Each passing test gave us confidence: "The logic is correct, we just need to find the right place to apply it."

### Why Isolation Tests Don't Prove Integration

| Factor | Isolation Test | Full Query |
|--------|----------------|------------|
| Query complexity | Simple (1-2 CTEs) | Complex (15+ CTEs) |
| Optimizer behavior | Predictable | Unpredictable |
| Predicate pushdown | None | Aggressive |
| JOIN reordering | None | Possible |
| CTE evaluation | Sequential | May be parallel |

### The Real Test

The ONLY test that matters:
```sql
-- This is the ONLY test that counts:
SELECT COUNTIF(is_at_ma_target_firm = 1) 
FROM `ml_features.january_2026_lead_list`;
-- Must be > 0
```

### Lesson Learned

> **Isolation tests prove syntax works, not that integration works.**
> 
> The only test that matters is the actual output table.

### Better Testing Strategy

1. **Write isolation tests** to verify syntax (quick sanity check)
2. **Run the actual query** to verify integration (the real test)
3. **If isolation passes but integration fails** → Architecture problem, not syntax problem

---

## 16. Problem #14: Not Knowing When to Stop

### What Happened

We spent ~8 hours debugging:
- Hour 1-2: Initial fixes (data types, JOINs)
- Hour 3-4: More fixes (exemptions, ORDER BY)
- Hour 5-6: Debug columns, diagnostic queries
- Hour 7-8: More syntax attempts (EXISTS, inline subqueries)

### The 3-Fix Rule (We Violated It)

We should have stopped after 3 fixes didn't work:
1. ✅ Fix 1: Data type casting
2. ✅ Fix 2: FULL OUTER JOIN
3. ✅ Fix 3: M&A exemptions
4. ❌ **Should have stopped here**
5. ❌ Fix 4: More exemptions (waste of time)
6. ❌ Fix 5: Debug columns (waste of time)
7. ❌ Fix 6: EXISTS subqueries (waste of time)

### When to Stop Debugging

**Stop immediately if:**
- 3+ fixes applied with no improvement
- Diagnostic queries work but actual output doesn't
- Debug columns all show 0 or NULL
- Multiple syntax approaches all fail in full query

**What to do instead:**
1. **Document what you tried** (for future reference)
2. **Revert to last working state** (clean slate)
3. **Redesign architecture** (simpler approach)
4. **Get fresh perspective** (different person, different day)

### The Cost of Continuing

| Time Spent | Value Added |
|------------|-------------|
| Hours 1-3 | High (found real issues) |
| Hours 4-6 | Medium (found some issues) |
| Hours 7-8 | Low (diminishing returns) |
| **Total** | **Should have stopped at hour 3** |

### Lesson Learned

> **Know when to stop.**
> 
> After 3 fixes with no improvement, you're treating symptoms, not the disease. Step back and redesign.

### Stop Criteria Checklist

- [ ] Applied 3+ fixes with no improvement? → **STOP**
- [ ] Diagnostic queries work but output doesn't? → **STOP**
- [ ] Multiple syntax approaches all fail? → **STOP**
- [ ] Debug columns all show 0/NULL? → **STOP**
- [ ] Query complexity >1,000 lines? → **Consider STOP**

---

## 17. Problem #15: The Value of Clean Reverts

### What Happened

After 8 hours of debugging, we reverted to commit `4e5aa0f` (before M&A implementation) and cleaned up all debugging files.

### Why This Was the Right Decision

1. **Clean slate**: Removed all failed attempts and debugging noise
2. **Version control**: Git history preserved for future reference
3. **Mental reset**: Fresh start without baggage of failed attempts
4. **Time saved**: Stopped wasting time on unfixable architecture

### What We Preserved

- ✅ All lessons learned (this document)
- ✅ Empirical analysis (M&A signal is real)
- ✅ Implementation guide (for future attempt)
- ✅ Git history (can see what was tried)

### What We Removed

- ❌ Failed SQL implementations
- ❌ 75+ debugging markdown files
- ❌ Debug columns in SQL
- ❌ Broken CTE logic

### The Revert Process

```bash
# 1. Revert to last working commit
git reset --hard 4e5aa0f

# 2. Clean up untracked debugging files
git clean -f

# 3. Force push to update remote
git push --force-with-lease
```

### Lesson Learned

> **Reverting isn't failure—it's strategic.**
> 
> Sometimes the best fix is to start over with a better architecture.

### When to Revert

**Revert if:**
- 3+ fixes applied with no improvement
- Architecture is fundamentally flawed (CTE scoping issues)
- Time spent > value of continuing
- Clean slate would enable better approach

**Don't revert if:**
- One or two small fixes needed
- Architecture is sound, just needs tweaks
- Close to solution

---

## 18. Root Cause Analysis Summary

### The Actual Root Cause

**BigQuery CTE scoping/evaluation issues caused JOINs referencing CTEs to return 0 matches**, despite the CTEs being correctly defined and containing data.

### Why It Took So Long to Identify

| Reason | Impact |
|--------|--------|
| CTEs worked in isolation | False confidence |
| Diagnostic queries showed data exists | Misleading signals |
| No errors or warnings | No feedback |
| Multiple potential causes | Chased red herrings |
| Complexity of 1,400-line query | Hard to isolate issue |
| Incremental fixes added noise | Root cause buried deeper |

### Contributing Factors (Not Root Cause)

These issues were real but wouldn't have mattered if CTE scoping worked:

| Factor | Impact | Would've Blocked? |
|--------|--------|-------------------|
| Data type mismatch | Medium | Possibly (some advisors) |
| 200-rep cap | High | Yes (94% of advisors) |
| Missing ORDER BY tiers | Medium | Yes (wrong prioritization) |
| Exclusion conflicts | Low | Some advisors |

### If We Had Used Pre-Built Tables

None of these issues would have occurred:
- No CTE scoping problems
- Data types verified at table creation
- Exclusions handled in pre-build
- Simple LEFT JOIN = reliable behavior

---

## 19. What We Should Have Done Differently

### Strategy Level

| What We Did | What We Should Have Done |
|-------------|--------------------------|
| Complex CTEs in monolithic query | Pre-built M&A table + simple JOIN |
| All-at-once implementation | Incremental, verified stages |
| Debug entire pipeline | Debug one stage at a time |
| Multiple quick fixes | Stop after 3 fixes, reconsider |
| Assumed CTE behavior | Tested CTE behavior first |

### Tactical Level

| What We Did | What We Should Have Done |
|-------------|--------------------------|
| Skipped pre-implementation tests | Run full test suite first |
| Used CTE references | Used direct table references |
| Added 200-rep cap "for safety" | Calculated impact of cap first |
| Added 15+ debug columns | Added 3-5 staged debug columns |
| Kept adding code | Simplified when complexity grew |

### Time Allocation

| Activity | Time Spent | Optimal Time |
|----------|------------|--------------|
| Pre-implementation testing | ~10 min | ~45 min |
| Initial implementation | ~30 min | ~60 min |
| Debugging | ~7 hours | ~30 min (if pre-tested) |
| Post-implementation verification | ~20 min | ~30 min |
| **Total** | **~8 hours** | **~2.5 hours** |

---

## 20. Checklist for Future Implementations

### Pre-Implementation (REQUIRED - 30-45 minutes)

- [ ] **Data Existence**: Source tables have expected row counts
- [ ] **Data Types**: All JOIN columns have compatible types
- [ ] **JOIN Test**: JOIN logic returns expected matches in isolation
- [ ] **Exclusion Check**: Identify conflicts with existing exclusion lists
- [ ] **Tier Logic Preview**: New tier CASE logic returns expected distribution
- [ ] **Quota Calculation**: New tier quotas won't exclude >50% of target population

### Implementation (60-90 minutes)

- [ ] **Architecture Decision**: Pre-built table or CTE? (Prefer pre-built)
- [ ] **Incremental Approach**: Build and verify one stage at a time
- [ ] **ORDER BY Audit**: Search for ALL `WHEN.*TIER_.*THEN` and add new tier
- [ ] **Exemption Audit**: List ALL WHERE filters and add exemptions where needed
- [ ] **3-Fix Rule**: If 3 fixes don't work, STOP and reconsider architecture

### Post-Implementation (REQUIRED - 30 minutes)

- [ ] **Row Count Check**: Total leads within expected range
- [ ] **New Tier Population**: New tiers have >0 leads
- [ ] **New Fields Not NULL**: New columns have non-NULL values
- [ ] **No Violations**: Large firm exclusion (or other rules) working correctly
- [ ] **Spot Check**: Manual review of 10-20 new tier leads

### Red Flags - STOP and Reconsider

- [ ] Query is >1,000 lines
- [ ] New feature requires changes in >5 CTEs
- [ ] Debug columns all show 0 or NULL
- [ ] Diagnostic queries work but actual output doesn't
- [ ] You've applied 3+ fixes with no improvement

---

## 21. Appendix: Failed Code Examples

### Failed Code Example 1: CTE Reference

```sql
-- ❌ FAILED: CTE reference that returned 0 matches
ma_target_firms AS (
    SELECT 
        firm_crd,
        ma_status,
        days_since_first_news
    FROM `savvy-gtm-analytics.ml_features.active_ma_target_firms`
    WHERE ma_status IN ('HOT', 'ACTIVE')
),

base_prospects AS (
    SELECT ...
    FROM ria_contacts_current c
    LEFT JOIN ma_target_firms ma_check 
        ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ma_check.firm_crd  -- ❌ 0 matches
    ...
)
```

### Working Alternative: Inline Subquery

```sql
-- ✅ WORKS: Inline subquery (but adds complexity)
base_prospects AS (
    SELECT ...
    FROM ria_contacts_current c
    LEFT JOIN (
        SELECT SAFE_CAST(firm_crd AS INT64) as firm_crd
        FROM `savvy-gtm-analytics.ml_features.active_ma_target_firms`
        WHERE ma_status IN ('HOT', 'ACTIVE')
    ) ma_check ON SAFE_CAST(c.PRIMARY_FIRM AS INT64) = ma_check.firm_crd
    ...
)
```

### Best Alternative: Pre-Built Table

```sql
-- ✅ BEST: Pre-built table reference
base_prospects AS (
    SELECT ...
    FROM ria_contacts_current c
    LEFT JOIN `ml_features.ma_eligible_advisors` ma 
        ON c.RIA_CONTACT_CRD_ID = ma.crd  -- Simple, reliable
    ...
)
```

### Failed Code Example 2: Overly Restrictive Cap

```sql
-- ❌ FAILED: 200-rep cap excluded 94% of M&A advisors
AND (
    df.firm_rep_count <= 50
    OR (df.score_tier LIKE 'TIER_MA%' AND df.firm_rep_count <= 200)  -- ❌ Too restrictive
)

-- ✅ FIXED: No cap on M&A exemption
AND (
    df.firm_rep_count <= 50
    OR df.score_tier LIKE 'TIER_MA%'  -- ✅ All M&A advisors included
)
```

### Failed Code Example 3: Missing ORDER BY Tier

```sql
-- ❌ FAILED: M&A tiers missing from ORDER BY
CASE final_tier
    WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 1
    WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 2
    -- ... Career Clock tiers missing ...
    -- ... M&A tiers missing ...
    WHEN 'STANDARD_HIGH_V4' THEN 10
END

-- ✅ FIXED: All tiers included
CASE final_tier
    WHEN 'TIER_0A_PRIME_MOVER_DUE' THEN 1
    WHEN 'TIER_0B_SMALL_FIRM_DUE' THEN 2
    WHEN 'TIER_0C_CLOCKWORK_DUE' THEN 3
    WHEN 'TIER_MA_ACTIVE_PRIME' THEN 4
    WHEN 'TIER_MA_ACTIVE' THEN 5
    WHEN 'TIER_1B_PRIME_ZERO_FRICTION' THEN 6
    -- ... all tiers ...
END
```

### Failed Code Example 4: Incomplete Exemptions

```sql
-- ❌ FAILED: Only one exclusion had M&A exemption
AND (ef.firm_pattern IS NULL OR ma_check.firm_crd IS NOT NULL)  -- ✅ Pattern exemption
AND ec.firm_crd IS NULL  -- ❌ No CRD exemption!

-- ✅ FIXED: Both exclusions have M&A exemption
AND (ef.firm_pattern IS NULL OR ma_check.firm_crd IS NOT NULL)  -- Pattern exemption
AND (ec.firm_crd IS NULL OR ma_check.firm_crd IS NOT NULL)      -- CRD exemption
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-02 | Lead Scoring Team | Initial post-mortem |
| 1.1 | 2026-01-02 | Lead Scoring Team | Added Problems #11-15: EXISTS subqueries, execution logs, isolation trap, when to stop, clean reverts. Fixed section numbering (13-21), updated Table of Contents, removed duplicate Root Cause section, added cross-reference to Implementation Guide in Executive Summary |

---

## Final Thoughts

The V3.5.0 M&A tier implementation failed not because the business logic was wrong or the data wasn't there. It failed because:

1. **We chose a complex architecture** (CTEs) when a simple one (pre-built table) would have been more reliable
2. **We didn't test prerequisites** before diving into implementation
3. **We kept adding fixes** instead of stepping back when they didn't work
4. **We trusted "no errors" as "success"** without verifying actual output

The M&A signal is real and valuable. The implementation just needs a simpler architecture. Use the companion document **V3.5.0_MA_TIER_COMPREHENSIVE_IMPLEMENTATION_GUIDE.md** for the correct approach.

---

**End of Document**
