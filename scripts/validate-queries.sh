#!/usr/bin/env bash
# validate-queries.sh — 모든 SQL 파일 검증
# 1) bq dry_run 문법 검증
# 2) 미사용 파라미터 감지
# 3) 필수 주석 존재 확인 (설명, 파라미터, 사용법)
set -euo pipefail
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUERIES_DIR="$SCRIPT_DIR/queries"
BQ_PROJECT="${BQ_PROJECT:-inspiring-bonus-484905-v9}"

# 카운터
total=0
passed=0
failed=0
warnings=0
errors=()

# ── 컬러 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

log_pass()  { echo -e "  ${GREEN}✅ $*${RESET}"; }
log_fail()  { echo -e "  ${RED}❌ $*${RESET}"; }
log_warn()  { echo -e "  ${YELLOW}⚠️  $*${RESET}"; }
log_info()  { echo -e "  ${BLUE}ℹ️  $*${RESET}"; }

# ── 필수 주석 검증 ──
check_required_comments() {
  local sql_file="$1"
  local basename
  basename=$(basename "$sql_file")
  local ok=true

  # 1행: 파일명 주석
  if ! head -1 "$sql_file" | grep -q "^-- $basename\|^-- .*${basename%.sql}"; then
    log_fail "파일명 주석 누락 (첫 줄에 '-- $basename' 필요)"
    ok=false
  fi

  # 2행: 설명 주석 (멀티바이트 UTF-8 호환을 위해 -P 사용)
  if ! sed -n '2p' "$sql_file" | grep -qP '^-- .+'; then
    log_fail "설명 주석 누락 (둘째 줄에 SQL 설명 필요)"
    ok=false
  fi

  # @param_count 존재 여부
  if ! grep -q '@param_count' "$sql_file"; then
    log_fail "@param_count 주석 누락"
    ok=false
  fi

  # @example 존재 여부
  if ! grep -q '@example' "$sql_file"; then
    log_fail "@example 사용법 주석 누락"
    ok=false
  fi

  $ok
}

# ── 파라미터 일관성 검증 ──
check_params() {
  local sql_file="$1"
  local ok=true

  # @param_count에서 선언된 개수
  local declared_count
  declared_count=$(grep -m1 '@param_count' "$sql_file" 2>/dev/null \
    | sed 's/.*@param_count[[:space:]]*//' | tr -d '[:space:]')

  if [ -z "$declared_count" ]; then
    return 0  # @param_count 없으면 주석 검증에서 이미 실패
  fi

  # @param으로 선언된 파라미터 목록 ($1, $2, ...)
  local declared_params
  declared_params=$(grep '@param[[:space:]]*\$[0-9]' "$sql_file" 2>/dev/null \
    | sed 's/.*\(\$[0-9]\+\).*/\1/' | sort -u)

  local declared_param_count=0
  if [ -n "$declared_params" ]; then
    declared_param_count=$(echo "$declared_params" | wc -l)
  fi

  # @param_count와 실제 @param 선언 수 비교
  if [ "$declared_count" -ne "$declared_param_count" ]; then
    log_fail "@param_count($declared_count)와 @param 선언 수($declared_param_count) 불일치"
    ok=false
  fi

  # SQL 본문(주석 제외)에서 사용된 $N 파라미터 추출
  local sql_body
  sql_body=$(grep -v '^--' "$sql_file")

  local used_params
  used_params=$(echo "$sql_body" | grep -oE '\$[0-9]+' | sort -u)

  # 선언되었지만 본문에서 미사용인 파라미터
  for param in $declared_params; do
    if ! echo "$used_params" | grep -qF "$param"; then
      log_warn "파라미터 $param 선언됨, SQL 본문에서 미사용"
      warnings=$((warnings + 1))
    fi
  done

  # 본문에서 사용되지만 미선언된 파라미터
  for param in $used_params; do
    if ! echo "$declared_params" | grep -qF "$param"; then
      log_fail "파라미터 $param 이 SQL 본문에서 사용되지만 @param 선언 없음"
      ok=false
    fi
  done

  $ok
}

# ── bq dry_run 문법 검증 ──
check_syntax() {
  local sql_file="$1"

  # bq가 설치되어 있는지 확인
  if ! command -v bq >/dev/null 2>&1; then
    log_warn "bq CLI 미설치 — dry_run 문법 검증 건너뜀"
    warnings=$((warnings + 1))
    return 0
  fi

  # SQL 읽기 + 파라미터를 더미 값으로 치환
  local sql
  sql=$(cat "$sql_file")

  # $1~$9를 더미 값으로 치환 (dry_run이 파싱할 수 있도록)
  # @param 타입 정보를 사용하여 적절한 더미 값 선택
  local i=1
  while [ $i -le 9 ]; do
    if echo "$sql" | grep -qF "\$$i"; then
      # 해당 파라미터의 타입 확인
      local ptype
      ptype=$(grep "@param.*\\\$$i" "$sql_file" 2>/dev/null \
        | awk '{for(j=1;j<=NF;j++) if($j ~ /^(DATE|INTEGER|NUMERIC|STRING)$/) print $j}' \
        | head -1)
      case "$ptype" in
        DATE)    sql="${sql//\$$i/2026-01-01}" ;;
        INTEGER) sql="${sql//\$$i/1}" ;;
        NUMERIC) sql="${sql//\$$i/1.0}" ;;
        *)       sql="${sql//\$$i/dummy}" ;;
      esac
    fi
    i=$((i + 1))
  done

  # ${BQ_DATASET} 치환
  local dataset="${BQ_DATASET:-ecommerce}"
  sql="${sql//\$\{BQ_DATASET\}/$dataset}"

  # dry_run 실행
  local result
  if result=$(echo "$sql" | bq query \
    --project_id="$BQ_PROJECT" \
    --use_legacy_sql=false \
    --dry_run \
    2>&1); then
    log_pass "bq dry_run 문법 검증 통과"
    return 0
  else
    # 테이블 미존재 에러는 문법 자체 오류가 아니므로 경고 처리
    if echo "$result" | grep -qiE 'not found|does not exist|404'; then
      log_warn "bq dry_run: 테이블 미존재 (문법 자체는 확인 불가)"
      warnings=$((warnings + 1))
      return 0
    fi
    log_fail "bq dry_run 실패: $(echo "$result" | head -3)"
    return 1
  fi
}

# ── 메인 ──
echo ""
echo "=========================================="
echo " SQL 파일 검증 (validate-queries.sh)"
echo "=========================================="
echo ""

# 모든 SQL 파일 탐색
while IFS= read -r sql_file; do
  total=$((total + 1))
  rel_path="${sql_file#"$SCRIPT_DIR"/}"
  echo -e "${BLUE}[$total] $rel_path${RESET}"

  file_ok=true

  # 1. 필수 주석 검증
  if ! check_required_comments "$sql_file"; then
    file_ok=false
  fi

  # 2. 파라미터 일관성 검증
  if ! check_params "$sql_file"; then
    file_ok=false
  fi

  # 3. bq dry_run 문법 검증
  if ! check_syntax "$sql_file"; then
    file_ok=false
  fi

  if $file_ok; then
    passed=$((passed + 1))
    log_pass "검증 통과"
  else
    failed=$((failed + 1))
    errors+=("$rel_path")
  fi
  echo ""
done < <(find "$QUERIES_DIR" -name '*.sql' -type f | sort)

# ── 결과 요약 ──
echo "=========================================="
echo " 검증 결과 요약"
echo "=========================================="
echo "  전체: $total 파일"
echo -e "  ${GREEN}통과: $passed${RESET}"
if [ $warnings -gt 0 ]; then
  echo -e "  ${YELLOW}경고: $warnings${RESET}"
fi
if [ $failed -gt 0 ]; then
  echo -e "  ${RED}실패: $failed${RESET}"
  echo ""
  echo "실패 파일:"
  for e in "${errors[@]}"; do
    echo "  - $e"
  done
  echo ""
  exit 1
fi
echo ""
echo -e "${GREEN}모든 SQL 파일 검증 통과!${RESET}"
