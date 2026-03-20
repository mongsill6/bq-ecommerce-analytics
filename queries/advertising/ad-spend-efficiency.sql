-- ================================================================
-- 파일: ad-spend-efficiency.sql
-- 목적: 일별 광고비 효율 지표(CPC, CPM, CPA) 추이를 플랫폼별로 분석합니다.
--       전일 대비 CPC 변화율을 추적하여 비용 급등을 감지하고,
--       CTR, CVR, ROAS를 종합하여 효율 등급을 자동 분류합니다.
--       광고비 일간 모니터링, 이상 지출 감지, 플랫폼별 비교에 활용됩니다.
-- ================================================================
--
-- ■ 파라미터
--   $1  DATE  필수  시작일 (YYYY-MM-DD)
--   $2  DATE  필수  종료일 (YYYY-MM-DD)
--
-- ■ 출력 컬럼
--   report_date      DATE     보고 일자
--   platform         STRING   광고 플랫폼
--   daily_spend      FLOAT64  일간 광고비 (원)
--   impressions      INT64    일간 노출 수
--   clicks           INT64    일간 클릭 수
--   orders           INT64    일간 기여 주문 수
--   cpc              FLOAT64  클릭당 비용 (원)
--   cpm              FLOAT64  1000회 노출당 비용 (원)
--   cpa              FLOAT64  주문당 획득 비용 (원)
--   ctr_pct          FLOAT64  클릭률 (%)
--   cvr_pct          FLOAT64  전환률 (%, 클릭 대비 주문)
--   roas             FLOAT64  ROAS (기여매출/광고비)
--   cpc_change_pct   FLOAT64  전일 대비 CPC 변화율 (%)
--   spend_efficiency STRING   효율 등급 (고효율/보통/비효율/과다지출)
--
-- ■ 실행 방법
--   bq_run_sql queries/advertising/ad-spend-efficiency.sql "2026-03-01" "2026-03-19"
--
-- ■ 예시 출력
--   report_date | platform | daily_spend | clicks | cpc  | cpm   | cpa   | ctr_pct | cvr_pct | roas | cpc_change_pct | spend_efficiency
--   2026-03-19  | coupang  | 520000      | 1200   | 433  | 2080  | 2600  | 2.40    | 3.33    | 5.77 | -2.5           | 고효율
--   2026-03-19  | naver    | 380000      | 760    | 500  | 3167  | 6333  | 1.20    | 1.32    | 2.37 | 8.7            | 비효율
--
-- ================================================================

SELECT
  DATE(report_date) AS report_date,
  platform,
  SUM(ad_spend) AS daily_spend,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(attributed_orders) AS orders,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(clicks)), 0) AS cpc,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(impressions)) * 1000, 0) AS cpm,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)), 0) AS cpa,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(attributed_orders), SUM(clicks)) * 100, 2) AS cvr_pct,
  ROUND(SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)), 2) AS roas,

  -- 전일 대비 CPC 변화율
  ROUND(
    SAFE_DIVIDE(
      SAFE_DIVIDE(SUM(ad_spend), SUM(clicks))
        - LAG(SAFE_DIVIDE(SUM(ad_spend), SUM(clicks))) OVER (PARTITION BY platform ORDER BY DATE(report_date)),
      LAG(SAFE_DIVIDE(SUM(ad_spend), SUM(clicks))) OVER (PARTITION BY platform ORDER BY DATE(report_date))
    ) * 100, 1
  ) AS cpc_change_pct,

  -- 효율 등급
  CASE
    WHEN SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)) <= 3000 THEN '🟢 고효율'
    WHEN SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)) <= 5000 THEN '🟡 보통'
    WHEN SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)) <= 8000 THEN '🟠 비효율'
    ELSE '🔴 과다지출'
  END AS spend_efficiency

FROM `${BQ_DATASET}.ad_campaigns`
WHERE DATE(report_date) BETWEEN '$1' AND '$2'
GROUP BY report_date, platform
ORDER BY report_date DESC, platform
