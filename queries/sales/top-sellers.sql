-- top-sellers.sql
-- 베스트셀러 TOP N (기간 지정)
-- ================================================================
-- @param_count  3
-- @param  $1  DATE     필수  시작일 (YYYY-MM-DD)
-- @param  $2  DATE     필수  종료일 (YYYY-MM-DD)
-- @param  $3  INTEGER  필수  상위 N개
-- @example  bq_run_sql queries/sales/top-sellers.sql "2026-03-01" "2026-03-19" 20
-- ================================================================

SELECT
  product_id,
  product_name,
  sku,
  SUM(quantity) AS total_qty,
  SUM(revenue) AS total_revenue,
  COUNT(DISTINCT order_id) AS order_count,
  ROUND(AVG(unit_price), 0) AS avg_price,
  ROUND(SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) * 100, 1) AS gpm_pct
FROM `${BQ_DATASET}.orders`
WHERE DATE(order_date) BETWEEN '$1' AND '$2'
GROUP BY product_id, product_name, sku
ORDER BY total_revenue DESC
LIMIT $3
