// =============================================================================
// session-05 — App Configuration 피처 플래그
//
// 배포 명령:
//   OID=$(az ad signed-in-user show --query id -o tsv)
//   az deployment group create \
//     --resource-group rg-ai200ws-dev \
//     --template-file workshop/infra/sessions/05-app-config-flags/main.bicep \
//     --parameters workshop/infra/sessions/05-app-config-flags/main.bicepparam \
//     --parameters userObjectId=$OID
//
// 의존성 (existing 참조):
//   - session-00: Key Vault (aoai-endpoint secret), UAMI
//   - session-01: Cosmos DB / session-02: PostgreSQL / session-03: Managed Redis
//
// 본 세션에서 신규 생성:
//   - App Configuration (Free) + 키/값 + Key Vault reference + 피처 플래그 2개 + sentinel
//   - 역할 할당: UAMI → App Configuration Data Reader, 사용자 → App Configuration Data Owner
// =============================================================================

targetScope = 'resourceGroup'

@description('환경 라벨')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('Azure 자원 기본 리전')
param location string = resourceGroup().location

@description('배포 실행자의 Entra objectId. 포털/CLI 로 플래그 토글하려면 Data Owner 필요. CLI override.')
param userObjectId string = ''

// -------- 공용 태그 ------------------------------------------------------------

var commonTags = {
  project: projectId
  env: env
  workshop: 'azure-ai-200'
  managedBy: 'bicep'
  session: 'session-05'
}

// -------- 내장 역할 정의 GUID ---------------------------------------------------

var roleAppConfigDataReader = '516239f1-63e1-4d78-a4de-a74fb236a071'
var roleAppConfigDataOwner = '5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b'

// -------- 자원 이름 ------------------------------------------------------------

// App Configuration: 글로벌 unique (DNS, <name>.azconfig.io). uniqueString 접미사.
var acName = take('ac-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 50)

// session-00~03 자원 이름 (각 세션 main.bicep 과 동일 규칙)
var uamiName = 'id-${projectId}-${env}'
var kvName = take('kv-${projectId}-${env}-${uniqueString(subscription().id, projectId, env)}', 24)
var cosmosName = take('cosmos-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 44)
var aoaiName = take('aoai-${projectId}-${env}-${uniqueString(subscription().id, projectId, env)}', 60)
var redisName = take('redis-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 60)
var pgName = take('pg-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 63)

// -------- existing 참조 --------------------------------------------------------

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: uamiName
}

resource kv 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: kvName
}

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aoaiName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosName
}

resource redis 'Microsoft.Cache/redisEnterprise@2025-04-01' existing = {
  name: redisName
}

// -------- 1) App Configuration store --------------------------------------------

module appConfig '../../modules/session-05/app-configuration.bicep' = {
  name: 'appConfig'
  params: {
    name: acName
    location: location
    skuName: 'free'
    tags: commonTags
  }
}

// -------- 2) 일반 키/값 (비-시크릿 endpoint·host) --------------------------------
//             값이 existing 자원의 런타임 속성이라 for-루프(시작 시점 계산)가 불가능하므로
//             개별 모듈로 호출한다.

module kvAoai '../../modules/session-05/app-configuration-keyvalue.bicep' = {
  name: 'kv-aoai-endpoint'
  params: {
    storeName: appConfig.outputs.name
    key: 'aoai:endpoint'
    value: aoai.properties.endpoint
  }
}

module kvCosmos '../../modules/session-05/app-configuration-keyvalue.bicep' = {
  name: 'kv-cosmos-endpoint'
  params: {
    storeName: appConfig.outputs.name
    key: 'cosmos:endpoint'
    value: cosmos.properties.documentEndpoint
  }
}

module kvPg '../../modules/session-05/app-configuration-keyvalue.bicep' = {
  name: 'kv-pg-host'
  params: {
    storeName: appConfig.outputs.name
    key: 'pg:host'
    value: '${pgName}.postgres.database.azure.com'
  }
}

module kvRedis '../../modules/session-05/app-configuration-keyvalue.bicep' = {
  name: 'kv-redis-host'
  params: {
    storeName: appConfig.outputs.name
    key: 'redis:host'
    value: redis.properties.hostName
  }
}

// sentinel — 이 키를 바꾸면 Provider 가 전체 설정을 새로 고친다 (refresh_on 대상).
module sentinel '../../modules/session-05/app-configuration-keyvalue.bicep' = {
  name: 'sentinel'
  params: {
    storeName: appConfig.outputs.name
    key: 'sentinel'
    value: '1'
  }
}

// -------- 3) Key Vault reference (시크릿성 값) -----------------------------------
//             session-01 이 저장한 aoai-endpoint secret 을 참조로 노출 (KV ref 패턴 시연).

module kvRef '../../modules/session-05/app-configuration-keyvault-ref.bicep' = {
  name: 'kvRef'
  params: {
    storeName: appConfig.outputs.name
    key: 'secrets:aoai-endpoint'
    secretUri: '${kv.properties.vaultUri}secrets/aoai-endpoint'
  }
}

// -------- 4) 피처 플래그 --------------------------------------------------------

module flagSemanticCache '../../modules/session-05/app-configuration-feature-flag.bicep' = {
  name: 'flag-semanticCache'
  params: {
    storeName: appConfig.outputs.name
    flagName: 'enable_semantic_cache'
    enabled: true
  }
}

module flagPgBackend '../../modules/session-05/app-configuration-feature-flag.bicep' = {
  name: 'flag-pgBackend'
  params: {
    storeName: appConfig.outputs.name
    flagName: 'enable_pg_backend'
    enabled: false
  }
}

// -------- 5) 역할 할당 — UAMI(읽기) / 사용자(토글용 쓰기) ------------------------

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

// -------- 출력 -----------------------------------------------------------------

output appConfigName string = appConfig.outputs.name
output appConfigEndpoint string = appConfig.outputs.endpoint
