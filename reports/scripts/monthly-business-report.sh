#!/usr/bin/env bash
# monthly-business-report.sh — 월간 비즈니스 종합 리포트 → Google Sheets 멀티탭 생성
# 매출 요약(YoY) + 베스트셀러 + 재고 현황 + 광고 ROAS를 종합
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$SCRIPT_DIR/utils/common.sh"
source "$SCRIPT_DIR/utils/bq-helpers.sh"
check_bq_deps

# 인자: 기준 연월 (YYYY-MM), 매출 목표
MONTH="${1:-$(date +%Y-%m)}"
TARGET="${2:-500000000}"
SPREADSHEET_ID="${GWS_REPORT_SPREADSHEET_ID:?GWS_REPORT_SPREADSHEET_ID 설정 필요}"

# 해당 월의 시작일/종료일 계산
MONTH_START="${MONTH}-01"
MONTH_END=$(date -d "${MONTH_START} +1 month -1 day" +%Y-%m-%d 2>/dev/null \
  || date -v1d -v+1m -v-1d -j -f "%Y-%m-%d" "${MONTH_START}" +%Y-%m-%d)

log_info "월간 비즈니스 리포트 (${MONTH})"
log_info "프로젝트: $BQ_PROJECT"
log_info "기간: ${MONTH_START} ~ ${MONTH_END}"
log_info "매출 목표: $(printf "%'d" "$TARGET")원"

# ──────────────────────────────────────────────
# 1. 매출 요약 (YoY 비교) → '매출요약' 탭
# ──────────────────────────────────────────────
log_info "[1/4] 매출 YoY 비교 조회 중..."

MONTHLY_SQL=$(cat "$SCRIPT_DIR/queries/sales/monthly-comparison.sql")
MONTHLY_SQL="${MONTHLY_SQL//\$1/$MONTH}"
MONTHLY_SQL="${MONTHLY_SQL//\$2/$TARGET}"

# 헤더 행 삽입
gws sheets spreadsheets values update \
  --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"매출요약!A1\",\"valueInputOption\":\"USER_ENTERED\"}" \
  --json '{"values":[["채널","카테고리","당월 주문수","당월 매출","당월 이익","당월 GPM%","전년 주문수","전년 매출","전년 이익","전년 GPM%","매출 YoY%","주문 YoY%","이익 YoY%","목표기여율%"]]}'

bq_to_sheets "$MONTHLY_SQL" "$SPREADSHEET_ID" "매출요약!A2"
log_success "매출요약 탭 업데이트 완료"

# ──────────────────────────────────────────────
# 2. 베스트셀러 TOP 20 → '베스트셀러' 탭
# ──────────────────────────────────────────────
log_info "[2/4] 월간 베스트셀러 조회 중..."

TOP_SQL=$(cat "$SCRIPT_DIR/queries/sales/top-sellers.sql")
TOP_SQL="${TOP_SQL//\$1/$MONTH_START}"
TOP_SQL="${TOP_SQL//\$2/$MONTH_END}"
TOP_SQL="${TOP_SQL//\$3/20}"

gws sheets spreadsheets values update \
  --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"베스트셀러!A1\",\"valueInputOption\":\"USER_ENTERED\"}" \
  --json '{"values":[["상품ID","상품명","SKU","판매수량","매출","주문수","평균단가","GPM%"]]}'

bq_to_sheets "$TOP_SQL" "$SPREADSHEET_ID" "베스트셀러!A2"
log_success "베스트셀러 탭 업데이트 완료"

# ──────────────────────────────────────────────
# 3. 재고 현황 → '재고현황' 탭
# ──────────────────────────────────────────────
log_info "[3/4] 재고 현황 조회 중..."

STOCK_SQL=$(cat "$SCRIPT_DIR/queries/inventory/stock-status.sql")

gws sheets spreadsheets values update \
  --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"재고현황!A1\",\"valueInputOption\":\"USER_ENTERED\"}" \
  --json '{"values":[["SKU","상품명","창고","현재재고","일평균판매","잔여일수","상태"]]}'

bq_to_sheets "$STOCK_SQL" "$SPREADSHEET_ID" "재고현황!A2"

# 재고 위험 요약 계산
STOCK_JSON=$(bq_query "$STOCK_SQL")
CRITICAL=$(echo "$STOCK_JSON" | jq '[.[] | select(.status | test("긴급"))] | length')
WARNING=$(echo "$STOCK_JSON" | jq '[.[] | select(.status | test("주의"))] | length')
log_success "재고현황 탭 업데이트 완료 (긴급: ${CRITICAL}개, 주의: ${WARNING}개)"

# ──────────────────────────────────────────────
# 4. 광고 ROAS → '광고성과' 탭
# ──────────────────────────────────────────────
log_info "[4/4] 광고 ROAS 조회 중..."

ROAS_SQL=$(cat "$SCRIPT_DIR/queries/advertising/roas-by-campaign.sql")
ROAS_SQL="${ROAS_SQL//\$1/$MONTH_START}"
ROAS_SQL="${ROAS_SQL//\$2/$MONTH_END}"

gws sheets spreadsheets values update \
  --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"광고성과!A1\",\"valueInputOption\":\"USER_ENTERED\"}" \
  --json '{"values":[["캠페인ID","캠페인명","플랫폼","노출수","클릭수","CTR%","광고비","기여매출","ROAS","주문수","CPA","효율등급"]]}'

bq_to_sheets "$ROAS_SQL" "$SPREADSHEET_ID" "광고성과!A2"
log_success "광고성과 탭 업데이트 완료"

# ──────────────────────────────────────────────
# 5. 요약 대시보드 → '요약' 탭
# ──────────────────────────────────────────────
log_info "요약 대시보드 생성 중..."

NOW=$(date '+%Y-%m-%d %H:%M:%S')

# 전체 매출 합산 요약
TOTAL_REVENUE=$(echo "$STOCK_JSON" | head -1 > /dev/null; bq_query "$MONTHLY_SQL" | jq -r '.[-1].cur_revenue // "0"')
TOTAL_YOY=$(bq_query "$MONTHLY_SQL" | jq -r '.[-1].revenue_yoy_pct // "N/A"')
TARGET_PCT=$(bq_query "$MONTHLY_SQL" | jq -r '.[-1].target_achievement_pct // "N/A"')

gws sheets spreadsheets values update \
  --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"요약!A1\",\"valueInputOption\":\"USER_ENTERED\"}" \
  --json "{\"values\":[
    [\"월간 비즈니스 리포트\",\"${MONTH}\"],
    [\"최종 업데이트\",\"${NOW}\"],
    [\"\"],
    [\"항목\",\"값\"],
    [\"당월 매출\",\"${TOTAL_REVENUE}\"],
    [\"매출 YoY 증감률\",\"${TOTAL_YOY}%\"],
    [\"목표 달성률\",\"${TARGET_PCT}%\"],
    [\"매출 목표\",\"${TARGET}\"],
    [\"\"],
    [\"재고 현황\"],
    [\"긴급 SKU\",\"${CRITICAL}\"],
    [\"주의 SKU\",\"${WARNING}\"],
    [\"\"],
    [\"시트별 상세\"],
    [\"매출요약\",\"채널별/카테고리별 YoY 비교\"],
    [\"베스트셀러\",\"TOP 20 상품 매출순\"],
    [\"재고현황\",\"전 SKU 재고 소진 예측\"],
    [\"광고성과\",\"캠페인별 ROAS 분석\"]
  ]}"

log_success "요약 대시보드 완료"

# ──────────────────────────────────────────────
# 완료
# ──────────────────────────────────────────────
log_success "리포트 생성 완료"
log_info "시트: https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
log_info "탭: 요약 | 매출요약 | 베스트셀러 | 재고현황 | 광고성과"
log_info "생성 시각: $NOW"
