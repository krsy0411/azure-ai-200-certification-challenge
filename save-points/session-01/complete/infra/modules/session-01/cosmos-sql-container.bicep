@description('Parent Cosmos DB account name')
param accountName string

@description('Parent database name')
param databaseName string

@description('Container name')
param name string

@description('Partition key path (예: /doc_id)')
param partitionKeyPath string = '/doc_id'

@description('Vector embedding 차원 — text-embedding-3-large 는 3072')
param vectorDimensions int = 3072

@description('Vector path — embedding 필드 경로')
param vectorPath string = '/embedding'

@description('Vector data type')
@allowed([
  'float32'
  'float16'
  'int8'
  'uint8'
])
param vectorDataType string = 'float32'

@description('Vector distance function')
@allowed([
  'cosine'
  'dotproduct'
  'euclidean'
])
param vectorDistanceFunction string = 'cosine'

@description('Vector index type')
@allowed([
  'flat'
  'quantizedFlat'
  'diskANN'
])
param vectorIndexType string = 'quantizedFlat'

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: accountName

  resource database 'sqlDatabases@2024-12-01-preview' existing = {
    name: databaseName
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-12-01-preview' = {
  parent: cosmos::database
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
      // Vector policy — 컨테이너 생성 시점에만 설정 가능
      // (나중에 추가하려면 drop & recreate 필요 — docs/pitfalls/common.md 참고)
      vectorEmbeddingPolicy: {
        vectorEmbeddings: [
          {
            path: vectorPath
            dataType: vectorDataType
            distanceFunction: vectorDistanceFunction
            dimensions: vectorDimensions
          }
        ]
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '${vectorPath}/?'
          }
          {
            path: '/_etag/?'
          }
        ]
        vectorIndexes: [
          {
            path: vectorPath
            type: vectorIndexType
          }
        ]
      }
    }
  }
}

output id string = container.id
output name string = container.name
