// =============================================================================
// S00 — 사전 설정 & 구독 준비
//
// 한 번의 `az deployment sub create` 로 RG + 워크샵 전체의 기반 자원을 배포.
// 후속 세션 (S01~S07) 은 이 자원들을 `existing` 또는 출력값으로 참조한다.
//
// 배포 명령:
//   az deployment sub create \
//     --location <region> \
//     --template-file infra/sessions/00-setup/main.bicep \
//     --parameters infra/sessions/00-setup/main.bicepparam \
//     --parameters userObjectId=$(az ad signed-in-user show --query id -o tsv)
// =============================================================================

targetScope = 'subscription'

// -------- 파라미터 -------------------------------------------------------------

@description('환경 라벨 (예: dev, prod)')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('기본 리전 (RG · LAW · AI · KV · UAMI)')
param location string = 'koreacentral'

@description('AOAI 리전. koreacentral 에 가용한 모델이 없으면 eastus/japaneast 로 분리.')
param aoaiLocation string = 'koreacentral'

@description('배포 실행자의 Entra objectId. CLI override 강제 — bicepparam 박지 말 것.')
param userObjectId string = ''

// -------- AOAI 모델 파라미터 ---------------------------------------------------

@description('chat 모델 deployment 이름 (코드에서 부르는 이름)')
param chatDeploymentName string = 'gpt-5-mini'
param chatModelName string = 'gpt-5-mini'
param chatModelVersion string = '2025-08-07'
@minValue(1)
param chatCapacityK int = 10

@description('embedding 모델 deployment 이름')
param embedDeploymentName string = 'text-embedding-3-large'
param embedModelName string = 'text-embedding-3-large'
param embedModelVersion string = '1'
@minValue(1)
param embedCapacityK int = 10

// -------- 공용 태그 ------------------------------------------------------------

var commonTags = {
  project: projectId
  env: env
  workshop: 'azure-ai-200'
  managedBy: 'bicep'
  session: 's00-setup'
}

// -------- 이름 ----------------------------------------------------------------

var rgName = 'rg-${projectId}-${env}'
var lawName = 'law-${projectId}-${env}'
var aiName = 'ai-${projectId}-${env}'
// Key Vault: 글로벌 unique. uniqueString 으로 충돌 회피.
var kvName = take('kv-${projectId}-${env}-${uniqueString(subscription().id, projectId, env)}', 24)
var uamiName = 'id-${projectId}-${env}'
// AOAI: 글로벌 unique. customSubDomainName 으로도 사용됨.
var aoaiName = take('aoai-${projectId}-${env}-${uniqueString(subscription().id, projectId, env)}', 60)

// -------- 1) RG (sub scope) ---------------------------------------------------

module rg '../../modules/session-00/resource-group.bicep' = {
  name: 'rg-${env}'
  params: {
    name: rgName
    location: location
    tags: commonTags
  }
}

// -------- 2) Log Analytics + Application Insights ------------------------------

module law '../../modules/session-00/log-analytics.bicep' = {
  scope: resourceGroup(rgName)
  name: 'law'
  params: {
    name: lawName
    location: location
    tags: commonTags
  }
  dependsOn: [
    rg
  ]
}

module appInsights '../../modules/session-00/application-insights.bicep' = {
  scope: resourceGroup(rgName)
  name: 'appInsights'
  params: {
    name: aiName
    location: location
    workspaceResourceId: law.outputs.id
    tags: commonTags
  }
}

// -------- 3) Key Vault --------------------------------------------------------

module kv '../../modules/session-00/key-vault.bicep' = {
  scope: resourceGroup(rgName)
  name: 'kv'
  params: {
    name: kvName
    location: location
    tags: commonTags
    // dev 라도 purge protection 켜두는 게 좋다 — 7일 충돌 회피.
    enablePurgeProtection: true
  }
  dependsOn: [
    rg
  ]
}

// -------- 4) UAMI (공용) ------------------------------------------------------

module uami '../../modules/session-00/user-assigned-identity.bicep' = {
  scope: resourceGroup(rgName)
  name: 'uami'
  params: {
    name: uamiName
    location: location
    tags: commonTags
  }
  dependsOn: [
    rg
  ]
}

// -------- 5) Azure OpenAI account ---------------------------------------------

module aoai '../../modules/session-00/aoai-account.bicep' = {
  scope: resourceGroup(rgName)
  name: 'aoai'
  params: {
    name: aoaiName
    location: aoaiLocation
    tags: commonTags
    disableLocalAuth: true
  }
  dependsOn: [
    rg
  ]
}

// -------- 6) AOAI deployments — 직렬화 (409 Conflict 방지) ---------------------

module aoaiChat '../../modules/session-00/aoai-deployment.bicep' = {
  scope: resourceGroup(rgName)
  name: 'aoaiChat'
  params: {
    accountName: aoai.outputs.name
    deploymentName: chatDeploymentName
    modelName: chatModelName
    modelVersion: chatModelVersion
    capacity: chatCapacityK
    // gpt-5 계열은 리전 'Standard' SKU 미지원 — GlobalStandard 필수
    skuName: 'GlobalStandard'
  }
}

module aoaiEmbed '../../modules/session-00/aoai-deployment.bicep' = {
  scope: resourceGroup(rgName)
  name: 'aoaiEmbed'
  params: {
    accountName: aoai.outputs.name
    deploymentName: embedDeploymentName
    modelName: embedModelName
    modelVersion: embedModelVersion
    capacity: embedCapacityK
  }
  // 같은 AOAI account 에 동시 PUT 하면 409 Conflict — chat 이 끝난 후에 embed.
  dependsOn: [
    aoaiChat
  ]
}

// -------- 7) RBAC: UAMI → Cognitive Services OpenAI User -----------------------

module aoaiUserRole '../../modules/session-00/role-assignment-aoai-user.bicep' = {
  scope: resourceGroup(rgName)
  name: 'aoaiUserRole-uami'
  params: {
    aoaiAccountName: aoai.outputs.name
    principalId: uami.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    aoaiChat
    aoaiEmbed
  ]
}

// -------- 8) (선택) 사용자에게도 AOAI User 부여 ---------------------------------
//             로컬 개발 시 az login 자격으로 AOAI 호출 가능하도록.
//             userObjectId 가 비어있으면 skip.

module aoaiUserRoleUser '../../modules/session-00/role-assignment-aoai-user.bicep' = if (!empty(userObjectId)) {
  scope: resourceGroup(rgName)
  name: 'aoaiUserRole-user'
  params: {
    aoaiAccountName: aoai.outputs.name
    principalId: userObjectId
    principalType: 'User'
  }
  dependsOn: [
    aoaiChat
    aoaiEmbed
  ]
}

// -------- 출력 — 후속 세션이 참조 ------------------------------------------------

output rgName string = rg.outputs.name
output lawId string = law.outputs.id
output appInsightsConnectionString string = appInsights.outputs.connectionString
output keyVaultName string = kv.outputs.name
output keyVaultUri string = kv.outputs.vaultUri
output uamiId string = uami.outputs.id
output uamiPrincipalId string = uami.outputs.principalId
output uamiClientId string = uami.outputs.clientId
output aoaiName string = aoai.outputs.name
output aoaiEndpoint string = aoai.outputs.endpoint
output chatDeploymentName string = chatDeploymentName
output embedDeploymentName string = embedDeploymentName
