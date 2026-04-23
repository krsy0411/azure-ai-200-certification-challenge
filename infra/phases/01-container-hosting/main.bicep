// Phase 1 — 컨테이너 호스팅 기초
//
// 생성 리소스:
// - 리소스 그룹 rg-ai200challenge-<env>
// - ACR acrai200challenge<env><acrSuffix>
// - App Service Plan asp-ai200challenge-<env> (Linux B1)
// - Web App (api) + 시스템 할당 MI + ACR AcrPull
// - Web App (web) + 시스템 할당 MI + ACR AcrPull
//
// subscription 스코프인 이유: 리소스 그룹을 이 템플릿 안에서 함께 생성해
// "Phase 1 = 한 번의 배포" 를 성립시키기 위함. Phase 2 이후는 RG 가 존재하므로
// resourceGroup 스코프로 진입.

targetScope = 'subscription'

@description('배포 리전')
param location string = 'koreacentral'

@description('환경 라벨 (dev | prod)')
param environment string = 'dev'

@description('프로젝트 식별자 (네이밍·태그에 공통 사용)')
param projectId string = 'ai200challenge'

@description('ACR 전역 유니크를 위한 2~4자 접미사')
@minLength(2)
@maxLength(4)
param acrSuffix string

@description('API / Web 컨테이너 이미지 태그')
param imageTag string = '0.1.0'

var rgName = 'rg-${projectId}-${environment}'
var acrName = 'acr${projectId}${environment}${acrSuffix}'
var planName = 'asp-${projectId}-${environment}'
var apiAppName = 'app-${projectId}-api-${environment}'
var webAppName = 'app-${projectId}-web-${environment}'

var commonTags = {
  project: projectId
  env: environment
  phase: '1'
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// 1) 리소스 그룹
// ---------------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: commonTags
}

// ---------------------------------------------------------------------------
// 2) ACR
// ---------------------------------------------------------------------------
module acr '../../modules/acr.bicep' = {
  name: 'deploy-acr'
  scope: rg
  params: {
    name: acrName
    location: location
    tags: union(commonTags, { tier: 'shared' })
    sku: 'Basic'
  }
}

// ---------------------------------------------------------------------------
// 3) App Service Plan
// ---------------------------------------------------------------------------
module plan '../../modules/app-service-plan.bicep' = {
  name: 'deploy-asp'
  scope: rg
  params: {
    name: planName
    location: location
    tags: commonTags
    sku: 'B1'
  }
}

// ---------------------------------------------------------------------------
// 4) API Web App (container) + MI
// ---------------------------------------------------------------------------
module apiApp '../../modules/app-service-container.bicep' = {
  name: 'deploy-app-api'
  scope: rg
  params: {
    name: apiAppName
    location: location
    tags: union(commonTags, { component: 'api' })
    planId: plan.outputs.id
    acrLoginServer: acr.outputs.loginServer
    imageName: 'api'
    imageTag: imageTag
    appSettings: {
      WEBSITES_PORT: '8000'
    }
  }
}

module apiAcrPull '../../modules/role-assignment-acrpull.bicep' = {
  name: 'ra-acrpull-api'
  scope: rg
  params: {
    acrName: acr.outputs.name
    principalId: apiApp.outputs.principalId
  }
}

// ---------------------------------------------------------------------------
// 5) Web (Next.js) Web App (container) + MI
// ---------------------------------------------------------------------------
module webApp '../../modules/app-service-container.bicep' = {
  name: 'deploy-app-web'
  scope: rg
  params: {
    name: webAppName
    location: location
    tags: union(commonTags, { component: 'web' })
    planId: plan.outputs.id
    acrLoginServer: acr.outputs.loginServer
    imageName: 'web'
    imageTag: imageTag
    appSettings: {
      WEBSITES_PORT: '3000'
      API_BASE_URL: 'https://${apiApp.outputs.defaultHostName}'
    }
  }
}

module webAcrPull '../../modules/role-assignment-acrpull.bicep' = {
  name: 'ra-acrpull-web'
  scope: rg
  params: {
    acrName: acr.outputs.name
    principalId: webApp.outputs.principalId
  }
}

// ---------------------------------------------------------------------------
// Outputs — 다음 Phase 가 재사용할 식별자
// ---------------------------------------------------------------------------
output resourceGroupName string = rg.name
output acrLoginServer string = acr.outputs.loginServer
output apiUrl string = 'https://${apiApp.outputs.defaultHostName}'
output webUrl string = 'https://${webApp.outputs.defaultHostName}'
