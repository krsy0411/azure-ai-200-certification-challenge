@description('Parent Cosmos DB account name (session-01 에서 생성)')
param accountName string

@description('Database name')
param databaseName string = 'appdb'

@description('Container name (예: leases, doc_stats)')
param name string

@description('Partition key path')
param partitionKeyPath string = '/id'

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: accountName
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-12-01-preview' existing = {
  parent: account
  name: databaseName
}

// change feed lease container 는 자동 생성에 의존하지 않고 Bicep 으로 사전 생성한다
// (control plane RBAC 부재 시 자동 생성이 silent 실패하는 함정 회피 — docs §주의).
resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-12-01-preview' = {
  parent: database
  name: name
  properties: {
    resource: {
      id: name
      partitionKey: {
        paths: [
          partitionKeyPath
        ]
        kind: 'Hash'
      }
    }
  }
}

output name string = container.name