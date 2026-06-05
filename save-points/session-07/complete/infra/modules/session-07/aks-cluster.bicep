@description('AKS cluster name')
param name string

@description('Azure region')
param location string

@description('DNS prefix')
param dnsPrefix string = name

@description('control plane + kubelet 로 쓸 User Assigned Managed Identity 의 자원 id')
param aksUamiId string

@description('kubelet identity 의 clientId / objectId (custom kubelet identity 지정에 필요)')
param kubeletClientId string
param kubeletObjectId string

@description('Container Insights 가 데이터를 보낼 Log Analytics Workspace 자원 id')
param logAnalyticsWorkspaceId string

@description('노드 VM SKU — koreacentral DSv5 할당량 0 함정 회피 위해 DSv3 사용')
param nodeVmSize string = 'Standard_D2s_v3'

@description('노드 수')
param nodeCount int = 2

@description('Tags')
param tags object = {}

// control plane·kubelet 모두 UserAssigned (custom kubelet identity 함정 회피),
// Entra ID + Azure RBAC + disableLocalAccounts, Workload Identity(OIDC) 활성.
resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksUamiId}': {}
    }
  }
  properties: {
    dnsPrefix: dnsPrefix
    disableLocalAccounts: true
    enableRBAC: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    identityProfile: {
      kubeletidentity: {
        resourceId: aksUamiId
        clientId: kubeletClientId
        objectId: kubeletObjectId
      }
    }
    agentPoolProfiles: [
      {
        name: 'system'
        count: nodeCount
        vmSize: nodeVmSize
        mode: 'System'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    }
  }
}

output id string = aks.id
output name string = aks.name
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
