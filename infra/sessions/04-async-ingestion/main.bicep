// =============================================================================
// session-04 — 비동기 인제스션 (Service Bus + Event Grid + Azure Functions)
//
// 배포 명령:
//   OID=$(az ad signed-in-user show --query id -o tsv)
//   az deployment group create \
//     --resource-group rg-ai200ws-dev \
//     --template-file workshop/infra/sessions/04-async-ingestion/main.bicep \
//     --parameters workshop/infra/sessions/04-async-ingestion/main.bicepparam \
//     --parameters userObjectId=$OID
//
// 의존성 (existing 참조):
//   - session-00: UAMI, Azure OpenAI, Application Insights
//   - session-01: Cosmos DB account (appdb)
//   - session-02: PostgreSQL Flexible Server (UAMI 가 Entra 관리자로 등록됨)
//
// 본 세션에서 신규 생성:
//   - Service Bus (Standard) + ingest-queue (DLQ max delivery 5)
//   - Storage (allowSharedKeyAccess=false) + documents/deployments 컨테이너
//   - Event Grid System Topic (Blob 소스) + Service Bus 로 전달하는 subscription
//   - Function App (Flex Consumption) + Flex plan
//   - Cosmos lease + doc_stats 컨테이너 (change feed)
//   - 역할 할당: UAMI→SB Receiver / 시스템토픽→SB Sender / UAMI→Storage Blob·Queue
// =============================================================================

targetScope = 'resourceGroup'

@description('환경 라벨')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('Azure 자원 기본 리전')
param location string = resourceGroup().location

@description('배포 실행자의 Entra objectId (현재 미사용 — 후속 확장 대비). CLI override.')
param userObjectId string = ''

// -------- 공용 태그 ------------------------------------------------------------

var commonTags = {
  project: projectId
  env: env
  workshop: 'azure-ai-200'
  managedBy: 'bicep'
  session: 'session-04'
}

// -------- 내장 역할 정의 GUID ---------------------------------------------------

var roleServiceBusDataReceiver = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
var roleServiceBusDataSender = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
var roleStorageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var roleStorageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var roleStorageQueueDataContributor = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'

// -------- 자원 이름 ------------------------------------------------------------

var sbName = take('sb-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 50)
var stName = take('st${projectId}${env}${uniqueString(resourceGroup().id, projectId, env)}', 24)
var egtName = 'egt-${projectId}-${env}'
var funcName = take('func-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 60)
var aspName = 'asp-${projectId}-${env}-flex'

// session-00~02 자원 이름 (각 세션 main.bicep 과 동일 규칙)
var uamiName = 'id-${projectId}-${env}'
var aiName = 'ai-${projectId}-${env}'
var cosmosName = take('cosmos-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 44)
var aoaiName = take('aoai-${projectId}-${env}-${uniqueString(subscription().id, projectId, env)}', 60)
var pgName = take('pg-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 63)

// -------- existing 참조 --------------------------------------------------------

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: uamiName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: aiName
}

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aoaiName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosName
}

// -------- 1) Service Bus namespace + queue --------------------------------------

module serviceBus '../../modules/session-04/service-bus-namespace.bicep' = {
  name: 'serviceBus'
  params: {
    name: sbName
    location: location
    skuName: 'Standard'
    tags: commonTags
  }
}

module ingestQueue '../../modules/session-04/service-bus-queue.bicep' = {
  name: 'ingestQueue'
  params: {
    namespaceName: serviceBus.outputs.name
    name: 'ingest-queue'
    maxDeliveryCount: 5
  }
}

// -------- 2) Storage (키 인증 off) ----------------------------------------------

module storage '../../modules/session-04/storage-account.bicep' = {
  name: 'storage'
  params: {
    name: stName
    location: location
    tags: commonTags
  }
}

// -------- 3) Event Grid system topic + subscription -----------------------------

module systemTopic '../../modules/session-04/event-grid-system-topic.bicep' = {
  name: 'systemTopic'
  params: {
    name: egtName
    location: location
    sourceStorageAccountId: storage.outputs.id
    tags: commonTags
  }
}

// 시스템 토픽 ID → Service Bus Data Sender (EG 가 SB 큐로 전달하려면 필요)
module sbSenderSystemTopic '../../modules/session-04/role-assignment-servicebus.bicep' = {
  name: 'sbSender-systemTopic'
  params: {
    namespaceName: serviceBus.outputs.name
    roleDefinitionId: roleServiceBusDataSender
    principalId: systemTopic.outputs.principalId
  }
}

module egSubscription '../../modules/session-04/event-grid-subscription.bicep' = {
  name: 'egSubscription'
  params: {
    systemTopicName: systemTopic.outputs.name
    name: 'to-service-bus'
    serviceBusQueueId: resourceId(
      'Microsoft.ServiceBus/namespaces/queues',
      serviceBus.outputs.name,
      'ingest-queue'
    )
    // documents 컨테이너만 인제스션 트리거 (deployments 컨테이너 함수 배포 zip 제외).
    subjectBeginsWith: '/blobServices/default/containers/documents/'
  }
  dependsOn: [
    ingestQueue
    sbSenderSystemTopic
  ]
}

// -------- 4) 역할 할당 — UAMI -> Service Bus 수신 / Storage Blob·Queue -----------

module sbReceiverUami '../../modules/session-04/role-assignment-servicebus.bicep' = {
  name: 'sbReceiver-uami'
  params: {
    namespaceName: serviceBus.outputs.name
    roleDefinitionId: roleServiceBusDataReceiver
    principalId: uami.properties.principalId
  }
}

module blobOwnerUami '../../modules/session-04/role-assignment-storage.bicep' = {
  name: 'blobOwner-uami'
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionId: roleStorageBlobDataOwner
    principalId: uami.properties.principalId
  }
}

module queueContributorUami '../../modules/session-04/role-assignment-storage.bicep' = {
  name: 'queueContributor-uami'
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionId: roleStorageQueueDataContributor
    principalId: uami.properties.principalId
  }
}

// -------- 4b) (선택) 사용자 검증용 권한 ----------------------------------------
//              E2E 테스트: az storage blob upload --auth-mode login (Blob Data Contributor),
//              실패 시뮬레이션: az servicebus message send (Service Bus Data Sender).

module blobContributorUser '../../modules/session-04/role-assignment-storage.bicep' = if (!empty(userObjectId)) {
  name: 'blobContributor-user'
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionId: roleStorageBlobDataContributor
    principalId: userObjectId
    principalType: 'User'
  }
}

module sbSenderUser '../../modules/session-04/role-assignment-servicebus.bicep' = if (!empty(userObjectId)) {
  name: 'sbSender-user'
  params: {
    namespaceName: serviceBus.outputs.name
    roleDefinitionId: roleServiceBusDataSender
    principalId: userObjectId
    principalType: 'User'
  }
}

// -------- 5) Cosmos lease + doc_stats 컨테이너 (change feed) ---------------------

module leaseContainer '../../modules/session-04/cosmos-container.bicep' = {
  name: 'leaseContainer'
  params: {
    accountName: cosmos.name
    name: 'leases'
    partitionKeyPath: '/id'
  }
}

module statsContainer '../../modules/session-04/cosmos-container.bicep' = {
  name: 'statsContainer'
  params: {
    accountName: cosmos.name
    name: 'doc_stats'
    partitionKeyPath: '/doc_id'
  }
}

// -------- 5b) PostgreSQL 방화벽 — Azure 서비스 허용 ------------------------------
//             Function App(Azure 호스팅) 이 UAMI 로 PG 에 접속하려면 PG 방화벽이 Azure
//             서비스를 허용해야 한다 (0.0.0.0 특수 규칙). session-02 는 dev IP 만 열므로
//             여기서 추가. 없으면 함수의 _upsert_pg 가 connection timeout 으로 실패한다.

module pgAllowAzure '../../modules/session-02/postgres-firewall-rule.bicep' = {
  name: 'pgAllowAzure'
  params: {
    serverName: pgName
    name: 'AllowAllAzureServices'
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// -------- 6) Function App (Flex Consumption) ------------------------------------

module plan '../../modules/session-04/function-app-plan-flex.bicep' = {
  name: 'plan'
  params: {
    name: aspName
    location: location
    tags: commonTags
  }
}

module functionApp '../../modules/session-04/function-app-flex.bicep' = {
  name: 'functionApp'
  params: {
    name: funcName
    location: location
    planId: plan.outputs.id
    uamiId: uami.id
    uamiClientId: uami.properties.clientId
    storageAccountName: storage.outputs.name
    storageBlobEndpoint: storage.outputs.blobEndpoint
    deploymentContainerName: storage.outputs.deploymentContainerName
    appInsightsConnectionString: appInsights.properties.ConnectionString
    serviceBusFqdn: serviceBus.outputs.fqdn
    aoaiEndpoint: aoai.properties.endpoint
    cosmosEndpoint: cosmos.properties.documentEndpoint
    cosmosDatabaseName: 'appdb'
    postgresHost: '${pgName}.postgres.database.azure.com'
    postgresUser: uamiName
    tags: commonTags
  }
  // Storage 역할이 부여된 후에 Function 이 시작되도록 (부팅 시 Storage 접근)
  dependsOn: [
    blobOwnerUami
    queueContributorUami
    sbReceiverUami
    pgAllowAzure
  ]
}

// -------- 출력 -----------------------------------------------------------------

output serviceBusName string = serviceBus.outputs.name
output storageName string = storage.outputs.name
output functionAppName string = functionApp.outputs.name
output systemTopicName string = systemTopic.outputs.name