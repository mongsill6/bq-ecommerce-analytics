-- gpm-analysis.sql
-- 상품별 GPM(매출총이익률) 분석
-- $1: 시작일, $2: 종료일

SELECT
  sku,
  product_name,
  category,
  channel,
  SUM(quantity) AS total_qty,
  ROUND(SUM(revenue), 0) AS revenue,
  ROUND(SUM(cost), 0) AS cogs,
  ROUND(SUM(revenue) - SUM(cost), 0) AS gross_profit,
  ROUND(SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) * 100, 1) AS gpm_pct,
  ROUND(AVG(unit_price), 0) AS avg_selling_price,
  ROUND(AVG(unit_cost), 0) AS avg_unit_cost,
  -- GPM 구간 분류
  CASE
    WHEN SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) >= 0.4 THEN '🟢 고수익'
    WHEN SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) >= 0.25 THEN '🟡 보통'
    WHEN SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) >= 0.1 THEN '🟠 저수익'
    ELSE '🔴 적자위험'
  END AS gpm_tier
FROM `${BQ_DATASET}.orders`
WHERE DATE(order_date) BETWEEN '$1' AND '$2'
GROUP BY sku, product_name, category, channel
HAVING SUM(quantity) >= 10
ORDER BY gross_profit DESC
