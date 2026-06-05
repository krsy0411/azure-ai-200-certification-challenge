@description('Parent App Configuration store name')
param storeName string

@description('Key 이름 (예: aoai:endpoint)')
param key string

@description('값')
param value string

resource store 'Microsoft.AppConfiguration/configurationStores@2024-05-01' existing = {
  name: storeName
}

// label 은 사용하지 않는다 (단일 dev 환경). name = key.
resource keyValue 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = {
  parent: store
  name: key
  properties: {
    value: value
  }
}

output key string = keyValue.name
