// Azure Functions Flex Consumption Function App
//
// 학습 경로 모듈 3 단원 4·6 매핑:
// - kind='functionapp,linux' + properties.functionAppConfig (Flex 전용)
// - UAMI 부여 (공용 UAMI 단일 — Phase 2 부터 일관)
// - deployment.storage.authentication = UserAssignedIdentity (Storage UAMI 접근)
// - AzureWebJobsStorage__credential = managedidentity (AAD-only)
//
// Flex 의 deployment.storage 는 ZIP 패키지 받을 blob container.
// 실제 코드 ZIP 배포는 `func azure functionapp publish` 또는 az functionapp deployment 로.

@description('Function App 이름')
@minLength(2)
@maxLength(60)
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('상위 Flex Consumption plan 의 resource ID')
param serverFarmId string

@description('UAMI resource ID (공용 ACA UAMI)')
param userAssignedIdentityId string

@description('UAMI clientId — Function 코드에서 AZURE_CLIENT_ID 로 사용')
param userAssignedIdentityClientId string

@description('Storage deployment blob container 의 fully qualified URL (blob endpoint + container name)')
param deploymentStorageValue string

@description('Storage blob endpoint (AzureWebJobsStorage__blobServiceUri)')
param storageBlobEndpoint string

@description('Storage queue endpoint')
param storageQueueEndpoint string

@description('Storage table endpoint')
param storageTableEndpoint string

@description('runtime — python 3.12 (학습 경로 모듈 3 단원 5 기준)')
param runtimeVersion string = '3.12'

@description('인스턴스 메모리 MB — 학습 경로 권장 2048')
@allowed([
  512
  2048
  4096
])
param instanceMemoryMB int = 2048

@description('최대 인스턴스 수 — Flex max 1000')
@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 100

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    serverFarmId: serverFarmId
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: deploymentStorageValue
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: userAssignedIdentityId
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: {
        name: 'python'
        version: runtimeVersion
      }
    }
    siteConfig: {
      appSettings: [
        // AzureWebJobsStorage — UAMI 로 접근 (Phase 8 까지 임시 패턴)
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: userAssignedIdentityClientId
        }
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: storageBlobEndpoint
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: storageQueueEndpoint
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: storageTableEndpoint
        }
        // 함수 코드에서 사용할 UAMI clientId
        {
          name: 'AZURE_CLIENT_ID'
          value: userAssignedIdentityClientId
        }
      ]
    }
  }
}

// appSettings 가 추가로 들어오면 별도 resource 로 merge
// (Bicep 의 siteConfig.appSettings 와 추가 settings 를 함께 다루기 위한 패턴 — 단순화: 모든 settings 를 한 곳에서 관리)
// 호출 측에서 appSettings 가 비어있지 않으면 siteConfig 갱신 필요. 본 모듈은 핵심 settings 만 박고
// 나머지는 main.bicep 에서 별도 resource (functionapp/config/appsettings) 로 patch 하도록 단순화.

output id string = functionApp.id
output name string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
// 주의: identity.type='UserAssigned' 인 경우 identity.principalId 는 존재하지 않음
// (SystemAssigned 일 때만 노출). 함정 1. 공용 UAMI 의 principalId 는 uami.properties.principalId
// (main.bicep 에서 직접 reference) 로 접근하므로 별도 output 불필요.
