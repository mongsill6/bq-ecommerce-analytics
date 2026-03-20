# cp_reviewer_funding

- **데이터셋**: `inspiring-bonus-484905-v9.coupang`
- **유형**: TABLE
- **행 수**: 4
- **크기**: 192 B
- **생성일**: 2026-02-09 18:20:37
- **수정일**: 2026-02-09 18:20:43
- **컬럼 수**: 6

## 스키마

| 컬럼명 | 타입 | 설명 |
|--------|------|------|
| `date` | `DATE` `REQUIRED` | 비용 기준일 (해당 월 마지막 일자) |
| `sku_id` | `INTEGER` `REQUIRED` | SKU ID |
| `quantity` | `INTEGER` | 진행 수량 |
| `funding_cost` | `INTEGER` | 체험단 참여 비용 (수량 × 125,000) |
| `sample_supply_cost` | `INTEGER` | 샘플 공급 비용 (공급가 × 수량) |
| `total_cost` | `INTEGER` | 총 비용 |

---
*자동 생성: 2026-03-20 09:15:48 by bq-schema-doc.sh*
