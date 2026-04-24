// Managed Identity Operator 역할 부여
// - 대상 UAMI 자체가 scope (대상 identity 의 resource ID)
// - principal 은 operator 역할을 받을 주체 (본 프로젝트는 AKS control plane UAMI)
// - AKS 에서 "custom kubelet identity" 를 쓸 때, control plane UAMI 가 kubelet
//   UAMI 를 제어할 권한이 필요하다. 같은 UAMI 를 두 역할에 공용하더라도 Azure 는
//   이 역할 할당을 명시적으로 요구한다 (self role assignment).

@description('역할을 받을 UAMI resource ID (이 identity 자체가 scope 가 된다)')
param targetIdentityId string

@description('target UAMI 의 이름 (existing 참조용)')
param targetIdentityName string

@description('역할을 받을 principal (operator) 의 objectId')
param principalId string

@description('principalType. UAMI 는 ServicePrincipal')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

var managedIdentityOperatorRoleId = 'f1a07417-d97a-45cb-824c-7a7467783830'

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' existing = {
  name: targetIdentityName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(targetIdentityId, principalId, managedIdentityOperatorRoleId)
  scope: identity
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperatorRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = assignment.id
