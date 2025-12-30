# V4.1.0 Deployment Checklist

**Model Version**: V4.1.0 R3  
**Deployment Date**: 2025-12-30  
**Status**: Ready for Production

---

## Pre-Deployment Validation

- [x] Model trained and validated (R3)
- [x] Test AUC > baseline (0.620 > 0.599 V4.0.0)
- [x] Top decile lift > 1.5x (2.03x achieved)
- [x] Overfitting controlled (AUC gap: 0.075 < 0.15 threshold)
- [x] SHAP interpretability complete (KernelExplainer working)
- [x] Registry updated (v4/models/registry.json)
- [x] Production model directory created (v4/models/v4.1.0/)
- [x] Inference script updated (v4/inference/lead_scorer_v4.py)
- [x] Feature list validated (22 features, 4 removed)

---

## Deployment Steps

### 1. BigQuery Pipeline Update
- [ ] Update BigQuery scoring pipeline to use `v4/models/v4.1.0/model.pkl`
- [ ] Update feature engineering SQL to use 22 features (remove 4 redundant)
- [ ] Test scoring query on sample data
- [ ] Verify scores match local inference results

### 2. Salesforce Integration
- [ ] Update Salesforce integration to use V4.1.0 model
- [ ] Update field mappings for new features (if any)
- [ ] Test lead scoring in Salesforce sandbox
- [ ] Verify score distribution matches expected

### 3. Parallel Scoring (Validation Period)
- [ ] Run parallel scoring (V4.0.0 vs V4.1.0) for 1 week
- [ ] Compare lift metrics between versions
- [ ] Monitor conversion rates by score decile
- [ ] Track any anomalies or regressions

### 4. Production Rollout
- [ ] Switch production scoring to V4.1.0
- [ ] Monitor performance metrics daily
- [ ] Track conversion rates and lift
- [ ] Document any issues or improvements

### 5. V4.0.0 Sunset
- [ ] Archive V4.0.0 model artifacts
- [ ] Update documentation to reflect V4.1.0 as current
- [ ] Remove V4.0.0 from active scoring pipeline

---

## Rollback Plan

### Rollback Criteria
If V4.1.0 underperforms, revert to V4.0.0 if:
- Top decile lift drops below 1.5x for 2 consecutive weeks
- Test AUC drops below 0.59 (below V4.0.0 baseline)
- Conversion rate in top decile drops below 5%

### Rollback Steps
1. Revert BigQuery pipeline to use `v4/models/v4.0.0/model.pkl`
2. Revert Salesforce integration to V4.0.0
3. Update registry to mark V4.1.0 as "deprecated"
4. Document rollback reason and metrics

### Rollback Contact
- Data Science: [Contact]
- Engineering: [Contact]
- Business: [Contact]

---

## Performance Monitoring

### Key Metrics to Track
- **Top Decile Lift**: Target ≥ 2.0x (current: 2.03x)
- **Test AUC-ROC**: Target ≥ 0.60 (current: 0.620)
- **Bottom 20% Conversion Rate**: Target < 2% (current: 1.40%)
- **Deprioritization Efficiency**: Target ≥ 11% (current: ~11.7%)

### Monitoring Frequency
- **Daily**: Top decile lift, conversion rates
- **Weekly**: Full lift by decile analysis
- **Monthly**: Model performance review, retraining consideration

---

## Sign-off

### Pre-Deployment Approval
- [ ] **Data Science**: Model validated and ready
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

## Notes

- **Model Location**: `v4/models/v4.1.0/`
- **Features**: 22 (removed 4 redundant: industry_tenure_months, tenure_bucket_x_mobility, independent_ria_x_ia_rep, recent_mover_x_bleeding)
- **SHAP Method**: KernelExplainer (TreeExplainer has compatibility issue, non-blocking)
- **Inference Script**: `v4/inference/lead_scorer_v4.py` (updated for V4.1.0)
- **Registry**: `v4/models/registry.json` (V4.1.0 marked as production, V4.0.0 deprecated)

---

## Change Log

| Date | Action | Status |
|------|--------|--------|
| 2025-12-30 | Model trained and validated (R3) | ✅ Complete |
| 2025-12-30 | Registry updated | ✅ Complete |
| 2025-12-30 | Production model directory created | ✅ Complete |
| 2025-12-30 | Inference script updated | ✅ Complete |
| 2025-12-30 | Deployment checklist created | ✅ Complete |
| 2025-12-30 | BigQuery pipeline SQL created | ✅ Complete |
| 2025-12-30 | Monthly scoring script updated | ✅ Complete |
| 2025-12-30 | Deployment execution guide created | ✅ Complete |
| TBD | BigQuery pipeline SQL executed | ⏳ Pending |
| TBD | Salesforce integration | ⏳ Pending |
| TBD | Parallel scoring validation | ⏳ Pending |
| TBD | Production rollout | ⏳ Pending |

