// Log Analytics Workspace
// ACA Environment 의 로그·진단 싱크로 사용. Phase 9 (Observability) 에서
// Application Insights 의 workspace-based 백엔드로도 재사용.

@description('Workspace 이름')
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('로그 보존 기간 (일)')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('SKU')
param sku string = 'PerGB2018'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output id string = workspace.id
output name string = workspace.name
output customerId string = workspace.properties.customerId

@secure()
output sharedKey string = workspace.listKeys().primarySharedKey
