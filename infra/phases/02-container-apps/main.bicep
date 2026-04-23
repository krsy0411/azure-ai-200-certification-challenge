// Phase 2 — Azure Container Apps 배포
//
// 생성 리소스 (모두 rg-ai200challenge-<env> 안):
// - Log Analytics Workspace (law-ai200challenge-<env>)
// - User-Assigned Managed Identity (id-ai200challenge-aca-<env>)
//     · Phase 1 의 ACR 에 대한 AcrPull 역할 할당
// - Container Apps Environment (cae-ai200challenge-<env>)
// - Container App `ca-ai200challenge-api-<env>` (internal ingress, 8000)
// - Container App `ca-ai200challenge-web-<env>` (external ingress, 3000)
//
// resourceGroup 스코프인 이유: Phase 1 에서 이미 RG 를 만들었으므로 여기서는
// 그 안에 모듈들을 조립만 한다. ACR 은 acrName 파라미터로 받아 existing 참조.

targetScope = 'resourceGroup'

@description('배포 리전')
param location string = 'koreacentral'

@description('환경 라벨 (dev | prod)')
param environment string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200challenge'

@description('Phase 1 에서 만든 ACR 의 이름 (acrLoginServer 아님)')
param acrName string

@description('ACA 에 배포할 이미지 태그 — Phase 1 과 같은 이미지 재사용')
param imageTag string = '0.1.0'

@description('Log Analytics 로그 보존일')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

var lawName = 'law-${projectId}-${environment}'
var uamiName = 'id-${projectId}-aca-${environment}'
var caeName = 'cae-${projectId}-${environment}'
var apiAppName = 'ca-${projectId}-api-${environment}'
var webAppName = 'ca-${projectId}-web-${environment}'

var commonTags = {
  project: projectId
  env: environment
  phase: '2'
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// 0) Phase 1 의 ACR 을 existing 으로 참조
//    loginServer 를 outputs 로 노출해 Container App 에 주입
// ---------------------------------------------------------------------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}

// ---------------------------------------------------------------------------
// 1) Log Analytics Workspace — ACA Environment 의 로그 싱크
// ---------------------------------------------------------------------------
module law '../../modules/log-analytics.bicep' = {
  name: 'deploy-law'
  params: {
    name: lawName
    location: location
    tags: commonTags
    retentionInDays: logRetentionDays
  }
}

// ---------------------------------------------------------------------------
// 2) UAMI — ACA 가 ACR pull 할 때 쓸 identity
// ---------------------------------------------------------------------------
module uami '../../modules/user-assigned-identity.bicep' = {
  name: 'deploy-uami-aca'
  params: {
    name: uamiName
    location: location
    tags: commonTags
  }
}

// ---------------------------------------------------------------------------
// 3) UAMI → ACR AcrPull 역할 할당 (Phase 1 에서 만든 모듈 재사용)
//    ACA 생성 전에 완료되어야 pull 가능
// ---------------------------------------------------------------------------
module uamiAcrPull '../../modules/role-assignment-acrpull.bicep' = {
  name: 'ra-acrpull-uami'
  params: {
    acrName: acrName
    principalId: uami.outputs.principalId
  }
}

// ---------------------------------------------------------------------------
// 4) Container Apps Environment
// ---------------------------------------------------------------------------
module cae '../../modules/container-apps-env.bicep' = {
  name: 'deploy-cae'
  params: {
    name: caeName
    location: location
    tags: commonTags
    logAnalyticsCustomerId: law.outputs.customerId
    logAnalyticsSharedKey: law.outputs.sharedKey
  }
}

// ---------------------------------------------------------------------------
// 5) API Container App (internal ingress)
//    ingressExternal=false → Environment 안에서만 FQDN 으로 도달
// ---------------------------------------------------------------------------
module apiApp '../../modules/container-app.bicep' = {
  name: 'deploy-ca-api'
  params: {
    name: apiAppName
    location: location
    tags: union(commonTags, { component: 'api' })
    environmentId: cae.outputs.id
    acrLoginServer: acr.properties.loginServer
    userAssignedIdentityId: uami.outputs.id
    imageName: 'api'
    imageTag: imageTag
    targetPort: 8000
    ingressExternal: false
    healthProbePath: '/healthz'
    minReplicas: 1
    maxReplicas: 5
    httpConcurrency: 30
    envVars: {}
  }
  dependsOn: [ uamiAcrPull ]
}

// ---------------------------------------------------------------------------
// 6) Web Container App (external ingress)
//    API_BASE_URL 은 api 의 internal FQDN — 같은 ACA Environment 안이면
//    HTTPS 로 도달 가능
// ---------------------------------------------------------------------------
module webApp '../../modules/container-app.bicep' = {
  name: 'deploy-ca-web'
  params: {
    name: webAppName
    location: location
    tags: union(commonTags, { component: 'web' })
    environmentId: cae.outputs.id
    acrLoginServer: acr.properties.loginServer
    userAssignedIdentityId: uami.outputs.id
    imageName: 'web'
    imageTag: imageTag
    targetPort: 3000
    ingressExternal: true
    healthProbePath: '/'
    minReplicas: 1
    maxReplicas: 5
    httpConcurrency: 30
    envVars: {
      API_BASE_URL: 'https://${apiApp.outputs.fqdn}'
    }
  }
  dependsOn: [ uamiAcrPull ]
}

// ---------------------------------------------------------------------------
// Outputs — 다음 Phase / 운영 작업에서 쓸 식별자
// ---------------------------------------------------------------------------
output logAnalyticsName string = law.outputs.name
output userAssignedIdentityId string = uami.outputs.id
output userAssignedIdentityPrincipalId string = uami.outputs.principalId
output containerAppsEnvId string = cae.outputs.id
output containerAppsEnvDefaultDomain string = cae.outputs.defaultDomain
output apiInternalFqdn string = apiApp.outputs.fqdn
output apiInternalUrl string = 'https://${apiApp.outputs.fqdn}'
output webFqdn string = webApp.outputs.fqdn
output webUrl string = 'https://${webApp.outputs.fqdn}'
