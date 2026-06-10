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

// disableLocalAuth 는 false 로 둔다. Azure 는 local auth 가 비활성화된 store 에는
// ARM/Bicep 으로 keyValues·featureFlags 를 시드할 수 없다 (배포 시 Conflict —
// "please use pass-through authentication mode"). 본 store 는 실제 시크릿을 담지 않고
// (endpoint·host·KV 참조 URI·플래그만), 앱은 connection string 이 아니라 endpoint +
// UAMI(App Configuration Data Reader) 로 읽으므로 접근키는 사용되지 않는다.
// 더 엄격한 posture 가 필요하면 keyValues 를 ARM 대신 `az appconfig kv set --auth-mode
// login` (Entra) 으로 시드하고 disableLocalAuth=true 로 둘 수 있다.
resource store 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    disableLocalAuth: false
  }
}

output id string = store.id
output name string = store.name
output endpoint string = store.properties.endpoint
