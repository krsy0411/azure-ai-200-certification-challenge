@description('Parent Key Vault name')
param keyVaultName string

@description('Secret name')
param name string

@description('Secret value')
@secure()
param value string

@description('Content type (예: text/plain, application/json)')
param contentType string = 'text/plain'

resource kv 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
  parent: kv
  name: name
  properties: {
    value: value
    contentType: contentType
    attributes: {
      enabled: true
    }
  }
}

output id string = secret.id
output name string = secret.name
output uri string = secret.properties.secretUri
