// Azure OpenAI Service — 계정 (Microsoft.CognitiveServices/accounts, kind=OpenAI)
// - customSubDomainName 필수: <name>.openai.azure.com 형태 엔드포인트 + AAD 인증에 요구됨
// - disableLocalAuth=true → API key 비활성, AAD 전용. UAMI 가 'Cognitive Services OpenAI User' 역할 보유
// - publicNetworkAccess=Enabled (Phase 9 까지 PE 미도입)
// - SKU 는 S0 고정 (AOAI 표준 SKU)

@description('AOAI 계정 이름 — customSubDomainName 으로도 사용 (소문자/숫자/-)')
@minLength(2)
@maxLength(64)
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('AAD 전용 모드. true 면 키 인증 차단')
param disableLocalAuth bool = true

@description('퍼블릭 네트워크 접근')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    disableLocalAuth: disableLocalAuth
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
  }
}

output id string = account.id
output name string = account.name
output endpoint string = account.properties.endpoint
