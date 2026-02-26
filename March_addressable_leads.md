# March Addressable Leads — Tier Totals for Ratio Planning

**Purpose:** Total addressable leads by tier (before quota/cap) so you can set tier ratios for the March lead list. Includes all tiers—including ones we did not use in January (e.g. TIER_NURTURE_TOO_EARLY, excluded V3 tiers) and FinTrx-scored/M&A pools.

**Source:** Same pipeline as January 2026 lead list (base_prospects → exclusions → tier assignment), with **no per-tier or per-SGA quota** applied. Counts are from `ml_features.march_addressable_by_tier` (created by `pipeline/sql/March_addressable_by_tier_cte.sql`).

---

## 1. Lead-list addressable (base list, before M&A)

These are advisors who pass all lead-list exclusions (firm exclusions, disclosures, title exclusions, recent promotee, V4 bottom 20%, firm size ≤50) and receive a **single** tier. One row per CRD (deduplicated). Use these for **ratio planning** for the March base list.

| Tier | Addressable count | Notes |
|------|-------------------|--------|
| **TIER_2_PROVEN_MOVER** | 1,533 | Proven movers (3+ prior firms, 5+ yrs tenure) |
| **TIER_1_PRIME_MOVER** | 885 | Prime mover (tenure/industry/firm criteria) |
| **TIER_1G_GROWTH_STAGE** | 770 | Growth stage (60–180 mo tenure, account size ≥250K, not heavy bleeder) |
| **TIER_1B_PRIME_MOVER_SERIES65** | 754 | Prime + Series 65 only |
| **TIER_1G_ENHANCED_SWEET_SPOT** | 581 | Sweet spot ($500K–$2M account size, 60–180 mo tenure) |
| **TIER_NURTURE_TOO_EARLY** | 370 | In Career Clock “too early” window — **excluded from Jan active list**; available for nurture or March if you include |
| **TIER_0B_SMALL_FIRM_DUE** | 254 | Small firm (≤10 reps) + in move window |
| **TIER_0C_CLOCKWORK_DUE** | 160 | Any predictable advisor in move window |
| **STANDARD_HIGH_V4** | 154 | No named V3 tier but V4 percentile ≥ 80 (backfill) |
| **TIER_3_MODERATE_BLEEDER** | 72 | Firm net change −10 to −1, 5+ yrs tenure |
| **TIER_1F_HV_WEALTH_BLEEDER** | 1 | High-value wealth title + bleeding firm |
| **Total (base addressable)** | **5,534** | |

Tiers that exist in the logic but had **0** addressable in this run (everyone in that segment was assigned a higher-priority tier): **TIER_0A_PRIME_MOVER_DUE**, **TIER_1A_PRIME_MOVER_CFP**, **TIER_1B_PRIME_ZERO_FRICTION**.

---

## 2. M&A addressable (separate pool)

M&A leads are a **separate** pool; they are added via `Insert_MA_Leads.sql` after the base list. Counts below are **before** lead-list filters (V4 ≥20, recent promotee exclusion, quota limit 300).

| Tier | Addressable count | Notes |
|------|-------------------|--------|
| **TIER_MA_ACTIVE** | 931 | M&A target firm, active opportunity |
| **TIER_MA_ACTIVE_PRIME** | 883 | M&A target, high-value (e.g. senior title / conversion expectation) |
| **Total (M&A addressable)** | **1,814** | |

After filters and quota, January inserted **300** M&A leads (all TIER_MA_ACTIVE_PRIME in that run). For March you can change how many M&A leads to take and the split between TIER_MA_ACTIVE vs TIER_MA_ACTIVE_PRIME.

---

## 3. FinTrx-scored prospects (V4 model)

Total prospects with a V4 score (no lead-list exclusions applied). Use for context on pool size and for STANDARD_HIGH_V4 backfill.

| Metric | Count | Notes |
|--------|--------|--------|
| **Total V4 scored** | 266,900 | All prospects in `v4_prospect_scores` |
| **V4 percentile ≥ 80** | 8,007 | Eligible for STANDARD_HIGH_V4 (backfill) |
| **V4 percentile ≥ 20** | 210,850 | Above bottom 20% (not deprioritized) |

The **lead list** only uses people who also pass base_prospects (firm, disclosure, title, recent promotee, firm size ≤50). So the 5,534 base addressable is a subset of these 266,900.

---

## 4. V3 PIT tiers (reference — different taxonomy)

`lead_scores_v3_6` uses a **different** tier set (PIT/contact-history-based). Shown for reference; the **March lead list** uses the hybrid tiers in Section 1, not these labels.

| Tier | Count | Notes |
|------|--------|--------|
| STANDARD | 19,863 | No named tier in PIT logic |
| TIER_2A_PROVEN_MOVER | 657 | |
| TIER_4_HEAVY_BLEEDER | 597 | Option C: excluded from Jan list (map to STANDARD) |
| TIER_1F_HV_WEALTH_BLEEDER | 108 | |
| TIER_3_EXPERIENCED_MOVER | 82 | |
| TIER_0C_CLOCKWORK_DUE | 76 | |
| TIER_1G_ENHANCED_SWEET_SPOT | 47 | |
| TIER_1E_PRIME_MOVER | 44 | |
| TIER_1B_PRIME_MOVER_SERIES65 | 39 | |
| TIER_2B_MODERATE_BLEEDER | 38 | |
| TIER_1D_SMALL_FIRM | 37 | |
| TIER_1G_GROWTH_STAGE | 31 | |
| TIER_1B_PRIME_ZERO_FRICTION | 30 | |
| TIER_1C_PRIME_MOVER_SMALL | 14 | |
| TIER_0A_PRIME_MOVER_DUE | 12 | |
| TIER_0B_SMALL_FIRM_DUE | 12 | |
| TIER_1A_PRIME_MOVER_CFP | 8 | |
| TIER_NURTURE_TOO_EARLY | 8 | |
| **Total (V3 PIT)** | **~21,700** | |

---

## 5. Who we exclude (and how many you could add back)

These exclusions shrink the pool from “all FinTrx / all scored” down to the **5,534** base addressable. If you change policy for March, you can conceptually add back some of these.

| Exclusion | Effect | If you included them |
|-----------|--------|------------------------|
| **Firm exclusions** | Excluded firms (e.g. Savvy, Ritholtz, excluded_firms table) | More leads from those firms |
| **Disclosures** | CRIMINAL, REGULATORY_EVENT, TERMINATION, INVESTIGATION, CUSTOMER_DISPUTE, CIVIL_EVENT, BOND | ~10% more prospects (compliance tradeoff) |
| **Title exclusions** | Paraplanner, assistant, operations, compliance, FSA, etc. | More leads, lower conversion |
| **Recent promotee** | &lt;5 yrs industry tenure + mid/senior title | ~1,915 more (0.29–0.45% conversion) |
| **Age &gt; 70** | AGE_RANGE 70+ | Small segment |
| **V4 bottom 20%** | v4_percentile &lt; 20 | More leads, much lower conversion (1.21%) |
| **Firm size &gt; 50 reps** | firm_rep_count &gt; 50 | More leads from large firms (0.60x baseline) |
| **TIER_4 / TIER_5 (Option C)** | Mapped to STANDARD in logic; then STANDARD only in list if V4≥80 | TIER_4 = experienced mover (20+ yrs, 1–4 at firm); TIER_5 = heavy bleeder; both convert near/below baseline |
| **TIER_NURTURE_TOO_EARLY** | In “too early” Career Clock window; excluded from **active** Jan list | **370** in addressable table — available for nurture or March if you include |

---

## 6. Summary totals for March ratio planning

| Pool | Total | Use for |
|------|--------|---------|
| **Base addressable (lead-list tiers)** | **5,534** | Set tier ratios for March base list |
| **of which TIER_NURTURE_TOO_EARLY** | 370 | Include or exclude for March active list |
| **M&A addressable** | 1,814 | Set M&A quota and TIER_MA_ACTIVE vs TIER_MA_ACTIVE_PRIME split |
| **FinTrx V4 scored** | 266,900 | Context; STANDARD_HIGH_V4 backfill comes from here |

January used **2,515** base leads (after quota) and **300** M&A leads (**2,815** total). For March you can change:

- **Tier ratios** within the 5,534 base addressable (e.g. more TIER_2_PROVEN_MOVER, less TIER_1G_GROWTH_STAGE).
- Whether to **include TIER_NURTURE_TOO_EARLY** (370) in the active list or keep for nurture only.
- **M&A total** and split between TIER_MA_ACTIVE (931) and TIER_MA_ACTIVE_PRIME (883).

---

*Generated from `march_addressable_by_tier` and supporting tables. Re-run `March_addressable_by_tier_cte.sql` after any FinTrx or scoring refresh to refresh these numbers.*
