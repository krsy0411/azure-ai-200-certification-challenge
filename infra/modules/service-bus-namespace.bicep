// Azure Service Bus namespace — Standard SKU + AAD-only
//
// 학습 경로 'integrate-backend-services-ai-solutions' / 모듈 1 단원 3·5 매핑:
// - SKU 비교 (Basic 제외, Standard 선택) + AAD+Managed Identity 권장
// - disableLocalAuth=true → SAS 인증 비활성, Entra 토큰만 사용
// - publicNetworkAccess=Enabled (Phase 9 PE 까지)
// - minimumTlsVersion=1.2

// ARM 측 실제 제한 6-50자. 단 Bicep 컴파일러가 string concat 결과의 minLength 를
// 보수적으로 추론해 BCP334 경고가 뜨므로 모듈 측에선 minLength 를 풀어둠 (실 배포에서 ARM 검증).
@description('Service Bus namespace 이름 (6-50자, 영숫자/-)')
@maxLength(50)
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('SKU — Standard 권장 (큐+토픽+구독 + 256KB)')
@allowed([
  'Standard'
  'Premium'
])
param skuName string = 'Standard'

resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    minimumTlsVersion: '1.2'
    zoneRedundant: false
  }
}

output id string = namespace.id
output name string = namespace.name
output hostName string = '${namespace.name}.servicebus.windows.net'
