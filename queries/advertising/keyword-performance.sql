-- keyword-performance.sql
-- 키워드별 클릭/전환/ROAS 분석
-- $1: 시작일, $2: 종료일

SELECT
  keyword,
  match_type,
  campaign_name,
  platform,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  SUM(ad_spend) AS keyword_spend,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(clicks)), 0) AS cpc,
  SUM(attributed_orders) AS conversions,
  ROUND(SAFE_DIVIDE(SUM(attributed_orders), SUM(clicks)) * 100, 2) AS cvr_pct,
  SUM(attributed_revenue) AS revenue,
  ROUND(SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)), 2) AS roas,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)), 0) AS cpa,

  -- 키워드 효율 등급
  CASE
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 5 THEN '🟢 핵심 키워드'
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 3 THEN '🟡 유지 키워드'
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 1 THEN '🟠 개선 필요'
    ELSE '🔴 중단 검토'
  END AS keyword_grade,

  -- 클릭 대비 전환 효율
  CASE
    WHEN SUM(clicks) >= 100 AND SAFE_DIVIDE(SUM(attributed_orders), SUM(clicks)) >= 0.05 THEN '높은 전환'
    WHEN SUM(clicks) >= 100 AND SAFE_DIVIDE(SUM(attributed_orders), SUM(clicks)) < 0.01 THEN '낮은 전환'
    WHEN SUM(clicks) < 10 THEN '데이터 부족'
    ELSE '보통'
  END AS conversion_quality

FROM `${BQ_DATASET}.ad_keywords`
WHERE DATE(report_date) BETWEEN '$1' AND '$2'
GROUP BY keyword, match_type, campaign_name, platform
HAVING SUM(impressions) > 0
ORDER BY keyword_spend DESC
