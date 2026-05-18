// Event Grid 'EventGrid Data Sender' 역할 부여 (topic scope)
//
// 학습 경로 모듈 2 매핑 — Entra 토큰으로 publish 권한.
// disableLocalAuth=true 토픽에서 publisher AAD 인증 필수.

@description('역할 부여 대상 Event Grid 토픽 이름')
param topicName string

@description('역할을 받을 principal (UAMI 등) 의 objectId')
param principalId string

@description('principalType — UAMI 는 ServicePrincipal')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

// EventGrid Data Sender (built-in)
var roleDefinitionId = 'd5a91429-5739-47e2-a06b-3470a27159e7'

resource topic 'Microsoft.EventGrid/topics@2025-02-15' existing = {
  name: topicName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(topic.id, principalId, roleDefinitionId)
  scope: topic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = assignment.id
