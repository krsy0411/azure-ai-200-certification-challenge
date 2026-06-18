@description('Parent Cosmos DB account name')
param accountName string

@description('Database name')
param name string

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: accountName
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-12-01-preview' = {
  parent: cosmos
  name: name
  properties: {
    resource: {
      id: name
    }
  }
}

output id string = database.id
output name string = database.name
