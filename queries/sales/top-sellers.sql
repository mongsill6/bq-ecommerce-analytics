-- ================================================================
-- 파일: top-sellers.sql
-- 목적: 지정 기간 동안 매출 기준 베스트셀러 상위 N개 상품을 조회합니다.
--       상품별 판매 수량, 매출, 주문 수, 평균 판매가, GPM을 제공합니다.
--       월간/주간 베스트셀러 리포트, 재고 우선순위 결정에 활용됩니다.
-- ================================================================
--
-- ■ 파라미터
--   $1  DATE     필수  시작일 (YYYY-MM-DD)
--   $2  DATE     필수  종료일 (YYYY-MM-DD)
--   $3  INTEGER  필수  상위 N개 (예: 10, 20, 50)
--
-- ■ 출력 컬럼
--   product_id    STRING   상품 ID
--   product_name  STRING   상품명
--   sku           STRING   SKU 코드
--   total_qty     INT64    총 판매 수량
--   total_revenue FLOAT64  총 매출액
--   order_count   INT64    고유 주문 수
--   avg_price     FLOAT64  평균 판매 단가 (원)
--   gpm_pct       FLOAT64  매출총이익률 (%)
--
-- ■ 실행 방법
--   bq_run_sql queries/sales/top-sellers.sql "2026-03-01" "2026-03-19" 20
--
-- ■ 예시 출력
--   product_id | product_name            | sku          | total_qty | total_revenue | order_count | avg_price | gpm_pct
--   P001       | 아이폰15 케이스 울트라  | ACS06789     | 520       | 15600000      | 480         | 30000     | 55.2
--   P002       | 갤럭시S24 강화유리      | AGL07123     | 380       | 7600000       | 350         | 20000     | 48.7
--
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
