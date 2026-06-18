@description('Azure Container Registry name. Role assignment is scoped to this ACR.')
param acrName string

@description('Principal (UAMI principalId 또는 user objectId)')
param principalId string

@description('Principal type')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

// Built-in role: AcrPull
// https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/containers#acrpull
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, principalId, acrPullRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = roleAssignment.id
