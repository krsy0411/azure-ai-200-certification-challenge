// Phase 4 — Cosmos DB for NoSQL (벡터) + Azure OpenAI (gpt-4o-mini, text-embedding-3-large)
//
// 생성/갱신 리소스 (rg-ai200challenge-<env> 안):
//   - cosmos-ai200challenge-<env><suffix>            (계정, NoSQL, Serverless, AAD-only, vector capability)
//       └ kb (DB)
//           ├ documents (pk=/workspaceId)
//           └ chunks    (pk=/workspaceId, vector=embedding 3072-d float32 cosine, quantizedFlat index)
//   - aoai-ai200challenge-<env><suffix>              (Microsoft.CognitiveServices/accounts kind=OpenAI, AAD-only)
//       ├ deployment: gpt-4o-mini
//       └ deployment: text-embedding-3-large         (gpt deployment 에 dependsOn — 동시 PUT 충돌 회피)
//   - sqlRoleAssignment    (UAMI → Cosmos DB Built-in Data Contributor)
//   - roleAssignment       (UAMI → Cognitive Services OpenAI User on AOAI 계정)
//
// 갱신 리소스:
//   - ca-ai200challenge-api-<env>  (Phase 2 의 api Container App 에 envVars 주입)
//
// existing 참조:
//   - ACR (Phase 1)
//   - UAMI / ACA Env (Phase 2)
//
// 변경 피드 → Function 자동 임베딩은 Phase 7 (Functions) 으로 이관.

targetScope = 'resourceGroup'

@description('배포 리전')
param location string = 'koreacentral'

@description('환경 라벨 (dev | prod)')
param environment string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200challenge'

@description('Cosmos 계정 이름 전역 유니크 접미사 (소문자/숫자 2~4자)')
@minLength(2)
@maxLength(4)
param cosmosSuffix string

@description('AOAI 계정 이름 전역 유니크 접미사 (소문자/숫자 2~4자)')
@minLength(2)
@maxLength(4)
param aoaiSuffix string

@description('ACR 전역 유니크 접미사 (Phase 1 과 동일해야 같은 ACR 참조)')
@minLength(2)
@maxLength(4)
param acrSuffix string

@description('ACA 에 배포할 이미지 태그 — Phase 2 와 동일 이미지 재사용')
param imageTag string = '0.1.0'

@description('Cosmos DB 이름')
param cosmosDatabaseName string = 'kb'

@description('AOAI gpt-4o-mini deployment 이름')
param aoaiChatDeploymentName string = 'gpt-4o-mini'

@description('AOAI gpt-4o-mini 모델 버전')
param aoaiChatModelVersion string = '2024-07-18'

@description('AOAI gpt-4o-mini SKU capacity (1 단위 = 1000 TPM)')
@minValue(1)
param aoaiChatCapacity int = 30

@description('AOAI text-embedding-3-large deployment 이름')
param aoaiEmbedDeploymentName string = 'text-embedding-3-large'

@description('AOAI text-embedding-3-large 모델 버전')
param aoaiEmbedModelVersion string = '1'

@description('AOAI text-embedding-3-large SKU capacity')
@minValue(1)
param aoaiEmbedCapacity int = 30

// ---- 이름 규칙 ----------------------------------------------------------
var acrName = 'acr${projectId}${environment}${acrSuffix}'
var uamiName = 'id-${projectId}-aca-${environment}'
var caeName = 'cae-${projectId}-${environment}'
var apiAppName = 'ca-${projectId}-api-${environment}'
var cosmosName = 'cosmos-${projectId}-${environment}${cosmosSuffix}'
var aoaiName = 'aoai-${projectId}-${environment}${aoaiSuffix}'

var commonTags = {
  project: projectId
  env: environment
  phase: '4'
  managedBy: 'bicep'
}

// ---- 0) Phase 1/2 existing 참조 ----------------------------------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uamiName
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

// ---- 1) Cosmos 계정 -----------------------------------------------------
module cosmos '../../modules/cosmos-account.bicep' = {
  name: 'deploy-cosmos-account'
  params: {
    name: cosmosName
    location: location
    tags: commonTags
  }
}

// ---- 2) Cosmos DB (kb) --------------------------------------------------
module cosmosDb '../../modules/cosmos-sql-database.bicep' = {
  name: 'deploy-cosmos-db'
  params: {
    accountName: cosmos.outputs.name
    databaseName: cosmosDatabaseName
    tags: commonTags
  }
}

// ---- 3) Cosmos containers ----------------------------------------------
// documents: 메타데이터만, vector 없음
module cosmosDocuments '../../modules/cosmos-sql-container.bicep' = {
  name: 'deploy-cosmos-c-documents'
  params: {
    accountName: cosmos.outputs.name
    databaseName: cosmosDb.outputs.name
    containerName: 'documents'
    partitionKeyPath: '/workspaceId'
    tags: commonTags
  }
}

// chunks: text + 3072-d embedding (text-embedding-3-large 차원에 맞춤)
module cosmosChunks '../../modules/cosmos-sql-container.bicep' = {
  name: 'deploy-cosmos-c-chunks'
  params: {
    accountName: cosmos.outputs.name
    databaseName: cosmosDb.outputs.name
    containerName: 'chunks'
    partitionKeyPath: '/workspaceId'
    vectorEmbeddingPaths: [
      '/embedding'
    ]
    vectorDimensions: 3072
    vectorDataType: 'float32'
    vectorDistanceFunction: 'cosine'
    vectorIndexType: 'quantizedFlat'
    tags: commonTags
  }
}

// ---- 4) UAMI → Cosmos data plane (Built-in Data Contributor) -----------
module cosmosRbac '../../modules/role-assignment-cosmos-data-contributor.bicep' = {
  name: 'ra-cosmos-data-uami'
  params: {
    accountName: cosmos.outputs.name
    principalId: uami.properties.principalId
  }
}

// ---- 5) AOAI 계정 ------------------------------------------------------
module aoai '../../modules/aoai-account.bicep' = {
  name: 'deploy-aoai-account'
  params: {
    name: aoaiName
    location: location
    tags: commonTags
  }
}

// ---- 6) AOAI deployments (직렬화 — 동시 PUT 시 409 회피) ----------------
module aoaiChat '../../modules/aoai-deployment.bicep' = {
  name: 'deploy-aoai-chat'
  params: {
    accountName: aoai.outputs.name
    deploymentName: aoaiChatDeploymentName
    modelName: 'gpt-4o-mini'
    modelVersion: aoaiChatModelVersion
    // koreacentral 에서 gpt-4o-mini@2024-07-18 은 GlobalStandard SKU 만 제공 (2026-04 확인).
    // 데이터 region 보장이 깨지지만 학습용이라 수용.
    skuName: 'GlobalStandard'
    skuCapacity: aoaiChatCapacity
  }
}

module aoaiEmbed '../../modules/aoai-deployment.bicep' = {
  name: 'deploy-aoai-embed'
  params: {
    accountName: aoai.outputs.name
    deploymentName: aoaiEmbedDeploymentName
    modelName: 'text-embedding-3-large'
    modelVersion: aoaiEmbedModelVersion
    skuName: 'Standard'
    skuCapacity: aoaiEmbedCapacity
  }
  dependsOn: [
    aoaiChat
  ]
}

// ---- 7) UAMI → AOAI 'Cognitive Services OpenAI User' -------------------
module aoaiRbac '../../modules/role-assignment-aoai-user.bicep' = {
  name: 'ra-aoai-user-uami'
  params: {
    accountName: aoai.outputs.name
    principalId: uami.properties.principalId
  }
}

// ---- 8) api Container App 갱신 — envVars 주입 --------------------------
// Phase 2 와 동일 모듈을 같은 이름·같은 사양으로 다시 호출.
// targetPort 등은 Phase 2 와 정확히 일치해야 ACA 가 부분 갱신이 아니라
// 의도된 사양 전체로 수렴.
module apiApp '../../modules/container-app.bicep' = {
  name: 'deploy-ca-api'
  params: {
    name: apiAppName
    location: location
    tags: union(commonTags, { component: 'api' })
    environmentId: cae.id
    acrLoginServer: acr.properties.loginServer
    userAssignedIdentityId: uami.id
    imageName: 'api'
    imageTag: imageTag
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
  dependsOn: [
    cosmosRbac
    aoaiRbac
  ]
}

// ---- Outputs -----------------------------------------------------------
output cosmosAccountName string = cosmos.outputs.name
output cosmosDocumentEndpoint string = cosmos.outputs.documentEndpoint
output cosmosDatabaseName string = cosmosDb.outputs.name
output cosmosContainerDocuments string = cosmosDocuments.outputs.name
output cosmosContainerChunks string = cosmosChunks.outputs.name
output aoaiAccountName string = aoai.outputs.name
output aoaiEndpoint string = aoai.outputs.endpoint
output aoaiChatDeployment string = aoaiChat.outputs.name
output aoaiEmbedDeployment string = aoaiEmbed.outputs.name
output apiInternalFqdn string = apiApp.outputs.fqdn
