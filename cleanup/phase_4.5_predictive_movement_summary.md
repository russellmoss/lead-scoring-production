# Phase 4.5: Create Predictive Movement Structure - Summary

**Date**: December 30, 2025  
**Status**: ✅ Complete

---

## Actions Completed

### 1. Created Directory Structure

```
predictive_movement/
├── README.md                    # Overview and hypotheses
├── docs/
│   └── MODEL_DESIGN.md          # Detailed model design
├── data/
│   └── .gitkeep                # Placeholder for data files
├── sql/
│   └── .gitkeep                # Placeholder for SQL queries
├── scripts/
│   └── .gitkeep                # Placeholder for Python scripts
└── models/
    └── .gitkeep                # Placeholder for model artifacts
```

### 2. Created README.md

**Contents**:
- Overview: Purpose and business value
- Hypotheses: Primary and secondary hypotheses about advisor movement
- Data Sources: Internal (FINTRX, lead data) and external (economic indicators)
- Planned Approach: 4-phase development roadmap
- Key Questions: Timing, firm-specific, and business questions
- File Structure: Directory organization

**Key Sections**:
- **Overview**: Correlates priority advisor movement with economic metrics
- **Hypotheses**: 5 primary hypotheses (economic correlation, seasonality, firm stress, lag effects, firm-specific signals)
- **Data Sources**: Internal (FINTRX, V3/V4 features) and external (BLS, FRED, Yahoo Finance)
- **Planned Approach**: 4 phases (Exploratory → Correlation → Model → Alerting)

### 3. Created MODEL_DESIGN.md

**Contents**:
- Target Variable: 3 options (Binary, Continuous, Multi-class) with recommendation
- Features: Economic indicators, market volatility, internal signals, time-based, interactions
- Model Architecture: 3 options (ARIMAX, XGBoost, LSTM) with recommendation
- Training Strategy: Temporal split, evaluation metrics, baseline models
- Alerting System: Thresholds, integration points, frequency
- Model Maintenance: Retraining schedule, monitoring, drift detection
- Implementation Roadmap: 5-phase plan (12 weeks)
- Success Criteria: Model performance and business impact metrics

**Key Design Decisions**:
- **Target Variable**: Continuous regression (movement rate) - preserves most information
- **Model Architecture**: XGBoost (leverages V4 expertise, good interpretability)
- **Alert Thresholds**: Mean + 1.5 StdDev (high), Mean + 2 StdDev (very high)
- **Integration**: Slack notifications, Tableau dashboard, lead generation pipeline

### 4. Created .gitkeep Files

**Purpose**: Preserve empty directories in Git

**Files Created**:
- `predictive_movement/data/.gitkeep`
- `predictive_movement/sql/.gitkeep`
- `predictive_movement/scripts/.gitkeep`
- `predictive_movement/models/.gitkeep`

---

## Model Purpose

**Predictive RIA Advisor Movement Model** will:

1. **Predict Movement Probability**: Forecast when market conditions favor advisor movement
2. **Optimize Lead Generation**: Adjust lead quotas based on predicted movement
3. **Alert Team**: Notify when high-movement periods are predicted
4. **Resource Allocation**: Optimize SGA assignment during predicted high-movement months

---

## Key Hypotheses Documented

1. **Economic Correlation**: Movement correlates with unemployment, VIX, interest rates
2. **Seasonal Patterns**: Q1 high, Q4 low movement
3. **Firm Stress Signals**: Accelerating bleeding → upcoming departures
4. **Lag Effects**: 0-12 month lags between economic signals and movement
5. **Firm-Specific Early Warning**: Individual firm indicators predict movement

---

## Data Sources Identified

### Internal
- FINTRX historical snapshots
- V3/V4 model features
- Lead conversion data
- Current production tables (recent_movers_v41, firm_bleeding_velocity_v41)

### External (To Explore)
- BLS unemployment data
- S&P 500 / VIX (Yahoo Finance)
- Fed Funds Rate (FRED)
- Consumer Confidence Index (FRED)
- GDP Growth Rate (FRED)

---

## Implementation Roadmap

**Phase 1**: Data Collection (Weeks 1-2)
**Phase 2**: Exploratory Analysis (Weeks 3-4)
**Phase 3**: Model Development (Weeks 5-8)
**Phase 4**: Alerting System (Weeks 9-10)
**Phase 5**: Production Deployment (Weeks 11-12)

**Total Timeline**: 12 weeks

---

## Success Criteria

### Model Performance
- RMSE reduction: >20% vs. naive baseline
- Alert accuracy: >70% true positive rate
- False positive rate: <30%

### Business Impact
- Lead quota optimization: 10-20% improvement during high-movement periods
- Resource allocation: Better SGA assignment
- Proactive lead generation: 2-3x more leads during high-movement periods

---

## Next Steps

1. **Data Collection**: Set up automated data collection for economic indicators
2. **Exploratory Analysis**: Analyze historical movement patterns
3. **Feature Engineering**: Create time-series features from economic data
4. **Model Development**: Build and validate predictive model
5. **Integration**: Integrate with lead generation pipeline

---

**Document Status**: Complete  
**Structure Created**: ✅  
**Documentation Complete**: ✅  
**Ready for Development**: ✅

