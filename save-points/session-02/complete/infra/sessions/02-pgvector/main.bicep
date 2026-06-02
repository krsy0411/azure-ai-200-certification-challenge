// =============================================================================
// session-02 — PostgreSQL pgvector 비교
//
// 배포 명령:
//   OID=$(az ad signed-in-user show --query id -o tsv)
//   UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)
//   MY_IP=$(curl -s ifconfig.me)
//   az deployment group create \
//     --resource-group rg-ai200ws-dev \
//     --template-file workshop/infra/sessions/02-pgvector/main.bicep \
//     --parameters workshop/infra/sessions/02-pgvector/main.bicepparam \
//     --parameters userObjectId=$OID userPrincipalName=$UPN devClientIpAddress=$MY_IP
//
// 의존성:
//   - session-00 의 User Assigned Managed Identity 를 existing 으로 참조한다.
//
// 본 세션에서 신규 생성:
//   - PostgreSQL Flexible Server (Burstable B1ms, Entra ID 전용 인증)
//   - 데이터베이스 appdb
//   - 서버 파라미터 azure.extensions = VECTOR (pgvector 사전 허용)
//   - 본인 PC IP firewall rule
//   - Entra ID 관리자 2명 (배포 사용자 + UAMI)
//
// 주의: PostgreSQL Flexible Server 는 서버 상태를 바꾸는 자식 자원
//       (administrators · configurations · firewallRules · databases) 을 동시에
//       생성하면 409 Conflict (server busy) 가 발생한다. dependsOn 으로 직렬화한다.
// =============================================================================

targetScope = 'resourceGroup'

// -------- 파라미터 -------------------------------------------------------------

@description('환경 라벨 (예: dev, prod)')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('Azure 자원 기본 리전')
param location string = resourceGroup().location

@description('배포 실행자의 Entra objectId. PostgreSQL Entra 관리자로 부여. CLI override 강제.')
param userObjectId string = ''

@description('배포 실행자의 UPN (예: user@contoso.com). PostgreSQL Entra 관리자 principalName. CLI override 강제.')
param userPrincipalName string = ''

@description('본인 PC 공인 IP. PostgreSQL firewall 허용. CLI override 강제 — bicepparam 박지 말 것.')
param devClientIpAddress string = '0.0.0.0'

// -------- PostgreSQL 파라미터 ---------------------------------------------------

@description('PostgreSQL 데이터베이스 이름')
param databaseName string = 'appdb'

@description('PostgreSQL major version')
param postgresVersion string = '16'

// -------- 공용 태그 ------------------------------------------------------------

var commonTags = {
  project: projectId
  env: env
  workshop: 'azure-ai-200'
  managedBy: 'bicep'
  session: 'session-02'
}

// -------- 자원 이름 ------------------------------------------------------------

// PostgreSQL Flexible Server: 글로벌 unique (DNS). uniqueString 접미사로 충돌 회피.
var pgName = take('pg-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 63)

// session-00 자원 이름 (session-00 의 main.bicep 과 동일 규칙)
var uamiName = 'id-${projectId}-${env}'

// -------- session-00 자원 existing 참조 -----------------------------------------

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: uamiName
}

// -------- 1) PostgreSQL Flexible Server -----------------------------------------

module postgres '../../modules/session-02/postgres-flexible-server.bicep' = {
  name: 'postgres'
  params: {
    name: pgName
    location: location
    version: postgresVersion
    skuName: 'Standard_B1ms'
    skuTier: 'Burstable'
    storageSizeGB: 32
    tags: commonTags
  }
}

// -------- 2) Entra ID 관리자 — 배포 사용자 --------------------------------------
//             passwordAuth 가 꺼진 서버는 최소 한 명의 Entra 관리자가 필요하다.

module aadAdminUser '../../modules/session-02/postgres-aad-admin.bicep' = if (!empty(userObjectId)) {
  name: 'aadAdminUser'
  params: {
    serverName: postgres.outputs.name
    principalObjectId: userObjectId
    principalName: userPrincipalName
    principalType: 'User'
  }
}

// -------- 3) Entra ID 관리자 — UAMI ---------------------------------------------
//             ca-api (STORE_BACKEND=pg) 가 UAMI 토큰으로 접속할 수 있도록 부여.
//             administrators 동시 생성은 충돌하므로 사용자 관리자 뒤에 직렬화.

module aadAdminUami '../../modules/session-02/postgres-aad-admin.bicep' = {
  name: 'aadAdminUami'
  params: {
    serverName: postgres.outputs.name
    principalObjectId: uami.properties.principalId
    principalName: uamiName
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    aadAdminUser
  ]
}

// -------- 4) 서버 파라미터 — azure.extensions = VECTOR ---------------------------

module serverConfig '../../modules/session-02/postgres-server-config.bicep' = {
  name: 'serverConfig'
  params: {
    serverName: postgres.outputs.name
    configName: 'azure.extensions'
    value: 'VECTOR'
  }
  dependsOn: [
    aadAdminUami
  ]
}

// -------- 5) firewall rule — 본인 PC IP -----------------------------------------

module firewallRule '../../modules/session-02/postgres-firewall-rule.bicep' = {
  name: 'firewallRule'
  params: {
    serverName: postgres.outputs.name
    name: 'dev-client-ip'
    startIpAddress: devClientIpAddress
  }
  dependsOn: [
    serverConfig
  ]
}

// -------- 6) 데이터베이스 appdb --------------------------------------------------

module database '../../modules/session-02/postgres-database.bicep' = {
  name: 'database'
  params: {
    serverName: postgres.outputs.name
    name: databaseName
  }
  dependsOn: [
    firewallRule
  ]
}

// -------- 출력 — 후속 세션 · 문서가 참조 ------------------------------------------

output postgresName string = postgres.outputs.name
output postgresFqdn string = postgres.outputs.fqdn
output databaseName string = databaseName
