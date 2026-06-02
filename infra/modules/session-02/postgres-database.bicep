@description('Parent PostgreSQL Flexible Server name')
param serverName string

@description('Database name')
param name string = 'appdb'

@description('Character set')
param charset string = 'UTF8'

@description('Collation')
param collation string = 'en_US.utf8'

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: serverName
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: server
  name: name
  properties: {
    charset: charset
    collation: collation
  }
}

output name string = database.name
