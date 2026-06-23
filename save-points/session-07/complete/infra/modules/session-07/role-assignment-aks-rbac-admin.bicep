@description('대상 AKS cluster name')
param clusterName string

@description('RBAC Cluster Admin 을 받을 principal (배포 사용자 objectId)')
param principalId string

@description('Principal type')
param principalType string = 'User'

// Azure Kubernetes Service RBAC Cluster Admin — 클러스터가 Azure RBAC for Kubernetes
// (enableAzureRBAC=true) 이면 "Cluster User Role"(kubeconfig 다운로드용)만으로는
// kubectl get/apply 가 Forbidden 이다. 데이터플레인 조작에는 이 RBAC 역할이 별도로 필요.
var rbacClusterAdminRoleId = 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: clusterName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aks
  name: guid(aks.id, principalId, rbacClusterAdminRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      rbacClusterAdminRoleId
    )
    principalId: principalId
    principalType: principalType
  }
}

output id string = roleAssignment.id
