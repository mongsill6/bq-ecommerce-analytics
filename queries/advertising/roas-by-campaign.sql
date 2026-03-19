-- roas-by-campaign.sql
-- 캠페인별 ROAS (Return on Ad Spend) 분석
-- $1: 시작일, $2: 종료일

SELECT
  campaign_id,
  campaign_name,
  platform,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  SUM(ad_spend) AS total_spend,
  SUM(attributed_revenue) AS attributed_revenue,
  ROUND(SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)), 2) AS roas,
  SUM(attributed_orders) AS orders,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)), 0) AS cpa,
  CASE
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 5 THEN '🟢 우수'
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 3 THEN '🟡 양호'
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 1 THEN '🟠 주의'
    ELSE '🔴 적자'
  END AS efficiency
FROM `${BQ_DATASET}.ad_campaigns`
WHERE DATE(report_date) BETWEEN '$1' AND '$2'
GROUP BY campaign_id, campaign_name, platform
ORDER BY total_spend DESC
