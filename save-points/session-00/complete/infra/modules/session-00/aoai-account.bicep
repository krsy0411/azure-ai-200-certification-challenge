@description('Azure OpenAI account name (global unique)')
param name string

@description('Azure region (AOAI 가용 리전)')
param location string

@description('Custom subdomain. Defaults to account name. Required for AAD/MI auth.')
param customSubdomainName string = name

@description('Disable local (key) auth. true = AAD/MI only.')
param disableLocalAuth bool = true

@description('Public network access')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Tags')
param tags object = {}

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  kind: 'OpenAI'
  tags: tags
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: customSubdomainName
    disableLocalAuth: disableLocalAuth
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

output id string = aoai.id
output name string = aoai.name
output endpoint string = aoai.properties.endpoint
