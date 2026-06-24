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
// 본 세션에서 할 일:
//   아래 4개 모듈 호출 블록과 출력 블록을 직접 채운다. 모듈 본체는
//   ../../modules/session-03/ 에 이미 완성되어 있다 (수정하지 않는다).
//
// 주의: access policy assignment 동시 생성은 클러스터 Updating 충돌을 부를 수 있어
//       dependsOn 으로 직렬화한다.
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

// -------- 1) Azure Managed Redis 클러스터 모듈 호출하기 -------------------------
// 힌트: ../../modules/session-03/redis-enterprise.bicep 를 호출합니다.
// name=redisName, location, skuName='Balanced_B0', tags=commonTags.

// -------- 2) 데이터베이스 default 모듈 호출하기 --------------------------------
// 힌트: redis-enterprise-database.bicep 를 호출합니다. clusterName=redis.outputs.name.
// (RediSearch · NoEviction · Entra 전용 은 모듈 안에 기본값으로 들어 있음)

// -------- 3) access policy assignment (UAMI) 모듈 호출하기 ---------------------
// 힌트: redis-access-policy-assignment.bicep 를 호출. clusterName=redis.outputs.name,
// principalObjectId=uami.properties.principalId. dependsOn 에 2)의 데이터베이스 명시.

// -------- 4) access policy assignment (배포 사용자, 선택) 모듈 호출하기 --------
// 힌트: if (!empty(userObjectId)) 조건부 호출. principalObjectId=userObjectId.
// 동시 생성 충돌 회피 위해 dependsOn 에 3)을 명시해 직렬화.

// -------- 출력 — 후속 세션 · 문서가 참조 ------------------------------------------
// 힌트: redisName, redisHostName(redis.outputs.hostName),
//      redisPort(redisDatabase.outputs.port) 를 output 으로 내보냅니다.
