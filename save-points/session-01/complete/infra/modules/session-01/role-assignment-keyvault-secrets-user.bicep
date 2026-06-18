@description('Key Vault name. Role assignment is scoped to this Key Vault.')
param keyVaultName string

@description('Principal (UAMI principalId 또는 user objectId)')
param principalId string

@description('Principal type')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

// Built-in role: Key Vault Secrets User
// https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/security#key-vault-secrets-user
var keyVaultSecretsUserId = '4633458b-17de-408a-b874-0445c86b69e6'

resource kv 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, principalId, keyVaultSecretsUserId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserId)
    principalId: principalId
    principalType: principalType
  }
}

output id string = roleAssignment.id
