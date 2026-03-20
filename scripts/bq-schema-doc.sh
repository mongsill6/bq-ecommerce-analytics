#!/usr/bin/env bash
# bq-schema-doc.sh — 지정 데이터셋의 모든 테이블 스키마를 마크다운 문서로 생성
# 사용법: bash scripts/bq-schema-doc.sh [DATASET]
# 출력: docs/schemas/<table>.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 공통 유틸리티 로드
# shellcheck source=../utils/common.sh
source "$SCRIPT_DIR/utils/common.sh"

# .env 로드
if [ -f "$SCRIPT_DIR/.env" ]; then
  # shellcheck source=/dev/null
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi

BQ_PROJECT="${BQ_PROJECT:-inspiring-bonus-484905-v9}"
BQ_DATASET="${1:-${BQ_DATASET:-}}"

if [ -z "$BQ_DATASET" ]; then
  log_error "데이터셋을 지정하세요: bash scripts/bq-schema-doc.sh <DATASET>"
  log_error "  예: bash scripts/bq-schema-doc.sh ecommerce"
  exit 1
fi

check_deps bq jq

OUTPUT_DIR="$SCRIPT_DIR/docs/schemas"
mkdir -p "$OUTPUT_DIR"

FULL_DATASET="${BQ_PROJECT}:${BQ_DATASET}"

log_info "데이터셋: $FULL_DATASET"
log_info "출력 디렉토리: $OUTPUT_DIR"

# ── 테이블 목록 조회 ──
log_info "테이블 목록 조회 중..."
tables_json=$(make_temp "bq-tables")
bq ls --format=json --max_results=1000 "$FULL_DATASET" > "$tables_json"

table_count=$(jq 'length' "$tables_json")
if [ "$table_count" -eq 0 ]; then
  log_warn "데이터셋에 테이블이 없습니다: $FULL_DATASET"
  exit 0
fi

log_info "테이블 ${table_count}개 발견"

# ── 타입 매핑 ──
bq_type_desc() {
  case "$1" in
    STRING)    echo "문자열" ;;
    INTEGER|INT64) echo "정수" ;;
    FLOAT|FLOAT64) echo "실수" ;;
    NUMERIC|BIGNUMERIC) echo "고정소수점" ;;
    BOOLEAN|BOOL) echo "불리언" ;;
    DATE)      echo "날짜" ;;
    DATETIME)  echo "날짜시간" ;;
    TIMESTAMP) echo "타임스탬프" ;;
    TIME)      echo "시간" ;;
    BYTES)     echo "바이트" ;;
    RECORD|STRUCT) echo "구조체" ;;
    GEOGRAPHY) echo "지리정보" ;;
    JSON)      echo "JSON" ;;
    *)         echo "$1" ;;
  esac
}

# ── RECORD 필드 재귀 렌더링 ──
render_fields() {
  local fields_json="$1"
  local depth="${2:-0}"
  local prefix="${3:-}"

  local count
  count=$(echo "$fields_json" | jq 'length')

  for (( i=0; i<count; i++ )); do
    local name type mode description fields_nested
    name=$(echo "$fields_json" | jq -r ".[$i].name")
    type=$(echo "$fields_json" | jq -r ".[$i].type")
    mode=$(echo "$fields_json" | jq -r ".[$i].mode // \"NULLABLE\"")
    description=$(echo "$fields_json" | jq -r ".[$i].description // \"\"")

    local display_name="${prefix}${name}"
    local mode_badge=""
    if [ "$mode" = "REQUIRED" ]; then
      mode_badge=' `REQUIRED`'
    elif [ "$mode" = "REPEATED" ]; then
      mode_badge=' `REPEATED`'
    fi

    local desc_col=""
    if [ -n "$description" ]; then
      desc_col=" $description"
    fi

    printf '| `%s` | `%s`%s |%s |\n' "$display_name" "$type" "$mode_badge" "$desc_col"

    # RECORD 타입이면 하위 필드 재귀
    if [ "$type" = "RECORD" ] || [ "$type" = "STRUCT" ]; then
      fields_nested=$(echo "$fields_json" | jq ".[$i].fields // []")
      local nested_count
      nested_count=$(echo "$fields_nested" | jq 'length')
      if [ "$nested_count" -gt 0 ]; then
        render_fields "$fields_nested" $((depth + 1)) "${display_name}."
      fi
    fi
  done
}

# ── 각 테이블 처리 ──
generated=0
for (( idx=0; idx<table_count; idx++ )); do
  table_id=$(jq -r ".[$idx].tableReference.tableId" "$tables_json")
  table_type=$(jq -r ".[$idx].type" "$tables_json")

  log_info "[$(( idx + 1 ))/$table_count] $table_id ($table_type)"

  # 스키마 조회
  schema_json=$(make_temp "bq-schema")
  bq show --format=json "${BQ_PROJECT}:${BQ_DATASET}.${table_id}" > "$schema_json"

  # 메타데이터 추출
  num_rows=$(jq -r '.numRows // "N/A"' "$schema_json")
  num_bytes=$(jq -r '.numBytes // "0"' "$schema_json")
  created=$(jq -r '.creationTime // ""' "$schema_json")
  modified=$(jq -r '.lastModifiedTime // ""' "$schema_json")
  table_desc=$(jq -r '.description // ""' "$schema_json")

  # 바이트를 읽기 좋은 형식으로 변환
  if [ "$num_bytes" != "0" ] && [ "$num_bytes" != "N/A" ]; then
    if [ "$num_bytes" -ge 1073741824 ]; then
      size_human="$(echo "scale=2; $num_bytes / 1073741824" | bc) GB"
    elif [ "$num_bytes" -ge 1048576 ]; then
      size_human="$(echo "scale=2; $num_bytes / 1048576" | bc) MB"
    elif [ "$num_bytes" -ge 1024 ]; then
      size_human="$(echo "scale=2; $num_bytes / 1024" | bc) KB"
    else
      size_human="${num_bytes} B"
    fi
  else
    size_human="N/A"
  fi

  # 타임스탬프 변환 (밀리초 → 날짜)
  created_date="N/A"
  modified_date="N/A"
  if [ -n "$created" ] && [ "$created" != "null" ]; then
    created_date=$(date -d "@$(( created / 1000 ))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")
  fi
  if [ -n "$modified" ] && [ "$modified" != "null" ]; then
    modified_date=$(date -d "@$(( modified / 1000 ))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")
  fi

  # 필드 목록
  fields=$(jq '.schema.fields // []' "$schema_json")
  field_count=$(echo "$fields" | jq 'length')

  # 마크다운 파일 생성
  md_file="$OUTPUT_DIR/${table_id}.md"
  {
    echo "# ${table_id}"
    echo ""
    if [ -n "$table_desc" ]; then
      echo "> $table_desc"
      echo ""
    fi
    echo "- **데이터셋**: \`${BQ_PROJECT}.${BQ_DATASET}\`"
    echo "- **유형**: ${table_type}"
    echo "- **행 수**: ${num_rows}"
    echo "- **크기**: ${size_human}"
    echo "- **생성일**: ${created_date}"
    echo "- **수정일**: ${modified_date}"
    echo "- **컬럼 수**: ${field_count}"
    echo ""
    echo "## 스키마"
    echo ""
    echo "| 컬럼명 | 타입 | 설명 |"
    echo "|--------|------|------|"
    render_fields "$fields"
    echo ""
    echo "---"
    echo "*자동 생성: $(date '+%Y-%m-%d %H:%M:%S') by bq-schema-doc.sh*"
  } > "$md_file"

  generated=$((generated + 1))
done

# ── 인덱스 파일 생성 ──
index_file="$OUTPUT_DIR/README.md"
{
  echo "# ${BQ_DATASET} 데이터셋 스키마 문서"
  echo ""
  echo "- **프로젝트**: \`${BQ_PROJECT}\`"
  echo "- **데이터셋**: \`${BQ_DATASET}\`"
  echo "- **테이블 수**: ${table_count}"
  echo "- **생성일**: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "## 테이블 목록"
  echo ""
  for (( idx=0; idx<table_count; idx++ )); do
    table_id=$(jq -r ".[$idx].tableReference.tableId" "$tables_json")
    table_type=$(jq -r ".[$idx].type" "$tables_json")
    echo "- [${table_id}](./${table_id}.md) (${table_type})"
  done
} > "$index_file"

log_success "스키마 문서 ${generated}개 생성 완료 → $OUTPUT_DIR/"
trap - ERR EXIT
set +e
