// AKS 클러스터 (보조 워커용)
// - Entra ID 통합 + Azure RBAC on, 로컬 계정 disable
// - system 노드 풀 1개 (VM Scale Set 기반)
// - Azure CNI Overlay 네트워킹
// - control plane identity = UAMI (AKS API 가 Azure 리소스 조작에 사용)
// - kubelet identity = 같은 UAMI (ACR pull 권한 담당)
// - Container Insights 애드온 → 외부 Log Analytics Workspace 에 로그/메트릭 싱크
//
// Phase 2 의 ACA 가 메인이고 이 클러스터는 학습·보조 워커 역할. 비용 최적화를 위해
// 배포·검증 후 `az aks stop` 으로 중단 가능 (디스크 비용만 잔존).
//
// 왜 control plane 도 UAMI 인가: AKS 는 `identityProfile.kubeletidentity` (custom
// kubelet identity) 를 주입하려면 control plane 도 UserAssigned 여야 한다. 같은 UAMI
// 를 두 역할에 모두 쓰면 관리 단순화. 단, control plane 이 kubelet identity 를
// orchestrate 하기 위해 **Managed Identity Operator** 역할이 필요한데, 같은 identity
// 라서 자기 자신에 대한 self role assignment 로 부여한다 (상위 main.bicep 에서).

@description('AKS 클러스터 이름')
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('control plane 이 쓸 UAMI resource ID. 본 프로젝트는 kubelet identity 와 동일한 UAMI 사용')
param controlPlaneIdentityId string

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

@description('system 노드 VM 크기. 기본값은 DSv3 Family (koreacentral 기본 쿼터가 있는 가장 보수적인 선택)')
param systemNodeVmSize string = 'Standard_D2s_v3'

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
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${controlPlaneIdentityId}': {}
    }
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
