#!/usr/bin/env bash
# daily-sales-report.sh — 일간 매출 리포트 생성 → Google Sheets 업데이트
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$SCRIPT_DIR/utils/common.sh"
source "$SCRIPT_DIR/utils/bq-helpers.sh"
check_bq_deps

DATE="${1:-$(date +%Y-%m-%d)}"
SPREADSHEET_ID="${GWS_REPORT_SPREADSHEET_ID:?GWS_REPORT_SPREADSHEET_ID 설정 필요}"

log_info "일간 매출 리포트 ($DATE)"
log_info "프로젝트: $BQ_PROJECT"

# 1. 일간 매출 요약
log_info "매출 데이터 조회 중..."
bq_to_sheets \
  "$(cat "$SCRIPT_DIR/queries/sales/daily-sales-summary.sql" | sed "s/\$1/$DATE/g")" \
  "$SPREADSHEET_ID" \
  "일간매출!A2"

# 2. TOP 10 상품
log_info "베스트셀러 조회 중..."
bq_to_sheets \
  "$(cat "$SCRIPT_DIR/queries/sales/top-sellers.sql" | sed "s/\$1/$DATE/g; s/\$2/$DATE/g; s/\$3/10/g")" \
  "$SPREADSHEET_ID" \
  "베스트셀러!A2"

# 3. 업데이트 타임스탬프
NOW=$(date '+%Y-%m-%d %H:%M:%S')
gws sheets spreadsheets values update \
  --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"일간매출!A1\",\"valueInputOption\":\"USER_ENTERED\"}" \
  --json "{\"values\":[[\"최종 업데이트: $NOW\"]]}"

log_success "리포트 업데이트 완료: https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
