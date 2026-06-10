@description('Cosmos DB account name (global unique, 3-44 chars, lowercase + hyphens)')
@minLength(3)
@maxLength(44)
param name string

@description('Azure region')
param location string

@description('Capacity mode')
@allowed([
  'Serverless'
  'Provisioned'
])
param capacityMode string = 'Serverless'

@description('Disable local (key) authentication. true = Entra ID 만')
param disableLocalAuth bool = true

@description('Tags')
param tags object = {}

// 2024-12-01-preview 부터 serverless 는 capability(EnableServerless) 가 아니라
// databaseAccount 의 capacityMode 속성으로 지정한다. 벡터 검색만 capability 로 유지.
var capabilities = [
  {
    name: 'EnableNoSQLVectorSearch'
  }
]

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capacityMode: capacityMode
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    capabilities: capabilities
    disableLocalAuth: disableLocalAuth
    publicNetworkAccess: 'Enabled'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
  }
}

output id string = cosmos.id
output name string = cosmos.name
output endpoint string = cosmos.properties.documentEndpoint
