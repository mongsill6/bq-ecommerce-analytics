-- monthly-comparison.sql
-- 월간 매출 전년 동기(YoY) 대비 비교
-- ================================================================
-- @param_count  2
-- @param  $1  STRING   필수  기준 연월 (YYYY-MM)
-- @param  $2  NUMERIC  필수  월간 매출 목표 금액
-- @example  bq_run_sql queries/sales/monthly-comparison.sql "2026-03" "500000000"
-- ================================================================

WITH current_month AS (
  SELECT
    channel,
    category,
    COUNT(DISTINCT order_id) AS order_count,
    SUM(quantity) AS total_qty,
    SUM(revenue) AS revenue,
    SUM(cost) AS cost,
    SUM(revenue) - SUM(cost) AS gross_profit,
    ROUND(SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) * 100, 1) AS gpm_pct
  FROM `${BQ_DATASET}.orders`
  WHERE FORMAT_DATE('%Y-%m', DATE(order_date)) = '$1'
  GROUP BY channel, category
),

prev_year_month AS (
  SELECT
    channel,
    category,
    COUNT(DISTINCT order_id) AS order_count,
    SUM(quantity) AS total_qty,
    SUM(revenue) AS revenue,
    SUM(cost) AS cost,
    SUM(revenue) - SUM(cost) AS gross_profit,
    ROUND(SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) * 100, 1) AS gpm_pct
  FROM `${BQ_DATASET}.orders`
  WHERE FORMAT_DATE('%Y-%m', DATE(order_date))
    = FORMAT_DATE('%Y-%m', DATE_SUB(PARSE_DATE('%Y-%m-%d', CONCAT('$1', '-01')), INTERVAL 1 YEAR))
  GROUP BY channel, category
),

-- 월초~현재까지 누적 매출 (당월 진행률 파악용)
ytd_cumulative AS (
  SELECT
    FORMAT_DATE('%Y-%m', DATE(order_date)) AS month,
    SUM(revenue) AS cumulative_revenue
  FROM `${BQ_DATASET}.orders`
  WHERE FORMAT_DATE('%Y', DATE(order_date)) = LEFT('$1', 4)
    AND DATE(order_date) <= CURRENT_DATE()
  GROUP BY month
)

-- 채널별/카테고리별 YoY 비교
SELECT
  COALESCE(c.channel, p.channel) AS channel,
  COALESCE(c.category, p.category) AS category,

  -- 당월 실적
  IFNULL(c.order_count, 0) AS cur_orders,
  IFNULL(c.revenue, 0) AS cur_revenue,
  IFNULL(c.gross_profit, 0) AS cur_profit,
  IFNULL(c.gpm_pct, 0) AS cur_gpm_pct,

  -- 전년 동월 실적
  IFNULL(p.order_count, 0) AS yoy_orders,
  IFNULL(p.revenue, 0) AS yoy_revenue,
  IFNULL(p.gross_profit, 0) AS yoy_profit,
  IFNULL(p.gpm_pct, 0) AS yoy_gpm_pct,

  -- YoY 증감률 (%)
  ROUND(SAFE_DIVIDE(c.revenue - p.revenue, p.revenue) * 100, 1) AS revenue_yoy_pct,
  ROUND(SAFE_DIVIDE(c.order_count - p.order_count, p.order_count) * 100, 1) AS orders_yoy_pct,
  ROUND(SAFE_DIVIDE(c.gross_profit - p.gross_profit, p.gross_profit) * 100, 1) AS profit_yoy_pct,

  -- 목표 대비 달성률 (채널+카테고리별 매출 / 전체 목표 비중)
  ROUND(SAFE_DIVIDE(c.revenue, CAST('$2' AS FLOAT64)) * 100, 1) AS target_contribution_pct

FROM current_month c
FULL OUTER JOIN prev_year_month p
  ON c.channel = p.channel AND c.category = p.category

ORDER BY cur_revenue DESC;

-- ============================================================
-- 서머리: 전체 합산 YoY + 목표 달성률
-- ============================================================
SELECT
  '** TOTAL **' AS channel,
  '** ALL **' AS category,

  SUM(c.order_count) AS cur_orders,
  SUM(c.revenue) AS cur_revenue,
  SUM(c.gross_profit) AS cur_profit,
  ROUND(SAFE_DIVIDE(SUM(c.gross_profit), SUM(c.revenue)) * 100, 1) AS cur_gpm_pct,

  SUM(p.order_count) AS yoy_orders,
  SUM(p.revenue) AS yoy_revenue,
  SUM(p.gross_profit) AS yoy_profit,
  ROUND(SAFE_DIVIDE(SUM(p.gross_profit), SUM(p.revenue)) * 100, 1) AS yoy_gpm_pct,

  ROUND(SAFE_DIVIDE(SUM(c.revenue) - SUM(p.revenue), SUM(p.revenue)) * 100, 1) AS revenue_yoy_pct,
  ROUND(SAFE_DIVIDE(SUM(c.order_count) - SUM(p.order_count), SUM(p.order_count)) * 100, 1) AS orders_yoy_pct,
  ROUND(SAFE_DIVIDE(SUM(c.gross_profit) - SUM(p.gross_profit), SUM(p.gross_profit)) * 100, 1) AS profit_yoy_pct,

  -- 전체 목표 대비 달성률
  ROUND(SAFE_DIVIDE(SUM(c.revenue), CAST('$2' AS FLOAT64)) * 100, 1) AS target_achievement_pct,

  -- 연간 누적 매출 (YTD)
  (SELECT SUM(cumulative_revenue) FROM ytd_cumulative) AS ytd_revenue

FROM current_month c
FULL OUTER JOIN prev_year_month p
  ON c.channel = p.channel AND c.category = p.category;
