// Azure Container Registry
// 학습용 Basic SKU, admin 계정 비활성, public network 기본 On (Phase 8 에서 축소)

@description('ACR 리소스 이름. 소문자·영숫자, 5~50자, 전역 유니크.')
param name string

@description('배포 리전')
param location string

@description('공통 태그')
param tags object = {}

@description('SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Basic'

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
  }
}

output id string = registry.id
output name string = registry.name
output loginServer string = registry.properties.loginServer
