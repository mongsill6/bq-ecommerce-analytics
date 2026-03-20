-- ================================================================
-- 파일: keyword-performance.sql
-- 목적: 광고 키워드별 클릭, 전환, ROAS를 분석하여 키워드 효율을 평가합니다.
--       키워드를 핵심/유지/개선필요/중단검토 4단계로 분류하고,
--       클릭 대비 전환 품질(높은/보통/낮은/데이터부족)을 판정합니다.
--       키워드 입찰 최적화, 비효율 키워드 정리, 신규 키워드 발굴에 활용됩니다.
-- ================================================================
--
-- ■ 파라미터
--   $1  DATE  필수  시작일 (YYYY-MM-DD)
--   $2  DATE  필수  종료일 (YYYY-MM-DD)
--
-- ■ 출력 컬럼
--   keyword            STRING   검색 키워드
--   match_type         STRING   매칭 유형 (exact, phrase, broad)
--   campaign_name      STRING   소속 캠페인명
--   platform           STRING   광고 플랫폼
--   impressions        INT64    총 노출 수
--   clicks             INT64    총 클릭 수
--   ctr_pct            FLOAT64  클릭률 (%)
--   keyword_spend      FLOAT64  키워드 광고비 (원)
--   cpc                FLOAT64  클릭당 비용 (원)
--   conversions        INT64    전환(주문) 수
--   cvr_pct            FLOAT64  전환률 (%, 클릭 대비 주문)
--   revenue            FLOAT64  기여 매출 (원)
--   roas               FLOAT64  ROAS (기여매출/광고비)
--   cpa                FLOAT64  전환당 비용 (원)
--   keyword_grade      STRING   키워드 등급 (핵심/유지/개선필요/중단검토)
--   conversion_quality STRING   전환 품질 (높은전환/보통/낮은전환/데이터부족)
--
-- ■ 실행 방법
--   bq_run_sql queries/advertising/keyword-performance.sql "2026-03-01" "2026-03-19"
--
-- ■ 예시 출력
--   keyword         | match_type | campaign_name | platform | clicks | ctr_pct | keyword_spend | roas | cpa  | keyword_grade | conversion_quality
--   아이폰 케이스   | exact      | 아이폰_브랜드 | coupang  | 2500   | 3.12    | 625000        | 7.20 | 2500 | 핵심 키워드   | 높은 전환
--   슈피겐         | broad      | 브랜드_검색   | naver    | 1800   | 4.50    | 450000        | 5.33 | 3000 | 핵심 키워드   | 높은 전환
--   핸드폰 필름    | phrase     | 갤럭시_키워드 | coupang  | 800    | 0.80    | 320000        | 0.75 | 16000| 중단 검토     | 낮은 전환
--
-- ================================================================

SELECT
  keyword,
  match_type,
  campaign_name,
  platform,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  SUM(ad_spend) AS keyword_spend,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(clicks)), 0) AS cpc,
  SUM(attributed_orders) AS conversions,
  ROUND(SAFE_DIVIDE(SUM(attributed_orders), SUM(clicks)) * 100, 2) AS cvr_pct,
  SUM(attributed_revenue) AS revenue,
  ROUND(SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)), 2) AS roas,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)), 0) AS cpa,

  -- 키워드 효율 등급
  CASE
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 5 THEN '🟢 핵심 키워드'
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 3 THEN '🟡 유지 키워드'
    WHEN SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)) >= 1 THEN '🟠 개선 필요'
    ELSE '🔴 중단 검토'
  END AS keyword_grade,

  -- 클릭 대비 전환 효율
  CASE
    WHEN SUM(clicks) >= 100 AND SAFE_DIVIDE(SUM(attributed_orders), SUM(clicks)) >= 0.05 THEN '높은 전환'
    WHEN SUM(clicks) >= 100 AND SAFE_DIVIDE(SUM(attributed_orders), SUM(clicks)) < 0.01 THEN '낮은 전환'
    WHEN SUM(clicks) < 10 THEN '데이터 부족'
    ELSE '보통'
  END AS conversion_quality

FROM `${BQ_DATASET}.ad_keywords`
WHERE DATE(report_date) BETWEEN '$1' AND '$2'
GROUP BY keyword, match_type, campaign_name, platform
HAVING SUM(impressions) > 0
ORDER BY keyword_spend DESC
