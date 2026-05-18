// Service Bus 'Azure Service Bus Data Sender' 역할 부여
//
// 학습 경로 모듈 1 인증 매핑 — AAD+UAMI 권장.
// disableLocalAuth=true 인 namespace 에서 message send 권한.
// Receiver / Owner 는 별도 모듈.

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

// Azure Service Bus Data Sender (built-in)
var roleDefinitionId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'

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
