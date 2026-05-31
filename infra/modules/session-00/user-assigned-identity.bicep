@description('UAMI name')
param name string

@description('Azure region')
param location string

@description('Tags')
param tags object = {}

resource id 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: name
  location: location
  tags: tags
}

output id string = id.id
output name string = id.name
output principalId string = id.properties.principalId
output clientId string = id.properties.clientId
