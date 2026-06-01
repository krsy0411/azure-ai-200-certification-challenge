@description('AOAI account name. Role assignment is scoped to this account.')
param aoaiAccountName string

@description('Principal (UAMI principalId or user objectId) that will get the role')
param principalId string

@description('Principal type')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

// Built-in role: Cognitive Services OpenAI User
// https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning#cognitive-services-openai-user
var cognitiveServicesOpenAIUserId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aoaiAccountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aoai
  // Deterministic GUID so re-deploys are idempotent.
  name: guid(aoai.id, principalId, cognitiveServicesOpenAIUserId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = roleAssignment.id
