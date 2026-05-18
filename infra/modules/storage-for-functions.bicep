// Storage account — Function App AzureWebJobsStorage + deployment blob container
//
// 학습 경로 모듈 3 단원 5·6 매핑 (Function App 동작 의존성):
// - Flex Consumption 의 deployment.storage 가 blob container 를 사용
// - AzureWebJobsStorage 는 함수 실행 메타데이터 보관 (blob/queue/table)
// - allowSharedKeyAccess=false → AAD-only (Phase 4·5·6 일관성)
// - allowBlobPublicAccess=false → 데이터 노출 차단

@description('Storage account 이름 (영숫자 3-24자, 소문자)')
@minLength(3)
@maxLength(24)
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('Function App deployment ZIP 을 받을 blob container 이름')
param deploymentContainerName string = 'app-package'

resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storage
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: deploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

output id string = storage.id
output name string = storage.name
output blobEndpoint string = storage.properties.primaryEndpoints.blob
output queueEndpoint string = storage.properties.primaryEndpoints.queue
output tableEndpoint string = storage.properties.primaryEndpoints.table
output deploymentContainerName string = deploymentContainer.name
output deploymentStorageValue string = '${storage.properties.primaryEndpoints.blob}${deploymentContainer.name}'
