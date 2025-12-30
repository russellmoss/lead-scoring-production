# Predictive RIA Advisor Movement Model

**Status**: Planning / Future Development  
**Started**: December 30, 2025  
**Purpose**: Predict when market conditions favor advisor movement to optimize lead generation timing

---

## Overview

This model will correlate movement of "priority advisors" (those fitting our Ideal Customer Profile) with economic metrics to:

1. **Determine when to alert the team** that conditions favor advisor movement
2. **Identify when market conditions require higher funnel volume** (adjust lead quotas)
3. **Optimize outreach timing** based on predicted movement waves

### Business Value

- **Proactive Lead Generation**: Generate more leads when movement is likely
- **Resource Optimization**: Allocate SGA resources when conversion probability is highest
- **Market Timing**: Understand macro-economic drivers of advisor movement

---

## Hypotheses

### Primary Hypotheses

1. **Economic Correlation**: Advisor movement correlates with economic indicators
   - Higher unemployment → more advisor movement (job market pressure)
   - Market volatility (VIX) → advisor uncertainty → movement
   - Interest rate changes → business model pressure → movement

2. **Seasonal Patterns**: Movement patterns have seasonal components
   - Q1 (January-March): High movement (bonus season, new year resolutions)
   - Q4 (October-December): Lower movement (holiday season, year-end planning)
   - Mid-year: Moderate movement (summer transitions)

3. **Firm-Level Stress Signals**: Firm-level stress signals precede advisor departures
   - Accelerating bleeding velocity → upcoming advisor departures
   - Firm size changes → instability signals
   - Regulatory issues → advisor flight

### Secondary Hypotheses

4. **Lag Effects**: Economic signals have lagged effects on movement
   - 0-3 month lag: Immediate market reactions
   - 3-6 month lag: Delayed business model impacts
   - 6-12 month lag: Long-term structural changes

5. **Firm-Specific Early Warning**: Firm-specific indicators predict movement before aggregate signals
   - Individual firm bleeding → advisor departures
   - Firm classification changes → transition signals

---

## Data Sources

### Internal Data

**Historical Lead Conversion Data**:
- V3/V4 model features and scores
- Lead conversion outcomes (MQL dates, conversion rates)
- Historical lead lists and tier distributions

**FINTRX Historical Snapshots**:
- Employment history (advisor movements over time)
- Firm-level metrics (bleeding, stability, size changes)
- Advisor-level features (tenure, experience, mobility)

**Current Production Features**:
- `ml_features.recent_movers_v41` - Recent mover identification
- `ml_features.firm_bleeding_velocity_v41` - Bleeding velocity trends
- `ml_features.inferred_departures_analysis` - Inferred departure patterns

### External Data (To Explore)

**Economic Indicators**:
- **BLS Unemployment Data**: Monthly unemployment rates
- **S&P 500 / VIX**: Market volatility and returns
- **Fed Funds Rate**: Interest rate changes (FRED API)
- **Consumer Confidence Index**: Economic sentiment

**Industry-Specific**:
- **FINRA Disciplinary Actions**: Regulatory pressure signals
- **RIA Industry News**: Sentiment analysis of industry publications
- **M&A Activity**: Industry consolidation signals

**Data Collection Strategy**:
- Start with publicly available APIs (FRED, Yahoo Finance)
- Explore paid data sources if needed (industry news APIs)
- Build automated data collection pipeline

---

## Planned Approach

### Phase 1: Exploratory Analysis (Weeks 1-2)

**Objectives**:
- Analyze historical movement patterns
- Identify seasonal trends
- Calculate baseline movement rates

**Deliverables**:
- Movement pattern analysis report
- Seasonal index calculations
- Baseline movement rate by month/quarter

**Key Questions**:
- What's the average monthly movement rate?
- Are there clear seasonal patterns?
- How does movement vary by advisor segment (ICP vs. non-ICP)?

### Phase 2: Economic Correlation (Weeks 3-4)

**Objectives**:
- Correlate movement with economic indicators
- Identify lag effects
- Determine predictive signals

**Deliverables**:
- Correlation analysis report
- Lag analysis (0-12 months)
- Feature importance ranking

**Key Questions**:
- Which economic indicators correlate most strongly?
- What's the optimal lag window?
- Are correlations consistent across time periods?

### Phase 3: Predictive Model (Weeks 5-8)

**Objectives**:
- Build predictive model for movement probability
- Validate on historical data
- Test forecasting accuracy

**Deliverables**:
- Trained predictive model
- Validation report
- Forecast accuracy metrics

**Key Questions**:
- What model architecture works best? (Time series, regression, classification)
- How far ahead can we predict? (1 month, 3 months, 6 months)
- What's the minimum acceptable forecast accuracy?

### Phase 4: Alerting System (Weeks 9-10)

**Objectives**:
- Create alerting system for high-movement periods
- Integrate with lead generation pipeline
- Build dashboard for monitoring

**Deliverables**:
- Alerting system (Slack notifications, email)
- Dashboard (Tableau/Looker)
- Integration with lead list generation

**Key Questions**:
- What threshold triggers an alert? (e.g., 2x baseline movement)
- How do we adjust lead quotas based on predictions?
- What's the false positive rate we can tolerate?

---

## Key Questions to Answer

### Timing Questions
- **What's the lag between economic signals and movement?**
  - Immediate (0-1 month): Market volatility reactions
  - Short-term (1-3 months): Business model adjustments
  - Long-term (3-6 months): Structural changes

### Firm-Specific Questions
- **Are there firm-specific early warning indicators?**
  - Individual firm bleeding velocity
  - Firm size changes
  - Regulatory issues

### Business Questions
- **How do we define "good time for movement"?**
  - Above historical average
  - Above baseline + 1 standard deviation
  - Top quartile of movement months

- **How do we adjust lead quotas based on predictions?**
  - Linear scaling: 2x movement → 2x leads
  - Threshold-based: Above threshold → increase by fixed amount
  - Graduated scaling: Different multipliers for different movement levels

---

## File Structure

```
predictive_movement/
├── README.md                    # This file - overview and hypotheses
├── docs/
│   └── MODEL_DESIGN.md          # Detailed model design (TBD)
├── data/
│   └── .gitkeep                # Placeholder for data files
├── sql/
│   └── .gitkeep                # Feature engineering queries
├── scripts/
│   └── .gitkeep                # Analysis and model training scripts
└── models/
    └── .gitkeep                # Trained model artifacts
```

---

## Related Documentation

- **Model Evolution**: See `MODEL_EVOLUTION_HISTORY.md` for lead scoring model history
- **Current Models**: See `models/UNIFIED_MODEL_REGISTRY.json` for V3/V4 model details
- **Movement Analysis**: See `validation/LEAD_SCORING_KEY_FINDINGS.md` for movement insights

---

## Next Steps

1. **Data Collection**: Set up automated data collection for economic indicators
2. **Exploratory Analysis**: Analyze historical movement patterns
3. **Feature Engineering**: Create time-series features from economic data
4. **Model Development**: Build and validate predictive model
5. **Integration**: Integrate with lead generation pipeline

---

**Document Status**: Planning Phase  
**Last Updated**: December 30, 2025  
**Maintainer**: Data Science Team

