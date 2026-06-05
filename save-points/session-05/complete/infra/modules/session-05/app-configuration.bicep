@description('App Configuration store name')
param name string

@description('Azure region')
param location string

@description('SKU — Free 등급으로 충분 (피처 플래그·KV 참조·레이블 모두 지원). 비용 0.')
@allowed([
  'free'
  'standard'
])
param skuName string = 'free'

@description('Tags')
param tags object = {}

// disableLocalAuth=true — 연결 문자열 대신 Entra ID + RBAC 만 허용.
resource store 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    disableLocalAuth: true
  }
}

output id string = store.id
output name string = store.name
output endpoint string = store.properties.endpoint
