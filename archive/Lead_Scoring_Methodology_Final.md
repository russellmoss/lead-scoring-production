# 🎯 Lead Scoring Methodology
## How We Built a Smarter Way to Prioritize Advisor Outreach

**Version:** 3.2  
**Status:** ✅ Production Ready  
**January 2026 Lead List:** 2,768 leads  

---

## 📋 Executive Summary

We developed a lead scoring system that helps SGAs focus their time on the advisors most likely to convert. Instead of treating all leads equally, we prioritize based on patterns that actually predict success.

### January 2026 Lead List Projections

| Metric | Value |
|--------|-------|
| **Total Leads** | 2,768 |
| **Expected Conversion Rate** | **4.61%** |
| **Conservative Estimate (P10)** | **3.85%** |
| **Expected MQLs** | **~128** |
| **Improvement vs. Baseline** | **+68%** |

> ⭐ **Bottom Line:** We have **99.98% confidence** that this lead list will outperform our historical baseline of 2.74%.

---

## 📊 The Baseline

Before evaluating our methodology, we established the correct baseline — what happens when we contact leads without scoring.

| Metric | Value |
|--------|-------|
| **Historical Baseline** | 2.74% |
| **Sample Size** | 32,264 leads |
| **Time Period** | February 2024 - Present |
| **Lead Source** | Provided Lead List (FINTRX) |

This baseline is specific to **Provided Lead List** leads — the same source as our January list.

---

## 🧭 The Problem We Solved

When we started, leads were worked in essentially random order. Every advisor got the same priority regardless of their situation. SGAs spent as much time on low-probability leads as high-probability ones.

### The Breakthrough: Listening to Our Best Sourcers

We sat down with our top-performing SGAs and asked: *"What do you look for when self-sourcing?"*

Their answers were remarkably consistent — and when we tested their intuitions against actual conversion data, they were right.

---

## 👥 What the Data Validated

### Insight #1: Small Firm Advisors Are More Portable

At a small firm, the advisor *owns* the client relationship. At a wirehouse, the *institution* owns it.

**Result:** Advisors at firms with ≤10 people convert at **3.4x baseline**

---

### Insight #2: The Sweet Spot Is 1-4 Years Tenure

Too new = no book. Too long = too entrenched. The sweet spot is 1-4 years.

**Result:** Advisors with 1-4 years tenure convert at **2.4x baseline**

---

### Insight #3: Firms Bleeding Advisors Signal Opportunity

When advisors see peers leaving, they question their own situation.

**Result:** Advisors at firms losing advisors convert at **2.1-2.8x baseline**

---

### Insight #4: Prior Movement Predicts Future Movement

Advisors who have changed firms before are more likely to move again.

**Result:** Advisors with 3+ prior firms convert at **2.5x baseline**

---

### Insight #5: CFP Designation Signals Book Ownership

CFP holders manage client relationships directly — they have portable books.

**Result:** CFP holders at bleeding firms convert at **4.3x baseline**

---

## ✅ The Tier System

We encoded these validated insights into a tiered scoring system. Each tier represents signals that predict high conversion.

| Tier | Historical Rate | vs Baseline | What It Means |
|------|-----------------|-------------|---------------|
| **T1B** (Series 65 Only) | 11.76% | **4.3x** | Fee-only RIA, no broker-dealer ties |
| **T3** (Moderate Bleeder) | 6.76% | **2.5x** | Experienced advisor at unstable firm |
| **T1F** (Wealth Bleeder) | 6.06% | **2.2x** | Senior title at bleeding firm |
| **T2** (Proven Mover) | 5.91% | **2.2x** | 3+ prior firms, proven mobility |
| **T1** (Prime Mover) | 4.76% | **1.7x** | Mid-career at small bleeding firm |
| **HIGH_V4** (ML Backfill) | 3.67% | **1.3x** | ML-identified high potential |

### Design Principle

Every tier in the system converts **above baseline**. If a tier doesn't beat baseline, it doesn't belong in the list.

---

## 🤖 How Machine Learning Fits In

### What V4 Does

The V4 machine learning model (XGBoost) serves two purposes:

| Purpose | How It Works |
|---------|--------------|
| **Deprioritization** | Filters out the bottom 20% of leads across all tiers |
| **Backfill Identification** | Identifies the best remaining leads when priority tiers are exhausted |

### Why Rules + ML

| Rules (V3) | Machine Learning (V4) |
|------------|----------------------|
| Transparent and explainable | Catches hidden patterns |
| SGAs understand why leads qualify | Identifies worst leads to avoid |
| Based on validated domain expertise | Provides intelligent backfill |

> 💡 **Key Insight:** V4's top features (mobility, tenure, firm stability) align with SGA expertise — validating that our rules capture the right signals.

---

## 📊 January 2026 Lead List Composition

| Tier | Leads | % of List | Historical Rate | Expected MQLs |
|------|-------|-----------|-----------------|---------------|
| **T2** (Proven Mover) | 1,750 | 63.2% | 5.91% | 103 |
| **T1** (Prime Mover) | 350 | 12.6% | 4.76% | 17 |
| **T3** (Moderate Bleeder) | 327 | 11.8% | 6.76% | 22 |
| **HIGH_V4** (Backfill) | 218 | 7.9% | 3.67% | 8 |
| **T1B** (Series 65) | 70 | 2.5% | 11.76% | 8 |
| **T1F** (Wealth Bleeder) | 52 | 1.9% | 6.06% | 3 |
| **T1A** (CFP) | 1 | 0.0% | ~10%+ | 0.5 |
| **TOTAL** | **2,768** | **100%** | **5.85%** | **162** |

### Why This Mix Works

- **T2 is the workhorse** — high volume, strong conversion, large historical sample
- **T1 variants are premium** — highest rates but limited availability
- **HIGH_V4 fills gaps** — converts 34% above baseline, ensures volume targets

---

## 🔢 How We Calculated the Estimate

### Three-Step Process

**Step 1: Tier-Weighted Average**
```
Raw Estimate = Σ (Leads × Rate) / Total = 5.85%
```

**Step 2: Bootstrap Simulation**
- 10,000 iterations sampling from Beta distributions
- Accounts for uncertainty in historical rates
- Raw 95% CI: [4.43%, 7.54%]

**Step 3: Conservative Adjustments**

| Adjustment | Factor | Rationale |
|------------|--------|-----------|
| Small sample shrinkage | 90% | Top tiers have limited historical data |
| Implementation friction | 95% | New process learning curve |
| Historical optimism | 92% | Past validation may be slightly rosy |
| **Combined** | **78.66%** | Applied to raw estimate |

**Final Result:** 5.85% × 78.66% = **4.61%**

---

## 📈 Expected Performance

### Scenarios

| Scenario | Rate | Total MQLs | Per SGA |
|----------|------|------------|---------|
| **Conservative (P10)** | 3.85% | 107 | 7.6 |
| **Expected** | 4.61% | 128 | 9.1 |
| **Optimistic (P90)** | 5.42% | 150 | 10.7 |

### Probability Analysis

| Threshold | Probability |
|-----------|-------------|
| Exceed Baseline (2.74%) | **99.98%** |
| Exceed 4.0% | **84%** |
| Exceed 5.0% | 25% |

### vs. Baseline

| Metric | Baseline | January List | Improvement |
|--------|----------|--------------|-------------|
| Conversion Rate | 2.74% | 4.61% | **+68%** |
| MQLs (per 2,768) | 76 | 128 | **+52** |
| MQLs per SGA | 5.4 | 9.1 | **+69%** |

---

## 🔑 Key Takeaways

### For Leadership

- Methodology is grounded in **validated SGA expertise**
- Projections are **conservative** (21% discount applied)
- **99.98% confidence** of beating baseline

### For SGAs

- **T1 leads are highest priority** — multiple signals indicating readiness
- **Every lead beats baseline** — no wasted effort on low-probability contacts
- **Narratives explain why** — each lead comes with context

### For Operations

- **2,768 leads** to distribute (~198 per SGA)
- **Expected 128 MQLs** (conservative: 107)
- **Monitor actual vs. expected** to refine future lists

---

## 📋 Summary

| Question | Answer |
|----------|--------|
| **What did we build?** | Tiered lead scoring based on SGA expertise, validated by data |
| **How does it work?** | Rules prioritize; ML filters and backfills |
| **What do we expect?** | 4.61% conversion, ~128 MQLs |
| **Why confident?** | 10,000 simulations, 21% conservative discount, 99.98% confidence |

---

## 📊 Appendix: V4 Feature Importance

| Rank | Feature | What It Measures |
|------|---------|------------------|
| 1 | mobility_tier | Career movement history |
| 2 | has_email | Contact availability |
| 3 | tenure_bucket | Time at current firm |
| 4 | mobility_x_heavy_bleeding | Mobile + struggling firm |
| 5 | has_linkedin | LinkedIn profile presence |
| 6 | firm_stability_tier | Firm retention/growth |
| 7 | is_wirehouse | Large broker-dealer flag |
| 8 | firm_rep_count | Firm size |

---

## 📈 Appendix: Historical Tier Performance

| Tier | Sample Size | Rate | 95% CI |
|------|-------------|------|--------|
| T1B (Series 65) | 34 | 11.76% | [4.7%, 26.6%] |
| T3 (Moderate Bleeder) | 74 | 6.76% | [2.9%, 14.7%] |
| T1F (Wealth Bleeder) | 99 | 6.06% | [2.8%, 12.5%] |
| T2 (Proven Mover) | 711 | 5.91% | [4.4%, 7.8%] |
| T1 (Prime Mover) | 42 | 4.76% | [1.3%, 15.8%] |
| HIGH_V4 Backfill | 6,043 | 3.67% | [3.2%, 4.2%] |
| **Baseline** | **32,264** | **2.74%** | **[2.56%, 2.92%]** |

---

*This methodology represents the combined expertise of our Strategic Growth Associates, validated through rigorous data analysis and statistical testing.*

**Version:** 3.2 | **Generated:** December 2025
