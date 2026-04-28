#!/usr/bin/env bash
# PostToolUse hook — Edit/Write 가 apps/api/src/**/*.py 에 일어났을 때 자동 실행.
# uv project root (apps/api) 로 cd 후 ruff check + 변경 파일 py_compile.
# 실패 시 exit 2 → stderr 피드백.
#
# Phase 5 세션에서 ruff E501 한 번 놓쳐 빌드 라운드를 한 번 더 돈 적이 있어 자동화.

set -uo pipefail

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE" || "$FILE" != *.py ]]; then
  exit 0
fi

# apps/api/src/ 하위만 대상. (apps/web 은 TS, scripts/ 등은 무관)
case "$FILE" in
  *"apps/api/src/"*) ;;
  *) exit 0 ;;
esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
API_DIR="$PROJECT_DIR/apps/api"

if [[ ! -d "$API_DIR" ]]; then
  printf 'apps/api not found at %s\n' "$API_DIR" >&2
  exit 0
fi

cd "$API_DIR" || exit 0

# 1) ruff check (전체 src/ — 변경 파일이 다른 파일에 영향 줄 수 있음)
if ! RUFF_OUT=$(uv run ruff check src/ 2>&1); then
  printf 'ruff check FAILED:\n%s\n' "$RUFF_OUT" >&2
  exit 2
fi

# 2) py_compile (변경 파일만)
REL=${FILE#"$PROJECT_DIR/apps/api/"}
if ! COMPILE_OUT=$(uv run python -m py_compile "$REL" 2>&1); then
  printf 'py_compile FAILED for %s:\n%s\n' "$REL" "$COMPILE_OUT" >&2
  exit 2
fi

exit 0
