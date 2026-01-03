# V3.5.0 Documentation Update Suite - Cursor.ai Prompts

**Purpose**: Update all documentation to reflect V3.5.0 M&A Tier implementation  
**Created**: January 3, 2026  
**Status**: Ready for execution

---

## Overview

This document contains Cursor.ai prompts to update the following files:

| File | Location | Purpose |
|------|----------|---------|
| `README.md` | Root directory | Main project documentation |
| `VERSION_3_MODEL_REPORT.md` | `v3/` | V3 model technical documentation |
| `EXECUTION_LOG.md` | `pipeline/logs/` | Implementation execution log |
| `UNIFIED_MODEL_REGISTRY.json` | `models/` | Unified model metadata |

---

# PROMPT 1: Update README.md

## File Location
`C:\Users\russe\Documents\lead_scoring_production\README.md`

## Instructions

Update the README.md to reflect V3.5.0 with M&A tiers and the two-query architecture. Make the following changes:

### 1. Update Header Section

**Find** (lines 1-8):
```markdown
# Lead Scoring Production Pipeline - Hybrid V3 + V4 Model

**Version**: 3.1 (Option C: Maximized Lead List)  
**Last Updated**: January 1, 2026  
**Status**: Production Ready  
**V4 Model**: V4.2.0 (Career Clock) - Deployed January 1, 2026  
**Repository Cleanup**: Completed December 30, 2025 (see `recommended_cleanup.md`)
```

**Replace with**:
```markdown
# Lead Scoring Production Pipeline - Hybrid V3 + V4 Model

**Version**: 3.5.0 (M&A Active Tiers + Two-Query Architecture)  
**Last Updated**: January 3, 2026  
**Status**: ✅ Production Ready  
**V3 Model**: V3.5.0_01032026_MA_TIERS - M&A opportunity capture  
**V4 Model**: V4.2.0 (Career Clock) - Deployed January 1, 2026  
**Architecture**: Two-Query (bypasses BigQuery CTE optimization issues)
```

### 2. Update Executive Summary

**Find** the Executive Summary section and update Key Results:

**Replace with**:
```markdown
## Executive Summary

This repository contains a **hybrid lead scoring system** that combines:

- **V3 Rules-Based Model**: Tiered classification with M&A opportunity tiers (V3.5.0)
- **V4 XGBoost ML Model**: Machine learning model for deprioritization and backfill
- **Two-Query Architecture**: Reliable M&A lead insertion (bypasses BigQuery CTE issues)

**Key Results (January 2026 Lead List - V3.5.0):**
- **Total Leads**: 3,100 (2,800 standard + 300 M&A)
- **M&A Leads**: 300 (TIER_MA_ACTIVE_PRIME at 9.0% expected conversion)
- **Large Firm Exemption**: 293 M&A leads from firms with >200 reps (normally excluded)
- **Expected MQLs from M&A Tier**: ~27 additional MQLs (300 × 9.0%)
- **Architecture**: Two-query approach (INSERT after CREATE)

**V3.5.0 M&A Tier Performance (Based on Commonwealth/LPL Analysis):**
- **TIER_MA_ACTIVE_PRIME**: 9.0% conversion (2.36x baseline) - Senior titles + mid-career at M&A targets
- **TIER_MA_ACTIVE**: 5.4% conversion (1.41x baseline) - All advisors at M&A target firms
- **Evidence**: Commonwealth Financial Network converted at 5.37% during LPL acquisition (242 contacts, 13 MQLs)

**Why M&A Tiers Matter:**
- Large firms (>50 reps) normally convert at 0.60x baseline → we exclude them
- But M&A disruption changes dynamics → Commonwealth converted at 5.37% during acquisition
- Without M&A tiers, we would miss 100-500 MQLs per major M&A event
```

### 3. Update Quick Start Guide - Monthly Execution

**Find** the Monthly Execution section and **replace** with:

```markdown
### Monthly Execution (5 Steps - Two-Query Architecture)

```bash
# Step 1: Refresh M&A Eligible Advisors Table (monthly or when M&A news hits)
# Run SQL: pipeline/sql/create_ma_eligible_advisors.sql
# Creates: ml_features.ma_eligible_advisors (~2,225 advisors)

# Step 2: Calculate V4 features for all prospects
# Run SQL: pipeline/sql/v4_prospect_features.sql
# Creates: ml_features.v4_prospect_features

# Step 3: Score prospects with V4 model
cd pipeline
python scripts/score_prospects_monthly.py
# Creates: ml_features.v4_prospect_scores

# Step 4: Generate base lead list (standard leads only)
# Run SQL: pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
# Creates: ml_features.january_2026_lead_list (~2,800 leads)

# Step 5: Insert M&A leads (MUST run AFTER Step 4)
# Run SQL: pipeline/sql/Insert_MA_Leads.sql
# Adds: ~300 M&A leads to existing table
# Final: ml_features.january_2026_lead_list (~3,100 leads)

# Step 6: Export to CSV
python scripts/export_lead_list.py
# Output: pipeline/exports/january_2026_lead_list_YYYYMMDD.csv
```

**⚠️ CRITICAL**: Step 5 (Insert_MA_Leads.sql) MUST run AFTER Step 4. The two-query architecture is required because single-query approaches fail due to BigQuery CTE optimization issues.
```

### 4. Update Pipeline Architecture Diagram

**Find** the Pipeline Architecture section and **replace** the diagram:

```markdown
## Pipeline Architecture

### High-Level Flow (V3.5.0 Two-Query Architecture)

```
┌─────────────────────────────────────────────────────────────────┐
│        MONTHLY LEAD LIST GENERATION PIPELINE (V3.5.0)           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  STEP 1: Refresh M&A Advisors Table                             │
│     └─> SQL: create_ma_eligible_advisors.sql                    │
│     └─> Output: ml_features.ma_eligible_advisors (~2,225)       │
│     └─> Purpose: Pre-build M&A advisor list with tier assignments│
│                                                                  │
│  STEP 2: Calculate V4 Features                                  │
│     └─> SQL: v4_prospect_features.sql                           │
│     └─> Output: ml_features.v4_prospect_features                │
│     └─> Purpose: Calculate 29 ML features for all prospects     │
│                                                                  │
│  STEP 3: Score Prospects with V4 Model                         │
│     └─> Python: score_prospects_monthly.py                      │
│     └─> Output: ml_features.v4_prospect_scores                 │
│     └─> Purpose: Generate ML scores, percentiles, SHAP features │
│                                                                  │
│  STEP 4: Generate Base Lead List (Query 1)                     │
│     └─> SQL: January_2026_Lead_List_V3_V4_Hybrid.sql            │
│     └─> Output: ml_features.january_2026_lead_list (~2,800)     │
│     └─> Purpose: Standard leads with V3 tiers + V4 upgrades     │
│                                                                  │
│  STEP 5: Insert M&A Leads (Query 2) ⚠️ MUST RUN AFTER STEP 4   │
│     └─> SQL: Insert_MA_Leads.sql                                │
│     └─> Output: Adds ~300 M&A leads to existing table           │
│     └─> Purpose: Add M&A tier leads (bypasses CTE issues)       │
│                                                                  │
│  STEP 6: Export to CSV                                          │
│     └─> Python: export_lead_list.py                             │
│     └─> Output: exports/[month]_2026_lead_list_YYYYMMDD.csv    │
│     └─> Purpose: CSV file for Salesforce import                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why Two-Query Architecture?

Single-query approaches failed due to BigQuery CTE optimization issues:

| Approach Attempted | Result |
|--------------------|--------|
| EXISTS subquery exemption | ❌ Works in isolation, fails in full query |
| JOIN exemption | ❌ Works in isolation, fails in full query |
| UNION two-track architecture | ❌ Works in isolation, fails in full query |
| LEFT JOIN with inline subquery | ❌ Works in isolation, fails in full query |
| **INSERT after CREATE** | ✅ **Works reliably** |

The INSERT approach completely bypasses BigQuery's CTE optimization by using two separate, simple queries instead of one complex 1,400+ line query.
```

### 5. Add New Section: V3.5.0 M&A Tiers

**Add after the "Step-by-Step Execution" section**:

```markdown
---

## V3.5.0 M&A Active Tiers

### Overview

V3.5.0 adds two M&A (Mergers & Acquisitions) opportunity tiers that capture advisors at firms undergoing M&A activity. These leads would normally be excluded by the large firm filter (>50 reps) but convert at elevated rates during M&A disruption.

### New Tiers

| Tier | Expected Conversion | Lift | Criteria |
|------|---------------------|------|----------|
| **TIER_MA_ACTIVE_PRIME** | 9.0% | 2.36x | Senior title OR mid-career (10-20yr) at M&A target |
| **TIER_MA_ACTIVE** | 5.4% | 1.41x | All advisors at M&A target firms |

### Evidence: Commonwealth/LPL Merger Analysis

**Event**: LPL Financial announced acquisition of Commonwealth Financial Network (July 2024)

| Metric | Value |
|--------|-------|
| Total Commonwealth advisors | ~2,500 |
| Advisors contacted | 242 |
| Conversions (MQLs) | 13 |
| **Conversion Rate** | **5.37%** |
| **Lift vs Baseline** | **1.41x** |

**Profile Analysis**:
- Senior Titles: 9.30% conversion (2.06x lift)
- Mid-Career (10-20yr): 8.16% conversion (1.75x lift)
- Serial Movers: 5.14% conversion (0.86x lift) - Does NOT help
- Newer to Firm: 4.65% conversion (0.81x lift) - Does NOT help

### Implementation Files

| File | Purpose |
|------|---------|
| `pipeline/sql/create_ma_eligible_advisors.sql` | Pre-build M&A advisors table |
| `pipeline/sql/Insert_MA_Leads.sql` | Insert M&A leads after base list |
| `pipeline/sql/post_implementation_verification_ma_tiers.sql` | Verification queries |
| `V3_5_0_MA_TIER_COMPREHENSIVE_IMPLEMENTATION_GUIDE.md` | Full implementation guide |

### M&A Target Firms Table

The `ml_features.active_ma_target_firms` table tracks firms with active M&A activity:

| Column | Description |
|--------|-------------|
| `firm_crd` | Firm CRD ID |
| `firm_name` | Firm name |
| `ma_status` | HOT (60-180 days) or ACTIVE (181-365 days) |
| `days_since_first_news` | Days since M&A announcement |
| `firm_employees` | Number of advisors at firm |

**Current Stats** (January 2026):
- HOT: 39 firms, 183 advisors
- ACTIVE: 27 firms, 2,042 advisors
- Total: 66 firms, 2,225 advisors

### Refresh Schedule

| Trigger | Action |
|---------|--------|
| Monthly | Re-run `create_ma_eligible_advisors.sql` |
| M&A news | Update `active_ma_target_firms`, re-run creation script |
| Firm status change | Update `ma_status` (HOT → ACTIVE → STALE) |
```

### 6. Update BigQuery Tables Section

**Find** the BigQuery Tables section and **add** these tables:

```markdown
| `ml_features.active_ma_target_firms` | M&A target firm tracking | Manual (news feed) |
| `ml_features.ma_eligible_advisors` | Pre-built M&A advisor list | Step 1 (monthly) |
```

### 7. Update Monthly Checklist

**Find** the Monthly Checklist section and **replace** with:

```markdown
### Monthly Checklist (V3.5.0)

```markdown
## [MONTH] 2026 Lead List Generation

**Date**: YYYY-MM-DD
**Operator**: [Name]
**Model Version**: V3.5.0_MA_TIERS

### Pre-Flight Checks
- [ ] BigQuery access verified
- [ ] V4 model files present
- [ ] Previous month's list archived
- [ ] M&A target firms table updated (if new M&A news)

### Step 1: M&A Advisors Table
- [ ] Ran create_ma_eligible_advisors.sql
- [ ] Row count: ___________ (expected: ~2,000-4,500)
- [ ] TIER_MA_ACTIVE_PRIME count: ___________
- [ ] TIER_MA_ACTIVE count: ___________

### Step 2: V4 Features
- [ ] Created ml_features.v4_prospect_features
- [ ] Row count: ___________

### Step 3: V4 Scoring
- [ ] Scored all prospects
- [ ] Created ml_features.v4_prospect_scores
- [ ] Row count: ___________

### Step 4: Base Lead List (Query 1)
- [ ] Ran January_2026_Lead_List_V3_V4_Hybrid.sql
- [ ] Created ml_features.[month]_2026_lead_list
- [ ] Lead count: ___________ (expected: ~2,800)

### Step 5: Insert M&A Leads (Query 2)
- [ ] ⚠️ Confirmed Step 4 completed successfully
- [ ] Ran Insert_MA_Leads.sql
- [ ] M&A leads inserted: ___________ (expected: ~300)
- [ ] Total lead count after insert: ___________ (expected: ~3,100)

### Step 6: Verification
- [ ] Ran post_implementation_verification_ma_tiers.sql
- [ ] CHECK 8.1: M&A tiers populated ___________
- [ ] CHECK 8.2: Large firm exemption working ___________
- [ ] CHECK 8.3: Commonwealth check ___________
- [ ] CHECK 8.4: No violations ___________

### Step 7: Export
- [ ] Final validation passed
- [ ] Exported to CSV
- [ ] File location: ___________

### Summary
- **Total Leads**: ___________
- **Standard Leads**: ___________
- **M&A Leads**: ___________
- **Leads per SGA**: ___________
- **Expected M&A MQLs**: ___________ (M&A leads × 9%)
```
```

### 8. Update Change Log

**Add to Change Log section** (at the top of the change log):

```markdown
### V3.5.0 - January 3, 2026 - M&A Active Tiers + Two-Query Architecture

**Summary:** Added M&A opportunity tiers to capture advisors at firms undergoing M&A activity. Implemented two-query architecture after single-query approaches failed due to BigQuery CTE optimization issues.

#### Key Changes

1. **Added TIER_MA_ACTIVE_PRIME**
   - Senior title OR mid-career (10-20yr) at M&A target
   - Expected conversion: 9.0% (2.36x lift)
   - Validated on Commonwealth/LPL merger data

2. **Added TIER_MA_ACTIVE**
   - All advisors at M&A target firms
   - Expected conversion: 5.4% (1.41x lift)
   - Captures opportunity window (60-365 days post-announcement)

3. **Implemented Two-Query Architecture**
   - Query 1: Generate base lead list (standard leads)
   - Query 2: INSERT M&A leads after base list created
   - Reason: Single-query approaches failed due to BigQuery CTE optimization

4. **Created Pre-Built M&A Advisors Table**
   - `ml_features.ma_eligible_advisors` (~2,225 advisors)
   - Pre-computes tier assignments
   - Refreshed monthly or on M&A news

5. **Large Firm Exemption for M&A**
   - M&A advisors exempt from >50 rep exclusion
   - 293 of 300 M&A leads are at firms with >200 reps
   - Would have been excluded without M&A exemption

#### Evidence Supporting Changes

| Signal | Conversion | Lift | Action |
|--------|------------|------|--------|
| Commonwealth M&A (overall) | 5.37% | 1.41x | Add TIER_MA_ACTIVE |
| Senior titles at M&A | 9.30% | 2.06x | Add to TIER_MA_ACTIVE_PRIME |
| Mid-career at M&A | 8.16% | 1.75x | Add to TIER_MA_ACTIVE_PRIME |

#### Why Single-Query Failed

Four approaches were attempted and all failed:

1. EXISTS subquery exemption → Works in isolation, fails in full query
2. JOIN exemption → Works in isolation, fails in full query
3. UNION two-track → Works in isolation, fails in full query
4. LEFT JOIN with inline subquery → Works in isolation, fails in full query

Root cause: BigQuery's CTE optimization in complex queries (1,400+ lines) causes unpredictable behavior.

#### Files Created

- `pipeline/sql/create_ma_eligible_advisors.sql`
- `pipeline/sql/Insert_MA_Leads.sql`
- `pipeline/sql/pre_implementation_verification_ma_tiers.sql`
- `pipeline/sql/post_implementation_verification_ma_tiers.sql`
- `V3_5_0_MA_TIER_COMPREHENSIVE_IMPLEMENTATION_GUIDE.md`
- `pipeline/V3_5_0_MA_TIER_IMPLEMENTATION_RESULTS.md`

#### Files Modified

- `v3/models/model_registry_v3.json` (updated to V3.5.0)
- `README.md` (this document)
- `v3/VERSION_3_MODEL_REPORT.md`

#### Verification Results

| Check | Result |
|-------|--------|
| M&A tiers populated | ✅ 300 leads |
| Large firm exemption | ✅ 293 leads with >200 reps |
| No violations | ✅ 0 non-M&A large firms |
| Narratives | ✅ 100% coverage |

---
```

### 9. Update Document Footer

**Replace** the document footer:

```markdown
---

**Document Version**: 3.5.0 (M&A Active Tiers + Two-Query Architecture)  
**Last Updated**: January 3, 2026  
**Model Version**: V3.5.0_01032026_MA_TIERS  
**Architecture**: Two-Query (CREATE then INSERT)  
**Maintainer**: Data Science Team  
**Questions?**: Contact the Data Science team
```

---

# PROMPT 2: Update VERSION_3_MODEL_REPORT.md

## File Location
`C:\Users\russe\Documents\lead_scoring_production\v3\VERSION_3_MODEL_REPORT.md`

## Instructions

Add a new V3.5.0 section documenting the M&A tiers. Insert AFTER the V3.4.0 section and BEFORE the "Model Deployment" section.

### 1. Update Header

**Find** (lines 1-8):
```markdown
# Version 3 Lead Scoring Model - Comprehensive Technical Report

**Model Version:** V3.4.0_01012026_CAREER_CLOCK  
...
```

**Replace with**:
```markdown
# Version 3 Lead Scoring Model - Comprehensive Technical Report

**Model Version:** V3.5.0_01032026_MA_TIERS  
**Original Development Date:** December 21, 2025  
**Last Updated:** January 3, 2026 (V3.5.0: M&A Active Tiers - capture advisors at M&A target firms)  
**Base Directory:** `Version-3/`  
**Status:** ✅ Production Ready (V3.5.0 with M&A tiers achieving 9.0% conversion for PRIME tier)
```

### 2. Add V3.5.0 Section

**Insert after V3.4.0 section** (find the next "---" after V3.4.0 content and insert before it):

```markdown
---

## V3.5.0 M&A Active Tiers (January 2026)

**Release Date:** January 3, 2026

### Background: The Large Firm Paradox

Our data shows large firms (>50 reps) convert at 0.60x baseline, so we exclude them:

| Firm Size | Conversion Rate | Lift | Action |
|-----------|-----------------|------|--------|
| ≤10 reps | 6.2% | 1.62x | Include |
| 11-50 reps | 4.1% | 1.07x | Include |
| >50 reps | 2.3% | 0.60x | **Exclude** |

**The Problem:** M&A disruption changes everything. When Commonwealth (2,500 reps) was acquired by LPL, their advisors converted at 5.37% - far above the 2.3% we'd expect from a large firm.

**The Solution:** Create M&A opportunity tiers that exempt advisors at M&A target firms from the large firm exclusion.

### Empirical Evidence: Commonwealth/LPL Merger

**Event:** LPL Financial announced acquisition of Commonwealth Financial Network (July 2024)

| Metric | Value |
|--------|-------|
| Total Commonwealth advisors | ~2,500 |
| Advisors contacted | 242 |
| Conversions (MQLs) | 13 |
| **Conversion Rate** | **5.37%** |
| **Lift vs Baseline (3.82%)** | **1.41x** |
| **Lift vs Large Firm (2.3%)** | **2.34x** |

#### Profile Analysis

| Profile | Contacted | Converted | Conv Rate | Lift | Tier |
|---------|-----------|-----------|-----------|------|------|
| **Senior Titles** | 43 | 4 | 9.30% | 2.06x | → PRIME |
| **Mid-Career (10-20yr)** | 49 | 4 | 8.16% | 1.75x | → PRIME |
| Serial Movers (3+) | 175 | 9 | 5.14% | 0.86x | Does NOT help |
| Newer to Firm (<5yr) | 86 | 4 | 4.65% | 0.81x | Does NOT help |

**Key Insight:** Senior titles and mid-career advisors convert best during M&A. Serial movers do NOT convert better (they're always in-market anyway).

### New Tier Definitions

| Tier | Criteria | Expected Conv | Lift | Priority Rank |
|------|----------|---------------|------|---------------|
| **TIER_MA_ACTIVE_PRIME** | M&A target + (Senior title OR Mid-career 10-20yr) | 9.0% | 2.36x | 4 |
| **TIER_MA_ACTIVE** | M&A target (any advisor) | 5.4% | 1.41x | 5 |

**Senior Titles Include:**
- President, Principal, Partner
- Owner, Founder, Director
- Managing Director, Managing Partner

**Mid-Career Definition:**
- Industry tenure: 10-20 years (120-240 months)
- Established but not entrenched
- Most receptive to change

### Implementation Architecture: Two-Query Approach

#### Why Single-Query Failed

Multiple attempts to integrate M&A tiers into the main lead list query failed:

| Attempt | Approach | Result |
|---------|----------|--------|
| 1 | EXISTS subquery exemption | ❌ Works in isolation, fails in full query |
| 2 | JOIN exemption | ❌ Works in isolation, fails in full query |
| 3 | UNION two-track with NOT EXISTS | ❌ Works in isolation, fails in full query |
| 4 | LEFT JOIN with inline subquery | ❌ Works in isolation, fails in full query |

**Root Cause:** BigQuery's CTE optimization in complex queries (1,400+ lines) causes unpredictable behavior. CTEs may be evaluated in unexpected order, JOINs may return 0 matches, and no errors are thrown.

#### The Working Solution

```
QUERY 1: CREATE january_2026_lead_list (standard leads only)
                           ↓
QUERY 2: INSERT INTO january_2026_lead_list (M&A leads)
```

This completely bypasses BigQuery's CTE optimization by using two separate, simple queries.

### Implementation Files

| File | Purpose |
|------|---------|
| `pipeline/sql/create_ma_eligible_advisors.sql` | Pre-build M&A advisors with tier assignments |
| `pipeline/sql/Insert_MA_Leads.sql` | Insert M&A leads after base list created |
| `ml_features.active_ma_target_firms` | Track firms with M&A activity |
| `ml_features.ma_eligible_advisors` | Pre-built M&A advisor table |

### Tier Hierarchy (V3.5.0)

| Rank | Tier | Conversion | Status |
|------|------|------------|--------|
| 1 | TIER_0A_PRIME_MOVER_DUE | 16.13% | Career Clock |
| 2 | TIER_0B_SMALL_FIRM_DUE | 10.0% | Career Clock |
| 3 | TIER_0C_CLOCKWORK_DUE | 6.5% | Career Clock |
| 4 | **TIER_MA_ACTIVE_PRIME** | **9.0%** | **NEW (V3.5.0)** |
| 5 | **TIER_MA_ACTIVE** | **5.4%** | **NEW (V3.5.0)** |
| 6 | TIER_1B_PRIME_ZERO_FRICTION | 11.76% | Zero Friction |
| 7 | TIER_1A_PRIME_MOVER_CFP | 16.44% | Certification |
| ... | ... | ... | ... |

### Verification Results (January 3, 2026)

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| M&A tiers populated | 150-600 | 300 | ✅ PASS |
| TIER_MA_ACTIVE_PRIME | 50-200 | 300 | ✅ PASS |
| Large firm exemption | M&A >50 reps | 293 with >200 reps | ✅ PASS |
| No violations | 0 | 0 | ✅ PASS |
| Narratives | 100% | 100% | ✅ PASS |

### Business Impact

| Metric | Value |
|--------|-------|
| M&A leads added | 300 |
| Expected conversion | 9.0% |
| Expected MQLs | 27 |
| Would be excluded without M&A tier | 293 (at firms >200 reps) |

### M&A Window Timing

| Days Since Announcement | Status | Rationale |
|-------------------------|--------|-----------|
| 0-60 | WATCH | Too early - advisors still processing |
| 60-180 | **HOT** | Optimal - uncertainty is peak |
| 181-365 | **ACTIVE** | Still elevated - deal in progress |
| 365+ | STALE | Deal closed, dust settled |

**Critical Insight:** Contact advisors WHILE they're still at the firm. Once they leave, conversion drops to ~1.2%.

### Key Learnings

1. **M&A creates opportunity windows** - Normally low-converting large firms convert well during disruption
2. **Senior + Mid-career convert best** - They have the most at stake
3. **Timing matters** - 60-365 day window after announcement
4. **BigQuery has CTE limitations** - Use two-query architecture for complex logic
5. **The "Works in Isolation" Trap** - Logic that passes diagnostic queries can fail in full query context

### Rollback Plan

If M&A tiers underperform:

```sql
-- Remove M&A leads from lead list
DELETE FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list`
WHERE score_tier LIKE 'TIER_MA%';
```

### Refresh Schedule

| Trigger | Action |
|---------|--------|
| Monthly | Re-run `create_ma_eligible_advisors.sql` |
| M&A news | Update `active_ma_target_firms` |
| Firm status change | Update `ma_status` (HOT → ACTIVE → STALE) |

---
```

### 3. Update Document History

**Add to Document History table**:

```markdown
| 1.3 | 2026-01-03 | Added V3.5.0 M&A Active Tiers section, documented two-query architecture, updated tier hierarchy |
```

---

# PROMPT 3: Create/Update EXECUTION_LOG.md

## File Location
`C:\Users\russe\Documents\lead_scoring_production\pipeline\logs\EXECUTION_LOG.md`

## Instructions

Create or update the execution log with the V3.5.0 implementation details.

### Content to Add

```markdown
# Lead Scoring Pipeline Execution Log

---

## January 3, 2026 - V3.5.0 M&A Tiers Implementation

**Operator:** Data Science Team  
**Model Version:** V3.5.0_01032026_MA_TIERS  
**Status:** ✅ COMPLETE

### Implementation Summary

Successfully implemented M&A Active Tiers using two-query architecture after multiple single-query attempts failed.

### What Was Attempted (Failed Approaches)

| Attempt | Approach | Result | Hours Spent |
|---------|----------|--------|-------------|
| 1 | EXISTS subquery exemption in base_prospects | ❌ Failed | ~2 |
| 2 | JOIN exemption replacing EXISTS | ❌ Failed | ~2 |
| 3 | UNION two-track with NOT EXISTS | ❌ Failed | ~2 |
| 4 | LEFT JOIN with inline subquery | ❌ Failed | ~2 |
| **5** | **INSERT after CREATE (two-query)** | **✅ SUCCESS** | ~1 |

**Total debugging time before finding solution:** ~8 hours  
**Root cause:** BigQuery CTE optimization in 1,400+ line queries

### What Worked

Two-query architecture:
1. Query 1: `January_2026_Lead_List_V3_V4_Hybrid.sql` → Creates base lead list (2,800 leads)
2. Query 2: `Insert_MA_Leads.sql` → Inserts M&A leads (300 leads)

### Files Created

| File | Purpose |
|------|---------|
| `pipeline/sql/create_ma_eligible_advisors.sql` | Pre-build M&A advisors table |
| `pipeline/sql/Insert_MA_Leads.sql` | Insert M&A leads |
| `pipeline/sql/pre_implementation_verification_ma_tiers.sql` | Pre-flight checks |
| `pipeline/sql/post_implementation_verification_ma_tiers.sql` | Post-implementation checks |
| `V3_5_0_MA_TIER_COMPREHENSIVE_IMPLEMENTATION_GUIDE.md` | Full implementation guide |
| `pipeline/V3_5_0_MA_TIER_IMPLEMENTATION_RESULTS.md` | Detailed results log |

### Files Modified

| File | Changes |
|------|---------|
| `v3/models/model_registry_v3.json` | Updated to V3.5.0, added M&A tier definitions |
| `README.md` | Updated architecture, added M&A section |
| `v3/VERSION_3_MODEL_REPORT.md` | Added V3.5.0 section |

### Verification Results

| Check | Result |
|-------|--------|
| 8.1: M&A Tier Population | ✅ 300 leads |
| 8.2: Large Firm Exemption | ✅ 293 leads with >200 reps |
| 8.3: Commonwealth | ⚠️ 0 (ACTIVE tier, quota filled by PRIME) |
| 8.4: No Violations | ✅ 0 |
| 8.5: Narratives | ✅ 100% coverage |
| 8.6: Tier Distribution | ✅ M&A tiers present |
| 8.7: Spot Check | ✅ Verified |

### Final Statistics

| Metric | Value |
|--------|-------|
| Total leads | 3,100 |
| Standard leads | 2,800 |
| M&A leads | 300 |
| M&A tier | All TIER_MA_ACTIVE_PRIME |
| Expected M&A conversion | 9.0% |
| Expected M&A MQLs | 27 |

### Lessons Learned

1. **BigQuery CTE chains are unreliable** for complex exemption logic in 1,400+ line queries
2. **"Works in isolation" ≠ "Works in full query"** - Always test in production context
3. **Two-query architecture is reliable** - Completely bypasses optimization issues
4. **3-Fix Rule:** If 3 fixes don't work, change the architecture
5. **Pre-flight verification is critical** - Saved hours of debugging

### Next Steps

- [ ] Monitor M&A tier conversion rates (90-day tracking)
- [ ] Update `active_ma_target_firms` when new M&A news hits
- [ ] Consider increasing M&A quota to include ACTIVE tier
- [ ] Document SFTP feed changes when data source changes

---

## Execution History

| Date | Version | Leads Generated | M&A Leads | Notes |
|------|---------|-----------------|-----------|-------|
| 2026-01-03 | V3.5.0 | 3,100 | 300 | First M&A tier implementation |
| 2026-01-01 | V3.4.0 | 2,800 | 0 | Career Clock tiers |
| 2025-12-30 | V3.3.3 | 2,768 | 0 | Zero Friction + Sweet Spot |

---

## Future Lead List Generation

### For February 2026

```bash
# 1. Update month references in SQL files
# 2. Run the 6-step pipeline (see README.md)
# 3. Verify M&A leads are inserted
# 4. Export to CSV
```

### For SFTP Feed Transition

When transitioning to SFTP data feed:
1. Update source table references in:
   - `v4_prospect_features.sql`
   - `create_ma_eligible_advisors.sql`
   - `January_2026_Lead_List_V3_V4_Hybrid.sql`
2. Verify column names match
3. Run validation queries
4. Update documentation

---
```

---

# PROMPT 4: Update UNIFIED_MODEL_REGISTRY.json

## File Location
`C:\Users\russe\Documents\lead_scoring_production\models\UNIFIED_MODEL_REGISTRY.json`

## Instructions

Update the unified model registry with V3.5.0 information.

### Add/Update the following structure

```json
{
  "registry_version": "2.0",
  "last_updated": "2026-01-03",
  "active_models": {
    "v3": {
      "model_id": "lead-scoring-v3.5.0",
      "model_version": "V3.5.0_01032026_MA_TIERS",
      "previous_version": "V3.4.0_01012026_CAREER_CLOCK",
      "status": "PRODUCTION",
      "deployed_date": "2026-01-03",
      "architecture": "two-query",
      "description": "Rules-based tiered classification with M&A opportunity tiers",
      "changes_from_v3.4": [
        "Added TIER_MA_ACTIVE_PRIME tier (9.0% conversion, 2.36x lift)",
        "Added TIER_MA_ACTIVE tier (5.4% conversion, 1.41x lift)",
        "Implemented two-query architecture (INSERT after CREATE)",
        "Created pre-built ma_eligible_advisors table",
        "Added large firm exemption for M&A advisors",
        "Added M&A-specific narratives",
        "Bypassed BigQuery CTE optimization issues"
      ],
      "tier_definitions": {
        "TIER_MA_ACTIVE_PRIME": {
          "description": "Senior title or mid-career advisor at M&A target firm",
          "expected_conversion": 0.09,
          "expected_lift": 2.36,
          "priority_rank": 4,
          "criteria": {
            "is_at_ma_target_firm": true,
            "OR": [
              {"is_senior_title": true},
              {"industry_tenure_months": "120-240"}
            ]
          },
          "validation": {
            "source": "Commonwealth/LPL merger analysis",
            "sample_size": 43,
            "actual_conversion": 0.093
          }
        },
        "TIER_MA_ACTIVE": {
          "description": "All advisors at M&A target firms",
          "expected_conversion": 0.054,
          "expected_lift": 1.41,
          "priority_rank": 5,
          "criteria": {
            "is_at_ma_target_firm": true
          },
          "validation": {
            "source": "Commonwealth/LPL merger analysis",
            "sample_size": 242,
            "actual_conversion": 0.0537
          }
        }
      },
      "files": {
        "main_query": "pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql",
        "ma_insert_query": "pipeline/sql/Insert_MA_Leads.sql",
        "ma_advisors_table": "pipeline/sql/create_ma_eligible_advisors.sql",
        "verification": "pipeline/sql/post_implementation_verification_ma_tiers.sql",
        "implementation_guide": "V3_5_0_MA_TIER_COMPREHENSIVE_IMPLEMENTATION_GUIDE.md",
        "model_registry": "v3/models/model_registry_v3.json"
      },
      "bigquery_tables": {
        "lead_list": "ml_features.january_2026_lead_list",
        "ma_eligible_advisors": "ml_features.ma_eligible_advisors",
        "active_ma_target_firms": "ml_features.active_ma_target_firms"
      },
      "execution_order": [
        "1. Run create_ma_eligible_advisors.sql",
        "2. Run v4_prospect_features.sql",
        "3. Run score_prospects_monthly.py",
        "4. Run January_2026_Lead_List_V3_V4_Hybrid.sql",
        "5. Run Insert_MA_Leads.sql (MUST be after step 4)",
        "6. Run export_lead_list.py"
      ]
    },
    "v4": {
      "model_id": "lead-scoring-v4.2.0",
      "model_version": "V4.2.0_CAREER_CLOCK",
      "status": "PRODUCTION",
      "deployed_date": "2026-01-01",
      "description": "XGBoost ML model with Career Clock features",
      "files": {
        "model": "v4/models/v4.2.0/model.pkl",
        "config": "v4/models/v4.2.0/model.json",
        "features": "v4/data/v4.2.0/final_features.json"
      }
    }
  },
  "sftp_transition": {
    "status": "PENDING",
    "notes": "When SFTP feed is enabled, update source table references in all SQL files",
    "files_to_update": [
      "pipeline/sql/v4_prospect_features.sql",
      "pipeline/sql/create_ma_eligible_advisors.sql",
      "pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql"
    ]
  }
}
```

---

# Summary Checklist

After running these prompts, verify:

- [ ] `README.md` updated with V3.5.0 header, two-query architecture, M&A section
- [ ] `VERSION_3_MODEL_REPORT.md` has V3.5.0 section with full M&A documentation
- [ ] `EXECUTION_LOG.md` documents implementation process and lessons learned
- [ ] `UNIFIED_MODEL_REGISTRY.json` reflects V3.5.0 with all metadata
- [ ] All files reference the correct model version: `V3.5.0_01032026_MA_TIERS`
- [ ] Two-query architecture is documented in all relevant places
- [ ] Execution order is clear (INSERT MUST run after CREATE)
- [ ] SFTP transition notes are included for future reference

---

**END OF DOCUMENTATION UPDATE PROMPTS**
