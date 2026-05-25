@description('Log Analytics Workspace name')
param name string

@description('Azure region')
param location string

@description('Retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Daily ingest cap in GB. -1 = unlimited.')
param dailyQuotaGb int = -1

@description('Tags')
param tags object = {}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output id string = law.id
output name string = law.name
output customerId string = law.properties.customerId
