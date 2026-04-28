---
name: phase-verify
description: AI-200 챌린지의 Phase 배포 직후 CLI 검증 (단계 5) 를 책임. 자원 존재 / 권한 구성 / 헬스 체크 / 데이터 적재·검색 라운드트립 / Log Analytics KQL 까지 정해진 시나리오를 순서대로 실행하고 결과를 docs/learning-paths/0N-*.md 의 측정 표 + 함정·교훈 절에 기록. 사용자가 /phase-verify 또는 "검증 시작" 으로 명시 호출하지 않으면 자동 invoke 금지.
disable-model-invocation: true
---

# /phase-verify — Phase N CLI 검증 (단계 5)

배포가 끝난 직후 (`az deployment group create` 성공 후) main agent 가 호출. 단계 6 (사용자 GUI 검증) 진입 전 마지막 자동화 단계.

## 사전 조건

- `docs/history.md` 또는 사용자 메시지에서 **현재 Phase 번호 N** 확인.
- 해당 Phase 의 `infra/phases/0N-*/main.bicep` 이 존재하고 직전 deployment 가 `Succeeded` 인지 확인.

## 검증 시나리오

다음 5개 카테고리를 순서대로. 각 단계 결과는 명확히 표 / 코드 블록으로 기록.

### 1. 자원 존재 / 구성

```bash
az resource list -g rg-ai200challenge-dev \
  --query "[].{name:name, type:type}" -o table
```

기대 자원: `infra/phases/0N-*/main.bicep` 에서 새로 만든 자원이 모두 보여야 함. 누락 / 추가 자원 발견 시 즉시 사용자에게 보고.

Phase-specific 추가 점검 (해당 Phase 모듈에 따라):
- PG: `az postgres flexible-server show ... --query state` = `Ready`, `azure.extensions=VECTOR`
- Cosmos: `az cosmosdb show ... --query enableLocalAuth` = `false`, vector indexing 활성
- AOAI: `az cognitiveservices account deployment list ...` 으로 model deployment 모두 Succeeded
- AKS: `az aks get-credentials ...` 후 `kubectl get nodes`

### 2. 권한 / RBAC

UAMI 기반 인증이 정상인지:
- ACR pull: `az role assignment list --assignee <uami-principalId>` 에 `AcrPull` 있어야
- AOAI: `Cognitive Services OpenAI User` 부여 확인
- Cosmos / PG / Redis 등 Phase 자원의 RBAC 도 같은 방식

CLAUDE.md §8 룰 — 본인 IP / objectId 가 git 안 박혀있는지 grep 로 한 번 더 확인 (`grep -r "<my-ip>" infra/`).

### 3. 컨테이너 / 앱 헬스

```bash
# ACA api revision Healthy 확인
az containerapp revision list -g rg-ai200challenge-dev \
  -n ca-ai200challenge-api-dev \
  --query "[?properties.active==\`true\`].{name:name, image:properties.template.containers[0].image, healthState:properties.healthState}" \
  -o table

# /healthz (ingress 임시 external 토글 후, 끝나면 internal 회수)
az containerapp ingress update -g rg-ai200challenge-dev -n ca-ai200challenge-api-dev --type external
API=$(az containerapp show ... --query properties.configuration.ingress.fqdn -o tsv)
curl -fsS "https://$API/healthz"
# ... 검증 후
az containerapp ingress update ... --type internal
```

ingress 토글은 *검증 흐름의 일부* 라 CLAUDE.md §7 의 임시 권한 회수 예외에 해당 — 같은 흐름에서 회수.

### 4. 데이터 라운드트립 (해당 Phase 의 핵심 라우터)

Phase 별로 검증 시나리오가 다름. main agent 는 phase-specific 시나리오를 만들어 실행:

- Phase 4: `/api/index?store=cosmos` → `/api/search?store=cosmos`
- Phase 5: `/api/index?store=pg` + `/api/search?store=pg&index_kind=hnsw|ivf` 비교
- Phase 6: 시맨틱 캐시 hit/miss + chat RAG
- Phase 7: 변경 피드 트리거 → 자동 임베딩
- Phase 8: 시크릿이 KV 에서 로드되는지
- Phase 9: 트레이스가 App Insights 에 도달하는지

샘플 chunk / 쿼리 셋은 5-건 정도로 작게 (학습 트래픽).

### 5. Log Analytics KQL (Phase 9 이후 핵심)

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-ai200challenge-api-dev"
| where TimeGenerated > ago(15m)
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
| take 50
```

부트스트랩 / 호출 / 에러 패턴 확인. Phase-specific 함정 (예: chicken-and-egg, 권한 거부) 이 로그에 보이면 함정·교훈 절에 추가.

## 결과 기록

검증 끝나면 `docs/learning-paths/0N-*.md` 의 다음 절을 채움:

1. **"Cosmos vs PG 비교 측정"** (또는 phase 별 측정 표) — 실측 수치로 *_TBD_* 교체
2. **"함정 · 교훈"** — 검증 중 발견한 새 함정 추가 (자세한 본문, 재현 명령, 해결책)
3. **"MS Learn 경로 커버리지"** 표의 "사용 / 부분 사용 / 생략" 컬럼 — 실제 검증 결과로 갱신

## 임시 권한 회수 (검증 종료 단계)

CLAUDE.md §7 의 *임시 권한 회수는 정리 룰의 예외*. 검증 흐름의 일부로 부여한 것은 같은 흐름에서 회수:

- 본인 objectId 임시 admin (PG / Cosmos) — 검증 종료 시 즉시 delete
- ACA api ingress external — internal 로 복귀

자원 자체 (PG / Cosmos / AOAI 등) 는 *건드리지 않음* — 그건 단계 7 (`/phase-cleanup`) 의 책임.

## 단계 6 (사용자 GUI 검증) 진입 안내

검증 결과 보고 마지막에 다음 메시지를 사용자에게:

> **단계 5 CLI 검증 완료.** 단계 6 GUI 검증은 사용자 본인이 Portal·브라우저·외부 도구로 추가 검증. 끝나면 "GUI 검증 끝" / "정리해" 라고 알려주세요. 그 전까지 자원 정리 명령 (`az ... delete`) 은 hook 차단됨.

## 출력 톤

한국어. CLAUDE.md §4. 검증 5개 카테고리 결과를 표 / 체크박스로 명확히. 누락 / 실패는 즉시 빨간 깃발로 표시 (이모지 X — CLAUDE.md 안내 따라).
