// Phase 6 — Azure Managed Redis (시맨틱 캐시 + pub/sub + Streams) + chat.py RAG 화
//
// 학습 경로 'enhance-ai-solutions-azure-managed-redis' (3 모듈 × 7 단원) 커버.
// 결정 (사용자 승인: 2026-05-13, A 조합 — docs/learning-paths/06-managed-redis.md 참조):
//   ① 계층: MemoryOptimized_M10 (학습 경로 dev/test 권장, RediSearch 포함)
//   ② 인증: AAD-only — accessKeysAuthentication=Disabled, UAMI 에 default access policy 부여
//   ③ 인덱스: HNSW + FLOAT32 + DIM 3072 + COSINE + HASH (앱 측 FT.CREATE 로 부트스트랩)
//   ④ 메인 RAG retrieval: Phase 5 PG `chunks_hnsw` (existing 참조) + Redis L1 시맨틱 캐시
//   ⑤ pub/sub = 알림 fanout / Streams = 학습용 1개 큐 (앱 측)
//   ⑥ chat.py RAG 화 — apps/api/src/routers/chat.py (Phase 6 새 이미지)
//
// 생성 리소스 (rg-ai200challenge-<env>):
//   - redis-ai200challenge-<env><suffix>          (Redis Enterprise cluster, MemoryOptimized_M10)
//       └ default (database) — RediSearch, AAD-only, port 10000
//   - default/<assignmentName>                    (UAMI 에 default access policy 부여)
//
// 갱신 리소스:
//   - ca-ai200challenge-api-<env>                 (envVars 에 REDIS_HOST/PORT 추가, 이미지 0.6.0)
//
// existing 참조 (CLAUDE.md §7 의 "다음 Phase 진입 시 재배포" 패턴에 따라 Phase 4·5 를 먼저 재배포):
//   - ACR (Phase 1)
//   - UAMI / ACA Env (Phase 2)
//   - Cosmos / AOAI (Phase 4 재배포 후)
//   - PG (Phase 5 재배포 후)

targetScope = 'resourceGroup'

@description('배포 리전')
param location string = 'koreacentral'

@description('환경 라벨 (dev | prod)')
param environment string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200challenge'

@description('Redis 클러스터 이름 전역 유니크 접미사 (소문자/숫자 2~4자)')
@minLength(2)
@maxLength(4)
param redisSuffix string

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

@description('ACR 전역 유니크 접미사 (Phase 1 과 동일)')
@minLength(2)
@maxLength(4)
param acrSuffix string

@description('ACA 에 배포할 이미지 태그 (Phase 6 새 이미지 — redis 의존성 + chat.py RAG)')
param imageTag string

@description('PostgreSQL 데이터베이스 이름')
param pgDatabaseName string = 'kb'

@description('Redis SKU')
@allowed([
  'MemoryOptimized_M10'
  'MemoryOptimized_M20'
  'Balanced_B0'
  'Balanced_B1'
])
param redisSkuName string = 'MemoryOptimized_M10'

// ---- 이름 규칙 ----------------------------------------------------------
// Redis 이름 패턴 ^(?=.{1,60}$)[A-Za-z0-9]+(-[A-Za-z0-9]+)*$ 는 하이픈 허용 → 표준 네이밍 그대로
var acrName = 'acr${projectId}${environment}${acrSuffix}'
var uamiName = 'id-${projectId}-aca-${environment}'
var caeName = 'cae-${projectId}-${environment}'
var apiAppName = 'ca-${projectId}-api-${environment}'
var cosmosName = 'cosmos-${projectId}-${environment}${cosmosSuffix}'
var aoaiName = 'aoai-${projectId}-${environment}${aoaiSuffix}'
var pgName = 'pg-${projectId}-${environment}${pgSuffix}'
var redisName = 'redis-${projectId}-${environment}${redisSuffix}'

// Access policy assignment 이름은 ^[A-Za-z0-9]{1,60}$ — 하이픈 불가
var redisUamiAssignmentName = 'uamiaca${environment}'

var commonTags = {
  project: projectId
  env: environment
  phase: '6'
  managedBy: 'bicep'
}

// ---- 0) Phase 1/2/4/5 existing 참조 ------------------------------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uamiName
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
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

// ---- 1) Redis Enterprise cluster ---------------------------------------
module redisCluster '../../modules/redis-enterprise.bicep' = {
  name: 'deploy-redis-cluster'
  params: {
    name: redisName
    location: location
    tags: commonTags
    skuName: redisSkuName
  }
}

// ---- 2) Redis database (default) — RediSearch + AAD-only ---------------
// RediSearch 활성화 → evictionPolicy='NoEviction' 강제 (Azure Managed Redis 제약).
// TTL 캐시 정리는 evictionPolicy 가 아니라 키별 EXPIRE 로. 함정 1 — 학습 경로 본문 밖.
module redisDb '../../modules/redis-enterprise-database.bicep' = {
  name: 'deploy-redis-database'
  params: {
    clusterName: redisCluster.outputs.name
    databaseName: 'default'
    evictionPolicy: 'NoEviction'
    clusteringPolicy: 'EnterpriseCluster'
    port: 10000
  }
}

// ---- 3) UAMI 에 default access policy 부여 (AAD-only 데이터 접근) -------
module redisUamiAccess '../../modules/redis-access-policy-assignment.bicep' = {
  name: 'deploy-redis-access-uami'
  params: {
    clusterName: redisCluster.outputs.name
    databaseName: redisDb.outputs.name
    assignmentName: redisUamiAssignmentName
    accessPolicyName: 'default'
    principalObjectId: uami.properties.principalId
  }
}

// ---- 4) ACA api Container App 갱신 -------------------------------------
// Phase 4·5 envVars 그대로 두고 REDIS_HOST / REDIS_PORT 만 추가.
// imageTag 는 bicepparam 에서 Phase 6 새 이미지 (0.6.0) — semantic cache + chat.py RAG 포함.
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
      // Phase 4 — Cosmos
      COSMOS_ENDPOINT: cosmos.properties.documentEndpoint
      COSMOS_DB: pgDatabaseName
      COSMOS_CONTAINER_DOCUMENTS: 'documents'
      COSMOS_CONTAINER_CHUNKS: 'chunks'
      // Phase 4 — AOAI
      AOAI_ENDPOINT: aoai.properties.endpoint
      AOAI_DEPLOYMENT_CHAT: 'gpt-4o-mini'
      AOAI_DEPLOYMENT_EMBED: 'text-embedding-3-large'
      // Phase 5 — PostgreSQL
      PG_HOST: pgServer.properties.fullyQualifiedDomainName
      PG_PORT: '5432'
      PG_DATABASE: pgDatabaseName
      PG_USER: uamiName
      // Phase 6 — Redis Enterprise (Azure Managed Redis)
      // Azure Managed Redis 의 AAD 인증 username 은 'default' 가 아니라 principal objectId.
      // 학습 경로 본문에는 없고 /azure/redis/entra-for-authentication 에 명시. 함정 3.
      REDIS_HOST: redisCluster.outputs.hostName
      REDIS_PORT: '${redisDb.outputs.port}'
      REDIS_TLS: 'true'
      REDIS_USERNAME: uami.properties.principalId
      REDIS_SEMANTIC_INDEX: 'idx:semantic'
      REDIS_SEMANTIC_PREFIX: 'sc:'
      REDIS_SEMANTIC_TTL_SECONDS: '86400'
      REDIS_SEMANTIC_THRESHOLD: '0.92'
      // Identity
      AZURE_CLIENT_ID: uami.properties.clientId
    }
  }
  dependsOn: [
    redisUamiAccess
  ]
}

// ---- Outputs -----------------------------------------------------------
output redisClusterName string = redisCluster.outputs.name
output redisHostName string = redisCluster.outputs.hostName
output redisDatabasePort int = redisDb.outputs.port
output apiInternalFqdn string = apiApp.outputs.fqdn
