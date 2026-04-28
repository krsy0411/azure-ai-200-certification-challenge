---
name: phase-start
description: AI-200 챌린지의 Phase N 진입을 워크플로우대로 시작. 단계 1 (학습 경로 정독 — phase-learning-fetcher subagent 호출) + 단계 2 (결정 옵션 사용자 제시·승인 대기) 까지 책임. 사용자가 명시적으로 /phase-start <N> 또는 "phase N 시작" 으로 호출하지 않으면 절대 자동 invoke 금지.
disable-model-invocation: true
---

# /phase-start — Phase N 진입 (단계 1 + 2)

CLAUDE.md §1, §2, §6 룰 + 7단계 워크플로우의 **앞 두 단계** 를 책임진다. 다음 흐름을 *순서대로* 진행:

## Step 1 — 사전 점검

- 사용자 메시지에서 Phase 번호 N 추출 (인자 또는 본문). 누락 시 사용자에게 짧게 묻고 중단.
- `docs/history.md` 를 Read — 현재 위치 / 지난 Phase 결정 / 미해결 항목 복원.
- N-1 phase 의 산출물 (`docs/learning-paths/0(N-1)-*.md`) 의 "다음 phase 로 이관" 메모 확인.
- N phase 의 자원이 *이전 phase 의 자원* 을 `existing` 참조한다면, **CLAUDE.md §7 의 "다음 Phase 진입 시 재배포"** 패턴이 필요한지 한 줄로 사용자에게 알림. (예: Phase 5 → 6 진입 시 cosmos/aoai/pg 가 살아 있어야 하는지 등)

## Step 2 — 학습 경로 정독 (단계 1)

`phase-learning-fetcher` subagent 를 invoke 해 정독을 위임.

```
Agent({
  subagent_type: "phase-learning-fetcher",
  description: "Phase <N> 학습 경로 정독",
  prompt: "Phase <N> 의 학습 경로를 정독하고 정해진 출력 형식 (모듈/단원 표 + 핵심 결정 포인트 + 연습 시나리오 + 본 레포 적용 검토) 으로 돌려주세요."
})
```

main 컨텍스트는 압축 결과만 받음. 받은 결과를 사용자에게 그대로 보여줌 (모듈/단원 표 포함).

## Step 3 — 결정 옵션 제시 (단계 2)

학습 경로 정독 결과 + 본 레포 컨텍스트 (CLAUDE.md, 이전 phase 산출물) 를 바탕으로 **이 phase 에서 사용자가 결정해야 할 포인트** 를 옵션 표로 제시.

표 형식:

```
| 결정 | 옵션 A (추천) | 옵션 B | 옵션 C |
|---|---|---|---|
| 1. <SKU 선택> | <...> | <...> | (없으면 빈 칸) |
| 2. <인증 모드> | <...> | <...> | |
| 3. <인덱스 / 파티션 전략> | <...> | <...> | |
| ... | | | |
```

각 옵션에는 **비용 / 학습 커버리지 / 다른 phase 와의 정합성** 트레이드오프를 한 줄로 적음.

추천안 (보통 A) 의 근거를 옵션 표 아래에 1-2 문장.

## Step 4 — 사용자 승인 대기 (단계 2 종료 조건)

표 제시 후 명시적으로 **사용자 응답 대기**. 다음 중 하나가 올 때까지 코드/Bicep 작성을 *시작하지 않음*:

- "추천대로 가자" / "A 로 가자" / "A + B + C 조합으로" 같은 명확한 승인
- 결정별 다른 옵션 선택 명시
- 추가 질문 / 추가 조사 요청

**금지 행동** (CLAUDE.md §1, §6 강화):

- 사용자 승인 전에 `Edit` / `Write` 로 `infra/phases/0N-*` 또는 새 코드 파일 작성
- 사용자가 "검토만" 요청한 단계에서 배포 명령 (`az deployment create` 등) 실행

## Step 5 — 승인 후 Phase plan 기록

사용자 승인을 받으면:

1. `docs/learning-paths/0N-*.md` 신규 작성 (없으면) — 학습 경로 / MS Learn 커버리지 / 결정 / 아키텍처 / 배포 명령 / 검증 시나리오 / 함정·교훈 / 정리 절. 측정 표·함정·교훈은 *placeholder TBD* 로 두고 검증 후 채움.
2. `docs/history.md` 의 "다음 액션" 을 Phase N 진입 후 step (구현 / 검증 / 정리) 로 갱신 — 단, **사용자가 "히스토리 갱신" 명시 요청한 경우만** (CLAUDE.md §9).

이 시점에 단계 3 (구현) 진입 가능. 구현은 main agent 가 자유롭게 — Skill 외부.

## 출력 톤

한국어. CLAUDE.md §4. 단계 헤더로 진행 상황 명확히 (`### Step 2 — 학습 경로 정독 결과` 등). 결정 옵션은 *표 형식* 강제. 결정 추천 근거는 짧고 명확하게.
