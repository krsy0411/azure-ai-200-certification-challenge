@description('Azure Managed Redis (Redis Enterprise) cluster name (globally unique — forms <name>.<region>.redisenterprise.cache.azure.net)')
@minLength(3)
@maxLength(60)
param name string

@description('Azure region')
param location string

@description('SKU name. Balanced_B0 은 Azure Managed Redis 의 가장 작은 등급 (학습용 비용 최소화).')
param skuName string = 'Balanced_B0'

@description('Minimum TLS version')
param minimumTlsVersion string = '1.2'

@description('Tags')
param tags object = {}

resource cluster 'Microsoft.Cache/redisEnterprise@2025-04-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    minimumTlsVersion: minimumTlsVersion
  }
}

output id string = cluster.id
output name string = cluster.name
output hostName string = cluster.properties.hostName
