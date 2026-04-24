// AKS 클러스터 범위에 "Azure Kubernetes Service RBAC Cluster Admin" 역할을 부여.
// Azure RBAC on + disableLocalAccounts=true 상태에서 kubectl 명령을 실제로 수행하려면
// AAD principal 에게 이 역할이 필요하다 (kubelet 자격과는 별개).
//
// role id: b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b (built-in)

@description('대상 AKS 클러스터 이름')
param aksName string

@description('역할을 받을 principal (user/group/service principal) 의 objectId')
param principalId string

@description('principalId 타입')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

var clusterAdminRoleId = 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' existing = {
  name: aksName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, principalId, clusterAdminRoleId)
  scope: aks
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', clusterAdminRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = assignment.id
