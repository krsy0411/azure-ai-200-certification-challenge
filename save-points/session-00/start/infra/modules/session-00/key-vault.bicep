@description('Key Vault name (global unique, 3-24 chars)')
@maxLength(24)
param name string

@description('Azure region')
param location string

@description('Tenant ID. Defaults to subscription tenant.')
param tenantId string = subscription().tenantId

@description('SKU. Standard for dev, Premium for HSM.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Soft-delete retention in days. Min 7, max 90.')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 7

@description('Enable purge protection. Recommended true even in dev to avoid 7-day name collisions on cleanup+redeploy.')
param enablePurgeProtection bool = true

@description('Tags')
param tags object = {}

resource kv 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: skuName
    }
    // RBAC-only — access policies not used.
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection ? true : null
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

output id string = kv.id
output name string = kv.name
output vaultUri string = kv.properties.vaultUri
