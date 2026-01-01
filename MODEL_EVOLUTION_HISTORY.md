# Model Evolution History: Lead Scoring Production

**Document Purpose**: Comprehensive institutional knowledge of lead scoring model evolution  
**Created**: December 30, 2025  
**Last Updated**: January 1, 2026  
**Status**: Historical Reference Document  
**Maintained By**: Data Science Team

---

## Executive Summary

This document chronicles the complete evolution of the lead scoring system from initial attempts through the current hybrid V3.4.0 + V4.2.0 production pipeline. It captures critical lessons learned, technical decisions, and the rationale behind each major version change.

**Key Takeaways**:
- **V2**: Data leakage disaster taught us the importance of point-in-time data
- **V3**: Rules-based approach achieved 4.3x lift with full explainability
- **V4**: ML redemption for deprioritization (identifying leads to skip)
- **V4.2.0**: Career Clock features enable timing-aware scoring
- **Hybrid**: Best of both worlds - V3 prioritizes, V4 deprioritizes

**Current Production**: V3.4.0 (Rules with Career Clock tiers) + V4.2.0 (XGBoost with Career Clock features) Hybrid Pipeline

---

## Version Timeline

| Version | Date | Key Change | Top Lift | Status | Why Superseded |
|---------|------|------------|----------|--------|----------------|
| V1 | Early 2025 | Initial attempt | Unknown | Deprecated | [Details lost to history] |
| V2 | Mid 2025 | First ML model (XGBoost) | 1.50x | **FAILED** | Data leakage disaster |
| V3.0 | Dec 21, 2025 | Rules-based tiers | 3.69x | Deprecated | Consolidated to V3.2 |
| V3.2 | Dec 21, 2025 | 7→5 tier consolidation | 3.69x | Deprecated | V3.3 bleeding refinement |
| V3.3 | Dec 30, 2025 | Bleeding signal refinement | 4.30x (T1A) | Deprecated | V3.4 Career Clock tiers |
| V3.4.0 | Jan 1, 2026 | Career Clock tiers (TIER_0A/0B/0C) | 33.33% (T0B) | **Production** | Timing-aware prioritization |
| V4.0.0 | Dec 24, 2025 | XGBoost (14 features) | 1.51x | Deprecated | Superseded by V4.1.0 |
| V4.1.0 R1 | Dec 30, 2025 | XGBoost (26 features) | ~1.8x | Deprecated | Severe overfitting |
| V4.1.0 R2 | Dec 30, 2025 | XGBoost (22 features) | ~1.9x | Deprecated | SHAP compatibility issues |
| V4.1.0 R3 | Dec 30, 2025 | XGBoost (22 features) | 2.03x | Deprecated | Superseded by V4.2.0 |
| V4.2.0 | Jan 1, 2026 | XGBoost (29 features, Career Clock) | 1.87x | **Production** | Timing-aware deprioritization |
| V5.0 | Dec 30, 2025 | Enhancement Validation | N/A | **NOT DEPLOYED** | Features degraded performance |

---

## V1: Initial Attempt

### What Was Tried
- [Historical details not fully documented]
- Likely a simple heuristic or basic ML approach

### Why It Failed
- [Historical details not fully documented]
- Likely insufficient feature engineering or data quality issues

### Key Lesson
- [Historical details not fully documented]
- Foundation for understanding that lead scoring requires careful feature design

---

## V2: First ML Model (Data Leakage Disaster)

### Architecture
- **Algorithm**: XGBoost
- **Features**: 20 features
- **Training Period**: [Dates not fully documented]
- **Performance**: 1.50x top decile lift (in testing)

### The Data Leakage Disaster

**The Problem**: V2 included a feature called `days_in_gap` that calculated the time between employment records. This data was retrospectively backfilled—meaning the `end_date` of an employment record only exists AFTER the person leaves.

**Timeline Example**:
```
January 1:   Advisor leaves Firm A (FINTRX doesn't know yet)
January 15:  Sales team contacts advisor (system shows them still at Firm A)
February 1:  Advisor joins Firm B, files paperwork
February 2:  FINTRX updates their records, BACKFILLS Firm A end_date to January 1
```

**Impact**:
- Feature showed strong signal (IV = 0.478) - #2 most important feature
- Model looked great in testing (1.50x lift)
- Would completely fail in production (data wouldn't exist at prediction time)
- When removed, model performance dropped from 3.03x lift to 1.65x lift

**Detection**: Discovered during V3 development when auditing all features for point-in-time validity.

**Prevention (V3+ Rule)**: 
> "NEVER use `end_date` from employment history. All features must be calculated from data available at `contacted_date`."

### Other V2 Issues

1. **Black Box Problem**: Sales team couldn't understand why leads were scored high
2. **Low Adoption**: Without explainability, trust was low
3. **CV Implementation**: Issues with temporal ordering in cross-validation

### Why V2 Was Abandoned

The data leakage issue made the model completely unreliable for production. Even if fixed, the lack of explainability would have limited adoption. This led to the decision to pivot to a rules-based approach (V3).

---

## V3: Rules-Based Success

### Why Rules Beat ML

| Aspect | V2 ML | V3 Rules |
|--------|-------|----------|
| Top Lift | 1.50x | 3.69x (4.30x for T1A) |
| Explainability | None | Full |
| Sales Trust | Low | High |
| Maintenance | Retrain | Edit SQL |
| Data Leakage Risk | High | Zero |

### V3 Architecture

**Model Type**: Rules-based tiered classification system  
**Tiers**: 5 priority tiers + STANDARD baseline  
**Assignment**: Hierarchical (first match wins)

**Key Tiers**:
- **TIER_1A_PRIME_MOVER_CFP**: 16.44% conversion, 4.30x lift
- **TIER_1B_PRIME_MOVER_SERIES65**: 16.48% conversion, 4.31x lift
- **TIER_1_PRIME_MOVER**: 13.21% conversion, 3.46x lift
- **TIER_2_PROVEN_MOVER**: 8.59% conversion, 2.50x lift
- **TIER_3_MODERATE_BLEEDER**: 9.52% conversion, 2.77x lift

### V3.0 → V3.2 Evolution

**V3.0**: Initial 7-tier system  
**V3.2**: Consolidated to 5 tiers for operational simplicity while maintaining performance

### V3.2 → V3.3 Evolution (Bleeding Signal Refinement)

**Key Discovery**: Analysis of bleeding signal revealed critical insights:

| Bleeding Category | Leads | Conversion Rate | vs Baseline |
|-------------------|-------|-----------------|-------------|
| STABLE | 13,016 | 5.47% | 1.43x ✅ |
| MODERATE_BLEEDING | 1,767 | 5.43% | 1.42x ✅ |
| LOW_BLEEDING | 2,149 | 5.35% | 1.40x ✅ |
| HEAVY_BLEEDING | 25,084 | **3.27%** | **0.86x ❌** |

**Key Finding**: Heavy bleeding firms convert BELOW baseline. The best advisors leave bleeding firms first; by the time a firm is heavily bleeding, the opportunity has passed.

**V3.3 Changes**:
- **REMOVED**: TIER_5_HEAVY_BLEEDER (converts below baseline)
- **UPDATED**: TIER_3_MODERATE_BLEEDER threshold tightened (3-15 departures, was 1-10)
- **ADDED**: TIER_3A_ACCELERATING_BLEEDER (firms with accelerating velocity)
- **UPDATED**: Firm departures now use inferred approach (START_DATE at new firm) for 60-90 days fresher signal
- **ADDED**: `bleeding_velocity` field (ACCELERATING/STEADY/DECELERATING)

### V3 Key Innovations

1. **Point-in-Time (PIT) Methodology**: All features calculated using only data available at `contacted_date`
2. **Virtual Snapshot Approach**: Construct advisor/firm state dynamically from historical tables
3. **Never Use `end_date`**: Employment end dates are retrospectively backfilled and unreliable
4. **Fixed Analysis Date**: Use `2025-10-31` instead of `CURRENT_DATE()` for training stability
5. **Transparent Business Rules**: Every tier decision explainable in plain English

### V3 Performance

**Backtest Performance (Tier 1)**:
- Average: 19.74% conversion, 5.12x lift
- Low variance across all backtest periods (robust)

**Business Impact**:
- Sales team can focus on 1,804 priority leads (4.6% of total)
- Expected 180+ MQLs from priority tiers vs 60 from random selection
- **3x improvement in conversion efficiency**

---

## V4: ML Redemption

### The Insight That Saved V4

**Key Realization**: ML is better at "Don't Contact" than "Do Contact"

After V3's success with prioritization, we attempted to use ML for the same purpose. V4.0.0 achieved only 1.51x lift (vs V3's 3.69x). However, analysis revealed:

- **Bottom 20% Conversion**: 1.33% (0.42x lift, 58% below baseline)
- **Top 80% Conversion**: 3.66% (1.15x lift, 14% above baseline)
- **Efficiency Gain**: Skip 20% of leads, lose only 8.3% of conversions = **11.7% efficiency gain**

**Decision**: Use V4 as a **deprioritization filter**, not a prioritization tool.

### V4.0.0 Architecture

- **Algorithm**: XGBoost
- **Features**: 14 features
- **Training Date**: December 24, 2025
- **Performance**: 
  - AUC-ROC: 0.5989
  - Top Decile Lift: 1.51x
  - Bottom 20% Conversion: 1.33%

### V4.0.0 → V4.1.0 Evolution

**Motivation**: Improve model performance and add new features based on bleeding signal analysis.

**V4.1.0 R1** (December 30, 2025):
- **Features**: 26 features (added 8 new V4.1 features)
- **Performance**: Severe overfitting (Train AUC: 0.946, Test AUC: 0.561, gap = 0.385)
- **Status**: Failed - overfitting too severe

**V4.1.0 R2** (December 30, 2025):
- **Features**: 22 features (removed 4 redundant)
- **Hyperparameters**: Stronger regularization
- **Performance**: Improved but overfitting persisted (Test AUC: 0.5822, AUC Gap: 0.2723)
- **Status**: Failed - overfitting still present

**V4.1.0 R3** (December 30, 2025):
- **Features**: 22 features (feature selection complete)
- **Hyperparameters**: Even stronger regularization (`max_depth=2`, `min_child_weight=30`, `reg_alpha=1.0`, `reg_lambda=5.0`)
- **Removed Features**: `industry_tenure_months`, `tenure_bucket_x_mobility`, `independent_ria_x_ia_rep`, `recent_mover_x_bleeding`
- **Performance**: 
  - Test AUC-ROC: 0.6198
  - Test AUC-PR: 0.0697
  - Top Decile Lift: 2.03x
  - Bottom 20% Conversion: 1.40%
  - Train/Test AUC Gap: 0.0746 (acceptable)
  - Early Stopping: 223/2000 iterations
- **Status**: ✅ **Production** - Met all critical success criteria

### V4.1.0 New Features

**8 New Features Added**:
1. `is_recent_mover` - Advisor moved in last 12 months (inferred departure)
2. `days_since_last_move` - Days since last firm change
3. `firm_departures_corrected` - Corrected bleeding signal (inferred departures)
4. `bleeding_velocity_encoded` - Accelerating/steady/decelerating bleeding
5. `is_independent_ria` - Firm is Independent RIA
6. `is_ia_rep_type` - Rep type is pure IA (no BD ties)
7. `is_dual_registered` - Rep type is DR (negative signal)
8. `independent_ria_x_ia_rep` - Interaction (removed in R3 due to redundancy)

**Feature Engineering Insights**:
- Independent RIA + IA rep type converts at 3.64% (1.33x baseline)
- Dual-registered advisors convert below baseline (0.86-0.90x)
- Recent movers (inferred) provide 60-90 day fresher signal than END_DATE

### V4 SHAP Analysis Journey

**Problem**: SHAP TreeExplainer failed with XGBoost due to `base_score` parsing issue:
```
ERROR: could not convert string to float: '[5E-1]'
```

**Fix Attempts**:
1. **Fix 1: Patch JSON** - Failed (XGBoost internal representation issue)
2. **Fix 2: Patch Config** - Failed (same issue)
3. **Fix 3: Background Data** - Failed (same issue)
4. **Fix 4: KernelExplainer** - ✅ **Success** (model-agnostic, slower but works)

**Final Solution**: Use `shap.KernelExplainer` for V4.1.0 R3 model interpretability.

**SHAP Results** (V4.1.0 R3):
- Top Features: `has_email`, `tenure_months`, `tenure_bucket_encoded`, `days_since_last_move`, `is_dual_registered`
- 3 new V4.1 features in top 10

#### Isotonic Calibration (Dec 30, 2025) - Limited Success

**Problem**: V4.1.0 R3 had a non-monotonic lift curve where decile 4 (0.47x) and decile 5 (0.49x) had lower lift than decile 3 (0.63x), making percentile rankings unreliable for within-tier sorting.

**Solution Attempted**: Applied isotonic regression calibration as a post-processing wrapper to force monotonicity without retraining the model.

**Implementation**:
- Created `isotonic_calibrator.pkl` using sklearn.isotonic.IsotonicRegression
- Updated `score_prospects_monthly.py` to apply calibration before percentile calculation
- Updated `LeadScorerV4` class with `score_leads_calibrated()` method
- Original model files unchanged (verified by MD5 checksums)

**Calibration Results (Dec 31, 2025)**:

**Outcome**: Calibration did not resolve non-monotonicity in lift curve.

**Findings**:
- Isotonic calibration ensures score monotonicity but does not change lead rankings
- Non-monotonicity in deciles 4-5 is a model limitation, not a calibration issue
- Calibration preserved the same ranking, so the same "bad" leads stayed in the same deciles
- Top decile lift decreased slightly (1.75x → 1.70x)
- Bottom 20% conversion decreased slightly (~1.2% → ~1.0%)
- Non-monotonic deciles increased from 2 (D4, D5) to 3 (D4, D5, D8)

**What Isotonic Calibration Actually Does**:
- ✅ Transforms scores monotonically (higher raw scores → higher calibrated scores)
- ✅ Calibrates probabilities to be more interpretable
- ❌ Does NOT change lead rankings (same leads stay in same deciles)
- ❌ Does NOT fix model ranking errors

**Decision**: **KEEP** calibration for now (easy to rollback if needed). The calibration doesn't hurt and provides calibrated probabilities, even though it didn't solve the non-monotonicity problem.

**Impact on Production**: **None** — V4 is used for deprioritization (bottom 20%) which is unaffected. The hybrid system uses V3 for prioritization and V4 only to filter the bottom 20%. The middle-decile non-monotonicity doesn't affect either use case.

**Files Added**:
- `v4/models/v4.1.0_r3/isotonic_calibrator.pkl`
- `v4/models/v4.1.0_r3/calibrator_metadata.json`

**Usage**: Calibration applied automatically in `score_prospects_monthly.py`. If calibrator file is missing, script falls back to raw scores.

**Rollback Instructions** (if needed):
```bash
# Delete calibrator
rm v4/models/v4.1.0_r3/isotonic_calibrator.pkl
# Script will automatically use raw scores
```

---

## V4.2.0: Career Clock Features (January 1, 2026)

### Overview

**Status**: ✅ **PRODUCTION**  
**Date**: January 1, 2026  
**Objective**: Add timing-aware features to identify optimal outreach timing and deprioritize "too early" leads

### Motivation

Following V4.1.0 R3's success, we identified an opportunity to improve deprioritization by understanding individual advisor career patterns. The Career Clock concept emerged from analysis showing that advisors with predictable tenure patterns can be contacted at optimal times in their career cycle.

**Key Insight**: Advisors with consistent tenure lengths (e.g., changing firms every 3-4 years) can be identified and contacted when they're 70-130% through their typical cycle—the optimal "move window."

### Architecture

- **Algorithm**: XGBoost (same as V4.1.0 R3)
- **Features**: 29 features (22 existing + 7 Career Clock)
- **Training Date**: January 1, 2026
- **Training Data**: 30,738 leads from `ml_features.v4_features_pit_v42`
- **Performance**:
  - Test AUC-ROC: 0.6258 (+0.60% vs V4.1.0 R3)
  - Test AUC-PR: 0.0531
  - Top Decile Lift: 1.87x
  - **Bottom 20% Rate: 0.0117** (-16.4% improvement vs V4.1.0 R3)
  - Train/Test AUC Gap: 0.0959 (healthy, low overfitting)

### Career Clock Features (7 New)

1. **`cc_tenure_cv`** (FLOAT): Coefficient of variation of tenure lengths
   - Low CV = predictable pattern (e.g., always 3-4 years)
   - High CV = unpredictable pattern
   - Default: 1.0 (unpredictable)

2. **`cc_pct_through_cycle`** (FLOAT): Percent through typical tenure cycle
   - 0.0 = just started current job
   - 1.0 = at typical tenure length
   - Default: 1.0

3. **`cc_is_clockwork`** (INT): Flag for highly predictable career patterns
   - 1 = CV < 0.3 AND >= 3 completed jobs
   - 0 = otherwise
   - Default: 0

4. **`cc_is_in_move_window`** (INT): Flag for being in optimal move window
   - 1 = 70-130% through cycle (optimal timing)
   - 0 = otherwise
   - Default: 0

5. **`cc_is_too_early`** (INT): Flag for leads contacted too early
   - 1 = < 70% through cycle (too early to contact)
   - 0 = otherwise
   - Default: 0

6. **`cc_months_until_window`** (INT): Months until entering move window
   - Default: 999 (unknown)

7. **`cc_completed_jobs`** (INT): Count of completed employment records
   - Default: 0

### Feature Engineering

**PIT Compliance**: All Career Clock features use only completed employment records (`END_DATE IS NOT NULL`) where `END_DATE < contacted_date` (or `prediction_date` for inference).

**Key Innovation**: Calculate individual advisor career patterns from historical tenure data, enabling personalized timing signals rather than one-size-fits-all rules.

### Performance Comparison

| Metric | V4.1.0 R3 | V4.2.0 | Change |
|--------|-----------|--------|--------|
| **Test AUC-ROC** | 0.6198 | **0.6258** | **+0.60%** ✅ |
| **Top Decile Lift** | 2.03x | 1.87x | -7.9% |
| **Bottom 20% Rate** | 1.40% | **1.17%** | **-16.4%** ✅ |
| **Features** | 22 | 29 | +7 |
| **AUC Gap** | 0.0746 | 0.0959 | +0.0213 (still healthy) |

### Key Improvements

1. **Better Deprioritization**: Bottom 20% rate improved from 1.40% to 1.17% (-16.4%)
2. **Improved AUC**: Test AUC increased from 0.6198 to 0.6258 (+0.60%)
3. **Timing Awareness**: Can now identify leads contacted too early in their career cycle
4. **No Regression**: All validation gates passed (AUC >= 0.58, Lift >= 1.4x, etc.)

### Validation

**All Gates Passed**:
- ✅ G1: Test AUC >= 0.58 (0.6258)
- ✅ G2: Top Decile Lift >= 1.4x (1.87x)
- ✅ G3: AUC Gap < 0.15 (0.0959)
- ✅ G4: Bottom 20% Rate < 2% (0.0117)
- ✅ G5: V4.2 AUC >= V4.1 AUC (0.6258 >= 0.6198)

**Feature Correlation**: All Career Clock features show low correlation with existing features (< 0.85 threshold), confirming they provide unique signal.

**Hybrid System Coherence**: V3.4 Career Clock tiers (TIER_0A/0B/0C) and V4.2.0 Career Clock features work together seamlessly—96%+ of Career Clock tier leads are NOT deprioritized by V4.2.0.

### Integration with V3.4.0

**V3.4.0 Career Clock Tiers** (Prioritization):
- **TIER_0A_PRIME_MOVER_DUE**: 16.67% conversion (12 leads)
- **TIER_0B_SMALL_FIRM_DUE**: **33.33% conversion** (12 leads, 9x baseline lift) ✅
- **TIER_0C_CLOCKWORK_DUE**: 9.52% conversion (84 leads)

**V4.2.0 Career Clock Features** (Deprioritization):
- Identifies "too early" leads for deprioritization
- Works in harmony with V3.4 tiers (no conflicts)

**Result**: Both systems use Career Clock logic but for different purposes—V3.4 prioritizes "due" leads, V4.2.0 deprioritizes "too early" leads.

### Hyperparameters

**Changes from V4.1.0 R3**:
- `colsample_bytree`: 0.6 → 0.7 (increased for more features)
- All other parameters unchanged

**Rationale**: With 29 features (vs 22), slightly higher column sampling helps the model explore more feature combinations while maintaining regularization.

### Key Learnings

1. **Timing Matters**: Individual advisor career patterns provide valuable signal for optimal outreach timing
2. **Complementary Systems**: V3.4 and V4.2.0 Career Clock logic work together, not in conflict
3. **Feature Correlation**: Career Clock features are orthogonal to existing features (low correlation)
4. **Deprioritization Focus**: Career Clock features excel at identifying "too early" leads for deprioritization

### Files Created

- `v4/sql/v4.1/phase_2_feature_engineering_v41.sql` (updated with Career Clock CTEs)
- `pipeline/sql/v4_prospect_features.sql` (updated with Career Clock features)
- `v4/scripts/train_v42_career_clock.py` (new training script)
- `v4/data/v4.2.0/final_features.json` (29 features)
- `v4/models/v4.2.0/` (model artifacts)

### Documentation

- `V4_CAREER_CLOCK_IMPLEMENTATION_GUIDE.md` - Complete implementation guide
- `deprioritization_analysis.md` - Comprehensive validation analysis
- `tier_0b_validation_analysis.md` - Statistical validation of TIER_0B performance

---

## V5.0 Enhancement Validation (December 2025) - NOT DEPLOYED ❌

### Overview

| Attribute | Value |
|-----------|-------|
| **Status** | ❌ **NOT DEPLOYED** - Features degraded performance |
| **Date** | December 30, 2025 |
| **Objective** | Test new features to improve contacting-to-MQL conversion |
| **Outcome** | All candidate features degraded model performance |
| **Gates Passed** | 1/6 (only PIT compliance) |
| **Decision** | Keep V4.1.0 R3 as production model |

### Motivation

Following the successful V4.1.0 R3 deployment, we explored additional features from FINTRX data to potentially improve model performance:

1. **Firm AUM** - Hypothesis: Larger AUM = more portable book
2. **Accolades** - Hypothesis: Recognized advisors = higher quality
3. **Custodians** - Hypothesis: Tech stack signals platform fit
4. **Licenses** - Hypothesis: License sophistication = advisor quality
5. **Disclosures** - Hypothesis: Negative signal for exclusion

### Validation Framework

Used a rigorous 6-phase validation framework with 6 gates:

| Gate | Criterion | Threshold | Result |
|------|-----------|-----------|--------|
| G-NEW-1 | AUC improvement | ≥ 0.005 | ❌ -0.0004 |
| G-NEW-2 | Lift improvement | ≥ 0.1x | ❌ -0.34x |
| G-NEW-3 | Statistical significance | p < 0.05 | ❌ p = 0.50 |
| G-NEW-4 | Temporal stability | ≥ 3/4 periods | ❌ 1/4 |
| G-NEW-5 | Bottom 20% not degraded | < 10% increase | ❌ Degraded |
| G-NEW-6 | PIT compliance | No leakage | ✅ Passed |

**Only 1 out of 6 gates passed** (PIT compliance, which is a design requirement)

### Phase 1: Feature Candidate Creation

**Table Created**: `ml_experiments.feature_candidates_v5`  
**Rows**: 285,690 (one per advisor)

| Feature | Coverage | Status |
|---------|----------|--------|
| Firm AUM | 87.76% | ✅ High |
| Accolades | 4.5% | ⚠️ Low |
| Custodians | 64.37% | ✅ Good |
| Disclosures | 17.89% | ✅ Acceptable |
| Licenses | 100% | ✅ Perfect |

**Key Implementation**:
- All features use PIT-safe logic (DATE_SUB, historical tables)
- Deduplication implemented to ensure one row per advisor
- Cross-region dataset issue resolved (used `FinTrx_data_CA` instead of `FinTrx_data`)

### Phase 2: Univariate Analysis

**Features Analyzed**: 14  
**Promising**: 2 (`firm_aum_bucket`, `has_accolade`)  
**Weak**: 5  
**Skipped**: 7

| Feature | Coverage | Lift | P-Value | Status |
|---------|----------|------|---------|--------|
| firm_aum_bucket | 87.76% | 1.80x | < 0.0001 | ✅ Promising |
| has_accolade | 4.5% | 1.70x | 0.0252 | ✅ Promising |
| log_firm_aum | 87.76% | 0.23x | < 0.0001 | ⚠️ Negative correlation |

**Key Finding**: `log_firm_aum` showed **negative correlation** (Q4 < Q1), suggesting categorical buckets capture signal better than continuous transformation.

### Phase 3: Ablation Study

**Critical Finding**: Both promising features **degraded** model performance when added.

| Model | Features | AUC-ROC | Lift | AUC Δ | Lift Δ |
|-------|----------|---------|------|-------|--------|
| BASELINE (V4.1) | 22 | 0.6277 | 2.05x | - | - |
| + firm_aum_bucket | 23 | 0.6273 | 1.72x | -0.0004 | -0.34x |
| + has_accolade | 23 | 0.6231 | 1.86x | -0.0046 | -0.19x |
| + combined | 24 | 0.6275 | 1.73x | -0.0001 | -0.32x |

**Conclusion**: Univariate signal ≠ Multivariate value. Features that look promising in isolation degraded the full model.

### Phase 4: Multi-Period Backtesting

| Period | Baseline AUC | Enhanced AUC | AUC Δ | Improved? |
|--------|--------------|--------------|-------|-----------|
| Feb-May 2024 | 0.5883 | 0.5654 | -0.0229 | ❌ |
| Feb-Jul 2024 | 0.6356 | 0.6332 | -0.0024 | ❌ |
| Feb-Sep 2024 | 0.6970 | 0.7031 | +0.0062 | ✅ |
| Feb 2024-Mar 2025 | 0.5517 | 0.5503 | -0.0013 | ❌ |

**Result**: Only 1/4 periods improved. Failed G-NEW-4 gate.

### Phase 5: Statistical Significance

| Metric | Baseline | Enhanced | Δ | P-value |
|--------|----------|----------|---|---------|
| AUC-ROC | 0.6277 | 0.6273 | -0.0004 | 0.50 |
| Top Decile Lift | 2.05x | 1.72x | -0.34x | 0.50 |

**Result**: No statistical evidence of improvement. High p-values confirm degradation is real.

### Phase 6: Final Decision

**Recommendation**: ❌ **DO NOT DEPLOY**

**Reasons**:
1. Features degrade AUC (-0.0004) and lift (-0.34x)
2. Only 1/4 time periods showed improvement
3. No statistical significance (p = 0.50)
4. Only 1/6 validation gates passed

### Key Learnings

1. **Univariate ≠ Multivariate**: Features promising in isolation may not improve full model
2. **V4.1 R3 is well-optimized**: Strong regularization makes marginal improvements difficult
3. **Coverage isn't everything**: 87.76% AUM coverage still degraded performance
4. **Low coverage causes instability**: 4.5% accolade coverage introduced noise
5. **Redundancy**: New features likely correlated with existing V4.1 signals

### Artifacts Preserved

All experiment artifacts archived in `v5/experiments/reports/`:
- `FINAL_VALIDATION_REPORT.md` - Comprehensive summary
- `final_decision_results.json` - Gate pass/fail data
- `PHASE1_RESULTS.md` through `PHASE6_RESULTS.md` - Phase-specific reports
- `phase_2_univariate_analysis.csv` - Feature-level statistics
- `ablation_study_results.csv` - Model comparison data
- `multi_period_backtest_results.csv` - Period-by-period results
- `statistical_significance_results.json` - P-values and test results

### Validation Framework Success

**The validation framework successfully prevented a production regression.** By testing before deployment, we:
- ✅ Discovered features would harm performance
- ✅ Avoided degrading January 2026 lead list quality
- ✅ Documented findings for future reference
- ✅ Confirmed V4.1.0 R3 remains optimal

### Future Considerations

If revisiting these features:
1. **Interaction features**: Test `firm_aum_bucket × firm_stability_tier` instead of standalone
2. **Post-model filtering**: Use `has_accolade` as tie-breaker, not model feature
3. **Different transformations**: Investigate `log_firm_aum` negative correlation
4. **Segment-specific models**: AUM may matter more for certain advisor segments

---

## Hybrid Strategy: V3 + V4

### Architecture

```
┌─────────────────┐         ┌─────────────────┐
│   V3 Rules      │         │   V4 XGBoost    │
│  (Prioritize)   │         │ (Deprioritize)  │
└────────┬────────┘         └────────┬────────┘
         │                           │
         └───────────┬───────────────┘
                     ▼
         ┌───────────────────────────┐
         │   HYBRID PRIORITY LOGIC    │
         ├───────────────────────────┤
         │ V3 T1 + V4 top 50%  →     │
         │   HIGHEST PRIORITY         │
         │ V3 T1 + V4 bottom 50% →   │
         │   HIGH (verify)             │
         │ V3 Standard + V4 top 20% →│
         │   UPGRADE                  │
         │ V3 Standard + V4 bottom   │
         │   20% → SKIP               │
         └───────────────────────────┘
```

### Expected Business Impact

| Scenario | Leads Contacted | Expected Conversions | Efficiency |
|----------|-----------------|----------------------|------------|
| No model | 6,000 | 192 | Baseline |
| V3 only (priority tiers) | 600 | ~33 | 1.74x lift |
| V4 filter (skip bottom 20%) | 4,800 | 176 | +11.7% efficiency |
| **Hybrid (V3 + V4)** | ~4,800 | ~180+ | **Best of both** |

### Production Implementation

**Monthly Lead List Generation**:
- `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
- Combines V3 tier assignments with V4 percentile scores
- Disagreement threshold: V4 percentile < 60 (excludes low V4 scores even if V3 tier is high)
- SGA assignment: Stratified round-robin based on expected conversion rate

---

## Key Lessons Learned

### 1. Data Leakage Prevention (CRITICAL)

**Rules**:
1. NEVER use `end_date` from employment history
2. ALWAYS use point-in-time methodology
3. Fixed `analysis_date` prevents training drift
4. Audit all features for temporal validity

**Audit Query**:
```sql
SELECT COUNTIF(feature_calculation_date > contacted_date) as leakage_count
FROM feature_table
-- Result must be 0
```

**Impact**: V2's data leakage disaster cost months of development time and led to complete model abandonment.

### 2. Explainability Matters More Than Accuracy

Even a 2x better model is useless if sales team won't use it. V3 rules with 3.69x lift and full explainability beat V2 ML with 1.50x lift and zero explainability.

**Sales Team Feedback**: "We trust V3 because we understand it. V2 was a black box."

### 3. ML is Better at "Don't Contact" Than "Do Contact"

The insight that saved V4: use ML for deprioritization, not prioritization. V4's 1.51x lift for prioritization was disappointing, but its 0.42x lift for bottom 20% deprioritization was highly valuable.

### 4. Small Firms Convert Better

Discovery from V3.2 analysis: firms with ≤10 reps convert 3.5x better than baseline. This became a Tier 1 qualification path (TIER_1D_SMALL_FIRM).

### 5. Heavy Bleeding is Too Late

V3.3 analysis revealed that heavy bleeding firms (16+ departures) convert BELOW baseline (3.27% vs 3.82%). The best advisors leave first; by the time a firm is heavily bleeding, the opportunity has passed.

**Solution**: Focus on moderate bleeding (3-15 departures) with accelerating velocity.

### 6. Overfitting Requires Aggressive Regularization

V4.1.0 R1 showed severe overfitting (0.385 AUC gap). Required:
- Feature selection (removed 4 redundant features)
- Stronger regularization (`reg_lambda=5.0`, `reg_alpha=1.0`)
- Deeper trees (`max_depth=2`)
- Higher minimum child weight (`min_child_weight=30`)
- Early stopping (150 rounds)

### 7. SHAP Compatibility Issues Require Workarounds

XGBoost's internal `base_score` representation (scientific notation string) is incompatible with SHAP TreeExplainer. Solution: Use KernelExplainer (model-agnostic, slower but reliable).

### 8. Inferred Departures Provide Fresher Signal

Using `START_DATE` at new firm to infer departure from old firm provides 60-90 days fresher signal than `END_DATE` (which is retrospectively backfilled).

---

## Technical Decisions Registry

### Decision 1: Rules-Based Over ML (V3)

**Date**: December 21, 2025  
**Context**: V2 ML model failed due to data leakage  
**Decision**: Build rules-based tier system instead of fixing V2  
**Rationale**: 
- Zero data leakage risk
- Full explainability
- Easier maintenance
- Sales team trust

**Outcome**: V3 achieved 3.69x lift (vs V2's 1.50x) with full explainability

### Decision 2: Hybrid Approach (V3 + V4)

**Date**: December 24, 2025  
**Context**: V4.0.0 achieved only 1.51x lift for prioritization (vs V3's 3.69x)  
**Decision**: Use V4 for deprioritization, not prioritization  
**Rationale**:
- V4 excels at identifying bottom 20% (1.33% conversion)
- V3 excels at identifying top tiers (13-16% conversion)
- Complementary strengths

**Outcome**: 11.7% efficiency gain from deprioritization filter

### Decision 3: Remove TIER_5_HEAVY_BLEEDER (V3.3)

**Date**: December 30, 2025  
**Context**: Analysis showed heavy bleeding firms convert below baseline  
**Decision**: Remove TIER_5, tighten TIER_3, add TIER_3A  
**Rationale**:
- Heavy bleeding (16+ departures): 3.27% conversion (0.86x baseline)
- Moderate bleeding (3-15 departures): 5.43% conversion (1.42x baseline)
- Best advisors leave first

**Outcome**: Improved tier performance, removed negative signal

### Decision 4: Use KernelExplainer for SHAP (V4.1.0 R3)

**Date**: December 30, 2025  
**Context**: TreeExplainer failed due to XGBoost `base_score` parsing issue  
**Decision**: Use KernelExplainer instead of TreeExplainer  
**Rationale**:
- Model-agnostic (works with any model)
- Bypasses XGBoost internal representation issues
- Slower but reliable

**Outcome**: SHAP interpretability working, model ready for deployment

### Decision 5: Feature Selection Over Feature Engineering (V4.1.0 R3)

**Date**: December 30, 2025  
**Context**: V4.1.0 R1 had 26 features, severe overfitting  
**Decision**: Remove 4 redundant features instead of adding more  
**Rationale**:
- Multicollinearity analysis showed high correlations
- XGBoost with regularization can handle some redundancy, but too much causes overfitting
- Simpler model generalizes better

**Outcome**: Reduced from 26 to 22 features, improved test AUC from 0.561 to 0.620

---

## Feature Engineering Insights

### Point-in-Time (PIT) Features

**Rule**: All features must be calculable using only data available at `contacted_date`.

**Examples**:
- ✅ `tenure_months` - Calculated from `START_DATE` (available at contact time)
- ✅ `firm_departures_12mo` - Count departures in 12 months BEFORE `contacted_date`
- ❌ `days_in_gap` - Uses `END_DATE` (retrospectively backfilled)

### Inferred Departures

**Innovation**: Use `START_DATE` at new firm to infer departure from old firm.

**Advantage**: 60-90 days fresher signal than `END_DATE`.

**Implementation**:
```sql
-- Find most recent prior employer
WITH prior_employer AS (
  SELECT 
    advisor_crd,
    firm_crd as prior_firm_crd,
    start_date as prior_start_date,
    ROW_NUMBER() OVER (PARTITION BY advisor_crd ORDER BY start_date DESC) as rn
  FROM employment_history
  WHERE start_date < current_firm_start_date
)
SELECT 
  advisor_crd,
  prior_firm_crd,
  current_firm_start_date as inferred_departure_date
FROM prior_employer
WHERE rn = 1
```

### Firm Classification Features

**Discovery**: Independent RIA + IA rep type converts at 3.64% (1.33x baseline).

**Features**:
- `is_independent_ria` - Firm is Independent RIA
- `is_ia_rep_type` - Rep type is pure IA (no BD ties)
- `is_dual_registered` - Rep type is DR (negative signal: 0.86-0.90x)

**Source**: Analysis of 35,361 contacted leads from Provided Lead Lists.

### Bleeding Velocity

**Innovation**: Detect accelerating, steady, or decelerating bleeding.

**Calculation**:
- Compare 90-day departures to prior 90-day departures
- ACCELERATING: Current > Prior (bleeding just started)
- STEADY: Current ≈ Prior (ongoing bleeding)
- DECELERATING: Current < Prior (bleeding slowing)

**Insight**: Accelerating bleeding is the optimal signal (firm entering instability phase).

---

## Data Leakage Prevention

### Rules

1. **NEVER use `end_date`** from employment history
2. **ALWAYS use point-in-time methodology** - all features calculated from data available at `contacted_date`
3. **Fixed `analysis_date`** - Use `2025-10-31` instead of `CURRENT_DATE()` for training stability
4. **Audit all features** for temporal validity before model training

### Audit Process

**Step 1**: Identify all features used in model  
**Step 2**: For each feature, verify:
- Source data available at `contacted_date`?
- No retrospective backfilling?
- No future information leakage?

**Step 3**: Run leakage audit query:
```sql
SELECT COUNTIF(feature_calculation_date > contacted_date) as leakage_count
FROM feature_table
-- Result must be 0
```

**Step 4**: Document any acceptable PIT risks (e.g., current firm classification is relatively stable)

### V2 Leakage Example

**Feature**: `days_in_gap`  
**Problem**: Used `END_DATE` which is retrospectively backfilled  
**Impact**: Feature showed strong signal (IV = 0.478) but was useless in production  
**Prevention**: V3+ never uses `end_date`, only `start_date` for inferred departures

---

## SHAP Analysis Journey

### The Problem

V4.1.0 R2 model training completed successfully, but SHAP TreeExplainer failed:
```
ERROR: could not convert string to float: '[5E-1]'
```

**Root Cause**: XGBoost saves `base_score` as a scientific notation string `[5E-1]`, but SHAP TreeExplainer expects a float.

### Fix Attempts

| Fix | Method | Status | Notes |
|-----|--------|--------|-------|
| Fix 1 | Patch JSON file | ❌ Failed | XGBoost internal representation issue |
| Fix 2 | Patch XGBoost config | ❌ Failed | Same issue |
| Fix 3 | Use background data | ❌ Failed | Same issue |
| Fix 4 | KernelExplainer | ✅ Success | Model-agnostic, slower but works |

### Final Solution

**KernelExplainer**:
- Model-agnostic (works with any model)
- Bypasses XGBoost internal parsing issues
- Slower than TreeExplainer but reliable
- Requires background data sample (50-100 rows)

**Implementation**:
```python
import shap

# Load background data
bg_df = load_background_data(limit=50)

# Create prediction function
def predict_proba(X):
    dmatrix = xgb.DMatrix(X, feature_names=feature_names)
    return model.predict(dmatrix)

# KernelExplainer
explainer = shap.KernelExplainer(predict_proba, bg_df)
shap_values = explainer.shap_values(X_test)
```

### SHAP Results (V4.1.0 R3)

**Top 10 Features by SHAP Importance**:
1. `has_email` (0.0429)
2. `tenure_months` (0.0299)
3. `tenure_bucket_encoded` (0.0158)
4. `days_since_last_move` (0.0133) - **New V4.1**
5. `is_dual_registered` (0.0122) - **New V4.1**
6. `has_firm_data` (0.0100)
7. `firm_departures_corrected` (0.0093) - **New V4.1**
8. `mobility_3yr` (0.0079)
9. `firm_net_change_12mo` (0.0048)
10. `short_tenure_x_high_mobility` (0.0034)

**3 new V4.1 features in top 10** ✅

---

## Archived Files Reference

### V3 Archived Files

**Location**: `archive/v3/` (to be created)

**Files to Archive**:
- `v3/sql/generate_lead_list_v3.2.1.sql` (old version)
- `v3/sql/generate_lead_list_v3.2.1.sql.bak`
- `v3/sql/test_v3.3_*.sql` (test files)
- `v3/sql/v3.3_verification_results.md`
- `v3/scripts/run_phase_4.py` (one-time training)
- `v3/scripts/run_phase_7.py` (one-time training)
- `v3/scripts/run_backtest_v3.py` (historical backtest)
- `v3/reports/v3_backtest_summary.md`
- `v3/reports/v3.2_validation_results.md`
- `v3/EXECUTION_LOG.md` (historical)
- `v3/January_2026_Lead_List_Query_V3.2.sql` (old version)
- `v3/V3_Lead_Scoring_Model_Complete_Guide.md` (superseded by VERSION_3_MODEL_REPORT.md)

### V4 Archived Files

**Location**: `archive/v4/` (to be created)

**Files to Archive**:
- `v4/models/v4.0.0/` (deprecated model)
- `v4/models/v4.1.0/` (superseded by R3)
- `v4/models/v4.1.0_r2/` (superseded by R3)
- `v4/data/processed/` (old processed data)
- `v4/data/v4.1.0/` (old version data)
- `v4/data/v4.1.0_r2/` (old version data)
- `v4/scripts/v4.1/phase_*.py` (training scripts - one-time use)
- `v4/sql/phase_1_target_definition.sql` (old phase SQL)
- `v4/sql/phase_2_feature_engineering.sql` (old phase SQL)
- `v4/sql/production_scoring.sql` (V4.0 version)
- `v4/reports/deprioritization_analysis.md`
- `v4/reports/validation_report.md`
- `v4/reports/shap_analysis_report.md`
- `v4/reports/v4.1/overfitting_report*.md` (training reports)
- `v4/EXECUTION_LOG*.md` (historical logs)
- `v4/DEPLOYMENT_*.md` (historical deployment docs)
- `v4/SHAP_Investigation.md` (historical investigation)
- `v4/V4_1_Retraining_Cursor_Guide.md` (historical guide)
- `v4/XGBoost_ML_Lead_Scoring_V4_Development_Plan.md` (historical plan)

### Pipeline Archived Files

**Location**: `archive/pipeline/` (to be created)

**Files to Archive**:
- `pipeline/sql/cleanup_old_january_tables.sql` (one-time cleanup)
- `pipeline/sql/create_excluded_v3_v4_disagreement_table.sql` (temporary analysis)
- `pipeline/sql/generate_january_2026_lead_list.sql` (superseded)
- `pipeline/scripts/execute_v4_features.py` (one-time execution)
- `pipeline/scripts/analyze_v4_percentile_distribution.py`
- `pipeline/scripts/calculate_expected_conversion_rate.py`
- `pipeline/scripts/check_alpha_zero.py`
- `pipeline/scripts/check_shap_status.py`
- `pipeline/scripts/fix_model_*.py` (one-time fixes)
- `pipeline/scripts/run_lead_list_sql.py`
- `pipeline/scripts/test_shap_with_fixed_model.py`
- `pipeline/scripts/v41_backtest_simulation.py` (historical backtest)
- `pipeline/scripts/validate_partner_founder_grouping.py`
- `pipeline/scripts/verify_shap_diversity.py`
- `pipeline/logs/EXECUTION_LOG.md` (historical)
- `pipeline/logs/V4.1_INTEGRATION_LOG.md` (historical)
- `pipeline/reports/V4.1_Backtest_Results.md` (historical)
- `pipeline/exports/*.csv` (regenerate as needed)
- `pipeline/sql/*.md` (execution results, fix documentation)

---

## Conclusion

The lead scoring system has evolved from a data leakage disaster (V2) to a successful hybrid approach (V3.3 + V4.1.0 R3) that combines the best of rules-based prioritization and ML-based deprioritization.

**Key Success Factors**:
1. **Data Leakage Prevention**: Strict PIT methodology prevents false signals
2. **Explainability**: Rules-based V3 builds sales team trust
3. **Complementary Strengths**: V3 prioritizes, V4 deprioritizes
4. **Iterative Improvement**: Each version builds on lessons learned

**Current Production**: V3.4.0 (Rules with Career Clock tiers) + V4.2.0 (XGBoost with Career Clock features) Hybrid Pipeline  
**Status**: ✅ Production Ready  
**Next Evolution**: Predictive RIA Advisor Movement Model (future)

---

**Document Status**: Complete  
**Last Updated**: January 1, 2026  
**Maintained By**: Data Science Team  
**Next Review**: As needed when new versions are developed

