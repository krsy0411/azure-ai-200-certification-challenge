// Azure Managed Redis (Microsoft.Cache/redisEnterprise) — cluster
//
// 학습 경로 'enhance-ai-solutions-azure-managed-redis' / 모듈 1 단원 2
// "Azure Managed Redis 살펴보기" 의 dev/test 권장 계층 (Memory Optimized) 을 채택.
//
// - sku.name = MemoryOptimized_M10 (학습 경로 dev/test 권장, RediSearch 포함)
//   * capacity 는 Enterprise/EnterpriseFlash SKU 만 사용 — MemoryOptimized 는 지정 X
// - publicNetworkAccess = Enabled (Phase 9 PE 까지)
// - minimumTlsVersion = '1.2'
// - highAvailability = Enabled (default 이지만 명시)
//
// AAD-only 강제 (accessKeysAuthentication = Disabled) 와 RediSearch 모듈은
// 자식 database 모듈에서 부여한다.

@description('Redis Enterprise 클러스터 이름 (1-60자, 영숫자/-)')
@minLength(1)
@maxLength(60)
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('SKU 이름 — MemoryOptimized_M10 (학습 경로 dev/test 권장)')
@allowed([
  'MemoryOptimized_M10'
  'MemoryOptimized_M20'
  'MemoryOptimized_M50'
  'Balanced_B0'
  'Balanced_B1'
  'Balanced_B3'
  'Balanced_B5'
  'ComputeOptimized_X3'
  'ComputeOptimized_X5'
])
param skuName string = 'MemoryOptimized_M10'

@description('최소 TLS 버전')
@allowed([
  '1.2'
])
param minimumTlsVersion string = '1.2'

resource cluster 'Microsoft.Cache/redisEnterprise@2025-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    minimumTlsVersion: minimumTlsVersion
    publicNetworkAccess: 'Enabled'
    highAvailability: 'Enabled'
  }
}

output id string = cluster.id
output name string = cluster.name
output hostName string = cluster.properties.hostName
