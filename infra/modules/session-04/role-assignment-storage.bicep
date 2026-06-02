@description('Parent Storage account name')
param storageAccountName string

@description('Built-in role definition GUID (예: Blob Data Owner / Blob Data Reader / Queue Data Contributor)')
param roleDefinitionId string

@description('Principal object id (UAMI principalId)')
param principalId string

@description('Principal type')
param principalType string = 'ServicePrincipal'

resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = roleAssignment.id