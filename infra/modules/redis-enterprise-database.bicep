// Azure Managed Redis — database (default) + RediSearch + AAD-only
//
// 학습 경로 모듈 3 단원 2 (FT.CREATE / KNN) 은 RediSearch 모듈이 활성화돼야 동작.
// 학습 경로 모듈 1 단원 4 (TTL / 캐시 무효화) 는 evictionPolicy 와 결합되지만,
// **RediSearch 모듈이 켜진 database 는 evictionPolicy 가 'NoEviction' 으로 강제**된다
// (Azure Managed Redis 제약 — 학습 경로 본문에는 강조되지 않은 함정).
// TTL 캐시 정리는 evictionPolicy 가 아니라 키별 EXPIRE 로 처리한다.
//
// - clusteringPolicy = EnterpriseCluster (Azure Managed Redis 기본 권장)
// - evictionPolicy = NoEviction (RediSearch 활성화 시 필수)
// - clientProtocol = Encrypted (TLS 강제)
// - port = 10000
// - accessKeysAuthentication = Disabled  → AAD-only (CLAUDE.md §8 + Phase 4·5 일관성)
// - modules = [{ name: 'RediSearch' }]
//
// modules 는 *creation time only* — 나중에 추가/제거하려면 database 재생성 필요.

@description('상위 redisEnterprise 클러스터 이름')
param clusterName string

@description('database 이름 (default 권장)')
param databaseName string = 'default'

@description('eviction 정책 — RediSearch 활성화 시 NoEviction 강제')
@allowed([
  'AllKeysLFU'
  'AllKeysLRU'
  'AllKeysRandom'
  'NoEviction'
  'VolatileLFU'
  'VolatileLRU'
  'VolatileRandom'
  'VolatileTTL'
])
param evictionPolicy string = 'NoEviction'

@description('클러스터링 정책')
@allowed([
  'EnterpriseCluster'
  'OSSCluster'
  'NoCluster'
])
param clusteringPolicy string = 'EnterpriseCluster'

@description('database 포트')
param port int = 10000

resource cluster 'Microsoft.Cache/redisEnterprise@2025-07-01' existing = {
  name: clusterName
}

resource database 'Microsoft.Cache/redisEnterprise/databases@2025-07-01' = {
  parent: cluster
  name: databaseName
  properties: {
    clientProtocol: 'Encrypted'
    clusteringPolicy: clusteringPolicy
    evictionPolicy: evictionPolicy
    port: port
    accessKeysAuthentication: 'Disabled'
    modules: [
      {
        name: 'RediSearch'
      }
    ]
  }
}

output id string = database.id
output name string = database.name
output port int = database.properties.port
