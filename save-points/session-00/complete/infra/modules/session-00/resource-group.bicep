targetScope = 'subscription'

@description('RG name')
param name string

@description('Azure region')
param location string

@description('Tags applied to the RG')
param tags object = {}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: name
  location: location
  tags: tags
}

output id string = rg.id
output name string = rg.name
