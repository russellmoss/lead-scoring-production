# Title Exclusions Reference

## Overview

This document tracks all title exclusions applied across the lead scoring pipeline to ensure consistency when generating new lead lists.

## Standard Title Exclusions

The following titles are excluded from all lead lists:

### Non-Producing Titles
- Financial Solutions Advisor
- Paraplanner
- Associate Advisor (or any title containing "associate")
- Operations
- Wholesaler
- Compliance
- Assistant
- Insurance Agent
- Insurance

### Executive/Senior Titles
- Chief Financial Officer (CFO)
- Chief Investment Officer (CIO)
- Vice President (VP)
- Managing Director
- Founder
- Partner
- CEO (Chief Executive Officer)

## Files Updated

### Main Pipeline Files
1. **`pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`**
   - Location: `base_prospects` CTE (line ~344)
   - Status: ✅ Updated with CFO, CIO, VP exclusions

2. **`pipeline/sql/create_ma_eligible_advisors.sql`**
   - Location: `ma_advisors` CTE WHERE clause
   - Status: ✅ Updated with CFO, CIO, VP exclusions

3. **`pipeline/sql/Supplemental_Lead_List_Under_70.sql`**
   - Location: `base_prospects` CTE
   - Status: ✅ Updated with CFO, CIO, VP exclusions

4. **`pipeline/sql/Top_10_Percentile_51_Advisor_List.sql`**
   - Location: `base_prospects` CTE
   - Status: ✅ Updated with all executive/senior title exclusions

## SQL Pattern

When adding title exclusions to new queries, use this pattern:

```sql
-- Title exclusions
AND NOT (
    UPPER(c.TITLE_NAME) LIKE '%FINANCIAL SOLUTIONS ADVISOR%'
    OR UPPER(c.TITLE_NAME) LIKE '%PARAPLANNER%'
    OR UPPER(c.TITLE_NAME) LIKE '%ASSOCIATE%'  -- Catches all associate titles
    OR UPPER(c.TITLE_NAME) LIKE '%OPERATIONS%'
    OR UPPER(c.TITLE_NAME) LIKE '%WHOLESALER%'
    OR UPPER(c.TITLE_NAME) LIKE '%COMPLIANCE%'
    OR UPPER(c.TITLE_NAME) LIKE '%ASSISTANT%'
    OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE AGENT%'
    OR UPPER(c.TITLE_NAME) LIKE '%INSURANCE%'
    -- Executive/Senior title exclusions
    OR UPPER(c.TITLE_NAME) LIKE '%CHIEF FINANCIAL OFFICER%'
    OR UPPER(c.TITLE_NAME) LIKE '%CFO%'
    OR UPPER(c.TITLE_NAME) LIKE '%CHIEF INVESTMENT OFFICER%'
    OR UPPER(c.TITLE_NAME) LIKE '%CIO%'
    OR UPPER(c.TITLE_NAME) LIKE '%VICE PRESIDENT%'
    OR UPPER(c.TITLE_NAME) LIKE '%VP %'  -- VP with space to avoid false positives
    OR UPPER(c.TITLE_NAME) LIKE '%MANAGING DIRECTOR%'
    OR UPPER(c.TITLE_NAME) LIKE '%FOUNDER%'
    OR UPPER(c.TITLE_NAME) LIKE '%PARTNER%'
    OR UPPER(c.TITLE_NAME) LIKE '%CEO%'
    OR UPPER(c.TITLE_NAME) LIKE '%CHIEF EXECUTIVE OFFICER%'
)
```

## Rationale

These exclusions are applied because:

1. **Executive/Senior Roles**: CFO, CIO, VP, Managing Director, Founder, Partner, CEO are typically:
   - Less likely to move (equity/ownership stake)
   - More committed to current firm
   - Lower conversion rates historically

2. **Associate Titles**: Associate-level positions are typically:
   - Junior advisors without portable books
   - Lower conversion rates
   - Less decision-making authority

3. **Non-Producing Roles**: Operations, Compliance, etc. are:
   - Not client-facing advisors
   - Don't have portable books
   - Not the target audience

## When Creating New Lead Lists

**Always include these title exclusions** in the `base_prospects` or equivalent CTE to ensure consistency across all lead lists.

## Last Updated

- **Date**: 2026-01-14
- **Added**: CFO, CIO, VP exclusions to main pipeline
- **Files Updated**: 4 SQL files
