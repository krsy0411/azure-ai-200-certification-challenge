// Managed Identity 에 ACR AcrPull 역할 할당.
// 스코프는 ACR 리소스. principalId 는 소비자 (웹앱·ACA·AKS 등) 의 시스템 할당 MI.

@description('역할을 부여할 대상 ACR 이름')
param acrName string

@description('역할을 받을 principal (웹앱 등) 의 objectId')
param principalId string

@description('principalType. 웹앱·MI 는 ServicePrincipal')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

// AcrPull role definition ID (built-in)
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}

// guid() 로 결정적 이름을 만들어 재배포 시 중복 생성 방지
resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, principalId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = assignment.id
