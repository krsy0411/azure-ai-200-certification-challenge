@description('Cosmos DB account name. SQL data plane role assignment is scoped to this account.')
param cosmosAccountName string

@description('Principal (UAMI principalId 또는 user objectId)')
param principalId string

// Built-in role: Cosmos DB Built-in Data Contributor (SQL data plane RBAC)
// 주의: 일반 Azure RBAC 가 아닌 Cosmos 전용 SQL role assignment 사용
// https://learn.microsoft.com/azure/cosmos-db/nosql/security/how-to-grant-data-plane-role-based-access
var cosmosBuiltInDataContributorId = '00000000-0000-0000-0000-000000000002'

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosAccountName
}

resource sqlRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-12-01-preview' = {
  parent: cosmos
  name: guid(cosmos.id, principalId, cosmosBuiltInDataContributorId)
  properties: {
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/${cosmosBuiltInDataContributorId}'
    principalId: principalId
    scope: cosmos.id
  }
}

output id string = sqlRoleAssignment.id
