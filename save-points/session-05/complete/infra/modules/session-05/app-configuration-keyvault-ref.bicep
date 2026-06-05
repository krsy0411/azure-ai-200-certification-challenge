@description('Parent App Configuration store name')
param storeName string

@description('Key 이름 (예: secrets:aoai-endpoint)')
param key string

@description('참조할 Key Vault secret 의 전체 URI (예: https://kv-....vault.azure.net/secrets/aoai-endpoint)')
param secretUri string

resource store 'Microsoft.AppConfiguration/configurationStores@2024-05-01' existing = {
  name: storeName
}

// Key Vault reference — 값이 아니라 secret URI 포인터만 저장한다. Provider 가 load() 시
// keyvault_credential 로 자동 해석한다. 버전 식별자는 생략(회전 자동 추종).
resource keyVaultRef 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = {
  parent: store
  name: key
  properties: {
    value: string({
      uri: secretUri
    })
    contentType: 'application/vnd.microsoft.appconfig.keyvaultref+json'
  }
}

output key string = keyVaultRef.name
