# session-05 (App Configuration 피처 플래그)

👈 [session-04](./04-async-ingestion.md)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [session-00](./00-setup.md) ~ [session-04](./04-async-ingestion.md) 완료 — Azure Container Apps · Cosmos DB · PostgreSQL · Managed Redis · Key Vault · User Assigned Managed Identity · Application Insights 가 본인 구독에 존재
> - 시작본 코드를 작업 폴더로 받기 — [시작본 코드 받기](#시작본-코드-받기) 참고

---

## 시작본 코드 받기

[session-04](./04-async-ingestion.md) 결과물이 들어 있는 `workshop/` 위에 본 세션 시작본을 덮습니다.

```bash
# Linux · macOS · WSL
cp -a save-points/session-05/start/. workshop/
```

```powershell
# Windows PowerShell
Copy-Item -Path save-points/session-05/start/* -Destination workshop -Recurse -Force
```

이후 본 세션의 모든 명령은 `workshop/` 안에서 실행한다고 가정합니다.

학습자가 채우는 파일은 두 개입니다 — `infra/sessions/05-app-config-flags/main.bicep` (모듈 조립), `apps/api/src/config/loader.py` (App Configuration 로더). 모듈 5개와 `main.py` 배선은 완성되어 제공됩니다.

---

## 1 단계 : 프로비저닝

`workshop/infra/sessions/05-app-config-flags/main.bicep` 을 열고, 그룹별 주석을 찾아 코드를 채웁니다.

이 단계의 Bicep 은 **App Configuration store 와 역할 할당만** 만듭니다. 키/값·Key Vault 참조·피처 플래그는 Bicep 이 아니라 배포 후 [`scripts/seed_app_config.py`](#2-단계--설정값-시딩) 로 시딩합니다 (그 이유는 [2 단계](#2-단계--설정값-시딩) 에서 설명합니다).

### 1.1 호출할 모듈 한눈에 보기

`infra/modules/session-05/` 에 완성되어 있는 모듈입니다.

```text
infra/modules/session-05/
├── app-configuration.bicep         # Free 등급 store
└── role-assignment-appconfig.bicep # 역할 부여 (재사용)
```

### 1.2 store 모듈 호출

`// -------- 1) App Configuration store 모듈 호출하기` 주석 아래에 채웁니다. 빈 store 만 만들고, 설정값은 [2 단계](#2-단계--설정값-시딩) 에서 시딩합니다.

```bicep
module appConfig '../../modules/session-05/app-configuration.bicep' = {
  name: 'appConfig'
  params: {
    name: acName
    location: location
    skuName: 'free'
    tags: commonTags
  }
}
```

### 1.3 역할 할당

`// -------- 2) 역할 할당 모듈 호출하기` 주석 아래에 채웁니다. User Assigned Managed Identity 는 읽기(`Data Reader`), 사용자는 시딩·토글을 위한 쓰기(`Data Owner`) 를 부여합니다. 사용자에게 `Data Owner` 가 필요한 이유는, [2 단계](#2-단계--설정값-시딩) 의 시딩 스크립트가 본인 자격으로 store 데이터플레인에 키/값과 피처 플래그를 직접 쓰기 때문입니다.

```bicep
module dataReaderUami '../../modules/session-05/role-assignment-appconfig.bicep' = {
  name: 'dataReader-uami'
  params: {
    storeName: appConfig.outputs.name
    roleDefinitionId: roleAppConfigDataReader
    principalId: uami.properties.principalId
  }
}

module dataOwnerUser '../../modules/session-05/role-assignment-appconfig.bicep' = if (!empty(userObjectId)) {
  name: 'dataOwner-user'
  params: {
    storeName: appConfig.outputs.name
    roleDefinitionId: roleAppConfigDataOwner
    principalId: userObjectId
    principalType: 'User'
  }
}
```

### 1.4 출력

`// -------- 출력` 주석 아래에 채웁니다.

```bicep
output appConfigName string = appConfig.outputs.name
output appConfigEndpoint string = appConfig.outputs.endpoint
```

### 1.5 조립 검증 + 배포

```bash
az bicep build --file infra/sessions/05-app-config-flags/main.bicep --outfile /tmp/main.json && echo "BUILD OK"
```

```powershell
# Windows PowerShell
az bicep build --file infra/sessions/05-app-config-flags/main.bicep --outfile "$env:TEMP\main.json"
if ($?) { "BUILD OK" }
```

배포 전에 `what-if` 로 어떤 자원이 생성·변경되는지 미리 확인합니다.

```bash
OID=$(az ad signed-in-user show --query id -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/05-app-config-flags/main.bicep \
  --parameters infra/sessions/05-app-config-flags/main.bicepparam \
  --parameters userObjectId=$OID
```

```powershell
# Windows PowerShell
$OID = (az ad signed-in-user show --query id -o tsv)

az deployment group what-if `
  --resource-group rg-ai200ws-dev `
  --template-file infra/sessions/05-app-config-flags/main.bicep `
  --parameters infra/sessions/05-app-config-flags/main.bicepparam `
  --parameters userObjectId=$OID
```

> [!NOTE]
> `what-if` 출력에서 역할 할당이 `Unsupported` 로 표기되는 경우가 있습니다. 본 세션은 역할 할당 1건이 `Unsupported` 로 나오며, 이는 정상이고 실제 배포는 성공합니다.

미리보기 내용이 예상과 맞으면 같은 `$OID` 로 실제 배포를 실행합니다.

```bash
az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/05-app-config-flags/main.bicep \
  --parameters infra/sessions/05-app-config-flags/main.bicepparam \
  --parameters userObjectId=$OID
```

```powershell
# Windows PowerShell
az deployment group create `
  --resource-group rg-ai200ws-dev `
  --template-file infra/sessions/05-app-config-flags/main.bicep `
  --parameters infra/sessions/05-app-config-flags/main.bicepparam `
  --parameters userObjectId=$OID
```

> [!NOTE]
> App Configuration 자체 배포는 약 **1분** 으로 본 챌린지에서 가장 빠릅니다.

### 1.6 배포 완료 확인

> [!NOTE]
> 본 세션의 App Configuration store 는 `disableLocalAuth: true` (연결 문자열·액세스 키 비활성, Entra ID + 역할 기반 접근만 허용) 로 배포됩니다. 그래서 store 의 데이터플레인을 다루는 `az appconfig` 명령 (`feature`·`kv` 의 `list`·`show`·`set`·`disable`·`enable`) 에는 반드시 `--auth-mode login` 을 붙입니다. 없으면 `Cannot find a read write access key ...` 오류로 실패합니다. 반면 store 메타데이터를 조회하는 `az appconfig show` (컨트롤플레인) 에는 필요하지 않습니다.

이 단계의 Bicep 은 빈 store 만 만들었으므로, store 가 정상 생성됐는지만 확인합니다 (키/값·피처 플래그는 아직 없습니다 — [2 단계](#2-단계--설정값-시딩) 시딩 뒤에 확인합니다).

```bash
AC=$(az appconfig list -g rg-ai200ws-dev --query "[0].name" -o tsv)

az appconfig show -n $AC -g rg-ai200ws-dev \
  --query "{state:provisioningState, sku:sku.name, endpoint:endpoint}" -o jsonc
```

```powershell
# Windows PowerShell
$AC = (az appconfig list -g rg-ai200ws-dev --query "[0].name" -o tsv)

az appconfig show -n $AC -g rg-ai200ws-dev `
  --query "{state:provisioningState, sku:sku.name, endpoint:endpoint}" -o jsonc
```

기대 — `provisioningState` 가 `Succeeded`, `sku` 가 `free` 입니다.

---

## 2 단계 : 설정값 시딩

[1 단계](#1-단계--프로비저닝) 에서 만든 빈 store 에 키/값·Key Vault 참조·피처 플래그를 [`scripts/seed_app_config.py`](../../save-points/session-05/complete/scripts/seed_app_config.py) 로 시딩합니다.

**왜 Bicep 이 아니라 스크립트인가** — store 가 `disableLocalAuth: true` 라, 키/값·피처 플래그 같은 데이터플레인 쓰기를 **Bicep 으로** 시도하면 문제가 생깁니다. 배포자(사용자)의 `App Configuration Data Owner` 역할이 같은 배포 안에서 부여되는데, 그 역할이 데이터플레인에 전파되는 데 수 분이 걸려 첫 쓰기가 `Forbidden` 으로 깨집니다. 그래서 store 와 역할만 Bicep 으로 만들고, **설정값은 배포가 끝나 역할이 데이터플레인에 전파된 뒤 본인 자격으로 시딩**합니다. 시딩 스크립트는 전파가 아직 안 끝나 `Forbidden` 이 나면 전파될 때까지 자동으로 재시도합니다.

### 2.1 시딩에 필요한 엔드포인트를 환경변수로

스크립트는 각 자원의 엔드포인트를 환경변수에서 읽습니다. 본인 구독에 배포된 자원에서 값을 조회해 내보냅니다.

```bash
RG=rg-ai200ws-dev
AC=$(az appconfig list -g $RG --query "[0].name" -o tsv)
export APP_CONFIG_ENDPOINT=$(az appconfig show -n $AC -g $RG --query endpoint -o tsv)
export AOAI_ENDPOINT=$(az cognitiveservices account list -g $RG --query "[0].properties.endpoint" -o tsv)
export COSMOS_ENDPOINT=$(az cosmosdb list -g $RG --query "[0].documentEndpoint" -o tsv)
export PG_HOST=$(az postgres flexible-server list -g $RG --query "[0].fullyQualifiedDomainName" -o tsv)
export REDIS_HOST=$(az redisenterprise list -g $RG --query "[0].hostName" -o tsv)
export KV_VAULT_URI=$(az keyvault list -g $RG --query "[0].properties.vaultUri" -o tsv)
```

```powershell
# Windows PowerShell
$RG = "rg-ai200ws-dev"
$AC = (az appconfig list -g $RG --query "[0].name" -o tsv)
$env:APP_CONFIG_ENDPOINT = (az appconfig show -n $AC -g $RG --query endpoint -o tsv)
$env:AOAI_ENDPOINT = (az cognitiveservices account list -g $RG --query "[0].properties.endpoint" -o tsv)
$env:COSMOS_ENDPOINT = (az cosmosdb list -g $RG --query "[0].documentEndpoint" -o tsv)
$env:PG_HOST = (az postgres flexible-server list -g $RG --query "[0].fullyQualifiedDomainName" -o tsv)
$env:REDIS_HOST = (az redisenterprise list -g $RG --query "[0].hostName" -o tsv)
$env:KV_VAULT_URI = (az keyvault list -g $RG --query "[0].properties.vaultUri" -o tsv)
```

### 2.2 시딩 실행

`apps/api` 의 의존성 환경으로 시딩 스크립트를 실행합니다.

```bash
uv run --project apps/api python scripts/seed_app_config.py
```

다음과 비슷한 출력이 표시됩니다.

```
App Configuration 시딩 — 8 개 설정 → https://ac-ai200ws-dev-xxxx.azconfig.io
완료 — 키/값 5 개 + 피처 플래그 2 개 시딩.
```

> [!NOTE]
> 역할이 데이터플레인에 아직 전파되지 않았으면 `RBAC 전파 대기 중 (Forbidden) — 20s 후 재시도...` 가 찍히며 스크립트가 자동으로 재시도합니다. 직접 손대지 않고 그대로 두면 전파가 끝난 뒤 시딩이 이어집니다.

### 2.3 시딩 검증

store 의 데이터플레인을 조회하므로 두 명령 모두 `--auth-mode login` 이 필수입니다 (store 가 local-auth 비활성).

```bash
az appconfig kv list -n $AC --auth-mode login --query "[].key" -o table

az appconfig feature list -n $AC --auth-mode login --query "[].{key:key, state:state}" -o table
```

```powershell
# Windows PowerShell
az appconfig kv list -n $AC --auth-mode login --query "[].key" -o table

az appconfig feature list -n $AC --auth-mode login --query "[].{key:key, state:state}" -o table
```

기대 — 키/값 목록에 `aoai:endpoint` · `cosmos:endpoint` · `pg:host` · `redis:host` · `sentinel` · `secrets:aoai-endpoint` 6개가 나오고, 피처 플래그 2개 (`enable_semantic_cache` 는 on, `enable_pg_backend` 는 off) 가 나옵니다.

---

## 3 단계 : 복붙으로 경험해보기

### 3.1 App Configuration 로더 구현

`apps/api/src/config/loader.py` 의 `load_app_config` 함수가 `raise NotImplementedError` 로 비어 있습니다. 그 줄을 찾아 함수 본체를 아래 코드로 교체합니다.

```python
async def load_app_config(settings: Settings) -> AppConfig:
    credential = DefaultAzureCredential()
    provider = await load(
        endpoint=settings.app_config_endpoint,
        credential=credential,
        keyvault_credential=credential,
        feature_flag_enabled=True,
        feature_flag_refresh_enabled=True,
        refresh_on=[WatchKey(_SENTINEL_KEY)],
        refresh_interval=_REFRESH_INTERVAL_SECONDS,
    )
    return AppConfig(provider, credential)
```

### 3.2 이미지 빌드 · 배포 · 토글 실험

```bash
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/api:s05 apps/api
docker push $ACR_NAME.azurecr.io/api:s05

# App Configuration endpoint 를 환경변수로 주입 (REDIS_HOST 는 session-03 에서 설정됨)
AC_ENDPOINT=$(az appconfig show -n $AC -g rg-ai200ws-dev --query endpoint -o tsv)
az containerapp update \
  --name ca-api-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --image $ACR_NAME.azurecr.io/api:s05 \
  --set-env-vars APP_CONFIG_ENDPOINT=$AC_ENDPOINT

API_FQDN=$(az containerapp show -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)
```

```powershell
# Windows PowerShell
$ACR_NAME = (az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)
docker build --platform linux/amd64 -t "$ACR_NAME.azurecr.io/api:s05" apps/api
docker push "$ACR_NAME.azurecr.io/api:s05"

$AC_ENDPOINT = (az appconfig show -n $AC -g rg-ai200ws-dev --query endpoint -o tsv)
az containerapp update `
  --name ca-api-ai200ws-dev `
  --resource-group rg-ai200ws-dev `
  --image "$ACR_NAME.azurecr.io/api:s05" `
  --set-env-vars "APP_CONFIG_ENDPOINT=$AC_ENDPOINT"

$API_FQDN = (az containerapp show -n ca-api-ai200ws-dev -g rg-ai200ws-dev `
  --query "properties.configuration.ingress.fqdn" -o tsv)
```

캐시 ON 상태에서 검증용 트래픽을 흘려, hot 질문이 캐시 hit 으로 즉시 반환되는지 확인합니다. 헬퍼 스크립트는 hot 질문 (캐시 hit 유발) 과 다양한 질문 (retrieve+generate = miss 유발) 을 번갈아 보냅니다.

```bash
uv run --project apps/api python scripts/send_chat_traffic.py --url $API_FQDN --count 6
```

출력에서 `q=휴가 규정 알려줘` 줄이 두 번째 등장부터 0.1~0.2s 면 캐시 hit 입니다. 다양한 질문 줄은 retrieve+generate 를 매번 수행하므로 더 느립니다.

CLI 로 피처 플래그를 OFF 로 토글하고, 폴링 주기에 따라 반영될 때까지 잠시 대기한 뒤 다시 트래픽을 흘립니다. 이번에는 hot 질문도 캐시를 우회해 느려집니다.

> [!NOTE]
> 초기 플래그 상태는 앱 시작 시점에 반영되고, 실행 중인 앱에서의 런타임 토글은 provider 의 폴링 주기에 따라 반영됩니다. 본 챌린지 설정(`refresh_interval` 30초)에서는 토글 후 약 30~60초 내에 반영됩니다. 토글 직후 즉시 바뀌지 않더라도 정상이며, 폴링 주기가 지난 뒤(아래 `sleep 60`) 다시 확인합니다 (본인 설정 실수로 오해하지 않습니다).

```bash
az appconfig feature disable -n $AC --auth-mode login --feature enable_semantic_cache --yes
sleep 60
uv run --project apps/api python scripts/send_chat_traffic.py --url $API_FQDN --count 6
```

```powershell
# Windows PowerShell
az appconfig feature disable -n $AC --auth-mode login --feature enable_semantic_cache --yes
Start-Sleep -Seconds 60
uv run --project apps/api python scripts/send_chat_traffic.py --url $API_FQDN --count 6
```

`q=휴가 규정 알려줘` 줄까지 retrieve+generate 시간으로 느려지면 캐시가 우회된 것입니다. 아직 hot 질문이 빠르게 반환된다면 반영이 덜 된 것이므로, 1~2분 더 기다렸다가 같은 트래픽 명령을 다시 실행해 확인합니다.

다시 켜려면 `az appconfig feature enable -n $AC --auth-mode login --feature enable_semantic_cache --yes` 명령어를 터미널에 입력합니다.

---

## 4 단계 : Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **App Configuration** → **Configuration explorer** — `aoai:endpoint` 등 키 목록 + Key Vault reference 키(`secrets:aoai-endpoint`)는 타입이 `Key vault reference`

   ![Configuration explorer 의 키/값 목록을 보여 주는 Azure Portal 스크린샷](images/session-05/3a-app-config-configuration-explorer.png)

   `aoai:endpoint` · `cosmos:endpoint` · `pg:host` · `redis:host` 키 4개와 `sentinel` 이 나열되고, `secrets:aoai-endpoint` 의 타입이 **Key vault reference** 로 표시되는지 확인합니다.

2. **App Configuration** → **Feature manager** — `enable_semantic_cache` 토글. 토글은 CLI 가 아니라 **Feature manager 화면에서 직접** 수행해 Portal 조작을 경험합니다.

   아래 순서로 터미널 (트래픽) 과 Portal (토글) 을 오가며, 4번 **Logs** 차트에 나타날 절벽 데이터를 만듭니다.

   1. 별도 터미널에서 캐시 ON 상태로 트래픽 15건을 흘립니다.

      ```bash
      uv run --project apps/api python scripts/send_chat_traffic.py --url $API_FQDN --count 15
      ```

   2. **Feature manager** 에서 `enable_semantic_cache` 를 **OFF 로 토글** 합니다.
   3. 폴링 주기에 따라 반영될 때까지 대기한 뒤 (약 30~60초), 캐시 OFF 상태로 같은 스크립트를 다시 실행해 트래픽 15건을 흘립니다.

      ```bash
      uv run --project apps/api python scripts/send_chat_traffic.py --url $API_FQDN --count 15
      ```

   4. `enable_semantic_cache` 를 다시 **ON 으로 토글** 해 원상복구합니다.

       ![Feature manager 의 enable_semantic_cache 피처 플래그 토글을 보여 주는 Azure Portal 스크린샷](images/session-05/3b-app-config-feature-manager-toggle.png)

3. **Key Vault** → **Secrets** — App Configuration이 참조하는 secret 이름은 확인 가능합니다. 실제 값은 권한이 있어야 조회할 수 있습니다.

   ![Key Vault 의 Secrets 목록에 aoai-endpoint 가 나열된 모습을 보여 주는 Azure Portal 스크린샷](images/session-05/3c-key-vault-secrets-list.png)

4. **Application Insights** → **Logs** 에서 다음 KQL 실행

   ```kusto
   let win = 40m;
   let chats = requests
   | where timestamp > ago(win)
   | where name == "POST /api/chat"
   | summarize requests = count() by bin(timestamp, 1m);
   let lookups = dependencies
   | where timestamp > ago(win)
   | where name == "cache.lookup"
   | summarize lookups = count() by bin(timestamp, 1m);
   chats
   | join kind=leftouter lookups on timestamp
   | project timestamp, requests, lookups = coalesce(lookups, 0)
   | order by timestamp asc
   | render timechart
   ```

   `requests` (분당 `/api/chat` 호출 수) 와 `cache.lookup` (분당 캐시 조회 수) 두 선을 함께 그립니다. 플래그를 OFF 로 토글하면 코드가 캐시 계층을 건너뛰어 `cache.lookup` 만 0 으로 떨어지지만, `requests` 선은 그대로 유지됩니다 — 같은 트래픽인데 캐시 계층만 사라졌다는 명백한 증거입니다. 다시 ON 으로 토글하면 `cache.lookup` 이 회복됩니다. 두 선을 함께 봐야 **플래그 OFF (캐시 건너뜀)** 와 **트래픽 없음 (idle)** 을 구분할 수 있습니다 — 둘 다 `cache.lookup` 이 0 이지만, 전자는 `requests` 가 유지되고 후자는 `requests` 도 함께 0 입니다.

   ![cache.lookup 의 분당 발생 건수가 플래그 OFF 구간에서 0 으로 떨어지는 절벽을 시간 축 차트로 보여 주는 Application Insights Logs 의 Azure Portal 스크린샷](images/session-05/3d-app-insights-hit-rate-timechart.png)

   2번에서 만든 ON → OFF → ON 시퀀스에 맞춰, OFF 구간에서 `lookups` 가 0 으로 떨어졌다가 다시 ON 으로 토글하면 0 에서 회복되는 절벽이 차트에 나타나는지 확인합니다.

> [!NOTE]
> **Live Metrics 는 이 세션에서 캡쳐하지 않습니다** — Live Metrics 는 SDK 기본값으로 켜져 있어 설정 문제는 아니지만, Azure Container Apps 가 트래픽이 없으면 replica 를 0 으로 내리는(scale-to-zero) 특성 때문에 실시간 스트림을 보내는 주체가 사라져 참가자가 재현하기 어렵습니다. 캐시 ON→OFF 효과는 위 **Logs(KQL)** 의 `hit_rate` 타임차트로 영구 데이터로 확인합니다. 관측성 전담 세션인 [session-06](./06-observability.md) 도 Live Metrics 대신 KQL 을 우선하는 같은 방식으로 구성됩니다.

---

## 마무리

- **save-point** — 본 세션의 모든 변경은 `save-points/session-05/complete/` 와 일치합니다. 다음 세션으로 넘어가려면 `workshop/` 을 그대로 두고 bash: `cp -a save-points/session-06/start/. workshop/` · PowerShell: `Copy-Item -Path save-points/session-06/start/* -Destination workshop -Recurse -Force` 를 실행합니다
- **자원 정리** — App Configuration (Free) 과 Key Vault 는 비용이 사실상 0 이고 후속 세션 ([session-06](./06-observability.md)) 에서 계속 사용되므로 정리하지 않습니다
- **다음 세션 미리보기** — [session-06](./06-observability.md) 에서는 지금까지 자동 계측이 잡아주던 trace 를 RAG 의 비즈니스 의미가 담긴 커스텀 span (`rag.retrieve`, `rag.generate`, `cache.lookup`, 토큰 카운트) 으로 격상시키고, KQL Workbook 과 Metric Alert 로 관측성을 구축합니다

---

👈 [session-04](./04-async-ingestion.md) | [session-06](./06-observability.md) 👉
