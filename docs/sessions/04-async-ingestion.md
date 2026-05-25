# session-04 — 비동기 인제스션 (Service Bus + Event Grid + Functions)

> 학습 경로 매핑: [Integrate backend services for AI solutions](https://learn.microsoft.com/ko-kr/training/paths/integrate-backend-services-ai-solutions/)  
> 사전 조건: session-01·session-02·session-03 완료, `git checkout session-04-start`

---

## 0. 이 세션에서 무엇을 경험하나

- **한 문장 골**: PDF 한 장을 Blob 에 업로드하면, 30초 안에 청크·임베드 되어 Cosmos·PG 양쪽 인덱스에 자동으로 들어가는 *비동기 파이프라인* 을 본인 손으로 본다.
- **새로 프로비저닝되는 자원**:
  - Service Bus Namespace (Standard) + Queue (`ingest-queue`) + DLQ
  - Event Grid System Topic (Blob Storage events)
  - Azure Functions (Flex Consumption, Python v2)
  - Storage Account (Blob, OAC + RBAC)
  - Cosmos change feed *lease container* (Bicep 으로 사전 생성)
- **사용해볼 SDK/CLI**:
  - Azure Functions Python v2 데코레이터 (`@app.cosmos_db_trigger`, `@app.service_bus_queue_trigger`, `@app.blob_trigger`)
  - `func azure functionapp publish`
- **Portal 에서 확인할 지표/데이터**:
  - Service Bus → Queue Metrics — Active 메시지 수 그래프
  - Service Bus → DLQ — 0 유지 (실패 없음 검증)
  - Function App → Invocations — 트리거 실행 카운트
  - Function App → Log stream — 라이브 로그
  - Event Grid → Topic Metrics — Publish/Deliver 수

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈

- `service-bus-namespace.bicep` — Standard SKU
- `service-bus-queue.bicep` — `ingest-queue` + DLQ (max delivery 5)
- `event-grid-system-topic.bicep` — Storage Blob 이벤트 토픽
- `event-grid-subscription.bicep` — SB queue 로 라우팅
- `storage-account.bicep` — `allowSharedKeyAccess=false`, OAC + RBAC
- `function-app-plan-flex.bicep` — Flex Consumption Linux 플랜
- `function-app-flex.bicep` — Python v2, `functionAppConfig.runtime` 신 스키마
- `cosmos-lease-container.bicep` — change feed lease (사전 생성!)
- RBAC: `role-assignment-servicebus-data-receiver.bicep`, `role-assignment-eventgrid-data-sender.bicep`, `role-assignment-storage-blob-data-reader.bicep`

### 1.2 배포

```bash
OID=$(az ad signed-in-user show --query id -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/04-async-ingestion/main.bicep \
  --parameters infra/sessions/04-async-ingestion/main.bicepparam \
  --parameters userObjectId=$OID

az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/04-async-ingestion/main.bicep \
  --parameters infra/sessions/04-async-ingestion/main.bicepparam \
  --parameters userObjectId=$OID
```

> ⏱ 약 **5~7분** 소요. 진행되는 동안 §2 의 이벤트 흐름 다이어그램 정독.

### 1.3 배포 완료 확인

```bash
az functionapp show -n func-ai200ws-dev -g rg-ai200ws-dev \
  --query "{state:state, runtime:functionAppConfig.runtime}" -o jsonc
# 기대: state=Running, runtime.name=python, runtime.version=3.12
```

---

## 2단계 · 복붙으로 경험해보기

### 2.1 이벤트 흐름 다이어그램

```
[사용자] Blob 업로드 (PDF/MD)
   ↓
[Storage] → [Event Grid System Topic] → 이벤트 발행
   ↓
[Event Grid Subscription] → [Service Bus Queue: ingest-queue]
   ↓
[Function: on_ingest_message]  (queue trigger)
   ├─ Blob 다운로드 (UAMI + Storage Blob Data Reader)
   ├─ 청크 분할 (텍스트)
   ├─ AOAI embed (DefaultAzureCredential)
   └─ Cosmos upsert + PG upsert (병렬)
       ↓
[Cosmos change feed] → [Function: on_cosmos_change]
   └─ (선택) 다운스트림 publish 또는 통계

실패 시: SB Queue → DLQ (max delivery 5)
```

> 🎯 **AI-200 시험 포인트**: "사용자 응답 시간을 빠르게" — 무거운 임베드 작업은 큐로 빼고, API 는 chunk 가 준비된 후에만 답하도록.

### 2.2 코드 복사·붙여넣기

**파일 1**: `apps/functions/function_app.py`

```python
# (Azure Functions Python v2 — 두 개의 함수:
#  1) on_ingest_message (Service Bus queue trigger):
#     - Blob URL → 다운로드 (UAMI, Storage Blob Data Reader)
#     - 청크 분할 (~500 tokens, overlap 50)
#     - AOAI text-embedding-3-large 배치 임베드
#     - Cosmos + PG 양쪽 upsert
#  2) on_cosmos_change (Cosmos change feed trigger):
#     - lease container 사용 (Bicep 으로 사전 생성!)
#     - 통계 collection 업데이트
#  주의:
#  - query_items 에 partition_key 명시 (cross-partition RU 폭주 방지)
#  - Flex Consumption 이라 FUNCTIONS_WORKER_RUNTIME 환경변수 X
#  - 실제 코드는 후속 구현.)
```

**파일 2**: `apps/functions/requirements.txt` — `azure-functions`, `azure-identity`, `azure-storage-blob`, `azure-cosmos`, `openai`, `psycopg[binary]`, `pgvector`

### 2.3 함수 배포

```bash
cd apps/functions

# Functions Core Tools 로 배포
func azure functionapp publish func-ai200ws-dev --python --build remote

cd ../..
```

### 2.4 E2E 테스트

```bash
# 1) 샘플 markdown 만들기
cat > /tmp/sample-policy.md <<'EOF'
# 휴가 규정

- 연간 휴가는 15일입니다.
- 6개월 근속 후부터 사용 가능합니다.
EOF

# 2) Blob 업로드
STORAGE=$(az storage account list -g rg-ai200ws-dev \
  --query "[?contains(name,'st')].name | [0]" -o tsv)
az storage blob upload \
  --account-name $STORAGE \
  --container-name documents \
  --file /tmp/sample-policy.md \
  --name policy/sample-policy.md \
  --auth-mode login

# 3) 30초 대기 후 Cosmos 에 도착했는지
sleep 30
az cosmosdb sql query \
  --account-name cosmos-ai200ws-dev \
  --database-name appdb \
  --container-name chunks \
  --query-text "SELECT VALUE COUNT(1) FROM c WHERE c.doc_id = 'sample-policy'" \
  --partition-key-value "sample-policy"
# 기대: 0 이 아닌 정수 (청크 개수)
```

---

## 3단계 · Azure Portal UI 에서 확인

1. **Service Bus** (`sb-ai200ws-dev`) → 큐 `ingest-queue` → **Metrics**
   - `Active Messages` — 업로드 직후 1 → 0 (Function 이 처리)
   - `Dead-lettered Messages` — **0 유지** (실패 없음)
2. **Service Bus** → 큐 → **Service Bus Explorer** → Peek — 처리 중인 메시지 본문 확인
3. **Function App** (`func-ai200ws-dev`) → **Functions** → `on_ingest_message` → **Invocations** — 실행 1개, status `Success`, duration ~2~5초
4. **Function App** → **Log stream** — 라이브 로그에 `[on_ingest_message] processed sample-policy.md → 3 chunks`
5. **Event Grid System Topic** → **Topics** → **Metrics** — `Publish Events`, `Delivery Successes` 카운트 1
6. **Cosmos DB** → Data Explorer → `chunks` → `SELECT * WHERE doc_id = 'sample-policy'` — 청크 객체들

### 실패 시뮬레이션 (선택)

```bash
# 일부러 잘못된 메시지를 큐에 직접 보내기 → 5회 재시도 후 DLQ 로
az servicebus message send \
  --resource-group rg-ai200ws-dev \
  --namespace-name sb-ai200ws-dev \
  --queue-name ingest-queue \
  --body '{"invalid": true}'

# 1~2분 후 Portal 에서 DLQ Count 가 1 로 증가하는 것 확인
```

---

## 주의 (Heads-up)

- ⚠️ **Cosmos change feed trigger lease container 자동 생성은 control plane RBAC 없으면 silent fail** — 가장 잔인. Function 정상 보임, 에러 0, trigger 안 fire. **Bicep 으로 lease container 사전 생성** 필수
- ⚠️ **Flex Consumption 신 스키마** — `FUNCTIONS_WORKER_RUNTIME`, `FUNCTIONS_EXTENSION_VERSION` 미지원. `functionAppConfig.runtime.name = "python"` 사용
- ⚠️ **`identity.type='UserAssigned'` 자원은 `identity.principalId` 미노출** — `userAssignedIdentities[id].principalId` 사용. Bicep output 작성 시 주의
- ⚠️ **Storage `allowSharedKeyAccess=false` 시 Function 부팅 실패** — OAC + RBAC 사전 설정 필수
- ⚠️ **`query_items` 에 `partition_key=...` 명시** — cross-partition 은 RU 폭주
- ⚠️ **Function AppExceptions 는 host-level lease creation 403 을 못 잡음** — Activity log 와 Storage 진단 로그를 같이 확인

---

## 마무리

- **save-point**: `git tag session-04-complete`
- **다음 세션 미리보기**: session-05 — 지금까지 환경변수에 박혀있던 `ENABLE_SEMANTIC_CACHE` 같은 토글을 App Configuration 으로 빼서, *재배포 없이* 포털에서 바꾸자

---

## 참고 자료

- Microsoft Learn — [Integrate backend services for AI solutions](https://learn.microsoft.com/ko-kr/training/paths/integrate-backend-services-ai-solutions/)
- Microsoft Learn — [Azure Functions Flex Consumption](https://learn.microsoft.com/ko-kr/azure/azure-functions/flex-consumption-plan)
- 본 저장소 — `infra/sessions/04-async-ingestion/main.bicep`, `apps/functions/function_app.py`

---

👈 [session-03 — Managed Redis 시맨틱 캐시](./03-redis-cache.md) | [session-05 — App Configuration 피처 플래그](./05-app-config-flags.md) 👉
