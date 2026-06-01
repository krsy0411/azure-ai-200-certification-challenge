// =============================================================================
// session-00 — 사전 설정 & 구독 준비
//
// 한 번의 `az deployment sub create` 로 RG + 워크샵 전체의 기반 자원을 배포한다.
// 후속 세션 (session-01~07) 은 이 자원들을 existing 또는 출력값으로 참조한다.
//
// 배포 명령:
//   OID=$(az ad signed-in-user show --query id -o tsv)
//   az deployment sub create \
//     --location koreacentral \
//     --template-file workshop/infra/sessions/00-setup/main.bicep \
//     --parameters workshop/infra/sessions/00-setup/main.bicepparam \
//     --parameters userObjectId=$OID
//
// 본 세션에서 할 일:
//   아래 8개 모듈 호출 블록과 출력 블록을 직접 채운다. 호출할 모듈 본체는
//   ../../modules/session-00/ 에 이미 완성되어 있다 (수정하지 않는다).
// =============================================================================

targetScope = 'subscription'

// -------- 파라미터 -------------------------------------------------------------

@description('환경 라벨 (예: dev, prod)')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('기본 리전 (RG · LAW · AI · KV · UAMI)')
param location string = 'koreacentral'

@description('AOAI 리전. koreacentral 에 가용한 모델이 없으면 eastus/japaneast 로 분리.')
param aoaiLocation string = 'koreacentral'

@description('배포 실행자의 Entra objectId. CLI override 강제 — bicepparam 박지 말 것.')
param userObjectId string = ''

// -------- AOAI 모델 파라미터 ---------------------------------------------------

@description('chat 모델 deployment 이름 (코드에서 부르는 이름)')
param chatDeploymentName string = 'gpt-4o-mini'
param chatModelName string = 'gpt-4o-mini'
param chatModelVersion string = '2024-07-18'
@minValue(1)
param chatCapacityK int = 10

@description('embedding 모델 deployment 이름')
param embedDeploymentName string = 'text-embedding-3-large'
param embedModelName string = 'text-embedding-3-large'
param embedModelVersion string = '1'
@minValue(1)
param embedCapacityK int = 10

// -------- 공용 태그 ------------------------------------------------------------

var commonTags = {
  project: projectId
  env: env
  workshop: 'azure-ai-200'
  managedBy: 'bicep'
  session: 's00-setup'
}

// -------- 이름 ----------------------------------------------------------------

var rgName = 'rg-${projectId}-${env}'
var lawName = 'law-${projectId}-${env}'
var aiName = 'ai-${projectId}-${env}'
// Key Vault: 글로벌 unique. uniqueString 으로 충돌 회피.
var kvName = take('kv-${projectId}-${env}-${uniqueString(subscription().id, projectId, env)}', 24)
var uamiName = 'id-${projectId}-${env}'
// AOAI: 글로벌 unique. customSubDomainName 으로도 사용됨.
var aoaiName = take('aoai-${projectId}-${env}-${uniqueString(subscription().id, projectId, env)}', 60)

// -------- 1) Resource Group 모듈 호출하기 (subscription scope) -----------------
// 힌트: ../../modules/session-00/resource-group.bicep 모듈을 호출하고
// 파라미터로 name=rgName, location, tags=commonTags 를 전달합니다.
// 이 모듈만 RG 자체를 만들므로 scope 를 지정하지 않습니다 (subscription scope).

// -------- 2) Log Analytics + Application Insights 모듈 호출하기 ----------------
// 힌트: log-analytics.bicep 와 application-insights.bicep 를 차례로 호출합니다.
// 두 모듈 모두 scope: resourceGroup(rgName) 으로 지정하고, RG 모듈에 dependsOn 합니다.
// application-insights 는 workspaceResourceId 로 log-analytics 의 outputs.id 를 받습니다.

// -------- 3) Key Vault 모듈 호출하기 ------------------------------------------
// 힌트: key-vault.bicep 를 scope: resourceGroup(rgName) 으로 호출합니다.
// dev 라도 enablePurgeProtection=true 로 둡니다 (soft-delete 7일 충돌 회피).

// -------- 4) User Assigned Managed Identity 모듈 호출하기 ----------------------
// 힌트: user-assigned-identity.bicep 를 scope: resourceGroup(rgName) 으로 호출합니다.
// 후속 세션의 Container Apps · Functions 가 공용으로 사용합니다.

// -------- 5) Azure OpenAI account 모듈 호출하기 -------------------------------
// 힌트: aoai-account.bicep 를 호출합니다. location=aoaiLocation, disableLocalAuth=true.

// -------- 6) Azure OpenAI deployment 2개 모듈 호출하기 (순차 생성) --------------
// 힌트: aoai-deployment.bicep 를 두 번 호출합니다 (chat → embed).
// 같은 AOAI account 에 동시 PUT 하면 409 Conflict 가 나므로,
// embed 모듈의 dependsOn 에 chat 모듈을 명시해 순차 실행되게 합니다.

// -------- 7) 역할 할당 — User Assigned Managed Identity 에 Cognitive Services OpenAI User 부여 ---
// 힌트: role-assignment-aoai-user.bicep 를 호출합니다.
// principalId 는 UAMI 모듈의 outputs.principalId, principalType='ServicePrincipal'.
// dependsOn 에 deployment 2개를 명시합니다.

// -------- 8) (선택) 사용자 계정에도 Cognitive Services OpenAI User 부여 ----------
// 힌트: if (!empty(userObjectId)) 조건부로 role-assignment-aoai-user.bicep 를
// 다시 호출합니다. principalId=userObjectId, principalType='User'.
// 로컬 개발 시 az login 자격으로 AOAI 를 호출할 수 있게 합니다.

// -------- 출력 — 후속 세션이 참조 ------------------------------------------------
// 힌트: rgName, lawId, appInsightsConnectionString, keyVaultName, keyVaultUri,
//      uamiId, uamiPrincipalId, uamiClientId, aoaiName, aoaiEndpoint,
//      chatDeploymentName, embedDeploymentName 를 output 으로 내보냅니다.
