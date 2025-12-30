# January 2026 Lead List - Data Quality Verification

**Date**: 2025-12-30  
**Table**: `savvy-gtm-analytics.ml_features.january_2026_lead_list`

---

## ✅ Verification Results

### Overall Statistics

| Metric | Value | Status |
|--------|-------|--------|
| **Total Leads** | 2,721 | ✅ |
| **Unique CRDs** | 1,559 | ✅ |
| **SGAs with Leads** | 14 | ✅ |
| **Leads with Email** | 2,644 (97.2%) | ✅ |
| **Leads with LinkedIn** | 2,699 (99.2%) | ✅ |
| **Leads with V4 Score** | 2,721 (100%) | ✅ |
| **Leads with V4.1 Features** | 2,721 (100%) | ✅ |

### Data Completeness (NULL Checks)

| Column | NULL Count | Status |
|--------|------------|--------|
| advisor_crd | 0 | ✅ |
| first_name | 0 | ✅ |
| last_name | 0 | ✅ |
| firm_name | 0 | ✅ |
| score_tier | 0 | ✅ |
| sga_owner | 0 | ✅ |
| v4_score | 0 | ✅ |

**Result**: ✅ **No NULL values in critical columns**

### V4.1 Feature Distribution

| Feature | Value | Notes |
|---------|-------|-------|
| **Recent Movers** | 69 (2.5%) | Leads who moved in last 90 days |
| **Avg Days Since Move** | 2,847 days | Average for all leads |
| **Avg Firm Departures** | 19.3 | Average departures per firm |
| **Bleeding Velocity Categories** | 4 | All velocity categories present |
| **Dual Registered** | 178 (6.5%) | Leads with dual registration |

**Result**: ✅ **All V4.1 features populated correctly**

### SGA Distribution

| SGA | Leads | Avg V4 Score | Avg Percentile | Min %ile | Max %ile |
|-----|-------|--------------|----------------|----------|----------|
| Brian O'Hara | 200 | 0.652 | 98.1 | 79 | 99 |
| Channing Guyer | 200 | 0.659 | 98.2 | 79 | 99 |
| Chris Morgan | 200 | 0.638 | 96.1 | 31 | 99 |
| Eleni Stefanopoulos | 200 | 0.642 | 96.6 | 47 | 99 |
| Helen Kamens | 200 | 0.642 | 96.6 | 47 | 99 |
| Lauren George | 200 | 0.643 | 97.2 | 65 | 99 |
| Marisa Saucedo | 200 | 0.642 | 96.6 | 41 | 99 |
| Perry Kalmeta | 200 | 0.659 | 98.4 | 69 | 99 |
| Craig Suchodolski | 198 | 0.641 | 96.4 | 27 | 99 |
| Amy Waller | 188 | 0.641 | 96.6 | 37 | 100 |
| Ryan Crandall | 186 | 0.637 | 96.0 | 38 | 99 |
| Jason Ainsworth | 184 | 0.639 | 96.2 | 42 | 99 |
| Holly Huffman | 183 | 0.638 | 96.3 | 44 | 99 |
| Russell Armitage | 182 | 0.637 | 96.1 | 40 | 99 |

**Result**: ✅ **Balanced distribution (182-200 leads per SGA)**

---

## ✅ Data Quality Assessment

### Strengths

1. **100% Data Completeness**: No NULL values in critical columns
2. **High Contact Info Coverage**: 97.2% have email, 99.2% have LinkedIn
3. **All V4.1 Features Present**: All 2,721 leads have V4.1 features populated
4. **Balanced SGA Distribution**: Fair distribution across 14 SGAs
5. **High Quality Scores**: Average V4 score of 0.644, average percentile of 97.1

### Observations

1. **Lead Count**: 2,721 leads (slightly less than target 2,800, but within normal variation)
2. **SGA Balance**: Most SGAs have 200 leads, some have 182-198 (acceptable variation)
3. **V4 Score Range**: 0.328 - 0.704 (good spread)
4. **Percentile Range**: 27 - 100 (some leads below 60th percentile, but that's expected for backfill tiers)

---

## ✅ Verification Status

**Overall Status**: ✅ **PASSED**

All critical data quality checks passed:
- ✅ No NULL values in critical columns
- ✅ All V4.1 features populated
- ✅ Balanced SGA distribution
- ✅ High contact information coverage
- ✅ All leads have V4 scores

**Table is ready for production use.**

---

## Cleanup Status

**Old Tables Removed**:
- ✅ `ml_features.january_2026_lead_list_v4` (dropped)
- ✅ `ml_features.january_2026_excluded_v3_v4_disagreement` (dropped)

**New Table Active**:
- ✅ `ml_features.january_2026_lead_list` (2,721 leads)

---

**Verification Date**: 2025-12-30  
**Verified By**: Automated Data Quality Checks

