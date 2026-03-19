-- weekly-trend.sql
-- 주간 매출 트렌드 (최근 N주)

SELECT
  DATE_TRUNC(DATE(order_date), WEEK(MONDAY)) AS week_start,
  channel,
  COUNT(DISTINCT order_id) AS orders,
  SUM(revenue) AS revenue,
  SUM(revenue) - SUM(cost) AS profit,
  ROUND(SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) * 100, 1) AS gpm_pct,
  -- 전주 대비 증감률
  ROUND(
    SAFE_DIVIDE(
      SUM(revenue) - LAG(SUM(revenue)) OVER (PARTITION BY channel ORDER BY DATE_TRUNC(DATE(order_date), WEEK(MONDAY))),
      LAG(SUM(revenue)) OVER (PARTITION BY channel ORDER BY DATE_TRUNC(DATE(order_date), WEEK(MONDAY)))
    ) * 100, 1
  ) AS wow_change_pct
FROM `${BQ_DATASET}.orders`
WHERE DATE(order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 WEEK)
GROUP BY week_start, channel
ORDER BY week_start DESC, revenue DESC
