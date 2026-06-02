@description('Parent Azure Managed Redis cluster name')
param clusterName string

@description('클라이언트 프로토콜 — Encrypted (TLS) 강제')
param clientProtocol string = 'Encrypted'

@description('포트 — Azure Managed Redis 기본 10000')
param port int = 10000

@description('클러스터링 정책 — 모듈(RediSearch) 사용에는 EnterpriseCluster 가 단순')
param clusteringPolicy string = 'EnterpriseCluster'

resource cluster 'Microsoft.Cache/redisEnterprise@2025-04-01' existing = {
  name: clusterName
}

// Redis Enterprise 는 클러스터당 데이터베이스 1개, 이름은 반드시 'default'.
// RediSearch + 벡터 인덱스를 쓰므로 eviction 은 NoEviction 으로 고정한다 — 그 외 정책은
// 인덱스를 stale 하게 만든다 (docs §주의). 인증은 access key 를 끄고 Entra ID 전용.
resource database 'Microsoft.Cache/redisEnterprise/databases@2025-04-01' = {
  parent: cluster
  name: 'default'
  properties: {
    clientProtocol: clientProtocol
    port: port
    evictionPolicy: 'NoEviction'
    clusteringPolicy: clusteringPolicy
    accessKeysAuthentication: 'Disabled'
    modules: [
      {
        name: 'RediSearch'
      }
    ]
  }
}

output name string = database.name
output port int = database.properties.port
