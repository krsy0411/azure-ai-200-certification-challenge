# 공통 함정 모음

본 문서는 챌린지 전체 함정·주의의 **단일 Source of Truth** 입니다. 세션 문서에는 더 이상 별도 `## 주의` 섹션이 없으며, 진행 중 막혔을 때는 여기서 한곳에서 검색합니다. 카테고리별로 묶고 각 항목에 가장 자주 마주치는 세션 태그 (`session-NN`) 를 달아두었습니다.

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

### `az account get-access-token` 은 `--resource` (not `--resource-url`) (session-02)

- 증상 — Entra 토큰으로 `psql` 접속 시 토큰 발급 명령이 `ERROR: unrecognized arguments: --resource-url https://ossrdbms-aad.database.windows.net` 으로 실패
- 원인 — `az account get-access-token` 은 `--resource-url` 이 아니라 `--resource` 인자를 받음
- 회피 — `--resource https://ossrdbms-aad.database.windows.net` 으로 호출

  ```bash
  PGPASSWORD=$(az account get-access-token \
    --resource https://ossrdbms-aad.database.windows.net \
    --query accessToken -o tsv)
  ```

### PostgreSQL Entra 전용 인증 — psql 접속 3대 전제 (session-02)

- 증상 — `psql` 접속이 거부 (FATAL) 되거나 timeout 으로 멈추거나 인증에 실패. PostgreSQL Flexible Server 가 Entra ID 전용 인증 (`passwordAuth` 비활성) 이라 비밀번호 접속이 아예 불가
- 원인 — 다음 세 전제 중 하나라도 어긋남
  - **Entra 관리자 = `userObjectId`** — 배포 명령에 `userObjectId` 를 넘기지 않으면 관리자 부여 모듈이 `if (!empty(userObjectId))` 조건으로 건너뛰어, 본인이 관리자로 등록되지 않아 접속 거부
  - **firewall = 본인 IP** — 배포 후 네트워크가 바뀌어 (다른 Wi-Fi · VPN 등) IP 가 달라지면 firewall 에 막혀 timeout
  - **1시간 토큰** — `az account get-access-token` 으로 받은 Entra ID 토큰은 약 1시간 후 만료. 만료된 토큰을 `PGPASSWORD` 로 쓰면 인증 실패
- 회피 — 배포 시 `userObjectId=$OID` 를 전달, IP 가 바뀌면 `az postgres flexible-server firewall-rule create` 로 추가하거나 `devClientIpAddress` 를 갱신해 재배포, 토큰은 만료 전 재발급 후 재접속

  ```bash
  PGPASSWORD=$(az account get-access-token \
    --resource https://ossrdbms-aad.database.windows.net \
    --query accessToken -o tsv)
  ```

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

### `koreacentral` 리전 모델 미가용 (session-00)

- 증상 — 배포 시 일부 모델이 `koreacentral` 에서 가용하지 않아 deployment 생성이 실패
- 원인 — Azure OpenAI 모델은 리전별로 가용 여부가 다름. 기본 리전 `koreacentral` 에 원하는 모델이 없을 수 있음
- 회피 — 배포 명령에 `--parameters aoaiLocation=eastus` (또는 `japaneast`) 를 추가해 Azure OpenAI 리전만 분리

  ```bash
  az deployment sub create ... \
    --parameters aoaiLocation=eastus
  ```

### 모델 deprecation — 신규 deployment 생성 차단 (session-00)

- 증상 — `az deployment sub what-if` preflight 에서 `ServiceModelDeprecated` 오류. deprecation 일정이 지난 모델·버전을 deployment 로 참조하면 발생 (기존 deployment 의 추론은 retirement 일까지 동작하지만 신규 생성은 차단)
- 원인 — Azure OpenAI 모델은 버전별 수명 주기 (deprecation → retirement 일정) 가 있어, 신규 deployment 생성 차단일이 지나면 같은 Bicep 이라도 재배포가 실패함. 모델별 일정은 공식 [model retirement schedule](https://learn.microsoft.com/azure/ai-foundry/openai/concepts/model-retirement-schedule) 에서 확인
- 회피 — 배포 전 아래 명령으로 현재 배포 가능한 모델·버전을 확인하고, 차단된 모델은 후속 버전으로 교체. 본 챌린지는 `gpt-4o-mini` (version `2024-07-18`) 와 `gpt-5-mini` (version `2025-08-07`) 를 사용

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

### Soft-delete 7일 이름 충돌 — Key Vault 는 purge protection 때문에 purge 도 불가 (session-00·session-05)

- 증상 — 자원을 정리 (RG 삭제 등) 한 뒤 같은 이름으로 재배포하면 `VaultAlreadyExists` / `name already taken`. 특히 Key Vault 는 정리 직후 7일간 어떤 방법으로도 재생성·purge 가 안 됨
- 원인 — Key Vault · App Configuration 은 soft-delete 후 보존 기간 동안 이름이 전역 예약됨. 본 챌린지 Key Vault 는 `enablePurgeProtection: true` 이고 이름이 `uniqueString(subscription().id, projectId, env)` (고정 시드) 라, ① 재배포해도 항상 같은 이름이 나오고 ② purge protection 때문에 보존 기간 (7일) 이 지나기 전엔 누구도 (Microsoft 포함) purge 불가. KV 모듈에 `createMode: 'recover'` 가 없어 같은 이름 재배포는 실패한다. **즉 purge protection 은 이 충돌을 "회피" 하는 게 아니라 오히려 강제한다** — purge 로 즉시 이름을 비울 수 없게 만들기 때문 (이전 문서의 "purge protection 켜두면 충돌 회피" 설명은 사실과 반대였다)
- 회피 —
  - **Key Vault 는 정리 대상에서 제외하고 그대로 보존** — 비용이 사실상 0 이고 후속 세션·재배포가 그대로 재사용한다. `/phase-cleanup` 도 KV 를 보존하며, 전체 teardown 시에도 KV 만 남기고 나머지를 지운다 ([CLAUDE.md](../../CLAUDE.md) §7)
  - 실수로 KV 를 지웠다면 — `az keyvault recover -n <name> -l <region>` 로 복구하거나 (soft-delete 시 RBAC 역할 할당은 사라지므로 재배포로 재부여 필요), 7일 경과 후 자동 purge 를 기다린 뒤 재배포
  - App Configuration 은 purge protection 이 없어 `az appconfig purge -n <name> -y` 로 즉시 이름 회수 가능. 데이터 자원 (Cosmos · PostgreSQL 등) 의 soft-delete 충돌은 접미사를 한 단계 올려 회피 (`dev04` → `dev06`)

### Cosmos serverless 는 capability 가 아니라 `capacityMode` 속성 (session-01)

- 증상 — `BadRequest: Capability EnableServerless is not allowed in API version beyond 2024-05-15-preview. Used API Version: 2024-12-01-preview. Use CapacityMode instead to serverless`
- 원인 — API `2024-12-01-preview` 부터 serverless 를 `capabilities: [{ name: 'EnableServerless' }]` 로 켤 수 없다. `databaseAccount` 의 `capacityMode` 속성으로 지정해야 함
- 회피 — capabilities 에는 `EnableNoSQLVectorSearch` 만 두고 `properties.capacityMode` 설정

  ```bicep
  resource cosmos '...@2024-12-01-preview' = {
    properties: {
      capacityMode: 'Serverless'
      capabilities: [ { name: 'EnableNoSQLVectorSearch' } ]
    }
  }
  ```

### App Configuration `disableLocalAuth=true` 는 ARM/Bicep keyValue 시드와 양립 불가 (session-05)

- 증상 — 배포 시 keyValues·featureFlags 가 `Conflict: ... configuration store is using local authentication mode and local authentication is disabled. please use pass-through authentication mode` 로 실패. 배포자가 `App Configuration Data Owner` 를 가져도 실패 (RBAC 전파 문제가 아님)
- 원인 — Azure 는 local auth 가 비활성화된 App Configuration store 에 ARM/Bicep 으로 key-value 를 생성할 수 없다 (문서화된 제약)
- 회피 — 둘 중 하나
  - store 를 `disableLocalAuth: false` 로 두고 ARM 으로 시드 — store 가 시크릿을 안 담으면(endpoint·host·KV 참조 URI·플래그만) 무난. 앱은 여전히 endpoint + UAMI(Entra) 로 읽으므로 접근키 미사용
  - 또는 `disableLocalAuth: true` 유지 + keyValues 를 ARM 대신 `az appconfig kv set --auth-mode login` / `az appconfig feature set --auth-mode login` (Entra) 으로 시드

### 피처 플래그 contentType 에 `;charset=utf-8` 누락 (session-05)

- 증상 — `az appconfig feature list` 가 비어있고 (`feature disable` 는 "does not exist"), 앱의 `is_enabled()` 도 항상 false. `az appconfig kv list` 에는 `.appconfig.featureflag/<name>` 키가 보임
- 원인 — Bicep 으로 플래그를 쓸 때 contentType 을 `application/vnd.microsoft.appconfig.ff+json` 으로만 지정. CLI·SDK 는 charset 까지 정확히 일치해야 feature flag 로 인식
- 회피 — `contentType: 'application/vnd.microsoft.appconfig.ff+json;charset=utf-8'`

### PgBouncer 는 Burstable 등급 미지원 (session-02)

- 증상 — 서버 측 PgBouncer 를 켜면 `ServerParameterToCMSPgBouncerNotSupportedForBurstable` 오류로 배포 실패
- 원인 — PostgreSQL Flexible Server 의 내장 PgBouncer 는 Burstable 컴퓨트 등급에서 지원되지 않음. 학습용으로 Burstable 등급을 사용하면 충돌
- 회피 — 서버 측 PgBouncer 대신 클라이언트 측 `psycopg_pool` 로 연결 풀을 관리

### PostgreSQL 자식 자원 동시 생성 시 409 Conflict (session-02)

- 증상 — 관리자 · 서버 파라미터 · firewall rule · 데이터베이스를 동시에 생성하면 서버가 Updating 상태라 `409 Conflict`
- 원인 — Flexible Server 의 자식 자원들을 한 번에 PUT 하면 서버가 아직 이전 변경을 적용 중이라 충돌
- 회피 — `main.bicep` 의 `dependsOn` 으로 자식 자원 생성을 순차화

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
- 함의 — placeholder 이미지는 본 챌린지가 지정한 포트 (8000 · 3000) 를 듣지 않으므로 첫 revision 이 `ActivationFailed` 로 표시될 수 있음. deployment 자체는 `Succeeded` 이고 `az containerapp update` 로 실제 이미지를 올리면 새 revision 이 `Healthy` 가 됨. 배포 실패로 오해하지 않음

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

### PostgreSQL `SET LOCAL` 은 파라미터 바인딩 불가 (session-02)

- 증상 — `hnsw.ef_search` 등을 `SET LOCAL hnsw.ef_search = %s` 로 바인딩하면 `psycopg.errors.SyntaxError: syntax error at or near "$1"` 으로 실패
- 원인 — PostgreSQL 의 `SET` / `SET LOCAL` 명령은 prepared statement 파라미터 (`$1`) 를 지원하지 않음. psycopg 가 `%s` 를 `$1` 로 변환해 보내면서 구문 오류 발생
- 회피 — 값을 직접 삽입. 정수형 값은 `int()` 로 캐스팅해 SQL injection 을 막고 f-string 으로 삽입

  ```python
  await conn.execute(f"SET LOCAL hnsw.ef_search = {int(ef_search)}")
  ```

### RediSearch TAG 필드의 하이픈 escape 누락 (session-03)

- 증상 — 캐시가 항상 miss (hit rate = 0%)
- 원인 — TAG 필드 값에 `-` 가 있는데 escape 처리하지 않음. 쿼리 파서가 잘못 해석
- 회피 — TAG 값에서 하이픈을 `\\-` 로 escape (Python f-string 안에서는 `\\\\-` 형태)

### RediSearch COSINE 은 유사도가 아니라 distance 를 반환 (session-03)

- 증상 — 유사도 컷오프를 적용했는데 캐시가 전부-hit 또는 전부-miss 가 되고 원인 추적이 어려움
- 원인 — RediSearch 의 COSINE 은 distance (0 = 동일 ~ 2 = 반대) 를 반환. 유사도와 방향이 반대라 컷오프 비교를 그대로 하면 전부 통과하거나 전부 탈락
- 회피 — 유사도 컷오프는 `1 - distance` 로 환산해 비교 (예: 유사도 ≥ 0.62 → `1 - distance ≥ 0.62`)

### FT.SEARCH 는 Hash 키만 인덱싱 (session-03)

- 증상 — 캐시가 항상 miss. 값은 저장되는데 검색에 잡히지 않음
- 원인 — RediSearch 인덱스는 인덱스 prefix 와 일치하는 Redis Hash 키만 인덱싱. 일반 `SET` 으로 저장한 값은 인덱싱되지 않음
- 회피 — 임베딩 · 답변 · 출처를 한 Hash 키에 함께 저장 (`hset`)

---

## 비동기 · 메시징

### Cosmos change feed lease container 자동 생성 차단 (session-04)

- 증상 — trigger 가 fire 하지 않음. `create_lease_container_if_not_exists=True` 로 두면 함수가 start 하지 못하고 `403 Forbidden` (Substatus 5300)
- 원인 — Entra ID (관리 ID) 인증에서 lease container 생성은 data plane 이 아니라 control plane (비-데이터) 작업이라 차단됨. lease container 가 없으면 자동 생성이 거부되어 trigger 가 동작하지 못함
- 회피 — **Bicep 으로 lease container 를 사전 생성** 하고, trigger 는 `create_lease_container_if_not_exists=False` 로 둔다 (본 챌린지 구성)

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

### Event Grid Blob 구독에 subject 필터 누락 → 배포 컨테이너까지 트리거 (session-04)

- 증상 — 업로드하지 않은 blob 까지 인제스션 시도. 큐에 `BlobNotFound` 메시지가 누적되고, `func azure functionapp publish` 직후 다발 발생
- 원인 — system topic 구독이 `subjectBeginsWith` 없이 모든 컨테이너의 `BlobCreated` 를 수신. 함수 배포 zip 이 올라가는 `deployments` 컨테이너 이벤트까지 큐로 전달되는데, 그 blob 은 곧 삭제되어 함수가 다운로드 시 404
- 회피 — 구독 필터를 documents 컨테이너로 제한

  ```bicep
  filter: {
    includedEventTypes: [ 'Microsoft.Storage.BlobCreated' ]
    subjectBeginsWith: '/blobServices/default/containers/documents/'
  }
  ```

### PostgreSQL 방화벽이 Azure Function 을 차단 → ConnectionTimeout (session-04)

- 증상 — 함수의 `_upsert_pg` 가 `psycopg.ConnectionTimeout` (연결 거부가 아니라 ~132초 timeout). Cosmos 적재는 되는데 PG 만 빔. 메시지가 max delivery 5회 재시도 후 DLQ
- 원인 — session-02 PG 방화벽이 dev IP 만 허용. Azure 호스팅 함수의 outbound 가 차단됨 (drop 은 거부가 아닌 timeout 으로 나타남)
- 회피 — PG 에 "Allow Azure services" 규칙 추가 (시작·끝 IP 모두 `0.0.0.0`). dev 챌린지 수준의 단순 해법이며 운영에선 VNet 통합 권장

  ```bash
  az postgres flexible-server firewall-rule create -g <rg> -n <pg> \
    --rule-name AllowAllAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
  ```

### Event Grid → Service Bus 전달 권한은 System Topic 의 관리 ID 에 (session-04)

- 증상 — Event Grid 구독이 정상으로 보이는데 Service Bus 로 전달이 0 건
- 원인 — `Azure Service Bus Data Sender` 역할을 User Assigned Managed Identity 에 부여. Event Grid → Service Bus 전달에 쓰이는 ID 는 System Topic 의 SystemAssigned 관리 ID 임
- 회피 — System Topic 의 SystemAssigned 관리 ID 에 `Azure Service Bus Data Sender` 를 부여. 전달이 0 이면 이 역할 부여를 먼저 확인

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

### `set_attribute` (customDimensions) ≠ OpenTelemetry 메트릭 (customMetrics) (session-06)

- 증상 — 토큰 · 캐시 관련 KQL 쿼리가 빈 결과
- 원인 — `set_attribute` 로 남긴 값은 customDimensions 에 들어가고, 집계 시계열은 Counter 메트릭 → customMetrics.value 로 들어감. 둘을 혼동하면 메트릭 발행 자체가 빠짐
- 회피 — 집계가 필요한 값은 attribute 가 아니라 Counter 메트릭으로 발행. KQL 이 빈 결과면 메트릭 발행 누락을 먼저 확인

### 커스텀 루트 span 을 만들지 않음 (session-06)

- 증상 — Transaction search 의 span 트리에 루트가 중복으로 보임
- 원인 — FastAPI 자동 계측이 이미 SERVER (requests) span 을 루트로 만드는데, 또 루트 span 을 만들면 중복
- 회피 — RAG span 들은 `start_as_current_span` 으로 열어 자동 request span 의 자식으로 중첩

### 민감 정보를 attribute 에 넣지 않음 (session-06)

- 증상 — 질문 본문 · 답변 같은 민감 정보가 Application Insights 에 영구 기록됨
- 원인 — span attribute 에 넣은 값은 텔레메트리로 영구 보존
- 회피 — `user.session_id` 까지만 기록하고 질문 본문 · 답변은 attribute 에 넣지 않음

### 기본 샘플링이 100% 가 아닐 수 있음 (session-06)

- 증상 — 일부 트레이스가 Application Insights 에 보이지 않음
- 원인 — 기본 sampling 이 100% 가 아니라 일부 트레이스가 드롭됨
- 회피 — 모든 트레이스를 보려면 `OTEL_TRACES_SAMPLER=always_on` 설정 (메트릭은 샘플링 영향 없음)

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

### Azure RBAC 클러스터는 Cluster User Role 만으론 kubectl 불가 (session-07)

- 증상 — `az aks get-credentials` 는 되는데 `kubectl get/apply` 가 전부 `Error from server (Forbidden): ... User does not have access to the resource in Azure. Update role assignment to allow access`. 구독 Owner 여도 동일
- 원인 — `enableAzureRBAC=true` 클러스터는 Kubernetes 데이터플레인 접근을 Azure 역할로 통제. `Azure Kubernetes Service Cluster User Role` 은 kubeconfig 다운로드(`listClusterUserCredential`)만 허용하고, 실제 리소스 조작 권한이 아니다 (Owner 도 K8s 데이터플레인은 미포함 — Cosmos/Storage 데이터플레인과 같은 구조)
- 회피 — 본인에게 `Azure Kubernetes Service RBAC Cluster Admin`(또는 Writer/Admin) 을 클러스터 scope 로 추가 부여. Bicep 으로 선언하면 깔끔
- 참고 — `az aks command invoke` 로 클러스터 내부에서 kubectl 실행 시 로컬 `kubelogin` 불필요 (CI/자동화에 유용)

### `koreacentral` DSv5 vCPU 할당량 = 0 (session-07)

- 증상 — Azure Kubernetes Service 배포 시 quota exceeded
- 원인 — `koreacentral` 의 DSv5 Family 기본 vCPU 가 0. 별도 신청이 필요
- 회피 — DSv3 (기본 10 vCPU) 사용

### Workload Identity subject 가 정확히 일치해야 함 (session-07)

- 증상 — 파드가 Azure 자원 접근에서 인증 오류. 토큰 교환이 실패
- 원인 — federatedIdentityCredential 의 subject (`system:serviceaccount:<ns>:<sa>`) 가 매니페스트의 namespace · ServiceAccount 이름과 정확히 일치하지 않음
- 회피 — subject 의 namespace · ServiceAccount 를 매니페스트와 글자 단위로 맞춤

---

## 비용 · 운영

### idle 자원의 누적 비용 (전체)

- 측정 (이전 학습 단계에서 dev 환경 7일 기준)
  - Redis (당시 **Memory_M10**): **~₩11,680/일** (당시 전체 청구의 75%) — **현재 챌린지는 최소 등급 `Balanced_B0` 로 배포**하므로 이보다 훨씬 낮음 (list price 기준 약 1/18, [Azure Managed Redis 요금](https://azure.microsoft.com/pricing/details/managed-redis/))
  - Azure Container Apps Container App (min replica 1): ~₩1,743/일
  - Azure Kubernetes Service LB + Public IP: ~₩1,125/일
  - PostgreSQL B1ms: ~₩700/일
- 함의 — dev 환경이라도 compute 가 있는 자원은 시간당 누적. (위 Redis ~₩11,680/일 은 당시 Memory_M10 기준 — **SKU 가 크면 빠르게 누적**된다는 예시이며, 현재 `Balanced_B0` 의 비용 서열은 이보다 훨씬 아래)
- 회피 — 본 챌린지 진행이 끝나면 즉시 [cleanup.md](../cleanup.md) 수행

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
- **Windows + psycopg async** — Windows 기본 ProactorEventLoop 에서 `asyncio.run()` 으로 psycopg async 를 돌리면 `Psycopg cannot use the 'ProactorEventLoop'` 로 죽는다. `asyncio.run(main(), loop_factory=asyncio.SelectorEventLoop)` (Python 3.12+) 로 SelectorEventLoop 강제. `seed_both.py` 같은 로컬 스크립트에서 발생 (session-02)
- **PostgreSQL `SET LOCAL x = %s`** 는 bind 파라미터를 받지 않아 `syntax error at or near "$1"`. 신뢰된 정수는 직접 보간(`f"SET LOCAL hnsw.ef_search = {int(v)}"`)하거나 `SELECT set_config('x', %s, true)` 사용 (session-02)
- **FastAPI OpenTelemetry 계측은 app 생성 직후(모듈 레벨)에 해야 한다** — `configure_azure_monitor()` 를 lifespan startup 에서 호출하면 `FastAPI.__init__` 패치가 **이미 생성된** app 에 적용 안 돼 **인입 요청 server span(`requests` 테이블)이 통째로 누락**된다. 커스텀 span(`dependencies`)·metric·log 는 잡히는데 `requests` 만 빠져 증상이 헷갈림. 영향: session-06 의 `requests` 기반 알림(오류율·p95)·Workbook P95 에 데이터가 안 들어옴. 해결: `app = FastAPI(...)` **직후 모듈 레벨**에서 `configure_azure_monitor(...)` + `FastAPIInstrumentor.instrument_app(app)` 호출 (session-06)
- **`azure-appconfiguration-provider` 의 `load()` 피처 플래그 활성화 kwarg 이름은 공식 문서마다 다르다** — SDK README(client library)는 단수 `feature_flag_enabled`, MS Learn 개념 문서는 복수 `feature_flags_enabled` 로 표기한다. `load()` 가 `**kwargs` 라 **틀린 이름을 넘기면 에러 없이 무시되고 피처 플래그를 아예 로드하지 않아** `is_enabled()` 가 항상 false 가 된다 (플래그·캐시 토글이 통째로 죽음, 증상이 조용해 진단이 어려움). 본 챌린지가 쓰는 `azure-appconfiguration-provider>=2.0.0` 는 **단수 `feature_flag_enabled`** 가 정답 (SDK README 기준이며 `loader.py` 도 단수 사용). 직접 손볼 때는 설치된 버전의 README 로 이름을 재확인 (session-05)
- **App Configuration `feature_flag_refresh_enabled=True` 누락 시 토글 미반영** — refresh 설정이 빠지면 포털에서 피처 플래그를 토글해도 앱에 반영되지 않는다. 가장 흔한 함정 (session-05)
- **`is_enabled()` 는 호출마다 평가** — hot path 에서 과도하게 호출하지 않도록 요청 시작 시 1회 평가 후 결과를 재사용 (session-05)
- **`identity.type='UserAssigned'` 자원은 `identity.principalId` 를 노출하지 않음** — 최상위 `identity.principalId` 대신 `userAssignedIdentities[id].principalId` 로 접근 (session-04)
- **`az redisenterprise show` 는 평탄화된 응답** — 일반 ARM 자원의 `properties.xxx` 가 아니라 `resourceState` · `hostName` 등이 최상위에 위치 (session-03)
