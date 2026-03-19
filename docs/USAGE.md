# Usage Guide

bq-ecommerce-analytics의 모든 스크립트와 쿼리 사용법을 정리한 가이드입니다.

## 사전 요구사항

- **bash** 4.0 이상
- **bq** CLI (BigQuery CLI) — 서비스 계정 인증 완료
- **gws** CLI (Google Workspace CLI) — 리포트 스크립트의 Sheets 출력용
- **jq** — JSON 파서

## 환경변수

`.env.example`을 `.env`로 복사한 후 값을 설정합니다.

```bash
cp .env.example .env
```

| 변수 | 필수 | 기본값 | 설명 |
|------|------|--------|------|
| `BQ_PROJECT` | 권장 | `inspiring-bonus-484905-v9` | BigQuery 프로젝트 ID |
| `BQ_DATASET` | 필수 | (빈 문자열) | BigQuery 데이터셋 이름. SQL 내 `${BQ_DATASET}` 치환에 사용 |
| `GOOGLE_APPLICATION_CREDENTIALS` | 필수 | — | GCP 서비스 계정 JSON 키 파일 경로 |
| `GWS_REPORT_SPREADSHEET_ID` | 리포트 사용 시 | — | 리포트 출력용 Google Spreadsheet ID |

**참고:** `utils/bq-helpers.sh`가 `.env` 파일을 자동으로 로드합니다.

## 아키텍처 개요

```
.env → utils/common.sh → utils/bq-helpers.sh → queries/*.sql
                                              → reports/scripts/*.sh
```

- `utils/common.sh`: 로깅, 에러 트랩, 임시파일 관리
- `utils/bq-helpers.sh`: .env 로드, BQ 실행 함수, SQL 인젝션 방지, Sheets 연동
- `queries/*.sql`: 파라미터화된 BigQuery SQL 쿼리
- `reports/scripts/*.sh`: 쿼리를 조합하여 리포트 자동 생성

---

## SQL 쿼리

모든 SQL 파일은 `bq_run_sql` 함수로 실행합니다. 파라미터는 `$1`, `$2` 등으로 전달됩니다.

### 매출 (queries/sales/)

#### daily-sales-summary.sql

특정 날짜의 채널별/카테고리별 매출을 요약합니다.

```bash
source utils/bq-helpers.sh
bq_run_sql queries/sales/daily-sales-summary.sql "2026-03-20"
```

**파라미터:** `$1` — 날짜 (DATE, YYYY-MM-DD, 필수)

#### weekly-trend.sql

최근 12주 주간 매출 트렌드와 WoW(전주 대비) 증감률을 조회합니다.

```bash
bq_run_sql queries/sales/weekly-trend.sql
```

**파라미터:** 없음

#### monthly-comparison.sql

전년 동월 대비 매출 비교와 목표 달성률을 계산합니다.

```bash
bq_run_sql queries/sales/monthly-comparison.sql "2026-03" 500000000
```

**파라미터:**
- `$1` — 대상 월 (STRING, YYYY-MM)
- `$2` — 매출 목표 금액 (NUMERIC)

#### top-sellers.sql

기간 내 베스트셀러 상위 N개 상품을 조회합니다.

```bash
bq_run_sql queries/sales/top-sellers.sql "2026-03-01" "2026-03-20" 10
```

**파라미터:**
- `$1` — 시작일 (DATE, 필수)
- `$2` — 종료일 (DATE, 필수)
- `$3` — TOP N (INTEGER, 필수)

---

### 재고 (queries/inventory/)

#### stock-status.sql

전 SKU 재고 현황과 일평균 판매 기반 소진 예측일을 조회합니다.

```bash
bq_run_sql queries/inventory/stock-status.sql
```

**파라미터:** 없음

#### depletion-forecast.sql

7일/14일/30일 이동평균 기반 소진일 예측, 추세 방향, 변동계수를 산출합니다.

```bash
bq_run_sql queries/inventory/depletion-forecast.sql
```

**파라미터:** 없음

#### reorder-alert.sql

발주점(ROP) 계산, 안전재고 산출, 긴급발주 알림을 생성합니다.

```bash
# 리드타임 7일 (기본값)
bq_run_sql queries/inventory/reorder-alert.sql

# 리드타임 14일 지정
bq_run_sql queries/inventory/reorder-alert.sql 14
```

**파라미터:** `$1` — 리드타임 일수 (INTEGER, 선택, 기본값: 7)

#### rocket-delivery-risk.sql

쿠팡 로켓배송 전용 재고 위험(14일 미만 소진 예측)을 감지합니다.

```bash
bq_run_sql queries/inventory/rocket-delivery-risk.sql
```

**파라미터:** 없음

---

### 광고 (queries/advertising/)

#### roas-by-campaign.sql

캠페인별 ROAS, CTR, CPA, 효율 등급을 산출합니다.

```bash
bq_run_sql queries/advertising/roas-by-campaign.sql "2026-03-01" "2026-03-20"
```

**파라미터:**
- `$1` — 시작일 (DATE, 필수)
- `$2` — 종료일 (DATE, 필수)

#### ad-spend-efficiency.sql

일별 CPC/CPM/CPA/CVR 추이와 전일 대비 CPC 변화율을 조회합니다.

```bash
bq_run_sql queries/advertising/ad-spend-efficiency.sql "2026-03-01" "2026-03-20"
```

**파라미터:**
- `$1` — 시작일 (DATE, 필수)
- `$2` — 종료일 (DATE, 필수)

#### keyword-performance.sql

키워드별 클릭/전환/ROAS와 중단 검토 등급을 산출합니다.

```bash
bq_run_sql queries/advertising/keyword-performance.sql "2026-03-01" "2026-03-20"
```

**파라미터:**
- `$1` — 시작일 (DATE, 필수)
- `$2` — 종료일 (DATE, 필수)

---

### 상품 (queries/product/)

#### gpm-analysis.sql

상품별 GPM(Gross Profit Margin) 분석과 수익 등급을 산출합니다.

```bash
bq_run_sql queries/product/gpm-analysis.sql "2026-03-01" "2026-03-20"
```

**파라미터:**
- `$1` — 시작일 (DATE, 필수)
- `$2` — 종료일 (DATE, 필수)

**등급:** 고수익 / 보통 / 저수익 / 적자위험

#### price-competitiveness.sql

카테고리 평균 대비 가격 포지션, 백분위, 경쟁력을 판정합니다.

```bash
bq_run_sql queries/product/price-competitiveness.sql "2026-03-01" "2026-03-20"
```

**파라미터:**
- `$1` — 시작일 (DATE, 필수)
- `$2` — 종료일 (DATE, 필수)

---

## 리포트 스크립트

### daily-sales-report.sh

일간 매출 리포트를 생성하여 Google Sheets에 업데이트합니다.

```bash
# 오늘 날짜 기준
bash reports/scripts/daily-sales-report.sh

# 특정 날짜 지정
bash reports/scripts/daily-sales-report.sh "2026-03-15"
```

**인자:** `$1` — 날짜 (선택, 기본값: 오늘)
**필수 환경변수:** `GWS_REPORT_SPREADSHEET_ID`

**Sheets 탭 구성:**
- `일간매출!A2`: 채널별/카테고리별 매출 요약
- `베스트셀러!A2`: 당일 TOP 10 상품

### weekly-inventory-alert.sh

주간 재고 위험 알림을 콘솔에 출력합니다.

```bash
bash reports/scripts/weekly-inventory-alert.sh
```

**인자:** 없음

**출력 항목:**
- 긴급(7일 미만) / 주의(14일 미만) SKU 수
- 로켓배송 즉시 입고 필요 SKU 수
- 긴급 SKU 목록 (sku, 상품명, 잔여일)

### monthly-business-report.sh

월간 비즈니스 종합 리포트를 Google Sheets 멀티탭으로 생성합니다.

```bash
# 이번 달 기본
bash reports/scripts/monthly-business-report.sh

# 특정 월, 목표 금액 지정
bash reports/scripts/monthly-business-report.sh "2026-03" 800000000
```

**인자:**
- `$1` — 대상 월 (선택, 기본값: 이번 달, 형식: YYYY-MM)
- `$2` — 매출 목표 금액 (선택, 기본값: 500000000)

**필수 환경변수:** `GWS_REPORT_SPREADSHEET_ID`

**Sheets 탭 구성:**
- `매출요약`: 전년 동월 대비 + 목표 달성률 + YTD
- `베스트셀러`: TOP 20 상품
- `재고현황`: 전 SKU 재고 + 긴급/주의 집계
- `광고성과`: 캠페인별 ROAS
- `요약`: 대시보드 (핵심 지표 모음)

### ad-roas-report.sh

광고 ROAS 리포트를 Google Sheets 멀티탭으로 업데이트합니다.

```bash
# 최근 7일 기본
bash reports/scripts/ad-roas-report.sh

# 기간 지정
bash reports/scripts/ad-roas-report.sh "2026-03-20" "2026-03-01"
```

**인자:**
- `$1` — 종료일 (선택, 기본값: 오늘)
- `$2` — 시작일 (선택, 기본값: 종료일 7일 전)

**필수 환경변수:** `GWS_REPORT_SPREADSHEET_ID`

**Sheets 탭 구성:**
- `캠페인ROAS`: 캠페인별 ROAS + 적자 캠페인 콘솔 출력
- `적자캠페인`: ROAS < 1 캠페인 목록
- `광고효율추이`: 일별 CPC/CPM/CPA/CVR
- `키워드성과`: 키워드별 성과 + 중단 검토 대상
- `주간추이`: 최근 28일 주간 집계

---

## SQL 검증 스크립트

모든 SQL 파일의 구조와 문법을 검증합니다.

```bash
# 직접 실행
bash scripts/validate-queries.sh

# Makefile 경유
make validate
```

**검증 항목:**
1. 필수 주석 헤더 (`-- 파일명`, 설명, `@param_count`, `@example`)
2. 파라미터 일관성 (`@param_count`와 실제 `@param` 선언 수 일치 여부)
3. `bq dry_run` 문법 검증 (더미값 치환 후 실행)

---

## Makefile 타겟

```bash
make help        # 사용법 출력
make install     # 의존성 확인 (bq, gws, jq, shellcheck, bats)
make lint        # shellcheck 정적 분석
make test        # bats 단위 테스트
make validate    # SQL 파일 구조/문법 검증
```
