# V4.2.0 Career Clock Implementation Guide - Agentic Readiness Assessment

**Date:** January 1, 2026  
**Reviewer:** AI Assistant (Cursor.ai)  
**Status:** ⚠️ **NOT READY** - Issues Found (See Below)

---

## Executive Summary

The V4.2.0 Career Clock Implementation Guide has **good structure and PIT awareness**, but contains **critical errors** that will cause deployment failures. The guide needs fixes before agentic execution.

**Overall Assessment:**
- ✅ **PIT Compliance:** Strong - explicit PIT requirements documented
- ✅ **Verification Gates:** Comprehensive - 4 verification gates with clear criteria
- ⚠️ **Code Accuracy:** Issues found - CTE name mismatches and incorrect references
- ⚠️ **File Paths:** Need verification - some paths may be incorrect
- ✅ **Model Safety:** Good - includes regression gates and comparison to baseline

---

## Critical Issues Found

### 🔴 **ISSUE 1: Incorrect CTE Reference in Inference JOIN (Line 376)**

**Problem:**
```sql
LEFT JOIN career_clock_features ccf ON fp.crd = ccf.crd
```

**Actual File Structure:**
- The `all_features` CTE uses `bp` (base_prospects) as the main alias
- There is no `fp` alias in the file
- The JOIN should reference `bp.crd` or `cf.crd`

**Fix Required:**
```sql
-- Should be:
LEFT JOIN career_clock_features ccf ON bp.crd = ccf.crd
-- OR add to all_features CTE and join there
```

**Impact:** ⚠️ **HIGH** - Will cause SQL execution failure

---

### 🟡 **ISSUE 2: Missing `cc_avg_prior_tenure_months` in Feature List**

**Problem:**
- Code Snippet 3.1 (feature list JSON) lists 7 Career Clock features
- But `cc_avg_prior_tenure_months` is calculated in CTEs but NOT in the feature list
- Training script (Code Snippet 4.1) also doesn't include it in FEATURE_LIST

**Actual Features Calculated:**
1. `cc_completed_jobs` ✅
2. `cc_avg_prior_tenure_months` ⚠️ (calculated but not in feature list)
3. `cc_tenure_cv` ✅
4. `cc_pct_through_cycle` ✅
5. `cc_is_clockwork` ✅
6. `cc_is_in_move_window` ✅
7. `cc_is_too_early` ✅
8. `cc_months_until_window` ✅

**Fix Required:**
- Add `cc_avg_prior_tenure_months` to feature list JSON (Code Snippet 3.1)
- Add to training script FEATURE_LIST (Code Snippet 4.1)
- Update feature count from 29 to 30 (or remove from CTE if not needed)

**Impact:** ⚠️ **MEDIUM** - Feature mismatch between training and inference

---

### 🟡 **ISSUE 3: Table Name Mismatch in Training**

**Problem:**
- Guide references: `ml_features.v4_features_pit_v42`
- But actual file creates: `ml_features.v4_features_pit_v41` (line 22 of actual file)
- The guide says to update `phase_2_feature_engineering_v41.sql` but create table `v42`

**Fix Required:**
- Either: Update CREATE TABLE to `v4_features_pit_v42` in the SQL
- Or: Update guide to reference correct table name
- Ensure consistency across all references

**Impact:** ⚠️ **MEDIUM** - Table name confusion

---

### 🟡 **ISSUE 4: Missing `mobility` CTE Reference Point**

**Problem:**
- Guide says "Add after the `mobility` CTE" (line 77)
- Need to verify `mobility` CTE exists and find exact insertion point
- Training file has `mobility` CTE, but need to confirm exact location

**Fix Required:**
- Specify exact line number or provide more context
- Or: Add after a more uniquely named CTE

**Impact:** ⚠️ **LOW** - Can be resolved during implementation

---

## PIT Compliance Assessment

### ✅ **STRONG PIT AWARENESS**

**Positive Aspects:**
1. ✅ Explicit PIT requirements documented (lines 67-70)
2. ✅ Code snippets include `END_DATE < contacted_date` filters
3. ✅ Clear distinction between training (`contacted_date`) and inference (`prediction_date`)
4. ✅ Comments emphasize "PIT-safe" throughout

**Code Snippet 1.1 (Training):**
```sql
-- PIT CRITICAL: Only completed jobs BEFORE contact date
AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < b.contacted_date
```
✅ **CORRECT**

**Code Snippet 2.1 (Inference):**
```sql
-- PIT: Only completed jobs before prediction date
AND eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE < bp.prediction_date
```
✅ **CORRECT**

**Verdict:** PIT compliance is well-documented and correctly implemented in code snippets.

---

## Verification Gates Assessment

### ✅ **COMPREHENSIVE GATES**

**Gate 1.1: Feature Distribution Validation**
- ✅ Checks Career Clock feature distribution
- ✅ Validates conversion rates by pattern type
- ✅ Compares to V3.4 validation
- ✅ Clear expected results

**Gate 2.1: Schema Match Validation**
- ✅ Compares training vs inference schemas
- ✅ Checks for missing columns
- ✅ Validates data type consistency
- ✅ Good SQL query for validation

**Gate 4.1: Model Training Gates**
- ✅ G1: Test AUC >= 0.58
- ✅ G2: Top Decile Lift >= 1.4x
- ✅ G3: AUC Gap < 0.15
- ✅ G4: Bottom 20% Rate < 2%
- ✅ G5: **No regression** (V4.2 >= V4.1) - **CRITICAL SAFEGUARD**
- ✅ Career Clock feature importance checks

**Gate 7.1: Final System Validation**
- ✅ Comprehensive validation queries
- ✅ Checks deprioritization by Career Clock status
- ✅ Validates "Too_Early" leads have higher deprioritization

**Verdict:** Verification gates are comprehensive and include critical regression prevention.

---

## Model Safety Assessment

### ✅ **GOOD SAFEGUARDS**

**Positive Aspects:**
1. ✅ **Regression Gate (G5):** Prevents deployment if V4.2 performs worse than V4.1
2. ✅ **Baseline Comparison:** Clear V4.1.0 R3 baseline metrics provided
3. ✅ **Feature Importance Validation:** Checks Career Clock features are used
4. ✅ **Expected Impact:** Realistic expectations (+2-5% AUC, +5-10% lift)
5. ✅ **Hyperparameter Notes:** Suggests starting with same params, adjusting if needed

**Potential Concerns:**
1. ⚠️ **Feature Count Increase:** 22 → 29 features (32% increase) - may need regularization adjustment
2. ⚠️ **No Overfitting Check:** Guide mentions it but doesn't have explicit overfitting gate
3. ⚠️ **No Feature Correlation Check:** Should validate Career Clock features aren't highly correlated with existing features

**Recommendations:**
- Add explicit overfitting check (train/test gap monitoring)
- Add feature correlation validation
- Consider feature selection if Career Clock features are redundant

---

## File Path Verification

### ⚠️ **NEEDS VERIFICATION**

**Files Referenced:**
1. ✅ `v4/sql/v4.1/phase_2_feature_engineering_v41.sql` - **EXISTS**
2. ✅ `pipeline/sql/v4_prospect_features.sql` - **EXISTS**
3. ❓ `v4/data/v4.1.0/final_features.json` - **NEEDS VERIFICATION**
4. ❓ `v4/models/v4.1.0/hyperparameters.json` - **NEEDS VERIFICATION**
5. ❓ `pipeline/scripts/score_prospects_monthly.py` - **NEEDS VERIFICATION**
6. ❓ `v4/scripts/phase_6_model_training.py` - **NEEDS VERIFICATION**

**Action Required:** Verify all file paths exist before execution.

---

## Required Fixes Before Agentic Execution

### **Priority 1: Critical Fixes (Must Fix)**

1. **Fix CTE Reference in Inference JOIN (Line 376)**
   ```sql
   -- CHANGE FROM:
   LEFT JOIN career_clock_features ccf ON fp.crd = ccf.crd
   
   -- CHANGE TO:
   LEFT JOIN career_clock_features ccf ON bp.crd = ccf.crd
   ```
   **OR** add Career Clock features to `all_features` CTE and join there.

2. **Fix Feature List Consistency**
   - Either add `cc_avg_prior_tenure_months` to feature list (30 features total)
   - OR remove it from CTE if not needed for model
   - Ensure training and inference feature lists match exactly

3. **Fix Table Name Consistency**
   - Decide: `v4_features_pit_v41` or `v4_features_pit_v42`?
   - Update all references consistently
   - Update CREATE TABLE statement

### **Priority 2: Important Fixes (Should Fix)**

4. **Add Overfitting Gate**
   - Add explicit check: `train_auc - test_auc < 0.15` (already in G3, but make explicit)
   - Add feature correlation check for Career Clock features

5. **Clarify CTE Insertion Point**
   - Specify exact line number or provide unique CTE name for insertion point
   - Add verification that `mobility` CTE exists

6. **Verify File Paths**
   - Check all referenced files exist
   - Update paths if needed

### **Priority 3: Enhancements (Nice to Have)**

7. **Add Feature Correlation Validation**
   ```sql
   -- Add to Gate 1.1:
   -- Check correlation between Career Clock and existing features
   -- Ensure no r > 0.90 correlations
   ```

8. **Add Rollback Plan**
   - Document how to revert to V4.1.0 if V4.2.0 fails gates
   - Include rollback SQL/queries

---

## Recommended Action Plan

### **Step 1: Fix Critical Issues**
1. Fix CTE reference in Code Snippet 2.2 (line 376)
2. Resolve feature list inconsistency (`cc_avg_prior_tenure_months`)
3. Fix table name consistency

### **Step 2: Add Missing Safeguards**
4. Add feature correlation check to Gate 1.1
5. Add explicit overfitting validation
6. Add rollback documentation

### **Step 3: Verify File Paths**
7. Verify all file paths exist
8. Update guide with correct paths if needed

### **Step 4: Final Review**
9. Run linter on all code snippets
10. Test SQL syntax in BigQuery (dry run)
11. Verify all CTE names match actual files

---

## Final Verdict

**Status:** ⚠️ **NOT READY FOR AGENTIC EXECUTION**

**Reason:** Critical code errors (CTE reference, feature list mismatch) will cause deployment failures.

**Estimated Fix Time:** 15-30 minutes

**After Fixes:** ✅ **READY** - Guide has excellent structure, PIT awareness, and verification gates. Once critical issues are fixed, it will be production-ready.

---

## Positive Aspects (Keep These!)

1. ✅ **Excellent PIT Documentation** - Clear requirements and implementation
2. ✅ **Comprehensive Verification Gates** - 4 gates with clear criteria
3. ✅ **Regression Prevention** - G5 gate prevents model degradation
4. ✅ **Clear Step-by-Step Structure** - Easy to follow
5. ✅ **Expected Impact Documentation** - Realistic expectations
6. ✅ **Model Safety Focus** - Comparison to baseline, importance checks

---

**Next Steps:**
1. Fix critical issues identified above
2. Re-run this assessment
3. Proceed with agentic execution once all issues resolved
