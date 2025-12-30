# Tier Distribution Fix Summary

**Date**: 2025-12-30  
**Status**: ✅ **FIXED - Better Balance Achieved**

---

## Problem Identified

The lead list had **81% STANDARD_HIGH_V4** (2,273 leads) after fixing duplicates, which lowered the expected conversion rate from **5.5% to 4.0%**.

**Root Cause**: 
1. Deduplication was happening AFTER tier quotas were applied
2. When duplicates were removed from priority tiers, we lost those leads
3. We backfilled heavily with STANDARD_HIGH_V4 to reach 2,800 leads

---

## Solution Applied

1. **Moved deduplication BEFORE tier quotas** - This preserves priority tier leads
2. **Reverted STANDARD_HIGH_V4 quota** from 2,000 back to 600 (then increased to 1,500 for backfill)
3. **Restructured SQL flow**: `tier_limited` → `deduplicated_before_quotas` → `linkedin_prioritized` (with tier quotas)

---

## Results Comparison

### Before Fix (81% STANDARD_HIGH_V4)
| Tier | Leads | % | Expected Rate |
|------|-------|---|---------------|
| STANDARD_HIGH_V4 | 2,273 | 81% | 3.5% |
| TIER_2_PROVEN_MOVER | 457 | 16% | 5.2% |
| TIER_1B | 70 | 3% | 7.9% |
| **Blended Rate** | **2,800** | **100%** | **~4.0%** |

### After Fix (Better Balance)
| Tier | Leads | % | Expected Rate | Expected MQLs |
|------|-------|---|---------------|---------------|
| STANDARD_HIGH_V4 | 1,705 | 61% | 3.5% | 59.7 |
| TIER_2_PROVEN_MOVER | 705 | 25% | 5.2% | 36.7 |
| TIER_1_PRIME_MOVER | 253 | 9% | 7.1% | 18.0 |
| TIER_1B_PRIME_MOVER_SERIES65 | 70 | 2.5% | 7.9% | 5.5 |
| TIER_1F_HV_WEALTH_BLEEDER | 43 | 1.5% | 6.5% | 2.8 |
| TIER_3_MODERATE_BLEEDER | 24 | 0.9% | 4.4% | 1.1 |
| **Blended Rate** | **2,800** | **100%** | **~4.4%** | **~123 MQLs** |

---

## Key Improvements

✅ **Priority tiers restored**: TIER_1_PRIME_MOVER (253), TIER_1F (43), TIER_3 (24) are back  
✅ **Better tier mix**: 61% STANDARD_HIGH_V4 (down from 81%)  
✅ **Higher expected rate**: ~4.4% (up from 4.0%)  
✅ **All unique**: 2,800 leads, all unique CRDs  
✅ **Perfect distribution**: 200 leads per SGA  

---

## Expected Performance

- **Blended Conversion Rate**: ~4.4% (up from 4.0%)
- **Expected MQLs**: ~123 (vs ~112 at 4.0%)
- **Still below earlier 5.5% rate**, but much better than 4.0%

---

## Why Not 5.5%?

The earlier list (2,721 leads) had:
- 64% TIER_2_PROVEN_MOVER (1,750 leads)
- 13% TIER_1_PRIME_MOVER (343 leads)
- 10% TIER_3_MODERATE_BLEEDER (281 leads)

This list has:
- 25% TIER_2_PROVEN_MOVER (705 leads)
- 9% TIER_1_PRIME_MOVER (253 leads)
- 0.9% TIER_3_MODERATE_BLEEDER (24 leads)

**Reason**: After deduplication, we don't have enough unique priority tier leads to fill the quotas. The available pool of unique qualified leads is smaller than expected.

---

## Recommendation

✅ **Use this list** - It's the best balance we can achieve with available unique leads:
- 2,800 leads (200 per SGA)
- All unique (no duplicates)
- 4.4% expected rate (above 4% target)
- Better tier mix than the 81% STANDARD_HIGH_V4 version

**Trade-off**: Slightly lower conversion rate (4.4% vs 5.5%) but perfect distribution and no duplicates.

---

**Updated**: 2025-12-30

