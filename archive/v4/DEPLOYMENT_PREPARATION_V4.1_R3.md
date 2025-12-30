# V4.1-R3 Deployment Preparation

**Date**: 2025-12-30  
**Model Version**: V4.1.0 R3  
**Status**: ✅ Ready for Deployment (with monitoring)  
**Backtest Confidence**: 66.1% (below 95% threshold, but positive improvement)

---

## Executive Summary

### Backtest Results

| Metric | V4.0.0 Hybrid | V4.1-R3 Hybrid | Improvement |
|--------|---------------|----------------|-------------|
| **Conversion Rate** | 4.56% | 4.83% | **+6.1%** |
| **Expected MQLs (2,800 leads)** | 127 | 135 | **+8 MQLs/month** |
| **Lift vs Baseline** | 1.66x | 1.76x | +0.10x |
| **Statistical Confidence** | - | - | 66.1% |

### Deployment Recommendation

**✅ PROCEED WITH CAUTION**

**Rationale**:
- Positive improvement: +6.1% conversion rate, +8 MQLs/month
- Expected annual impact: +91 MQLs/year
- Statistical confidence below 95% threshold (66.1%)
- Low risk: Can rollback if performance degrades

**Deployment Strategy**: 
- Deploy with parallel monitoring (V4.0.0 vs V4.1-R3)
- Monitor for 1-2 weeks before full rollout
- Re-evaluate after collecting production data

---

## Pre-Deployment Checklist

### Model Validation ✅

- [x] Model trained and validated (R3)
- [x] Test AUC > baseline (0.620 > 0.599 V4.0.0)
- [x] Top decile lift > 1.5x (2.03x achieved)
- [x] Overfitting controlled (AUC gap: 0.075 < 0.15 threshold)
- [x] SHAP interpretability complete (KernelExplainer working)
- [x] Backtest simulation completed
- [x] Backtest shows positive improvement (+6.1%)

### Infrastructure ✅

- [x] Registry updated (`v4/models/registry.json`)
- [x] Production model directory created (`v4/models/v4.1.0/`)
- [x] Inference script updated (`v4/inference/lead_scorer_v4.py`)
- [x] Feature list validated (22 features, 4 removed)
- [x] BigQuery feature table created (`ml_features.v4_prospect_features`)
- [x] Monthly scoring script updated (`pipeline/scripts/score_prospects_monthly.py`)
- [x] Lead list SQL updated (`pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`)

### Pipeline Integration ✅

- [x] Feature engineering SQL updated (`pipeline/sql/v4_prospect_features.sql`)
- [x] V4.1 features integrated (7 new features added)
- [x] Redundant features removed (4 features)
- [x] Table names kept consistent (no breaking changes)
- [x] Scoring pipeline tested (1,571,776 prospects scored successfully)

---

## Deployment Steps

### Phase 1: Pre-Deployment Validation (COMPLETE)

**Status**: ✅ All steps complete

1. ✅ Model training and validation (R3)
2. ✅ Backtest simulation completed
3. ✅ Pipeline integration complete
4. ✅ Feature table created in BigQuery
5. ✅ Monthly scoring tested

### Phase 2: Production Deployment (READY)

**Target Date**: January 2026

#### Step 2.1: Execute Lead List Generation SQL

**Action**: Execute the updated lead list SQL in BigQuery

**File**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

**Expected Output**:
- Table: `ml_features.january_2026_lead_list_v4`
- Rows: ~2,800 leads (200 per SGA × 14 SGAs)
- Columns: All V3 tiers + V4.1 scores + V4.1 features

**Validation**:
- [ ] SQL executes without errors
- [ ] Lead count matches expected (~2,800)
- [ ] V4.1 scores present (v4_score, v4_percentile)
- [ ] V4.1 features present (is_recent_mover, bleeding_velocity_encoded, etc.)
- [ ] Tier distribution looks reasonable

**Command**:
```bash
# Execute in BigQuery Console or via bq CLI
bq query --use_legacy_sql=false < pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql
```

#### Step 2.2: Verify Score Distribution

**Action**: Validate that V4.1 scores are reasonable

**Query**:
```sql
SELECT 
    COUNT(*) as total_leads,
    AVG(v4_score) as avg_score,
    MIN(v4_score) as min_score,
    MAX(v4_score) as max_score,
    PERCENTILE_CONT(v4_score, 0.5) OVER() as median_score,
    COUNT(DISTINCT v4_percentile) as unique_percentiles
FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
```

**Expected Results**:
- Average score: ~0.40 (similar to backtest)
- Score range: 0.15 - 0.70 (similar to backtest)
- Percentiles: 1-100

**Validation**:
- [ ] Score distribution matches backtest expectations
- [ ] No unexpected NULL values
- [ ] Percentiles calculated correctly

#### Step 2.3: Monitor First Week Performance

**Action**: Track conversion rates for first week of January 2026

**Metrics to Track**:
- Top decile conversion rate (target: ≥ 5.0%)
- Overall conversion rate (target: ≥ 4.5%)
- Lift vs baseline (target: ≥ 1.7x)
- MQL count (target: ≥ 130 for 2,800 leads)

**Monitoring Query**:
```sql
-- Track conversions by V4.1 score decile
WITH scored_leads AS (
    SELECT 
        crd,
        v4_score,
        v4_percentile,
        NTILE(10) OVER (ORDER BY v4_score DESC) as score_decile
    FROM `savvy-gtm-analytics.ml_features.january_2026_lead_list_v4`
),
conversions AS (
    SELECT 
        l.crd,
        CASE WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL THEN 1 ELSE 0 END as converted
    FROM scored_leads s
    LEFT JOIN `savvy-gtm-analytics.Salesforce.Lead` l
        ON s.crd = l.CRD__c
    WHERE l.CreatedDate >= '2026-01-01'
)
SELECT 
    score_decile,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(SUM(converted) * 100.0 / COUNT(*), 2) as conv_rate_pct,
    ROUND(SUM(converted) * 100.0 / COUNT(*) / 2.74, 2) as lift_vs_baseline
FROM scored_leads s
LEFT JOIN conversions c ON s.crd = c.crd
GROUP BY score_decile
ORDER BY score_decile;
```

**Validation**:
- [ ] Top decile conversion rate ≥ 5.0%
- [ ] Overall conversion rate ≥ 4.5%
- [ ] No significant regressions vs V4.0.0

### Phase 3: Parallel Monitoring (WEEK 1-2)

**Duration**: 1-2 weeks after deployment

**Action**: Run V4.0.0 and V4.1-R3 in parallel and compare

**Monitoring Plan**:
1. **Daily**: Track conversion rates by score decile
2. **Weekly**: Full lift analysis comparison
3. **Weekly**: Statistical significance test

**Success Criteria**:
- V4.1-R3 conversion rate ≥ V4.0.0 conversion rate
- Top decile lift ≥ 2.0x
- No significant regressions in any decile

**Decision Point** (End of Week 2):
- ✅ **If criteria met**: Proceed to Phase 4 (Full Rollout)
- ⚠️ **If criteria not met**: Investigate and consider rollback

### Phase 4: Full Production Rollout (WEEK 3+)

**Action**: Make V4.1-R3 the primary model

**Steps**:
1. Update all production queries to use V4.1-R3
2. Archive V4.0.0 model (keep for rollback)
3. Update documentation
4. Monitor performance monthly

---

## Performance Monitoring

### Key Metrics Dashboard

| Metric | Target | Current (Backtest) | Monitoring Frequency |
|--------|--------|-------------------|---------------------|
| **Top Decile Lift** | ≥ 2.0x | 2.03x | Daily |
| **Overall Conversion Rate** | ≥ 4.5% | 4.83% | Daily |
| **MQLs per Month (2,800 leads)** | ≥ 130 | 135 | Weekly |
| **Bottom 20% Conversion Rate** | < 2.0% | 1.40% | Weekly |
| **Test AUC-ROC** | ≥ 0.60 | 0.620 | Monthly |

### Monitoring Queries

#### Daily: Top Decile Performance
```sql
SELECT 
    DATE(contacted_date) as date,
    COUNT(*) as leads,
    SUM(converted) as conversions,
    ROUND(SUM(converted) * 100.0 / COUNT(*), 2) as conv_rate_pct
FROM `savvy-gtm-analytics.ml_features.v4_prospect_scores` s
LEFT JOIN conversions c ON s.crd = c.crd
WHERE s.v4_percentile >= 90
  AND DATE(contacted_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY date
ORDER BY date DESC;
```

#### Weekly: Full Lift Analysis
```sql
-- See monitoring query in Step 2.3
```

#### Monthly: Model Performance Review
- Review all metrics vs targets
- Compare to V4.0.0 baseline
- Consider retraining if performance degrades

---

## Rollback Plan

### Rollback Criteria

**Immediate Rollback** (within 24 hours):
- Top decile conversion rate < 3.0% for 2 consecutive days
- Overall conversion rate < 3.5% for 2 consecutive days
- Critical bug or data quality issue

**Planned Rollback** (within 1 week):
- Top decile lift < 1.5x for 1 week
- Overall conversion rate < 4.0% for 1 week
- Statistical significance shows V4.0.0 outperforming V4.1-R3

### Rollback Steps

1. **Revert BigQuery Pipeline**:
   ```sql
   -- Update queries to use V4.0.0 tables
   -- Revert to: ml_features.v4_prospect_features (V4.0.0)
   -- Revert to: ml_features.v4_prospect_scores (V4.0.0)
   ```

2. **Revert Monthly Scoring Script**:
   ```python
   # In pipeline/scripts/score_prospects_monthly.py
   V4_MODEL_DIR = Path(r"...\v4\models\v4.0.0")  # Revert
   V4_FEATURES_FILE = Path(r"...\v4\data\processed\final_features.json")  # Revert
   ```

3. **Update Registry**:
   ```json
   {
     "current_production": "v4.0.0",
     "models": {
       "v4.1.0": {
         "status": "rolled_back",
         "rollback_date": "2026-01-XX",
         "rollback_reason": "..."
       }
     }
   }
   ```

4. **Document Rollback**:
   - Update `v4/EXECUTION_LOG_V4.1.md`
   - Document metrics at time of rollback
   - Document root cause analysis

### Rollback Contacts

- **Data Science**: [Contact]
- **Engineering**: [Contact]
- **Business**: [Contact]

---

## Risk Assessment

### Low Risk Factors ✅

- Positive improvement in backtest (+6.1%)
- Model validated on test set (0.620 AUC)
- Pipeline already tested (1.5M+ prospects scored)
- Rollback plan in place
- Parallel monitoring period planned

### Medium Risk Factors ⚠️

- Statistical confidence below 95% (66.1%)
- Small test set (3,393 leads)
- Production data may differ from test set

### Mitigation Strategies

1. **Parallel Monitoring**: Run V4.0.0 and V4.1-R3 side-by-side for 1-2 weeks
2. **Daily Monitoring**: Track key metrics daily for first week
3. **Quick Rollback**: Can revert within 24 hours if needed
4. **Gradual Rollout**: Start with January 2026 lead list, expand if successful

---

## Expected Impact

### January 2026 Lead List

- **Leads**: 2,800 (200 per SGA × 14 SGAs)
- **Expected MQLs**: 135 (95% CI: 114-158)
- **vs Baseline**: +58 additional MQLs (baseline = 77 at 2.74%)
- **vs V4.0.0**: +8 additional MQLs

### Annual Projection

- **Monthly MQLs**: +8 per month
- **Annual MQLs**: +91 per year
- **Conversion Rate Improvement**: +6.1%

---

## Sign-off

### Pre-Deployment Approval

- [ ] **Data Science**: Model validated and backtested
  - Sign-off: _______________
  - Date: _______________

- [ ] **Engineering**: Pipeline tested and ready
  - Sign-off: _______________
  - Date: _______________

- [ ] **Business**: Business requirements met
  - Sign-off: _______________
  - Date: _______________

### Post-Deployment Validation

- [ ] **Week 1**: Performance metrics validated
  - Sign-off: _______________
  - Date: _______________

- [ ] **Week 2**: No regressions detected
  - Sign-off: _______________
  - Date: _______________

---

## Files Reference

### Model Files
- **Model**: `v4/models/v4.1.0/model.pkl`
- **Features**: `v4/data/v4.1.0/final_features.json`
- **Registry**: `v4/models/registry.json`

### Pipeline Files
- **Feature Engineering**: `pipeline/sql/v4_prospect_features.sql`
- **Monthly Scoring**: `pipeline/scripts/score_prospects_monthly.py`
- **Lead List SQL**: `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`

### Documentation
- **Backtest Results**: `pipeline/reports/V4.1_Backtest_Results.md`
- **Deployment Checklist**: `v4/DEPLOYMENT_CHECKLIST_V4.1.md`
- **Deployment Execution**: `v4/DEPLOYMENT_EXECUTION.md`

---

## Change Log

| Date | Action | Status |
|------|--------|--------|
| 2025-12-30 | Model trained and validated (R3) | ✅ Complete |
| 2025-12-30 | Backtest simulation completed | ✅ Complete |
| 2025-12-30 | Pipeline integration complete | ✅ Complete |
| 2025-12-30 | Deployment preparation document created | ✅ Complete |
| TBD | Lead list SQL executed | ⏳ Pending |
| TBD | Week 1 monitoring complete | ⏳ Pending |
| TBD | Week 2 validation complete | ⏳ Pending |
| TBD | Full production rollout | ⏳ Pending |

---

**Document Version**: 1.0  
**Last Updated**: 2025-12-30  
**Next Review**: After Week 1 monitoring

