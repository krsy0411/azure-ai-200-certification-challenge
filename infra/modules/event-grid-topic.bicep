// Event Grid 사용자 지정 토픽 — CloudEvents 1.0 + AAD-only
//
// 학습 경로 모듈 2 단원 3·5 매핑:
// - inputSchema='CloudEventSchemaV1_0' (학습 경로 표준 권장)
// - disableLocalAuth=true → Entra 토큰만 (publisher SAS key 비활성)
// - publicNetworkAccess=Enabled

@description('Event Grid 토픽 이름')
@minLength(3)
@maxLength(50)
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

resource topic 'Microsoft.EventGrid/topics@2025-02-15' = {
  name: name
  location: location
  tags: tags
  properties: {
    inputSchema: 'CloudEventSchemaV1_0'
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    minimumTlsVersionAllowed: '1.2'
  }
}

output id string = topic.id
output name string = topic.name
output endpoint string = topic.properties.endpoint
