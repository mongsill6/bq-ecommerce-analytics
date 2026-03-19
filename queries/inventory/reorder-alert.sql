-- reorder-alert.sql
-- 안전재고 기준 발주 필요 상품 알림 (리드타임 고려)
-- 파라미터: $1 = 기본 리드타임 일수 (기본값 7일)

WITH daily_sales AS (
  SELECT
    sku,
    DATE(order_date) AS sale_date,
    SUM(quantity) AS daily_qty
  FROM `${BQ_DATASET}.orders`
  WHERE DATE(order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY sku, sale_date
),
sales_stats AS (
  SELECT
    sku,
    AVG(daily_qty) AS avg_daily_sales,
    STDDEV(daily_qty) AS sales_stddev,
    MAX(daily_qty) AS max_daily_sales,
    COUNT(DISTINCT sale_date) AS active_days
  FROM daily_sales
  GROUP BY sku
),
reorder_calc AS (
  SELECT
    i.sku,
    i.product_name,
    i.warehouse,
    i.current_stock,
    ROUND(ss.avg_daily_sales, 1) AS avg_daily_sales,
    ROUND(IFNULL(ss.sales_stddev, 0), 1) AS sales_stddev,
    -- 리드타임 (일): 파라미터 또는 기본 7일
    IFNULL(CAST($1 AS INT64), 7) AS lead_time_days,
    -- 리드타임 중 예상 소비량
    ROUND(ss.avg_daily_sales * IFNULL(CAST($1 AS INT64), 7), 0) AS lead_time_demand,
    -- 안전재고 = 서비스 레벨 Z(1.65 ≈ 95%) × σ × √리드타임
    ROUND(1.65 * IFNULL(ss.sales_stddev, 0) * SQRT(IFNULL(CAST($1 AS INT64), 7)), 0) AS safety_stock,
    -- 발주점(ROP) = 리드타임 수요 + 안전재고
    ROUND(
      ss.avg_daily_sales * IFNULL(CAST($1 AS INT64), 7)
      + 1.65 * IFNULL(ss.sales_stddev, 0) * SQRT(IFNULL(CAST($1 AS INT64), 7)),
    0) AS reorder_point,
    -- 현재 재고 소진 예상일
    ROUND(SAFE_DIVIDE(i.current_stock, ss.avg_daily_sales), 0) AS days_of_stock,
    ss.active_days
  FROM `${BQ_DATASET}.inventory` i
  LEFT JOIN sales_stats ss ON i.sku = ss.sku
  WHERE ss.avg_daily_sales > 0
)
SELECT
  sku,
  product_name,
  warehouse,
  current_stock,
  avg_daily_sales,
  sales_stddev,
  lead_time_days,
  lead_time_demand,
  safety_stock,
  reorder_point,
  days_of_stock,
  -- 발주 필요 수량 (ROP - 현재고, 음수면 0)
  GREATEST(reorder_point - current_stock, 0) AS order_quantity,
  -- 발주까지 남은 여유일 (현재고가 ROP 도달까지)
  ROUND(SAFE_DIVIDE(current_stock - reorder_point, avg_daily_sales), 0) AS days_until_reorder,
  CASE
    WHEN current_stock <= safety_stock THEN '🔴 긴급발주'
    WHEN current_stock <= reorder_point THEN '🟡 발주필요'
    WHEN current_stock <= reorder_point * 1.2 THEN '🟢 발주임박'
    ELSE '⚪ 여유'
  END AS alert_level
FROM reorder_calc
WHERE current_stock <= reorder_point * 1.2
ORDER BY
  CASE
    WHEN current_stock <= safety_stock THEN 1
    WHEN current_stock <= reorder_point THEN 2
    ELSE 3
  END,
  days_of_stock ASC
