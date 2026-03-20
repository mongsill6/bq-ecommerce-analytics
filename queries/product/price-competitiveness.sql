-- ================================================================
-- 파일: price-competitiveness.sql
-- 목적: 카테고리·채널 내 가격 포지셔닝과 경쟁력을 분석합니다.
--       카테고리 평균가 대비 가격 지수(Price Index)와 백분위를 산출하고,
--       가격대를 저가~고가 5단계로 분류합니다.
--       가격+마진 조합으로 경쟁력 라벨을 자동 판정합니다:
--       가격우위+고마진 / 가격우위+저마진 / 적정가격 / 프리미엄 / 고가(판매부진)
--       가격 전략 수립, 할인 정책 검토, 프리미엄 포지셔닝 평가에 활용됩니다.
--       5개 이상 판매된 상품만 포함합니다.
-- ================================================================
--
-- ■ 파라미터
--   $1  DATE  필수  시작일 (YYYY-MM-DD)
--   $2  DATE  필수  종료일 (YYYY-MM-DD)
--
-- ■ 출력 컬럼
--   sku                   STRING   SKU 코드
--   product_name          STRING   상품명
--   category              STRING   상품 카테고리
--   channel               STRING   판매 채널
--   avg_selling_price     FLOAT64  평균 판매가 (원)
--   category_avg_price    FLOAT64  카테고리 평균가 (원)
--   price_index           FLOAT64  가격 지수 (%, 100=카테고리 평균)
--   price_percentile      FLOAT64  카테고리 내 가격 백분위 (%)
--   total_qty             INT64    총 판매 수량
--   revenue               FLOAT64  총 매출액 (원)
--   margin_pct            FLOAT64  평균 마진율 (%)
--   price_tier            STRING   가격대 (저가/중저가/중간/중고가/고가)
--   competitiveness_label STRING   경쟁력 판정 결과
--   pct_of_max_price      FLOAT64  카테고리 최고가 대비 비율 (%)
--   category_sku_count    INT64    카테고리 내 SKU 수
--
-- ■ 실행 방법
--   bq_run_sql queries/product/price-competitiveness.sql "2026-03-01" "2026-03-19"
--
-- ■ 예시 출력
--   sku       | product_name   | category | avg_selling_price | category_avg_price | price_index | price_percentile | margin_pct | price_tier | competitiveness_label
--   ACS06789  | 울트라 케이스  | case     | 30000             | 25000              | 120.0       | 85.0             | 55.2       | 중고가     | 프리미엄(판매호조)
--   ACS05555  | 에어핏 케이스  | case     | 18000             | 25000              | 72.0        | 25.0             | 35.0       | 중저가     | 가격우위+고마진
--   ACS09999  | 고급 가죽케이스| case     | 55000             | 25000              | 220.0       | 100.0            | 62.0       | 고가       | 고가(판매부진)
--
-- ================================================================

WITH product_prices AS (
  -- 자사 상품 가격 및 판매 데이터
  SELECT
    sku,
    product_name,
    category,
    channel,
    AVG(unit_price) AS avg_price,
    AVG(unit_cost) AS avg_cost,
    SUM(quantity) AS total_qty,
    SUM(revenue) AS total_revenue,
    AVG(SAFE_DIVIDE(unit_price - unit_cost, unit_price)) * 100 AS avg_margin_pct
  FROM `${BQ_DATASET}.orders`
  WHERE DATE(order_date) BETWEEN '$1' AND '$2'
  GROUP BY sku, product_name, category, channel
),

category_stats AS (
  -- 카테고리별 가격 통계 (경쟁 포지션 산출용)
  SELECT
    category,
    channel,
    AVG(avg_price) AS cat_avg_price,
    MIN(avg_price) AS cat_min_price,
    MAX(avg_price) AS cat_max_price,
    APPROX_QUANTILES(avg_price, 100) AS price_quantiles,
    COUNT(DISTINCT sku) AS sku_count
  FROM product_prices
  GROUP BY category, channel
),

price_bands AS (
  -- 가격대별 판매량 분포
  SELECT
    p.category,
    p.channel,
    CASE
      WHEN p.avg_price < cs.cat_avg_price * 0.7 THEN '① 저가 (~70%)'
      WHEN p.avg_price < cs.cat_avg_price * 0.9 THEN '② 중저가 (70~90%)'
      WHEN p.avg_price < cs.cat_avg_price * 1.1 THEN '③ 중간 (90~110%)'
      WHEN p.avg_price < cs.cat_avg_price * 1.3 THEN '④ 중고가 (110~130%)'
      ELSE '⑤ 고가 (130%~)'
    END AS price_band,
    COUNT(DISTINCT p.sku) AS sku_count,
    SUM(p.total_qty) AS band_total_qty,
    ROUND(AVG(p.avg_price), 0) AS band_avg_price,
    ROUND(AVG(p.avg_margin_pct), 1) AS band_avg_margin_pct
  FROM product_prices p
  JOIN category_stats cs
    ON p.category = cs.category AND p.channel = cs.channel
  GROUP BY p.category, p.channel, price_band
)

-- 메인: 상품별 가격 경쟁력 포지션
SELECT
  p.sku,
  p.product_name,
  p.category,
  p.channel,
  ROUND(p.avg_price, 0) AS avg_selling_price,
  ROUND(cs.cat_avg_price, 0) AS category_avg_price,
  -- 카테고리 평균 대비 가격 비율
  ROUND(SAFE_DIVIDE(p.avg_price, cs.cat_avg_price) * 100, 1) AS price_index,
  -- 카테고리 내 가격 백분위 (PERCENT_RANK)
  ROUND(
    SAFE_DIVIDE(p.avg_price - cs.cat_min_price, cs.cat_max_price - cs.cat_min_price) * 100,
    1
  ) AS price_percentile,
  p.total_qty,
  ROUND(p.total_revenue, 0) AS revenue,
  ROUND(p.avg_margin_pct, 1) AS margin_pct,
  -- 가격대 분류
  CASE
    WHEN p.avg_price < cs.cat_avg_price * 0.7 THEN '① 저가'
    WHEN p.avg_price < cs.cat_avg_price * 0.9 THEN '② 중저가'
    WHEN p.avg_price < cs.cat_avg_price * 1.1 THEN '③ 중간'
    WHEN p.avg_price < cs.cat_avg_price * 1.3 THEN '④ 중고가'
    ELSE '⑤ 고가'
  END AS price_tier,
  -- 가격 경쟁력 판정
  CASE
    WHEN p.avg_price < cs.cat_avg_price * 0.9 AND p.avg_margin_pct >= 25
      THEN '🟢 가격우위+고마진'
    WHEN p.avg_price < cs.cat_avg_price * 0.9 AND p.avg_margin_pct < 25
      THEN '🟡 가격우위+저마진'
    WHEN p.avg_price BETWEEN cs.cat_avg_price * 0.9 AND cs.cat_avg_price * 1.1
      THEN '🔵 적정가격'
    WHEN p.avg_price > cs.cat_avg_price * 1.1 AND p.total_qty >= 50
      THEN '🟣 프리미엄(판매호조)'
    WHEN p.avg_price > cs.cat_avg_price * 1.1 AND p.total_qty < 50
      THEN '🔴 고가(판매부진)'
    ELSE '⚪ 분류불가'
  END AS competitiveness_label,
  -- 할인율 영향도 (정가 대비 판매가 비율 추정)
  ROUND(SAFE_DIVIDE(p.avg_price, cs.cat_max_price) * 100, 1) AS pct_of_max_price,
  cs.sku_count AS category_sku_count
FROM product_prices p
JOIN category_stats cs
  ON p.category = cs.category AND p.channel = cs.channel
WHERE p.total_qty >= 5
ORDER BY p.category, price_percentile DESC
