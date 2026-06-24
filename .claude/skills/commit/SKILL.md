---
name: commit
description: 현재 작업 트리의 모든 변경 사항을 의미 단위로 묶어 여러 commit 으로 분할 생성. 본 레포의 commit 컨벤션 (`<type>(<scope>): <한국어 메시지>`) 강제. CLAUDE.md "커밋 규칙" 의 자동 강제 도구. 사용자가 명시적으로 /commit 또는 "커밋해" 로 호출하지 않으면 절대 자동 invoke 금지.
disable-model-invocation: true
---

# /commit — 변경 사항을 의미 단위로 분할 commit

CLAUDE.md "커밋 규칙" 의 자동 강제. 사용자가 push 시점을 결정하므로 본 Skill 은 **commit 만** 만들고 push 는 절대 X.

## 사전 조건

- 사용자 메시지에 "커밋해" / "/commit" / "commit" 같은 명시 요청
- `git status` 결과가 비어있으면 즉시 "변경 사항 없음" 보고 후 종료
- 사용자가 *특정 묶음만* 커밋 요청 (예: "docs 만 커밋해") 했으면 그 묶음만 처리

## 절대 룰 (사용자 요구)

1. **모든 변경 파일을 커밋** — `git status` 의 staged + unstaged + untracked 전부 대상. 누락 X.
2. **의미 단위 묶음 분할 commit** — 한 번에 모든 파일을 commit 하지 않는다. 비슷한 내용을 다루는 파일끼리 묶어 *여러* commit 생성.
3. **commit convention 준수** — `<type>(<scope>): <메시지>` 형식. 예: `feat(session-03): Azure Managed Redis + 시맨틱 캐시 + chat.py RAG 화`
4. **메시지 본문은 한국어** — 접두사 (`feat`, `fix`, `docs`, `chore`, `refactor` 등) 와 scope (`session-N`, `rules`, `hooks` 등) 만 영문, 콜론 뒤 본문은 한국어로 작성.

## Step 1 — 변경 현황 파악

다음 명령을 *병렬* 로 실행해 전체 그림 확보:

```bash
git status
git diff --stat
git diff --cached --stat
git log --oneline -10   # 최근 commit 컨벤션 확인 (scope · 표현 일관성 위해)
```

각 파일이 어떤 영역에 속하는지 분류표 작성 (다음 Step 의 묶음 규칙 적용).

## Step 2 — 의미 단위 묶음 분류 규칙

본 레포 구조 기반 묶음 우선순위 (위 → 아래 순으로 적용):

| 우선순위 | 묶음 키 | 대상 파일 패턴 | type / scope 예시 |
|---|---|---|---|
| 1 | **session-specific 산출물 (IaC)** | `infra/modules/<session 자원>-*.bicep`, `infra/sessions/0N-*/main.bicep`, `infra/sessions/0N-*/main.bicepparam` | `feat(session-N): ...` 또는 `feat(infra,session-N): ...` |
| 2 | **session-specific 산출물 (앱 코드)** | `apps/api/src/**/*.py`, `apps/api/pyproject.toml` (session N 의존성 추가), `apps/web/...` | `feat(session-N): ...` |
| 3 | **session 문서** | `docs/sessions/0N-*.md` | `docs(session-N): ...` |
| 4 | **함정 fix (session 진행 중 발견)** | 이미 commit 된 session 코드에 대한 hotfix | `fix(session-N): ...` |
| 5 | **레포 룰 / 워크플로우** | `CLAUDE.md`, `.claude/skills/**`, `.claude/agents/**`, `.claude/hooks/**`, `.claude/settings*.json` | `docs(rules): ...`, `feat(workflow): ...`, `feat(hooks): ...` |
| 6 | **아키텍처 / 공통 docs** | `docs/architecture.md`, `docs/cleanup.md`, `README.md` 등 | `docs(arch): ...`, `docs: ...` |
| 7 | **CI / 빌드 설정** | `.github/workflows/**`, `Dockerfile`, `uv.lock` (단독 변경 시) | `chore(ci): ...`, `chore(build): ...` |
| 8 | **그 외 잡다한 변경** | 위에 안 잡힌 것 | `chore: ...` (scope 없어도 OK) |

**같은 묶음 안에서도 더 쪼개야 할 때**:
- 한 session 에 *기능 추가 (feat)* + *함정 fix (fix)* 가 섞이면 → type 별로 분할
- IaC + 앱 코드가 동시에 한 session 에서 변경됐고 양이 크면 → `infra,session-N` / `session-N` 으로 분할 (예: session-02 의 `feat(session-02): PG ...` 와 `feat(session-02): api 0.5.1 ...` 가 분리된 패턴 참고)
- 단, *너무* 잘게 쪼개지 X — 같은 작업의 자연스러운 단위는 묶는다 (예: Bicep 모듈 3개 + main.bicep + bicepparam 은 한 commit)

**uv.lock**: 의존성을 추가한 commit 과 *같이* 묶는다 (단독 commit 금지 — 어떤 의존성 변경 때문인지 추적 불가).

## Step 3 — 묶음 계획 표 + 사용자 confirm

분류 결과를 사용자에게 **표 형식** 으로 제시:

```
| # | type(scope) | 메시지 (안) | 포함 파일 |
|---|---|---|---|
| 1 | feat(session-03) | Azure Managed Redis + 시맨틱 캐시 + chat.py RAG 화 | infra/modules/redis-*.bicep, infra/sessions/03-*/, apps/api/src/cache/, apps/api/src/messaging/, apps/api/src/routers/chat.py, apps/api/src/main.py, apps/api/pyproject.toml |
| 2 | docs(session-03) | 학습 경로 정독 + 결정 + 측정 + 함정 5개 정식 기록 | docs/sessions/03-redis-cache.md |
| 3 | feat(commit-skill) | /commit Skill — 변경 사항을 의미 단위로 분할 commit | .claude/skills/commit/SKILL.md |
| 4 | docs(rules) | session 워크플로우 룰 갱신 | CLAUDE.md, .claude/skills/** |
```

확인 요청: **"위 묶음대로 4개 commit 을 만들면 됩니까?"**

사용자 응답:
- "응" / "진행해" → Step 4
- "1번 메시지를 ... 로 바꿔줘" / "1·2 합쳐줘" → 조정 후 다시 confirm
- "취소" → 종료

## Step 4 — 묶음별 순차 commit 생성

각 묶음을 별도 commit 으로 생성. 파일 staging 은 `git add <명시 파일>` (절대 `git add .` / `git add -A` 금지 — secret 파일 우발 staging 방지).

명령 패턴 (각 묶음마다 반복):

```bash
git add <묶음 1 의 파일 목록 명시>
git commit -m "$(cat <<'EOF'
<type>(<scope>): <한국어 메시지>

<선택 — 본문 (한국어). 변경의 *why* 중심. 항목 3개 이상이면 bullet 으로>

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

**메시지 작성 원칙**:
- 제목 줄: 50자 이내 권장, 한국어. 마침표 X.
- 본문 (선택): 변경이 단순하면 생략. 함정/결정/구조 변경이 있으면 *why* 를 1-3 줄 한국어로.
- 기존 commit 표현 일관성: `~ + ~`, `~ — ~ 결정`, `~ fix` 같은 본 레포 패턴 따르기.

각 commit 마다 결과 (commit hash + 메시지 제목) 사용자에게 보고:

```
[1/4] 8a3f2c1 feat(session-03): Azure Managed Redis + 시맨틱 캐시 + chat.py RAG 화
```

## Step 5 — 최종 검증

모든 commit 완료 후:

```bash
git status   # working tree clean 확인
git log --oneline -<N>   # 방금 만든 N 개 commit 표시
```

결과 보고 + push 여부 안내:

```
N 개 commit 생성 완료. push 는 사용자가 별도로 결정하세요 (CLAUDE.md 룰).
원격 푸시 원하시면 `git push` 를 직접 실행.
```

## 금지 행동

- `git push` — 절대 X. 본 Skill 은 commit 까지만.
- `git commit --amend` — 사용자가 명시적으로 "amend 해" 요청하지 않은 한 X. 항상 새 commit.
- `git commit --no-verify` — pre-commit hook 우회 X. hook 실패 시 같은 흐름에서 root cause fix.
- `git add .` / `git add -A` — secret 파일 우발 포함 방지. 항상 명시 파일.
- 사용자 confirm 없이 commit 실행 — Step 3 의 confirm 단계 절대 skip X.
- `.env`, `*.key`, `credentials.json` 같은 secret 의심 파일이 변경 목록에 있으면 즉시 사용자에게 경고 + commit 보류.

## 안전 가드

- 변경 목록에 `*.bicepparam` 가 있으면 CLAUDE.md §8 (보안) 점검: `devClientIpAddress`, `userObjectId` 같은 식별 정보가 *실제 값* 으로 들어가 있는지 grep 확인. 들어가 있으면 commit 전 사용자에게 "이 값을 default (`'0.0.0.0'` / `''`) 로 되돌릴까요?" 묻기.
- `git log` 의 최근 commit 의 scope·표현이 사용자 묶음 분류와 다르면 사용자에게 알리고 본 Skill 의 분류 표를 갱신 (레포 컨벤션 우선).

## 출력 톤

한국어. Step 3 의 묶음 계획 표는 명확히 (markdown table). 각 commit 실행 결과는 `[i/N] <hash> <subject>` 한 줄로 간결히. 에러는 즉시 보고 + 사용자가 다음 결정 내릴 수 있게 명령·로그 인용.
