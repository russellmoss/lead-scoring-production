# Lead Scoring Explained

**For:** Sales, executives, and anyone who wants to understand how we decide which advisors to contact and in what order.

**Last updated:** February 2026  
**Current production:** March 2026 Lead List (V3.7.0) + V4.2.0 ML model

---

## What problem does lead scoring solve?

We have a large universe of financial advisors. We can’t contact everyone. Lead scoring answers two questions:

1. **Who should we contact?** (Exclude advisors who are a poor fit or too risky.)
2. **In what order?** (Contact the best-fit advisors first so we hit our goals with fewer calls.)

The goal is to maximize **conversion rate**: the share of contacted advisors who become real opportunities (MQLs). Our **baseline**—the conversion rate for “average” leads—is about **3.8%**. We use rules and a machine-learning model to do better than that.

---

## The big picture: Rules + ML, each doing what it’s best at

We use a **hybrid** approach:

| Role | What we use | Why |
|------|-------------|-----|
| **Prioritization** (who’s best?) | **V3 rules** | Rules encode what we’ve learned from data: e.g. “advisors at firms that are losing reps convert better.” They’re interpretable and have been validated on real conversion data. |
| **Deprioritization** (who to skip?) | **V4 ML model** | The model is good at spotting *combinations* of factors that predict low conversion. We use it only to filter out the bottom 20% of leads. |

**Important decision (March 2026):** We used to backfill the list with “STANDARD” leads who had a high ML score but didn’t match any rule. January data showed those converted at only **0.8%** (worse than baseline). We **removed that backfill**. Today, everyone on the active list fits at least one **rules-based tier**. The ML model is used only to **exclude** the worst 20%, not to add leads.

---

## Tiers: What they mean and why they exist

Tiers are **labels** we put on leads based on rules. Each tier has a **historical conversion rate** (and often a confidence level). Higher tiers get contacted first and get more of the “budget” (leads per SGA).

### Tier 0 — Career Clock (highest priority)

These advisors have **predictable job-hopping patterns** and are in their **“move window”** (roughly 70–130% of their typical tenure at a firm). We contact them when they’re most likely to be open to a move.

| Tier | Who it is | Why it works |
|------|-----------|--------------|
| **TIER_0A_PRIME_MOVER_DUE** | Prime Mover profile + in move window | Strong behavioral signal plus timing; ~5.6% conversion in validation. |
| **TIER_0B_SMALL_FIRM_DUE** | Small firm + in move window | Small firms + predictable timing; validated lift. |
| **TIER_0C_CLOCKWORK_DUE** | Any advisor with predictable pattern, in window | Broader “in window” group; ~5% conversion. |

**Career Clock** is built from employment history (tenure at each firm). We only use past jobs that had ended by the time we score, so there’s no look-ahead bias. Career Clock signal is **independent of age** (we checked; correlation is very low).

### Tier 1 — Prime Movers and high-signal segments

These are advisors who show several signals that they might be ready to move: tenure, firm instability, credentials, firm size, etc.

| Tier | Who it is | Why it works |
|------|-----------|--------------|
| **TIER_1B_PRIME_ZERO_FRICTION** | Series 65 only, portable custodian (e.g. Schwab/Fidelity), small firm, firm losing reps | Easiest transition; highest Tier 1 conversion (~13.6%). |
| **TIER_1A_PRIME_MOVER_CFP** | CFP at a “bleeding” firm, 1–4 yr tenure, 5+ yr experience | Credentialed, mid-career, firm churn. |
| **TIER_1G_ENHANCED_SWEET_SPOT** | Growth-stage practice, AUM in a sweet spot, stable firm | Practice maturity + AUM band that converts well. |
| **TIER_1B_PRIME_MOVER_SERIES65** | Fee-only RIA (Series 65 only) meeting Prime Mover criteria | Lower friction than dual-registered. |
| **TIER_1G_GROWTH_STAGE** | Growth stage outside the AUM sweet spot | Still a growth-stage signal. |
| **TIER_1_PRIME_MOVER** | Mid-career (1–4 yr at firm, 5–15 yr experience) at small/unstable firm | Classic “likely to move” profile. |
| **TIER_1F_HV_WEALTH_BLEEDER** | High-value wealth title at a firm that’s losing reps | Title + firm instability. |

### Tier 2 and 3 — Behavioral signals

| Tier | Who it is | Why it works |
|------|-----------|--------------|
| **TIER_2_PROVEN_MOVER** | 3+ prior firms, 5+ years experience | History of moving; ~5.2% conversion. |
| **TIER_3_MODERATE_BLEEDER** | Firm lost 1–10 reps in last 12 months, 5+ years experience | Firm churn without being extreme. |

### STANDARD tier

Advisors who pass all filters but don’t match any of the above tiers get **STANDARD**. They convert at about the baseline rate (~3.8%). In March 2026 we still take some STANDARD leads (with high V4 score) to fill SGA quotas, but we **no longer** treat “high V4 alone” as a reason to add lots of extra leads.

### Tiers we intentionally exclude from the active list

We **don’t** put these on the active contact list, based on validation:

| Tier | Reason |
|------|--------|
| **TIER_4_EXPERIENCED_MOVER** | Converts at or below baseline; no lift. |
| **TIER_5_HEAVY_BLEEDER** | Marginal lift; best advisors may have already left. |
| **TIER_NURTURE_TOO_EARLY** | In a predictable pattern but *before* the move window; we keep them in nurture, not active list. |

---

## Exclusions: Who we never contact (or drop early)

Before we assign a tier, we exclude advisors who are a bad fit or too risky.

### Firm-level

- **Excluded firms:** Wirehouses, broker-dealers, insurance-heavy firms, and specific partners (e.g. Ritholtz) — from a centralized exclusion table.
- **Excluded firm CRDs:** Specific firms we don’t target (e.g. Savvy itself).
- **Low discretionary AUM:** Firm’s discretionary ratio &lt; 50% (book is less portable).
- **Very high turnover:** Firm turnover ≥ 100% in the last 12 months.
- **Size cap:** We only take leads from firms with ≤ 50 reps (larger firms convert worse).

### Advisor-level

- **Age 70+:** Conversion drops sharply; we exclude 70–74, 75–79, etc.
- **Disclosures:** We exclude advisors with certain regulatory/legal disclosures (criminal, regulatory event, termination, investigation, customer dispute, civil, bond). *Why:* Compliance and reputational risk. Analysis showed conversion impact was small (~0.11% difference), but we exclude for risk control.
- **Title:** Paraplanner, associate advisor, operations, wholesaler, compliance, assistant, insurance agent, branch manager, CFO/CIO, VP, etc. — roles that typically don’t have a portable book or decision authority.
- **Recent promotee:** &lt;5 years in the industry *and* mid/senior title (e.g. “Financial Advisor,” “Wealth Advisor”). These convert very poorly (~0.3–0.45%); we exclude them.
- **Lead disposition:** If we already marked them “No Book,” “Book Not Transferable,” or “Not a Fit” in Salesforce, we don’t re-contact.
- **Recently closed:** If they were closed in the last 365 days with a non-recyclable disposition, we exclude them (recyclable dispositions like “Bad Lead Provided” or “Wrong Phone Number” can be re-contacted after 180 days under our recycle rules).

---

## The V4 ML model: What it does and how it was validated

### What V4 does in production

- **Scores** every prospect in the pipeline (0–1 score, then turned into a **percentile** 1–100).
- We **exclude the bottom 20%** (percentile &lt; 20). Those leads convert at about **0.31x** baseline; skipping them costs few conversions and saves a lot of effort.
- We do **not** use V4 to *add* leads (no “high V4 only” backfill anymore).
- For **Tier 1** leads, we also apply a “disagreement” filter: if the rule says Tier 1 but V4 is below the 60th percentile, we exclude them (likely rule false positive).

### How the model was validated

- **V4.2.0** (current) has **23 features** (tenure, mobility, firm size and stability, credentials, age bucket, etc.). Age was added after analysis showed it added signal without duplicating other features.
- Validation used **train/test splits**, **AUC-ROC**, **top-decile lift**, and **overfitting checks**. V4.2.0 improved over the previous version on AUC, lift, and overfitting.
- **Point-in-time (PIT) safe:** Features are built only from information that would have been known at the time of contact (e.g. employment history only with end date before contact date).
- Narratives shown to sales are **gain-based** (from the model), not SHAP-based, to avoid a known XGBoost baseline issue.

---

## How a lead list like March 2026 gets built (high level)

The March list is produced by a **single BigQuery script**: `March_2026_Lead_List_V3_7_0.sql`. It runs end-to-end and writes the final table (e.g. `ml_features.march_2026_lead_list`). M&A leads are added in a **separate** step (`Insert_MA_Leads.sql`).

### Step-by-step (simplified)

1. **Active SGAs**  
   Pull the list of active Sales Growth Advisors from Salesforce. Total lead need = 200 leads per SGA.

2. **Exclusions and reference data**  
   Load excluded firms, excluded firm CRDs, disposition-based exclusions, “closed recently” exclusions, and who’s already in Salesforce (and who’s recyclable: e.g. Nurture 300+ days no contact, or Closed with recyclable disposition and 180+ days).

3. **Base prospects**  
   From FinTrx (advisor/firm data), take producing advisors with required fields, and apply exclusions: firm patterns, firm CRD, disposition, closed recent, age 70+, disclosures, title. This is the **base_prospects** pool.

4. **Recent promotee exclusion**  
   Drop advisors who are “recent promotees” (&lt;5 yr tenure + mid/senior title).

5. **Enrichment**  
   Join in employment history (moves, tenure), firm metrics (headcount, departures, arrivals, turnover), certifications (CFP, Series 65, etc.), Career Clock stats, discretionary ratio, and other flags needed for tier logic.

6. **V4 scores**  
   Attach V4 score and percentile (from a pre-built V4 prospect scores table).

7. **V4 filter**  
   Keep only prospects with **V4 percentile ≥ 20** (or null). Bottom 20% are dropped.

8. **Tier assignment**  
   For each prospect, evaluate the rules in a fixed order and assign the **first matching tier** (e.g. Career Clock first, then Prime Mover variants, then Proven Mover, Moderate Bleeder). Anyone not matching a chosen tier and not excluded becomes STANDARD (and can be used for backfill with high V4). TIER_4, TIER_5, and TIER_NURTURE_TOO_EARLY are not placed on the active list.

9. **Scored prospects**  
   Attach narratives and expected conversion rates per tier.

10. **Who’s eligible for this list**  
    Only **new prospects** or **recyclable** leads (Nurture/Closed per recycle rules). Everyone else is ineligible for this run.

11. **Ranking and diversity**  
    Rank within firm; apply a **per-firm cap** (e.g. up to 50 leads per firm) so the list isn’t dominated by a few big firms.

12. **Tier quotas**  
    For each tier, we only take up to a **quota** (e.g. 100 for TIER_0A, 150 for TIER_0B, 380 for TIER_1_PRIME_MOVER, ~1,600 for TIER_2_PROVEN_MOVER, etc.). Quotas scale with the number of SGAs (e.g. `quota * total_sgas / 12`). STANDARD (high V4) is used to fill remaining slots up to 200 per SGA.

13. **Deduplication**  
    One lead per CRD; keep the best-ranked instance (by tier priority, then V4, etc.).

14. **LinkedIn prioritization**  
    Prefer leads with LinkedIn when filling quotas; a limited number of no-LinkedIn leads are allowed so we don’t over-penalize missing data.

15. **SGA assignment**  
    Assign leads to SGAs so each gets **exactly 200**. We use a **stratified round-robin** by conversion-rate bucket so each SGA gets a similar mix of high/medium/low expected conversion. Partner/Founder leads at the same firm are assigned to the same SGA to avoid duplicate outreach to the same leadership.

16. **Final list**  
    Apply the V3/V4 disagreement filter (Tier 1 with V4 &lt; 60th percentile removed). The result is the **march_2026_lead_list** table.

M&A leads are added in a separate process (e.g. `Insert_MA_Leads.sql`) and are not part of the main script’s tier quotas.

---

## Decisions we made and why (summary for execs)

| Decision | What we did | Why |
|----------|-------------|-----|
| **Rules first, ML to cut the tail** | V3 rules assign tiers; V4 only drops bottom 20% | Rules beat ML for *prioritization* in testing; ML is strong at finding who *not* to call. |
| **No STANDARD_HIGH_V4 backfill** | Removed in V3.7.0 | January data: those leads converted at 0.8% (0.6x baseline). We have enough rules-based leads; no need to backfill with ML-only. |
| **Exclude disclosures** | Hard exclude for criminal, regulatory, termination, investigation, customer dispute, civil, bond | Conversion impact is small; we do it for **compliance and reputational risk**. |
| **Exclude recent promotees** | &lt;5 yr tenure + mid/senior title excluded | They convert at 0.29–0.45%; they typically don’t have a portable book yet. |
| **Career Clock tiers** | Added TIER_0A/0B/0C for “in move window” | Validation showed timing signal is independent of age and adds lift (e.g. 5.07% for “in window”). |
| **Exclude TIER_4 and TIER_5** | Not on active list | They convert at or below baseline; we don’t waste contact budget on them. |
| **Nurture “Too Early”** | TIER_NURTURE_TOO_EARLY not on active list | Kept in nurture; we contact them later when they’re closer to their move window. |
| **200 leads per SGA** | Fixed list size per SGA | Ensures equitable capacity and allows stratified distribution by expected conversion. |
| **Recycle rules** | Nurture 300+ days no contact; Closed with recyclable disposition + 180 days | Lets us re-contact leads who weren’t ready or had bad data, without over-contacting recent “no”s. |

---

## Where to look for more detail

- **Technical / pipeline:** `lead_scoring_explanation.md` (tier definitions, validation stats, exclusions, metrics).
- **List enrichment (any list with CRDs):** `List Enrichment playbook (1).md` (matching, FinTrx enrichment, Phase 4 scoring, Salesforce history).
- **Career Clock:** `career_clock_results.md` (methodology, correlation with age, conversion by CC status).
- **Disclosures:** `disclosure_analysis_results.md` (impact on conversion; we still exclude for compliance).
- **V4 model:** `v4/reports/v4.2/V4.2_Final_Summary.md` (features, validation gates, deployment).
- **March list SQL:** `pipeline/sql/March_2026_Lead_List_V3_7_0.sql` (full pipeline; comments describe each section).

---

*This document is maintained for sales and executives. For changes to tiers, exclusions, or the pipeline, work with the data/GTM analytics team.*
