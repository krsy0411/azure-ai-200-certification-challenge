#!/usr/bin/env bash
# PreToolUse hook — Bash 가 az ... delete 패턴 명령을 실행하려고 할 때 차단/허용 결정.
# CLAUDE.md §7 (자원 라이프사이클) 의 자동 강제 — 사용자 명시 정리 요청 마커가 있을 때만 통과.
#
# 마커 파일: .claude/cleanup-approved
# /phase-cleanup 슬래시 커맨드가 사용자 confirm 후 마커 생성, 정리 끝나면 자동 삭제.
#
# 응답 JSON 의 hookSpecificOutput.permissionDecision 으로 deny/allow 결정.

set -uo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

# az delete 류 패턴이 아니면 NOOP 통과 (allow).
# - az resource delete / az group delete
# - az postgres flexible-server delete
# - az cosmosdb delete
# - az cognitiveservices account delete
# - az containerapp delete
# - az redis delete
# - 기타 az 의 delete 서브커맨드
if ! printf '%s' "$COMMAND" | grep -Eq '^[[:space:]]*az[[:space:]]+([a-z-]+[[:space:]]+){1,5}delete([[:space:]]|$)'; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
MARKER="$PROJECT_DIR/.claude/cleanup-approved"

if [[ ! -f "$MARKER" ]]; then
  jq -n --arg cmd "$COMMAND" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("CLAUDE.md §7 — 자원 정리는 사용자 명시 요청 후에만. 차단된 명령: \($cmd | .[0:80])\n\n사용자가 \"정리해\" / \"삭제해\" 등을 명시 요청하면 /phase-cleanup 슬래시 커맨드를 실행하거나, 직접 마커 파일을 만들어 통과시키세요:\n  touch .claude/cleanup-approved\n마커는 정리 1회 후 자동 삭제됩니다.")
    }
  }'
  exit 0
fi

# 마커 있으면 1회 통과 후 삭제 (single-use). 같은 세션에서 여러 자원 정리하려면 /phase-cleanup 이 한 번에 실행.
# 단, 한 정리 흐름에 az delete 가 여러 번 필요할 수 있어 마커 즉시 삭제는 너무 빠름.
# 대안: 마커 파일에 timestamp/expires 정보를 두고 일정 시간 (예: 30분) 동안 통과.
# 여기서는 단순화 — 마커가 있으면 통과, 삭제는 /phase-cleanup 마지막 단계에서.
exit 0
