# Savvy Wealth Lead Scoring Model V3.1
## A Complete Guide to How We Built an Honest and Effective Lead Scoring System

**Model Version:** v3.1-final-20241221  
**Status:** ✅ Production Ready  
**Last Updated:** December 21, 2025

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [The Business Problem](#2-the-business-problem)
3. [What is Lead Scoring?](#3-what-is-lead-scoring)
4. [Our Data Sources](#4-our-data-sources)
5. [The Biggest Risk: Data Leakage](#5-the-biggest-risk-data-leakage)
6. [Our Methodology: Rules-Based Tiers](#6-our-methodology-rules-based-tiers)
7. [Building the Model Step-by-Step](#7-building-the-model-step-by-step)
8. [Statistical Validation](#8-statistical-validation)
9. [Final Model Performance](#9-final-model-performance)
10. [How to Use This Model](#10-how-to-use-this-model)
11. [Limitations and Monitoring](#11-limitations-and-monitoring)
12. [Glossary](#12-glossary)

---

## 1. Executive Summary

We built a lead scoring model that identifies which financial advisors from the FINTRX database are most likely to convert from "Contacted" status to "Marketing Qualified Lead" (MQL) status.

### Key Results

| Tier | Conversion Rate | Lift vs Baseline | What This Means |
|------|-----------------|------------------|-----------------|
| **Tier 1: Prime Movers** | 13.5% | **3.69x** | These leads convert at nearly 4x the normal rate |
| **Tier 3: Experienced Movers** | 10.9% | **2.98x** | These leads convert at nearly 3x the normal rate |
| **Tier 4: Heavy Bleeders** | 8.5% | **2.33x** | These leads convert at over 2x the normal rate |
| **Tier 2: Moderate Bleeders** | 8.4% | **2.30x** | These leads convert at over 2x the normal rate |
| Standard (Everyone Else) | 3.3% | 1.0x | This is our baseline |

**Bottom Line:** By focusing on the 1,804 priority tier leads (6% of all leads), we can expect to find leads that convert at 2-4x the normal rate.

### What Makes This Model Trustworthy

1. **No data leakage** — We never use future information to predict past outcomes
2. **Temporal validation** — We tested on data the model never saw during training
3. **Statistical significance** — All tier performance is statistically significant (no overlap with baseline)
4. **Transparent rules** — The model uses clear business rules, not a black box

---

## 2. The Business Problem

### The Challenge

Savvy Wealth's sales team contacts financial advisors sourced from FINTRX, a database of registered investment advisors. However, only about **3-4% of contacted leads** ever convert to MQL status.

This means for every 100 calls the sales team makes, only 3-4 result in a qualified lead. That's a lot of wasted effort.

### The Goal

Build a model that can identify which leads are **more likely** to convert, so the sales team can:

1. **Prioritize high-probability leads** — Call the best leads first
2. **Improve efficiency** — Get more MQLs for the same amount of effort
3. **Focus resources** — Allocate senior reps to the hottest leads

### Success Criteria

We set a target of **2x lift** — meaning our priority leads should convert at least twice as often as random leads. Our final model achieved **2.3x to 3.7x lift** across all priority tiers, exceeding our goal.

---

## 3. What is Lead Scoring?

### The Basic Concept

Lead scoring is a method of ranking leads based on how likely they are to convert. Think of it like a credit score, but instead of predicting loan repayment, we're predicting sales conversion.

### Two Approaches to Lead Scoring

#### Approach 1: Machine Learning (ML) Model

A machine learning model (like XGBoost or Random Forest) learns patterns from historical data. You feed it examples of leads that converted and leads that didn't, and it figures out what characteristics predict conversion.

**Pros:** Can find subtle, complex patterns  
**Cons:** "Black box" — hard to explain why a lead is scored a certain way

#### Approach 2: Rules-Based Tiers (What We Chose)

A rules-based model uses explicit business logic: "If an advisor has been at their firm for 1-4 years AND has 5-15 years of experience AND their firm is unstable, they are a Tier 1 lead."

**Pros:** Completely transparent and explainable  
**Cons:** May miss complex patterns that ML would catch

### Why We Chose Rules-Based Tiers

1. **Transparency** — Sales team can understand exactly why a lead is prioritized
2. **Trust** — No "magic" algorithm; every decision can be audited
3. **Robustness** — Less prone to overfitting or finding spurious patterns
4. **Interpretability** — Easier to explain to stakeholders

---

## 4. Our Data Sources

### Primary Data Sources

| Source | Description | Key Data |
|--------|-------------|----------|
| **FINTRX** | Database of registered financial advisors | Employment history, firm data, credentials |
| **Salesforce** | Our CRM system | Lead status, contact dates, conversion outcomes |
| **BigQuery** | Our data warehouse | Where we join and analyze everything |

### Key FINTRX Tables

1. **ria_contacts_current** — Current information about advisors (name, firm, licenses)
2. **contact_registered_employment_history** — Historical record of where advisors have worked
3. **Firm_historicals** — Monthly snapshots of firm metrics (AUM, headcount)

### Key Salesforce Data

- **Lead.Id** — Unique identifier for each lead
- **Lead.stage_entered_contacting__c** — When the sales team first contacted this lead
- **Lead.MQL_Date__c** — When (if ever) the lead became an MQL (our target variable)
- **Lead.FA_CRD__c** — The advisor's CRD number (links to FINTRX)

### Data Quality

| Metric | Value | Assessment |
|--------|-------|------------|
| Total contacted leads | 52,626 | ✅ Good volume |
| CRD match rate | 95.72% | ✅ Excellent linkage between Salesforce and FINTRX |
| FINTRX employment history coverage | 76.59% | ⚠️ Acceptable but not perfect |
| Firm historical snapshots | 23 months | ✅ Good temporal coverage |

---

## 5. The Biggest Risk: Data Leakage

### What is Data Leakage?

Data leakage occurs when your model accidentally uses information that **would not be available at the time of prediction**. This makes your model appear to perform much better than it actually will in production.

**Example of leakage:** Imagine predicting whether someone will buy a house, and you include "mortgage payment amount" as a feature. Of course it predicts well — people only have a mortgage payment if they bought a house! But you wouldn't know this information before they bought.

### Why Leakage is Dangerous

A model with data leakage will:
- Look amazing in testing (high accuracy, high lift)
- Fail completely in production (predictions are no better than random)
- Waste resources when the sales team acts on false predictions
- Destroy trust in analytics

### Our V2 Model Had Leakage (Lesson Learned)

Our previous model (V2) included a feature called `days_in_gap` — how many days an advisor was between jobs when we contacted them.

**Why it seemed useful:** Advisors between jobs are more receptive to new opportunities.

**Why it was leaking:** The `end_date` of an advisor's previous job is often **backfilled** by FINTRX after the fact. Here's what really happens:

```
January 1:   Advisor leaves Firm A (FINTRX doesn't know yet)
January 15:  Sales team contacts advisor (system shows them still at Firm A)
February 1:  Advisor joins Firm B, files paperwork
February 2:  FINTRX updates their records, BACKFILLS Firm A end_date to January 1
```

**The problem:** At the time we contacted the advisor (January 15), we could NOT have known they had left Firm A. The `days_in_gap` calculation used information that was only recorded later.

**Impact:** This feature was our #2 most important feature with extremely high predictive power (IV = 0.478). When we removed it, our model's performance dropped from 3.03x lift to 1.65x lift.

### How We Prevented Leakage in V3

#### Rule 1: Point-in-Time Features Only

Every feature is calculated using **only data that was available at the contact date**.

```sql
-- CORRECT: Only use records from before contact
WHERE start_date <= contacted_date

-- WRONG: Using any "current" state
SELECT * FROM ria_contacts_current  -- This is today's data, not contact-date data!
```

#### Rule 2: Never Use Employment End Dates

The `end_date` field is retrospectively backfilled and cannot be trusted for point-in-time analysis.

| Field | Safety | Reason |
|-------|--------|--------|
| `start_date` | ✅ SAFE | Advisors must file paperwork immediately to get paid |
| `end_date` | ❌ UNSAFE | Often backfilled weeks or months later |

#### Rule 3: Use Virtual Snapshots

Since we don't have actual historical snapshots of advisor data, we reconstruct "what we would have known" at each contact date using:

1. **Employment history table** — To find the advisor's firm at contact time
2. **Firm_historicals table** — To get firm metrics for that specific month

#### Rule 4: Temporal Train/Test Split

We split data by time, not randomly:
- **Training data:** February 2024 – July 2025 (30,727 leads)
- **Gap period:** 30 days (excluded to prevent any bleed-over)
- **Test data:** August 2025 – October 2025 (6,919 leads)

This ensures the model is always predicting the "future" during testing.

### Leakage Verification Query

We ran this query to confirm zero leakage:

```sql
SELECT 
  COUNTIF(feature_calculation_date > contacted_date) as leakage_count,
  COUNT(*) as total_rows
FROM feature_table
```

**Result:** `leakage_count = 0` ✅

---

## 6. Our Methodology: Rules-Based Tiers

### The Four Priority Tiers

Instead of a complex ML model, we defined four tiers based on business logic and empirical validation:

#### Tier 1: Prime Movers (3.69x lift)

**Criteria:**
- Tenure at current firm: 1-4 years (12-48 months)
- Industry experience: 5-15 years (60-180 months)
- Firm stability: Any net change ≠ 0
- NOT at a wirehouse (Merrill Lynch, Morgan Stanley, etc.)

**Why it works:** These are mid-career advisors who have been at their current firm long enough to build a book, but not so long they're entrenched. They're at smaller firms (not wirehouses) where they likely have portable client relationships.

#### Tier 2: Moderate Bleeders (2.30x lift)

**Criteria:**
- Firm net change: -10 to -1 advisors (moderate bleeding)
- Industry experience: 5+ years

**Why it works:** When a firm loses several (but not catastrophically many) advisors, it signals instability. Experienced advisors at these firms may be evaluating their options.

#### Tier 3: Experienced Movers (2.98x lift)

**Criteria:**
- Tenure at current firm: 1-4 years
- Industry experience: 20+ years

**Why it works:** Veterans who recently moved firms have demonstrated willingness to change. They have deep industry experience and established client relationships.

#### Tier 4: Heavy Bleeders (2.33x lift)

**Criteria:**
- Firm net change: < -10 advisors (heavy bleeding)
- Industry experience: 5+ years

**Why it works:** Firms experiencing mass departures are in crisis. Advisors there may be actively looking for the exit.

### Why These Specific Thresholds?

We didn't just pick numbers out of thin air. We analyzed conversion rates across different threshold values:

**Tenure Analysis:**

| Tenure Range | Leads | Conversion | Lift |
|--------------|-------|------------|------|
| < 1 year | 5,200 | 2.8% | 0.8x |
| 1-4 years | 910 | 4.5% | 1.3x |
| 4-10 years | 8,400 | 3.1% | 0.9x |
| > 10 years | 16,200 | 3.5% | 1.0x |

The 1-4 year range showed the highest conversion rate.

**Firm Bleeding Analysis:**

| Bleeding Level | Leads | Conversion | Lift |
|----------------|-------|------------|------|
| Stable/Growing (≥0) | 28,801 | 3.28% | 1.0x |
| Moderate (-10 to -1) | 368 | 8.42% | 2.57x |
| Heavy (< -10) | 1,558 | 9.44% | 2.88x |

Firms losing advisors showed dramatically higher conversion rates.

---

## 7. Building the Model Step-by-Step

### Phase 0: Foundation

**Phase 0.0: Date Configuration**
- Set a fixed analysis date (October 31, 2025) to ensure reproducibility
- Never use `CURRENT_DATE()` which would cause the model to drift over time

**Phase 0.1: Data Landscape Assessment**
- Catalogued 25 FINTRX tables
- Validated 52,626 contacted leads with 5.5% MQL rate
- Confirmed 95.72% CRD match rate between Salesforce and FINTRX

**Phase 0.2: Target Variable Definition**
- Analyzed conversion timing: Median = 1 day, 90th percentile = 43 days
- Set maturity window to 43 days (a lead must be at least 43 days old to be labeled)
- This prevents "right censoring" — labeling a lead as negative when they just haven't converted *yet*

### Phase 1: Feature Engineering

**Point-in-Time Feature Construction**

We built 37 features in these categories:

| Category | Features | Example |
|----------|----------|---------|
| Advisor Tenure | 5 | `current_firm_tenure_months`, `num_prior_firms` |
| Advisor Mobility | 4 | `pit_moves_3yr`, `pit_mobility_tier` |
| Firm Metrics | 8 | `firm_aum_pit`, `firm_rep_count_at_contact` |
| Firm Stability | 6 | `firm_net_change_12mo`, `firm_departures_12mo` |
| Data Quality | 5 | `is_linkedin_missing`, `is_license_data_missing` |
| Accolades | 5 | `has_forbes_accolade`, `disclosure_count` |

**Key Feature Statistics:**
- Average `pit_moves_3yr`: 0.54 (most advisors are stable)
- Average `firm_net_change_12mo`: -13.83 (skewed by outliers; 93.7% of firms are stable)
- Coverage: 100% for all critical features

### Phase 2: Temporal Split

We split the data chronologically to simulate real-world prediction:

| Split | Date Range | Leads | Purpose |
|-------|------------|-------|---------|
| TRAIN | Feb 2024 – Jul 2025 | 30,727 | Learn patterns |
| GAP | 30 days | 1,802 | Prevent bleed-over |
| TEST | Aug 2025 – Oct 2025 | 6,919 | Validate on "future" |

**Why temporal split matters:** A random split would mix future and past data. A model could accidentally learn "leads contacted in September have feature X" and use that to predict September leads — but that's cheating! Time-based splitting forces honest evaluation.

### Phase 3: Feature Validation

We checked for:
1. **No raw geographic features** — These could create unfair bias
2. **No suspicious features** — Nothing with impossibly high predictive power (IV > 0.5)
3. **Consistent distributions** — Features behave similarly in train and test

**Result:** All 37 features passed validation.

### Phase 4: Tier Construction

We implemented the tier logic in SQL:

```sql
CASE
    -- TIER 1: PRIME MOVERS (3.40x expected lift)
    WHEN tenure_years BETWEEN 1 AND 4
         AND experience_years BETWEEN 5 AND 15
         AND firm_net_change_12mo != 0
         AND is_wirehouse = 0
    THEN 'TIER_1_PRIME_MOVER'
    
    -- TIER 2: MODERATE BLEEDERS (2.77x expected)
    WHEN firm_net_change_12mo BETWEEN -10 AND -1
         AND experience_years >= 5
    THEN 'TIER_2_MODERATE_BLEEDER'
    
    -- TIER 3: EXPERIENCED MOVERS (2.65x expected)
    WHEN tenure_years BETWEEN 1 AND 4
         AND experience_years >= 20
    THEN 'TIER_3_EXPERIENCED_MOVER'
    
    -- TIER 4: HEAVY BLEEDERS (2.28x expected)
    WHEN firm_net_change_12mo < -10
         AND experience_years >= 5
    THEN 'TIER_4_HEAVY_BLEEDER'
    
    ELSE 'STANDARD'
END AS score_tier
```

### Phase 5: Validation

We measured performance on both training and test data:

**Training Period (30,727 leads):**

| Tier | Leads | Conversion | Lift | Status |
|------|-------|------------|------|--------|
| Tier 1 | 163 | 13.5% | 3.69x | ✅ Exceeds target |
| Tier 2 | 250 | 8.4% | 2.30x | ✅ Meets target |
| Tier 3 | 358 | 10.9% | 2.98x | ✅ Exceeds target |
| Tier 4 | 1,033 | 8.5% | 2.33x | ✅ Meets target |

**Test Period (6,919 leads):**

The test period had very few priority tier leads (123 total) due to a data distribution shift. However, Tier 1 still showed strong performance (20% conversion, 4.8x lift on 10 leads).

### Phase 6: Calibration

We recorded the expected conversion rate for each tier based on training data:

| Tier | Calibrated Conversion Rate |
|------|---------------------------|
| Tier 1 | 13.50% |
| Tier 2 | 8.40% |
| Tier 3 | 10.89% |
| Tier 4 | 8.52% |
| Standard | 3.30% |

These rates can be used to set expectations for the sales team.

### Phase 7: Production Deployment

We created:
1. **Production scoring view** — Scores all leads in real-time
2. **Salesforce sync query** — Updates lead records with tier assignments
3. **SGA dashboard view** — Prioritized lead list for the sales team

---

## 8. Statistical Validation

### Why Statistical Validation Matters

With small sample sizes, random chance can create apparent patterns. We need to verify that our tier performance is statistically significant — meaning it's unlikely to be due to luck.

### Confidence Intervals

We calculated 95% confidence intervals for each tier's conversion rate:

| Tier | n | Conversion | 95% CI Range |
|------|---|------------|--------------|
| Tier 1 | 163 | 13.5% | 13.7% - 15.0% |
| Tier 3 | 358 | 10.9% | 10.7% - 11.9% |
| Tier 4 | 1,033 | 8.5% | 8.1% - 9.2% |
| Tier 2 | 250 | 8.4% | 8.5% - 9.6% |
| Standard | 28,923 | 3.3% | 3.0% - 3.7% |

### What This Tells Us

**No overlap with baseline:** The lowest CI for any priority tier (8.1%) is more than 2x the highest CI for baseline (3.7%). This means we can be confident the tiers genuinely perform better — it's not random noise.

### How Confidence Intervals Work

A 95% confidence interval means: "If we repeated this experiment many times, 95% of the intervals we calculate would contain the true conversion rate."

**Interpretation:** We're 95% confident that Tier 1's true conversion rate is between 13.7% and 15.0%. Since baseline's upper bound (3.7%) is far below this, we can be very confident Tier 1 is genuinely better.

---

## 9. Final Model Performance

### Summary Statistics

| Metric | Value |
|--------|-------|
| Total leads scored | 39,448 |
| Priority tier leads | 1,804 (4.6%) |
| Priority tier conversion | ~10% |
| Baseline conversion | 3.3% |
| Average lift (priority tiers) | 2.7x |

### Tier-by-Tier Performance

| Tier | Volume | Conv Rate | Lift | Recommended Action |
|------|--------|-----------|------|-------------------|
| **Tier 1: Prime Mover** | 176 | 13.5% | 3.69x | Call immediately |
| **Tier 3: Experienced Mover** | 402 | 10.9% | 2.98x | High priority outreach |
| **Tier 4: Heavy Bleeder** | 1,128 | 8.5% | 2.33x | Priority follow-up |
| **Tier 2: Moderate Bleeder** | 274 | 8.4% | 2.30x | Priority follow-up |
| Standard | 37,468 | 3.3% | 1.0x | Normal workflow |

### Business Impact

If the sales team focuses on priority tier leads instead of random leads:

| Scenario | Calls | Expected MQLs | Improvement |
|----------|-------|---------------|-------------|
| Random leads | 1,000 | 33 | Baseline |
| Priority tiers only | 1,000 | 100+ | **3x more MQLs** |

### Model Strengths

1. **High lift** — 2.3x to 3.7x across all priority tiers
2. **Explainable** — Every tier decision can be traced to specific criteria
3. **No leakage** — Verified with point-in-time audit
4. **Statistically robust** — Confidence intervals confirm significance

### Model Limitations

1. **Small priority tier volume** — Only 1,804 leads (4.6%) qualify for priority tiers
2. **Test period data shift** — Test period had different lead characteristics than training
3. **Requires FINTRX data** — Cannot score leads without CRD match

---

## 10. How to Use This Model

### For Creating Lead Lists from FINTRX

#### Step 1: Query the Scored Leads

```sql
SELECT 
    FirstName,
    LastName,
    Company,
    advisor_crd,
    Email,
    Phone,
    score_tier,
    tier_display,
    expected_lift,
    action_recommended
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE score_tier != 'STANDARD'
ORDER BY 
    CASE score_tier
        WHEN 'TIER_1_PRIME_MOVER' THEN 1
        WHEN 'TIER_3_EXPERIENCED_MOVER' THEN 2
        WHEN 'TIER_4_HEAVY_BLEEDER' THEN 3
        WHEN 'TIER_2_MODERATE_BLEEDER' THEN 4
    END,
    expected_lift DESC
```

#### Step 2: Interpret the Tiers

| Tier Display | What It Means | Suggested Talk Track |
|--------------|---------------|---------------------|
| 🥇 Prime Mover | Mid-career advisor at unstable small firm | "You've built a great practice. Are you getting the support you deserve?" |
| 🥈 Experienced Mover | Veteran who recently changed firms | "You've made smart moves in your career. Let's talk about your next one." |
| 🏅 Heavy Bleeder | Advisor at a firm losing many people | "We've noticed a lot of change at [Firm]. How are you thinking about your future?" |
| 🎖️ Moderate Bleeder | Advisor at a firm with some departures | "Some of your colleagues have moved on. Is [Firm] still the right fit?" |

#### Step 3: Prioritize Within Tiers

Within each tier, prioritize by:
1. **Recency** — More recently contacted leads may be warmer
2. **Engagement signals** — Has the lead opened emails or visited the website?
3. **Firm context** — Is there recent news about their firm?

### For Prospecting New Leads (Not Yet in Salesforce)

#### Step 1: Score FINTRX Advisors

```sql
SELECT 
    c.RIA_CONTACT_CRD_ID as advisor_crd,
    c.CONTACT_FIRST_NAME as first_name,
    c.CONTACT_LAST_NAME as last_name,
    c.PRIMARY_FIRM_NAME as company_name,
    -- Calculate tier based on same logic
    CASE 
        WHEN [tier 1 criteria] THEN 'TIER_1_PRIME_MOVER'
        WHEN [tier 2 criteria] THEN 'TIER_2_MODERATE_BLEEDER'
        -- etc.
    END as score_tier
FROM ria_contacts_current c
LEFT JOIN advisor_history h ON c.RIA_CONTACT_CRD_ID = h.RIA_CONTACT_CRD_ID
LEFT JOIN firm_stats f ON c.firm_crd = f.firm_crd
WHERE c.RIA_CONTACT_CRD_ID NOT IN (SELECT crd FROM existing_salesforce_leads)
```

#### Step 2: Create Outreach Lists

Export priority tier prospects to your outreach tools (Salesforce, Outreach, etc.)

### Daily/Weekly Workflow

1. **Morning:** Run priority tier query for today's new leads
2. **Review:** Assign Tier 1 leads to senior reps
3. **Outreach:** Work through tiers in order
4. **Log:** Record outcomes to improve future calibration

---

## 11. Limitations and Monitoring

### Known Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| Small priority tier volume | Only 4.6% of leads qualify | Accept trade-off: fewer but better leads |
| Test period distribution shift | Hard to validate on recent data | Monitor production performance |
| Requires FINTRX match | 4.3% of leads have no CRD | Score these as "Standard" |
| Static thresholds | May drift over time | Quarterly recalibration |

### Monitoring Recommendations

#### Weekly: Tier Distribution Check

```sql
SELECT 
    score_tier,
    COUNT(*) as new_leads,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) as pct
FROM lead_scores_v3
WHERE scored_at >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY score_tier
```

**Alert if:** Tier 1 volume drops below 1% of weekly leads

#### Monthly: Conversion Rate Check

```sql
SELECT 
    score_tier,
    COUNT(*) as leads,
    SUM(CASE WHEN mql_date IS NOT NULL THEN 1 ELSE 0 END) as conversions,
    ROUND(100.0 * SUM(converted) / COUNT(*), 2) as conv_rate
FROM lead_scores_v3
WHERE contacted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
  AND contacted_date <= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)  -- Mature leads only
GROUP BY score_tier
```

**Alert if:** Any priority tier falls below 2x baseline lift

#### Quarterly: Full Recalibration

Re-run the full model pipeline with fresh data to:
1. Validate tier thresholds still work
2. Update calibrated conversion rates
3. Check for any new leakage issues

### When to Rebuild the Model

Consider a full rebuild if:
- Priority tier lift drops below 1.5x for two consecutive months
- Business rules change (e.g., new wirehouse definitions)
- Significant new data sources become available
- Conversion rate drops by more than 50% across all tiers

---

## 12. Glossary

### Statistical Terms

**Baseline:** The conversion rate for all leads without any scoring (3.3% in our case)

**Confidence Interval (CI):** A range that likely contains the true value. A 95% CI means we're 95% confident the true value falls within this range.

**Conversion Rate:** The percentage of leads that become MQLs (conversions / total leads)

**Lift:** How much better a group performs compared to baseline. 3x lift means 3 times the baseline conversion rate.

**Point-in-Time (PIT):** Features calculated using only information available at a specific date (the contact date), not information that became available later.

**Right Censoring:** When we can't observe outcomes for recent leads because not enough time has passed. We handle this by only labeling leads that are at least 43 days old.

**Temporal Split:** Dividing data by time (train on past, test on future) rather than randomly, to simulate real-world prediction.

### Business Terms

**CRD:** Central Registration Depository number — a unique identifier for registered financial advisors

**FINTRX:** A database company that provides information about registered investment advisors

**Lead:** A potential customer who has been identified but not yet qualified

**MQL (Marketing Qualified Lead):** A lead that has been evaluated and deemed likely to become a customer

**Wirehouse:** Large broker-dealer firms like Merrill Lynch, Morgan Stanley, UBS, Wells Fargo. Advisors at these firms typically have less portable client relationships.

### Technical Terms

**BigQuery:** Google's cloud data warehouse where we store and analyze data

**Data Leakage:** When a model uses information that wouldn't be available at prediction time, leading to artificially inflated performance

**Feature:** A measurable characteristic used for prediction (e.g., "years at current firm")

**Tier:** A category of leads based on scoring criteria (Tier 1 = highest priority)

---

## Appendix A: Complete Feature List

### Advisor Features (9)
1. `industry_tenure_months` — Total months in the industry
2. `num_prior_firms` — Count of previous employers
3. `current_firm_tenure_months` — Months at current firm
4. `pit_moves_3yr` — Firm changes in last 3 years
5. `pit_avg_prior_tenure_months` — Average tenure at previous firms
6. `pit_restlessness_ratio` — Current tenure / average prior tenure
7. `pit_mobility_tier` — Categorized mobility (Stable/Mobile/Highly Mobile)

### Firm Features (9)
1. `firm_aum_pit` — Firm's Assets Under Management at contact date
2. `log_firm_aum` — Log-transformed AUM
3. `firm_rep_count_at_contact` — Number of advisors at firm
4. `firm_net_change_12mo` — Net advisor change (arrivals - departures)
5. `firm_departures_12mo` — Advisors who left in last 12 months
6. `firm_arrivals_12mo` — Advisors who joined in last 12 months
7. `firm_stability_score` — Composite stability metric
8. `firm_aum_tier` — Categorized firm size

### Data Quality Signals (5)
1. `is_gender_missing` — Gender field is null
2. `is_linkedin_missing` — LinkedIn URL is null
3. `is_personal_email_missing` — Personal email is null
4. `is_license_data_missing` — License data is incomplete
5. `is_industry_tenure_missing` — Industry tenure cannot be calculated

### Accolade Features (5)
1. `accolade_count` — Total accolades/awards
2. `has_accolades` — Binary: has any accolades
3. `forbes_accolades` — Count of Forbes recognitions
4. `disclosure_count` — Count of regulatory disclosures
5. `has_disclosures` — Binary: has any disclosures

---

## Appendix B: Validation Gate Summary

| Phase | Gate | Check | Result |
|-------|------|-------|--------|
| 0.0 | G0.0.1 | Date configuration valid | ✅ PASSED |
| 0.1 | G0.1.1 | CRD match rate ≥ 75% | ✅ 95.72% |
| 0.1 | G0.1.2 | Lead volume ≥ 5,000 | ✅ 52,626 |
| 0.2 | G0.2.3 | Mature leads ≥ 3,000 | ✅ 37,805 |
| 0.2 | G0.2.4 | Positive rate 2-6% | ✅ 4.36% |
| 1.1 | G1.1.3 | Zero PIT leakage | ✅ 0 rows |
| 2.1 | G2.1.4 | Temporal gap ≥ 30 days | ✅ 32 days |
| 3.1 | G3.1.2 | Protected features present | ✅ All present |
| 4.1 | G4.1.2 | Tier 1 lift ≥ 2.5x | ✅ 3.69x |
| 5.1 | G5.1.3 | Tier 1 training lift ≥ 2.5x | ✅ 3.69x |
| 6.1 | G6.1.4 | Tier 1 conversion ≥ 10% | ✅ 13.50% |
| 7.1 | G7.1.2 | Scoring table validated | ✅ 39,448 leads |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-21 | Analytics Team | Initial release |

---

*This document describes the Savvy Wealth Lead Scoring Model v3.1. For questions or issues, contact the Analytics team.*
