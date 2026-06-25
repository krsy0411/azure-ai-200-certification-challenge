// =============================================================================
// session-05 — App Configuration 피처 플래그
//
// 배포 명령:
//   OID=$(az ad signed-in-user show --query id -o tsv)
//   az deployment group create \
//     --resource-group rg-ai200ws-dev \
//     --template-file workshop/infra/sessions/05-app-config-flags/main.bicep \
//     --parameters workshop/infra/sessions/05-app-config-flags/main.bicepparam \
//     --parameters userObjectId=$OID
//
// 본 세션에서 할 일:
//   아래 그룹별 모듈 호출과 출력 블록을 직접 채운다. 모듈 본체는
//   ../../modules/session-05/ 에 이미 완성되어 있다 (수정하지 않는다).
//   키/값·Key Vault 참조·피처 플래그는 Bicep 이 아니라 배포 후
//   scripts/seed_app_config.py 로 시딩한다 (docs 2 단계 참고).
// =============================================================================

targetScope = 'resourceGroup'

@description('환경 라벨')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('Azure 자원 기본 리전')
param location string = resourceGroup().location

@description('배포 실행자의 Entra objectId. 포털/CLI 로 플래그 토글하려면 Data Owner 필요. CLI override.')
param userObjectId string = ''

// -------- 공용 태그 ------------------------------------------------------------

var commonTags = {
  project: projectId
  env: env
  workshop: 'azure-ai-200'
  managedBy: 'bicep'
  session: 'session-05'
}

// -------- 내장 역할 정의 GUID ---------------------------------------------------

var roleAppConfigDataReader = '516239f1-63e1-4d78-a4de-a74fb236a071'
var roleAppConfigDataOwner = '5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b'

// -------- 자원 이름 ------------------------------------------------------------

// App Configuration: 글로벌 unique (DNS, <name>.azconfig.io). uniqueString 접미사.
var acName = take('ac-${projectId}-${env}-${uniqueString(resourceGroup().id, projectId, env)}', 50)

// session-00 의 공용 UAMI (App Configuration 역할 부여 대상).
// 키/값·Key Vault 참조·피처 플래그는 Bicep 이 아니라 배포 후 scripts/seed_app_config.py
// 로 시딩하므로, 다른 세션 자원 (aoai·cosmos·pg·redis·kv) 의 existing 참조는 불필요하다.
var uamiName = 'id-${projectId}-${env}'

// -------- existing 참조 --------------------------------------------------------

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: uamiName
}

// -------- 1) App Configuration store 모듈 호출하기 ----------------------------
// 힌트: app-configuration.bicep (name=acName, location, skuName='free', tags).

// -------- 2) 역할 할당 모듈 호출하기 ----------------------------------------
// 힌트: role-assignment-appconfig.bicep — UAMI 에 roleAppConfigDataReader,
// (선택) if(!empty(userObjectId)) 로 사용자에 roleAppConfigDataOwner(principalType='User').
// 시딩 스크립트가 본인 자격으로 store 데이터플레인에 쓰므로 Data Owner 가 필요하다.

// -------- 출력 -----------------------------------------------------------------
// 힌트: appConfigName, appConfigEndpoint (appConfig.outputs.endpoint).
