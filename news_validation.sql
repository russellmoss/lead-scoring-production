-- =============================================================================
-- NEWS MENTIONS TIMING VALIDATION QUERY
-- =============================================================================
-- Hypothesis: Advisors mentioned in news within 90 days before contact 
-- convert at higher rates (news = "mindset shift" signal)
-- 
-- Expected Coverage: ~4.8% of contacts have news mentions
-- Tables: news_ps, ria_contact_news, lead_scoring_features_pit
-- =============================================================================

-- PART 1: Basic Validation - Does recent news correlate with conversion?
-- =============================================================================

WITH lead_news AS (
    -- Get all leads with their news mentions (if any) within 90 days before contact
    SELECT 
        l.lead_id,
        l.advisor_crd,
        l.contacted_date,
        l.target,
        -- Count news mentions in 90 days before contact
        COUNT(DISTINCT CASE 
            WHEN n.WRITTEN_AT IS NOT NULL 
                 AND n.WRITTEN_AT >= DATE_SUB(l.contacted_date, INTERVAL 90 DAY)
                 AND n.WRITTEN_AT < l.contacted_date
            THEN n.ID 
        END) as news_count_90d,
        -- Count news mentions in 180 days before contact (broader window)
        COUNT(DISTINCT CASE 
            WHEN n.WRITTEN_AT IS NOT NULL 
                 AND n.WRITTEN_AT >= DATE_SUB(l.contacted_date, INTERVAL 180 DAY)
                 AND n.WRITTEN_AT < l.contacted_date
            THEN n.ID 
        END) as news_count_180d,
        -- Get most recent news date before contact
        MAX(CASE 
            WHEN n.WRITTEN_AT < l.contacted_date 
            THEN n.WRITTEN_AT 
        END) as most_recent_news_date
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON l.advisor_crd = rc.RIA_CONTACT_CRD_ID
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contact_news` cn
        ON rc.ID = cn.RIA_CONTACT_ID
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.news_ps` n
        ON cn.NEWS_ID = n.ID
    GROUP BY 1, 2, 3, 4
),

-- Calculate conversion rates by news status
news_conversion_summary AS (
    SELECT 
        CASE 
            WHEN news_count_90d > 0 THEN 'Has Recent News (90d)'
            WHEN news_count_180d > 0 THEN 'Has News (90-180d)'
            ELSE 'No News'
        END as news_status,
        COUNT(*) as leads,
        SUM(target) as conversions,
        ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
        ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline  -- 3.82% baseline
    FROM lead_news
    GROUP BY 1
)

SELECT 
    news_status,
    leads,
    conversions,
    conversion_rate_pct,
    lift_vs_baseline,
    ROUND(leads * 100.0 / SUM(leads) OVER(), 2) as pct_of_total
FROM news_conversion_summary
ORDER BY 
    CASE news_status 
        WHEN 'Has Recent News (90d)' THEN 1 
        WHEN 'Has News (90-180d)' THEN 2 
        ELSE 3 
    END;


-- =============================================================================
-- PART 2: Detailed Analysis - News recency effect
-- =============================================================================

WITH lead_news AS (
    SELECT 
        l.lead_id,
        l.advisor_crd,
        l.contacted_date,
        l.target,
        COUNT(DISTINCT CASE 
            WHEN n.WRITTEN_AT >= DATE_SUB(l.contacted_date, INTERVAL 90 DAY)
                 AND n.WRITTEN_AT < l.contacted_date
            THEN n.ID 
        END) as news_count_90d,
        MAX(CASE 
            WHEN n.WRITTEN_AT < l.contacted_date 
            THEN n.WRITTEN_AT 
        END) as most_recent_news_date
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON l.advisor_crd = rc.RIA_CONTACT_CRD_ID
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contact_news` cn
        ON rc.ID = cn.RIA_CONTACT_ID
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.news_ps` n
        ON cn.NEWS_ID = n.ID
    GROUP BY 1, 2, 3, 4
),

recency_buckets AS (
    SELECT 
        *,
        CASE 
            WHEN most_recent_news_date IS NULL THEN 'No News'
            WHEN DATE_DIFF(contacted_date, most_recent_news_date, DAY) <= 30 THEN '0-30 days'
            WHEN DATE_DIFF(contacted_date, most_recent_news_date, DAY) <= 60 THEN '31-60 days'
            WHEN DATE_DIFF(contacted_date, most_recent_news_date, DAY) <= 90 THEN '61-90 days'
            WHEN DATE_DIFF(contacted_date, most_recent_news_date, DAY) <= 180 THEN '91-180 days'
            WHEN DATE_DIFF(contacted_date, most_recent_news_date, DAY) <= 365 THEN '181-365 days'
            ELSE '365+ days'
        END as news_recency_bucket
    FROM lead_news
)

SELECT 
    news_recency_bucket,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline
FROM recency_buckets
GROUP BY 1
ORDER BY 
    CASE news_recency_bucket
        WHEN '0-30 days' THEN 1
        WHEN '31-60 days' THEN 2
        WHEN '61-90 days' THEN 3
        WHEN '91-180 days' THEN 4
        WHEN '181-365 days' THEN 5
        WHEN '365+ days' THEN 6
        ELSE 7
    END;


-- =============================================================================
-- PART 3: News Type Analysis - Which news types signal conversion?
-- =============================================================================

WITH lead_news_types AS (
    SELECT 
        l.lead_id,
        l.advisor_crd,
        l.contacted_date,
        l.target,
        n.NEWS_TYPE as news_type,
        n.WRITTEN_AT as news_date
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` l
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON l.advisor_crd = rc.RIA_CONTACT_CRD_ID
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contact_news` cn
        ON rc.ID = cn.RIA_CONTACT_ID
    INNER JOIN `savvy-gtm-analytics.FinTrx_data_CA.news_ps` n
        ON cn.NEWS_ID = n.ID
    WHERE n.WRITTEN_AT >= DATE_SUB(l.contacted_date, INTERVAL 90 DAY)
      AND n.WRITTEN_AT < l.contacted_date
),

news_type_summary AS (
    SELECT 
        COALESCE(news_type, 'Unknown') as news_type,
        COUNT(DISTINCT lead_id) as leads_with_news_type,
        SUM(target) as conversions,
        ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
        ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline
    FROM lead_news_types
    GROUP BY 1
    HAVING COUNT(DISTINCT lead_id) >= 10  -- Minimum sample size
)

SELECT *
FROM news_type_summary
ORDER BY lift_vs_baseline DESC;


-- =============================================================================
-- PART 4: Statistical Significance Test
-- =============================================================================

WITH lead_news AS (
    SELECT 
        l.lead_id,
        l.target,
        CASE 
            WHEN COUNT(DISTINCT CASE 
                WHEN n.WRITTEN_AT >= DATE_SUB(l.contacted_date, INTERVAL 90 DAY)
                     AND n.WRITTEN_AT < l.contacted_date
                THEN n.ID 
            END) > 0 THEN 1 
            ELSE 0 
        END as has_recent_news
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON l.advisor_crd = rc.RIA_CONTACT_CRD_ID
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contact_news` cn
        ON rc.ID = cn.RIA_CONTACT_ID
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.news_ps` n
        ON cn.NEWS_ID = n.ID
    GROUP BY 1, 2
),

stats AS (
    SELECT 
        has_recent_news,
        COUNT(*) as n,
        SUM(target) as conversions,
        AVG(target) as p,
        STDDEV(target) as std
    FROM lead_news
    GROUP BY 1
)

SELECT 
    'News vs No News Comparison' as test_name,
    MAX(CASE WHEN has_recent_news = 1 THEN n END) as news_sample_size,
    MAX(CASE WHEN has_recent_news = 0 THEN n END) as no_news_sample_size,
    ROUND(MAX(CASE WHEN has_recent_news = 1 THEN p END) * 100, 3) as news_conv_rate_pct,
    ROUND(MAX(CASE WHEN has_recent_news = 0 THEN p END) * 100, 3) as no_news_conv_rate_pct,
    ROUND((MAX(CASE WHEN has_recent_news = 1 THEN p END) - 
           MAX(CASE WHEN has_recent_news = 0 THEN p END)) * 100, 3) as rate_diff_pp,
    ROUND(MAX(CASE WHEN has_recent_news = 1 THEN p END) / 
          NULLIF(MAX(CASE WHEN has_recent_news = 0 THEN p END), 0), 2) as relative_lift,
    -- Z-score for two-proportion test
    ROUND(
        (MAX(CASE WHEN has_recent_news = 1 THEN p END) - 
         MAX(CASE WHEN has_recent_news = 0 THEN p END)) /
        SQRT(
            (MAX(CASE WHEN has_recent_news = 1 THEN p END) * (1 - MAX(CASE WHEN has_recent_news = 1 THEN p END)) / 
             MAX(CASE WHEN has_recent_news = 1 THEN n END)) +
            (MAX(CASE WHEN has_recent_news = 0 THEN p END) * (1 - MAX(CASE WHEN has_recent_news = 0 THEN p END)) / 
             MAX(CASE WHEN has_recent_news = 0 THEN n END))
        ), 2
    ) as z_score,
    -- Note: Z-score > 1.96 = statistically significant at p < 0.05
    CASE 
        WHEN ABS(
            (MAX(CASE WHEN has_recent_news = 1 THEN p END) - 
             MAX(CASE WHEN has_recent_news = 0 THEN p END)) /
            SQRT(
                (MAX(CASE WHEN has_recent_news = 1 THEN p END) * (1 - MAX(CASE WHEN has_recent_news = 1 THEN p END)) / 
                 MAX(CASE WHEN has_recent_news = 1 THEN n END)) +
                (MAX(CASE WHEN has_recent_news = 0 THEN p END) * (1 - MAX(CASE WHEN has_recent_news = 0 THEN p END)) / 
                 MAX(CASE WHEN has_recent_news = 0 THEN n END))
            )
        ) >= 1.96 THEN 'YES (p < 0.05)'
        ELSE 'NO'
    END as statistically_significant
FROM stats;


-- =============================================================================
-- PART 5: Interaction with V3 Tiers - Does news amplify tier performance?
-- =============================================================================

WITH lead_news AS (
    SELECT 
        l.lead_id,
        l.advisor_crd,
        l.contacted_date,
        l.target,
        CASE 
            WHEN COUNT(DISTINCT CASE 
                WHEN n.WRITTEN_AT >= DATE_SUB(l.contacted_date, INTERVAL 90 DAY)
                     AND n.WRITTEN_AT < l.contacted_date
                THEN n.ID 
            END) > 0 THEN 'Has Recent News' 
            ELSE 'No News' 
        END as news_status
    FROM `savvy-gtm-analytics.ml_features.lead_scoring_features_pit` l
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` rc
        ON l.advisor_crd = rc.RIA_CONTACT_CRD_ID
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contact_news` cn
        ON rc.ID = cn.RIA_CONTACT_ID
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.news_ps` n
        ON cn.NEWS_ID = n.ID
    GROUP BY 1, 2, 3, 4
),

-- Join with V3 scores if available
lead_with_tiers AS (
    SELECT 
        ln.*,
        COALESCE(v3.score_tier, 'UNKNOWN') as v3_tier
    FROM lead_news ln
    LEFT JOIN `savvy-gtm-analytics.ml_features.lead_scores_v3` v3
        ON ln.lead_id = v3.lead_id
)

SELECT 
    v3_tier,
    news_status,
    COUNT(*) as leads,
    SUM(target) as conversions,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct,
    ROUND(AVG(target) / 0.0382, 2) as lift_vs_baseline
FROM lead_with_tiers
WHERE v3_tier IN ('TIER_1A_PRIME_MOVER_CFP', 'TIER_1B_PRIME_MOVER_SERIES65', 
                  'TIER_1_PRIME_MOVER', 'TIER_2_PROVEN_MOVER', 'TIER_3_MODERATE_BLEEDER',
                  'STANDARD')
GROUP BY 1, 2
HAVING COUNT(*) >= 5
ORDER BY v3_tier, news_status;