@description('Flex Consumption plan name')
param name string

@description('Azure region')
param location string

@description('Tags')
param tags object = {}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  properties: {
    reserved: true // Linux
  }
}

output id string = plan.id
output name string = plan.name