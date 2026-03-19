-- daily-sales-summary.sql
-- 일간 매출 요약 (채널별/카테고리별)
-- ================================================================
-- @param_count  1
-- @param  $1  DATE  필수  조회 날짜 (YYYY-MM-DD)
-- @example  bq_run_sql queries/sales/daily-sales-summary.sql "2026-03-19"
-- ================================================================

SELECT
  DATE(order_date) AS sale_date,
  channel,
  category,
  COUNT(DISTINCT order_id) AS order_count,
  SUM(quantity) AS total_qty,
  SUM(revenue) AS total_revenue,
  SUM(cost) AS total_cost,
  SUM(revenue) - SUM(cost) AS gross_profit,
  SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) * 100 AS gpm_pct
FROM `${BQ_DATASET}.orders`
WHERE DATE(order_date) = '$1'
GROUP BY sale_date, channel, category
ORDER BY total_revenue DESC
