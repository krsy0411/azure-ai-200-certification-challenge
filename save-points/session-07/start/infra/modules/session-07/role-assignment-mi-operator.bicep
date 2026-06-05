@description('역할 scope 가 될 UAMI 이름 (AKS 클러스터 identity 자신)')
param targetUamiName string

@description('Managed Identity Operator 를 받을 principal (control plane UAMI principalId)')
param principalId string

// Managed Identity Operator — control plane UAMI 가 kubelet identity 를 노드에 할당하려면
// 그 identity 에 대해 이 역할이 필요하다. cp == kubelet 이 같은 UAMI 면 자기 자신에 부여.
var miOperatorRoleId = 'f1a07417-d97a-45cb-824c-7a7467783830'

resource targetUami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: targetUamiName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: targetUami
  name: guid(targetUami.id, principalId, miOperatorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', miOperatorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output id string = roleAssignment.id