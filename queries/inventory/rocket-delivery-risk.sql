-- rocket-delivery-risk.sql
-- 로켓배송 재고 위험 감지 (소진 임박 상품)

WITH rocket_sales AS (
  SELECT
    sku,
    product_name,
    DATE(order_date) AS sale_date,
    SUM(quantity) AS daily_qty
  FROM `${BQ_DATASET}.orders`
  WHERE channel = 'coupang_rocket'
    AND DATE(order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
  GROUP BY sku, product_name, sale_date
),
sales_stats AS (
  SELECT
    sku,
    ANY_VALUE(product_name) AS product_name,
    AVG(daily_qty) AS avg_daily,
    MAX(daily_qty) AS peak_daily,
    -- 최근 7일 평균 vs 이전 7일 평균 (가속도)
    AVG(IF(sale_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), daily_qty, NULL)) AS recent_7d_avg,
    AVG(IF(sale_date < DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), daily_qty, NULL)) AS prev_7d_avg
  FROM rocket_sales
  GROUP BY sku
)
SELECT
  ss.sku,
  ss.product_name,
  i.current_stock AS rocket_stock,
  ROUND(ss.avg_daily, 1) AS avg_daily_sales,
  ROUND(ss.peak_daily, 0) AS peak_daily_sales,
  ROUND(SAFE_DIVIDE(i.current_stock, ss.avg_daily), 0) AS days_remaining,
  ROUND(SAFE_DIVIDE(ss.recent_7d_avg - ss.prev_7d_avg, ss.prev_7d_avg) * 100, 1) AS sales_acceleration_pct,
  CASE
    WHEN SAFE_DIVIDE(i.current_stock, ss.avg_daily) < 3 THEN '🚨 즉시 입고'
    WHEN SAFE_DIVIDE(i.current_stock, ss.avg_daily) < 7 THEN '⚠️ 입고 필요'
    WHEN SAFE_DIVIDE(i.current_stock, ss.avg_daily) < 14 THEN '📋 모니터링'
    ELSE '✅ 안전'
  END AS risk_level
FROM sales_stats ss
JOIN `${BQ_DATASET}.inventory` i ON ss.sku = i.sku AND i.warehouse = 'coupang_rocket'
WHERE SAFE_DIVIDE(i.current_stock, ss.avg_daily) < 14
ORDER BY days_remaining ASC
