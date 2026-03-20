-- ================================================================
-- 파일: rocket-delivery-risk.sql
-- 목적: 쿠팡 로켓배송 채널 전용 재고 위험 감지 쿼리입니다.
--       14일 이내 소진 예상 상품만 필터링하여 즉시 대응이 필요한 SKU를 식별합니다.
--       판매 가속도(최근7일 vs 이전7일)를 계산하여 급증 추세를 조기에 감지합니다.
--       로켓배송 품절 방지, 긴급 입고 판단, 일일 알림에 활용됩니다.
-- ================================================================
--
-- ■ 파라미터
--   없음 (coupang_rocket 채널 자동 필터링)
--
-- ■ 출력 컬럼
--   sku                    STRING   SKU 코드
--   product_name           STRING   상품명
--   rocket_stock           INT64    로켓배송 창고 현재 재고
--   avg_daily_sales        FLOAT64  14일 일평균 판매량
--   peak_daily_sales       FLOAT64  14일 내 최대 일판매량
--   days_remaining         FLOAT64  잔여 재고일 (현재고 / 일평균)
--   sales_acceleration_pct FLOAT64  판매 가속도 (%, 양수=증가추세)
--   risk_level             STRING   위험 등급 (즉시입고/입고필요/모니터링/안전)
--
-- ■ 실행 방법
--   bq_run_sql queries/inventory/rocket-delivery-risk.sql
--
-- ■ 예시 출력
--   sku       | product_name          | rocket_stock | avg_daily_sales | peak_daily_sales | days_remaining | sales_acceleration_pct | risk_level
--   ACS06789  | 아이폰15 울트라케이스 | 15           | 8.2             | 25               | 2              | 32.5                   | 즉시 입고
--   AGL07123  | 갤럭시S24 강화유리    | 42           | 5.1             | 12               | 8              | -5.3                   | 모니터링
--
-- ================================================================

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
