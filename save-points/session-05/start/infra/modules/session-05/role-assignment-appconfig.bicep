@description('Parent App Configuration store name')
param storeName string

@description('Built-in role definition GUID (App Configuration Data Reader / Data Owner)')
param roleDefinitionId string

@description('Principal object id (UAMI principalId 또는 user objectId)')
param principalId string

@description('Principal type')
param principalType string = 'ServicePrincipal'

resource store 'Microsoft.AppConfiguration/configurationStores@2024-05-01' existing = {
  name: storeName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: store
  name: guid(store.id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = roleAssignment.id
