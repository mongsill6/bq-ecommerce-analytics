-- ================================================================
-- 파일: reorder-alert.sql
-- 목적: 안전재고(Safety Stock) 및 발주점(ROP) 기반으로 발주가 필요한 상품을 알림합니다.
--       리드타임을 고려하여 발주 시점과 발주 수량을 자동 계산합니다.
--       안전재고 산식: Z(1.65, 95% 서비스 레벨) x 판매표준편차 x sqrt(리드타임)
--       발주점(ROP) = 리드타임 수요 + 안전재고
--       ROP의 120% 이하인 상품만 출력하여 선제적 발주를 지원합니다.
-- ================================================================
--
-- ■ 파라미터
--   $1  INTEGER  선택  리드타임 일수 (기본값: 7)
--
-- ■ 출력 컬럼
--   sku                STRING   SKU 코드
--   product_name       STRING   상품명
--   warehouse          STRING   창고명
--   current_stock      INT64    현재 재고
--   avg_daily_sales    FLOAT64  30일 일평균 판매량
--   sales_stddev       FLOAT64  판매량 표준편차
--   lead_time_days     INT64    리드타임 (일)
--   lead_time_demand   FLOAT64  리드타임 중 예상 소비량
--   safety_stock       FLOAT64  안전재고 수량
--   reorder_point      FLOAT64  발주점 (ROP)
--   days_of_stock      FLOAT64  현재 재고 소진 예상일
--   order_quantity     FLOAT64  발주 필요 수량 (ROP - 현재고)
--   days_until_reorder FLOAT64  발주까지 남은 여유일
--   alert_level        STRING   알림 등급 (긴급발주/발주필요/발주임박/여유)
--
-- ■ 실행 방법
--   bq_run_sql queries/inventory/reorder-alert.sql 7
--   bq_run_sql queries/inventory/reorder-alert.sql 14    # 해외 발주 (14일 리드타임)
--   bq_run_sql queries/inventory/reorder-alert.sql       # 기본값 7일 적용
--
-- ■ 예시 출력
--   sku       | product_name  | warehouse | current_stock | avg_daily_sales | reorder_point | order_quantity | days_until_reorder | alert_level
--   ACS06789  | 아이폰15 울트라| coupang   | 30            | 12.3            | 110           | 80             | -7                 | 긴급발주
--   AGL07123  | 갤럭시S24 유리 | own       | 95            | 8.5             | 82            | 0              | 2                  | 발주임박
--
-- ================================================================

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
