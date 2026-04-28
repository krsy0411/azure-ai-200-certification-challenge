// Phase 5 — Azure Database for PostgreSQL Flexible Server + pgvector
//
// 학습 경로 'develop-ai-solutions-azure-database-postgresql' (3 모듈) 커버.
// 결정 (history.md / 사전 협의):
//   ① Phase 4 자원(cosmos / aoai) 은 existing 참조만 — 재배포 X. ACA api 의 envVars 에 PG 추가만 갱신.
//   ② AAD admin 은 UAMI 단일 등록. 사용자 본인은 검증 시 임시 부여 후 회수.
//   ③ 내장 PgBouncer 활성 (pgbouncer.enabled=true). 앱 측에서도 psycopg_pool 이중 풀링.
//   ④ chunks_hnsw / chunks_ivf 두 테이블에 같은 데이터 적재 (앱 부트스트랩 SQL 에서) — Bicep 영향 없음.
//
// 생성 리소스 (rg-ai200challenge-<env>):
//   - pg-ai200challenge-<env><suffix>           (Flexible Server, PG 16, B1ms, AAD-only)
//       └ kb (DB)
//   - administrators sub-resource               (UAMI → AAD admin)
//   - configurations sub-resource (배치)
//        ├ azure.extensions = VECTOR
//        ├ pgbouncer.enabled = true
//        ├ pgbouncer.pool_mode = transaction
//        └ pgbouncer.default_pool_size = 50
//   - firewall rules
//        ├ AllowAzureServices (0.0.0.0/0.0.0.0 의 특수 의미)
//        └ <devClient> (사용자 IP — 검증 시 psql 접속용)
//
// 갱신 리소스:
//   - ca-ai200challenge-api-<env>               (ACA api: cosmos+aoai+pg 모두 envVars 주입)
//
// existing 참조:
//   - ACR (Phase 1)
//   - UAMI / ACA Env (Phase 2)
//   - Cosmos / AOAI (Phase 4)

targetScope = 'resourceGroup'

@description('배포 리전')
param location string = 'koreacentral'

@description('환경 라벨 (dev | prod)')
param environment string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200challenge'

@description('PG 서버 이름 전역 유니크 접미사 (소문자/숫자 2~4자)')
@minLength(2)
@maxLength(4)
param pgSuffix string

@description('Cosmos 계정 전역 유니크 접미사 (Phase 4 와 동일해야 같은 계정 참조)')
@minLength(2)
@maxLength(4)
param cosmosSuffix string

@description('AOAI 계정 전역 유니크 접미사 (Phase 4 와 동일)')
@minLength(2)
@maxLength(4)
param aoaiSuffix string

@description('ACR 전역 유니크 접미사 (Phase 1 과 동일)')
@minLength(2)
@maxLength(4)
param acrSuffix string

@description('ACA 에 배포할 이미지 태그 (Phase 5 새 이미지 — psycopg 의존성 추가됨)')
param imageTag string

@description('PostgreSQL 데이터베이스 이름')
param pgDatabaseName string = 'kb'

@description('PostgreSQL 메이저 버전')
@allowed([
  '14'
  '15'
  '16'
  '17'
])
param postgresVersion string = '16'

@description('PG 스토리지 크기 (GiB)')
@minValue(32)
param pgStorageSizeGB int = 32

@description('검증용 사용자 IP — psql 접속을 위한 firewall allow 대상 (예: 1.2.3.4)')
param devClientIpAddress string

// ---- 이름 규칙 ----------------------------------------------------------
var acrName = 'acr${projectId}${environment}${acrSuffix}'
var uamiName = 'id-${projectId}-aca-${environment}'
var caeName = 'cae-${projectId}-${environment}'
var apiAppName = 'ca-${projectId}-api-${environment}'
var cosmosName = 'cosmos-${projectId}-${environment}${cosmosSuffix}'
var aoaiName = 'aoai-${projectId}-${environment}${aoaiSuffix}'
var pgName = 'pg-${projectId}-${environment}${pgSuffix}'

var commonTags = {
  project: projectId
  env: environment
  phase: '5'
  managedBy: 'bicep'
}

// ---- 0) Phase 1/2/4 existing 참조 --------------------------------------
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

// ---- 1) PostgreSQL Flexible Server (AAD-only) --------------------------
module pgServer '../../modules/postgres-flexible-server.bicep' = {
  name: 'deploy-pg-server'
  params: {
    name: pgName
    location: location
    tags: commonTags
    postgresVersion: postgresVersion
    skuName: 'Standard_B1ms'
    skuTier: 'Burstable'
    storageSizeGB: pgStorageSizeGB
    entraOnlyAuth: true
  }
}

// ---- 2) AAD admin = UAMI ----------------------------------------------
// AAD admin 이 등록되기 전까지는 server 가 사실상 사용 불가 — 다른 모든 sub-resource (DB / firewall / config) 를 이 모듈에 의존시켜
// admin 부재 상태에서 후속 작업이 시도되지 않도록 직렬화한다.
module pgAadAdmin '../../modules/postgres-aad-admin.bicep' = {
  name: 'deploy-pg-aad-admin'
  params: {
    serverName: pgServer.outputs.name
    principalObjectId: uami.properties.principalId
    principalName: uamiName
    principalType: 'ServicePrincipal'
  }
}

// ---- 3) Database (kb) -------------------------------------------------
module pgDb '../../modules/postgres-database.bicep' = {
  name: 'deploy-pg-database'
  params: {
    serverName: pgServer.outputs.name
    databaseName: pgDatabaseName
  }
  dependsOn: [
    pgAadAdmin
  ]
}

// ---- 4) Server parameters (vector extension + PgBouncer) --------------
module pgServerConfig '../../modules/postgres-server-config.bicep' = {
  name: 'deploy-pg-server-config'
  params: {
    serverName: pgServer.outputs.name
    parameters: {
      'azure.extensions': 'VECTOR'
      'pgbouncer.enabled': 'true'
      'pgbouncer.pool_mode': 'transaction'
      'pgbouncer.default_pool_size': '50'
    }
  }
  dependsOn: [
    pgAadAdmin
  ]
}

// ---- 5) Firewall rules ------------------------------------------------
// 5-1) Azure services allow — startIp=endIp=0.0.0.0 의 특수 의미.
//      ACA outbound IP 가 가변이라 Phase 9 (PE) 까지는 이 규칙으로 우회.
module fwAzureServices '../../modules/postgres-firewall-rule.bicep' = {
  name: 'deploy-pg-fw-azure-services'
  params: {
    serverName: pgServer.outputs.name
    ruleName: 'AllowAllAzureServicesAndResourcesWithinAzureIps'
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
  dependsOn: [
    pgAadAdmin
  ]
}

// 5-2) 사용자 IP allow — 검증 시 로컬 psql 접속.
module fwDevClient '../../modules/postgres-firewall-rule.bicep' = {
  name: 'deploy-pg-fw-dev-client'
  params: {
    serverName: pgServer.outputs.name
    ruleName: 'DevClient'
    startIpAddress: devClientIpAddress
    endIpAddress: devClientIpAddress
  }
  dependsOn: [
    pgAadAdmin
  ]
}

// ---- 6) ACA api Container App 갱신 ------------------------------------
// Phase 4 와 동일하게 같은 이름·같은 사양으로 다시 호출. envVars 에 cosmos + aoai + pg 모두 주입.
// imageTag 는 bicepparam 에서 Phase 5 새 이미지(0.5.x)로 받아 PgStore 가 포함된 이미지를 배포.
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
      // 기본은 PgBouncer 포트(6432). 비교 측정 시 5432 로 토글.
      PG_HOST: pgServer.outputs.fqdn
      PG_PORT: '6432'
      PG_DATABASE: pgDb.outputs.name
      PG_USER: uamiName
      // Identity
      AZURE_CLIENT_ID: uami.properties.clientId
    }
  }
  dependsOn: [
    pgServerConfig
    fwAzureServices
  ]
}

// ---- Outputs -----------------------------------------------------------
output pgServerName string = pgServer.outputs.name
output pgFqdn string = pgServer.outputs.fqdn
output pgDatabaseName string = pgDb.outputs.name
output pgAadAdminPrincipalName string = uamiName
output apiInternalFqdn string = apiApp.outputs.fqdn
