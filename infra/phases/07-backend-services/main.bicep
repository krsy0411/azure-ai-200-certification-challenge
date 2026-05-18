// Phase 7 — AI 솔루션을 위한 백 엔드 서비스 통합
//
// 학습 경로 'integrate-backend-services-ai-solutions' (3 모듈 × 25 단원) 커버.
// 결정 (사용자 승인: 2026-05-16, A 조합 10개 — docs/learning-paths/07-backend-services.md 참조):
//   ① Service Bus Standard / 큐 단독 / AAD-only
//   ② Event Grid CloudEvents 1.0 / 사용자 지정 토픽 1개 / AAD-only
//   ③ Functions Flex Consumption (koreacentral 확인됨) / Cosmos change feed trigger
//   ④ MCP 서버 생략 / Function App settings 임시 (Phase 8 까지)
//   ⑤ Phase 4·5·6 모두 existing 참조 (Cosmos / AOAI / PG / Redis)
//
// 생성 리소스:
//   - sb-ai200challenge-<env>                    (Service Bus namespace, Standard, AAD-only)
//       └ inference-queue                         (큐 + DLQ + max delivery 5)
//   - egt-ai200challenge-<env>                   (Event Grid 사용자 지정 토픽, CloudEvents 1.0, AAD-only)
//   - stai200challengedev<suffix>                (Storage account — AzureWebJobsStorage + deployment blob)
//   - asp-func-ai200challenge-<env>              (Flex Consumption plan FC1)
//   - func-ai200challenge-<env>                  (Function App — UAMI, Cosmos change feed + SB trigger)
//   - role assignments (UAMI 에): SB Sender/Receiver + EG Sender + Storage Blob Owner
//
// existing 참조 (§7 패턴 — Phase 7 진입 전 Phase 4·5·6 main.bicep 재배포 완료):
//   - ACR (Phase 1) / UAMI / ACA Env (Phase 2)
//   - Cosmos / AOAI (Phase 4) / PG (Phase 5) / Redis (Phase 6)

targetScope = 'resourceGroup'

@description('배포 리전')
param location string = 'koreacentral'

@description('환경 라벨 (dev | prod)')
param environment string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200challenge'

@description('Storage account 전역 유니크 접미사 (Phase 7 신규)')
@minLength(2)
@maxLength(4)
param stSuffix string

@description('Cosmos 계정 전역 유니크 접미사 (Phase 4 와 동일)')
@minLength(2)
@maxLength(4)
param cosmosSuffix string

@description('AOAI 계정 전역 유니크 접미사 (Phase 4 와 동일)')
@minLength(2)
@maxLength(4)
param aoaiSuffix string

@description('PG 서버 전역 유니크 접미사 (Phase 5 와 동일)')
@minLength(2)
@maxLength(4)
param pgSuffix string

@description('Redis 클러스터 전역 유니크 접미사 (Phase 6 와 동일)')
@minLength(2)
@maxLength(4)
param redisSuffix string

@description('PostgreSQL 데이터베이스 이름')
param pgDatabaseName string = 'kb'

@description('Service Bus SKU — Standard 권장')
@allowed([
  'Standard'
  'Premium'
])
param serviceBusSku string = 'Standard'

@description('Function App 인스턴스 메모리 MB — 학습 경로 권장 2048')
@allowed([
  512
  2048
  4096
])
param functionInstanceMemoryMB int = 2048

@description('Function App 최대 인스턴스 수')
@minValue(40)
@maxValue(1000)
param functionMaximumInstanceCount int = 100

// ---- 이름 규칙 ----------------------------------------------------------
var uamiName = 'id-${projectId}-aca-${environment}'
var cosmosName = 'cosmos-${projectId}-${environment}${cosmosSuffix}'
var aoaiName = 'aoai-${projectId}-${environment}${aoaiSuffix}'
var pgName = 'pg-${projectId}-${environment}${pgSuffix}'
var redisName = 'redis-${projectId}-${environment}${redisSuffix}'

var sbName = 'sb-${projectId}-${environment}'
var queueName = 'inference-queue'
var egtName = 'egt-${projectId}-${environment}'
var storageName = 'st${projectId}${environment}${stSuffix}'
var planName = 'asp-func-${projectId}-${environment}'
var functionAppName = 'func-${projectId}-${environment}'
var lawName = 'law-${projectId}-${environment}'
var appInsightsName = 'ai-${projectId}-${environment}'

var commonTags = {
  project: projectId
  env: environment
  phase: '7'
  managedBy: 'bicep'
}

// ---- 0) Phase 1/2/4/5/6 existing 참조 ----------------------------------
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uamiName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-08-15' existing = {
  name: cosmosName
}

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aoaiName
}

resource pgServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: pgName
}

resource redis 'Microsoft.Cache/redisEnterprise@2025-07-01' existing = {
  name: redisName
}

// LAW (Phase 2 산출물) — App Insights workspace-based 연결 대상
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: lawName
}

// ---- 0b) Cosmos lease 컨테이너 (Function Cosmos trigger 가 progress 추적) -
// 함정 4 (Phase 7): Cosmos Built-in Data Contributor 는 data plane 만 (containers/items/*).
// Container *생성* 은 control plane 권한 — UAMI 에 없음. 그래서 Function trigger 의
// create_lease_container_if_not_exists 가 실패 → trigger 발화 자체 안 됨.
// 해결: lease 컨테이너를 Bicep 으로 미리 생성.
module leaseContainer '../../modules/cosmos-sql-container.bicep' = {
  name: 'deploy-cosmos-lease-container'
  params: {
    accountName: cosmos.name
    databaseName: pgDatabaseName
    containerName: 'leases'
    tags: commonTags
    partitionKeyPath: '/id'
  }
}

// ---- 1) Application Insights (Phase 7 built-in 모니터링) -----------------
// Microsoft Learn 명시: Functions 의 built-in integration. 자동 trace/exception/dependency 수집.
// Phase 9 의 사용자 정의 span / 워크북은 별도 책임 (자원 생성과 분리).
module appInsights '../../modules/application-insights.bicep' = {
  name: 'deploy-app-insights'
  params: {
    name: appInsightsName
    location: location
    tags: union(commonTags, { component: 'monitoring' })
    workspaceResourceId: law.id
  }
}

// ---- 2) Service Bus namespace + queue ----------------------------------
module sb '../../modules/service-bus-namespace.bicep' = {
  name: 'deploy-sb-namespace'
  params: {
    name: sbName
    location: location
    tags: commonTags
    skuName: serviceBusSku
  }
}

module sbQueue '../../modules/service-bus-queue.bicep' = {
  name: 'deploy-sb-queue'
  params: {
    namespaceName: sb.outputs.name
    queueName: queueName
    maxDeliveryCount: 5
  }
}

// ---- 2) Event Grid 사용자 지정 토픽 -------------------------------------
module egt '../../modules/event-grid-topic.bicep' = {
  name: 'deploy-eg-topic'
  params: {
    name: egtName
    location: location
    tags: commonTags
  }
}

// ---- 3) Storage account (Function App 동작 + deployment) ---------------
module storage '../../modules/storage-for-functions.bicep' = {
  name: 'deploy-storage'
  params: {
    name: storageName
    location: location
    tags: commonTags
  }
}

// ---- 4) UAMI 에 데이터 평면 RBAC -----------------------------------------
module rbacSbSender '../../modules/role-assignment-servicebus-data-sender.bicep' = {
  name: 'deploy-rbac-sb-sender'
  params: {
    namespaceName: sb.outputs.name
    principalId: uami.properties.principalId
  }
}

module rbacSbReceiver '../../modules/role-assignment-servicebus-data-receiver.bicep' = {
  name: 'deploy-rbac-sb-receiver'
  params: {
    namespaceName: sb.outputs.name
    principalId: uami.properties.principalId
  }
}

module rbacEgSender '../../modules/role-assignment-eventgrid-data-sender.bicep' = {
  name: 'deploy-rbac-eg-sender'
  params: {
    topicName: egt.outputs.name
    principalId: uami.properties.principalId
  }
}

module rbacStorageOwner '../../modules/role-assignment-storage-blob-owner.bicep' = {
  name: 'deploy-rbac-storage-owner'
  params: {
    storageAccountName: storage.outputs.name
    principalId: uami.properties.principalId
  }
}

// ---- 5) Flex Consumption plan -----------------------------------------
module plan '../../modules/function-app-plan-flex.bicep' = {
  name: 'deploy-flex-plan'
  params: {
    name: planName
    location: location
    tags: commonTags
  }
}

// ---- 6) Function App ---------------------------------------------------
// UAMI 로 모든 자원 접근:
// - Cosmos (Phase 4) / AOAI (Phase 4) / PG (Phase 5) / Redis (Phase 6)
// - Service Bus + Event Grid + Storage (Phase 7)
//
// 추가 app settings 는 Function App 내부에서 appSettings 로 주입 (siteConfig 별도 patch 회피 — 단순화).
module functionApp '../../modules/function-app-flex.bicep' = {
  name: 'deploy-function-app'
  params: {
    name: functionAppName
    location: location
    tags: union(commonTags, { component: 'functions' })
    serverFarmId: plan.outputs.id
    userAssignedIdentityId: uami.id
    userAssignedIdentityClientId: uami.properties.clientId
    deploymentStorageValue: storage.outputs.deploymentStorageValue
    storageBlobEndpoint: storage.outputs.blobEndpoint
    storageQueueEndpoint: storage.outputs.queueEndpoint
    storageTableEndpoint: storage.outputs.tableEndpoint
    instanceMemoryMB: functionInstanceMemoryMB
    maximumInstanceCount: functionMaximumInstanceCount
  }
  dependsOn: [
    rbacStorageOwner
    rbacSbSender
    rbacSbReceiver
    rbacEgSender
  ]
}

// ---- 7) Function App 의 데이터 자원 endpoint app settings ---------------
// Function App 모듈은 핵심 settings (AzureWebJobsStorage / AZURE_CLIENT_ID) 만 박음.
// Phase 4·5·6·7 endpoint 등 추가 settings 는 별도 resource 로 patch.
resource appSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  name: '${functionAppName}/appsettings'
  properties: {
    // Function host 필수 (Function App 모듈의 siteConfig 와 merge)
    AzureWebJobsStorage__credential: 'managedidentity'
    AzureWebJobsStorage__clientId: uami.properties.clientId
    AzureWebJobsStorage__blobServiceUri: storage.outputs.blobEndpoint
    AzureWebJobsStorage__queueServiceUri: storage.outputs.queueEndpoint
    AzureWebJobsStorage__tableServiceUri: storage.outputs.tableEndpoint
    // 주의: Flex Consumption 에서 FUNCTIONS_EXTENSION_VERSION / FUNCTIONS_WORKER_RUNTIME 는
    // deprecated — functionAppConfig.runtime 으로 대체됨. 박으면 BadRequest. 함정 2.
    AZURE_CLIENT_ID: uami.properties.clientId

    // Application Insights (Microsoft Learn "built-in integration" — Functions monitoring 가이드)
    // AAD ingest (APPLICATIONINSIGHTS_AUTHENTICATION_STRING=Authorization=AAD) 는 UAMI 에
    // Monitoring Metrics Publisher RBAC 필요. Phase 7 에서는 instrumentation key 기반 ingest
    // 로 폴백 (connection string 만 박음) — 함정 7. Phase 9 에서 정식 AAD ingest + RBAC 추가.
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.outputs.connectionString

    // Phase 4 — Cosmos (change feed source)
    COSMOS_ENDPOINT: cosmos.properties.documentEndpoint
    COSMOS_DB: pgDatabaseName
    COSMOS_CONTAINER_CHUNKS: 'chunks'
    COSMOS_CONNECTION__accountEndpoint: cosmos.properties.documentEndpoint
    COSMOS_CONNECTION__credential: 'managedidentity'
    COSMOS_CONNECTION__clientId: uami.properties.clientId

    // Phase 4 — AOAI (embed)
    AOAI_ENDPOINT: aoai.properties.endpoint
    AOAI_DEPLOYMENT_EMBED: 'text-embedding-3-large'

    // Phase 5 — PostgreSQL
    PG_HOST: pgServer.properties.fullyQualifiedDomainName
    PG_PORT: '5432'
    PG_DATABASE: pgDatabaseName
    PG_USER: uamiName

    // Phase 6 — Redis Enterprise
    REDIS_HOST: redis.properties.hostName
    REDIS_PORT: '10000'
    REDIS_TLS: 'true'
    REDIS_USERNAME: uami.properties.principalId
    REDIS_SEMANTIC_INDEX: 'idx:semantic'
    REDIS_SEMANTIC_PREFIX: 'sc:'

    // Phase 7 — Service Bus + Event Grid
    // service_bus_queue_trigger 의 connection prefix 패턴 — SERVICEBUS_CONNECTION__* 로 resolve.
    // 학습 경로 모듈 1 인증 + functions-bindings-service-bus-trigger docs.
    SERVICEBUS_CONNECTION__fullyQualifiedNamespace: sb.outputs.hostName
    SERVICEBUS_CONNECTION__credential: 'managedidentity'
    SERVICEBUS_CONNECTION__clientId: uami.properties.clientId
    SERVICE_BUS_QUEUE_NAME: queueName

    // EventGrid publisher SDK 용 (Function 코드에서 직접 호출)
    EVENT_GRID_TOPIC_ENDPOINT: egt.outputs.endpoint
    EVENT_GRID_EVENT_TYPE: 'ai200challenge.document.indexed'
  }
  dependsOn: [
    functionApp
  ]
}

// ---- Outputs -----------------------------------------------------------
output serviceBusNamespace string = sb.outputs.name
output serviceBusHostName string = sb.outputs.hostName
output queueName string = sbQueue.outputs.name
output eventGridTopic string = egt.outputs.name
output eventGridEndpoint string = egt.outputs.endpoint
output storageAccount string = storage.outputs.name
output functionAppName string = functionApp.outputs.name
output functionAppHostName string = functionApp.outputs.defaultHostName
