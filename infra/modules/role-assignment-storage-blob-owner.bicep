// Storage 'Storage Blob Data Owner' 역할 부여 (storage account scope)
//
// Function App Flex Consumption 의 deployment.storage 가 UAMI 로 blob container 접근.
// 또한 AzureWebJobsStorage__credential=managedidentity 로 blob/queue/table 모두 사용.
// 'Owner' 등급 — read/write/delete + ACL. Flex 동작 + 함수 host 메타데이터에 필요.

@description('역할 부여 대상 Storage account 이름')
param storageAccountName string

@description('역할을 받을 principal (UAMI 등) 의 objectId')
param principalId string

@description('principalType — UAMI 는 ServicePrincipal')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

// Storage Blob Data Owner (built-in)
var roleDefinitionId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'

resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, principalId, roleDefinitionId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = assignment.id
