-- ad-spend-efficiency.sql
-- 일별 광고비 효율 분석 (CPC, CPM, CPA 추이)
-- $1: 시작일, $2: 종료일

SELECT
  DATE(report_date) AS report_date,
  platform,
  SUM(ad_spend) AS daily_spend,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(attributed_orders) AS orders,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(clicks)), 0) AS cpc,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(impressions)) * 1000, 0) AS cpm,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)), 0) AS cpa,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(attributed_orders), SUM(clicks)) * 100, 2) AS cvr_pct,
  ROUND(SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)), 2) AS roas,

  -- 전일 대비 CPC 변화율
  ROUND(
    SAFE_DIVIDE(
      SAFE_DIVIDE(SUM(ad_spend), SUM(clicks))
        - LAG(SAFE_DIVIDE(SUM(ad_spend), SUM(clicks))) OVER (PARTITION BY platform ORDER BY DATE(report_date)),
      LAG(SAFE_DIVIDE(SUM(ad_spend), SUM(clicks))) OVER (PARTITION BY platform ORDER BY DATE(report_date))
    ) * 100, 1
  ) AS cpc_change_pct,

  -- 효율 등급
  CASE
    WHEN SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)) <= 3000 THEN '🟢 고효율'
    WHEN SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)) <= 5000 THEN '🟡 보통'
    WHEN SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)) <= 8000 THEN '🟠 비효율'
    ELSE '🔴 과다지출'
  END AS spend_efficiency

FROM `${BQ_DATASET}.ad_campaigns`
WHERE DATE(report_date) BETWEEN '$1' AND '$2'
GROUP BY report_date, platform
ORDER BY report_date DESC, platform
