# 공통 함정 모음

본 워크샵 전체에서 학습자가 자주 막혔던 함정을 모았습니다. 각 세션 문서의 `## 주의` 와 중복되더라도, 디버깅 시 한곳에서 빠르게 검색할 수 있도록 합쳐둡니다.

> [!NOTE]
> 출처 표기 (`session-NN`) 는 가장 자주 마주치는 세션입니다. 다른 세션에서도 발생할 수 있습니다.

---

## 인증 · RBAC

### Cosmos data plane RBAC ≠ control plane (session-01·session-04)

- 증상 — `Cosmos DB Account Reader` 만 부여한 상태에서 Data Explorer 가 401 응답, `query_items` 도 403 응답
- 원인 — Cosmos DB 는 control plane (계정·DB·컨테이너 정의) 과 data plane (실제 문서 CRUD) 의 RBAC 가 완전히 별개
- 회피 — 본인에게 임시 부여 후, 사용 끝나면 회수

  ```bash
  # 본인 임시 grant
  COSMOS=$(az cosmosdb show -n cosmos-ai200ws-dev -g rg-ai200ws-dev --query id -o tsv)
  OID=$(az ad signed-in-user show --query id -o tsv)
  az cosmosdb sql role assignment create \
    --account-name cosmos-ai200ws-dev \
    --resource-group rg-ai200ws-dev \
    --scope "/" \
    --principal-id $OID \
    --role-definition-id 00000000-0000-0000-0000-000000000002  # Data Contributor
  ```

### Entra ID username 자리에 principal objectId 사용 (session-03)

- 증상 — Redis 연결이 `NOAUTH` 또는 `WRONGPASS`
- 원인 — Entra ID username 자리에 User Assigned Managed Identity 의 `clientId` 를 사용. `clientId` 와 `principalId` 둘 다 UUID 형식이라 헷갈리기 쉬움
- 회피 — **`principalId` (objectId)** 사용. User Assigned Managed Identity 의 경우 `az identity show --query principalId` 로 확인

### Application Insights AUTH 모드는 Monitoring Metrics Publisher 역할 필수 (session-06)

- 증상 — 텔레메트리가 Application Insights 에 노출되지 않음
- 원인 — `AuthenticationString=Authorization=AAD` 모드인데 User Assigned Managed Identity 에 `Monitoring Metrics Publisher` 역할이 부여되지 않음
- 회피 — 해당 역할을 부여하거나, 학습 단계에서는 instrumentation key 사용으로 대체

### `enableRbacAuthorization=true` Key Vault 의 Portal Data Explorer 접근 불가 (session-05)

- 증상 — Portal 에서 "Request is blocked" 메시지가 노출. 구독 owner 도 동일 현상
- 원인 — RBAC-only Key Vault 는 본인에게도 명시적으로 `Key Vault Secrets User` 등의 역할이 부여되어 있어야 함
- 회피 — 본인에게 임시 부여하거나 CLI (`az keyvault secret list`) 사용

---

## Bicep · IaC

### `bicepparam` 에 사용자 식별 정보 작성 금지 (전체)

- 증상 — 포트폴리오 공개 시 본인 IP · objectId · 이메일이 git history 에 영구히 노출
- 원인 — `devClientIpAddress`, `userObjectId`, `userPrincipalName` 등을 `bicepparam` 기본값에 작성해둠
- 회피 — 기본값을 빈 문자열 또는 `0.0.0.0/0` 으로 두고, 배포 명령을 실행할 때마다 `--parameters key=value` 인자로 직접 넘겨주는 방식으로 전달

  ```bash
  az deployment group create ... \
    --parameters userObjectId=$(az ad signed-in-user show --query id -o tsv) \
    --parameters devClientIpAddress=$(curl -s ifconfig.me)
  ```

### Azure OpenAI 동시 생성 시 409 Conflict (session-00)

- 증상 — `Conflict — Another operation is in progress`
- 원인 — 같은 Azure OpenAI 계정에 두 개의 모델 deployment 를 동시에 생성하려 함
- 회피 — Bicep `dependsOn: [aoaiChatDeployment]` 로 두 번째 deployment 가 순차적으로 실행되도록 지정

### 모델 deprecation — 신규 deployment 생성 차단 (session-00)

- 증상 — `az deployment sub what-if` preflight 에서 `ServiceModelDeprecated` 오류. 실측 사례 — `gpt-4o-mini` (version `2024-07-18`) 가 2026-03-31 부로 신규 deployment 생성 차단 (기존 deployment 의 추론은 2026-10-01 까지 동작하지만 새로 만들 수 없음)
- 원인 — Azure OpenAI 모델은 버전별 수명 주기 (deprecation 일정) 가 있어, 신규 deployment 생성 차단일이 지나면 같은 Bicep 이라도 재배포가 실패함
- 회피 — 현재 배포 가능한 모델을 확인하고 후속 모델로 교체. 본 워크샵은 `gpt-5-mini` (version `2025-08-07`) 로 교체함

  ```bash
  az cognitiveservices model list -l koreacentral \
    --query "[?model.format=='OpenAI'].{name:model.name, version:model.version}" -o table
  ```
- 연계 함정 — 교체 모델의 SKU 지원 여부도 확인 필요. gpt-5 계열은 리전 `Standard` SKU 미지원으로 preflight 에서 `InvalidResourceProperties: The specified SKU 'Standard' of account deployment is not supported by the model 'gpt-5-mini'` 오류가 발생. deployment 의 `sku.name` 을 `GlobalStandard` 로 지정해야 함

### Cosmos serverless 는 capability 가 아니라 `capacityMode` (session-01)

- 증상 — `what-if` · 배포에서 `BadRequest: Capability EnableServerless is not allowed in API version beyond 2024-05-15-preview. Use CapacityMode instead`
- 원인 — API 버전 `2024-05-15-preview` 이후로는 serverless 가 `capabilities` 배열의 `EnableServerless` 가 아니라 `properties.capacityMode: 'Serverless'` 로 지정
- 회피 — `cosmos-account.bicep` 처럼 `properties.capacityMode` 사용

  ```bicep
  resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' = {
    properties: {
      capacityMode: 'Serverless'
    }
  }
  ```

### `subscription()` 과 `resourceGroup()` scope 혼동 (session-00)

- 증상 — `The scope of the deployment is mismatch`
- 원인 — subscription scope 에서 `resourceGroup()` 함수를 사용했거나, 그 반대 상황 발생
- 회피 — 파일 첫 줄에 `targetScope = 'subscription'` 또는 `'resourceGroup'` 을 명시하고 일관된 함수만 사용. Resource Group 안의 자원은 `resourceGroup()` scope 으로 모듈 호출

### 이름 충돌 (글로벌 unique: Azure Container Registry · Key Vault · Storage) (session-01·session-04)

- 증상 — `The storage account named ... is already taken`
- 원인 — 글로벌 unique 이름이 다른 구독에서 이미 사용 중
- 회피 — `uniqueString(resourceGroup().id)` 접미사 강제

  ```bicep
  var acrName = 'acrai200ws${env}${uniqueString(resourceGroup().id)}'
  ```

### Soft-delete 7일 이름 충돌 (Key Vault / App Configuration) (session-05)

- 증상 — 자원 정리 후 재배포 시 `name already taken`
- 원인 — Key Vault / App Configuration 은 soft-delete 후 7일 동안 같은 이름 재생성 불가
- 회피 — dev 환경도 `purgeProtectionEnabled: true` 설정 + 정리 시 `--purge` 옵션 사용 (Key Vault) 또는 접미사를 한 단계 올림

---

## 컨테이너 · 이미지

### ARM Mac 에서 `--platform linux/amd64` 옵션 누락 (session-01·session-04·session-07)

- 증상 — Azure Container Apps / Azure Functions / Azure Kubernetes Service 안에서 `exec format error`. silent fail 케이스도 발생
- 원인 — ARM 호스트에서 빌드한 ARM64 이미지를 amd64 노드에서 실행
- 회피 — 모든 `docker build` 명령에 `--platform linux/amd64` 강제

  ```bash
  docker build --platform linux/amd64 -t myimg:tag .
  ```
- 대안 — `az acr build` 로 클라우드에서 빌드 (Docker Desktop 불필요)

### 자체 이미지가 ACR 에 없는 첫 배포는 `MANIFEST_UNKNOWN` 으로 실패 — placeholder 이미지 패턴 (session-01)

- 증상 — Bicep 으로 Container App 을 처음 만들 때 아직 빌드 · push 하지 않은 자체 이미지 (예: `api:s01`) 를 참조하면 배포가 `ContainerAppOperationError: MANIFEST_UNKNOWN: manifest tagged by "s01" is not found` 로 실패하고 deployment 전체가 `Failed` 가 됨
- 원인 — 자체 이미지는 빌드 · push 후에야 ACR 에 존재. IaC 가 그 이미지를 참조하는 시점에는 ACR 에 manifest 가 없음
- 회피 — IaC 와 앱 배포를 분리하는 Azure Container Apps 권장 패턴 사용. Bicep 모듈에서 이미지 파라미터가 비면 public placeholder 이미지 (`mcr.microsoft.com/k8se/quickstart:latest`) 로 먼저 생성하고, 이미지 빌드 · push 후 `az containerapp update --image` 로 교체

  ```bicep
  var placeholderImage = 'mcr.microsoft.com/k8se/quickstart:latest'
  var resolvedImage = empty(containerImage) ? placeholderImage : '${acrLoginServer}/${containerImage}'
  ```
- 함의 — placeholder 이미지는 본 워크샵이 지정한 포트 (8000 · 3000) 를 듣지 않으므로 첫 revision 이 `ActivationFailed` 로 표시될 수 있음. deployment 자체는 `Succeeded` 이고 `az containerapp update` 로 실제 이미지를 올리면 새 revision 이 `Healthy` 가 됨. 배포 실패로 오해하지 않음

### `az configure --defaults group=...` 잔여 효과 (session-01)

- 증상 — `az acr login` 실패. 메시지가 인증 문제처럼 보이지만 실제 원인은 다름
- 원인 — 이전에 설정한 default group 이 다른 명령에 잘못된 컨텍스트를 주입
- 회피 — `az configure --defaults group=""` 로 초기화 후 재시도

### Azure Functions Flex Consumption 신 스키마 (session-04)

- 증상 — 환경변수 `FUNCTIONS_WORKER_RUNTIME=python` 이 무시되고 runtime detection 실패
- 원인 — Flex Consumption 은 `functionAppConfig.runtime.name` 신 스키마 사용
- 회피 —

  ```bicep
  resource func 'Microsoft.Web/sites@2024-04-01' = {
    properties: {
      functionAppConfig: {
        runtime: { name: 'python', version: '3.12' }
        scaleAndConcurrency: { ... }
      }
    }
  }
  ```

### Storage `allowSharedKeyAccess=false` 일 때 Azure Functions 부팅 실패 (session-04)

- 증상 — Azure Functions 가 시작 직후 stop 상태로 전환
- 원인 — Azure Functions 호스트가 Storage account 에 SharedKey 로 접근하려는데 차단됨
- 회피 — OAC (Object Access Control) + User Assigned Managed Identity 에 `Storage Blob Data Owner` + `Storage Queue Data Contributor` + `Storage Table Data Contributor` 역할 부여

### `aiohttp` 누락 시 비동기 인증 ImportError 로 부팅 실패 (session-01)

- 증상 — 컨테이너가 시작 직후 죽음. 로그에 `ImportError: aiohttp package is not installed. Use pip install aiohttp to install it.`
- 원인 — `azure.identity.aio.DefaultAzureCredential` (async credential) 이 async HTTP transport 로 `aiohttp` 를 요구. `pyproject.toml` 에 명시하지 않으면 이미지에 포함되지 않음
- 회피 — `pyproject.toml` 의존성에 `aiohttp>=3.10.0` 명시

  ```toml
  dependencies = [
      "azure-identity>=1.19.0",
      "aiohttp>=3.10.0",  # azure.identity.aio 의 async transport 가 요구
  ]
  ```

---

## Azure OpenAI · SDK

### gpt-5 계열 reasoning 모델은 `max_tokens` · 커스텀 `temperature` 미지원 (session-01)

- 증상 — chat completion 호출이 `BadRequest` 로 실패. 실측 에러 — `Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead.`. `temperature` 를 1 이외 값으로 주면 별도 거부
- 원인 — gpt-5 계열 reasoning 모델은 토큰 상한 파라미터를 `max_completion_tokens` 로 받고, `temperature` 는 기본값 (1) 만 허용
- 회피 — `max_tokens` 대신 `max_completion_tokens` 사용, `temperature` 는 생략. reasoning 토큰이 출력 토큰과 함께 차감되므로 상한을 여유 있게 둠

  ```python
  response = await client.chat.completions.create(
      model=settings.azure_openai_chat_deployment,
      messages=messages,
      max_completion_tokens=2048,  # max_tokens 아님. temperature 는 생략 (기본 1)
  )
  ```

---

## 벡터 · 인덱싱

### `vector(3072)` HNSW 인덱스 생성 시 2000 차원 한계 (session-02)

- 증상 — `CREATE INDEX ... USING hnsw` 실패. `dimension > 2000 not supported`
- 원인 — pgvector 의 `vector` 타입 HNSW 인덱스는 2000 차원 한계
- 회피 — **`halfvec(3072)`** 사용 + `halfvec_cosine_ops`

  ```sql
  CREATE TABLE chunks (embedding halfvec(3072));
  CREATE INDEX ON chunks USING hnsw (embedding halfvec_cosine_ops);
  ```

### Cosmos vector policy 는 컨테이너 생성 시점에만 설정 가능 (session-01)

- 증상 — 기존 컨테이너에 vector policy 추가 시 실패
- 원인 — Cosmos vector policy 는 immutable
- 회피 — 컨테이너 drop & recreate. 재시도 시 시드 데이터 백업 필수

### RediSearch DB 는 `evictionPolicy=NoEviction` 필수 (session-03)

- 증상 — 인덱스가 작동하지 않음. `FT.SEARCH` 결과가 stale
- 원인 — 다른 eviction policy 가 인덱스 메타 데이터와 충돌
- 회피 — Bicep 에서 `evictionPolicy: 'NoEviction'` 명시

### `register_vector_async` chicken-and-egg (session-02)

- 증상 — 앱 시작 시 PoolTimeout (30s) 후 dead
- 원인 — 풀 초기화 콜백에서 `register_vector_async` 호출. DB 에 vector extension 이 없으면 실패하고 풀 초기화 자체가 실패
- 회피 — 부트스트랩 스크립트로 `CREATE EXTENSION vector` 를 먼저 실행하고, 그 다음 앱을 시작

### RediSearch TAG 필드의 하이픈 escape 누락 (session-03)

- 증상 — 캐시가 항상 miss (hit rate = 0%)
- 원인 — TAG 필드 값에 `-` 가 있는데 escape 처리하지 않음. 쿼리 파서가 잘못 해석
- 회피 — TAG 값에서 하이픈을 `\\-` 로 escape (Python f-string 안에서는 `\\\\-` 형태)

---

## 비동기 · 메시징

### Cosmos change feed lease container silent fail (session-04)

- 증상 — Azure Functions 가 정상으로 보이고 에러도 0건이지만, trigger 가 fire 하지 않음
- 원인 — lease container 자동 생성이 control plane RBAC 부재로 silent 실패
- 회피 — **Bicep 으로 lease container 를 사전 생성** 필수

  ```bicep
  resource leases 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-08-15' = {
    name: 'leases'
    properties: { resource: { id: 'leases', partitionKey: { paths: ['/id'] } } }
  }
  ```

### Cosmos `query_items` 에 `partition_key` 명시 (session-04)

- 증상 — RU 가 폭주하고 throttling 429 발생
- 원인 — cross-partition query 가 모든 파티션을 fan-out 스캔
- 회피 — 가능하면 항상 `partition_key` 명시

### Internal Azure Container Apps ingress 는 외부에서 HTTP 404 응답 (session-01)

- 증상 — "앱이 죽었나?" 로 오해 가능. 실제로는 정상 동작
- 원인 — internal-only ingress 는 외부 트래픽을 TCP 차단하지 않고 라우팅하지 않음. 결과적으로 404 응답
- 회피 — 외부 접근이 필요하면 `ingress.external = true`. 외부에서 테스트할 때는 ingress 를 일시적으로 토글

---

## OpenTelemetry · 관찰 가능성

### `configure_azure_monitor` 는 FastAPI app 생성 전에 호출 (session-01·session-06)

- 증상 — 트래픽은 200 OK 인데 Application Insights `requests` 테이블이 0 건. 메트릭만 기록되고 요청 span 이 전혀 잡히지 않음
- 원인 — `configure_azure_monitor` 를 `lifespan` (= `app = FastAPI()` 생성 후) 에서 호출. FastAPI 자동 계측은 `FastAPI.__init__` 을 패치하는 방식이라, 이미 만들어진 app 인스턴스에는 적용되지 않음
- 회피 — 계측을 import 최상단 (app 생성 전) 에서 활성화

  ```python
  import os

  from azure.monitor.opentelemetry import configure_azure_monitor

  if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
      configure_azure_monitor()

  from fastapi import FastAPI  # noqa: E402

  app = FastAPI()  # 계측이 이미 켜진 뒤에 생성
  ```

### `azure-monitor-opentelemetry` 는 httpx · aiohttp 를 자동 계측하지 않음 (session-01)

- 증상 — FastAPI 요청 span 은 잡히는데, Azure OpenAI · Cosmos 호출이 dependency span 으로 남지 않아 Transaction search 의 span 트리가 비어 보임
- 원인 — `azure-monitor-opentelemetry` 는 FastAPI · requests · urllib 등은 자동 계측하지만 httpx · aiohttp 는 자동 활성화하지 않음. Azure OpenAI (httpx) · Cosmos (aiohttp) 호출이 누락됨
- 회피 — instrumentation 패키지를 의존성에 추가하고 명시적으로 instrument

  ```python
  from opentelemetry.instrumentation.aiohttp_client import AioHttpClientInstrumentor
  from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

  HTTPXClientInstrumentor().instrument()
  AioHttpClientInstrumentor().instrument()
  ```

  `pyproject.toml` 에 `opentelemetry-instrumentation-httpx` · `opentelemetry-instrumentation-aiohttp-client` 를 추가

---

## Azure Kubernetes Service

### Custom kubelet identity 사용 시 control plane 도 UserAssigned 강제 (session-07)

- 증상 — `CustomKubeletIdentityOnlySupportedOnUserAssignedMSICluster`. `what-if` 가 이 오류를 사전에 잡지 못함
- 원인 — kubelet identity 를 명시하면 control plane identity 도 User Assigned Managed Identity 여야 함
- 회피 — Bicep 양쪽 모두 `identity: { type: 'UserAssigned' }`

### `addonProfiles.omsagent` 단독으로는 Log Analytics Workspace 에 데이터가 흐르지 않음 (session-07)

- 증상 — Azure Kubernetes Service → Insights 가 `no data`. 디버깅에 가장 오래 걸린 함정 (실제 측정 34시간)
- 원인 — 최신 Container Insights 는 DCR (Data Collection Rule) + DCRA (Data Collection Rule Association) 명시 선언이 필요
- 회피 — Bicep 에 `Microsoft.Insights/dataCollectionRules` + `Microsoft.Insights/dataCollectionRuleAssociations` 모두 선언

### `koreacentral` DSv5 vCPU 할당량 = 0 (session-07)

- 증상 — Azure Kubernetes Service 배포 시 quota exceeded
- 원인 — `koreacentral` 의 DSv5 Family 기본 vCPU 가 0. 별도 신청이 필요
- 회피 — DSv3 (기본 10 vCPU) 사용

---

## 비용 · 운영

### idle 자원의 누적 비용 (전체)

- 측정 (이전 학습 단계에서 dev 환경 7일 기준)
  - Redis Enterprise Memory_M10: **~₩11,680/일** (전체 청구의 75%)
  - Azure Container Apps Container App (min replica 1): ~₩1,743/일
  - Azure Kubernetes Service LB + Public IP: ~₩1,125/일
  - PostgreSQL B1ms: ~₩700/일
- 함의 — dev 환경이라도 compute 가 있는 자원은 시간당 누적
- 회피 — 본 워크샵 진행이 끝나면 즉시 [cleanup.md](../cleanup.md) 수행

### 컨테이너 이미지는 Resource Group 삭제 후에도 남음

- 증상 — Resource Group 삭제 후 재배포 시 Azure Container Registry 가 남아 이미지 history 가 보존됨. 좋은 동작이지만 학습자가 인지하지 못할 수 있음
- 원인 — Azure Container Registry 보존이 [CLAUDE.md](../../CLAUDE.md) 의 자원 라이프사이클 원칙. 학습 자산으로 의도된 보존
- 회피 — 의식적으로 Azure Container Registry 는 후속 진행에서도 재사용 가능하다는 점을 인지

---

## 로컬 도구

### macOS 에서 Python 이 `SSLCertVerificationError` — certifi CA 번들 지정 (session-01)

- 증상 — macOS 에서 로컬 스크립트 (예: Cosmos 시드) 실행 시 `azure.core.exceptions.ServiceRequestError: ... SSLCertVerificationError: [SSL: CERTIFICATE_VERIFY_FAILED] unable to get local issuer certificate`. `az` CLI 는 정상인데 Python 의 `aiohttp` 만 실패
- 원인 — macOS 의 Python 이 시스템 CA 번들을 찾지 못해 Azure 엔드포인트의 인증서 체인을 검증하지 못함
- 회피 — `certifi` 가 제공하는 CA 번들 경로를 `SSL_CERT_FILE` 환경변수에 지정한 뒤 재실행

  ```bash
  export SSL_CERT_FILE=$(uv run --project apps/api python -c "import certifi; print(certifi.where())")
  ```

---

## 그 외 작은 함정

- **`linux App Service Plan`** Bicep `properties.reserved=true` 필수 (공식 문서에서 분명히 명시되지 않음) — Azure Container Apps 가 아닌 App Service 시나리오에서 발생 (session-01 관련)
- **Hatchling 빌드** 는 Dockerfile 에 `COPY README.md` 명령이 필요. 누락되면 `uv sync` 실패
- **KEDA metadata** 는 반드시 string 으로 (`string(httpConcurrency)`). 숫자 타입으로 두면 Azure Container Apps 가 reject (session-01)
- **Log Analytics `sharedKey`** 는 `@secure()` output 으로 노출. Bicep 작성 시 주의
- **Cosmos `quantizedFlat` 인덱스 비동기 빌드** — 빌드 중 쿼리는 0개 결과 반환 (에러 아님). "데이터가 안 들어갔나" 로 오진하기 쉬움 (session-01)
- **PostgreSQL 파라미터 set 순서** 는 알파벳 정렬에 의존. `pgbouncer.enabled` 가 sub-param 들보다 먼저 와야 함 (session-02)
- **App Configuration Sentinel refresh** 는 30~60초 폴링 방식. 즉시 반영되지 않으므로, 실시간 반영이 필요하면 push 모델을 별도 구성 (session-05)
