-- ================================================================
-- 파일: depletion-forecast.sql
-- 목적: 이동평균(MA) 기반으로 재고 소진 시점을 정밀하게 예측합니다.
--       7일(단기), 14일(중기), 30일(장기) 이동평균을 비교하여
--       판매 트렌드의 방향(증가/감소/급증/급감)과 가속도를 파악합니다.
--       변동계수(CV)로 수요 불확실성을 정량화하고, 소진 예상 날짜를 제공합니다.
--       재고 전략 수립, 수요 예측 정밀화, 시즌 대응에 활용됩니다.
-- ================================================================
--
-- ■ 파라미터
--   없음 (최근 60일 데이터 기반 자동 분석)
--
-- ■ 출력 컬럼
--   sku                      STRING   SKU 코드
--   product_name             STRING   상품명
--   warehouse                STRING   창고명
--   current_stock            INT64    현재 재고 수량
--   ma_7d                    FLOAT64  7일 이동평균 (단기)
--   ma_14d                   FLOAT64  14일 이동평균 (중기)
--   ma_30d                   FLOAT64  30일 이동평균 (장기)
--   depletion_days_7d        FLOAT64  7일MA 기준 소진 예상일
--   depletion_days_14d       FLOAT64  14일MA 기준 소진 예상일
--   depletion_days_30d       FLOAT64  30일MA 기준 소진 예상일
--   estimated_depletion_date DATE     소진 예상 날짜 (7일MA 기준)
--   trend_pct                FLOAT64  추세 방향 (%, 단기MA vs 장기MA)
--   weekly_acceleration      FLOAT64  주간 가속도 (최근7일 - 이전7일 평균차)
--   demand_cv_pct            FLOAT64  수요 변동계수 (%, 높을수록 불확실)
--   forecast_status          STRING   소진 전망 (7일내/2주내/1개월내/여유)
--   trend_direction          STRING   트렌드 방향 (급증/증가/감소/급감)
--
-- ■ 실행 방법
--   bq_run_sql queries/inventory/depletion-forecast.sql
--
-- ■ 예시 출력
--   sku       | product_name   | current_stock | ma_7d | ma_14d | ma_30d | depletion_days_7d | estimated_depletion_date | trend_pct | forecast_status | trend_direction
--   ACS06789  | 아이폰15 울트라| 45            | 12.5  | 10.2   | 8.8    | 4                 | 2026-03-24               | 42.0      | 7일 내 소진     | 급증
--   AGL07123  | 갤럭시S24 유리 | 280           | 8.5   | 9.1    | 9.5    | 33                | 2026-04-22               | -10.5     | 여유            | 감소
--
-- ================================================================

WITH daily_sales AS (
  SELECT
    sku,
    product_name,
    DATE(order_date) AS sale_date,
    SUM(quantity) AS daily_qty
  FROM `${BQ_DATASET}.orders`
  WHERE DATE(order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
  GROUP BY sku, product_name, sale_date
),
moving_averages AS (
  SELECT
    sku,
    ANY_VALUE(product_name) AS product_name,
    -- 7일 이동평균 (단기 추세)
    AVG(IF(sale_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), daily_qty, NULL)) AS ma_7d,
    -- 14일 이동평균 (중기 추세)
    AVG(IF(sale_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY), daily_qty, NULL)) AS ma_14d,
    -- 30일 이동평균 (장기 추세)
    AVG(IF(sale_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), daily_qty, NULL)) AS ma_30d,
    -- 추세 가속도: 최근 7일 vs 이전 7일 (14일 윈도우 내)
    AVG(IF(sale_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), daily_qty, NULL))
      - AVG(IF(sale_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
                          AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY), daily_qty, NULL)) AS trend_delta,
    -- 판매 변동성 (30일 표준편차)
    STDDEV(IF(sale_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), daily_qty, NULL)) AS sales_stddev_30d,
    COUNT(DISTINCT IF(sale_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY), sale_date, NULL)) AS active_days_30d
  FROM daily_sales
  GROUP BY sku
)
SELECT
  ma.sku,
  ma.product_name,
  i.warehouse,
  i.current_stock,
  -- 이동평균 값
  ROUND(ma.ma_7d, 1) AS ma_7d,
  ROUND(ma.ma_14d, 1) AS ma_14d,
  ROUND(ma.ma_30d, 1) AS ma_30d,
  -- 각 MA 기반 소진 예상일
  ROUND(SAFE_DIVIDE(i.current_stock, ma.ma_7d), 0) AS depletion_days_7d,
  ROUND(SAFE_DIVIDE(i.current_stock, ma.ma_14d), 0) AS depletion_days_14d,
  ROUND(SAFE_DIVIDE(i.current_stock, ma.ma_30d), 0) AS depletion_days_30d,
  -- 소진 예상 날짜 (7일 MA 기준 — 최근 추세 반영)
  DATE_ADD(CURRENT_DATE(), INTERVAL CAST(ROUND(SAFE_DIVIDE(i.current_stock, ma.ma_7d), 0) AS INT64) DAY) AS estimated_depletion_date,
  -- 추세 방향: 단기 MA > 장기 MA면 판매 증가세
  ROUND(SAFE_DIVIDE(ma.ma_7d - ma.ma_30d, ma.ma_30d) * 100, 1) AS trend_pct,
  ROUND(ma.trend_delta, 2) AS weekly_acceleration,
  -- 변동계수 (CV): 수요 불확실성 지표
  ROUND(SAFE_DIVIDE(ma.sales_stddev_30d, ma.ma_30d) * 100, 1) AS demand_cv_pct,
  CASE
    WHEN SAFE_DIVIDE(i.current_stock, ma.ma_7d) < 7 THEN '🔴 7일 내 소진'
    WHEN SAFE_DIVIDE(i.current_stock, ma.ma_7d) < 14 THEN '🟡 2주 내 소진'
    WHEN SAFE_DIVIDE(i.current_stock, ma.ma_7d) < 30 THEN '🟢 1개월 내 소진'
    ELSE '⚪ 여유'
  END AS forecast_status,
  CASE
    WHEN SAFE_DIVIDE(ma.ma_7d - ma.ma_30d, ma.ma_30d) > 0.2 THEN '📈 급증'
    WHEN SAFE_DIVIDE(ma.ma_7d - ma.ma_30d, ma.ma_30d) > 0 THEN '↗️ 증가'
    WHEN SAFE_DIVIDE(ma.ma_7d - ma.ma_30d, ma.ma_30d) > -0.2 THEN '↘️ 감소'
    ELSE '📉 급감'
  END AS trend_direction
FROM moving_averages ma
JOIN `${BQ_DATASET}.inventory` i ON ma.sku = i.sku
WHERE ma.ma_7d > 0
ORDER BY depletion_days_7d ASC
