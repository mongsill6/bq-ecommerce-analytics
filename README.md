# bq-ecommerce-analytics

[![CI](https://github.com/mongsill6/bq-ecommerce-analytics/actions/workflows/ci.yml/badge.svg)](https://github.com/mongsill6/bq-ecommerce-analytics/actions/workflows/ci.yml)
[![ShellCheck](https://img.shields.io/badge/linter-ShellCheck-blue)](https://www.shellcheck.net/)
[![Bats](https://img.shields.io/badge/tests-Bats-brightgreen)](https://github.com/bats-core/bats-core)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> BigQuery 기반 이커머스 데이터 분석 쿼리 & 자동 리포트 파이프라인
> 매출·재고·광고·상품 분석을 SQL 쿼리로 표준화하고, Google Sheets 리포트로 자동 출력

## 프로젝트 구조

```
bq-ecommerce-analytics/
├── queries/                                # SQL 쿼리 (13개, 1,050+ 줄)
│   ├── sales/                              # 매출 분석
│   │   ├── daily-sales-summary.sql         # 일간 매출 요약 (채널별/카테고리별)
│   │   ├── weekly-trend.sql                # 주간 매출 트렌드 (12주 WoW)
│   │   ├── monthly-comparison.sql          # 월간 전년 대비 + 목표 달성률
│   │   └── top-sellers.sql                 # 베스트셀러 TOP N
│   ├── inventory/                          # 재고 관리/예측
│   │   ├── stock-status.sql                # 현재 재고 현황 + 소진 예측
│   │   ├── depletion-forecast.sql          # 7/14/30일 이동평균 소진 예측
│   │   ├── reorder-alert.sql               # 발주점(ROP) + 안전재고 알림
│   │   └── rocket-delivery-risk.sql        # 로켓배송 재고 위험 감지
│   ├── advertising/                        # 광고 성과
│   │   ├── roas-by-campaign.sql            # 캠페인별 ROAS/CTR/CPA
│   │   ├── ad-spend-efficiency.sql         # 일별 CPC/CPM/CPA/CVR 추이
│   │   └── keyword-performance.sql         # 키워드별 성과 + 중단 검토
│   └── product/                            # 상품 분석
│       ├── gpm-analysis.sql                # 상품별 GPM (수익 등급 산출)
│       └── price-competitiveness.sql       # 카테고리 내 가격 포지션
├── reports/
│   ├── scripts/                            # 리포트 자동화 (4개)
│   │   ├── daily-sales-report.sh           # 일간 매출 → Sheets
│   │   ├── weekly-inventory-alert.sh       # 주간 재고 알림
│   │   ├── monthly-business-report.sh      # 월간 종합 리포트 (5탭)
│   │   └── ad-roas-report.sh               # 광고 ROAS 리포트 (5탭)
│   └── templates/                          # Sheets 리포트 템플릿
├── scripts/                                # 개발 유틸리티
│   ├── validate-queries.sh                 # SQL 파일 검증 (헤더/파라미터/문법)
│   └── bq-schema-doc.sh                    # 스키마 자동 문서화 → 마크다운
├── utils/
│   ├── common.sh                           # 공통 유틸 (로깅, 에러 핸들링, 임시파일)
│   └── bq-helpers.sh                       # BQ 실행 + SQL 인젝션 방지 + 파라미터 검증
├── tests/
│   └── common.bats                         # bats 단위 테스트
├── docs/
│   ├── USAGE.md                            # 상세 사용법
│   └── schemas/                            # 자동 생성 테이블 스키마 문서
│       ├── README.md
│       ├── ca_brands.md
│       ├── ca_product_keywords.md
│       ├── ca_products.md
│       ├── cp_coupon_funding.md
│       ├── cp_nca.md
│       ├── cp_nca_ad.md
│       ├── cp_pa.md
│       ├── cp_products.md
│       ├── cp_reviewer_funding.md
│       ├── daily_performance.md
│       ├── ext_db_skuid.md
│       ├── ext_ops_status.md
│       ├── keyword_rankings.md
│       └── rocket_metrics.md
├── .github/workflows/
│   └── ci.yml                              # CI (ShellCheck + SQL 검증 + Bats)
├── Makefile                                # install, lint, test, validate, schema-doc
├── .shellcheckrc                           # ShellCheck 설정
├── .env.example                            # 환경변수 템플릿
├── CONTRIBUTING.md                         # 기여 가이드
├── LICENSE                                 # MIT License
└── .gitignore
```

**13개 SQL 쿼리 · 4개 리포트 · 2개 개발 스크립트 · 2개 유틸리티 · 15개 스키마 문서 — 총 2,400+ 줄**

## 사전 요구사항

- **bash** 4.0+
- **bq** CLI (Google Cloud SDK)
- **gws** CLI (Sheets 연동용)
- **jq** 1.6+
- 서비스 계정 인증 완료 (`GOOGLE_APPLICATION_CREDENTIALS`)
- **shellcheck** (개발/CI용)
- **bats** (테스트용)

## 빠른 시작

```bash
# 1. 클론
git clone https://github.com/mongsill6/bq-ecommerce-analytics.git
cd bq-ecommerce-analytics

# 2. 의존성 확인
make install

# 3. 환경변수 설정
cp .env.example .env
# .env에서 BQ_PROJECT, BQ_DATASET, GOOGLE_APPLICATION_CREDENTIALS 등 설정

# 4. 바로 사용!

# 오늘의 매출 요약
source utils/bq-helpers.sh
bq_run_sql queries/sales/daily-sales-summary.sql "$(date +%Y-%m-%d)"

# 재고 위험 SKU 확인
bq_run_sql queries/inventory/rocket-delivery-risk.sql

# 일간 매출 리포트 → Google Sheets 자동 업데이트
./reports/scripts/daily-sales-report.sh

# 월간 종합 리포트 (5탭)
./reports/scripts/monthly-business-report.sh 2026-03 50000000
```

## SQL 쿼리 상세

모든 쿼리는 `@param_count`, `@param`, `@example` 주석 헤더를 포함하며,
`bq_run_sql`에 의해 `$1`, `$2` 파라미터가 자동 치환됩니다.

### 매출 분석 (4개, 288줄)

- **`daily-sales-summary.sql`** (45줄) — 특정 날짜 채널별/카테고리별 매출, 주문 수, GPM 산출
  - 파라미터: `$1` (DATE)
- **`weekly-trend.sql`** (48줄) — 최근 12주 주간 매출 트렌드 + WoW 증감률
  - 파라미터: 없음
- **`monthly-comparison.sql`** (149줄) — 전년 동월 대비 비교 + 목표 달성률 + YTD
  - 파라미터: `$1` (YYYY-MM), `$2` (목표 금액)
- **`top-sellers.sql`** (46줄) — 기간 내 베스트셀러 상위 N개
  - 파라미터: `$1`, `$2` (DATE), `$3` (INTEGER)

### 재고 관리 (4개, 361줄)

- **`stock-status.sql`** (67줄) — 전 SKU 재고 현황 + 일평균 판매 기반 소진 예측
  - 파라미터: 없음
- **`depletion-forecast.sql`** (106줄) — 7/14/30일 이동평균 기반 소진일 예측 + 추세/변동계수
  - 파라미터: 없음
- **`reorder-alert.sql`** (116줄) — 발주점(ROP) 계산 + 안전재고 + 리드타임 기반 긴급발주 알림
  - 파라미터: `$1` (INTEGER, 리드타임 일수, 기본 7)
- **`rocket-delivery-risk.sql`** (72줄) — 쿠팡 로켓배송 전용 재고 위험 감지 (14일 미만)
  - 파라미터: 없음

### 광고 성과 (3개, 209줄)

- **`roas-by-campaign.sql`** (58줄) — 캠페인별 ROAS, CTR, CPA, 효율 등급
  - 파라미터: `$1`, `$2` (DATE)
- **`ad-spend-efficiency.sql`** (73줄) — 일별 CPC/CPM/CPA/CVR 추이 + 전일 대비 CPC 변화율
  - 파라미터: `$1`, `$2` (DATE)
- **`keyword-performance.sql`** (78줄) — 키워드별 클릭/전환/ROAS + 중단 검토 등급
  - 파라미터: `$1`, `$2` (DATE)

### 상품 분석 (2개, 206줄)

- **`gpm-analysis.sql`** (62줄) — 상품별 GPM 분석 + 수익 등급 (고수익/보통/저수익/적자위험)
  - 파라미터: `$1`, `$2` (DATE)
- **`price-competitiveness.sql`** (144줄) — 카테고리 평균 대비 가격 포지션 + 백분위 분석
  - 파라미터: `$1`, `$2` (DATE)

## 리포트 자동화

### daily-sales-report.sh — 일간 매출 리포트

```bash
./reports/scripts/daily-sales-report.sh [날짜]
```

Sheets에 '일간매출' + '베스트셀러' 탭 자동 업데이트 + 타임스탬프 기록

### weekly-inventory-alert.sh — 주간 재고 알림

```bash
./reports/scripts/weekly-inventory-alert.sh
```

긴급(7일 미만)/주의(14일 미만) SKU 콘솔 출력 + 로켓배송 즉시 입고 필요 목록

### monthly-business-report.sh — 월간 종합 리포트

```bash
./reports/scripts/monthly-business-report.sh [YYYY-MM] [목표금액]
```

Sheets 5탭 생성: '매출요약'(YoY + 목표달성률) · '베스트셀러'(TOP 20) · '재고현황' · '광고성과'(캠페인 ROAS) · '요약'(대시보드)

### ad-roas-report.sh — 광고 ROAS 리포트

```bash
./reports/scripts/ad-roas-report.sh [종료일] [시작일]
```

Sheets 5탭 생성: '캠페인ROAS' · '적자캠페인'(ROAS < 1) · '광고효율추이'(일별) · '키워드성과' · '주간추이'(28일)

## 유틸리티

### utils/common.sh (66줄)

공통 인프라: `set -euo pipefail` 엄격 모드, 컬러 로깅(`log_info/warn/error/success`), ERR 트랩, 임시파일 자동 정리(`make_temp`), 의존성 체크(`check_deps`, `check_bq_deps`)

### utils/bq-helpers.sh (216줄)

BigQuery 통합 인터페이스:
- **`bq_sanitize_param()`** — SQL 인젝션 방지 (`;`, `--`, `UNION`, `DROP` 등 차단) + 타입별 형식 검증
- **`bq_run_sql()`** — SQL 파일 실행 + `@param_count` 기반 파라미터 개수 검증 + `$1`/`$2` 자동 치환
- **`bq_query()`** — 인라인 SQL 실행 (JSON 출력)
- **`bq_to_csv()`** — SQL 결과 → CSV 파일
- **`bq_to_sheets()`** — SQL 결과 → Google Sheets 업데이트

## 개발 도구

### scripts/validate-queries.sh (242줄)

SQL 파일 자동 검증:
1. 필수 주석 헤더 검증 (`@param_count`, `@example` 등)
2. 파라미터 일관성 검증 (선언 수 vs 실제 사용 수)
3. `bq dry_run`으로 문법 검증

### scripts/bq-schema-doc.sh (213줄)

데이터셋 스키마 → 마크다운 자동 문서화:
```bash
./scripts/bq-schema-doc.sh coupang     # docs/schemas/ 에 테이블별 .md 생성
make schema-doc DATASET=coupang        # Makefile 타겟
```

## 개발

### Makefile 타겟

```bash
make install                    # 의존성 확인 (bq, gws, jq, shellcheck, bats)
make lint                       # ShellCheck 정적 분석
make test                       # Bats 단위 테스트
make validate                   # SQL 검증 (헤더/파라미터/문법)
make schema-doc DATASET=...     # 스키마 마크다운 문서 자동 생성
```

### 크론 등록 예제

```cron
# 매일 오전 8시 — 일간 매출 리포트
0 8 * * * /path/to/bq-ecommerce-analytics/reports/scripts/daily-sales-report.sh

# 매주 월요일 오전 9시 — 주간 재고 알림
0 9 * * 1 /path/to/bq-ecommerce-analytics/reports/scripts/weekly-inventory-alert.sh

# 매월 1일 오전 10시 — 월간 종합 리포트
0 10 1 * * /path/to/bq-ecommerce-analytics/reports/scripts/monthly-business-report.sh

# 매주 금요일 오후 5시 — 광고 ROAS 리포트
0 17 * * 5 /path/to/bq-ecommerce-analytics/reports/scripts/ad-roas-report.sh
```

## CI/CD

GitHub Actions로 `push`/`PR` → `main` 시 자동 검증 (3단계 파이프라인):

1. **ShellCheck Lint** — 모든 `.sh` 파일 정적 분석 + shebang 라인 검증
2. **SQL Validation** — 주석 헤더 + 파라미터 일관성 + 기본 문법 검증
3. **Bats Unit Tests** — `tests/` 디렉터리 단위 테스트 실행

```bash
# 로컬에서 동일한 검증 실행
make lint        # shellcheck
make validate    # SQL 검증
make test        # bats
```

## 보안

- **SQL 인젝션 방지**: `bq_sanitize_param()`으로 모든 사용자 입력 검증
  - 위험 패턴 차단: `;`, `--`, `/*`, `UNION`, `DROP`, `DELETE` 등
  - 타입별 형식 강제: DATE(`YYYY-MM-DD`), INTEGER(숫자만), STRING(이스케이프)
- **파라미터 검증**: `@param_count` 기반 인자 개수 자동 확인
- **Strict mode**: 모든 스크립트에 `set -euo pipefail` 적용

## 문서

- [USAGE.md](docs/USAGE.md) — 전체 쿼리/스크립트 상세 사용법
- [CONTRIBUTING.md](CONTRIBUTING.md) — 개발 환경 설정, SQL 작성 규칙, PR 프로세스
- [docs/schemas/](docs/schemas/) — 자동 생성된 테이블 스키마 문서 (15개 테이블)

## License

MIT
