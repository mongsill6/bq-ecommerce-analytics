-- ================================================================
-- 파일: daily-sales-summary.sql
-- 목적: 특정 날짜의 채널별·카테고리별 매출 실적을 요약합니다.
--       일간 리포트, KPI 대시보드, 일일 브리핑에 활용됩니다.
--       주문 수, 판매 수량, 매출, 원가, 매출총이익(GP), GPM을 산출합니다.
-- ================================================================
--
-- ■ 파라미터
--   $1  DATE  필수  조회 날짜 (YYYY-MM-DD)
--
-- ■ 출력 컬럼
--   sale_date       DATE     주문일
--   channel         STRING   판매 채널 (coupang, naver, amazon 등)
--   category        STRING   상품 카테고리
--   order_count     INT64    고유 주문 수
--   total_qty       INT64    총 판매 수량
--   total_revenue   FLOAT64  총 매출액
--   total_cost      FLOAT64  총 원가
--   gross_profit    FLOAT64  매출총이익 (매출 - 원가)
--   gpm_pct         FLOAT64  매출총이익률 (%)
--
-- ■ 실행 방법
--   bq_run_sql queries/sales/daily-sales-summary.sql "2026-03-19"
--
-- ■ 예시 출력
--   sale_date   | channel  | category | order_count | total_qty | total_revenue | total_cost | gross_profit | gpm_pct
--   2026-03-19  | coupang  | case     | 150         | 320       | 12800000      | 6400000    | 6400000      | 50.0
--   2026-03-19  | naver    | film     | 85          | 170       | 5100000       | 2550000    | 2550000      | 50.0
--
-- ================================================================

SELECT
  DATE(order_date) AS sale_date,
  channel,
  category,
  COUNT(DISTINCT order_id) AS order_count,
  SUM(quantity) AS total_qty,
  SUM(revenue) AS total_revenue,
  SUM(cost) AS total_cost,
  SUM(revenue) - SUM(cost) AS gross_profit,
  SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) * 100 AS gpm_pct
FROM `${BQ_DATASET}.orders`
WHERE DATE(order_date) = '$1'
GROUP BY sale_date, channel, category
ORDER BY total_revenue DESC
