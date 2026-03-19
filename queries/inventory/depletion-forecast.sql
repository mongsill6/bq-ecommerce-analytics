-- depletion-forecast.sql
-- 이동평균 기반 재고 소진일 예측 (7일/14일/30일 MA)
-- 단기·중기·장기 추세를 비교하여 재고 소진 시점 예측

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
