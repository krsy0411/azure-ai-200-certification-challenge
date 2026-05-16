// Azure Managed Redis — database access policy assignment (AAD)
//
// accessKeysAuthentication = Disabled 인 상태에서 *데이터 평면* 에 접근하려면
// Entra principal 에 access policy 를 명시적으로 부여해야 한다. 학습 경로 본문은
// AAD vs key 비교를 강조하지 않지만, 본 레포는 Phase 4·5 일관성 (Entra-only) 으로
// 모든 데이터 자원에 동일 패턴을 적용한다 (CLAUDE.md §8).
//
// accessPolicyName 은 현재 'default' 만 지원 (RBAC role 의 Redis 측 표현).
// name (assignment 이름) 패턴: ^[A-Za-z0-9]{1,60}$ — 하이픈 불가.

@description('상위 redisEnterprise 클러스터 이름')
param clusterName string

@description('상위 database 이름')
param databaseName string = 'default'

@description('Access policy assignment 이름 (영숫자 1-60자, 하이픈 불가)')
@minLength(1)
@maxLength(60)
param assignmentName string

@description('Access policy 이름 — 현재 default 만 지원')
param accessPolicyName string = 'default'

@description('데이터 접근 권한을 부여할 principal 의 objectId (UAMI 면 principalId)')
param principalObjectId string

resource cluster 'Microsoft.Cache/redisEnterprise@2025-07-01' existing = {
  name: clusterName
}

resource database 'Microsoft.Cache/redisEnterprise/databases@2025-07-01' existing = {
  parent: cluster
  name: databaseName
}

resource assignment 'Microsoft.Cache/redisEnterprise/databases/accessPolicyAssignments@2025-07-01' = {
  parent: database
  name: assignmentName
  properties: {
    accessPolicyName: accessPolicyName
    user: {
      objectId: principalObjectId
    }
  }
}

output id string = assignment.id
output name string = assignment.name
