@description('Parent Service Bus namespace name')
param namespaceName string

@description('Built-in role definition GUID (예: Data Receiver / Data Sender)')
param roleDefinitionId string

@description('Principal object id (UAMI principalId 또는 system topic identity)')
param principalId string

@description('Principal type')
param principalType string = 'ServicePrincipal'

resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: namespaceName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: namespace
  name: guid(namespace.id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = roleAssignment.id