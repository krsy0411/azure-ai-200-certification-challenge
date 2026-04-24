// AKS 클러스터 (보조 워커용)
// - Entra ID 통합 + Azure RBAC on, 로컬 계정 disable
// - system 노드 풀 1개 (VM Scale Set 기반)
// - Azure CNI Overlay 네트워킹
// - kubelet identity = UAMI (ACR pull 권한 담당)
// - Container Insights 애드온 → 외부 Log Analytics Workspace 에 로그/메트릭 싱크
//
// Phase 2 의 ACA 가 메인이고 이 클러스터는 학습·보조 워커 역할. 비용 최적화를 위해
// 배포·검증 후 `az aks stop` 으로 중단 가능 (디스크 비용만 잔존).

@description('AKS 클러스터 이름')
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('kubelet 이 ACR pull 등에 쓸 UAMI resource ID')
param kubeletIdentityId string

@description('kubelet UAMI 의 clientId')
param kubeletIdentityClientId string

@description('kubelet UAMI 의 principalId (objectId)')
param kubeletIdentityPrincipalId string

@description('Container Insights 가 사용할 Log Analytics Workspace resource ID')
param logAnalyticsWorkspaceId string

@description('AAD 테넌트 ID')
param aadTenantId string

@description('cluster admin 으로 등록할 AAD objectId 배열 (개인 계정 또는 그룹 ID)')
param adminGroupObjectIDs array = []

@description('system 노드 VM 크기')
param systemNodeVmSize string = 'Standard_D2s_v5'

@description('system 노드 수')
@minValue(1)
@maxValue(5)
param systemNodeCount int = 2

@description('Kubernetes 버전. 빈 문자열이면 AKS 권장 기본값 사용')
param kubernetesVersion string = ''

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: '${name}-dns'
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    enableRBAC: true
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      tenantID: aadTenantId
      adminGroupObjectIDs: adminGroupObjectIDs
    }
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: false
        osDiskType: 'Managed'
        osDiskSizeGB: 64
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'none'
      loadBalancerSku: 'standard'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      podCidr: '10.244.0.0/16'
    }
    identityProfile: {
      kubeletidentity: {
        resourceId: kubeletIdentityId
        clientId: kubeletIdentityClientId
        objectId: kubeletIdentityPrincipalId
      }
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
    }
  }
}

output id string = aks.id
output name string = aks.name
output fqdn string = aks.properties.fqdn
output nodeResourceGroup string = aks.properties.nodeResourceGroup
output oidcIssuerUrl string = ''
