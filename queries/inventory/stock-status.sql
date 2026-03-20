-- ================================================================
-- 파일: stock-status.sql
-- 목적: 전 상품의 현재 재고 현황과 소진 예측일을 조회합니다.
--       최근 30일 일평균 판매량 기반으로 재고 소진 예상일(days_of_stock)을 계산하고,
--       긴급/주의/양호/저회전 4단계로 상태를 분류합니다.
--       일일 재고 점검, 발주 계획 수립, 재고 대시보드에 활용됩니다.
-- ================================================================
--
-- ■ 파라미터
--   없음 (전체 재고 자동 조회)
--
-- ■ 출력 컬럼
--   sku              STRING   SKU 코드
--   product_name     STRING   상품명
--   warehouse        STRING   창고명
--   current_stock    INT64    현재 재고 수량
--   avg_daily_sales  FLOAT64  최근 30일 일평균 판매량
--   days_of_stock    FLOAT64  재고 소진 예상일 (일)
--   status           STRING   재고 상태 (긴급/주의/양호/저회전)
--
-- ■ 실행 방법
--   bq_run_sql queries/inventory/stock-status.sql
--
-- ■ 예시 출력
--   sku         | product_name         | warehouse      | current_stock | avg_daily_sales | days_of_stock | status
--   ACS06789    | 아이폰15 울트라케이스| coupang_rocket | 45            | 12.3            | 4             | 긴급
--   AGL07123    | 갤럭시S24 강화유리   | own_warehouse  | 280           | 8.5             | 33            | 양호
--   ACS09999    | 아이패드 폴리오      | own_warehouse  | 500           | 0.0             | NULL          | 저회전
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
