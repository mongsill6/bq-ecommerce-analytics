-- ================================================================
-- 파일: gpm-analysis.sql
-- 목적: 상품별 GPM(Gross Profit Margin, 매출총이익률)을 분석합니다.
--       SKU × 채널별로 매출, 원가(COGS), 매출총이익, GPM을 산출하고,
--       고수익(>=40%)/보통(>=25%)/저수익(>=10%)/적자위험(<10%) 4단계로 분류합니다.
--       10개 이상 판매된 상품만 포함하여 유의미한 분석을 보장합니다.
--       가격 정책 점검, 수익성 개선 대상 발굴, 채널별 마진 비교에 활용됩니다.
-- ================================================================
--
-- ■ 파라미터
--   $1  DATE  필수  시작일 (YYYY-MM-DD)
--   $2  DATE  필수  종료일 (YYYY-MM-DD)
--
-- ■ 출력 컬럼
--   sku               STRING   SKU 코드
--   product_name      STRING   상품명
--   category          STRING   상품 카테고리
--   channel           STRING   판매 채널
--   total_qty         INT64    총 판매 수량
--   revenue           FLOAT64  총 매출액 (원)
--   cogs              FLOAT64  총 원가 (원, Cost of Goods Sold)
--   gross_profit      FLOAT64  매출총이익 (원)
--   gpm_pct           FLOAT64  매출총이익률 (%)
--   avg_selling_price FLOAT64  평균 판매 단가 (원)
--   avg_unit_cost     FLOAT64  평균 단위 원가 (원)
--   gpm_tier          STRING   GPM 등급 (고수익/보통/저수익/적자위험)
--
-- ■ 실행 방법
--   bq_run_sql queries/product/gpm-analysis.sql "2026-03-01" "2026-03-19"
--
-- ■ 예시 출력
--   sku       | product_name          | category | channel | total_qty | revenue    | cogs     | gross_profit | gpm_pct | avg_selling_price | gpm_tier
--   ACS06789  | 아이폰15 울트라케이스 | case     | coupang | 520       | 15600000   | 6240000  | 9360000      | 60.0    | 30000             | 고수익
--   AGL07123  | 갤럭시S24 강화유리    | film     | naver   | 380       | 7600000    | 5320000  | 2280000      | 30.0    | 20000             | 보통
--   ACS08888  | 보급형 범퍼케이스     | case     | coupang | 200       | 2000000    | 1800000  | 200000       | 10.0    | 10000             | 저수익
--
-- ================================================================

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
