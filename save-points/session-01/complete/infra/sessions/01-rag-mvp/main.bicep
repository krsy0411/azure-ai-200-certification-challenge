// =============================================================================
// session-01 — RAG MVP on Azure Container Apps + Key Vault + OpenTelemetry
//
// 배포 명령:
//   az deployment group create \
//     --resource-group rg-ai200ws-dev \
//     --template-file infra/sessions/01-rag-mvp/main.bicep \
//     --parameters infra/sessions/01-rag-mvp/main.bicepparam \
//     --parameters userObjectId=$(az ad signed-in-user show --query id -o tsv)
//
// 의존성:
//   - session-00 이 만든 자원 (UAMI, Log Analytics, Application Insights, Key Vault,
//     Azure OpenAI) 을 existing 으로 참조한다.
//
// 본 세션에서 신규 생성:
//   - Azure Container Registry · Azure Container Apps Environment
//   - Azure Container Apps Container App × 2 (ca-api, ca-web)
//   - Cosmos DB account · database · container (vector policy)
//   - Key Vault Secret 1개 (aoai-endpoint)
//   - 역할 할당 3개 (UAMI 가 ACR/Cosmos/KV 에 접근)
// =============================================================================

targetScope = 'resourceGroup'

// -------- 파라미터 -------------------------------------------------------------

@description('환경 라벨 (예: dev, prod)')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('Azure 자원 기본 리전')
param location string = resourceGroup().location

@description('배포 실행자의 Entra objectId. 로컬 개발 시 Cosmos · Key Vault 접근용. 비우면 skip.')
param userObjectId string = ''

// -------- 컨테이너 이미지 태그 --------------------------------------------------

@description('FastAPI 이미지 태그 (예: s01, latest)')
param apiImageTag string = ''

@description('Next.js 이미지 태그')
param webImageTag string = ''

// -------- Cosmos DB 파라미터 ----------------------------------------------------

@description('Cosmos DB database 이름')
param cosmosDatabaseName string = 'appdb'

@description('Cosmos DB chunks container 이름')
param cosmosChunksContainerName string = 'chunks'

@description('Vector 임베딩 차원 수 — text-embedding-3-large 는 3072')
param vectorDimensions int = 3072

// -------- 공용 태그 ------------------------------------------------------------

var commonTags = {
  project: projectId
  env: env
  workshop: 'azure-ai-200'
  managedBy: 'bicep'
  session: 'session-01'
}

// -------- 자원 이름 ------------------------------------------------------------

// ACR · Storage 는 글로벌 unique + 하이픈 금지. uniqueString 으로 충돌 회피.
var acrName = take('acr${projectId}${env}${uniqueString(resourceGroup().id, projectId, env)}', 50)

var caeName = 'cae-${projectId}-${env}'
var caApiName = 'ca-api-${projectId}-${env}'
var caWebName = 'ca-web-${projectId}-${env}'

// Cosmos: 글로벌 unique.
var cosmosName = take('cosmos-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 44)

// session-00 자원 이름 (session-00 의 main.bicep 과 동일 규칙)
var lawName = 'law-${projectId}-${env}'
var aiName = 'ai-${projectId}-${env}'
var uamiName = 'id-${projectId}-${env}'
var kvName = take('kv-${projectId}-${env}-${uniqueString(subscription().id, projectId, env)}', 24)
var aoaiName = take('aoai-${projectId}-${env}-${uniqueString(subscription().id, projectId, env)}', 60)

// -------- session-00 자원 existing 참조 -----------------------------------------

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: lawName
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: uamiName
}

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aoaiName
}

resource kv 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: kvName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: aiName
}

// Log Analytics shared key 는 listKeys 호출로 가져옴 (Container Apps Env 가 요구).
// @secure() 출력 없이 직접 listKeys 사용 — Bicep 의 표준 패턴.
var logAnalyticsSharedKey = law.listKeys().primarySharedKey

// -------- 1) Azure Container Registry -------------------------------------------

module acr '../../modules/session-01/acr.bicep' = {
  name: 'acr'
  params: {
    name: acrName
    location: location
    skuName: 'Basic'
    tags: commonTags
  }
}

// -------- 2) Azure Container Apps Environment -----------------------------------

module cae '../../modules/session-01/container-apps-env.bicep' = {
  name: 'cae'
  params: {
    name: caeName
    location: location
    logAnalyticsCustomerId: law.properties.customerId
    logAnalyticsSharedKey: logAnalyticsSharedKey
    tags: commonTags
  }
}

// -------- 3) Cosmos DB account · database · container --------------------------

module cosmos '../../modules/session-01/cosmos-account.bicep' = {
  name: 'cosmos'
  params: {
    name: cosmosName
    location: location
    capacityMode: 'Serverless'
    disableLocalAuth: true
    tags: commonTags
  }
}

module cosmosDatabase '../../modules/session-01/cosmos-sql-database.bicep' = {
  name: 'cosmosDatabase'
  params: {
    accountName: cosmos.outputs.name
    name: cosmosDatabaseName
  }
}

module cosmosChunksContainer '../../modules/session-01/cosmos-sql-container.bicep' = {
  name: 'cosmosChunksContainer'
  params: {
    accountName: cosmos.outputs.name
    databaseName: cosmosDatabase.outputs.name
    name: cosmosChunksContainerName
    partitionKeyPath: '/doc_id'
    vectorDimensions: vectorDimensions
    vectorPath: '/embedding'
    vectorDataType: 'float32'
    vectorDistanceFunction: 'cosine'
    vectorIndexType: 'quantizedFlat'
  }
}

// -------- 4) Key Vault Secret — Azure OpenAI endpoint URL ----------------------
//             endpoint URL 자체는 시크릿이 아니지만, Key Vault 에 저장하고 코드에서
//             SDK 로 읽어오는 Key Vault reference 패턴을 학습하기 위해 한 개를 저장한다.

module aoaiEndpointSecret '../../modules/session-01/key-vault-secret.bicep' = {
  name: 'aoaiEndpointSecret'
  params: {
    keyVaultName: kv.name
    name: 'aoai-endpoint'
    value: aoai.properties.endpoint
    contentType: 'text/plain'
  }
}

// -------- 5) 역할 할당 — UAMI 가 ACR · Cosmos · Key Vault 에 접근 ----------------

module acrPullRoleUami '../../modules/session-01/role-assignment-acrpull.bicep' = {
  name: 'acrPullRole-uami'
  params: {
    acrName: acr.outputs.name
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

module cosmosDataRoleUami '../../modules/session-01/role-assignment-cosmos-data-contributor.bicep' = {
  name: 'cosmosDataRole-uami'
  params: {
    cosmosAccountName: cosmos.outputs.name
    principalId: uami.properties.principalId
  }
}

module kvSecretsRoleUami '../../modules/session-01/role-assignment-keyvault-secrets-user.bicep' = {
  name: 'kvSecretsRole-uami'
  params: {
    keyVaultName: kv.name
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// -------- 6) 사용자에게도 Cosmos data plane · Key Vault Secrets 부여 -----------
//             로컬 개발 시 az login 자격으로 데이터 확인이 가능하도록.

module cosmosDataRoleUser '../../modules/session-01/role-assignment-cosmos-data-contributor.bicep' = if (!empty(userObjectId)) {
  name: 'cosmosDataRole-user'
  params: {
    cosmosAccountName: cosmos.outputs.name
    principalId: userObjectId
  }
}

module kvSecretsRoleUser '../../modules/session-01/role-assignment-keyvault-secrets-user.bicep' = if (!empty(userObjectId)) {
  name: 'kvSecretsRole-user'
  params: {
    keyVaultName: kv.name
    principalId: userObjectId
    principalType: 'User'
  }
}

// -------- 7) Azure Container Apps — FastAPI (ca-api) ----------------------------

module caApi '../../modules/session-01/container-app.bicep' = {
  name: 'caApi'
  params: {
    name: caApiName
    location: location
    environmentId: cae.outputs.id
    userAssignedIdentityId: uami.id
    userAssignedIdentityClientId: uami.properties.clientId
    acrLoginServer: acr.outputs.loginServer
    containerImage: empty(apiImageTag) ? '' : 'api:${apiImageTag}'
    targetPort: 8000
    externalIngress: true
    minReplicas: 0
    maxReplicas: 3
    cpu: '0.5'
    memory: '1Gi'
    envVars: [
      {
        name: 'AZURE_OPENAI_ENDPOINT'
        value: aoai.properties.endpoint
      }
      {
        name: 'AZURE_OPENAI_CHAT_DEPLOYMENT'
        value: 'gpt-5-mini'
      }
      {
        name: 'AZURE_OPENAI_EMBED_DEPLOYMENT'
        value: 'text-embedding-3-large'
      }
      {
        name: 'AZURE_OPENAI_API_VERSION'
        value: '2024-08-01-preview'
      }
      {
        name: 'COSMOS_ENDPOINT'
        value: cosmos.outputs.endpoint
      }
      {
        name: 'COSMOS_DATABASE'
        value: cosmosDatabaseName
      }
      {
        name: 'COSMOS_CHUNKS_CONTAINER'
        value: cosmosChunksContainerName
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: appInsights.properties.ConnectionString
      }
    ]
    tags: commonTags
  }
  dependsOn: [
    acrPullRoleUami
    cosmosDataRoleUami
    kvSecretsRoleUami
  ]
}

// -------- 8) Azure Container Apps — Next.js (ca-web) ----------------------------

module caWeb '../../modules/session-01/container-app.bicep' = {
  name: 'caWeb'
  params: {
    name: caWebName
    location: location
    environmentId: cae.outputs.id
    userAssignedIdentityId: uami.id
    userAssignedIdentityClientId: uami.properties.clientId
    acrLoginServer: acr.outputs.loginServer
    containerImage: empty(webImageTag) ? '' : 'web:${webImageTag}'
    targetPort: 3000
    externalIngress: true
    minReplicas: 0
    maxReplicas: 3
    cpu: '0.25'
    memory: '0.5Gi'
    envVars: [
      {
        // Next.js 서버 사이드에서 ca-api 를 호출. ACA 내부 통신 가능하나 학습 단순화를 위해 external FQDN 사용.
        name: 'API_BASE_URL'
        value: 'https://${caApi.outputs.fqdn}'
      }
    ]
    tags: commonTags
  }
  // caWeb 는 envVars 에서 caApi.outputs.fqdn 을 참조하므로 caApi 의존은 자동으로 잡힌다.
  // ACR pull 권한만 명시적으로 먼저 끝나도록 dependsOn 에 둔다.
  dependsOn: [
    acrPullRoleUami
  ]
}

// -------- 출력 — 후속 세션이 참조 ------------------------------------------------

output acrName string = acr.outputs.name
output acrLoginServer string = acr.outputs.loginServer
output caeName string = cae.outputs.name
output caApiFqdn string = caApi.outputs.fqdn
output caWebFqdn string = caWeb.outputs.fqdn
output cosmosName string = cosmos.outputs.name
output cosmosEndpoint string = cosmos.outputs.endpoint
output cosmosDatabaseName string = cosmosDatabaseName
output cosmosChunksContainerName string = cosmosChunksContainerName
