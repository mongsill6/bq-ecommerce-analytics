-- ================================================================
-- 파일: weekly-trend.sql
-- 목적: 최근 12주간 채널별 주간 매출 트렌드를 분석합니다.
--       전주 대비(WoW) 증감률을 계산하여 매출 추이를 파악합니다.
--       주간 리포트, 시즌 트렌드 분석, 채널별 성장세 모니터링에 활용됩니다.
-- ================================================================
--
-- ■ 파라미터
--   없음 (최근 12주 자동 조회)
--
-- ■ 출력 컬럼
--   week_start      DATE     주 시작일 (월요일 기준)
--   channel         STRING   판매 채널
--   orders          INT64    주간 고유 주문 수
--   revenue         FLOAT64  주간 매출액
--   profit          FLOAT64  주간 매출총이익
--   gpm_pct         FLOAT64  매출총이익률 (%)
--   wow_change_pct  FLOAT64  전주 대비 매출 증감률 (%)
--
-- ■ 실행 방법
--   bq_run_sql queries/sales/weekly-trend.sql
--
-- ■ 예시 출력
--   week_start  | channel  | orders | revenue    | profit    | gpm_pct | wow_change_pct
--   2026-03-17  | coupang  | 980    | 89200000   | 44600000  | 50.0    | 5.2
--   2026-03-17  | naver    | 420    | 33600000   | 15120000  | 45.0    | -2.1
--   2026-03-10  | coupang  | 932    | 84800000   | 42400000  | 50.0    | 3.8
--
-- ================================================================

SELECT
  DATE_TRUNC(DATE(order_date), WEEK(MONDAY)) AS week_start,
  channel,
  COUNT(DISTINCT order_id) AS orders,
  SUM(revenue) AS revenue,
  SUM(revenue) - SUM(cost) AS profit,
  ROUND(SAFE_DIVIDE(SUM(revenue) - SUM(cost), SUM(revenue)) * 100, 1) AS gpm_pct,
  -- 전주 대비 증감률
  ROUND(
    SAFE_DIVIDE(
      SUM(revenue) - LAG(SUM(revenue)) OVER (PARTITION BY channel ORDER BY DATE_TRUNC(DATE(order_date), WEEK(MONDAY))),
      LAG(SUM(revenue)) OVER (PARTITION BY channel ORDER BY DATE_TRUNC(DATE(order_date), WEEK(MONDAY)))
    ) * 100, 1
  ) AS wow_change_pct
FROM `${BQ_DATASET}.orders`
WHERE DATE(order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 WEEK)
GROUP BY week_start, channel
ORDER BY week_start DESC, revenue DESC
