// =============================================================================
// session-03 — Managed Redis 시맨틱 캐시
//
// 배포 명령:
//   OID=$(az ad signed-in-user show --query id -o tsv)
//   az deployment group create \
//     --resource-group rg-ai200ws-dev \
//     --template-file infra/sessions/03-redis-cache/main.bicep \
//     --parameters infra/sessions/03-redis-cache/main.bicepparam \
//     --parameters userObjectId=$OID
//
// 의존성:
//   - session-00 의 User Assigned Managed Identity 를 existing 으로 참조해
//     그 principalId 를 Redis access policy 에 부여한다 (별도 CLI 파라미터 불필요).
//
// 본 세션에서 신규 생성:
//   - Azure Managed Redis (Redis Enterprise) 클러스터 — Balanced_B0 (최소 등급)
//   - 데이터베이스 default — RediSearch 모듈, evictionPolicy=NoEviction, Entra 전용 인증
//   - access policy assignment 2개 — UAMI + 배포 사용자
//
// 주의: access policy assignment 를 동시에 만들면 클러스터가 Updating 상태라 충돌할 수
//       있으므로 dependsOn 으로 직렬화한다.
// =============================================================================

targetScope = 'resourceGroup'

// -------- 파라미터 -------------------------------------------------------------

@description('환경 라벨 (예: dev, prod)')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('Azure 자원 기본 리전')
param location string = resourceGroup().location

@description('배포 실행자의 Entra objectId. 로컬 개발 시 Redis 데이터 접근용. 비우면 skip.')
param userObjectId string = ''

// -------- 공용 태그 ------------------------------------------------------------

var commonTags = {
  project: projectId
  env: env
  workshop: 'azure-ai-200'
  managedBy: 'bicep'
  session: 'session-03'
}

// -------- 자원 이름 ------------------------------------------------------------

// Azure Managed Redis: 글로벌 unique (DNS). uniqueString 접미사로 충돌 회피.
var redisName = take('redis-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 60)

// session-00 자원 이름 (session-00 의 main.bicep 과 동일 규칙)
var uamiName = 'id-${projectId}-${env}'

// -------- session-00 자원 existing 참조 -----------------------------------------

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: uamiName
}

// -------- 1) Azure Managed Redis 클러스터 ---------------------------------------

module redis '../../modules/session-03/redis-enterprise.bicep' = {
  name: 'redis'
  params: {
    name: redisName
    location: location
    skuName: 'Balanced_B0'
    tags: commonTags
  }
}

// -------- 2) 데이터베이스 default — RediSearch + NoEviction + Entra 전용 ---------

module redisDatabase '../../modules/session-03/redis-enterprise-database.bicep' = {
  name: 'redisDatabase'
  params: {
    clusterName: redis.outputs.name
  }
}

// -------- 3) access policy assignment — UAMI ------------------------------------

module accessUami '../../modules/session-03/redis-access-policy-assignment.bicep' = {
  name: 'accessUami'
  params: {
    clusterName: redis.outputs.name
    principalObjectId: uami.properties.principalId
  }
  dependsOn: [
    redisDatabase
  ]
}

// -------- 4) access policy assignment — 배포 사용자 (선택) -----------------------

module accessUser '../../modules/session-03/redis-access-policy-assignment.bicep' = if (!empty(userObjectId)) {
  name: 'accessUser'
  params: {
    clusterName: redis.outputs.name
    principalObjectId: userObjectId
  }
  dependsOn: [
    accessUami
  ]
}

// -------- 출력 — 후속 세션 · 문서가 참조 ------------------------------------------

output redisName string = redis.outputs.name
output redisHostName string = redis.outputs.hostName
output redisPort int = redisDatabase.outputs.port
