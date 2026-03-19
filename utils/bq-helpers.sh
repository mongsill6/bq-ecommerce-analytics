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

# ── SQL 인젝션 방지: 입력값 검증 ──
bq_sanitize_param() {
  local value="$1"
  local param_type="${2:-STRING}"  # DATE, INTEGER, NUMERIC, STRING

  # 빈 값 체크
  if [ -z "$value" ]; then
    log_error "파라미터 값이 비어있습니다"
    return 1
  fi

  # 위험한 SQL 패턴 차단
  local dangerous_patterns=(
    ";"           # 다중 문장
    "--"          # 라인 주석
    "/\*"         # 블록 주석
    "UNION"       # UNION 인젝션
    "DROP "       # DDL
    "DELETE "     # DML
    "INSERT "     # DML
    "UPDATE "     # DML
    "ALTER "      # DDL
    "CREATE "     # DDL
    "TRUNCATE "   # DDL
    "EXEC "       # 프로시저
    "EXECUTE "    # 프로시저
    "xp_"         # 확장 프로시저
  )

  local upper_value
  upper_value=$(echo "$value" | tr '[:lower:]' '[:upper:]')
  for pattern in "${dangerous_patterns[@]}"; do
    if [[ "$upper_value" == *"$pattern"* ]]; then
      log_error "SQL 인젝션 의심 패턴 감지: '$pattern' in '$value'"
      return 1
    fi
  done

  # 타입별 형식 검증
  case "$param_type" in
    DATE)
      if ! [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_error "DATE 파라미터 형식 오류: '$value' (YYYY-MM-DD 필요)"
        return 1
      fi
      ;;
    INTEGER)
      if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        log_error "INTEGER 파라미터 형식 오류: '$value' (정수만 허용)"
        return 1
      fi
      ;;
    NUMERIC)
      if ! [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        log_error "NUMERIC 파라미터 형식 오류: '$value' (숫자만 허용)"
        return 1
      fi
      ;;
    STRING)
      # 작은따옴표 이스케이프 (SQL 문자열 안전하게)
      value="${value//\'/\'\'}"
      # 허용: 알파벳, 숫자, 하이픈, 언더스코어, 점, 공백, 한글
      if ! [[ "$value" =~ ^[a-zA-Z0-9가-힣_.:/%\ -]+$ ]]; then
        log_error "STRING 파라미터에 허용되지 않은 문자: '$value'"
        return 1
      fi
      ;;
  esac

  echo "$value"
}

# SQL 파일에서 @param_count 추출
_bq_get_param_count() {
  local sql_file="$1"
  local count
  count=$(grep -m1 '@param_count' "$sql_file" 2>/dev/null | sed 's/.*@param_count[[:space:]]*//' | tr -d '[:space:]')
  echo "${count:-}"
}

# SQL 파일에서 @param 타입 목록 추출 (순서대로)
_bq_get_param_types() {
  local sql_file="$1"
  grep '@param[[:space:]]*\$' "$sql_file" 2>/dev/null | \
    sed 's/.*@param[[:space:]]*\$[0-9]*[[:space:]]*//' | \
    awk '{print $1}'
}

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

# SQL 파일 실행 (변수 치환 지원 + 파라미터 검증)
bq_run_sql() {
  local sql_file="$1"
  shift

  # SQL 파일 존재 여부 확인
  if [ ! -f "$sql_file" ]; then
    log_error "SQL 파일을 찾을 수 없습니다: $sql_file"
    return 1
  fi

  # @param_count 기반 파라미터 개수 검증
  local expected_count
  expected_count=$(_bq_get_param_count "$sql_file")
  if [ -n "$expected_count" ]; then
    local actual_count=$#
    # 선택적 파라미터(@default 존재) 허용: actual >= required && actual <= expected
    local required_count
    required_count=$(grep -c '@param.*필수' "$sql_file" 2>/dev/null || echo "0")
    if [ "$actual_count" -lt "$required_count" ]; then
      log_error "파라미터 부족: $sql_file"
      log_error "  필수 ${required_count}개, 전달 ${actual_count}개 (최대 ${expected_count}개)"
      grep '@param\|@example' "$sql_file" | head -10 >&2
      return 1
    fi
    if [ "$actual_count" -gt "$expected_count" ]; then
      log_error "파라미터 초과: $sql_file"
      log_error "  최대 ${expected_count}개, 전달 ${actual_count}개"
      grep '@param\|@example' "$sql_file" | head -10 >&2
      return 1
    fi
  fi

  # @param 타입 기반 입력값 검증 (sanitize)
  local param_types=()
  while IFS= read -r ptype; do
    [ -n "$ptype" ] && param_types+=("$ptype")
  done < <(_bq_get_param_types "$sql_file")

  local sanitized_args=()
  local i=0
  for arg in "$@"; do
    local ptype="${param_types[$i]:-STRING}"
    local sanitized
    sanitized=$(bq_sanitize_param "$arg" "$ptype") || return 1
    sanitized_args+=("$sanitized")
    i=$((i + 1))
  done

  local sql
  sql=$(cat "$sql_file")
  # $1, $2... 인자로 변수 치환 (sanitize된 값 사용)
  local idx=1
  for arg in "${sanitized_args[@]}"; do
    sql="${sql//\$${idx}/$arg}"
    idx=$((idx + 1))
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
