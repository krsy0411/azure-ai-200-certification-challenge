// Cosmos DB for NoSQL — SQL Container
// - 파티션 키는 단일 hashed path (워크스페이스 격리: /workspaceId)
// - vectorEmbeddingPaths 가 비어 있으면 vector policy/index 미설정 → 일반 컨테이너 (예: documents)
// - vectorEmbeddingPaths 가 있으면 컨테이너 단위 vectorEmbeddingPolicy + indexingPolicy.vectorIndexes 설정
//   · 벡터 경로는 indexingPolicy.excludedPaths 에 자동으로 '/path/*' 형태로 추가
//     (스칼라 인덱스 폭증 방지 — vector index 가 별도로 관리)
// - Serverless 계정이므로 throughput 미설정

@description('상위 Cosmos DB 계정 이름')
param accountName string

@description('상위 SQL DB 이름')
param databaseName string

@description('컨테이너 이름')
param containerName string

@description('공통 태그')
param tags object = {}

@description('파티션 키 경로')
param partitionKeyPath string = '/workspaceId'

@description('벡터 임베딩 경로 목록. 비어 있으면 vector 비활성 컨테이너')
param vectorEmbeddingPaths array = []

@description('벡터 차원 (text-embedding-3-large = 3072)')
param vectorDimensions int = 3072

@description('벡터 데이터 타입')
@allowed([
  'float16'
  'float32'
  'uint8'
  'int8'
])
param vectorDataType string = 'float32'

@description('벡터 거리 함수')
@allowed([
  'cosine'
  'euclidean'
  'dotproduct'
])
param vectorDistanceFunction string = 'cosine'

@description('벡터 인덱스 타입 (quantizedFlat: 균형, diskANN: 대용량, flat: 소량)')
@allowed([
  'flat'
  'quantizedFlat'
  'diskANN'
])
param vectorIndexType string = 'quantizedFlat'

var hasVector = !empty(vectorEmbeddingPaths)

// for 식은 union() 인자로 직접 못 넣으므로 변수로 분리 (BCP138 회피)
var vectorExcludedPaths = [for p in vectorEmbeddingPaths: {
  path: '${p}/*'
}]
var defaultExcludedPaths = [
  {
    path: '/_etag/?'
  }
]
var excludedPaths = union(defaultExcludedPaths, vectorExcludedPaths)

var vectorIndexes = [for p in vectorEmbeddingPaths: {
  path: p
  type: vectorIndexType
}]

var vectorEmbeddings = [for p in vectorEmbeddingPaths: {
  path: p
  dataType: vectorDataType
  dimensions: vectorDimensions
  distanceFunction: vectorDistanceFunction
}]

// 기본 indexingPolicy
var indexingPolicyBase = {
  indexingMode: 'consistent'
  automatic: true
  includedPaths: [
    {
      path: '/*'
    }
  ]
  excludedPaths: excludedPaths
}

// vector 컨테이너면 vectorIndexes 추가
var indexingPolicy = hasVector ? union(indexingPolicyBase, {
  vectorIndexes: vectorIndexes
}) : indexingPolicyBase

// resource.id + partitionKey + indexingPolicy
var resourceBase = {
  id: containerName
  partitionKey: {
    paths: [
      partitionKeyPath
    ]
    kind: 'Hash'
  }
  indexingPolicy: indexingPolicy
}

// vector 컨테이너면 vectorEmbeddingPolicy 추가, 아니면 omit
var resourceFinal = hasVector ? union(resourceBase, {
  vectorEmbeddingPolicy: {
    vectorEmbeddings: vectorEmbeddings
  }
}) : resourceBase

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-08-15' existing = {
  name: accountName

  resource database 'sqlDatabases' existing = {
    name: databaseName
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-08-15' = {
  parent: account::database
  name: containerName
  tags: tags
  properties: {
    resource: resourceFinal
  }
}

output id string = container.id
output name string = container.name
