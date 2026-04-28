---
name: phase-cleanup
description: AI-200 챌린지의 Phase 종료 시 자원 정리 (단계 7) 를 책임. CLAUDE.md §7 룰대로 phase-specific 자원만 정리하고 공통 자원은 보존. 사용자가 명시적으로 "정리해" / "삭제해" / "/phase-cleanup" 등을 요청하지 않으면 절대 자동 invoke 금지. block-az-delete.sh hook 의 통과 마커 (.claude/cleanup-approved) 를 이 Skill 만이 만들고 정리 후 삭제.
disable-model-invocation: true
---

# /phase-cleanup — Phase N 자원 정리 (단계 7)

CLAUDE.md §7 자원 라이프사이클 룰의 자동 강제 도구.

## 사전 조건 — 명시 트리거

이 Skill 은 **사용자 명시 요청** 시에만 진입:

- 사용자 메시지에 "정리해" / "삭제해" / "drop" / "/phase-cleanup" / "리소스 정리" 같은 명확한 요청
- 단순 "괜찮아" / "확인했어" 같은 ack 는 트리거 X — 단계 6 (GUI 검증) 종료 표현일 수 있음

명시 요청 모호하면 사용자에게 짧게 confirm: **"Phase N 자원을 정리합니다. 다음 자원이 삭제됩니다 (..., ...) — 진행할까요?"**

## Step 1 — 정리 대상 / 보존 자원 분리 (CLAUDE.md §7)

해당 Phase 의 `infra/phases/0N-*/main.bicep` 을 Read 해서 이 Phase 가 *생성한* 자원 목록 추출.

CLAUDE.md §7 의 **보존 / 정리 분류** 적용:

### 보존 (절대 정리 X)

- ACR (`acrai200challengedev*`)
- Log Analytics (`law-...`)
- Application Insights (`ai-...`)
- 공용 UAMI (`id-...-aca-*`, `id-...-aks-*`)
- ACA Environment (`cae-...`)
- AKS 클러스터 (`aks-...`) + Container Insights MSCI
- Key Vault / App Configuration (Phase 8 이후)
- ACA api/web Container App (`ca-...-api-dev`, `ca-...-web-dev`) — Phase 단위 갱신은 image tag 만, 컨테이너 자체는 모든 phase 가 사용

### 정리 (Phase-specific 데이터·런타임)

- Cosmos DB (`cosmos-...`)
- Azure OpenAI (`aoai-...`) → soft-delete 후 `purge` 까지 (같은 이름 재배포 위해)
- PostgreSQL Flexible Server (`pg-...`)
- Managed Redis (`redis-...`)
- Service Bus (`sb-...`)
- Event Grid 토픽 (`egt-...`)
- Function App (`func-...`)
- Storage 계정 (`st-...`)
- Phase 1 의 App Service / App Service Plan (`app-...`, `asp-...`)

### 분류 결과 표시

```
| 자원 | 종류 | 처리 |
|---|---|---|
| pg-ai200challenge-dev05 | PostgreSQL Flexible | 삭제 |
| cosmos-ai200challenge-dev04 | Cosmos DB | 삭제 |
| aoai-ai200challenge-dev04 | Azure OpenAI | 삭제 + purge (soft-delete 회피) |
| ca-ai200challenge-api-dev | ACA api | **보존** (image tag 갱신은 다음 phase) |
| acrai200challengedev04 | ACR | **보존** (공통) |
| ... | ... | ... |
```

## Step 2 — 사용자 최종 confirm

위 표를 사용자에게 보여주고 **명시 confirm 대기**. "응 진행해" / "삭제해" 같은 답이 와야만 다음 단계로.

## Step 3 — 마커 파일 생성 + 삭제 명령 실행

block-az-delete.sh hook 의 통과 마커 생성:

```bash
touch .claude/cleanup-approved
```

이후 정리 대상 자원을 병렬 background 로 삭제:

```bash
az postgres flexible-server delete --name <pg-name> -g rg-... --yes &
az cosmosdb delete --name <cosmos-name> -g rg-... --yes &
az cognitiveservices account delete --name <aoai-name> -g rg-... &
wait
```

각 삭제 진행 상황을 사용자에게 보고. 모두 끝나면 AOAI purge 추가 (cognitive services 의 soft-delete 회피):

```bash
az cognitiveservices account purge --name <aoai-name> -g rg-... --location <region>
```

## Step 4 — 결과 검증 + 마커 삭제

```bash
az resource list -g rg-ai200challenge-dev --query "[].{name:name, type:type}" -o table
```

기대 결과: 보존 자원만 남고 정리 대상은 모두 사라짐. 누락 / 실패 시 즉시 사용자에게 보고.

확인 후 마커 파일 삭제:

```bash
rm -f .claude/cleanup-approved
```

(이 마커는 단일 cleanup 흐름에 한해 유효. 다음 정리 시 다시 /phase-cleanup 호출 필요.)

## Step 5 — 문서 갱신 안내

`docs/learning-paths/0N-*.md` 의 "정리 (Phase N+1 진입 직전)" 절이 실제 명령과 일치하는지 확인. 다르면 갱신 제안.

`docs/history.md` 의 "Azure RG 잔여 자원" 섹션이 정리 결과와 일치하는지 — 사용자가 명시적으로 "히스토리 갱신" 요청하지 않은 한 자동 갱신 X (CLAUDE.md §9).

## Step 6 — 단계 7 종료 + 다음 phase 안내

```
Phase N 자원 정리 완료. 다음은 Phase N+1 (<학습 경로 이름>). 진입 시 /phase-start <N+1> 로 시작하세요.
```

## 안전 가드

- 마커 파일 (`.claude/cleanup-approved`) 은 *이 Skill 만* 만든다. 사용자가 직접 만들 일은 없음 (그러면 hook 우회 가능). 만약 이미 있다면 *왜 있는지* 확인하고 의심스러우면 사용자에게 묻고 진행 보류.
- 공통 자원 (ACR / LAW / UAMI / CAE / AKS / KV / AC / ACA api/web) 이 정리 대상으로 분류되면 즉시 중단 + 사용자에게 보고. 절대 자동 진행 X.
- `az group delete` / `rg-ai200challenge-dev` 자체 삭제는 절대 X. 본 Skill 의 어떤 흐름에도 RG 삭제 명령 없음.

## 출력 톤

한국어. 단계별 진행 상황 명확히. 삭제 명령 실행 전 *반드시* 자원 분류 표 + confirm. 진행 중 에러는 같은 흐름에서 보고하되 사용자가 다음 결정을 내릴 수 있게 명령·로그 인용.
