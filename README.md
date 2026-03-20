# bq-ecommerce-analytics

[![CI](https://github.com/mongsill6/bq-ecommerce-analytics/actions/workflows/ci.yml/badge.svg)](https://github.com/mongsill6/bq-ecommerce-analytics/actions/workflows/ci.yml)
[![ShellCheck](https://img.shields.io/badge/linter-ShellCheck-blue)](https://www.shellcheck.net/)
[![Bats](https://img.shields.io/badge/tests-Bats-brightgreen)](https://github.com/bats-core/bats-core)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> BigQuery 기반 이커머스 데이터 분석 쿼리 & 자동 리포트 파이프라인
> 매출·재고·광고·상품 분석을 SQL 쿼리로 표준화하고, Google Sheets 리포트로 자동 출력

---

## 목차

- [아키텍처](#아키텍처)
- [프로젝트 구조](#프로젝트-구조)
- [설치 및 설정](#설치-및-설정)
- [빠른 시작](#빠른-시작)
- [데이터 모델](#데이터-모델)
- [SQL 쿼리 카탈로그](#sql-쿼리-카탈로그)
- [리포트 자동화](#리포트-자동화)
- [유틸리티](#유틸리티)
- [개발 도구](#개발-도구)
- [CI/CD](#cicd)
- [보안](#보안)
- [문서](#문서)

---

## 아키텍처

```
                          ┌─────────────────────┐
                          │   Google BigQuery    │
                          │  (coupang 데이터셋)   │
                          └──────────┬──────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
     .env (설정)           utils/common.sh           utils/bq-helpers.sh
              │           (로깅/에러트랩)          (BQ 실행/인젝션 방지)
              │                      │                      │
              └──────────────────────┼──────────────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
    queries/**/*.sql       reports/scripts/*.sh      scripts/*.sh
   (13개 파라미터화 SQL)     (4개 자동 리포트)      (검증/문서화 도구)
              │                      │
              │              ┌───────┴───────┐
              │              │ Google Sheets  │
              │              │ (리포트 출력)    │
              │              └───────────────┘
              │
       ┌──────┴──────┐
       │  bq_run_sql  │  ← SQL 인젝션 방지 + 파라미터 자동 치환
       └─────────────┘
```

---

## 프로젝트 구조

```
bq-ecommerce-analytics/
├── queries/                                # SQL 쿼리 (13개, 1,064줄)
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
├── reports/scripts/                        # 리포트 자동화 (4개)
│   ├── daily-sales-report.sh               # 일간 매출 → Sheets
│   ├── weekly-inventory-alert.sh           # 주간 재고 알림
│   ├── monthly-business-report.sh          # 월간 종합 리포트 (5탭)
│   └── ad-roas-report.sh                   # 광고 ROAS 리포트 (5탭)
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
│   └── schemas/                            # 자동 생성 테이블 스키마 문서 (14개)
├── .github/workflows/ci.yml               # CI (ShellCheck + SQL 검증 + Bats)
├── Makefile                                # install, lint, test, validate, schema-doc
├── .shellcheckrc                           # ShellCheck 설정
├── .env.example                            # 환경변수 템플릿
├── CONTRIBUTING.md                         # 기여 가이드
└── .gitignore
```

**13개 SQL 쿼리 · 4개 리포트 · 2개 개발 스크립트 · 2개 유틸리티 · 14개 스키마 문서 — 총 2,196줄**

---

## 설치 및 설정

### 1. 사전 요구사항

- **bash** 4.0+
- **jq** 1.6+
- **shellcheck** (개발/CI용)
- **bats** (테스트용)

### 2. Google Cloud SDK (bq CLI) 설치

```bash
# Linux/macOS
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# 설치 확인
gcloud version
bq version
```

### 3. gws CLI 설치 (Google Sheets 연동)

리포트 스크립트가 Google Sheets에 결과를 출력할 때 `gws` CLI를 사용합니다.

```bash
# gws 설치 확인
gws --version
```

### 4. 서비스 계정 인증

BigQuery에 접근하려면 GCP 서비스 계정 인증이 필요합니다.

```bash
# 서비스 계정 키 파일로 인증
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"

# 인증 확인
bq ls --project_id=inspiring-bonus-484905-v9
```

### 5. 프로젝트 설정

```bash
# 클론
git clone https://github.com/mongsill6/bq-ecommerce-analytics.git
cd bq-ecommerce-analytics

# 의존성 확인
make install

# 환경변수 설정
cp .env.example .env
```

`.env` 파일 구성:

```bash
BQ_PROJECT=inspiring-bonus-484905-v9           # BigQuery 프로젝트 ID
BQ_DATASET=coupang                             # BigQuery 데이터셋 이름
GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json # 서비스 계정 키 파일 경로
GWS_REPORT_SPREADSHEET_ID=your_spreadsheet_id  # 리포트 출력용 Sheets ID
```

- `BQ_PROJECT` — BigQuery 프로젝트 (권장, 기본값: `inspiring-bonus-484905-v9`)
- `BQ_DATASET` — 데이터셋 이름 (필수, SQL 내 `${BQ_DATASET}` 치환에 사용)
- `GOOGLE_APPLICATION_CREDENTIALS` — GCP 서비스 계정 JSON 키 파일 경로 (필수)
- `GWS_REPORT_SPREADSHEET_ID` — 리포트 출력용 Google Spreadsheet ID (리포트 사용 시 필수)

---

## 빠른 시작

```bash
# ── 환경 준비 ──
source utils/bq-helpers.sh

# ── 매출 분석 ──

# 오늘의 매출 요약 (채널별/카테고리별)
bq_run_sql queries/sales/daily-sales-summary.sql "$(date +%Y-%m-%d)"

# 최근 12주 매출 트렌드
bq_run_sql queries/sales/weekly-trend.sql

# 이번 달 전년 대비 + 목표 달성률 (목표 5억)
bq_run_sql queries/sales/monthly-comparison.sql "2026-03" 500000000

# 이번 달 베스트셀러 TOP 10
bq_run_sql queries/sales/top-sellers.sql "2026-03-01" "2026-03-20" 10

# ── 재고 관리 ──

# 전 SKU 재고 현황 + 소진 예측
bq_run_sql queries/inventory/stock-status.sql

# 로켓배송 재고 위험 SKU 확인
bq_run_sql queries/inventory/rocket-delivery-risk.sql

# 발주점 알림 (리드타임 14일)
bq_run_sql queries/inventory/reorder-alert.sql 14

# ── 광고 성과 ──

# 캠페인별 ROAS (최근 30일)
bq_run_sql queries/advertising/roas-by-campaign.sql "2026-02-20" "2026-03-20"

# 키워드 성과 + 중단 검토
bq_run_sql queries/advertising/keyword-performance.sql "2026-03-01" "2026-03-20"

# ── 자동 리포트 → Google Sheets ──

# 일간 매출 리포트
./reports/scripts/daily-sales-report.sh

# 월간 종합 리포트 (5탭)
./reports/scripts/monthly-business-report.sh 2026-03 500000000

# 광고 ROAS 리포트 (5탭)
./reports/scripts/ad-roas-report.sh
```

---

## 데이터 모델

BigQuery 프로젝트 `inspiring-bonus-484905-v9`, 데이터셋 `coupang`에 14개 테이블이 있습니다. 상세 스키마는 [docs/schemas/](docs/schemas/)를 참조하세요.

### 핵심 테이블

**`daily_performance`** — 일별 SKU 판매 실적 (핵심 팩트 테이블)
- 217K행, 36컬럼 | 매출(gmv), 판매량(units_sold), 반품(return_units), 원가(cogs), 주문수, 고객수, 전환율, PV 등
- 쿼리 연관: `daily-sales-summary`, `weekly-trend`, `monthly-comparison`, `top-sellers`, `gpm-analysis`

**`cp_products`** — 상품 마스터 (디멘전 테이블)
- 4.5K행, 16컬럼 | SKU 정보, 카테고리 체계(대/중/소), 브랜드, 주문/판매 상태
- 쿼리 연관: `stock-status`, `price-competitiveness`, 전 재고 쿼리

**`rocket_metrics`** — 로켓배송 재고/물류 지표
- 105K행, 21컬럼 | 센터별 입고/출고/재고 수량, 주문이행률, 반품률, 품절 여부
- 쿼리 연관: `stock-status`, `rocket-delivery-risk`, `depletion-forecast`, `reorder-alert`

### 광고 테이블

**`cp_nca`** — 쿠팡 NCA(네이티브 커머스 광고) 성과
- 150K행, 19컬럼 | 캠페인/광고/키워드 단위 노출·클릭·비용·매출
- 쿼리 연관: `roas-by-campaign`, `ad-spend-efficiency`, `keyword-performance`

**`cp_nca_ad`** — NCA 광고 소재별 상세
- 캠페인-광고-키워드 레벨 세분화 데이터

**`cp_pa`** — 쿠팡 PA(퍼포먼스 광고) 성과
- 915K행, 34컬럼 | 1일/14일 전환 윈도우별 주문·매출 (직접/간접 전환 구분)
- 쿼리 연관: `roas-by-campaign`, `ad-spend-efficiency`

### 키워드/브랜드 테이블

**`keyword_rankings`** — 키워드 검색 순위 추적
- 85K행, 18컬럼 | 키워드별 검색 순위, 광고 여부, 가격, 리뷰, 자사 상품 여부
- 쿼리 연관: `keyword-performance`, `price-competitiveness`

**`ca_brands`** — 쿠팡 애널리틱스 브랜드 데이터

**`ca_products`** — 쿠팡 애널리틱스 상품 데이터

**`ca_product_keywords`** — 상품별 키워드 매핑

### 프로모션/쿠폰 테이블

**`cp_coupon_funding`** — 쿠폰 펀딩 내역

**`cp_reviewer_funding`** — 리뷰어 펀딩 내역

### 외부 연동 테이블

**`ext_db_skuid`** — 외부 DB SKU ID 매핑 (EXTERNAL)

**`ext_ops_status`** — 운영 상태 외부 시트 연동 (EXTERNAL)
- 20컬럼 | 카테고리, 모델, 재고(배치/가용/쿠팡), 판매/주문 상태

### 테이블 관계도

```
cp_products (상품 마스터)
  │
  ├──< daily_performance (일별 매출)     ── barcode/sku_id JOIN
  ├──< rocket_metrics (재고/물류)         ── barcode JOIN
  ├──< cp_nca (NCA 광고)                 ── ad_product → product
  ├──< cp_pa (PA 광고)                   ── ad_product → product
  └──< keyword_rankings (검색순위)        ── product_id JOIN

ext_ops_status ──> cp_products           ── sku_id/barcode 매핑
```

---

## SQL 쿼리 카탈로그

모든 쿼리는 `@param_count`, `@param`, `@example` 주석 헤더를 포함하며,
`bq_run_sql`에 의해 `$1`, `$2` 파라미터가 자동 치환됩니다.

### 매출 분석 (4개, 288줄)

**`daily-sales-summary.sql`** (45줄) — 특정 날짜 채널별/카테고리별 매출, 주문 수, GPM 산출
- 파라미터: `$1` DATE (필수)
- 소스 테이블: `daily_performance`

**`weekly-trend.sql`** (48줄) — 최근 12주 주간 매출 트렌드 + WoW 증감률
- 파라미터: 없음
- 소스 테이블: `daily_performance`

**`monthly-comparison.sql`** (149줄) — 전년 동월 대비 비교 + 목표 달성률 + YTD
- 파라미터: `$1` STRING YYYY-MM, `$2` NUMERIC 목표금액
- 소스 테이블: `daily_performance`

**`top-sellers.sql`** (46줄) — 기간 내 베스트셀러 상위 N개
- 파라미터: `$1` DATE 시작일, `$2` DATE 종료일, `$3` INTEGER TOP N
- 소스 테이블: `daily_performance`

### 재고 관리 (4개, 361줄)

**`stock-status.sql`** (67줄) — 전 SKU 재고 현황 + 일평균 판매 기반 소진 예측
- 파라미터: 없음
- 소스 테이블: `rocket_metrics`, `daily_performance`

**`depletion-forecast.sql`** (106줄) — 7/14/30일 이동평균 기반 소진일 예측 + 추세/변동계수
- 파라미터: 없음
- 소스 테이블: `rocket_metrics`, `daily_performance`

**`reorder-alert.sql`** (116줄) — 발주점(ROP) 계산 + 안전재고 + 리드타임 기반 긴급발주 알림
- 파라미터: `$1` INTEGER 리드타임 일수 (선택, 기본값: 7)
- 소스 테이블: `rocket_metrics`, `daily_performance`

**`rocket-delivery-risk.sql`** (72줄) — 쿠팡 로켓배송 전용 재고 위험 감지 (14일 미만)
- 파라미터: 없음
- 소스 테이블: `rocket_metrics`, `daily_performance`

### 광고 성과 (3개, 209줄)

**`roas-by-campaign.sql`** (58줄) — 캠페인별 ROAS, CTR, CPA, 효율 등급
- 파라미터: `$1` DATE 시작일, `$2` DATE 종료일
- 소스 테이블: `cp_nca`, `cp_pa`

**`ad-spend-efficiency.sql`** (73줄) — 일별 CPC/CPM/CPA/CVR 추이 + 전일 대비 CPC 변화율
- 파라미터: `$1` DATE 시작일, `$2` DATE 종료일
- 소스 테이블: `cp_nca`, `cp_pa`

**`keyword-performance.sql`** (78줄) — 키워드별 클릭/전환/ROAS + 중단 검토 등급
- 파라미터: `$1` DATE 시작일, `$2` DATE 종료일
- 소스 테이블: `cp_nca`, `keyword_rankings`

### 상품 분석 (2개, 206줄)

**`gpm-analysis.sql`** (62줄) — 상품별 GPM 분석 + 수익 등급 (고수익/보통/저수익/적자위험)
- 파라미터: `$1` DATE 시작일, `$2` DATE 종료일
- 소스 테이블: `daily_performance`

**`price-competitiveness.sql`** (144줄) — 카테고리 평균 대비 가격 포지션 + 백분위 분석
- 파라미터: `$1` DATE 시작일, `$2` DATE 종료일
- 소스 테이블: `daily_performance`, `keyword_rankings`

---

## 리포트 자동화

4개 리포트 스크립트가 SQL 쿼리를 조합하여 Google Sheets에 자동 출력합니다.
모두 `GWS_REPORT_SPREADSHEET_ID` 환경변수가 필요합니다 (weekly-inventory-alert 제외).

### daily-sales-report.sh — 일간 매출 리포트

```bash
./reports/scripts/daily-sales-report.sh [날짜]
# 예: ./reports/scripts/daily-sales-report.sh 2026-03-20
# 날짜 생략 시 오늘 기준
```

- Sheets `일간매출` 탭: 채널별/카테고리별 매출 요약
- Sheets `베스트셀러` 탭: 당일 TOP 10 상품
- 타임스탬프 자동 기록

### weekly-inventory-alert.sh — 주간 재고 알림

```bash
./reports/scripts/weekly-inventory-alert.sh
```

- 콘솔 출력 (Sheets 미사용)
- 긴급(7일 미만) / 주의(14일 미만) SKU 수 요약
- 로켓배송 즉시 입고 필요 SKU 목록
- 긴급 SKU 상세 (sku, 상품명, 잔여일)

### monthly-business-report.sh — 월간 종합 리포트

```bash
./reports/scripts/monthly-business-report.sh [YYYY-MM] [목표금액]
# 예: ./reports/scripts/monthly-business-report.sh 2026-03 800000000
# 기본값: 이번 달, 목표 5억
```

Sheets 5탭 생성:

- `매출요약` — 전년 동월 대비 + 목표 달성률 + YTD 누적
- `베스트셀러` — TOP 20 상품
- `재고현황` — 전 SKU 재고 + 긴급/주의 집계
- `광고성과` — 캠페인별 ROAS
- `요약` — 대시보드 (핵심 지표 모음)

### ad-roas-report.sh — 광고 ROAS 리포트

```bash
./reports/scripts/ad-roas-report.sh [종료일] [시작일]
# 예: ./reports/scripts/ad-roas-report.sh 2026-03-20 2026-03-01
# 기본값: 오늘 ~ 7일 전
```

Sheets 5탭 생성:

- `캠페인ROAS` — 캠페인별 ROAS + 적자 캠페인 콘솔 경고
- `적자캠페인` — ROAS < 1 캠페인 목록
- `광고효율추이` — 일별 CPC/CPM/CPA/CVR
- `키워드성과` — 키워드별 성과 + 중단 검토 대상
- `주간추이` — 최근 28일 주간 집계

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

---

## 유틸리티

### utils/common.sh (66줄)

공통 인프라:
- `set -euo pipefail` 엄격 모드
- 컬러 로깅: `log_info`, `log_warn`, `log_error`, `log_success`
- ERR 트랩 (에러 발생 시 파일명:줄번호 출력)
- `make_temp` — 임시파일 생성 + EXIT 시 자동 정리
- `check_deps`, `check_bq_deps` — 의존성 존재 확인

### utils/bq-helpers.sh (216줄)

BigQuery 통합 인터페이스:

- **`bq_sanitize_param(value, type)`** — SQL 인젝션 방지
  - 위험 패턴 차단: `;`, `--`, `/*`, `UNION`, `DROP`, `DELETE` 등
  - 타입별 형식 강제: DATE(`YYYY-MM-DD`), INTEGER(숫자만), STRING(이스케이프)
- **`bq_run_sql(file, ...params)`** — SQL 파일 실행
  - `@param_count` 기반 파라미터 개수 자동 검증
  - `$1`/`$2` 자동 치환 + 인젝션 방지
- **`bq_query(sql)`** — 인라인 SQL 실행 (JSON 출력)
- **`bq_to_csv(sql, output_path)`** — SQL 결과 → CSV 파일
- **`bq_to_sheets(sql, spreadsheet_id, range)`** — SQL 결과 → Google Sheets 업데이트

---

## 개발 도구

### scripts/validate-queries.sh (242줄)

SQL 파일 자동 검증:
1. 필수 주석 헤더 검증 (`@param_count`, `@example` 등)
2. 파라미터 일관성 검증 (선언 수 vs 실제 사용 수)
3. `bq dry_run`으로 문법 검증

```bash
bash scripts/validate-queries.sh   # 직접 실행
make validate                      # Makefile 경유
```

### scripts/bq-schema-doc.sh (213줄)

데이터셋 스키마 → 마크다운 자동 문서화:

```bash
./scripts/bq-schema-doc.sh coupang         # docs/schemas/ 에 테이블별 .md 생성
make schema-doc DATASET=coupang            # Makefile 경유
```

### Makefile 타겟

```bash
make help          # 사용법 출력
make install       # 의존성 확인 (bq, gws, jq, shellcheck, bats)
make lint          # ShellCheck 정적 분석
make test          # Bats 단위 테스트
make validate      # SQL 검증 (헤더/파라미터/문법)
make schema-doc DATASET=coupang   # 스키마 마크다운 문서 자동 생성
```

---

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

---

## 보안

- **SQL 인젝션 방지**: `bq_sanitize_param()`으로 모든 사용자 입력 검증
  - 위험 패턴 차단: `;`, `--`, `/*`, `UNION`, `DROP`, `DELETE` 등
  - 타입별 형식 강제: DATE(`YYYY-MM-DD`), INTEGER(숫자만), STRING(이스케이프)
- **파라미터 검증**: `@param_count` 기반 인자 개수 자동 확인
- **Strict mode**: 모든 스크립트에 `set -euo pipefail` 적용
- **임시파일 보안**: `mktemp` 사용 + EXIT 트랩으로 자동 정리

---

## 문서

- [USAGE.md](docs/USAGE.md) — 전체 쿼리/스크립트 상세 사용법
- [CONTRIBUTING.md](CONTRIBUTING.md) — 개발 환경 설정, SQL 작성 규칙, PR 프로세스
- [docs/schemas/](docs/schemas/) — 자동 생성된 테이블 스키마 문서 (14개 테이블)

---

## License

MIT
