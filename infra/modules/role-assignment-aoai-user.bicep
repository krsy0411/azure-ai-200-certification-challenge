// AOAI 계정에 'Cognitive Services OpenAI User' 역할을 principal 에 부여.
// - 일반 ARM RBAC (Microsoft.Authorization/roleAssignments). Cosmos data-plane 과 달리 control-plane IAM 사용.
// - 'OpenAI User' 는 모델 호출 권한만 (배포 생성/삭제 권한 없음).

@description('역할을 부여할 대상 AOAI 계정 이름')
param accountName string

@description('역할을 받을 principal (UAMI 등) 의 objectId')
param principalId string

@description('principalType — UAMI 는 ServicePrincipal')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

// Cognitive Services OpenAI User (built-in)
var roleDefinitionId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: accountName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, principalId, roleDefinitionId)
  scope: account
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = assignment.id
