# Phase 7 — AI 솔루션을 위한 백 엔드 서비스 통합

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/integrate-backend-services-ai-solutions/ (3 모듈 × 25 단원)

> Phase 7 는 본 RAG 비서의 **데이터 파이프라인 자동화** 를 담당. Cosmos change feed → Service Bus → Function App → AOAI embed → PG/Redis 갱신 흐름이 핵심. Phase 4·5 에서 "Phase 7 로 이관" 했던 작업이 여기서 정식 구현된다.

---

## 학습 경로 구성 (정독 결과)

| 모듈 | 단원 (8~9개씩) |
|---|---|
| **1. Azure Service Bus 를 사용하여 AI 작업 큐·처리** (8 단원) | ① 소개 ② Service Bus 개념 + 메시징 살펴보기 ③ **큐 vs 토픽+구독 선택** ④ AI 워크로드 메시지 구조화 ⑤ 안정적 처리 (peek-lock · complete/abandon · DLQ) ⑥ 연습 — 메시지 처리 ⑦ 평가 ⑧ 요약 |
| **2. Azure Event Grid 로 이벤트 기반 AI 워크플로** (8 단원) | ① 소개 ② Event Grid 개념 + 이벤트 기반 패턴 ③ **이벤트 스키마·속성** (CloudEvents 1.0) ④ 배달·재시도 정책 + DLQ ⑤ 사용자 지정 이벤트 게시 ⑥ 연습 — 이벤트 게시·구독 ⑦ 평가 ⑧ 요약 |
| **3. Azure Functions 로 서버리스 AI 백 엔드** (9 단원) | ① 소개 ② **호스팅·크기 조정** (Flex Consumption / Premium / Container Apps) ③ 로컬 개발 환경 ④ 트리거·바인딩 (HTTP / Cosmos / Service Bus / Event Grid) ⑤ 비밀·구성 관리 (Key Vault 참조) ⑥ ID·액세스 (Managed Identity + RBAC) ⑦ 연습 — **MCP 서버 만들기** ⑧ 평가 ⑨ 요약 |

---

## MS Learn 경로 커버리지 — 사용 / 생략

| 단원 / 학습 항목 | 본 프로젝트 적용 | 비고 |
|---|---|---|
| 모듈 1 ③ 큐 vs 토픽+구독 | ✅ **큐** (`inference-queue`) | 임베딩 작업은 정확히 1 워커 — 경쟁 소비자 패턴 |
| 모듈 1 ④ AI 메시지 구조화 | ✅ `{document_id, chunk_id, chunk_text(≤8KB), correlation_id}` JSON | 256KB 한도 충분 → SKU Standard |
| 모듈 1 ⑤ peek-lock + DLQ | ✅ Function consumer 가 peek-lock 으로 수신, 실패 시 abandon → 5회 후 DLQ | 재시도 횟수 default |
| 모듈 1 인증 | ✅ **AAD + UAMI** (학습 경로 명시 권장) — `disableLocalAuth=true`, RBAC `Data Sender`/`Receiver` | §8 + Phase 4·5·6 일관성 |
| 모듈 2 ③ CloudEvents 1.0 | ✅ 사용자 지정 이벤트 `ai200challenge.document.indexed` | EventGrid native schema 미사용 |
| 모듈 2 ④ 배달·재시도 | ✅ 사용자 지정 토픽 + DLQ destination | |
| 모듈 2 ⑤ 사용자 지정 이벤트 | ✅ Function 임베딩 완료 후 EventGrid publish → Redis pub/sub 으로 fan-out | Phase 6 알림 흐름과 연결 |
| 모듈 2 — 시스템 토픽 (Blob → Function) | 🟡 **생략** — 본 레포 데이터 소스는 Cosmos (sample-data 가 JSON), Blob 흐름 X | Storage 추가 자원 회피 |
| 모듈 3 ② Flex Consumption | ✅ **Flex Consumption (koreacentral 가용성 확인 필요)** — 학습 경로 신규 기본값 | Consumption Linux 2028-09 EOL |
| 모듈 3 ④ 트리거·바인딩 | ✅ **Cosmos DB trigger** (change feed) + **Service Bus trigger** (consumer) | 두 trigger 가 핵심 |
| 모듈 3 ⑤ 비밀·구성 관리 | 🟡 **Phase 8 까지 임시** — Function App settings + UAMI. Key Vault 참조는 Phase 8 에서 정식 이관 | §1 phase 경계 |
| 모듈 3 ⑥ Managed Identity | ✅ 공용 UAMI (`id-ai200challenge-aca-dev`) 재사용 — Cosmos / AOAI / PG / Redis / Service Bus / Event Grid 모두 한 ID 로 접근 | |
| **모듈 3 ⑦ MCP 서버 연습** | ❌ **생략** | 학습 경로도 *actively evolving* 면책 + 본 레포 RAG 흐름과 분리 + AI-200 시험 범위 밖 |
| 각 모듈 평가 / 요약 | ❌ 학습 경로 평가는 사용자가 별도 |

---

## 결정 (사용자 승인: 2026-05-16, A 조합 10개)

| # | 결정 | 채택 | 근거 |
|---|---|---|---|
| 1 | Service Bus SKU | **Standard** | 큐+토픽+구독 + 256KB, Premium 의 ~1/10 비용, AI-200 시험 범위 충족 |
| 2 | 메시지 구조 | **큐 (`inference-queue`) + DLQ + correlation_id** | 경쟁 소비자 패턴 |
| 3 | Service Bus 인증 | **AAD+UAMI, `disableLocalAuth=true`** | 학습 경로 명시 권장 + §8 일관성 |
| 4 | Event Grid 스키마 | **CloudEvents 1.0** | 학습 경로 표준 권장 |
| 5 | Event Grid 토픽 | **사용자 지정 토픽 (`egt-ai200challenge-dev`)** 1개 | 시스템 토픽은 결정 7 로 인해 미생성 |
| 6 | Functions hosting | **Flex Consumption (koreacentral 가용성 사전 확인)** | 학습 경로 신규 기본값, Consumption Linux EOL |
| 7 | 데이터 소스·트리거 | **Cosmos DB change feed Trigger** | sample-data JSON → Cosmos 가 source-of-truth, Blob 흐름 미적용 |
| 8 | MCP 서버 연습 | **생략 + docs 명시** | 학습 경로 actively evolving 면책, RAG 흐름과 분리 |
| 9 | 시크릿·구성 | **Function App settings + UAMI (임시)** | Phase 8 에서 Key Vault 참조로 정식 이관 |
| 10 | 재배포 범위 | **Phase 4 + 5 + 6 모두 재배포** | Cosmos / AOAI / PG / Redis 4개 자원 모두 existing 참조 필요 |

---

## 자원 이름 규칙

| 리소스 | 이름 |
|---|---|
| Service Bus 네임스페이스 | `sb-ai200challenge-dev` |
| 큐: 임베딩 작업 | `inference-queue` |
| 큐: DLQ (자동) | `inference-queue/$DeadLetterQueue` |
| Event Grid 사용자 지정 토픽 | `egt-ai200challenge-dev` (이벤트 type `ai200challenge.document.indexed`) |
| Azure Functions | `func-ai200challenge-dev` (Flex Consumption) |
| Function App 동작용 Storage | `stai200challengedev07` (AzureWebJobsStorage) |
| Flex Consumption plan | `asp-func-ai200challenge-dev` |

---

## 이 프로젝트에서의 적용

### 데이터 파이프라인 흐름

```
[사용자] /api/index?store=cosmos POST chunks
    ↓
Cosmos NoSQL `chunks` 컨테이너 (Phase 4)
    ↓ change feed
[Function A — Cosmos trigger] (Phase 7)
    ↓ Service Bus enqueue { document_id, chunk_id, chunk_text, correlation_id }
Service Bus `inference-queue` (Standard, AAD-only)
    ↓ peek-lock
[Function B — Service Bus trigger] (Phase 7)
    ↓ (1) AOAI embed (chunk_text)
    ↓ (2) PG `chunks_hnsw` UPSERT (Phase 5)
    ↓ (3) Redis 인덱스 갱신 (Phase 6) — workspace 캐시 invalidate
    ↓ (4) EventGrid publish: `ai200challenge.document.indexed`
EventGrid `egt-ai200challenge-dev` (사용자 지정 토픽)
    ↓ subscription → Redis pub/sub
ws:<workspaceId>:events 채널 → SSE/WebSocket 클라이언트 알림
```

### Phase 6 ↔ Phase 7 역할 분리

- **Phase 7 Service Bus** = 메인 데이터 파이프라인 큐. 신뢰성·DLQ·재시도·AAD-only. 임베딩 작업 처리.
- **Phase 6 Redis Streams** = 학습용 1 흐름 (`stream:reembed`) 그대로 유지. 메인 워크로드 X.
- **Phase 6 Redis pub/sub** = Phase 7 의 EventGrid 알림이 *최종적으로 도달* 하는 fanout 채널. SSE/WebSocket 클라이언트로 알림 전달.

---

## Bicep 모듈 구성 (예정)

| 모듈 | 책임 |
|---|---|
| `infra/modules/service-bus-namespace.bicep` | `Microsoft.ServiceBus/namespaces` — Standard SKU, `disableLocalAuth: true` |
| `infra/modules/service-bus-queue.bicep` | `namespaces/queues` — `inference-queue`, DLQ default, max delivery count 5 |
| `infra/modules/role-assignment-servicebus-data-sender.bicep` | UAMI 에 `Azure Service Bus Data Sender` (queue scope) |
| `infra/modules/role-assignment-servicebus-data-receiver.bicep` | UAMI 에 `Azure Service Bus Data Receiver` |
| `infra/modules/event-grid-topic.bicep` | 사용자 지정 토픽 — CloudEvents 1.0, `disableLocalAuth: true` |
| `infra/modules/event-grid-subscription.bicep` | 토픽 구독 (handler = webhook 또는 EventGrid trigger Function) |
| `infra/modules/role-assignment-eventgrid-data-sender.bicep` | UAMI 에 `EventGrid Data Sender` (topic scope) |
| `infra/modules/function-app-flex.bicep` | `Microsoft.Web/sites` (kind=`functionapp,linux`) — Flex Consumption plan, UAMI 부여 |
| `infra/modules/function-app-plan-flex.bicep` | `Microsoft.Web/serverfarms` — Flex Consumption SKU |
| `infra/modules/storage-for-functions.bicep` | Function App 동작용 Storage (AzureWebJobsStorage) — UAMI 접근 |
| `infra/phases/07-backend-services/main.bicep` | 위 모듈 + Phase 4·5·6 `existing` 참조 조립 |
| `infra/phases/07-backend-services/main.bicepparam` | 접미사 / SKU / image tag override |

---

## Function 코드 구성 (예정)

새 디렉토리: `apps/functions/` (api 와 분리, 별도 Python 가상환경 + uv)

```
apps/functions/
├── pyproject.toml          # azure-functions / azure-identity / openai / psycopg / redis 의존성
├── host.json
├── function_app.py         # Function App 엔트리
├── triggers/
│   ├── cosmos_to_queue.py  # Cosmos change feed → Service Bus enqueue
│   └── queue_to_embed.py   # Service Bus 메시지 → embed → PG/Redis 갱신 → EventGrid publish
└── clients/
    ├── pg_writer.py        # PG chunks_hnsw UPSERT (Phase 5 pg_store.py 패턴 재사용)
    ├── redis_invalidator.py  # Redis workspace 캐시 invalidate (Phase 6 semantic.py)
    └── aoai_embed.py       # AOAI embed (Phase 4 aoai_client.py 재사용)
```

**핵심 동작**:
- 두 Function 모두 UAMI 단독으로 Cosmos / AOAI / PG / Redis / Service Bus / Event Grid 접근
- PG 토큰 만료 재인증 패턴 = `apps/api/src/stores/pg_store.py` 의 `_ensure_pool` 그대로 재사용 (Phase 5 함정 4 — chicken-and-egg 해결 코드 포함)
- Redis username = principal objectId (Phase 6 함정 3)

---

## 이미지·배포 (Function App 은 컨테이너 이미지 X, ZIP 배포)

```bash
# Function App 코드 ZIP 배포 (Flex Consumption)
cd apps/functions
func azure functionapp publish func-ai200challenge-dev --python
```

(또는 GitHub Actions 로 자동화 — Phase 10 범위)

---

## 배포 명령

### 사전 — Phase 4·5·6 재배포 (§7 패턴)

Phase 7 의 `main.bicep` 이 4·5·6 자원을 `existing` 참조. soft-delete 충돌 시 접미사 ↑:

```bash
# Phase 4 (Cosmos + AOAI)
az deployment group create \
  -g rg-ai200challenge-dev \
  -p infra/phases/04-cosmos-aoai/main.bicepparam

# Phase 5 (PG)
az deployment group create \
  -g rg-ai200challenge-dev \
  -p infra/phases/05-postgresql/main.bicepparam \
  -p devClientIpAddress=$DEV_IP

# Phase 6 (Redis)
az deployment group create \
  -g rg-ai200challenge-dev \
  -p infra/phases/06-managed-redis/main.bicepparam
```

### Phase 7 본 배포

```bash
# Flex Consumption koreacentral 가용성 사전 확인
az functionapp list-flexconsumption-locations \
  --query "[?contains(name,'koreacentral')]" -o table

# what-if → create
az deployment group what-if \
  -g rg-ai200challenge-dev \
  -p infra/phases/07-backend-services/main.bicepparam

az deployment group create \
  -g rg-ai200challenge-dev \
  -p infra/phases/07-backend-services/main.bicepparam
```

---

## 검증 시나리오 (단계 5 — `/phase-verify`)

### 1) 자원·권한 헬스
- `az servicebus namespace show` → `Succeeded`, Standard, `disableLocalAuth=true`
- `az servicebus queue show -n inference-queue` → 존재, max delivery count 5
- `az eventgrid topic show` → CloudEvents schema, `disableLocalAuth=true`
- `az functionapp show` → Flex Consumption, runtime=python 3.12, UAMI 부여
- UAMI role assignment: SB Data Sender/Receiver + EventGrid Data Sender + Cosmos Data Contributor

### 2) Cosmos → Service Bus → Function → embed 흐름

```bash
# 1) /api/index?store=cosmos POST 로 chunks 5건 적재 (Phase 4 흐름 재사용)
curl -X POST $API/api/index?store=cosmos -d '{...5 chunks...}'

# 2) Cosmos change feed → Function A → Service Bus enqueue 자동 발생
az servicebus queue show -n inference-queue --query "messageCount" -o tsv

# 3) Function B 가 자동 consume → embed → PG 갱신 → EventGrid publish
#    PG chunks_hnsw 적재 확인 (임시 admin 부여 후 psql)
```

### 3) Event Grid publish → Redis pub/sub

```bash
# redis-cli SUBSCRIBE (AAD 토큰 + TLS, Phase 6 패턴 동일)
redis-cli -h <redis-fqdn> -p 10000 --tls --user <uami-objectId> -a <token> \
  SUBSCRIBE 'ws:ws-test:events'

# index POST 후 'ai200challenge.document.indexed' 이벤트가 EventGrid → Redis 로 도달
```

### 4) DLQ 재처리

```bash
# 의도적으로 잘못된 chunk 메시지 enqueue → 5회 실패 후 DLQ 이동
az servicebus queue show -n inference-queue/$DeadLetterQueue --query "messageCount" -o tsv
```

### 5) KQL — Function 실행·재시도·DLQ

```kusto
AppRequests
| where AppRoleName == "func-ai200challenge-dev"
| where TimeGenerated > ago(15m)
| summarize total=count(), failed=countif(Success==false) by Name
| extend success_rate = 1.0 - todouble(failed)/total
```

---

## 측정 결과 (실측, 2026-05-17, Functions v0.7.0)

| 시나리오 | 측정값 | 비고 |
|---|---|---|
| **queue_to_embed 단일 처리** (SB receive → embed → PG UPSERT → Redis invalidate → EG publish → ack) | **1,519 ms** | AOAI embed 가 dominant (Phase 5·6 결론과 일치) |
| **인덱싱 end-to-end** (Cosmos chunk POST → PG 적재 완료) | ~60s 이내 | Cosmos change feed propagation lag 가 dominant — 보통 5~30s, Function cold start 시 추가 ~30s |
| Service Bus enqueue → consume latency | < 1s | peek-lock + AAD-only, 같은 region 내부 통신 |
| EventGrid publish (CloudEvents 1.0) | `PublishSuccessCount` metric 으로 확인 | Function 코드의 `await publish_document_indexed(...)` 호출, *send 응답* 만 측정 가능 (구독자 도달은 별도) |
| DLQ 카운트 (정상 시나리오) | **0** | max delivery 5 안에 모두 success |
| Function 호출 결과 (`AppRequests`) | `Success=True, ResultCode=0` | `cosmos_to_queue` + `queue_to_embed` 모두 성공 |
| PG `chunks_hnsw` 검색 검증 | 3건 모두 적재 + cosine distance 의미적 정렬 | `/api/search?store=pg` 로 직접 확인 |

### 관찰

- **Cosmos change feed lag 가 가장 큰 latency 원천**: chunk POST 후 trigger 발화까지 5~30s. Flex Consumption 의 scale-to-zero + cold start 가 더해지면 1분 이상. 운영에서는 always-ready 인스턴스 1개로 콜드 스타트 회피 (Phase 9 비용 측정 후 결정).
- **embed dominant 원칙 유지**: Phase 5 (PG 단독) / Phase 6 (Redis 캐시 hit) / Phase 7 (Function pipeline) 모두 AOAI embed 호출이 응답 시간의 80%+. 측정 일관성 확인.
- **메시지 손실 없음**: max delivery count 5 안에서 모두 처리 — peek-lock + AAD 인증의 신뢰성 확인.
- **App Insights ingest 안정성**: 함정 7 (AAD ingest 실패) fix 후 instrumentation key 폴백으로 telemetry 안정. AppTraces/AppRequests/AppExceptions 모두 정상 수집.

---

## 함정·교훈

1. **`identity.type='UserAssigned'` 인 자원은 `identity.principalId` 가 존재하지 않음** — Bicep `output principalId string = functionApp.identity.principalId` 가 `DeploymentOutputEvaluationFailed: The language expression property 'principalId' doesn't exist, available properties are 'type, userAssignedIdentities'` 로 실패. **SystemAssigned 일 때만** `identity.principalId` 가 노출됨. UAMI 단독 모드에서 principal 의 objectId 를 얻으려면 `userAssignedIdentities[id].principalId` 또는 `uami.properties.principalId` (existing 참조) 로 접근. 본 레포는 공용 UAMI 패턴이라 main.bicep 에서 `uami.properties.principalId` 로 충분 — 모듈 output 자체를 제거.

2. **Flex Consumption 은 `FUNCTIONS_WORKER_RUNTIME` / `FUNCTIONS_EXTENSION_VERSION` 등 다수 app settings 가 deprecated** — `BadRequest: The following app setting (Site.SiteConfig.AppSettings.FUNCTIONS_WORKER_RUNTIME) for Flex Consumption sites is invalid` 로 차단. Flex 는 runtime/extension version 을 `properties.functionAppConfig.runtime.{name,version}` 으로 관리하므로 두 settings 가 중복·충돌. 공식 deprecated 목록 ([functions-app-settings#flex-consumption-plan-deprecations](https://learn.microsoft.com/en-us/azure/azure-functions/functions-app-settings#flex-consumption-plan-deprecations)):
    - `FUNCTIONS_EXTENSION_VERSION`, `FUNCTIONS_WORKER_RUNTIME`, `FUNCTIONS_WORKER_RUNTIME_VERSION` → `functionAppConfig.runtime`
    - `WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT` → `functionAppConfig.scaleAndConcurrency.maximumInstanceCount`
    - `WEBSITE_CONTENTSHARE`, `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` → `functionAppConfig.deployment`
    - `WEBSITE_RUN_FROM_PACKAGE`, `ENABLE_ORYX_BUILD`, `SCM_DO_BUILD_DURING_DEPLOYMENT` → 미사용
    - `properties.alwaysOn`, `properties.ftpsState`, `properties.LinuxFxVersion`, `properties.use32BitWorkerProcess` 등 site 속성도 다수 미지원
    Bicep 작성 시 Consumption/Premium 의 settings 를 그대로 옮기지 말 것 — Flex 전용 schema 만 사용.

3. **`az functionapp show` 응답은 `properties.*` 안** — Phase 6 의 `az redisenterprise show` 가 properties 를 *평면화* (루트 레벨) 한 것과 정반대. Function App 의 `state`, `kind`(예외), `defaultHostName`, `functionAppConfig` 등은 모두 `properties.*` 안에 있어 `--query "state"` 가 null 반환. 정정: `--query "properties.state"`. **az CLI 의 자원별 응답 구조 일관성 부족** — 새 자원 처음 다룰 때는 항상 `az ... show -o json` raw 결과로 키 위치 확인 후 query 작성. 단 `name`, `kind`, `tags`, `identity` 등 일부 root-level 필드는 평면화돼 있어 더 헷갈림.

4. **Cosmos change feed trigger 의 lease 컨테이너 자동 생성 실패 — UAMI 에 control plane 권한 부재** — Bicep 의 `create_lease_container_if_not_exists=true` 가 작동 안 함. 원인: UAMI 에 부여한 `Cosmos DB Built-in Data Contributor` (`00000000-0000-0000-0000-000000000002`) 의 dataActions 는 `containers/*` 와 `containers/items/*` 만 — *기존 컨테이너의 데이터 read/write* 만 가능. 컨테이너 *생성* 은 control plane (Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/write) 권한 필요. Function trigger 가 lease 컨테이너 생성 시도 → 403 Forbidden → trigger 발화 자체 안 됨 → SB queue 비어있음 → 전체 파이프라인 작동 안 함. **디버깅 우선순위 함정**: AppExceptions 도 안 떠서 표면적으로 정상으로 보임 (lease 생성은 host 수준 작업이라 함수 본문 exception 으로 안 잡힘). 해결: `cosmos-sql-container.bicep` 모듈로 `leases` 컨테이너 (partition key `/id`) 를 Bicep 으로 *미리 생성*. 또는 UAMI 에 `DocumentDB Account Contributor` (control plane) 부여도 가능하나 권한 확장 위험 — 컨테이너 사전 생성이 안전.

5. **Function App 의 LAW resource log 는 diagnostic settings 명시 생성 필요** — Microsoft Learn 명시 ("Resource logs aren't collected and stored until you create a diagnostic setting"). App Insights connection string 만 박으면 `AppTraces` 는 받지만 `FunctionAppLogs` (resource log) 는 안 옴. Phase 9 에서 diagnostic-settings 모듈 추가 검토.

6. **`azure-identity.aio.DefaultAzureCredential` 은 `aiohttp` 가 별도 requirements 로 명시 필요** — Function 에서 첫 trigger 발화 시 `ModuleNotFoundError: No module named 'aiohttp'` 로 처리 실패. `azure-identity` 의 async credential 은 transport 로 `aiohttp` 를 사용하지만 *간접 의존성* 이라 pip 가 자동 설치 안 함. `azure-core` 가 `aiohttp` 를 optional extra 로 분리해 둔 결과. apps/api 는 `aiohttp>=3.10.0` 이 명시 의존성이라 문제 없었지만 (FastAPI 가 보통 함께 가져옴), Function App 의 `requirements.txt` 에는 따로 박아야 함. apps/api/pyproject.toml 의 dependencies 를 그대로 복사할 때 *transient deps* 가 빠질 수 있다는 학습.

7. **`APPLICATIONINSIGHTS_AUTHENTICATION_STRING=Authorization=AAD` 는 UAMI 에 별도 RBAC 필요** — Flex 공식 Bicep 샘플에 박힌 setting 인데 그대로 박으면 `ManagedIdentityCredential.GetToken ... Scopes: [https://monitor.azure.com//.default]` 실패 + App Insights ingest 막힘 + Function host 가 telemetry 안정성 문제로 trigger 발화 지연. AAD ingest 사용하려면 UAMI 에 **`Monitoring Metrics Publisher`** (또는 App Insights resource scope 의 `Publisher`) role 부여 필요. Phase 7 에서는 *instrumentation key 기반 ingest* (connection string 만 박음) 로 폴백 — Phase 9 에서 정식 AAD ingest + RBAC 추가 검토. 공식 샘플의 settings 를 그대로 따라가지 말고 *RBAC 와 함께* 도입해야 한다는 학습.

8. **dev 환경에서도 *idle 자원의 누적 비용* 이 폭증** — 7일 (2026-05-11 ~ 2026-05-18) 실측: **총 108,569 KRW** (사용자 청구서 기준 ~130K 부근). Cost Management Query API (`/providers/Microsoft.CostManagement/query`) 로 확인. 분포:

    | 자원 | 7일 비용 (KRW) | 비중 | 일 평균 | 비고 |
    |---|---|---|---|---|
    | **Redis Enterprise (Memory_M10)** | **81,762** | **75%** | ~11,680 | dev/test 권장 SKU 이지만 idle 시간당 ~485 KRW |
    | ACA api + web (Container Apps) | 12,199 | 11% | ~1,743 | min replica 1 — 트래픽 없어도 항상 1개 컨테이너 실행 |
    | AKS LoadBalancer + Public IP | **7,876** | **7%** | ~1,125 | `MC_rg-..._aks-...` 의 Standard LB + 공인 IP — Phase 3 *진짜* 부산물. AKS 클러스터를 안 만져도 idle 발생 |
    | PG Flexible B1ms | 4,895 | 5% | ~699 | Burstable 도 idle 비용 ~700 KRW/일 |
    | ACR Basic | 1,821 | 2% | ~260 | storage + image scan |
    | Cosmos / AOAI / Storage / Functions / SB / EG / LAW | < 30 | <1% | — | Serverless / Consumption 류는 거의 0 |

    **일별 폭증 패턴** — 5/13 (Phase 6 Redis 배포일): 9,766 KRW → 5/14: **22,720 KRW** (+132%). Redis 가 정확히 dominant 가 된 시점과 일치.

    **이전 인식과의 갭** — history.md 에 "AKS idle 비용 dominant" 로 기록했지만 *실측* 으로는 **Redis 가 dominant** (10배 차이). AKS LB 는 dev 가격 기준 *상대적으로 미미* (1,125 KRW/일 ≪ Redis 11,680 KRW/일).

    **학습**: dev 환경에서 *학습 후 자원 보존* 룰 (CLAUDE.md §7) 이 단기간에 비용 폭증을 만든다. 본 phase 8 이후 룰 변경: **무료/사실상 무료 자원만 보존** (ACR Basic 의 일 ~260 KRW 도 누적되면 부담, 단 storage 만이라 compute 자원 보존보다 훨씬 적음). Compute 가 있는 자원 (Redis / PG / ACA / AKS) 은 phase 종료 시점에 적극적 정리.

    **확인 명령** (Cost Management Query REST API):
    ```bash
    TOKEN=$(az account get-access-token --query accessToken -o tsv)
    SUB=$(az account show --query id -o tsv)
    curl -sS -X POST "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.CostManagement/query?api-version=2023-11-01" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d '{"type":"ActualCost","timeframe":"MonthToDate",
           "dataset":{"granularity":"None",
                      "aggregation":{"totalCost":{"name":"Cost","function":"Sum"}},
                      "grouping":[{"type":"Dimension","name":"ServiceName"}]}}'
    ```
    `az consumption usage list` 는 `pretaxCost: None` 만 반환 (현 시점 API 한계). REST API 직접 호출이 안정적.

9. *TBD* — Flex Consumption 의 koreacentral 콜드 스타트 실측 (가용성은 사전 확인 완료)
10. *TBD* — Service Bus AAD-only 모드에서 Python SDK 의 `DefaultAzureCredential` 패턴
11. *TBD* — EventGrid CloudEvents schema 의 Python SDK 직렬화 (subject·type 필드)
12. *TBD* — Function App settings 의 secret 노출 (Phase 8 Key Vault 전 임시 패턴)

---

## 정리 (Phase 8 진입 직전)

§7 룰 (2026-05-18 갱신, 함정 8 기반) — **무료/사실상-무료 자원만 보존, compute 자원은 모두 정리**.

사용자 명시 요청 후:

```bash
# Phase 7 phase-specific
az servicebus namespace delete -g rg-ai200challenge-dev -n sb-ai200challenge-dev --yes
az eventgrid topic delete -g rg-ai200challenge-dev -n egt-ai200challenge-dev --yes
az functionapp delete -g rg-ai200challenge-dev -n func-ai200challenge-dev --yes
az storage account delete -g rg-ai200challenge-dev -n stai200challengedev07 --yes
az appservice plan delete -g rg-ai200challenge-dev -n asp-func-ai200challenge-dev --yes

# Phase 4·5·6 데이터 자원 (이전 cleanup 에서 이미 정리됨)
# Phase 8 은 KV/AC 자체라 데이터 자원 불필요

# 신규 룰 — ACA api/web + AKS 도 정리 (idle 비용 누적)
az containerapp delete -g rg-ai200challenge-dev -n ca-ai200challenge-api-dev --yes
az containerapp delete -g rg-ai200challenge-dev -n ca-ai200challenge-web-dev --yes
az aks delete -g rg-ai200challenge-dev -n aks-ai200challenge-dev --yes
# AKS 의 MC_... RG 는 cascade 자동 삭제
```

**보존**: ACR / LAW / UAMI×2 / CAE / Application Insights. Phase 8·9 진입 시 ACA api 는 image tag 와 함께 재배포 (CAE 가 살아있어 빠름).
