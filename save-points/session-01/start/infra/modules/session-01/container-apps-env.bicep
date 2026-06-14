@description('Azure Container Apps Environment name')
param name string

@description('Azure region')
param location string

@description('Log Analytics Workspace customerId (GUID)')
param logAnalyticsCustomerId string

@description('Log Analytics Workspace shared key')
@secure()
param logAnalyticsSharedKey string

@description('Tags')
param tags object = {}

resource cae 'Microsoft.App/managedEnvironments@2024-10-02-preview' = {
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
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false
  }
}

output id string = cae.id
output name string = cae.name
output defaultDomain string = cae.properties.defaultDomain
