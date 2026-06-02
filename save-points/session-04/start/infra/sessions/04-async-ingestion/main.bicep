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
// 본 세션에서 할 일:
//   아래 그룹별 모듈 호출과 출력 블록을 직접 채운다. 모듈 본체는
//   ../../modules/session-04/ 에 이미 완성되어 있다 (수정하지 않는다).
//   완성본은 save-points/session-04/complete/ 또는 docs 참고.
// =============================================================================

targetScope = 'resourceGroup'

@description('환경 라벨')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('Azure 자원 기본 리전')
param location string = resourceGroup().location

@description('배포 실행자의 Entra objectId. 검증용 권한(Blob 업로드·SB 송신) 부여. CLI override.')
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

// -------- 1) Service Bus namespace + queue 모듈 호출하기 ------------------------
// 힌트: service-bus-namespace.bicep (skuName='Standard') →
//       service-bus-queue.bicep (namespaceName=serviceBus.outputs.name, name='ingest-queue',
//       maxDeliveryCount=5).

// -------- 2) Storage (키 인증 off) 모듈 호출하기 -------------------------------
// 힌트: storage-account.bicep (name=stName, location, tags).

// -------- 3) Event Grid system topic + 역할 + subscription 모듈 호출하기 -------
// 힌트: event-grid-system-topic.bicep (sourceStorageAccountId=storage.outputs.id) →
//       role-assignment-servicebus.bicep 로 systemTopic.outputs.principalId 에
//       roleServiceBusDataSender 부여 → event-grid-subscription.bicep
//       (serviceBusQueueId=resourceId('Microsoft.ServiceBus/namespaces/queues',
//        serviceBus.outputs.name, 'ingest-queue'), dependsOn 에 queue·sender).

// -------- 4) 역할 할당 — UAMI → SB 수신 / Storage Blob·Queue 모듈 호출하기 -----
// 힌트: role-assignment-servicebus.bicep (roleServiceBusDataReceiver) +
//       role-assignment-storage.bicep ×2 (roleStorageBlobDataOwner,
//       roleStorageQueueDataContributor), principalId=uami.properties.principalId.

// -------- 4b) (선택) 사용자 검증용 권한 모듈 호출하기 -------------------------
// 힌트: if (!empty(userObjectId)) 로 Storage Blob Data Contributor + Service Bus Data Sender
//       를 userObjectId 에 부여 (principalType='User'). E2E 업로드·실패 시뮬레이션용.

// -------- 5) Cosmos lease + doc_stats 컨테이너 모듈 호출하기 -------------------
// 힌트: cosmos-container.bicep ×2 — name='leases'(partitionKeyPath='/id'),
//       name='doc_stats'(partitionKeyPath='/doc_id'), accountName=cosmos.name.

// -------- 6) Function App (Flex Consumption) 모듈 호출하기 ---------------------
// 힌트: function-app-plan-flex.bicep → function-app-flex.bicep.
//       function-app-flex 파라미터: planId, uamiId=uami.id, uamiClientId,
//       storageAccountName/blobEndpoint/deploymentContainerName,
//       appInsightsConnectionString, serviceBusFqdn, aoaiEndpoint,
//       cosmosEndpoint=cosmos.properties.documentEndpoint, cosmosDatabaseName='appdb',
//       postgresHost='${pgName}.postgres.database.azure.com', postgresUser=uamiName.
//       dependsOn 에 Storage·SB 역할을 명시 (부팅 전 RBAC 보장).

// -------- 출력 -----------------------------------------------------------------
// 힌트: serviceBusName, storageName, functionAppName, systemTopicName.