@description('Parent AOAI account name')
param accountName string

@description('Deployment name (학습자가 코드에서 부르는 이름)')
param deploymentName string

@description('Model name (e.g. gpt-5-mini, text-embedding-3-large)')
param modelName string

@description('Model version (e.g. 2025-08-07 for gpt-5-mini, 1 for text-embedding-3-large)')
param modelVersion string

@description('Model format')
param modelFormat string = 'OpenAI'

@description('Deployment SKU name')
@allowed([
  'Standard'
  'GlobalStandard'
  'DataZoneStandard'
])
param skuName string = 'Standard'

@description('Capacity in 1000 TPM units. Adjust per quota.')
param capacity int = 10

@description('RAI policy (Content filter). Microsoft.DefaultV2 is built-in.')
param raiPolicyName string = 'Microsoft.DefaultV2'

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: accountName
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aoai
  name: deploymentName
  sku: {
    name: skuName
    capacity: capacity
  }
  properties: {
    model: {
      format: modelFormat
      name: modelName
      version: modelVersion
    }
    raiPolicyName: raiPolicyName
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
}

output id string = deployment.id
output name string = deployment.name
