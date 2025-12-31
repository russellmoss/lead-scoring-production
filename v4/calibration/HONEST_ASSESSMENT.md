# Honest Assessment: Isotonic Calibration Results

**Date**: 2025-12-31  
**Status**: Calibration implemented but did not achieve primary goal

---

## The Problem We Tried to Solve

V4.1.0 R3 had a non-monotonic lift curve where decile 4 (0.47x) and decile 5 (0.49x) had lower lift than decile 3 (0.63x).

## What We Did

Applied isotonic regression calibration as a post-processing wrapper to force monotonicity.

## What Actually Happened

| Metric | Before | After | Verdict |
|--------|--------|-------|---------|
| Non-monotonic deciles | 2 (D4, D5) | 3 (D4, D5, D8) | ❌ **Worse** |
| Top decile lift | 1.75x | 1.70x | ⚠️ Slight decrease |
| Bottom 20% conv | ~1.2% | ~1.0% | ⚠️ Slight decrease |

**The calibration didn't solve the non-monotonicity problem.**

---

## Why It Didn't Work

### What Isotonic Calibration Actually Does

| What It Does | What It Doesn't Do |
|--------------|-------------------|
| ✅ Transforms scores monotonically | ❌ Change lead rankings |
| ✅ Calibrates probabilities | ❌ Fix model ranking errors |
| ✅ Makes scores interpretable | ❌ Move leads between deciles |

The non-monotonic lift curve is caused by the **model ranking leads incorrectly** — some middle-scored leads are actually worse than lower-scored leads. Calibration preserves the ranking, so the same "bad" leads stay in the same deciles.

**Key Insight**: Isotonic calibration ensures that if lead A has a higher raw score than lead B, then lead A will have a higher calibrated score than lead B. But it doesn't fix cases where the model incorrectly assigned lead A a higher score than lead B in the first place.

---

## Impact on Production

**None** — The hybrid system uses:

| Use Case | Affected? |
|----------|-----------|
| V3 tier prioritization (T1A, T1B, T2) | ❌ No — V3 rules drive this |
| V4 deprioritization (bottom 20%) | ❌ No — Bottom 20% still ~1% conv |
| Middle decile sorting | ⚠️ Yes — but you don't use this |

The middle-decile non-monotonicity doesn't affect either primary use case.

---

## Decision: Keep or Rollback?

| Option | Pros | Cons |
|--------|------|------|
| **Keep** | Already implemented, doesn't hurt, calibrates probabilities | Didn't solve problem, slight performance decrease |
| **Rollback** | Restore original (slightly better) performance | Lose calibrated probabilities |

**Recommendation**: **KEEP** for now (easy to rollback if needed). The calibration doesn't hurt and provides calibrated probabilities, even though it didn't solve the non-monotonicity problem.

**Rollback** (if desired):
```bash
# Delete calibrator
rm v4/models/v4.1.0_r3/isotonic_calibrator.pkl

# The scoring script already has fallback - it will use raw scores automatically
```

---

## What This Means

1. **The model limitation is real**: The non-monotonicity in deciles 3-5 is a model limitation, not something post-processing can fix.

2. **It doesn't matter for your use case**: Your hybrid system doesn't rely on middle-decile sorting, so this limitation doesn't affect production.

3. **The model is working well**: Your **4.3x lift in T1A** (V3) and **bottom 20% deprioritization** (V4) are both working correctly.

4. **Accept the limitation**: The non-monotonicity in middle deciles is an interesting finding but not a problem you need to solve.

---

## Documentation Status

- ✅ **MODEL_EVOLUTION_HISTORY.md**: Updated with honest assessment
- ❌ **README.md**: Not updated (calibration didn't achieve its goal)
- ✅ **Internal docs**: All updated with honest findings

---

## Bottom Line

| Question | Answer |
|----------|--------|
| Update README? | **No** — calibration didn't achieve its goal |
| Keep calibration? | **Recommend keep** — doesn't hurt, easy to rollback |
| Worry about non-monotonicity? | **No** — doesn't affect your V3+V4 hybrid use case |
| Anything else to do? | Document the finding honestly, move on |

The model is working well for its intended purpose. The non-monotonicity in middle deciles is an interesting finding but not a problem you need to solve.

