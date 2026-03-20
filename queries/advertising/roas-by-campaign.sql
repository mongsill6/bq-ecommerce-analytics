-- ================================================================
-- 파일: roas-by-campaign.sql
-- 목적: 캠페인별 ROAS(Return on Ad Spend, 광고비 대비 매출)를 분석합니다.
--       노출, 클릭, CTR, 광고비, 기여매출, ROAS, CPA를 캠페인 단위로 집계하고,
--       효율 등급(우수/양호/주의/적자)을 자동 분류합니다.
--       광고 예산 최적화, 비효율 캠페인 식별, 광고 성과 보고에 활용됩니다.
-- ================================================================
--
-- ■ 파라미터
--   $1  DATE  필수  시작일 (YYYY-MM-DD)
--   $2  DATE  필수  종료일 (YYYY-MM-DD)
--
-- ■ 출력 컬럼
--   campaign_id        STRING   캠페인 ID
--   campaign_name      STRING   캠페인명
--   platform           STRING   광고 플랫폼 (coupang, naver, google 등)
--   impressions        INT64    총 노출 수
--   clicks             INT64    총 클릭 수
--   ctr_pct            FLOAT64  클릭률 (%)
--   total_spend        FLOAT64  총 광고비 (원)
--   attributed_revenue FLOAT64  기여 매출 (원)
--   roas               FLOAT64  ROAS (기여매출/광고비)
--   orders             INT64    기여 주문 수
--   cpa                FLOAT64  주문당 획득 비용 (원)
--   efficiency         STRING   효율 등급 (우수>=5 / 양호>=3 / 주의>=1 / 적자<1)
--
-- ■ 실행 방법
--   bq_run_sql queries/advertising/roas-by-campaign.sql "2026-03-01" "2026-03-19"
--
-- ■ 예시 출력
--   campaign_id | campaign_name      | platform | impressions | clicks | ctr_pct | total_spend | attributed_revenue | roas | orders | cpa   | efficiency
--   C001        | 아이폰케이스_브랜드 | coupang  | 250000      | 5000   | 2.00    | 1500000     | 9000000            | 6.00 | 300    | 5000  | 우수
--   C002        | 갤럭시필름_키워드   | naver    | 180000      | 2700   | 1.50    | 810000      | 1620000            | 2.00 | 90     | 9000  | 주의
--
-- ================================================================

SELECT
  campaign_id,
  campaign_name,
  platform,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  SUM(ad_spend) AS total_spend,
  SUM(attributed_revenue) AS attributed_revenue,
  ROUND(SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)), 2) AS roas,
  SUM(attributed_orders) AS orders,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)), 0) AS cpa,
  CASE
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 5 THEN '🟢 우수'
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 3 THEN '🟡 양호'
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 1 THEN '🟠 주의'
    ELSE '🔴 적자'
  END AS efficiency
FROM `${BQ_DATASET}.ad_campaigns`
WHERE DATE(report_date) BETWEEN '$1' AND '$2'
GROUP BY campaign_id, campaign_name, platform
ORDER BY total_spend DESC
