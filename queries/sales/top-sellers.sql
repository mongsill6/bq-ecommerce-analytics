-- top-sellers.sql
-- 베스트셀러 TOP N (기간 지정)
-- $1: 시작일, $2: 종료일, $3: TOP N

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
