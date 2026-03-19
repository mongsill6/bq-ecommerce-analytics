#!/usr/bin/env bash
# weekly-inventory-alert.sh — 주간 재고 알림 리포트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$SCRIPT_DIR/utils/bq-helpers.sh"

echo_header "주간 재고 알림 리포트"

# 1. 전체 재고 현황
echo "📦 재고 현황 조회 중..."
STOCK=$(bq_run_sql "$SCRIPT_DIR/queries/inventory/stock-status.sql")

CRITICAL=$(echo "$STOCK" | jq '[.[] | select(.status | test("긴급"))] | length')
WARNING=$(echo "$STOCK" | jq '[.[] | select(.status | test("주의"))] | length')

echo "  🔴 긴급: ${CRITICAL}개"
echo "  🟡 주의: ${WARNING}개"

# 2. 로켓배송 위험
echo ""
echo "🚀 로켓배송 재고 위험..."
ROCKET=$(bq_run_sql "$SCRIPT_DIR/queries/inventory/rocket-delivery-risk.sql")
ROCKET_CRITICAL=$(echo "$ROCKET" | jq '[.[] | select(.risk_level | test("즉시"))] | length')

echo "  🚨 즉시 입고 필요: ${ROCKET_CRITICAL}개"

# 3. 요약 출력
echo ""
echo "=== 요약 ==="
echo "긴급 발주 필요: $((CRITICAL + ROCKET_CRITICAL))개 SKU"

if [ "$((CRITICAL + ROCKET_CRITICAL))" -gt 0 ]; then
  echo ""
  echo "긴급 상품 목록:"
  echo "$STOCK" | jq -r '.[] | select(.status | test("긴급")) | "  - \(.sku) \(.product_name) (잔여 \(.days_of_stock)일)"'
  echo "$ROCKET" | jq -r '.[] | select(.risk_level | test("즉시")) | "  - [로켓] \(.sku) \(.product_name) (잔여 \(.days_remaining)일)"'
fi
