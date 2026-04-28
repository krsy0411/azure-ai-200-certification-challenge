#!/usr/bin/env bash
# PostToolUse hook — Edit/Write 가 *.bicep 파일에 일어났을 때 자동 실행.
# 변경 파일 경로를 stdin JSON 의 .tool_input.file_path 에서 읽어 az bicep build 로 lint.
# 실패 시 exit 2 (블로킹 에러) → stderr 가 main agent 컨텍스트로 피드백.
#
# CLAUDE.md §5 (Bicep IaC 우선) 의 일부로 stale 한 변경이 commit 가기 전에 차단.

set -uo pipefail

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

# 본 hook 은 *.bicep 만 대상. 다른 파일이면 NOOP 통과.
if [[ -z "$FILE" || "$FILE" != *.bicep ]]; then
  exit 0
fi

# 파일이 실제로 있어야 build 가능 (Edit 직후라 보통 있음).
if [[ ! -f "$FILE" ]]; then
  exit 0
fi

# az bicep build — stdout 은 ARM JSON 이라 버리고, 경고/에러는 stderr.
if ! OUTPUT=$(az bicep build -f "$FILE" --stdout 2>&1 > /dev/null); then
  printf 'bicep build FAILED for %s\n%s\n' "$FILE" "$OUTPUT" >&2
  exit 2
fi

# 경고는 stderr 로 가지만 exit 0 — main agent 가 알 수 있게 echo.
if [[ -n "$OUTPUT" ]]; then
  printf 'bicep build OK with warnings for %s:\n%s\n' "$FILE" "$OUTPUT" >&2
fi

exit 0
