@description('PostgreSQL Flexible Server name (globally unique — forms <name>.postgres.database.azure.com)')
@minLength(3)
@maxLength(63)
param name string

@description('Azure region')
param location string

@description('PostgreSQL major version')
@allowed([
  '15'
  '16'
])
param version string = '16'

@description('Compute SKU name. Burstable B1ms 는 학습용 최소 등급.')
param skuName string = 'Standard_B1ms'

@description('Compute tier')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param skuTier string = 'Burstable'

@description('Storage size in GB')
param storageSizeGB int = 32

@description('Tags')
param tags object = {}

// Entra ID 전용 인증 — 비밀번호 인증을 끈다. 따라서 administratorLogin/Password 를
// 지정하지 않으며, 별도 administrators 자원 (postgres-aad-admin.bicep) 으로 Entra 관리자를
// 부여해야 접속이 가능하다.
resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: version
    storage: {
      storageSizeGB: storageSizeGB
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
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

output id string = pg.id
output name string = pg.name
output fqdn string = pg.properties.fullyQualifiedDomainName
