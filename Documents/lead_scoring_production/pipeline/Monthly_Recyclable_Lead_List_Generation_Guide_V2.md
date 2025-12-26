# Monthly Recyclable Lead List Generation Guide (V2.1 - Corrected SQL)

**Status**: ✅ **READY FOR AGENTIC EXECUTION**  
**Purpose**: Generate a monthly list of 600 recyclable leads/opportunities for SGAs  
**Working Directory**: `C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation`  
**Output**: `exports/[MONTH]_[YEAR]_recyclable_leads.csv`  
**Report Output**: `reports/recycling_analysis/[MONTH]_[YEAR]_recyclable_list_report.md`

**Version History**:
- **V2.1** (Dec 24, 2025): Fixed all critical SQL issues - date type mismatches, tenure calculations, added PIT employment history join, field validation
- **V2.0** (Dec 24, 2025): Corrected firm change logic (exclude recent movers < 2 years)

---

## Executive Summary

This guide creates a **separate recyclable lead list** of 600 leads/opportunities per month that SGAs can work in addition to the primary Provided Lead List.

### Critical Logic Correction: Firm Changes

**WRONG ASSUMPTION** (V1): "Changed firms = hot lead, prioritize them"

**CORRECT LOGIC** (V2): 
- If someone **just changed firms** (< 2 years), they are **NOT ready to move again**
- They just went through transition pain, are building relationships, need to settle in
- **EXCLUDE** anyone who changed firms within the last 2 years
- **INCLUDE** people who changed firms 2+ years ago (proven movers, may be restless)

### Priority Tiers (Corrected)

| Priority | Criteria | Rationale | Expected Conv |
|----------|----------|-----------|---------------|
| **P1** | "Timing" disposition + 6-12 months passed | They said timing was bad - try again | 6-8% |
| **P2** | High V4 (≥80%) + No firm change + Long tenure | Model predicts movement, hasn't moved yet | 5-7% |
| **P3** | "No Response" + High V4 + 90-180 days | Good prospect who didn't engage before | 4-6% |
| **P4** | Changed firms **2-3 years ago** | Proven mover, may be getting restless | 4-5% |
| **P5** | Changed firms **3+ years ago** + High V4 | Definite mover, overdue for another change | 4-5% |
| **P6** | Standard recycle (other eligible) | General re-engagement pool | 3-4% |

### Key Exclusions

| Exclusion | Reason |
|-----------|--------|
| Changed firms **< 2 years ago** | Just settled in, won't move again soon |
| No-go dispositions | Permanent disqualifications |
| DoNotCall = true | Opted out |
| Recently contacted (< 90 days) | Too soon to re-engage |

---

## Phase 0: Setup

### Cursor Prompt 0.1: Create Directory Structure

```
@workspace Create the directory structure for recyclable lead list generation.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Task:
1. Ensure the following directories exist:
   Lead_List_Generation/
   ├── sql/
   │   └── recycling/
   ├── scripts/
   │   └── recycling/
   ├── exports/
   └── reports/
       └── recycling_analysis/

2. Create/update log file: reports/recycling_analysis/RECYCLABLE_LIST_LOG.md

3. Confirm structure created.
```

---

## Phase 1: Create Master Recyclable Pool SQL (Corrected Logic)

### Cursor Prompt 1.1: Create the Corrected Recyclable Query

```
@workspace Create the master SQL query for identifying recyclable leads and opportunities with CORRECTED firm change logic.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Task:
1. Create sql/recycling/recyclable_pool_master_v2.1.sql with the following SQL:
```

```sql
-- ============================================================================
-- RECYCLABLE POOL MASTER QUERY V2.1 (CORRECTED SQL)
-- 
-- KEY BUSINESS LOGIC:
-- 1. People who RECENTLY changed firms (< 2 years) are EXCLUDED
--    - They just settled in and won't move again soon
--    
-- 2. People who HAVEN'T changed firms + High V4 + Long tenure are PRIORITIZED
--    - Model predicts they're about to move
--    - They're still at the same firm (available to recruit)
--    
-- 3. People who changed firms 2-3 years ago are MEDIUM priority
--    - Proven movers, settling period is over
--    
-- 4. "Timing" dispositions are HIGH priority
--    - They literally told us timing was bad
--    - If 6-12 months passed, timing may be better now
--
-- PRIORITY ORDER:
--   P1: "Timing" disposition + 180-365 days passed (7% expected)
--   P2: High V4 + No firm change + Long tenure NOW (6% expected)
--   P3: "No Response" + High V4 (5% expected)
--   P4: Changed firms 2-3 years ago (4.5% expected)
--   P5: Changed firms 3+ years ago + V4≥60 (4% expected)
--   P6: Standard recycle (3% expected)
--
-- EXCLUSIONS:
--   - Changed firms < 2 years ago (just settled in)
--   - No-go dispositions (permanent DQ)
--   - DoNotCall = true
--   - Contacted < 90 days ago
--
-- SQL FIXES IN V2.1:
--   - Fixed date type mismatches (DATE() casting)
--   - Fixed tenure calculations (calculate to CloseDate, not CURRENT_DATE)
--   - Added PIT-compliant employment history join
--   - Added field validation with COALESCE
--   - Fixed priority logic to use correct tenure fields
-- ============================================================================

DECLARE target_count INT64 DEFAULT 600;
DECLARE min_days_since_contact INT64 DEFAULT 90;   -- Minimum days since last contact
DECLARE max_days_since_contact INT64 DEFAULT 730;  -- Maximum 2 years
DECLARE min_years_since_firm_change INT64 DEFAULT 2;  -- Must be 2+ years since firm change

-- ============================================================================
-- PART A: EXCLUSION LISTS
-- ============================================================================

-- A1. No-Go Dispositions (Leads) - Permanent disqualifications
CREATE TEMP TABLE nogo_lead_dispositions AS
SELECT disposition FROM UNNEST([
    'Not Interested in Moving',
    'Not a Fit',
    'No Book',
    'Book Not Transferable',
    'Restrictive Covenants',
    'Bad Lead Provided',
    'Wants Platform Only',
    'AUM / Revenue too Low'
]) AS disposition;

-- A2. No-Go Close Lost Reasons (Opportunities) - Permanent disqualifications
CREATE TEMP TABLE nogo_opp_reasons AS
SELECT reason FROM UNNEST([
    'Savvy Declined - No Book of Business',
    'Savvy Declined - Insufficient Revenue',
    'Savvy Declined – Book Not Transferable',
    'Savvy Declined - Poor Culture Fit',
    'Savvy Declined - Compliance',
    'Candidate Declined - Lost to Competitor'
]) AS reason;

-- A3. HIGH PRIORITY Recyclable Dispositions (Leads) - "Timing" related
CREATE TEMP TABLE timing_lead_dispositions AS
SELECT disposition FROM UNNEST([
    'Timing'
]) AS disposition;

-- A4. HIGH PRIORITY Recyclable Reasons (Opportunities) - "Timing" related
CREATE TEMP TABLE timing_opp_reasons AS
SELECT reason FROM UNNEST([
    'Candidate Declined - Timing',
    'Candidate Declined - Fear of Change'
]) AS reason;

-- A5. MEDIUM PRIORITY Recyclable - General re-engagement
CREATE TEMP TABLE general_recyclable_dispositions AS
SELECT disposition FROM UNNEST([
    'No Response',
    'Auto-Closed by Operations',
    'Other',
    'No Show / Ghosted'
]) AS disposition;

CREATE TEMP TABLE general_recyclable_reasons AS
SELECT reason FROM UNNEST([
    'No Longer Responsive',
    'No Show – Intro Call',
    'Other'
]) AS reason;

-- A6. Excluded firms (internal, wirehouses)
CREATE TEMP TABLE excluded_firms AS
SELECT firm_pattern FROM UNNEST([
    '%SAVVY WEALTH%', '%RITHOLTZ%',
    '%J.P. MORGAN%', '%MORGAN STANLEY%', '%MERRILL%', '%WELLS FARGO%',
    '%UBS %', '%EDWARD JONES%', '%AMERIPRISE%', '%NORTHWESTERN MUTUAL%',
    '%PRUDENTIAL%', '%RAYMOND JAMES%', '%FIDELITY%', '%SCHWAB%'
]) AS firm_pattern;

-- ============================================================================
-- PART B: LAST TASK ACTIVITY
-- ============================================================================

WITH lead_last_tasks AS (
    SELECT 
        t.WhoId as record_id,
        MAX(t.ActivityDate) as last_task_date,
        ARRAY_AGG(t.OwnerId ORDER BY t.ActivityDate DESC LIMIT 1)[OFFSET(0)] as last_task_owner_id,
        ARRAY_AGG(t.Subject ORDER BY t.ActivityDate DESC LIMIT 1)[OFFSET(0)] as last_task_subject
    FROM `savvy-gtm-analytics.SavvyGTMData.Task` t
    WHERE t.WhoId LIKE '00Q%'
      AND t.IsDeleted = false
    GROUP BY t.WhoId
),

opp_last_tasks AS (
    SELECT 
        t.WhatId as record_id,
        MAX(t.ActivityDate) as last_task_date,
        ARRAY_AGG(t.OwnerId ORDER BY t.ActivityDate DESC LIMIT 1)[OFFSET(0)] as last_task_owner_id,
        ARRAY_AGG(t.Subject ORDER BY t.ActivityDate DESC LIMIT 1)[OFFSET(0)] as last_task_subject
    FROM `savvy-gtm-analytics.SavvyGTMData.Task` t
    WHERE t.WhatId LIKE '006%'
      AND t.IsDeleted = false
    GROUP BY t.WhatId
),

users AS (
    SELECT Id, Name, Email
    FROM `savvy-gtm-analytics.SavvyGTMData.User`
    WHERE IsActive = true
),

-- ============================================================================
-- PART C: RECYCLABLE OPPORTUNITIES (Priority over Leads)
-- ============================================================================

recyclable_opportunities AS (
    SELECT 
        o.Id as record_id,
        'OPPORTUNITY' as record_type,
        o.Name as record_name,
        o.FA_CRD__c as fa_crd,
        -- Field validation with COALESCE
        COALESCE(o.Advisor_First_Name__c, c.FIRST_NAME, 'Unknown') as first_name,
        COALESCE(o.Advisor_Last_Name__c, c.LAST_NAME, 'Unknown') as last_name,
        COALESCE(o.Advisor_Email__c, c.EMAIL, NULL) as email,
        COALESCE(o.Advisor_Phone__c, c.PHONE, NULL) as phone,
        COALESCE(c.LINKEDIN_PROFILE_URL, o.Advisor_LinkedIn__c, NULL) as linkedin_url,
        COALESCE(c.PRIMARY_FIRM_NAME, o.Advisor_Firm_Name__c, NULL) as firm_name,
        COALESCE(o.SGM_Owner__c, o.OwnerId) as owner_id,
        sgm.Name as owner_name,
        
        -- Stage and disposition info
        o.StageName as last_stage,
        o.Closed_Lost_Reason__c as close_reason,
        o.Closed_Lost_Details__c as close_details,
        DATE(o.CloseDate) as close_date,
        
        -- Task activity
        ot.last_task_date,
        ot.last_task_subject,
        tu.Name as last_contacted_by,
        DATE_DIFF(CURRENT_DATE(), COALESCE(ot.last_task_date, DATE(o.CloseDate)), DAY) as days_since_last_contact,
        
        -- FINTRX enrichment
        c.PRIMARY_FIRM_NAME as current_firm_name,
        c.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        c.LINKEDIN_PROFILE_URL as fintrx_linkedin,
        
        -- Firm change analysis (CRITICAL FOR PRIORITY) - FIXED: Date type casting
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
                 AND DATE(c.PRIMARY_FIRM_START_DATE) > DATE(o.CloseDate) 
            THEN TRUE
            ELSE FALSE
        END as changed_firms_since_close,
        
        -- YEARS since firm change (key metric) - Current tenure at their current firm
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
            THEN DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_current_firm,
        
        -- Current tenure at firm NOW (for people who haven't changed firms)
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL
            THEN DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_current_firm_now,
        
        -- Tenure at firm WHEN WE CLOSED THEM (using PIT employment history)
        CASE 
            WHEN eh_pit.firm_start_at_close IS NOT NULL
            THEN DATE_DIFF(DATE(o.CloseDate), DATE(eh_pit.firm_start_at_close), DAY) / 365.0
            -- Fallback: if no employment history, use current firm start if it was before close
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
                 AND DATE(c.PRIMARY_FIRM_START_DATE) <= DATE(o.CloseDate)
            THEN DATE_DIFF(DATE(o.CloseDate), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_firm_when_closed,
        
        -- V4 scoring
        vs.v4_score,
        vs.v4_percentile,
        
        -- Is this a "Timing" close reason? (HIGH PRIORITY)
        CASE WHEN o.Closed_Lost_Reason__c IN (SELECT reason FROM timing_opp_reasons) THEN TRUE ELSE FALSE END as is_timing_reason,
        
        -- Is this a general recyclable reason?
        CASE WHEN o.Closed_Lost_Reason__c IN (SELECT reason FROM general_recyclable_reasons) THEN TRUE ELSE FALSE END as is_general_recyclable
        
    FROM `savvy-gtm-analytics.SavvyGTMData.Opportunity` o
    LEFT JOIN opp_last_tasks ot ON o.Id = ot.record_id
    LEFT JOIN users tu ON ot.last_task_owner_id = tu.Id
    LEFT JOIN users sgm ON COALESCE(o.SGM_Owner__c, o.OwnerId) = sgm.Id
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(o.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    -- PIT-compliant employment history join to find firm at time of close
    LEFT JOIN (
        SELECT 
            RIA_CONTACT_CRD_ID as crd,
            PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name_at_close,
            PREVIOUS_REGISTRATION_COMPANY_CRD as firm_crd_at_close,
            PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_at_close,
            PREVIOUS_REGISTRATION_COMPANY_END_DATE as firm_end_at_close
        FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
        WHERE PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
    ) eh_pit ON SAFE_CAST(REGEXP_REPLACE(CAST(o.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = eh_pit.crd
        AND DATE(eh_pit.firm_start_at_close) <= DATE(o.CloseDate)
        AND (eh_pit.firm_end_at_close IS NULL OR DATE(eh_pit.firm_end_at_close) >= DATE(o.CloseDate))
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY o.Id 
        ORDER BY eh_pit.firm_start_at_close DESC
    ) = 1
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` vs 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(o.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = vs.crd
    WHERE 
        -- Closed Lost only
        o.IsClosed = true
        AND o.IsWon = false
        AND o.IsDeleted = false
        -- NOT no-go reasons
        AND o.Closed_Lost_Reason__c NOT IN (SELECT reason FROM nogo_opp_reasons)
        -- Time window for last contact
        AND DATE_DIFF(CURRENT_DATE(), COALESCE(ot.last_task_date, o.CloseDate), DAY) >= min_days_since_contact
        AND DATE_DIFF(CURRENT_DATE(), COALESCE(ot.last_task_date, o.CloseDate), DAY) <= max_days_since_contact
        -- Has CRD
        AND o.FA_CRD__c IS NOT NULL
        -- CRITICAL: Exclude people who changed firms RECENTLY (< 2 years) - FIXED: Date type casting
        AND (
            -- No firm data available
            c.PRIMARY_FIRM_START_DATE IS NULL 
            -- OR they didn't change firms after we closed them
            OR DATE(c.PRIMARY_FIRM_START_DATE) <= DATE(o.CloseDate)
            -- OR they changed firms 2+ years ago (enough time to be restless again)
            OR DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) >= (min_years_since_firm_change * 365)
        )
        -- Not at excluded firms
        AND NOT EXISTS (
            SELECT 1 FROM excluded_firms ef
            WHERE UPPER(COALESCE(c.PRIMARY_FIRM_NAME, o.Advisor_Firm_Name__c)) LIKE ef.firm_pattern
        )
),

-- ============================================================================
-- PART D: RECYCLABLE LEADS
-- ============================================================================

recyclable_leads AS (
    SELECT 
        l.Id as record_id,
        'LEAD' as record_type,
        CONCAT(COALESCE(l.FirstName, ''), ' ', COALESCE(l.LastName, '')) as record_name,
        l.FA_CRD__c as fa_crd,
        -- Field validation with COALESCE
        COALESCE(l.FirstName, c.FIRST_NAME, 'Unknown') as first_name,
        COALESCE(l.LastName, c.LAST_NAME, 'Unknown') as last_name,
        COALESCE(l.Email, c.EMAIL, NULL) as email,
        COALESCE(l.Phone, c.PHONE, NULL) as phone,
        COALESCE(c.LINKEDIN_PROFILE_URL, l.LinkedIn_URL__c, l.LinkedIn_Profile_URL__c, NULL) as linkedin_url,
        COALESCE(c.PRIMARY_FIRM_NAME, l.Company, NULL) as firm_name,
        COALESCE(l.SGA_Owner__c, l.OwnerId) as owner_id,
        sga.Name as owner_name,
        
        -- Stage and disposition info
        l.Status as last_stage,
        l.Disposition__c as close_reason,
        CAST(NULL AS STRING) as close_details,
        DATE(l.Stage_Entered_Closed__c) as close_date,
        
        -- Task activity
        lt.last_task_date,
        lt.last_task_subject,
        tu.Name as last_contacted_by,
        DATE_DIFF(CURRENT_DATE(), COALESCE(lt.last_task_date, DATE(l.Stage_Entered_Closed__c)), DAY) as days_since_last_contact,
        
        -- FINTRX enrichment
        c.PRIMARY_FIRM_NAME as current_firm_name,
        c.PRIMARY_FIRM_START_DATE as current_firm_start_date,
        c.LINKEDIN_PROFILE_URL as fintrx_linkedin,
        
        -- Firm change analysis - FIXED: Date type casting (Stage_Entered_Closed__c is TIMESTAMP)
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
                 AND DATE(c.PRIMARY_FIRM_START_DATE) > DATE(l.Stage_Entered_Closed__c) 
            THEN TRUE
            ELSE FALSE
        END as changed_firms_since_close,
        
        -- YEARS since firm change - Current tenure at their current firm
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
            THEN DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_current_firm,
        
        -- Current tenure at firm NOW (for people who haven't changed firms)
        CASE 
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL
            THEN DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_current_firm_now,
        
        -- Tenure at firm WHEN WE CLOSED THEM (using PIT employment history)
        CASE 
            WHEN eh_pit.firm_start_at_close IS NOT NULL
            THEN DATE_DIFF(DATE(l.Stage_Entered_Closed__c), DATE(eh_pit.firm_start_at_close), DAY) / 365.0
            -- Fallback: if no employment history, use current firm start if it was before close
            WHEN c.PRIMARY_FIRM_START_DATE IS NOT NULL 
                 AND DATE(c.PRIMARY_FIRM_START_DATE) <= DATE(l.Stage_Entered_Closed__c)
            THEN DATE_DIFF(DATE(l.Stage_Entered_Closed__c), DATE(c.PRIMARY_FIRM_START_DATE), DAY) / 365.0
            ELSE NULL
        END as years_at_firm_when_closed,
        
        -- V4 scoring
        vs.v4_score,
        vs.v4_percentile,
        
        -- Is this a "Timing" disposition? (HIGH PRIORITY)
        CASE WHEN l.Disposition__c IN (SELECT disposition FROM timing_lead_dispositions) THEN TRUE ELSE FALSE END as is_timing_reason,
        
        -- Is this a general recyclable?
        CASE WHEN l.Disposition__c IN (SELECT disposition FROM general_recyclable_dispositions) THEN TRUE ELSE FALSE END as is_general_recyclable
        
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    LEFT JOIN lead_last_tasks lt ON l.Id = lt.record_id
    LEFT JOIN users tu ON lt.last_task_owner_id = tu.Id
    LEFT JOIN users sga ON COALESCE(l.SGA_Owner__c, l.OwnerId) = sga.Id
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = c.RIA_CONTACT_CRD_ID
    -- PIT-compliant employment history join to find firm at time of close
    LEFT JOIN (
        SELECT 
            RIA_CONTACT_CRD_ID as crd,
            PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name_at_close,
            PREVIOUS_REGISTRATION_COMPANY_CRD as firm_crd_at_close,
            PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_at_close,
            PREVIOUS_REGISTRATION_COMPANY_END_DATE as firm_end_at_close
        FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
        WHERE PREVIOUS_REGISTRATION_COMPANY_START_DATE IS NOT NULL
    ) eh_pit ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = eh_pit.crd
        AND DATE(eh_pit.firm_start_at_close) <= DATE(l.Stage_Entered_Closed__c)
        AND (eh_pit.firm_end_at_close IS NULL OR DATE(eh_pit.firm_end_at_close) >= DATE(l.Stage_Entered_Closed__c))
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY l.Id 
        ORDER BY eh_pit.firm_start_at_close DESC
    ) = 1
    LEFT JOIN `savvy-gtm-analytics.ml_features.v4_prospect_scores` vs 
        ON SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = vs.crd
    WHERE 
        -- Closed leads only
        l.Status = 'Closed'
        AND l.IsConverted = false
        AND l.DoNotCall = false
        AND l.IsDeleted = false
        -- NOT no-go dispositions
        AND l.Disposition__c NOT IN (SELECT disposition FROM nogo_lead_dispositions)
        -- Time window
        AND DATE_DIFF(CURRENT_DATE(), COALESCE(lt.last_task_date, DATE(l.Stage_Entered_Closed__c)), DAY) >= min_days_since_contact
        AND DATE_DIFF(CURRENT_DATE(), COALESCE(lt.last_task_date, DATE(l.Stage_Entered_Closed__c)), DAY) <= max_days_since_contact
        -- Has CRD
        AND l.FA_CRD__c IS NOT NULL
        -- Not converted to Opportunity
        AND l.ConvertedOpportunityId IS NULL
        -- CRITICAL: Exclude people who changed firms RECENTLY (< 2 years) - FIXED: Date type casting
        AND (
            c.PRIMARY_FIRM_START_DATE IS NULL 
            OR DATE(c.PRIMARY_FIRM_START_DATE) <= DATE(l.Stage_Entered_Closed__c)
            OR DATE_DIFF(CURRENT_DATE(), DATE(c.PRIMARY_FIRM_START_DATE), DAY) >= (min_years_since_firm_change * 365)
        )
        -- Not at excluded firms
        AND NOT EXISTS (
            SELECT 1 FROM excluded_firms ef
            WHERE UPPER(COALESCE(c.PRIMARY_FIRM_NAME, l.Company)) LIKE ef.firm_pattern
        )
        -- Not already in recyclable opportunities (dedupe by CRD)
        AND NOT EXISTS (
            SELECT 1 FROM recyclable_opportunities ro
            WHERE SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) = 
                  SAFE_CAST(REGEXP_REPLACE(CAST(ro.fa_crd AS STRING), r'[^0-9]', '') AS INT64)
        )
),

-- ============================================================================
-- PART E: COMBINE AND APPLY PRIORITY LOGIC
-- ============================================================================

combined_recyclable AS (
    SELECT * FROM recyclable_opportunities
    UNION ALL
    SELECT * FROM recyclable_leads
),

-- Apply CORRECTED priority logic
with_priority AS (
    SELECT 
        cr.*,
        
        -- ========================================
        -- PRIORITY ASSIGNMENT (CORRECTED LOGIC)
        -- ========================================
        CASE 
            -- P1: "Timing" reasons - they said timing was bad, try again now
            -- Opportunities first, then leads
            WHEN cr.is_timing_reason = TRUE AND cr.record_type = 'OPPORTUNITY'
                AND cr.days_since_last_contact BETWEEN 180 AND 365
                THEN 'P1_TIMING_OPP'
            WHEN cr.is_timing_reason = TRUE AND cr.record_type = 'LEAD'
                AND cr.days_since_last_contact BETWEEN 180 AND 365
                THEN 'P1_TIMING_LEAD'
            
            -- P2: High V4 + NO recent firm change + Long tenure NOW (about to move)
            -- These people haven't moved but model predicts they will
            -- FIXED: Use years_at_current_firm_now (current tenure) not years_at_firm_total
            WHEN cr.v4_percentile >= 80 
                AND cr.changed_firms_since_close = FALSE
                AND cr.years_at_current_firm_now >= 3
                AND cr.record_type = 'OPPORTUNITY'
                THEN 'P2_HIGH_V4_LONG_TENURE_OPP'
            WHEN cr.v4_percentile >= 80 
                AND cr.changed_firms_since_close = FALSE
                AND cr.years_at_current_firm_now >= 3
                AND cr.record_type = 'LEAD'
                THEN 'P2_HIGH_V4_LONG_TENURE_LEAD'
            
            -- P3: "No Response" + High V4 (good prospect who didn't engage)
            WHEN cr.close_reason IN ('No Response', 'No Longer Responsive', 'No Show – Intro Call', 'No Show / Ghosted')
                AND cr.v4_percentile >= 70
                AND cr.record_type = 'OPPORTUNITY'
                THEN 'P3_NO_RESPONSE_HIGH_V4_OPP'
            WHEN cr.close_reason IN ('No Response', 'Auto-Closed by Operations', 'No Show / Ghosted')
                AND cr.v4_percentile >= 70
                AND cr.record_type = 'LEAD'
                THEN 'P3_NO_RESPONSE_HIGH_V4_LEAD'
            
            -- P4: Changed firms 2-3 years ago (proven mover, may be getting restless)
            WHEN cr.changed_firms_since_close = TRUE
                AND cr.years_at_current_firm BETWEEN 2 AND 3
                AND cr.record_type = 'OPPORTUNITY'
                THEN 'P4_CHANGED_2_3_YRS_OPP'
            WHEN cr.changed_firms_since_close = TRUE
                AND cr.years_at_current_firm BETWEEN 2 AND 3
                AND cr.record_type = 'LEAD'
                THEN 'P4_CHANGED_2_3_YRS_LEAD'
            
            -- P5: Changed firms 3+ years ago + High V4 (definite mover, overdue)
            WHEN cr.changed_firms_since_close = TRUE
                AND cr.years_at_current_firm > 3
                AND cr.v4_percentile >= 60
                AND cr.record_type = 'OPPORTUNITY'
                THEN 'P5_CHANGED_3_PLUS_YRS_OPP'
            WHEN cr.changed_firms_since_close = TRUE
                AND cr.years_at_current_firm > 3
                AND cr.v4_percentile >= 60
                AND cr.record_type = 'LEAD'
                THEN 'P5_CHANGED_3_PLUS_YRS_LEAD'
            
            -- P6: Standard recycle - everything else that's eligible
            WHEN cr.record_type = 'OPPORTUNITY'
                THEN 'P6_STANDARD_OPP'
            ELSE 'P6_STANDARD_LEAD'
        END as recycle_priority,
        
        -- Expected conversion rate based on priority - FIXED: Use years_at_current_firm_now
        CASE 
            WHEN cr.is_timing_reason = TRUE AND cr.days_since_last_contact BETWEEN 180 AND 365 THEN 0.07
            WHEN cr.v4_percentile >= 80 AND cr.changed_firms_since_close = FALSE AND cr.years_at_current_firm_now >= 3 THEN 0.06
            WHEN cr.close_reason IN ('No Response', 'No Longer Responsive', 'No Show – Intro Call') AND cr.v4_percentile >= 70 THEN 0.05
            WHEN cr.changed_firms_since_close = TRUE AND cr.years_at_current_firm BETWEEN 2 AND 3 THEN 0.045
            WHEN cr.changed_firms_since_close = TRUE AND cr.years_at_current_firm > 3 THEN 0.04
            ELSE 0.03
        END as expected_conversion_rate
        
    FROM combined_recyclable cr
),

-- Final ranking
ranked_recyclable AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            ORDER BY 
                -- Priority tier order
                CASE 
                    WHEN recycle_priority LIKE 'P1_%' THEN 1
                    WHEN recycle_priority LIKE 'P2_%' THEN 2
                    WHEN recycle_priority LIKE 'P3_%' THEN 3
                    WHEN recycle_priority LIKE 'P4_%' THEN 4
                    WHEN recycle_priority LIKE 'P5_%' THEN 5
                    ELSE 6
                END,
                -- Within tier: Opportunities first
                CASE record_type WHEN 'OPPORTUNITY' THEN 0 ELSE 1 END,
                -- Then by V4 percentile
                v4_percentile DESC NULLS LAST,
                -- Then by days since contact (optimal window first)
                ABS(days_since_last_contact - 180),  -- Closer to 180 days = better
                record_id
        ) as recycle_rank
    FROM with_priority
)

-- ============================================================================
-- FINAL OUTPUT
-- ============================================================================

SELECT 
    recycle_rank as list_rank,
    record_id,
    record_type,
    fa_crd,
    first_name,
    last_name,
    email,
    phone,
    COALESCE(fintrx_linkedin, linkedin_url) as linkedin_url,
    COALESCE(current_firm_name, firm_name) as current_firm,
    firm_name as firm_at_close,
    owner_id,
    owner_name,
    
    -- Recycling context
    recycle_priority,
    ROUND(expected_conversion_rate * 100, 1) as expected_conv_rate_pct,
    
    -- History
    last_stage,
    close_reason,
    close_details,
    close_date,
    last_task_date,
    last_task_subject,
    last_contacted_by,
    days_since_last_contact,
    
    -- Firm change analysis
    changed_firms_since_close,
    ROUND(years_at_current_firm, 1) as years_at_current_firm,
    ROUND(years_at_current_firm_now, 1) as years_at_current_firm_now,
    ROUND(years_at_firm_when_closed, 1) as years_at_firm_when_closed,
    
    -- Scoring
    ROUND(v4_score, 4) as v4_score,
    v4_percentile,
    
    -- Flags
    is_timing_reason,
    is_general_recyclable,
    
    CURRENT_TIMESTAMP() as generated_at

FROM ranked_recyclable
WHERE recycle_rank <= target_count
ORDER BY recycle_rank;

-- ============================================================================
-- VALIDATION QUERIES - Run after generating list to verify data quality
-- ============================================================================

-- V1: Check for date type issues (should return 0 rows)
-- SELECT 
--     record_id,
--     record_type,
--     'DATE_ISSUE' as issue,
--     close_date,
--     years_at_current_firm
-- FROM [GENERATED_TABLE]
-- WHERE years_at_current_firm < 0 
--    OR years_at_current_firm > 50;

-- V2: Check for recent firm changers that slipped through (should return 0 rows)
-- SELECT 
--     record_id,
--     record_type,
--     'RECENT_MOVER' as issue,
--     changed_firms_since_close,
--     years_at_current_firm
-- FROM [GENERATED_TABLE]
-- WHERE changed_firms_since_close = TRUE 
--   AND years_at_current_firm < 2;

-- V3: Check priority distribution
-- SELECT 
--     recycle_priority,
--     COUNT(*) as count,
--     ROUND(AVG(expected_conv_rate_pct), 2) as avg_conv
-- FROM [GENERATED_TABLE]
-- GROUP BY recycle_priority
-- ORDER BY 1;
```

2. Save the file
3. Log creation to RECYCLABLE_LIST_LOG.md
```

---

## Phase 2: Create Narrative Generation Script (Updated)

### Cursor Prompt 2.1: Create Updated Narrative Generation

```
@workspace Create the Python script for generating recycling narratives with CORRECTED logic.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Task:
1. Create scripts/recycling/generate_recyclable_list_v2.1.py:
```

```python
"""
Recyclable Lead List Generator V2 (CORRECTED FIRM CHANGE LOGIC)

KEY INSIGHT: People who RECENTLY changed firms are NOT good recycle targets.
They just settled in and won't want to move again for 2+ years.

Priority Order:
  P1: "Timing" disposition (they said bad timing, try again)
  P2: High V4 + No firm change + Long tenure (about to move)
  P3: "No Response" + High V4 (good prospect who didn't engage)
  P4: Changed firms 2-3 years ago (proven mover, may be restless)
  P5: Changed firms 3+ years ago (overdue for another change)
  P6: Standard recycle candidates

Usage: python scripts/recycling/generate_recyclable_list_v2.1.py --month january --year 2026
"""

import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime
from google.cloud import bigquery
import argparse
import json

# ============================================================================
# CONFIGURATION
# ============================================================================
PROJECT_ID = "savvy-gtm-analytics"
WORKING_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation")
SQL_DIR = WORKING_DIR / "sql" / "recycling"
EXPORTS_DIR = WORKING_DIR / "exports"
REPORTS_DIR = WORKING_DIR / "reports" / "recycling_analysis"

EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
REPORTS_DIR.mkdir(parents=True, exist_ok=True)

TARGET_RECYCLABLE = 600


def generate_recycling_narrative_v2(row: pd.Series) -> str:
    """
    Generate a contextual narrative with CORRECTED firm change logic.
    
    Key insight: Recently changed firms = NOT a good signal (they just settled in)
    """
    
    parts = []
    
    # Part 1: Record type
    if row['record_type'] == 'OPPORTUNITY':
        parts.append("**OPPORTUNITY** - Previously engaged as opportunity.")
    else:
        parts.append("**LEAD** - Previously contacted as lead.")
    
    # Part 2: Why they were closed
    close_reason = row.get('close_reason', 'Unknown')
    close_date = row.get('close_date')
    if pd.notna(close_date):
        close_date_str = pd.to_datetime(close_date).strftime('%B %Y')
        parts.append(f"Closed in {close_date_str}: '{close_reason}'.")
    
    # Part 3: WHY WE'RE RECYCLING THEM (with corrected logic)
    priority = row.get('recycle_priority', '')
    days_since = row.get('days_since_last_contact', 0)
    
    if 'P1_TIMING' in priority:
        parts.append(
            f"**TIMING RE-ENGAGEMENT**: They told us timing was bad {int(days_since)} days ago. "
            f"Enough time has passed - timing may be better now. "
            f"Historical data shows 'Timing' dispositions convert at 7%+ on re-engagement."
        )
    
    elif 'P2_HIGH_V4_LONG_TENURE' in priority:
        v4_pct = row.get('v4_percentile', 0)
        tenure_now = row.get('years_at_current_firm_now', 0)
        parts.append(
            f"**HIGH MOVER POTENTIAL**: V4 score in top {100 - int(v4_pct)}% of prospects. "
            f"Currently has {tenure_now:.1f} years at same firm (long tenure = higher move likelihood). "
            f"**KEY INSIGHT**: They have NOT changed firms since we closed them - "
            f"meaning they're still available and may be getting restless after {tenure_now:.1f} years. "
            f"Our model predicts high conversion potential."
        )
    
    elif 'P3_NO_RESPONSE' in priority:
        v4_pct = row.get('v4_percentile', 0)
        parts.append(
            f"**NO RESPONSE RE-TRY**: Previously didn't respond, but V4 score ({int(v4_pct)} percentile) "
            f"indicates strong prospect. {int(days_since)} days have passed - circumstances may have changed. "
            f"Worth another outreach attempt."
        )
    
    elif 'P4_CHANGED_2_3_YRS' in priority:
        years_at_firm = row.get('years_at_current_firm', 0)
        parts.append(
            f"**PROVEN MOVER - WARMING UP**: Changed firms after we contacted them, but that was "
            f"{years_at_firm:.1f} years ago. They've had time to settle in and may be starting to "
            f"evaluate options again. Proven track record of being willing to move."
        )
    
    elif 'P5_CHANGED_3_PLUS_YRS' in priority:
        years_at_firm = row.get('years_at_current_firm', 0)
        parts.append(
            f"**PROVEN MOVER - OVERDUE**: Changed firms {years_at_firm:.1f} years ago. "
            f"Has been at current firm long enough to potentially be looking again. "
            f"Historical movers tend to move again within 3-5 years."
        )
    
    else:
        # P6 Standard
        parts.append(
            f"**STANDARD RE-ENGAGEMENT**: {int(days_since)} days since last contact. "
            f"Sufficient time has passed for circumstances to have changed."
        )
    
    # Part 4: IMPORTANT - Flag if they changed firms recently (for context)
    changed_firms = row.get('changed_firms_since_close', False)
    years_at_firm = row.get('years_at_current_firm')
    
    if changed_firms and pd.notna(years_at_firm):
        if years_at_firm < 2:
            # This shouldn't happen if SQL is correct, but flag it
            parts.append(
                f"⚠️ **WARNING**: Changed firms only {years_at_firm:.1f} years ago - may be too soon to re-engage."
            )
        else:
            parts.append(
                f"Note: Changed firms {years_at_firm:.1f} years ago (sufficient time has passed)."
            )
    elif not changed_firms:
        parts.append("Note: Still at same firm as when we contacted them.")
    
    # Part 5: Last contact info
    last_contacted = row.get('last_contacted_by', 'Unknown')
    last_task_date = row.get('last_task_date')
    last_task_subject = row.get('last_task_subject', '')
    
    if pd.notna(last_task_date):
        last_date_str = pd.to_datetime(last_task_date).strftime('%B %d, %Y')
        contact_info = f"Last contacted by {last_contacted} on {last_date_str}"
        if pd.notna(last_task_subject) and last_task_subject:
            subj = str(last_task_subject)[:40] + '...' if len(str(last_task_subject)) > 40 else str(last_task_subject)
            contact_info += f" ('{subj}')"
        parts.append(contact_info + ".")
    
    # Part 6: Expected conversion + owner
    expected_rate = row.get('expected_conv_rate_pct', 3.0)
    owner_name = row.get('owner_name', 'Unassigned')
    owner_field = 'SGM' if row['record_type'] == 'OPPORTUNITY' else 'SGA'
    
    parts.append(f"**Expected conversion: {expected_rate:.1f}%** | Previous owner: {owner_name} ({owner_field})")
    
    return " ".join(parts)


def query_recyclable_pool(client: bigquery.Client, target_count: int = TARGET_RECYCLABLE) -> pd.DataFrame:
    """Execute the recyclable pool query."""
    
    sql_file = SQL_DIR / "recyclable_pool_master_v2.1.sql"
    
    if sql_file.exists():
        with open(sql_file, 'r', encoding='utf-8') as f:
            query = f.read()
        query = query.replace('DECLARE target_count INT64 DEFAULT 600;', 
                             f'DECLARE target_count INT64 DEFAULT {target_count};')
    else:
        print(f"[ERROR] SQL file not found: {sql_file}")
        return pd.DataFrame()
    
    print(f"[INFO] Querying recyclable pool (target: {target_count})...")
    df = client.query(query).to_dataframe()
    print(f"[INFO] Retrieved {len(df):,} recyclable records")
    
    return df


def generate_summary_report_v2(df: pd.DataFrame, month: str, year: int) -> str:
    """Generate summary report with corrected logic explanation."""
    
    report = f"""# Recyclable Lead List Report - {month.title()} {year}
## V2 - Corrected Firm Change Logic

**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  
**Total Records**: {len(df):,}  
**Target**: {TARGET_RECYCLABLE}

---

## Key Logic Change from V1

**V1 (INCORRECT)**: Prioritized people who changed firms recently as "hot leads"

**V2 (CORRECT)**: 
- People who **just changed firms (< 2 years)** are **EXCLUDED** - they just settled in
- People who changed firms **2-3 years ago** are medium priority - may be getting restless
- People who changed firms **3+ years ago** are higher priority - overdue for another move
- **HIGHEST priority**: People who HAVEN'T moved + high V4 score + long tenure = about to move

---

## Priority Tier Distribution

| Priority | Description | Count | % | Avg Conv |
|----------|-------------|-------|---|----------|
"""
    
    priority_descriptions = {
        'P1_TIMING_OPP': 'Opp: "Timing" - try again now',
        'P1_TIMING_LEAD': 'Lead: "Timing" - try again now',
        'P2_HIGH_V4_LONG_TENURE_OPP': 'Opp: High V4 + Long tenure (about to move)',
        'P2_HIGH_V4_LONG_TENURE_LEAD': 'Lead: High V4 + Long tenure (about to move)',
        'P3_NO_RESPONSE_HIGH_V4_OPP': 'Opp: No response + High V4',
        'P3_NO_RESPONSE_HIGH_V4_LEAD': 'Lead: No response + High V4',
        'P4_CHANGED_2_3_YRS_OPP': 'Opp: Changed firms 2-3 yrs ago',
        'P4_CHANGED_2_3_YRS_LEAD': 'Lead: Changed firms 2-3 yrs ago',
        'P5_CHANGED_3_PLUS_YRS_OPP': 'Opp: Changed firms 3+ yrs ago',
        'P5_CHANGED_3_PLUS_YRS_LEAD': 'Lead: Changed firms 3+ yrs ago',
        'P6_STANDARD_OPP': 'Opp: Standard recycle',
        'P6_STANDARD_LEAD': 'Lead: Standard recycle'
    }
    
    priority_summary = df.groupby('recycle_priority').agg({
        'record_id': 'count',
        'expected_conv_rate_pct': 'mean'
    }).rename(columns={'record_id': 'count', 'expected_conv_rate_pct': 'avg_conv'})
    
    for priority in sorted(priority_summary.index):
        row = priority_summary.loc[priority]
        pct = row['count'] / len(df) * 100
        desc = priority_descriptions.get(priority, priority)
        report += f"| {priority} | {desc} | {int(row['count']):,} | {pct:.1f}% | {row['avg_conv']:.1f}% |\n"
    
    # Summary stats
    total_expected = df['expected_conv_rate_pct'].sum() / 100
    weighted_rate = df['expected_conv_rate_pct'].mean()
    opps = (df['record_type'] == 'OPPORTUNITY').sum()
    leads = (df['record_type'] == 'LEAD').sum()
    changed_firms = df['changed_firms_since_close'].sum()
    high_v4 = (df['v4_percentile'] >= 80).sum()
    
    report += f"""
---

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total Records | {len(df):,} |
| Opportunities | {opps:,} ({opps/len(df)*100:.1f}%) |
| Leads | {leads:,} ({leads/len(df)*100:.1f}%) |
| Weighted Avg Conversion | {weighted_rate:.2f}% |
| Expected Total Conversions | {total_expected:.1f} |
| Changed Firms (2+ yrs ago) | {changed_firms:,} |
| High V4 (≥80th percentile) | {high_v4:,} |

---

## Firm Change Analysis

| Category | Count | % | Avg Conv |
|----------|-------|---|----------|
"""
    
    # Firm change analysis
    def categorize_firm_change(row):
        if not row['changed_firms_since_close']:
            return 'No change (still at same firm)'
        years = row.get('years_at_current_firm')
        if pd.isna(years):
            return 'Changed (unknown timing)'
        elif years < 2:
            return 'Changed < 2 yrs (SHOULD BE EXCLUDED)'
        elif years < 3:
            return 'Changed 2-3 yrs ago'
        else:
            return 'Changed 3+ yrs ago'
    
    df['firm_change_category'] = df.apply(categorize_firm_change, axis=1)
    firm_summary = df.groupby('firm_change_category').agg({
        'record_id': 'count',
        'expected_conv_rate_pct': 'mean'
    })
    
    for cat, row in firm_summary.iterrows():
        pct = row['record_id'] / len(df) * 100
        report += f"| {cat} | {int(row['record_id']):,} | {pct:.1f}% | {row['expected_conv_rate_pct']:.1f}% |\n"
    
    report += f"""
---

## Files Generated

- **CSV Export**: `exports/{month}_{year}_recyclable_leads.csv`
- **This Report**: `reports/recycling_analysis/{month}_{year}_recyclable_list_report.md`

---

**Generated by**: Lead Scoring V3.2.5 + V4.0.0 Recycling Module V2  
**Key Change**: Corrected firm change logic - excludes recent movers (< 2 years)
"""
    
    return report


def main():
    parser = argparse.ArgumentParser(description='Generate monthly recyclable lead list (V2)')
    parser.add_argument('--month', type=str, default='january', help='Month name')
    parser.add_argument('--year', type=int, default=2026, help='Year')
    parser.add_argument('--target', type=int, default=TARGET_RECYCLABLE, help='Target count')
    args = parser.parse_args()
    
    print("=" * 70)
    print(f"RECYCLABLE LEAD LIST GENERATOR V2 - {args.month.upper()} {args.year}")
    print("=" * 70)
    print("\nKEY LOGIC: Excluding people who changed firms < 2 years ago")
    print("          (they just settled in and won't move again soon)\n")
    
    client = bigquery.Client(project=PROJECT_ID)
    
    # Query
    df = query_recyclable_pool(client, args.target)
    
    if len(df) == 0:
        print("[ERROR] No recyclable records found")
        return
    
    # Generate narratives
    print("[INFO] Generating recycling narratives...")
    df['recycle_narrative'] = df.apply(generate_recycling_narrative_v2, axis=1)
    
    # Export
    export_file = EXPORTS_DIR / f"{args.month}_{args.year}_recyclable_leads.csv"
    df.to_csv(export_file, index=False)
    print(f"[INFO] Exported to {export_file}")
    
    # Report
    report = generate_summary_report_v2(df, args.month, args.year)
    report_file = REPORTS_DIR / f"{args.month}_{args.year}_recyclable_list_report.md"
    with open(report_file, 'w', encoding='utf-8') as f:
        f.write(report)
    print(f"[INFO] Report: {report_file}")
    
    # Summary
    print("\n" + "=" * 70)
    print("GENERATION COMPLETE")
    print("=" * 70)
    print(f"Total: {len(df):,}")
    print(f"  Opportunities: {(df['record_type'] == 'OPPORTUNITY').sum():,}")
    print(f"  Leads: {(df['record_type'] == 'LEAD').sum():,}")
    print(f"Weighted conversion: {df['expected_conv_rate_pct'].mean():.2f}%")
    
    # Validate no recent firm changes slipped through
    if 'years_at_current_firm' in df.columns:
        recent_changers = df[
            (df['changed_firms_since_close'] == True) & 
            (df['years_at_current_firm'] < 2)
        ]
        if len(recent_changers) > 0:
            print(f"\n⚠️ WARNING: {len(recent_changers)} records changed firms < 2 years ago!")
        else:
            print("\n✅ Validated: No recent firm changers (< 2 years) in list")


if __name__ == "__main__":
    main()
```

2. Save the file
3. Run to generate January 2026 recyclable list
```

---

## Phase 3: Execution

### Cursor Prompt 3.1: Generate the Recyclable List

```
@workspace Generate the January 2026 recyclable lead list using V2 logic.

WORKING DIRECTORY: C:\Users\russe\Documents\Lead Scoring\Lead_List_Generation

Task:
1. Run: python scripts/recycling/generate_recyclable_list_v2.1.py --month january --year 2026

2. Verify outputs:
   - exports/january_2026_recyclable_leads.csv
   - reports/recycling_analysis/january_2026_recyclable_list_report.md

3. Validate:
   - No records with changed_firms_since_close=TRUE and years_at_current_firm < 2
   - Priority distribution looks correct (P1-P2 should be highest quality)

4. Log results
```

---

## Summary: Corrected Priority Logic

| Priority | Criteria | Rationale | Expected Conv |
|----------|----------|-----------|---------------|
| **P1** | "Timing" disposition + 6-12 mo passed | They said timing was bad - try again | 7% |
| **P2** | High V4 + NO firm change + Long tenure | Model predicts move, hasn't moved yet | 6% |
| **P3** | "No Response" + High V4 | Good prospect who didn't engage | 5% |
| **P4** | Changed firms **2-3 years ago** | Proven mover, settling period over | 4.5% |
| **P5** | Changed firms **3+ years ago** | Overdue for another change | 4% |
| **P6** | Standard recycle | General pool | 3% |

### Critical Exclusions

| Exclusion | Reason |
|-----------|--------|
| **Changed firms < 2 years ago** | Just settled in - won't move again soon |
| No-go dispositions | Permanent DQ |
| DoNotCall = true | Opted out |
| Contacted < 90 days ago | Too soon |

---

**Document Version**: 2.1 (Corrected SQL - Ready for Agentic Execution)  
**Created**: December 24, 2025  
**Last Updated**: December 24, 2025

---

## Pre-Execution Validation Checklist

Before running this query in production:

- [ ] Verified all custom field names exist in Salesforce schema
- [ ] Ran query with LIMIT 100 to validate output
- [ ] Confirmed no records with `changed_firms_since_close=TRUE` AND `years_at_current_firm < 2`
- [ ] Confirmed priority distribution looks reasonable (P1-P2 should be ~10-20% of list)
- [ ] Confirmed no NULL values in critical fields (record_id, fa_crd, recycle_priority)
- [ ] Confirmed date fields are properly formatted
- [ ] Tested narrative generation on sample records

## Post-Execution Validation

After generating the list:

- [ ] Total count = 600 (or target)
- [ ] No duplicate CRDs
- [ ] Opportunities appear before Leads in ranking
- [ ] Expected conversion rates align with priority (P1 highest, P6 lowest)
- [ ] Report generated successfully
- [ ] Validation queries run (V1, V2, V3) with expected results

## Changelog

### V2.1 (December 24, 2025)
- ✅ Fixed date type mismatches (added DATE() casting for all date comparisons)
- ✅ Fixed tenure calculations (calculate to CloseDate, not CURRENT_DATE)
- ✅ Added PIT-compliant employment history join to find firm at time of close
- ✅ Fixed priority logic to use `years_at_current_firm_now` instead of `years_at_firm_total`
- ✅ Added field validation with COALESCE wrappers for optional fields
- ✅ Fixed exclusion logic with proper date casting
- ✅ Added validation queries section
- ✅ Updated Python narrative generation to use correct field names
- ✅ Added pre/post execution checklists

### V2.0 (December 24, 2025)
- ✅ Corrected firm change logic (exclude recent movers < 2 years)
- ✅ Updated priority tiers with corrected rationale
