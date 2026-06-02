@description('Parent Azure Managed Redis cluster name')
param clusterName string

@description('Entra ID principal object id (UAMI principalId 또는 user objectId). clientId 가 아님.')
param principalObjectId string

resource cluster 'Microsoft.Cache/redisEnterprise@2025-04-01' existing = {
  name: clusterName
}

resource database 'Microsoft.Cache/redisEnterprise/databases@2025-04-01' existing = {
  parent: cluster
  name: 'default'
}

// 기본 access policy('default')에 Entra principal 을 연결 — 이 principal 의 토큰으로
// 데이터 작업이 가능해진다. access key 인증이 꺼져 있으므로 이 부여가 필수.
resource assignment 'Microsoft.Cache/redisEnterprise/databases/accessPolicyAssignments@2025-04-01' = {
  parent: database
  name: guid(database.id, principalObjectId)
  properties: {
    accessPolicyName: 'default'
    user: {
      objectId: principalObjectId
    }
  }
}

output id string = assignment.id
