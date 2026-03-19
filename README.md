# bq-ecommerce-analytics

BigQuery 기반 이커머스 데이터 분석 쿼리 & 자동 리포트 파이프라인

## 구조

```
queries/
├── sales/          # 매출 분석
├── inventory/      # 재고 관리/예측
├── advertising/    # 광고 성과 (ROAS)
└── product/        # 상품 분석
reports/
├── templates/      # Sheets 리포트 템플릿
└── scripts/        # 리포트 생성 자동화
utils/
└── bq-helpers.sh   # BQ 공통 유틸리티
```

## 쿼리 목록

### 매출 분석 (`queries/sales/`)
- `daily-sales-summary.sql` — 일간 매출 요약 (채널별/카테고리별)
- `weekly-trend.sql` — 주간 매출 트렌드
- `monthly-comparison.sql` — 월간 전년 대비 비교
- `top-sellers.sql` — 베스트셀러 TOP N

### 재고 관리 (`queries/inventory/`)
- `stock-status.sql` — 현재 재고 현황
- `depletion-forecast.sql` — 재고 소진 예측 (이동평균)
- `reorder-alert.sql` — 발주 필요 상품 알림
- `rocket-delivery-risk.sql` — 로켓배송 재고 위험 감지

### 광고 성과 (`queries/advertising/`)
- `roas-by-campaign.sql` — 캠페인별 ROAS
- `ad-spend-efficiency.sql` — 광고비 효율 분석
- `keyword-performance.sql` — 키워드별 성과

### 상품 분석 (`queries/product/`)
- `gpm-analysis.sql` — 상품별 GPM(매출총이익률)
- `price-competitiveness.sql` — 가격 경쟁력 분석
- `review-sentiment.sql` — 리뷰 감성 분석 요약

## 리포트 자동화

```bash
# 일간 매출 리포트 → Google Sheets 업데이트
./reports/scripts/daily-sales-report.sh

# 주간 재고 알림 리포트
./reports/scripts/weekly-inventory-alert.sh
```

## 사전 요구사항

- `bq` CLI (Google Cloud SDK)
- `gws` CLI (Sheets 연동용)
- 서비스 계정 인증 완료
- jq, bash 4.0+

## 설정

```bash
cp .env.example .env
# .env에 프로젝트 ID, 데이터셋명 설정
```

## License

MIT
