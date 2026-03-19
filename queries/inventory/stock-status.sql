-- stock-status.sql
-- 현재 재고 현황 + 일평균 판매량 기반 소진 예측

WITH daily_sales AS (
  SELECT
    sku,
    DATE(order_date) AS sale_date,
    SUM(quantity) AS daily_qty
  FROM `${BQ_DATASET}.orders`
  WHERE DATE(order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY sku, sale_date
),
avg_sales AS (
  SELECT
    sku,
    AVG(daily_qty) AS avg_daily_sales,
    STDDEV(daily_qty) AS sales_stddev
  FROM daily_sales
  GROUP BY sku
)
SELECT
  s.sku,
  s.product_name,
  s.warehouse,
  s.current_stock,
  ROUND(a.avg_daily_sales, 1) AS avg_daily_sales,
  CASE
    WHEN a.avg_daily_sales > 0 THEN ROUND(s.current_stock / a.avg_daily_sales, 0)
    ELSE NULL
  END AS days_of_stock,
  CASE
    WHEN a.avg_daily_sales > 0 AND s.current_stock / a.avg_daily_sales < 7 THEN '🔴 긴급'
    WHEN a.avg_daily_sales > 0 AND s.current_stock / a.avg_daily_sales < 14 THEN '🟡 주의'
    WHEN a.avg_daily_sales > 0 AND s.current_stock / a.avg_daily_sales < 30 THEN '🟢 양호'
    ELSE '⚪ 저회전'
  END AS status
FROM `${BQ_DATASET}.inventory` s
LEFT JOIN avg_sales a ON s.sku = a.sku
ORDER BY days_of_stock ASC NULLS LAST
