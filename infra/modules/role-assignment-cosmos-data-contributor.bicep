// Cosmos DB for NoSQL — data-plane RBAC
// 일반 ARM Microsoft.Authorization/roleAssignments 가 아니라
// Cosmos 자체 sqlRoleAssignments (NoSQL data plane) 으로 부여한다.
//
// roleDefinitionId 00000000-0000-0000-0000-000000000002 = Cosmos DB Built-in Data Contributor
// (read + write — 컨트롤 플레인 권한 없음)

@description('Cosmos DB 계정 이름')
param accountName string

@description('역할을 받을 principal (UAMI 등) 의 objectId')
param principalId string

// Built-in Data Contributor
var roleDefinitionId = '00000000-0000-0000-0000-000000000002'

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-08-15' existing = {
  name: accountName
}

resource assignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-08-15' = {
  parent: account
  name: guid(account.id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: '${account.id}/sqlRoleDefinitions/${roleDefinitionId}'
    principalId: principalId
    scope: account.id
  }
}

output id string = assignment.id
