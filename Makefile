.PHONY: help install lint test validate

SHELL_FILES := $(shell find reports/ utils/ scripts/ -name '*.sh' -type f 2>/dev/null)
SQL_FILES   := $(shell find queries/ -name '*.sql' -type f)
TEST_FILES  := $(wildcard tests/*.bats)

help: ## 사용법 출력
	@echo "bq-ecommerce-analytics — BigQuery 이커머스 분석 도구 모음"
	@echo ""
	@echo "타겟:"
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "예시:"
	@echo "  make install   # 필수 도구 설치 확인"
	@echo "  make lint      # shellcheck으로 모든 .sh 파일 검사"
	@echo "  make test      # bats 단위 테스트 실행"
	@echo "  make validate  # SQL 파일 검증 (문법/주석/파라미터)"

install: ## 필수 도구 설치 여부 확인 (bq, gws, jq, shellcheck)
	@echo "[INSTALL] 의존성 확인 중..."
	@ok=true; \
	for cmd in bq gws jq shellcheck; do \
		if command -v $$cmd >/dev/null 2>&1; then \
			printf "  %-12s ✅ %s\n" "$$cmd" "$$(command -v $$cmd)"; \
		else \
			printf "  %-12s ❌ 미설치\n" "$$cmd"; \
			ok=false; \
		fi; \
	done; \
	for cmd in bats; do \
		if command -v $$cmd >/dev/null 2>&1; then \
			printf "  %-12s ✅ %s (선택)\n" "$$cmd" "$$(command -v $$cmd)"; \
		else \
			printf "  %-12s ⚠️  미설치 (make test 시 필요)\n" "$$cmd"; \
		fi; \
	done; \
	if [ "$$ok" = false ]; then \
		echo ""; \
		echo "[INSTALL] ❌ 필수 도구가 누락되었습니다."; \
		exit 1; \
	fi; \
	echo "[INSTALL] ✅ 모든 필수 도구 확인 완료"

lint: ## shellcheck으로 모든 셸 스크립트 정적 분석
	@echo "[LINT] shellcheck 실행 중..."
	@shellcheck -x -S warning -e SC1091 $(SHELL_FILES)
	@echo "[LINT] 완료 — 문제 없음"

test: ## bats 단위 테스트 실행
	@echo "[TEST] bats 테스트 실행 중..."
	@bats tests/
	@echo "[TEST] 완료"

validate: ## SQL 파일 검증 (bq dry_run + 주석/파라미터 체크)
	@echo "[VALIDATE] SQL 검증 시작..."
	@bash scripts/validate-queries.sh
	@echo "[VALIDATE] 완료"
