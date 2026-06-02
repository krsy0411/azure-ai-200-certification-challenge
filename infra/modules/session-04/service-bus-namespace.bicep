@description('Service Bus namespace name (globally unique)')
param name string

@description('Azure region')
param location string

@description('SKU — 토픽·DLQ 등은 Standard 이상 필요. 본 워크샵은 큐 + DLQ 라 Standard.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param skuName string = 'Standard'

@description('Tags')
param tags object = {}

resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    minimumTlsVersion: '1.2'
    disableLocalAuth: true
  }
}

output id string = namespace.id
output name string = namespace.name
output fqdn string = '${namespace.name}.servicebus.windows.net'