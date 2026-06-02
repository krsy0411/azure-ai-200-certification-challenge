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
// 본 세션에서 할 일:
//   아래 6개 모듈 호출 블록과 출력 블록을 직접 채운다. 모듈 본체는
//   ../../modules/session-02/ 에 이미 완성되어 있다 (수정하지 않는다).
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

// -------- 1) PostgreSQL Flexible Server 모듈 호출하기 ---------------------------
// 힌트: ../../modules/session-02/postgres-flexible-server.bicep 를 호출합니다.
// name=pgName, location, version=postgresVersion, skuName='Standard_B1ms',
// skuTier='Burstable', storageSizeGB=32, tags=commonTags.

// -------- 2) Entra ID 관리자 (배포 사용자) 모듈 호출하기 ------------------------
// 힌트: passwordAuth 가 꺼진 서버는 Entra 관리자가 최소 1명 필요합니다.
// postgres-aad-admin.bicep 를 if (!empty(userObjectId)) 조건부로 호출.
// serverName=postgres.outputs.name, principalObjectId=userObjectId,
// principalName=userPrincipalName, principalType='User'.

// -------- 3) Entra ID 관리자 (User Assigned Managed Identity) 모듈 호출하기 -----
// 힌트: ca-api(STORE_BACKEND=pg) 가 UAMI 토큰으로 접속하도록 UAMI 도 관리자로.
// administrators 동시 생성은 충돌하므로 dependsOn 에 2)의 사용자 관리자를 명시.
// principalObjectId=uami.properties.principalId, principalName=uamiName,
// principalType='ServicePrincipal'.

// -------- 4) 서버 파라미터 azure.extensions=VECTOR 모듈 호출하기 ----------------
// 힌트: postgres-server-config.bicep 호출. configName='azure.extensions',
// value='VECTOR'. dependsOn 에 3)을 명시해 직렬화.

// -------- 5) firewall rule (본인 PC IP) 모듈 호출하기 --------------------------
// 힌트: postgres-firewall-rule.bicep 호출. name='dev-client-ip',
// startIpAddress=devClientIpAddress. dependsOn 에 4)를 명시.

// -------- 6) 데이터베이스 appdb 모듈 호출하기 ----------------------------------
// 힌트: postgres-database.bicep 호출. name=databaseName. dependsOn 에 5)를 명시.

// -------- 출력 — 후속 세션 · 문서가 참조 ------------------------------------------
// 힌트: postgresName, postgresFqdn, databaseName 을 output 으로 내보냅니다.
