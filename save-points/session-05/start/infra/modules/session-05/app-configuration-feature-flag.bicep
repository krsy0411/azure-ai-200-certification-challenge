@description('Parent App Configuration store name')
param storeName string

@description('피처 플래그 이름 (예: enable_semantic_cache)')
param flagName string

@description('초기 활성화 상태')
param enabled bool = true

resource store 'Microsoft.AppConfiguration/configurationStores@2024-05-01' existing = {
  name: storeName
}

// 피처 플래그는 특수 prefix 키 + ff+json 콘텐츠 타입으로 저장된다.
// 키의 '/' 는 child 자원명에 직접 못 쓰므로 App Configuration 규칙대로 ~2F 로 이스케이프
// 한다 (배포 시 '/' 로 복원). 결과 키: .appconfig.featureflag/<flagName>
resource featureFlag 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = {
  parent: store
  name: '.appconfig.featureflag~2F${flagName}'
  properties: {
    value: string({
      id: flagName
      enabled: enabled
      conditions: {
        client_filters: []
      }
    })
    contentType: 'application/vnd.microsoft.appconfig.ff+json'
  }
}

output key string = featureFlag.name
