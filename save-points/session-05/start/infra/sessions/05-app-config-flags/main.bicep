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
// 본 세션에서 할 일:
//   아래 그룹별 모듈 호출과 출력 블록을 직접 채운다. 모듈 본체는
//   ../../modules/session-05/ 에 이미 완성되어 있다 (수정하지 않는다).
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

// -------- 1) App Configuration store 모듈 호출하기 ----------------------------
// 힌트: app-configuration.bicep (name=acName, skuName='free').

// -------- 2) 일반 키/값 모듈 호출하기 ----------------------------------------
// 힌트: app-configuration-keyvalue.bicep 를 4번 호출 (개별 호출 — 값이 existing
// 런타임 속성이라 for-루프 불가). aoai:endpoint=aoai.properties.endpoint,
// cosmos:endpoint=cosmos.properties.documentEndpoint,
// pg:host='${pgName}.postgres.database.azure.com', redis:host=redis.properties.hostName.

// -------- 3) sentinel 키 모듈 호출하기 ---------------------------------------
// 힌트: app-configuration-keyvalue.bicep (key='sentinel', value='1'). refresh 트리거.

// -------- 4) Key Vault reference 모듈 호출하기 -------------------------------
// 힌트: app-configuration-keyvault-ref.bicep (key='secrets:aoai-endpoint',
// secretUri='${kv.properties.vaultUri}secrets/aoai-endpoint'). session-01 secret 참조.

// -------- 5) 피처 플래그 모듈 호출하기 --------------------------------------
// 힌트: app-configuration-feature-flag.bicep 2번 —
// enable_semantic_cache(enabled=true), enable_pg_backend(enabled=false).

// -------- 6) 역할 할당 모듈 호출하기 ----------------------------------------
// 힌트: role-assignment-appconfig.bicep — UAMI 에 roleAppConfigDataReader,
// (선택) if(!empty(userObjectId)) 로 사용자에 roleAppConfigDataOwner(principalType='User').

// -------- 출력 -----------------------------------------------------------------
// 힌트: appConfigName, appConfigEndpoint (appConfig.outputs.endpoint).
