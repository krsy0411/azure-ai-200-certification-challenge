---
name: phase-cleanup
description: AI-200 챌린지의 session 종료 시 자원 정리 (단계 7) 를 책임. CLAUDE.md §7 룰대로 phase-specific 자원만 정리하고 공통 자원은 보존. 사용자가 명시적으로 "정리해" / "삭제해" / "/phase-cleanup" 등을 요청하지 않으면 절대 자동 invoke 금지. block-az-delete.sh hook 의 통과 마커 (.claude/cleanup-approved) 를 이 Skill 만이 만들고 정리 후 삭제.
disable-model-invocation: true
---

# /phase-cleanup — session N 자원 정리 (단계 7)

CLAUDE.md §7 자원 라이프사이클 룰의 자동 강제 도구.

## 사전 조건 — 명시 트리거

이 Skill 은 **사용자 명시 요청** 시에만 진입:

- 사용자 메시지에 "정리해" / "삭제해" / "drop" / "/phase-cleanup" / "리소스 정리" 같은 명확한 요청
- 단순 "괜찮아" / "확인했어" 같은 ack 는 트리거 X — 단계 6 (GUI 검증) 종료 표현일 수 있음

명시 요청 모호하면 사용자에게 짧게 confirm: **"session N 자원을 정리합니다. 다음 자원이 삭제됩니다 (..., ...) — 진행할까요?"**

## Step 1 — 정리 대상 / 보존 자원 분리 (CLAUDE.md §7)

해당 session 의 `infra/sessions/0N-*/main.bicep` 을 Read 해서 이 session 가 *생성한* 자원 목록 추출.

CLAUDE.md §7 의 **보존 / 정리 분류** 적용 (2026-05-18 룰 갱신 — session-04 실측 비용 기반).

### soft-delete / 이름 예약 주의 자원

삭제 후에도 **이름이 일정 기간 예약**되어, 같은 이름으로 재배포 시 충돌하는 자원:

| 자원 종류 | soft-delete 기간 | purge 가능? | 처리 지침 |
|---|---|---|---|
| Key Vault (`enablePurgeProtection: true`) | 7일~ | ❌ purge 불가 (purge protection 이 purge 자체를 차단) | **삭제 금지** — 보존 목록에서 절대 이동 X. 삭제하면 이름이 7일 이상 잠겨 재배포 불가 |
| Azure OpenAI (Cognitive Services) | 48시간 | ✅ `az cognitiveservices account purge` | 삭제 직후 즉시 purge — 이름 즉시 해제. purge 없이 두면 48시간 동안 같은 이름 재배포 불가 |
| App Configuration (`disableLocalAuth: true`) | ~12분 | ✅ `az appconfig purge` | KV 와 달리 purge protection 이 없어 purge 가능. 삭제만 하면 이름이 ~12분 예약돼 같은 이름(`uniqueString` 고정 시드) 재배포가 `NameUnavailable` 로 충돌. **삭제 직후 즉시 `az appconfig purge` 로 이름 회수** (AOAI 와 동일 패턴). 실측: clean 재검증 시 이 ~12분 대기를 겪음 |
| Log Analytics Workspace | 14일 (데이터만) | ✅ 삭제 시 `--force` 플래그 | `--force` 없이 삭제하면 데이터가 14일 보존(복구 가능). `--force` 추가 시 즉시 완전 삭제 |

나머지 (Cosmos DB, PostgreSQL, Managed Redis, ACA Container Apps, ACA Environment, ACR, 공용 UAMI 등): soft-delete 없음, 삭제 즉시 이름 해제. Cosmos DB 는 soft-delete 는 없지만 백엔드 정리에 수 분 걸리므로 같은 이름 즉시 재배포 시 실패할 수 있습니다 (`az cosmosdb show` 가 NotFound 될 때까지 대기).

### 보존 (무료 또는 사실상 무료)

- **ACR Basic** (`acrai200wsdev*`) — storage 만 ~260 KRW/일, 이미지 학습 자산
- **Log Analytics** (`law-...`) — 5GB/월 free
- **공용 UAMI** (`id-...-aca-*`, `id-...-aks-*`) — 무료
- **ACA Environment** (`cae-...`) — Container App 이 살아있을 때만 과금, 자체 무료
- **Application Insights** (`ai-...`) — workspace-based, ingest 만 과금
- **Key Vault** (`kv-...`, session-00·01 부터) — sub-원 단위. **전체 teardown 에서도 절대 삭제 X** (purge protection + 고정 시드 이름 → 7일 잠김). KV 만이 무조건 보존.

### 정리 (compute 또는 유의미한 idle 비용 발생)

- **Cosmos DB** (`cosmos-...`)
- **Azure OpenAI** (`aoai-...`) → soft-delete 후 `purge` 까지 (같은 이름 재배포 위해)
- **App Configuration** (`ac-...`, session-05) → 비용은 sub-원 단위지만 **soft-delete 이름 예약(~12분)** 이 있어, 삭제 후 같은 이름 재배포 시 `NameUnavailable` 로 충돌한다. `disableLocalAuth` store 라 깨끗한 재배포가 필요할 때가 많으므로, 삭제할 때는 **AOAI 와 동일하게 `delete` 직후 `az appconfig purge` 로 이름을 즉시 회수**한다. KV 와 달리 purge 가능하므로 전체 teardown 시 KV 만 남기고 App Config 는 정리 대상(§7 — "전체 정리 시에도 KV 만 남기고 나머지를 지운다")
- **PostgreSQL Flexible Server** (`pg-...`) — Burstable 도 ~700 KRW/일
- **Managed Redis** (`redis-...`) — 현재 SKU `Balanced_B0` (list price ~$13/월). compute idle 비용 발생 (과거 Memory_M10 측정 시 ~11,680 KRW/일 이었으나 SKU 변경으로 대폭 하락)
- **Service Bus** (`sb-...`)
- **Event Grid 토픽** (`egt-...`)
- **Function App** (`func-...`) + Flex Consumption plan (`asp-func-...`)
- **Storage 계정** (`st-...`)
- **ACA api/web Container App** (`ca-...-api-dev`, `ca-...-web-dev`) — min replica 1 = ~1,743 KRW/일. session 단위 정리, 다음 session 진입 시 image tag 와 함께 재배포
- **AKS 클러스터** (`aks-...`) + **자동 생성된 `MC_..._aks-..._koreacentral` RG** — LB+IP idle ~1,125 KRW/일. session-07 학습 완료 후 정리. (향후) CI/포트폴리오 세션에서 단순 manifest 시연 필요하면 재배포
- **Container Insights MSCI/DCR** — AKS 와 cascade

### 분류 결정 (이전 룰과의 차이)

이전 룰 (2026-05-18 이전) 은 ACA api/web 과 AKS 도 *공통 자원* 으로 보존했다. session-04 실측 비용 (7일 108,569 KRW, 총비용의 18% 가 ACA+AKS idle) 으로 **compute 가 있는 자원은 모두 정리** 룰로 갱신. 보존 = *무료 또는 storage-only* 만.

### 분류 결과 표시

```
| 자원 | 종류 | 처리 |
|---|---|---|
| pg-ai200ws-dev05 | PostgreSQL Flexible | 삭제 |
| cosmos-ai200ws-dev04 | Cosmos DB | 삭제 |
| aoai-ai200ws-dev04 | Azure OpenAI | 삭제 + purge (soft-delete 회피) |
| ca-ai200ws-api-dev | ACA api | **보존** (image tag 갱신은 다음 phase) |
| acrai200wsdev04 | ACR | **보존** (공통) |
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
az appconfig delete --name <ac-name> -g rg-... --yes &   # 전체 teardown 시만 (App Config 정리 대상일 때)
wait
```

각 삭제 진행 상황을 사용자에게 보고. 모두 끝나면 **soft-delete 이름 예약이 있는 자원은 즉시 purge** 한다 (AOAI 48시간 · App Config ~12분 — purge 없이 두면 같은 이름 재배포가 충돌):

```bash
az cognitiveservices account purge --name <aoai-name> -g rg-... --location <region>
az appconfig purge --name <ac-name> --location <region> --yes   # App Config 를 삭제한 경우만
```

> App Configuration 의 `az appconfig delete`/`purge` 도 `az ... delete` 가드(block-az-delete.sh)·마커 흐름 안에서 실행된다. `purge` 는 삭제와 별개 명령이지만 같은 정리 흐름의 일부다.

## Step 4 — 결과 검증 + 마커 삭제

```bash
az resource list -g rg-ai200ws-dev --query "[].{name:name, type:type}" -o table
```

기대 결과: 보존 자원만 남고 정리 대상은 모두 사라짐. 누락 / 실패 시 즉시 사용자에게 보고.

확인 후 마커 파일 삭제:

```bash
rm -f .claude/cleanup-approved
```

(이 마커는 단일 cleanup 흐름에 한해 유효. 다음 정리 시 다시 /phase-cleanup 호출 필요.)

## Step 5 — 문서 갱신 안내

`docs/sessions/0N-*.md` 의 "정리 (session N+1 진입 직전)" 절이 실제 명령과 일치하는지 확인. 다르면 갱신 제안.

정리 결과(잔여 자원)는 Claude Code 프로젝트 메모리에 남겨 다음 대화에서 복원되게 한다 — 별도 `docs/history.md` 는 두지 않는다 (CLAUDE.md §9).

## Step 6 — 단계 7 종료 + 다음 session 안내

```
session N 자원 정리 완료. 다음은 session N+1 (<학습 경로 이름>). 진입 시 /phase-start <N+1> 로 시작하세요.
```

## 안전 가드

- 마커 파일 (`.claude/cleanup-approved`) 은 *이 Skill 만* 만든다. 사용자가 직접 만들 일은 없음 (그러면 hook 우회 가능). 만약 이미 있다면 *왜 있는지* 확인하고 의심스러우면 사용자에게 묻고 진행 보류.
- 보존 자원 (ACR / LAW / UAMI / CAE / AI / KV — *무료 또는 사실상 무료* 만) 이 정리 대상으로 분류되면 즉시 중단 + 사용자에게 보고. 절대 자동 진행 X. **단 App Configuration (`ac-...`) 은 보존이 아니라 정리 대상** — soft-delete 이름 예약 때문에 삭제 시 `az appconfig purge` 까지 동반한다 (위 soft-delete 표·정리 목록 참고). KV 만이 무조건 보존(절대 삭제 X).
- **UAMI (`id-...`) 는 삭제하지 않는다** — 모든 session 이 공유하는 신원이라, 삭제하면 oid 가 바뀌어 전 session 의 역할 할당·federated credential·DB Entra admin 이 끊긴다 (무료이기도 함). 보존 목록 고정.
- `az group delete` / `rg-ai200ws-dev` 자체 삭제는 절대 X. 본 Skill 의 어떤 흐름에도 RG 삭제 명령 없음.

## 출력 톤

한국어. 단계별 진행 상황 명확히. 삭제 명령 실행 전 *반드시* 자원 분류 표 + confirm. 진행 중 에러는 같은 흐름에서 보고하되 사용자가 다음 결정을 내릴 수 있게 명령·로그 인용.
