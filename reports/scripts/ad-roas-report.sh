#!/usr/bin/env bash
# ad-roas-report.sh — 광고 ROAS 리포트 자동화
# 캠페인별/키워드별 ROAS 조회 → Google Sheets 업데이트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$SCRIPT_DIR/utils/bq-helpers.sh"

# 기간 설정: 기본값 = 지난 7일
END_DATE="${1:-$(date +%Y-%m-%d)}"
START_DATE="${2:-$(date -d "$END_DATE - 7 days" +%Y-%m-%d)}"
SPREADSHEET_ID="${GWS_REPORT_SPREADSHEET_ID:?GWS_REPORT_SPREADSHEET_ID 설정 필요}"

echo_header "광고 ROAS 리포트 ($START_DATE ~ $END_DATE)"

# ─── 1. 캠페인별 ROAS ──────────────────────────────
echo "📊 캠페인별 ROAS 조회 중..."
CAMPAIGN_SQL=$(cat "$SCRIPT_DIR/queries/advertising/roas-by-campaign.sql" \
  | sed "s/\$1/$START_DATE/g; s/\$2/$END_DATE/g")
bq_to_sheets "$CAMPAIGN_SQL" "$SPREADSHEET_ID" "캠페인ROAS!A2"

# 적자 캠페인 별도 추출
CAMPAIGN_DATA=$(bq_query "$CAMPAIGN_SQL")
DEFICIT_COUNT=$(echo "$CAMPAIGN_DATA" | jq '[.[] | select(.roas != null and (.roas | tonumber) < 1)] | length')
echo "  🔴 적자 캠페인 (ROAS < 1): ${DEFICIT_COUNT}개"

if [ "$DEFICIT_COUNT" -gt 0 ]; then
  echo ""
  echo "  적자 캠페인 목록:"
  echo "$CAMPAIGN_DATA" | jq -r '.[] | select(.roas != null and (.roas | tonumber) < 1) | "    - \(.campaign_name) [\(.platform)] ROAS: \(.roas) | 광고비: \(.total_spend)원 | 매출: \(.attributed_revenue)원"'
fi

# 적자 캠페인 데이터를 별도 시트에 기록
DEFICIT_SQL="SELECT * FROM (${CAMPAIGN_SQL}) WHERE roas < 1 ORDER BY total_spend DESC"
bq_to_sheets "$DEFICIT_SQL" "$SPREADSHEET_ID" "적자캠페인!A2"

# ─── 2. 일별 광고비 효율 추이 ──────────────────────
echo ""
echo "📈 일별 광고비 효율 추이 조회 중..."
EFFICIENCY_SQL=$(cat "$SCRIPT_DIR/queries/advertising/ad-spend-efficiency.sql" \
  | sed "s/\$1/$START_DATE/g; s/\$2/$END_DATE/g")
bq_to_sheets "$EFFICIENCY_SQL" "$SPREADSHEET_ID" "광고효율추이!A2"

# ─── 3. 키워드별 성과 ──────────────────────────────
echo "🔑 키워드별 성과 조회 중..."
KEYWORD_SQL=$(cat "$SCRIPT_DIR/queries/advertising/keyword-performance.sql" \
  | sed "s/\$1/$START_DATE/g; s/\$2/$END_DATE/g")
bq_to_sheets "$KEYWORD_SQL" "$SPREADSHEET_ID" "키워드성과!A2"

# 중단 검토 키워드 추출
KEYWORD_DATA=$(bq_query "$KEYWORD_SQL")
STOP_KEYWORDS=$(echo "$KEYWORD_DATA" | jq '[.[] | select(.keyword_grade != null and (.keyword_grade | test("중단")))] | length')
echo "  🔴 중단 검토 키워드: ${STOP_KEYWORDS}개"

if [ "$STOP_KEYWORDS" -gt 0 ]; then
  echo ""
  echo "  중단 검토 키워드 목록:"
  echo "$KEYWORD_DATA" | jq -r '.[] | select(.keyword_grade != null and (.keyword_grade | test("중단"))) | "    - \"\(.keyword)\" [\(.match_type)] ROAS: \(.roas) | 광고비: \(.keyword_spend)원"'
fi

# ─── 4. 주간 추이 요약 ─────────────────────────────
echo ""
echo "📉 주간 추이 요약 집계 중..."
WEEKLY_TREND_SQL="
SELECT
  DATE_TRUNC(DATE(report_date), WEEK(MONDAY)) AS week_start,
  SUM(ad_spend) AS weekly_spend,
  SUM(attributed_revenue) AS weekly_revenue,
  ROUND(SAFE_DIVIDE(SUM(attributed_revenue), SUM(ad_spend)), 2) AS weekly_roas,
  SUM(attributed_orders) AS weekly_orders,
  ROUND(SAFE_DIVIDE(SUM(ad_spend), SUM(attributed_orders)), 0) AS weekly_cpa,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS weekly_ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(attributed_orders), SUM(clicks)) * 100, 2) AS weekly_cvr_pct
FROM \`${BQ_DATASET}.ad_campaigns\`
WHERE DATE(report_date) BETWEEN DATE_SUB('$END_DATE', INTERVAL 28 DAY) AND '$END_DATE'
GROUP BY week_start
ORDER BY week_start DESC
"
bq_to_sheets "$WEEKLY_TREND_SQL" "$SPREADSHEET_ID" "주간추이!A2"

# ─── 5. 업데이트 타임스탬프 ────────────────────────
NOW=$(date '+%Y-%m-%d %H:%M:%S')
gws sheets spreadsheets values update \
  --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"캠페인ROAS!A1\",\"valueInputOption\":\"USER_ENTERED\"}" \
  --json "{\"values\":[[\"최종 업데이트: $NOW | 기간: $START_DATE ~ $END_DATE\"]]}"

# ─── 결과 요약 ─────────────────────────────────────
echo ""
echo "=== 리포트 요약 ==="
TOTAL_SPEND=$(echo "$CAMPAIGN_DATA" | jq '[.[].total_spend // 0 | tonumber] | add // 0')
TOTAL_REVENUE=$(echo "$CAMPAIGN_DATA" | jq '[.[].attributed_revenue // 0 | tonumber] | add // 0')
OVERALL_ROAS=$(echo "$CAMPAIGN_DATA" | jq --argjson spend "$TOTAL_SPEND" --argjson rev "$TOTAL_REVENUE" -n 'if $spend > 0 then ($rev / $spend * 100 | round / 100) else 0 end')
TOTAL_CAMPAIGNS=$(echo "$CAMPAIGN_DATA" | jq 'length')

echo "  총 캠페인: ${TOTAL_CAMPAIGNS}개"
echo "  총 광고비: ${TOTAL_SPEND}원"
echo "  총 매출: ${TOTAL_REVENUE}원"
echo "  종합 ROAS: ${OVERALL_ROAS}"
echo "  적자 캠페인: ${DEFICIT_COUNT}개"
echo "  중단 검토 키워드: ${STOP_KEYWORDS}개"
echo ""
echo "  시트 탭: 캠페인ROAS, 적자캠페인, 광고효율추이, 키워드성과, 주간추이"
echo "---"
echo "✅ 광고 ROAS 리포트 업데이트 완료: https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
