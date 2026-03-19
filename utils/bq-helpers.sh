#!/usr/bin/env bash
# bq-helpers.sh — BigQuery 공통 유틸리티
# source this file: source utils/bq-helpers.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 공통 유틸리티 로드 (로깅, 에러 핸들링, 의존성 체크)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# .env 로드
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi

BQ_PROJECT="${BQ_PROJECT:-inspiring-bonus-484905-v9}"
BQ_DATASET="${BQ_DATASET:-}"

# BQ 쿼리 실행 (JSON 출력)
bq_query() {
  local sql="$1"
  local format="${2:-json}"
  bq query \
    --project_id="$BQ_PROJECT" \
    --use_legacy_sql=false \
    --format="$format" \
    --max_rows=10000 \
    "$sql"
}

# BQ 쿼리 → CSV 파일
bq_to_csv() {
  local sql="$1"
  local output="$2"
  bq query \
    --project_id="$BQ_PROJECT" \
    --use_legacy_sql=false \
    --format=csv \
    --max_rows=10000 \
    "$sql" > "$output"
  echo "✅ $output ($(wc -l < "$output")행)"
}

# SQL 파일 실행 (변수 치환 지원)
bq_run_sql() {
  local sql_file="$1"
  shift
  local sql
  sql=$(cat "$sql_file")
  # $1, $2... 인자로 변수 치환
  local i=1
  for arg in "$@"; do
    sql="${sql//\$${i}/$arg}"
    i=$((i + 1))
  done
  bq_query "$sql"
}

# 결과를 Google Sheets에 쓰기
bq_to_sheets() {
  local sql="$1"
  local spreadsheet_id="$2"
  local range="$3"

  local tmpfile
  tmpfile=$(make_temp bq-export)
  bq_query "$sql" > "$tmpfile"

  # JSON → Sheets values 변환
  local values
  values=$(jq '[.[] | [to_entries[].value | tostring]]' "$tmpfile")

  gws sheets spreadsheets values update \
    --params "{\"spreadsheetId\":\"$spreadsheet_id\",\"range\":\"$range\",\"valueInputOption\":\"USER_ENTERED\"}" \
    --json "{\"values\":$values}"
}

echo_header() {
  echo "=== $1 ==="
  echo "프로젝트: $BQ_PROJECT"
  echo "---"
}
