# Phase 4 — Cosmos DB for NoSQL (벡터) + Azure OpenAI 통합

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-cosmos-db/ (3 모듈)

> **AI-200 학습 경로에는 AOAI 단독 Phase 가 없다.** 임베딩 없이 벡터 검색을 검증할 수 없으므로 Phase 4 에 AOAI 계정·deployment 2개 (`gpt-4o-mini`, `text-embedding-3-large`) 를 함께 도입하고, Cosmos UAMI 가 AOAI 에도 `Cognitive Services OpenAI User` 로 접근하는 패턴을 확립한다. **변경 피드 → Function 자동 임베딩** 은 Functions 가 Phase 7 범위이므로 그쪽으로 이관.

## 학습 경로 구성

1. **Cosmos DB for NoSQL 에 대한 쿼리 빌드** — 리소스 모델, Python SDK 통합, CRUD, SQL 쿼리.
2. **벡터 검색 구현** — 벡터 포함 저장, `VectorDistance` 유사성 쿼리, 메타데이터 필터 + 하이브리드 검색.
3. **쿼리 성능 최적화** — 쿼리 패턴 분석, 범위·복합 인덱스, 벡터 인덱스 유형 선택, 일관성 수준 선택.

## 이 프로젝트에서의 적용

- 단일 Cosmos DB for NoSQL 계정 (`cosmos-ai200challenge-dev<suffix>`) — **Serverless** + `EnableNoSQLVectorSearch` capability
- DB `kb` · 컨테이너 2개: `documents` (메타), `chunks` (텍스트 + 임베딩 3072-d)
- 파티션 키: `/workspaceId` (워크스페이스 격리 + 쓰기 분산)
- 벡터 인덱스: `quantizedFlat` (3072-d 균형형) → 데이터 증가 시 `diskANN` 비교 실험은 후속
- **AAD 전용**: `disableLocalAuth=true` + Cosmos `sqlRoleAssignments` 로 Phase 2 의 ACA UAMI 에 `Cosmos DB Built-in Data Contributor` 부여
- AOAI: 동일 UAMI 가 **데이터 plane** 토큰으로 `gpt-4o-mini` / `text-embedding-3-large` 호출 (Cognitive Services OpenAI User)
- 일관성 수준: 계정 기본 `Session` 유지 (RAG 응답 측은 Phase 6 시맨틱 캐시에서 Eventual 검토)

## 구현 스냅샷

| 컴포넌트 | 리소스 | 이름 |
|---|---|---|
| Cosmos DB 계정 | NoSQL Serverless + Vector | `cosmos-ai200challenge-dev<suffix>` |
| Cosmos DB | SQL DB | `kb` |
| 컨테이너 (메타) | pk=`/workspaceId`, vector 없음 | `documents` |
| 컨테이너 (벡터) | pk=`/workspaceId`, embedding 3072-d float32 cosine, quantizedFlat | `chunks` |
| AOAI 계정 | kind=OpenAI, AAD-only | `aoai-ai200challenge-dev<suffix>` |
| AOAI deployment (chat) | gpt-4o-mini, Standard, 30 capacity | `gpt-4o-mini` |
| AOAI deployment (embed) | text-embedding-3-large, Standard, 30 capacity | `text-embedding-3-large` |
| Cosmos data plane RBAC | Built-in Data Contributor | UAMI ↔ Cosmos 계정 |
| AOAI control plane RBAC | Cognitive Services OpenAI User | UAMI ↔ AOAI 계정 |

---

## 아키텍처

```
rg-ai200challenge-dev
├─ cosmos-ai200challenge-dev<suffix>          (NoSQL, Serverless, AAD-only)
│     └─ kb (DB)
│         ├─ documents  (pk=/workspaceId, vector X)
│         └─ chunks     (pk=/workspaceId, /embedding 3072-d, quantizedFlat)
│
├─ aoai-ai200challenge-dev<suffix>            (kind=OpenAI, AAD-only)
│     ├─ deployment: gpt-4o-mini              (Standard 30 capacity)
│     └─ deployment: text-embedding-3-large   (Standard 30 capacity, dependsOn chat)
│
├─ id-ai200challenge-aca-dev                  (Phase 2 UAMI, existing)
│     ├─ Cosmos DB Built-in Data Contributor  on cosmos-...
│     └─ Cognitive Services OpenAI User       on aoai-...
│
└─ ca-ai200challenge-api-dev                  (Phase 2 ACA, 갱신)
      └─ env: COSMOS_ENDPOINT / COSMOS_DB / COSMOS_CONTAINER_DOCUMENTS
              COSMOS_CONTAINER_CHUNKS / AOAI_ENDPOINT / AOAI_DEPLOYMENT_CHAT
              AOAI_DEPLOYMENT_EMBED / AZURE_CLIENT_ID
```

> **Phase 2 와의 관계**: ACR · UAMI · ACA Env · `ca-...-api-dev` 모두 `existing` 으로 참조. Phase 4 가 만드는 신규 자원은 Cosmos 계정/DB/컨테이너 + AOAI 계정/deployment 2 + 역할 할당 2. `ca-...-api-dev` 는 동일 모듈을 같은 사양으로 재호출하면서 envVars 만 추가 → ACA 가 새 리비전을 자동 생성.

---

## Bicep 모듈 맵

| 파일 | 책임 |
|---|---|
| `infra/phases/04-cosmos-aoai/main.bicep` | Phase 4 엔트리 (resourceGroup 스코프). Phase 1/2 자원은 모두 `existing` 참조 |
| `infra/phases/04-cosmos-aoai/main.bicepparam` | 리전·환경·접미사·이미지 태그·AOAI 모델 버전·capacity 파라미터 |
| `infra/modules/cosmos-account.bicep` | NoSQL Serverless + `EnableNoSQLVectorSearch` + `disableLocalAuth=true` + Periodic 백업 |
| `infra/modules/cosmos-sql-database.bicep` | SQL DB (`kb`) — Serverless 이므로 throughput 미설정 |
| `infra/modules/cosmos-sql-container.bicep` | 컨테이너 1개 — vector 옵션 (paths 비어있으면 일반, 있으면 vectorEmbeddingPolicy + vectorIndexes) |
| `infra/modules/role-assignment-cosmos-data-contributor.bicep` | `sqlRoleAssignments` (data plane) UAMI → 00000000-...-002 |
| `infra/modules/aoai-account.bicep` | `Microsoft.CognitiveServices/accounts` kind=OpenAI, customSubDomainName, AAD-only |
| `infra/modules/aoai-deployment.bicep` | 모델 deployment 1개 (sku=Standard 기본, GlobalStandard 옵션) |
| `infra/modules/role-assignment-aoai-user.bicep` | 일반 ARM RBAC — `Cognitive Services OpenAI User` (5e0bd9bd-...) |
| `infra/modules/container-app.bicep` | **재사용** — Phase 4 에서 동일 사양 + envVars 만 변경하여 재호출 |

---

## 스텝별 Bicep 하이라이트

### 스텝 1 — Cosmos 계정 (Serverless + Vector capability)

```bicep
// modules/cosmos-account.bicep (발췌)
resource account 'Microsoft.DocumentDB/databaseAccounts@2024-08-15' = {
  name: name
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    capabilities: [
      { name: 'EnableServerless' }
      { name: 'EnableNoSQLVectorSearch' }
    ]
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: 'Tls12'
    locations: [
      { locationName: location, failoverPriority: 0, isZoneRedundant: false }
    ]
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
  }
}
```

> **`EnableServerless` capability** 와 **`EnableNoSQLVectorSearch` capability** 는 Cosmos 의 NoSQL 벡터 검색 GA 라인업. `disableLocalAuth=true` 가 들어가는 순간 키는 발급되지만 `403`. data plane 은 다음 스텝의 `sqlRoleAssignments` 로만 통제.

### 스텝 2 — 컨테이너의 vector 옵션 (조건부)

`documents` 와 `chunks` 모두 같은 모듈 호출. `vectorEmbeddingPaths` 가 비어 있으면 vector 미설정, 있으면 정책+인덱스를 모두 추가.

```bicep
// modules/cosmos-sql-container.bicep (발췌 — for 식은 union() 인자에 직접 못 들어가서
// 변수로 분리. 안 그러면 BCP138 'For-expressions are not supported in this context')
var vectorExcludedPaths = [for p in vectorEmbeddingPaths: { path: '${p}/*' }]
var excludedPaths = union([{ path: '/_etag/?' }], vectorExcludedPaths)

var vectorIndexes = [for p in vectorEmbeddingPaths: { path: p, type: vectorIndexType }]
var vectorEmbeddings = [for p in vectorEmbeddingPaths: {
  path: p
  dataType: vectorDataType
  dimensions: vectorDimensions
  distanceFunction: vectorDistanceFunction
}]

var resourceFinal = hasVector ? union(resourceBase, {
  vectorEmbeddingPolicy: { vectorEmbeddings: vectorEmbeddings }
}) : resourceBase
```

main.bicep 호출:

```bicep
module cosmosChunks '../../modules/cosmos-sql-container.bicep' = {
  name: 'deploy-cosmos-c-chunks'
  params: {
    accountName: cosmos.outputs.name
    databaseName: cosmosDb.outputs.name
    containerName: 'chunks'
    partitionKeyPath: '/workspaceId'
    vectorEmbeddingPaths: [ '/embedding' ]
    vectorDimensions: 3072                 // text-embedding-3-large
    vectorDataType: 'float32'
    vectorDistanceFunction: 'cosine'
    vectorIndexType: 'quantizedFlat'
  }
}
```

> **`/embedding` 의 `excludedPaths` 자동 추가**: vector index 가 별도로 관리되므로 일반 인덱스가 3072 차원 배열을 매번 인덱싱하면 RU 폭증. 모듈에서 `${path}/*` 패턴으로 자동 제외.

### 스텝 3 — Cosmos data plane RBAC (sqlRoleAssignments)

NoSQL data plane 은 일반 ARM `Microsoft.Authorization/roleAssignments` **가 아니라** Cosmos 자체 `sqlRoleAssignments`. `00000000-0000-0000-0000-000000000002` 가 Built-in Data Contributor.

```bicep
// modules/role-assignment-cosmos-data-contributor.bicep (발췌)
resource assignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-08-15' = {
  parent: account
  name: guid(account.id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: '${account.id}/sqlRoleDefinitions/${roleDefinitionId}'
    principalId: principalId
    scope: account.id
  }
}
```

> **여기서 자주 하는 실수**: 일반 RBAC 으로 `Cosmos DB Account Reader Role` 만 주고 끝내면 control plane (계정 메타데이터) 만 읽힘. 데이터는 **여전히 401**. 두 RBAC 트랙이 분리되어 있다는 게 Cosmos NoSQL 의 가장 큰 함정.

### 스텝 4 — AOAI 계정 + 모델 배포 직렬화

AOAI 계정 1개에 deployment 2개를 동시에 PUT 하면 `409 Conflict` 이 흔함. main.bicep 에서 두 번째 deployment 에 `dependsOn` 을 걸어 직렬화.

```bicep
module aoaiChat '../../modules/aoai-deployment.bicep' = {
  name: 'deploy-aoai-chat'
  params: {
    accountName: aoai.outputs.name
    deploymentName: 'gpt-4o-mini'
    modelName: 'gpt-4o-mini'
    modelVersion: '2024-07-18'
    skuName: 'Standard'
    skuCapacity: 30
  }
}

module aoaiEmbed '../../modules/aoai-deployment.bicep' = {
  name: 'deploy-aoai-embed'
  params: {
    accountName: aoai.outputs.name
    deploymentName: 'text-embedding-3-large'
    modelName: 'text-embedding-3-large'
    modelVersion: '1'
    skuName: 'Standard'
    skuCapacity: 30
  }
  dependsOn: [ aoaiChat ]
}
```

> **`Standard` vs `GlobalStandard` 트레이드오프**: GlobalStandard 가 가장 저렴하지만 라우팅 region 이 보장 안 됨. 한국 데이터 주권 학습 포인트와 충돌하므로 default 는 `Standard` (koreacentral 고정). 학습용 대량 호출 시 모듈 파라미터로 `GlobalStandard` 전환 가능.

### 스텝 5 — UAMI → AOAI 'Cognitive Services OpenAI User'

AOAI 는 일반 ARM RBAC. role definition `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd` 가 모델 호출 권한.

```bicep
// modules/role-assignment-aoai-user.bicep (발췌)
resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, principalId, roleDefinitionId)
  scope: account
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions', roleDefinitionId
    )
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
```

### 스텝 6 — Phase 2 의 api ACA 에 envVars 주입

같은 `container-app.bicep` 모듈을 **모든 사양 동일 + envVars 만 추가** 하여 재호출. ACA 는 동일 deployment 이름으로 들어오는 변경분을 `properties.template` 의 새 리비전으로 자동 처리.

```bicep
module apiApp '../../modules/container-app.bicep' = {
  name: 'deploy-ca-api'
  params: {
    name: apiAppName
    environmentId: cae.id
    acrLoginServer: acr.properties.loginServer
    userAssignedIdentityId: uami.id
    imageName: 'api'
    imageTag: imageTag                      // Phase 4 코드 변경에 맞춰 0.4.0 으로 bump
    targetPort: 8000
    ingressExternal: false
    healthProbePath: '/healthz'
    minReplicas: 1
    maxReplicas: 5
    httpConcurrency: 30
    envVars: {
      COSMOS_ENDPOINT: cosmos.outputs.documentEndpoint
      COSMOS_DB: cosmosDb.outputs.name
      COSMOS_CONTAINER_DOCUMENTS: cosmosDocuments.outputs.name
      COSMOS_CONTAINER_CHUNKS: cosmosChunks.outputs.name
      AOAI_ENDPOINT: aoai.outputs.endpoint
      AOAI_DEPLOYMENT_CHAT: aoaiChat.outputs.name
      AOAI_DEPLOYMENT_EMBED: aoaiEmbed.outputs.name
      AZURE_CLIENT_ID: uami.properties.clientId
    }
  }
  dependsOn: [ cosmosRbac, aoaiRbac ]
}
```

> **`AZURE_CLIENT_ID` 주입이 핵심**: ACA 위에서 `DefaultAzureCredential()` 이 어느 UAMI 를 쓸지 결정하려면 이 환경변수가 필수. 안 주면 system-assigned 를 찾다가 실패.

---

## 코드 — `apps/api`

### `apps/api/src/clients/aoai_client.py`

`get_bearer_token_provider` + `AsyncAzureOpenAI` 조합. 토큰은 SDK 가 만료마다 자동 갱신.

```python
from azure.identity.aio import DefaultAzureCredential, get_bearer_token_provider
from openai import AsyncAzureOpenAI

token_provider = get_bearer_token_provider(
    DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default"
)
client = AsyncAzureOpenAI(
    azure_endpoint=endpoint,
    api_version="2024-10-21",
    azure_ad_token_provider=token_provider,
)
```

### `apps/api/src/stores/cosmos_store.py`

`VectorDistance` 쿼리 — partition pruning + 메타데이터 필터 + 벡터 거리:

```python
query = f"""
SELECT TOP @k
    c.id, c.documentId, c.ordinal, c.text,
    VectorDistance(c.embedding, @qv) AS score
FROM c
{filter_clause}
ORDER BY VectorDistance(c.embedding, @qv)
"""

async for item in self._chunks.query_items(
    query=query, parameters=params, partition_key=workspace_id
):
    items.append(item)
```

`partition_key=workspace_id` 명시 → cross-partition 비활성, RU 절약.

### `apps/api/src/routers/index_search.py`

Phase 4 검증용 라우터 2개:

| 메서드 | 경로 | 동작 |
|---|---|---|
| POST | `/api/index` | chunks 배열 → 배치 임베딩 → Cosmos `chunks` upsert |
| POST | `/api/search` | query 문자열 → 임베딩 → vector top-K 결과 |

`chat.py` 는 Phase 5/6 에서 PG/Redis 합치며 RAG 화 예정 — 지금은 stub 유지.

### `apps/api/src/main.py` lifespan

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    cosmos = CosmosStore(CosmosSettings.from_env()) if os.environ.get("COSMOS_ENDPOINT") else None
    aoai = AOAIClient(...) if os.environ.get("AOAI_ENDPOINT") else None
    app.state.cosmos = cosmos; app.state.aoai = aoai
    try: yield
    finally:
        if cosmos: await cosmos.close()
        if aoai:   await aoai.close()
```

> **env 미주입 시 `None`**: Phase 1~3 의 단독 실행 (env 없는 환경) 에서도 `/healthz`, `/api/chat` (stub) 은 정상 동작. RAG 라우터만 `503 RAG backend not initialized` 로 친절히 거부.

---

## 이미지 빌드·푸시 (CLAUDE.md IaC-first 예외)

```bash
PROJECT="ai200challenge"
ENV="dev"
ACR_SUFFIX="04"
ACR_NAME="acr${PROJECT}${ENV}${ACR_SUFFIX}"
IMAGE_TAG="0.4.0"

# 1) AAD 로 ACR 로그인
az acr login --name "$ACR_NAME"

# 2) api 이미지 빌드 (linux/amd64 — ACA 기본)
docker build --platform linux/amd64 \
  -t "$ACR_NAME.azurecr.io/api:$IMAGE_TAG" \
  -f apps/api/Dockerfile apps/api

# 3) 푸시
docker push "$ACR_NAME.azurecr.io/api:$IMAGE_TAG"

# 4) 확인
az acr repository show-tags -n "$ACR_NAME" --repository api -o table
```

> **web 컨테이너는 Phase 4 에서 코드 변경 없음** → 0.1.0 태그 그대로. Phase 4 main.bicep 도 web 을 갱신하지 않으므로 (ACA api 만 재호출) 영향 없음.

---

## 배포 명령

### What-if (변경 사전 확인)

```bash
RG="rg-ai200challenge-dev"

az deployment group what-if \
  -g "$RG" \
  --template-file infra/phases/04-cosmos-aoai/main.bicep \
  --parameters infra/phases/04-cosmos-aoai/main.bicepparam
```

기대: Cosmos 계정/DB/컨테이너 2 + AOAI 계정/deployment 2 + sqlRoleAssignment 1 + roleAssignment 1 = 8 Create. `ca-...-api-dev` 1 Modify (envVars 추가 + imageTag bump). 역할 할당 한두 개는 `Unsupported` 노이즈.

### 실배포

```bash
DEPLOY_NAME="phase4-$(date +%Y%m%d-%H%M%S)"

az deployment group create \
  -g "$RG" \
  --name "$DEPLOY_NAME" \
  --template-file infra/phases/04-cosmos-aoai/main.bicep \
  --parameters infra/phases/04-cosmos-aoai/main.bicepparam

# outputs 확인
az deployment group show -g "$RG" --name "$DEPLOY_NAME" \
  --query 'properties.outputs' -o yaml
```

---

## 검증 시나리오

### 1) ACA 새 리비전 healthy

```bash
az containerapp revision list \
  -n ca-ai200challenge-api-dev -g "$RG" \
  --query '[].{name:name, active:properties.active, replicas:properties.replicas, traffic:properties.trafficWeight, healthState:properties.healthState, image:properties.template.containers[0].image}' \
  -o table
```

기대: 새 리비전 (image 가 `:0.4.0` 태그) 이 `Healthy`, `active=true`, `traffic=100`. 이전 `:0.1.0` 리비전은 `active=false`.

### 2) /api/index — 임베딩 후 Cosmos 저장

ACA api 는 internal ingress. 같은 ACA Env 안에서만 도달 가능. 가장 간단한 검증은 web 앱에 임시 호출 페이지를 두거나, ACA `exec` 로 들어가서 curl. 또는 `az containerapp ingress` 를 임시로 external 로 잠시 바꿔 검증 후 되돌리기 (학습용).

```bash
# (옵션) 일시적 external 노출
az containerapp ingress update \
  -n ca-ai200challenge-api-dev -g "$RG" \
  --type external

API_URL="https://$(az containerapp show \
  -n ca-ai200challenge-api-dev -g "$RG" \
  --query properties.configuration.ingress.fqdn -o tsv)"

curl -X POST "$API_URL/api/index" \
  -H 'Content-Type: application/json' \
  -d '{
    "workspace_id": "ws_default",
    "chunks": [
      {"document_id": "doc_demo", "ordinal": 0, "text": "Phase 4 는 Cosmos NoSQL 벡터 검색과 AOAI 임베딩을 결합한다."},
      {"document_id": "doc_demo", "ordinal": 1, "text": "파티션 키는 workspaceId 로 워크스페이스 격리와 쓰기 분산을 동시에 만족한다."}
    ]
  }'

# 검증 후 internal 로 되돌림
az containerapp ingress update \
  -n ca-ai200challenge-api-dev -g "$RG" \
  --type internal
```

기대: `200 OK`, `{"indexed":[{"id":"chunk_doc_demo_0",...},{"id":"chunk_doc_demo_1",...}]}`.

### 3) /api/search — VectorDistance top-K

```bash
curl -X POST "$API_URL/api/search" \
  -H 'Content-Type: application/json' \
  -d '{"workspace_id": "ws_default", "query": "워크스페이스 격리는 어떻게 구현?", "top_k": 3}'
```

기대: ordinal=1 청크가 score 가장 낮은 (가장 가까운) 결과로 상단. 응답에 `score` 필드(거리, 낮을수록 가까움) 가 포함.

### 4) Portal Data Explorer 에서 직접 쿼리 (AAD-only 함정)

`az cosmosdb sql query` CLI 명령은 **존재하지 않는다** (`az cosmosdb sql role` / `az cosmosdb sql container` 는 있지만 데이터 쿼리는 SDK/REST/Portal 만 가능). 따라서 Portal Data Explorer 로 검증.

먼저 사용자 본인 objectId 에 Cosmos data plane 역할 임시 부여 (UAMI 만 줘둔 상태이므로):

```bash
az cosmosdb sql role assignment create \
  --account-name cosmos-ai200challenge-dev04 \
  -g "$RG" \
  --role-definition-id 00000000-0000-0000-0000-000000000002 \
  --principal-id "$(az ad signed-in-user show --query id -o tsv)" \
  --scope "/"
```

Portal → `cosmos-ai200challenge-dev04` → Data Explorer → `kb` / `chunks` → New SQL Query:

```sql
SELECT c.id, c.workspaceId, c.documentId, c.ordinal, c.text,
       ARRAY_LENGTH(c.embedding) AS dim
FROM c
WHERE c.workspaceId = 'ws_default'
```

기대: 위 1 단계에서 저장한 청크들이 반환되며 `dim = 3072`. 검증 후 회수:

```bash
az cosmosdb sql role assignment delete \
  --account-name cosmos-ai200challenge-dev04 -g "$RG" \
  --role-assignment-id <위 create 응답의 name 필드 GUID>
```

### DoD

- 위 1~3 통과 시 Phase 4 완료. 4 는 data plane RBAC 동작 추가 검증.

---

## 함정 · 교훈 (배포 후 기록)

> 배포 실행 직후 사용자/Claude 가 함께 채워 넣는 영역. 아래는 **사전 예측되는 후보** — 실제 발생 여부는 배포 후 확인.

- **(예상) `EnableServerless` + `EnableNoSQLVectorSearch` capability 동시 활성화** — 둘은 충돌 없이 공존하지만, capability 중 하나라도 빠지면 다른 하나의 동작이 묶임. Serverless 만 켜면 vector 인덱스 생성 시 `BadRequest`. 두 capability 가 모두 있어야 정상.
- **(예상) `disableLocalAuth=true` 와 azure-cosmos SDK 버전** — 4.5.x 이전 SDK 는 일부 경로에서 키 인증을 fallback 으로 시도하다가 401. `>=4.7.0` 이면 AAD-only 모드에서 안정.
- **(예상) `quantizedFlat` 인덱스의 vector dimension 한계** — 공식 한계 4096, 3072-d 는 안전. 단, 인덱스 빌드 시간 (≥수 분) 동안 일반 쿼리는 정상이지만 vector 쿼리는 결과 0건일 수 있음. "데이터를 넣었는데 검색 결과가 빈 배열" → 인덱스 빌드 진행 중 의심.
- **(예상) AOAI deployment 동시 PUT 시 409** — main.bicep 에서 두 번째 deployment 에 `dependsOn` 을 안 걸면 발생. 본 모듈은 직렬화로 회피.
- **(예상) `customSubDomainName` 누락 시 AAD 인증 실패** — AOAI 는 customSubDomainName 이 없으면 `https://*.cognitiveservices.azure.com/...` 로만 접근 가능, 이 경우 AAD 토큰 audience 불일치. Bicep 에서 `customSubDomainName: name` 을 항상 설정.
- **(예상) `AZURE_CLIENT_ID` 미주입 시 DefaultAzureCredential UAMI 식별 실패** — ACA 위에서 system-assigned 가 없는 UAMI 만 붙어있을 때 AZURE_CLIENT_ID 가 없으면 어떤 ID 를 쓸지 모름. envVars 에 명시 필수.
- **(예상) what-if 의 역할 할당 `Unsupported`** — 매 Phase 공통 노이즈. 실제 배포는 정상.
- **(실측) `disableLocalAuth=true` Cosmos 에서 Portal Data Explorer 도 사용자 RBAC 필요** — Portal Data Explorer 는 AAD 토큰으로 들어가는데, 콘솔을 여는 사용자 objectId 가 Cosmos data plane RBAC 목록에 없으면 `Request blocked by Auth cosmos-... : Request is blocked by ...` 로 즉시 거부. UAMI 에만 `Built-in Data Contributor` 를 주고 사람 사용자를 빠뜨리기 쉬운데, 검증/디버깅 시 `az cosmosdb sql role assignment create -g <RG> --account-name <COSMOS> --role-definition-id 00000000-0000-0000-0000-000000000002 --principal-id $(az ad signed-in-user show --query id -o tsv) --scope "/"` 로 임시 부여 후 회수해야 함. IaC 에 박지 않고 임시 명령으로만 다루는 이유는 **사람 사용자 objectId 는 환경마다 다르고 OSS 레포에 박힐 가치도 없는 운영 정보**여서.

---

## MS Learn 경로 커버리지 — 사용 / 생략

공식 경로: https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-cosmos-db/ (3 모듈)

### 모듈 1 — Cosmos DB for NoSQL 에 대한 쿼리 빌드

| 영역 | 상태 | 비고 |
|---|---|---|
| 리소스 모델 (account / database / container) | ✓ | account=cosmos-..., database=kb, containers=documents/chunks |
| Python `azure-cosmos` SDK CRUD | ✓ | `CosmosStore.upsert_document`, `upsert_chunk`, `read_item` |
| AAD 인증 (DefaultAzureCredential) | ✓ | `disableLocalAuth=true` + sqlRoleAssignments |
| 파티션 키 설계 | ✓ | `/workspaceId` (격리 + 쓰기 분산) |
| Serverless capacity mode | ✓ | 학습 트래픽 비용 최소화 |
| Provisioned (RU/s) + Autoscale | ✗ | 학습 트래픽이라 의미 없음. AI-200 학습 노트로만 기록 |
| Multi-region writes | ✗ | 단일 region (`koreacentral`). 글로벌 분산 학습 포인트는 본 프로젝트 범위 외 |
| Stored procedures / Triggers / UDF | ✗ | 본 프로젝트 워크로드는 SDK + 변경 피드 (Phase 7) 로 충분 |

### 모듈 2 — 벡터 검색 구현

| 영역 | 상태 | 비고 |
|---|---|---|
| `EnableNoSQLVectorSearch` capability | ✓ | `cosmos-account.bicep` |
| `vectorEmbeddingPolicy` + `vectorIndexes` | ✓ | `cosmos-sql-container.bicep` 조건부 |
| `quantizedFlat` 인덱스 | ✓ | 3072-d 균형형. AI-200 시험 단골 |
| `flat` 인덱스 | ✗ | 수십 건 미만 데이터에만 유리, 본 프로젝트엔 의미 없음 |
| `diskANN` 인덱스 | ✗ | 데이터 ≥수만 건일 때 가치. **Phase 5 PG pgvector** 와의 비교에서 다시 도입 검토 |
| `VectorDistance` SQL 쿼리 | ✓ | `cosmos_store.vector_search_chunks` |
| 메타데이터 필터 + 벡터 거리 (하이브리드) | ✓ | `document_id` 옵션 필터 |
| 변경 피드 → 자동 임베딩 파이프라인 | ✗ | Functions 가 **Phase 7** 범위. 거기서 Event Grid + Service Bus 와 함께 도입 |
| Full-text search + vector (RRF) | ✗ | Cosmos NoSQL FTS 는 preview. 본 프로젝트는 Phase 6 시맨틱 캐시 + Phase 5 PG FTS 로 대체 |

### 모듈 3 — 쿼리 성능 최적화

| 영역 | 상태 | 비고 |
|---|---|---|
| 인덱싱 정책 (`includedPaths` / `excludedPaths`) | ✓ | vector 경로 자동 제외 |
| 일관성 수준 선택 (Session) | ✓ | 계정 기본 |
| Eventual 로의 의도적 약화 | ✗ | RAG 응답 측에서 검토는 **Phase 6** 캐시 도입과 함께 |
| 범위 인덱스 / 복합 인덱스 | ✗ | 현재 워크로드는 `id` + pk 기반이라 default 충분. 데이터 증가 시 재방문 |
| 쿼리 RU 분석 (`x-ms-request-charge`) | ✓ | "함정·교훈" 에 측정 결과 기록 예정 |
| TTL 기반 자동 만료 | ✗ | 본 프로젝트 데이터는 영구 보존 가정 |

> **Phase 4 DoD 는 "벡터 검색 + AAD 데이터 plane + AOAI 임베딩 통합"** 로 한정. 변경 피드 자동 임베딩, diskANN 비교, 다중 region 은 의도적으로 Phase 5/7 로 이관.

---

## 체크리스트

- [ ] Phase 4 Bicep 모듈 6개 (cosmos-account/sql-database/sql-container/role-data-contributor/aoai-account/aoai-deployment/role-aoai-user) + main.bicep/param 작성
- [ ] `az bicep build` 경고 없음
- [ ] `az deployment group what-if` 로 변경 내역 검토
- [ ] `apps/api` 이미지 `0.4.0` 빌드·푸시 (`docker build --platform linux/amd64 ... && docker push ...`)
- [ ] `az deployment group create` 로 Phase 4 배포 완료
- [ ] `az containerapp revision list` 로 새 리비전 Healthy 확인 (image=:0.4.0, traffic=100)
- [ ] `POST /api/index` 으로 chunks 2건 임베딩 + 저장 동작 확인
- [ ] `POST /api/search` 으로 vector top-K 가 의도된 순서로 반환 확인
- [ ] `az cosmosdb sql query` 로 Cosmos 콘솔에서도 직접 쿼리 가능 확인
- [ ] 본 문서 "함정 · 교훈" 에 실제 삽질 기록 추가
