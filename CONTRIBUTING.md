# Contributing Guide

bq-ecommerce-analytics에 기여하기 위한 가이드입니다.

## 개발 환경 설정

```bash
# .env 파일 생성
cp .env.example .env
# BQ_PROJECT, BQ_DATASET, GOOGLE_APPLICATION_CREDENTIALS 값 설정

# 의존성 확인
make install

# 전체 테스트
make lint && make test && make validate
```

**필수 도구:**
- bash 4.0+
- bq CLI (BigQuery)
- gws CLI (리포트 Sheets 출력용)
- jq
- shellcheck
- bats (Bash Automated Testing System)

## 코딩 컨벤션

### 셸 스크립트 기본 규칙

1. **Shebang**: 모든 스크립트는 `#!/usr/bin/env bash`로 시작
2. **엄격 모드**: `set -euo pipefail` 필수 (common.sh에서 적용)
3. **shellcheck 준수**: 모든 코드는 `shellcheck -S warning` 통과 필수
4. **common.sh 사용**: 모든 스크립트는 `utils/common.sh`를 source

```bash
#!/usr/bin/env bash
# 스크립트 설명 (한 줄)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/bq-helpers.sh"

check_bq_deps  # 의존성 검사
```

### 변수와 함수

- **변수명**: `UPPER_SNAKE_CASE` (환경변수/상수), `lower_snake_case` (지역변수)
- **함수명**: `lower_snake_case`
- **지역변수**: 함수 내부에서 `local` 키워드 사용
- **변수 참조**: 항상 `"${variable}"` 형식으로 쌍따옴표 사용

```bash
# 좋은 예
local row_count=0
readonly MAX_ROWS=10000

# 나쁜 예
rowCount=0
```

### 로깅

`common.sh`의 로깅 함수를 사용합니다. `echo`를 직접 사용하지 않습니다.

```bash
log_info "쿼리 실행 중: ${sql_file}"
log_warn "결과가 비어 있습니다"
log_error "BigQuery 실행 실패 (exit: ${exit_code})"
log_success "리포트 생성 완료: ${sheet_name}"
```

### 임시파일

`common.sh`의 `make_temp`을 사용합니다. EXIT 트랩에 의해 자동 정리됩니다.

```bash
local tmp_file
tmp_file=$(make_temp "bq-result")
bq_query "${sql}" > "${tmp_file}"
```

### BigQuery 호출

`bq` CLI를 직접 호출하지 말고, `utils/bq-helpers.sh`의 함수를 사용합니다.

```bash
# 좋은 예 — SQL 파일 실행 (파라미터 자동 검증/치환)
bq_run_sql queries/sales/top-sellers.sql "2026-03-01" "2026-03-20" 10

# 좋은 예 — 인라인 SQL
bq_query "SELECT COUNT(*) FROM \`${BQ_DATASET}.orders\`"

# 좋은 예 — CSV 출력
bq_to_csv "SELECT * FROM \`${BQ_DATASET}.orders\` LIMIT 100" /tmp/output.csv

# 좋은 예 — Sheets 연동
bq_to_sheets "SELECT * FROM \`${BQ_DATASET}.orders\`" "${SPREADSHEET_ID}" "Sheet1!A2"

# 나쁜 예 — bq 직접 호출
bq query --use_legacy_sql=false "SELECT ..."
```

### SQL 인젝션 방지

외부 입력값은 반드시 `bq_sanitize_param`으로 검증합니다. `bq_run_sql`은 `@param` 타입 기반으로 자동 검증합니다.

```bash
# bq_run_sql 사용 시 자동 검증됨
bq_run_sql queries/sales/daily-sales-summary.sql "${user_input_date}"

# 인라인 SQL에서는 수동 검증 필요
local safe_date
safe_date=$(bq_sanitize_param "${user_input}" "DATE")
bq_query "SELECT * FROM \`${BQ_DATASET}.orders\` WHERE date = '${safe_date}'"
```

### .shellcheckrc

프로젝트 루트의 `.shellcheckrc`에 전역 설정이 있습니다:

- `source-path=SCRIPTDIR`, `source-path=utils/` — source 경로 힌트
- `SC1091` 비활성화 — 런타임 경로 source 경고 무시
- `SC2155` 비활성화 — declare+할당 분리 권고 무시

인라인 비활성화가 필요한 경우 사유를 주석으로 남깁니다:

```bash
# shellcheck disable=SC2034  # bq-helpers.sh에서 참조하는 변수
BQ_DATASET="${BQ_DATASET}"
```

## SQL 쿼리 작성 규칙

### 파일 헤더 (필수)

모든 SQL 파일은 다음 주석 헤더를 포함해야 합니다:

```sql
-- 파일명.sql
-- 쿼리 설명 (한 줄)
-- @param_count N
-- @param $1 TYPE 필수|선택 설명
-- @param $2 TYPE 필수|선택 설명
-- @example bq_run_sql queries/category/파일명.sql "값1" "값2"
```

**타입:** `DATE` (YYYY-MM-DD), `STRING`, `INTEGER`, `NUMERIC`

### 테이블 참조

데이터셋명은 `${BQ_DATASET}` 변수를 사용합니다. 하드코딩하지 않습니다.

```sql
-- 좋은 예
SELECT * FROM `${BQ_DATASET}.orders`

-- 나쁜 예
SELECT * FROM `ecommerce.orders`
```

### 파라미터 참조

위치 파라미터 `$1`, `$2` 등을 사용합니다. `bq_run_sql`이 실행 시 치환합니다.

```sql
WHERE order_date = '$1'
  AND category = '$2'
LIMIT $3
```

### 카테고리 디렉토리

- `queries/sales/` — 매출 관련
- `queries/inventory/` — 재고 관련
- `queries/advertising/` — 광고 관련
- `queries/product/` — 상품 분석 관련

새 카테고리가 필요하면 디렉토리를 추가합니다.

### 검증

새 SQL 추가 후 반드시 `make validate`로 구조와 문법을 검증합니다.

```bash
# SQL 검증 (헤더, 파라미터 일관성, dry_run 문법)
make validate
```

## 리포트 스크립트 작성 규칙

- `reports/scripts/` 디렉토리에 생성
- `bq-helpers.sh`를 source하여 `bq_run_sql`, `bq_to_sheets` 등 사용
- Sheets 출력이 필요한 경우 `GWS_REPORT_SPREADSHEET_ID`를 `${var:?}` 형식으로 검증
- 각 섹션별로 `echo_header`로 구분

```bash
echo_header "매출 요약"
bq_run_sql queries/sales/daily-sales-summary.sql "${date}" | \
    bq_to_sheets - "${GWS_REPORT_SPREADSHEET_ID:?GWS_REPORT_SPREADSHEET_ID 미설정}" "매출!A2"
```

## 테스트 작성 규칙

### bats 테스트 구조

테스트 파일은 `tests/` 디렉토리에 `*.bats` 확장자로 작성합니다.

```bash
#!/usr/bin/env bats

setup() {
    UTILS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../utils" && pwd)"
    # common.sh의 set -euo pipefail과 trap을 제거 후 로드
    COMMON_SRC=$(sed -E \
        -e 's/^set -euo pipefail$//' \
        -e "/^trap '.*' ERR$/d" \
        "${UTILS_DIR}/common.sh")
    eval "${COMMON_SRC}"
}

@test "함수명: 동작 설명" {
    run my_function "arg1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected"* ]]
}
```

### 테스트 작성 원칙

- 각 함수의 정상 케이스와 실패 케이스 모두 테스트
- `run` 키워드로 명령 실행 후 `$status`와 `$output` 검증
- stderr 검증이 필요한 경우 `run bash -c '...'` 패턴 사용
- 외부 API(bq, gws)를 호출하는 함수는 mock/stub 처리
- `bq_sanitize_param`의 각 타입별 정상/거부 케이스 검증

## PR 절차

### 브랜치 전략

```
main ← feature/기능명
main ← fix/버그명
main ← docs/문서명
main ← query/쿼리명
```

### PR 제출 전 체크리스트

- [ ] `make lint` 통과 (shellcheck)
- [ ] `make test` 통과 (bats)
- [ ] `make validate` 통과 (SQL 검증)
- [ ] 새 스크립트는 `docs/USAGE.md`에 사용법 추가
- [ ] 새 SQL은 헤더 주석 완비 (`@param_count`, `@param`, `@example`)
- [ ] 커밋 메시지는 [Conventional Commits](https://www.conventionalcommits.org/) 형식 사용
  - `feat:` 새 기능/쿼리
  - `fix:` 버그 수정
  - `docs:` 문서 변경
  - `ci:` CI/CD 변경
  - `refactor:` 리팩터링
  - `test:` 테스트 추가/수정
  - `query:` SQL 쿼리 추가/수정

### PR 프로세스

1. `main`에서 feature 브랜치 생성
2. 변경사항 커밋 (Conventional Commits 형식)
3. `make lint && make test && make validate` 전체 통과 확인
4. PR 생성 — 변경사항 요약 + 테스트 결과 포함
5. GitHub Actions CI 통과 확인
6. 리뷰 승인 후 merge

### CI 파이프라인

PR 제출 시 자동 실행되는 검증:

1. **shellcheck**: 모든 `.sh` 파일 정적 분석 + shebang 검증
2. **sql-validation**: SQL 파일 존재 확인 + 주석 헤더 + 파라미터 일관성
3. **bats**: `tests/` 디렉토리 단위 테스트

세 단계 모두 통과해야 merge 가능합니다.
