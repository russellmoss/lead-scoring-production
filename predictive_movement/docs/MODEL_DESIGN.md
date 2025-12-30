# Predictive Movement Model Design

**Status**: Design Phase  
**Last Updated**: December 30, 2025  
**Purpose**: Detailed technical design for predictive advisor movement model

---

## Target Variable

### Definition

**Primary Target**: Monthly aggregate metric of "favorable movement conditions"

### Options

#### Option 1: Binary Classification
- **Target**: `is_high_movement_month` (Binary: 0/1)
- **Definition**: Movement rate above historical average
- **Threshold**: Mean + 1 standard deviation
- **Pros**: Simple, clear alerting threshold
- **Cons**: Loses information about magnitude

#### Option 2: Continuous Regression
- **Target**: `movement_rate` (Continuous: 0-1)
- **Definition**: Proportion of advisors who moved in month
- **Calculation**: `(advisors_who_moved / total_advisors) * 100`
- **Pros**: Preserves magnitude information
- **Cons**: More complex, requires regression model

#### Option 3: Multi-Class Classification
- **Target**: `movement_level` (Categorical: Low / Medium / High)
- **Definition**: 
  - Low: < 25th percentile
  - Medium: 25th-75th percentile
  - High: > 75th percentile
- **Pros**: Balanced approach, preserves some magnitude
- **Cons**: Arbitrary thresholds

### Recommended Approach

**Start with Option 2 (Continuous Regression)**:
- Preserves most information
- Can derive binary/multi-class from continuous predictions
- Allows for flexible threshold tuning

**Fallback to Option 1 (Binary)** if:
- Regression model underperforms
- Business needs simple yes/no alerts
- Interpretability is critical

---

## Features (Planned)

### Economic Indicators

| Feature | Source | Update Frequency | Lag Window | Hypothesis |
|---------|--------|------------------|------------|------------|
| **Unemployment Rate** | BLS API | Monthly | 0-3 months | Higher unemployment → more movement (job market pressure) |
| **S&P 500 YoY Return** | Yahoo Finance API | Daily | 0 months | Poor returns → advisor dissatisfaction |
| **VIX Average** | CBOE | Daily | 0 months | High volatility → uncertainty → movement |
| **Fed Funds Rate** | FRED API | Monthly | 0-6 months | Rate changes → business model pressure |
| **Consumer Confidence Index** | FRED API | Monthly | 0-3 months | Low confidence → economic uncertainty |
| **GDP Growth Rate** | FRED API | Quarterly | 0-6 months | Economic growth → stability vs. movement |

### Market Volatility Features

| Feature | Description | Hypothesis |
|---------|-------------|------------|
| **VIX 30-day Average** | Average VIX over last 30 days | Sustained volatility → movement |
| **VIX Spike Indicator** | VIX > 20 (binary) | Volatility spikes → immediate movement |
| **S&P 500 Drawdown** | Max drawdown in last 3 months | Market stress → advisor movement |
| **Market Volatility Trend** | VIX 3-month trend (increasing/decreasing) | Trend direction → movement direction |

### Internal Signals

| Feature | Source | Calculation | Hypothesis |
|---------|--------|-------------|------------|
| **Aggregate Firm Bleeding** | FINTRX | Sum of `firm_departures_corrected` across all firms | More bleeding firms → more movement |
| **Bleeding Velocity Trend** | FINTRX | % of firms with accelerating bleeding | Accelerating bleeding → upcoming movement wave |
| **New Firm Formations** | FINTRX | Count of new firms created | New firms → opportunities → movement |
| **Avg Tenure at Contact** | Lead Data | Average tenure of leads in pipeline | Longer tenure → pent-up movement |
| **Mobility Index** | FINTRX | % of advisors with 3+ moves in last 3 years | Higher mobility → more movement |
| **Firm Size Distribution** | FINTRX | Distribution of firm sizes (small/medium/large) | Small firm concentration → more movement |

### Time-Based Features

| Feature | Description | Hypothesis |
|---------|-------------|------------|
| **Month of Year** | 1-12 (cyclical encoding) | Seasonal patterns (Q1 high, Q4 low) |
| **Quarter** | 1-4 | Quarterly business cycles |
| **Days Since Last High Movement** | Days since last high-movement month | Movement waves cluster |
| **Movement Trend** | 3-month moving average | Trend direction → future movement |

### Interaction Features

| Feature | Description | Hypothesis |
|---------|-------------|------------|
| **High VIX × High Unemployment** | Interaction term | Economic stress combination → movement |
| **Bleeding Velocity × Market Volatility** | Interaction term | Firm stress + market stress → movement |
| **Seasonal × Economic** | Q1 × Unemployment | Seasonal + economic factors combine |

---

## Model Architecture

### Option 1: Time Series Regression

**Approach**: ARIMA with exogenous variables (ARIMAX)

**Pros**:
- Handles temporal dependencies
- Can incorporate lagged economic variables
- Well-established for time series

**Cons**:
- Requires stationary data
- May miss non-linear relationships
- Complex parameter tuning

**Implementation**:
```python
from statsmodels.tsa.arima.model import ARIMA

# ARIMA(p, d, q) with exogenous variables
model = ARIMA(
    movement_rate,
    order=(1, 1, 1),  # p, d, q
    exog=economic_features
)
```

### Option 2: Gradient Boosting (XGBoost/LightGBM)

**Approach**: Tree-based model with time features

**Pros**:
- Handles non-linear relationships
- Feature importance interpretability
- Proven success in V4 model

**Cons**:
- Less explicit temporal modeling
- Requires careful feature engineering for time

**Implementation**:
```python
import xgboost as xgb

model = xgb.XGBRegressor(
    max_depth=4,
    learning_rate=0.05,
    n_estimators=200
)
```

### Option 3: LSTM/RNN (Deep Learning)

**Approach**: Recurrent neural network for sequence modeling

**Pros**:
- Captures complex temporal patterns
- Can learn long-term dependencies
- State-of-the-art for time series

**Cons**:
- Requires large dataset
- Black box (less interpretable)
- Complex training

**Implementation**:
```python
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense

model = Sequential([
    LSTM(50, return_sequences=True),
    LSTM(50),
    Dense(1)
])
```

### Recommended Approach

**Start with Option 2 (XGBoost)**:
- Leverages existing XGBoost expertise from V4
- Good interpretability (feature importance)
- Can handle non-linear relationships
- Easier to debug and iterate

**Consider Option 1 (ARIMAX)** if:
- Time series patterns are very strong
- Need explicit lag modeling
- Want statistical confidence intervals

**Consider Option 3 (LSTM)** if:
- Large dataset available (>5 years)
- Complex temporal patterns emerge
- XGBoost underperforms

---

## Training Strategy

### Data Split

**Temporal Split** (Critical - no data leakage):
- **Training**: 2020-01 to 2024-06 (4.5 years)
- **Validation**: 2024-07 to 2024-12 (6 months)
- **Test**: 2025-01 to 2025-06 (6 months)

**Rolling Window Validation**:
- Use time-series cross-validation
- Train on N months, validate on next M months
- Slide window forward

### Evaluation Metrics

**Primary Metrics**:
- **RMSE** (Root Mean Squared Error): For continuous predictions
- **MAE** (Mean Absolute Error): For interpretability
- **R²** (Coefficient of Determination): For variance explained

**Business Metrics**:
- **Alert Accuracy**: % of high-movement months correctly predicted
- **False Positive Rate**: % of alerts that didn't result in high movement
- **Lead Quota Adjustment Accuracy**: Did adjusted quotas match actual movement?

### Baseline Models

**Naive Baseline**:
- Predict last month's movement rate
- Simple moving average (3-month)

**Seasonal Baseline**:
- Predict based on month-of-year average
- Accounts for seasonality

**Target**: Beat baseline by >20% (RMSE reduction)

---

## Alerting System

### Alert Thresholds

**High Movement Alert**:
- Predicted movement rate > Mean + 1.5 * StdDev
- Or: Predicted movement rate > 75th percentile
- Action: Increase lead quota by 1.5x

**Very High Movement Alert**:
- Predicted movement rate > Mean + 2 * StdDev
- Or: Predicted movement rate > 90th percentile
- Action: Increase lead quota by 2x

**Low Movement Alert**:
- Predicted movement rate < Mean - 1 * StdDev
- Or: Predicted movement rate < 25th percentile
- Action: Maintain baseline quota (no reduction)

### Integration Points

**Slack Notifications**:
- Daily forecast updates
- Weekly movement trend summary
- Alert notifications (high movement predicted)

**Dashboard (Tableau/Looker)**:
- Movement rate forecast (next 1-3 months)
- Economic indicator dashboard
- Historical accuracy metrics
- Lead quota recommendations

**Lead Generation Pipeline**:
- Automatic quota adjustment in lead list generation
- Dynamic tier quotas based on predicted movement
- SGA assignment optimization

### Alert Frequency

**Daily**:
- Forecast update (next 30 days)
- Economic indicator updates

**Weekly**:
- Movement trend analysis
- Model performance review

**Monthly**:
- Model retraining (if needed)
- Alert threshold calibration

---

## Model Maintenance

### Retraining Schedule

**Monthly Retraining**:
- Add new month of data
- Retrain model
- Validate on most recent 3 months

**Quarterly Review**:
- Full model performance audit
- Feature importance review
- Economic indicator relevance check

**Annual Review**:
- Model architecture review
- Consider new model types
- Business metric alignment check

### Monitoring

**Data Quality Checks**:
- Economic data availability
- FINTRX data completeness
- Feature calculation accuracy

**Model Performance Monitoring**:
- Forecast accuracy (RMSE, MAE)
- Alert accuracy (true positive rate)
- Business impact (lead quota adjustments)

**Drift Detection**:
- Feature distribution changes
- Target variable distribution changes
- Model performance degradation

---

## Implementation Roadmap

### Phase 1: Data Collection (Weeks 1-2)
- Set up economic data APIs (FRED, Yahoo Finance)
- Build automated data collection pipeline
- Create feature engineering SQL queries

### Phase 2: Exploratory Analysis (Weeks 3-4)
- Analyze historical movement patterns
- Calculate correlations with economic indicators
- Identify optimal lag windows

### Phase 3: Model Development (Weeks 5-8)
- Build XGBoost model
- Validate on historical data
- Tune hyperparameters
- Compare with baseline models

### Phase 4: Alerting System (Weeks 9-10)
- Build Slack integration
- Create dashboard
- Integrate with lead generation pipeline
- Test alert accuracy

### Phase 5: Production Deployment (Weeks 11-12)
- Deploy model to production
- Set up monitoring
- Document runbooks
- Train team on system

---

## Success Criteria

### Model Performance
- **RMSE Reduction**: >20% vs. naive baseline
- **Alert Accuracy**: >70% true positive rate
- **False Positive Rate**: <30%

### Business Impact
- **Lead Quota Optimization**: 10-20% improvement in conversion during high-movement periods
- **Resource Allocation**: Better SGA assignment during predicted high-movement months
- **Proactive Lead Generation**: 2-3x more leads generated during high-movement periods

---

**Document Status**: Design Phase  
**Next Steps**: Begin Phase 1 (Data Collection)  
**Last Updated**: December 30, 2025

