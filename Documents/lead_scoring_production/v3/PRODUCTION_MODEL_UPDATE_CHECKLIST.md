# Production Model Update Checklist

## Overview
This document lists **all files that must be updated** when changing the production model logic in Version-3. Use this as a checklist to ensure consistency across the entire system.

---

## 🔴 CRITICAL FILES (Must Update)

### 1. Core Tier Scoring Logic
**File:** `sql/phase_4_v3_tiered_scoring.sql`  
**Purpose:** Main tier assignment logic - defines all tier criteria and conversion rates  
**BigQuery Table:** `ml_features.lead_scores_v3`  
**Impact:** ⚠️ **HIGHEST PRIORITY** - This is the source of truth for all tier assignments

**What to Update:**
- Tier criteria (CASE WHEN statements)
- Expected conversion rates
- Expected lift values
- Tier display names
- Priority ranking logic
- Certification detection logic (CFP, Series 65, etc.)

**Dependencies:** 
- Reads from: `ml_features.lead_scoring_features_pit`
- Creates: `ml_features.lead_scores_v3`

---

### 2. Production View
**File:** `sql/phase_7_production_view.sql`  
**Purpose:** Production view that filters and exposes current lead scores  
**BigQuery View:** `ml_features.lead_scores_v3_current`  
**Impact:** ⚠️ **HIGH PRIORITY** - Used by dashboards and reporting

**What to Update:**
- Column selections (if new fields added to tier logic)
- Tier filtering logic (if tier names change)
- View structure (if output schema changes)

**Dependencies:**
- Reads from: `ml_features.lead_scores_v3`
- Creates: `ml_features.lead_scores_v3_current` (VIEW)

---

### 3. Lead List Generator Template
**File:** `sql/generate_lead_list_v3.2.1.sql`  
**Purpose:** Reusable template for generating monthly lead lists  
**Impact:** ⚠️ **HIGH PRIORITY** - Used for all monthly lead list generation

**What to Update:**
- Tier references in tier quota sections
- Tier filtering logic
- Tier priority ranking
- Tier display names

**Dependencies:**
- Reads from: `ml_features.lead_scores_v3` (or `lead_scores_v3_2_12212025` if using consolidated version)
- Used by: `scripts/generate_lead_list.py`

---

### 4. Model Registry (Metadata)
**File:** `models/model_registry_v3.json`  
**Purpose:** Model version tracking and tier definitions documentation  
**Impact:** ⚠️ **HIGH PRIORITY** - Documentation and version control

**What to Update:**
- `model_version` field
- `updated_date` field
- `changes_from_v3.2` or `changes_from_v3.1` array
- `expected_performance` section (lift values)
- `tier_definitions` section (all tier criteria, rates, descriptions)
- `tables.scores` field (if table name changes)

---

## 🟡 IMPORTANT FILES (Should Update)

### 5. Monthly Lead List Queries
**Files:** 
- `January_2026_Lead_List_Query_V3.2.sql`
- Any other month-specific lead list SQL files

**Purpose:** Specific monthly lead list generation with hardcoded tier quotas  
**Impact:** ⚠️ **MEDIUM PRIORITY** - Affects specific month's lead lists

**What to Update:**
- Tier quota values in Section O (if tier structure changes)
- Tier references throughout query
- Tier filtering logic
- Tier display names

**Dependencies:**
- Reads from: `ml_features.lead_scores_v3` (or consolidated version)

---

### 6. Salesforce Sync Query
**File:** `sql/phase_7_salesforce_sync_v3.2_12212025.sql`  
**Purpose:** Exports lead scores to Salesforce for custom field updates  
**Impact:** ⚠️ **MEDIUM PRIORITY** - Affects Salesforce integration

**What to Update:**
- Column mappings (if tier output schema changes)
- Tier filtering logic
- Field name mappings to Salesforce custom fields

**Dependencies:**
- Reads from: `ml_features.lead_scores_v3_2_12212025` (or current production table)

---

### 7. SGA Dashboard View
**File:** `sql/phase_7_sga_dashboard.sql`  
**Purpose:** Dashboard view for reporting and analytics  
**Impact:** ⚠️ **MEDIUM PRIORITY** - Affects dashboard displays

**What to Update:**
- Table/view references (if production table name changes)
- Tier aggregations
- Tier filtering logic

**Dependencies:**
- Reads from: `ml_features.lead_scores_v3_2_12212025` (or current production table)

---

### 8. Python Lead List Generator Script
**File:** `scripts/generate_lead_list.py`  
**Purpose:** Python script that generates lead lists from template  
**Impact:** ⚠️ **LOW-MEDIUM PRIORITY** - Usually doesn't need changes unless template structure changes

**What to Update:**
- Template file path (if template name changes)
- Placeholder replacement logic (if new placeholders added)

**Dependencies:**
- Uses: `sql/generate_lead_list_v3.2.1.sql`

---

## 🟢 OPTIONAL FILES (May Need Updates)

### 9. Feature Engineering (If Features Change)
**File:** `sql/lead_scoring_features_pit.sql`  
**Purpose:** Point-in-time feature engineering - creates all input features  
**Impact:** ⚠️ **ONLY IF FEATURES CHANGE** - Usually doesn't need updates for tier logic changes

**When to Update:**
- If new features are needed for tier logic
- If feature calculations need to change
- If feature names change

**Dependencies:**
- Creates: `ml_features.lead_scoring_features_pit`
- Used by: All tier scoring queries

---

### 10. Phase 7 Deployment Script
**File:** `scripts/run_phase_7.py`  
**Purpose:** Python script that deploys production view  
**Impact:** ⚠️ **LOW PRIORITY** - Usually doesn't need changes

**What to Update:**
- SQL file paths (if file names change)
- Table/view names (if they change)

**Dependencies:**
- Uses: `sql/phase_4_v3_tiered_scoring.sql` and `sql/phase_7_production_view.sql`

---

### 11. Phase 4 Deployment Script
**File:** `scripts/run_phase_4.py`  
**Purpose:** Python script that runs tier scoring  
**Impact:** ⚠️ **LOW PRIORITY** - Usually doesn't need changes

**What to Update:**
- SQL file paths (if file names change)
- Table names (if they change)

**Dependencies:**
- Uses: `sql/phase_4_v3_tiered_scoring.sql`

---

### 12. Documentation Files (For Reference)
**Files:**
- `V3_Lead_Scoring_Model_Report.md`
- `VERSION_3_MODEL_REPORT.md`
- `V3.2_POPULATION_TIER_DISTRIBUTION.md`
- `V3.2_12212025_Cursor_Deployment_Prompt.md`
- `V3.2_Tier_Update_Cursor_Prompt.md`

**Purpose:** Documentation and deployment guides  
**Impact:** ⚠️ **DOCUMENTATION ONLY** - Update for accuracy but not required for functionality

---

## 📋 Update Workflow Checklist

### Step 1: Backup Current Production
- [ ] Backup `sql/phase_4_v3_tiered_scoring.sql` (create backup copy)
- [ ] Backup current production table in BigQuery (if needed)

### Step 2: Update Core Logic
- [ ] Update `sql/phase_4_v3_tiered_scoring.sql` with new tier logic
- [ ] Test tier assignments with sample queries
- [ ] Verify all tier criteria are correct

### Step 3: Update Dependent Views/Queries
- [ ] Update `sql/phase_7_production_view.sql` (if needed)
- [ ] Update `sql/generate_lead_list_v3.2.1.sql` (if tier structure changes)
- [ ] Update `sql/phase_7_salesforce_sync_v3.2_12212025.sql` (if schema changes)
- [ ] Update `sql/phase_7_sga_dashboard.sql` (if table references change)

### Step 4: Update Monthly Queries
- [ ] Update `January_2026_Lead_List_Query_V3.2.sql` (if tier quotas/structure changes)
- [ ] Update any other month-specific queries

### Step 5: Update Metadata
- [ ] Update `models/model_registry_v3.json` with new version info
- [ ] Update tier definitions in registry
- [ ] Update expected performance metrics

### Step 6: Deploy to BigQuery
- [ ] Execute `sql/phase_4_v3_tiered_scoring.sql` in BigQuery
- [ ] Verify table created: `ml_features.lead_scores_v3`
- [ ] Execute `sql/phase_7_production_view.sql` in BigQuery (if view needs update)
- [ ] Verify view created: `ml_features.lead_scores_v3_current`

### Step 7: Validate
- [ ] Run validation queries to check tier distributions
- [ ] Verify tier assignments match expected criteria
- [ ] Check that all dependent queries still work
- [ ] Test lead list generation

### Step 8: Update Documentation (Optional)
- [ ] Update relevant markdown documentation files
- [ ] Update deployment guides if process changed

---

## 🔗 File Dependency Map

```
lead_scoring_features_pit.sql
    ↓
phase_4_v3_tiered_scoring.sql  ← ⭐ MAIN TIER LOGIC
    ↓
    ├──→ lead_scores_v3 (BigQuery Table)
    │       ↓
    │       ├──→ phase_7_production_view.sql → lead_scores_v3_current (View)
    │       ├──→ generate_lead_list_v3.2.1.sql → Monthly Lead Lists
    │       ├──→ January_2026_Lead_List_Query_V3.2.sql → Specific Month Lists
    │       ├──→ phase_7_salesforce_sync_v3.2_12212025.sql → Salesforce Export
    │       └──→ phase_7_sga_dashboard.sql → Dashboard View
    │
    └──→ model_registry_v3.json (Metadata)
```

---

## 🎯 Common Update Scenarios

### Scenario 1: Adding a New Tier
**Files to Update:**
1. ✅ `sql/phase_4_v3_tiered_scoring.sql` - Add new CASE WHEN clause
2. ✅ `models/model_registry_v3.json` - Add tier definition
3. ✅ `sql/generate_lead_list_v3.2.1.sql` - Add tier quota section
4. ✅ `sql/phase_7_production_view.sql` - Usually no change needed
5. ✅ `January_2026_Lead_List_Query_V3.2.sql` - Add tier quota

### Scenario 2: Changing Tier Criteria
**Files to Update:**
1. ✅ `sql/phase_4_v3_tiered_scoring.sql` - Update CASE WHEN logic
2. ✅ `models/model_registry_v3.json` - Update tier criteria description
3. ⚠️ `sql/lead_scoring_features_pit.sql` - Only if new features needed

### Scenario 3: Changing Conversion Rates
**Files to Update:**
1. ✅ `sql/phase_4_v3_tiered_scoring.sql` - Update expected_conversion_rate values
2. ✅ `models/model_registry_v3.json` - Update expected_performance section

### Scenario 4: Renaming Tiers
**Files to Update:**
1. ✅ `sql/phase_4_v3_tiered_scoring.sql` - Update tier name strings
2. ✅ `models/model_registry_v3.json` - Update tier keys and descriptions
3. ✅ `sql/generate_lead_list_v3.2.1.sql` - Update tier references
4. ✅ `sql/phase_7_production_view.sql` - Update if filtering by tier name
5. ✅ `January_2026_Lead_List_Query_V3.2.sql` - Update tier references

### Scenario 5: Changing Production Table Name
**Files to Update:**
1. ✅ `sql/phase_4_v3_tiered_scoring.sql` - Update CREATE TABLE statement
2. ✅ `sql/phase_7_production_view.sql` - Update FROM clause
3. ✅ `sql/generate_lead_list_v3.2.1.sql` - Update table reference
4. ✅ `sql/phase_7_salesforce_sync_v3.2_12212025.sql` - Update FROM clause
5. ✅ `sql/phase_7_sga_dashboard.sql` - Update table reference
6. ✅ `models/model_registry_v3.json` - Update tables.scores field
7. ✅ `January_2026_Lead_List_Query_V3.2.sql` - Update table reference

---

## ⚠️ Important Notes

1. **Always test in a development environment first** before deploying to production
2. **Backup production tables** before making changes
3. **Update model registry** to track version changes
4. **Check all dependent queries** after making changes
5. **Validate tier distributions** match expected patterns
6. **Coordinate with Salesforce team** if sync queries change

---

## 📞 Quick Reference

| File | Priority | When to Update |
|------|----------|----------------|
| `sql/phase_4_v3_tiered_scoring.sql` | 🔴 CRITICAL | Always - main tier logic |
| `sql/phase_7_production_view.sql` | 🔴 CRITICAL | If view structure changes |
| `sql/generate_lead_list_v3.2.1.sql` | 🔴 CRITICAL | If tier structure changes |
| `models/model_registry_v3.json` | 🔴 CRITICAL | Always - version tracking |
| `January_2026_Lead_List_Query_V3.2.sql` | 🟡 IMPORTANT | If tier quotas change |
| `sql/phase_7_salesforce_sync_v3.2_12212025.sql` | 🟡 IMPORTANT | If schema changes |
| `sql/phase_7_sga_dashboard.sql` | 🟡 IMPORTANT | If table references change |
| `sql/lead_scoring_features_pit.sql` | 🟢 OPTIONAL | Only if features change |

---

*Last Updated: January 2026*  
*Model Version: V3.2.1*

