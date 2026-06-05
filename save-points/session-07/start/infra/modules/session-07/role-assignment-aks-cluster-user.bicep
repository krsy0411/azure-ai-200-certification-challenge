@description('대상 AKS cluster name')
param clusterName string

@description('Cluster User Role 을 받을 principal (배포 사용자 objectId)')
param principalId string

@description('Principal type')
param principalType string = 'User'

// Azure Kubernetes Service Cluster User Role — disableLocalAccounts=true 클러스터에서
// kubectl 을 쓰려면 본인 Entra 사용자에 이 역할이 필요하다 (az aks get-credentials).
var clusterUserRoleId = '4abbcc35-e782-43d8-92c5-2d3f1bd2253f'

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: clusterName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aks
  name: guid(aks.id, principalId, clusterUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', clusterUserRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = roleAssignment.id