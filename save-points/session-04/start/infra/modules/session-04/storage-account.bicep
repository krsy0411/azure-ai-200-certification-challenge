@description('Storage account name (globally unique, 3-24 lowercase + digits)')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region')
param location string

@description('업로드 문서 컨테이너 이름')
param documentsContainerName string = 'documents'

@description('Function App 배포 패키지 컨테이너 이름 (Flex Consumption deployment storage)')
param deploymentContainerName string = 'deployments'

@description('Tags')
param tags object = {}

// allowSharedKeyAccess=false — 키 인증을 끄고 Entra ID + RBAC 만 허용.
// Function 호스트·Blob 다운로드 모두 Managed Identity 로 접근한다.
resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storage
  name: 'default'
}

resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: documentsContainerName
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: deploymentContainerName
}

output id string = storage.id
output name string = storage.name
output blobEndpoint string = storage.properties.primaryEndpoints.blob
output documentsContainerName string = documentsContainerName
output deploymentContainerName string = deploymentContainerName