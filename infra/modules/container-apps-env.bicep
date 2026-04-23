// Azure Container Apps Managed Environment
// Container App 들이 공유하는 네트워크·로그·Dapr 경계.
// 내부 ingress 앱은 이 Environment 의 private 도메인 안에서 서로 도달.

@description('Environment 이름')
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('Log Analytics Workspace customer (GUID) — 로그 대상')
param logAnalyticsCustomerId string

@description('Log Analytics Workspace primary shared key')
@secure()
param logAnalyticsSharedKey string

@description('Zone 이중화 (B-Series/soft-SKU 기본 false)')
param zoneRedundant bool = false

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    zoneRedundant: zoneRedundant
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output id string = env.id
output name string = env.name
output defaultDomain string = env.properties.defaultDomain
output staticIp string = env.properties.staticIp
