// Service Bus 'Azure Service Bus Data Receiver' 역할 부여
//
// peek-lock 수신 + complete/abandon/dead-letter 권한.
// Function App 의 Service Bus trigger 가 이 역할로 작동.

@description('역할 부여 대상 Service Bus namespace 이름')
param namespaceName string

@description('역할을 받을 principal (UAMI 등) 의 objectId')
param principalId string

@description('principalType — UAMI 는 ServicePrincipal')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

// Azure Service Bus Data Receiver (built-in)
var roleDefinitionId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'

resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: namespaceName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(namespace.id, principalId, roleDefinitionId)
  scope: namespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = assignment.id
