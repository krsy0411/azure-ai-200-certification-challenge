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

// -------- 1) Azure Container Registry 모듈 호출하기 ---------------------------
// 힌트: ../../modules/session-01/acr.bicep 모듈을 호출하고
// 파라미터로 name, location, skuName='Basic', tags 를 전달합니다.

// -------- 2) Azure Container Apps Environment 모듈 호출하기 --------------------
// 힌트: ../../modules/session-01/container-apps-env.bicep 모듈을 호출하고
// logAnalyticsCustomerId 와 logAnalyticsSharedKey 를 위 existing 참조에서 가져옵니다.

// -------- 3) Cosmos DB account · database · container 모듈 호출하기 ------------
// 힌트: 모듈 3개를 순서대로 호출합니다 (cosmos-account, cosmos-sql-database, cosmos-sql-container).
// cosmos-sql-container 는 partitionKeyPath='/doc_id', vectorPath='/embedding',
// vectorDataType='float32', vectorDistanceFunction='cosine', vectorIndexType='quantizedFlat' 사용.

// -------- 4) Key Vault Secret — Azure OpenAI endpoint URL 모듈 호출하기 -------
// 힌트: key-vault-secret.bicep 모듈로 name='aoai-endpoint', value=aoai.properties.endpoint 저장

// -------- 5) 역할 할당 — UAMI 가 ACR · Cosmos · Key Vault 에 접근 -------------
// 힌트: 다음 3개 모듈을 호출합니다.
// - role-assignment-acrpull.bicep (principalType='ServicePrincipal')
// - role-assignment-cosmos-data-contributor.bicep
// - role-assignment-keyvault-secrets-user.bicep (principalType='ServicePrincipal')

// -------- 6) 사용자에게도 Cosmos data plane · Key Vault Secrets 부여 모듈 호출하기 ----
// 힌트: if (!empty(userObjectId)) 조건부 모듈 호출. principalType='User'.

// -------- 7) Azure Container Apps — FastAPI (ca-api) 모듈 호출하기 ------------
// 힌트: container-app.bicep 모듈로 다음을 채웁니다.
// - name = caApiName, targetPort = 8000
// - environmentId, userAssignedIdentityId, userAssignedIdentityClientId, acrLoginServer
// - containerImage = 'api:${apiImageTag}'
// - envVars: AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_CHAT_DEPLOYMENT, AZURE_OPENAI_EMBED_DEPLOYMENT,
//            AZURE_OPENAI_API_VERSION, COSMOS_ENDPOINT, COSMOS_DATABASE, COSMOS_CHUNKS_CONTAINER,
//            APPLICATIONINSIGHTS_CONNECTION_STRING
// - dependsOn 에 위 5)의 RBAC 모듈 3개 명시 (Container App 시작 전 RBAC 부여 완료 보장)

// -------- 8) Azure Container Apps — Next.js (ca-web) 모듈 호출하기 ------------
// 힌트: container-app.bicep 모듈을 다시 호출.
// - name = caWebName, targetPort = 3000
// - envVars 는 API_BASE_URL = 'https://${caApi.outputs.fqdn}' 한 개

// -------- 출력 — 후속 세션이 참조 -----------------------------------------------
// 힌트: acrName, acrLoginServer, caeName, caApiFqdn, caWebFqdn,
//      cosmosName, cosmosEndpoint, cosmosDatabaseName, cosmosChunksContainerName
