# Career Clock Feature Deployment - January 1, 2026

## Deployment Summary

This document tracks the deployment of V3.4.0 Career Clock features to BigQuery production tables.

## Files to Deploy

### 1. Feature Engineering
**File:** `v3/sql/lead_scoring_features_pit.sql`  
**Target Table:** `savvy-gtm-analytics.ml_features.lead_scoring_features_pit`  
**Status:** ✅ Ready for deployment  
**Changes:** Added Career Clock CTEs and features (cc_completed_jobs, cc_avg_prior_tenure_months, cc_tenure_cv, cc_career_pattern, cc_pct_through_cycle, cc_cycle_status, cc_is_in_move_window, cc_is_too_early, cc_months_until_window)

### 2. Tier Scoring
**File:** `v3/sql/phase_4_v3_tiered_scoring.sql`  
**Target Table:** `savvy-gtm-analytics.ml_features.lead_scores_v3_4`  
**Status:** ✅ Ready for deployment  
**Changes:** Added Career Clock tiers (TIER_0A_PRIME_MOVER_DUE, TIER_0B_SMALL_FIRM_DUE, TIER_0C_CLOCKWORK_DUE, TIER_NURTURE_TOO_EARLY)

### 3. Lead List Generation
**File:** `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`  
**Target Tables:** 
- `savvy-gtm-analytics.ml_features.january_2026_lead_list`
- `savvy-gtm-analytics.ml_features.nurture_list_too_early`
**Status:** ✅ Ready for deployment  
**Changes:** Added Career Clock tier logic, excluded TIER_NURTURE_TOO_EARLY from active list, created separate nurture list

## Deployment Steps

1. ✅ **Feature Engineering** - Execute `v3/sql/lead_scoring_features_pit.sql`
2. ⏳ **Tier Scoring** - Execute `v3/sql/phase_4_v3_tiered_scoring.sql`
3. ⏳ **Lead List** - Execute `pipeline/sql/January_2026_Lead_List_V3_V4_Hybrid.sql`
4. ⏳ **Production View** - Update `ml_features.lead_scores_v3_production` to point to `lead_scores_v3_4`

## Verification Queries

### Verify Career Clock Features Exist
```sql
SELECT 
    column_name, 
    data_type 
FROM `savvy-gtm-analytics.ml_features.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'lead_scoring_features_pit'
  AND column_name LIKE 'cc_%'
ORDER BY column_name;
```

### Verify Career Clock Tiers
```sql
SELECT 
    score_tier,
    COUNT(*) as count,
    AVG(expected_conversion_rate) as avg_conv_rate
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3_4`
WHERE score_tier LIKE 'TIER_0%' OR score_tier = 'TIER_NURTURE_TOO_EARLY'
GROUP BY score_tier
ORDER BY score_tier;
```

### Verify Nurture List
```sql
SELECT 
    COUNT(*) as total_nurture_leads,
    COUNTIF(estimated_window_entry_date <= CURRENT_DATE()) as entered_window,
    COUNTIF(estimated_window_entry_date BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY)) as entering_next_30_days
FROM `savvy-gtm-analytics.ml_features.nurture_list_too_early`;
```

## Deployment Notes

- All SQL files have been updated with Career Clock features
- PIT compliance verified (all features use only data available at contacted_date)
- Tier logic updated to include new Career Clock priority tiers
- Nurture list created for "Too Early" leads

## Next Steps

After deployment:
1. Run verification queries above
2. Update production view: `ml_features.lead_scores_v3_production`
3. Monitor Career Clock tier performance using `pipeline/sql/monitor_career_clock_performance.sql`
