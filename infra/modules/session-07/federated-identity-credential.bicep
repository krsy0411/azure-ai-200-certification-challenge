@description('federated credential 을 붙일 User Assigned Managed Identity 이름 (워크로드용 — session-00 UAMI)')
param uamiName string

@description('federated credential 이름')
param name string = 'aks-workload'

@description('AKS OIDC issuer URL')
param issuer string

@description('Kubernetes ServiceAccount subject — system:serviceaccount:<namespace>:<sa-name>')
param subject string

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: uamiName
}

// Workload Identity — 파드의 ServiceAccount 토큰을 이 UAMI 와 신뢰 연결한다.
// 파드는 시크릿 없이 DefaultAzureCredential 로 Azure 자원(AOAI·Cosmos)에 접근한다.
resource fic 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: uami
  name: name
  properties: {
    issuer: issuer
    subject: subject
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

output id string = fic.id