// Azure Database for PostgreSQL Flexible Server
//
// 학습 경로 'develop-ai-solutions-azure-database-postgresql' / 모듈 1 단원 2~3 의
// "PostgreSQL 살펴보기 / 보안 연결" 부분을 충족하기 위한 최소 구성.
//
// - version = 16
// - sku = Burstable B1ms (1 vCore, 2 GiB) — 학습용 최저 비용
// - storage = 32 GiB, autoGrow Disabled (Burstable 기본)
// - network = public access (Phase 9 까지 PE 미도입)
// - authConfig = activeDirectoryAuth=Enabled + passwordAuth=Disabled  (Entra-only, AAD admin 은 별도 sub-resource 모듈)
// - HA = Disabled (학습용)
//
// AAD admin (administrators sub-resource), firewall rules, server parameters
// (azure.extensions / pgbouncer) 는 별도 모듈에서 부여한다.

@description('PostgreSQL Flexible Server 이름 (3-63자, 소문자/숫자/-)')
@minLength(3)
@maxLength(63)
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('PostgreSQL 메이저 버전')
@allowed([
  '14'
  '15'
  '16'
  '17'
])
param postgresVersion string = '16'

@description('SKU 이름 (Standard_B1ms = Burstable 1 vCore 2 GiB)')
param skuName string = 'Standard_B1ms'

@description('SKU tier')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param skuTier string = 'Burstable'

@description('스토리지 크기 (GiB)')
@minValue(32)
param storageSizeGB int = 32

@description('AAD-only 모드 여부. true 면 password 인증 비활성, AAD admin 등록 후에만 사용 가능')
param entraOnlyAuth bool = true

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: postgresVersion
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: entraOnlyAuth ? 'Disabled' : 'Enabled'
      tenantId: subscription().tenantId
    }
    highAvailability: {
      mode: 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
  }
}

output id string = server.id
output name string = server.name
output fqdn string = server.properties.fullyQualifiedDomainName
