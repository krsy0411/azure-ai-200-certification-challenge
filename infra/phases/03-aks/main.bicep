// Phase 3 — Azure Kubernetes Service 보조 클러스터
//
// 생성 리소스 (모두 rg-ai200challenge-<env> 안):
// - UAMI (id-ai200challenge-aks-<env>) — kubelet identity 로 사용
//   · Phase 1 ACR 에 대한 AcrPull 역할 할당
// - AKS 클러스터 (aks-ai200challenge-<env>)
//   · Entra ID 통합 + Azure RBAC on, 로컬 계정 disable
//   · system 노드 풀 2 × Standard_D2s_v5
//   · Azure CNI Overlay
//   · Container Insights 애드온 → Phase 2 LAW 재사용
// - AKS 클러스터 RBAC Cluster Admin 역할 할당 (signed-in user)
//
// resourceGroup 스코프. Phase 1 ACR, Phase 2 LAW 를 existing 으로 참조.
//
// AI-200 DoD: 클러스터 배포 + 1 Pod 운영 + Container Insights 모니터링.
// kubectl 로 Deployment/Service/HPA 를 별도 배포하며, 해당 매니페스트는
// `infra/phases/03-aks/k8s/api-deployment.yaml` 에 함께 버전관리된다.

targetScope = 'resourceGroup'

@description('배포 리전')
param location string = 'koreacentral'

@description('환경 라벨 (dev | prod)')
param environment string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200challenge'

@description('ACR 전역 유니크 접미사 (Phase 1/2 와 동일해야 같은 ACR 을 참조)')
@minLength(2)
@maxLength(4)
param acrSuffix string

@description('AAD 테넌트 ID (배포 시 AZURE_TENANT_ID 환경변수로 주입)')
param aadTenantId string

@description('cluster admin 으로 등록할 AAD objectId 배열 (배포 시 AKS_ADMIN_OBJECT_IDS 환경변수로 주입)')
param adminGroupObjectIDs array

@description('cluster admin role assignment 의 principal type')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param adminPrincipalType string = 'User'

@description('system 노드 VM 크기. 기본값은 DSv3 Family (koreacentral 기본 쿼터가 있는 가장 보수적인 선택)')
param systemNodeVmSize string = 'Standard_D2s_v3'

@description('system 노드 수')
@minValue(1)
@maxValue(5)
param systemNodeCount int = 2

@description('Kubernetes 버전. 빈 문자열이면 AKS 권장 기본값')
param kubernetesVersion string = ''

var acrName = 'acr${projectId}${environment}${acrSuffix}'
var lawName = 'law-${projectId}-${environment}'
var uamiName = 'id-${projectId}-aks-${environment}'
var aksName = 'aks-${projectId}-${environment}'

var commonTags = {
  project: projectId
  env: environment
  phase: '3'
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// 0) 기존 리소스 참조 — 네이밍 규칙으로 역산
//    Phase 1 ACR 은 모듈에 acrName 문자열만 전달하면 되므로 existing 불필요
//    Phase 2 LAW 는 resource ID 가 필요해 existing 으로 참조
// ---------------------------------------------------------------------------
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: lawName
}

// ---------------------------------------------------------------------------
// 1) UAMI — kubelet identity (ACR pull 담당)
// ---------------------------------------------------------------------------
module uami '../../modules/user-assigned-identity.bicep' = {
  name: 'deploy-uami-aks'
  params: {
    name: uamiName
    location: location
    tags: commonTags
  }
}

// ---------------------------------------------------------------------------
// 2) UAMI → ACR AcrPull 역할 할당 (Phase 1/2 모듈 재사용)
// ---------------------------------------------------------------------------
module uamiAcrPull '../../modules/role-assignment-acrpull.bicep' = {
  name: 'ra-acrpull-aks-uami'
  params: {
    acrName: acrName
    principalId: uami.outputs.principalId
  }
}

// ---------------------------------------------------------------------------
// 3) UAMI → UAMI 자기자신에 Managed Identity Operator 역할 할당
//    control plane 이 kubelet identity 를 orchestrate 하려면 이 역할이 필요.
//    본 프로젝트는 같은 UAMI 를 control plane / kubelet 양쪽에 쓰므로 self 할당.
// ---------------------------------------------------------------------------
module uamiMiOperator '../../modules/role-assignment-mi-operator.bicep' = {
  name: 'ra-mi-operator-aks-uami'
  params: {
    targetIdentityId: uami.outputs.id
    targetIdentityName: uami.outputs.name
    principalId: uami.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// 4) AKS 클러스터
//    kubelet identity 를 위에서 만든 UAMI 로 주입 → 별도 --attach-acr 불필요
//    control plane identity 도 같은 UAMI 사용
// ---------------------------------------------------------------------------
module aks '../../modules/aks-cluster.bicep' = {
  name: 'deploy-aks'
  params: {
    name: aksName
    location: location
    tags: commonTags
    controlPlaneIdentityId: uami.outputs.id
    kubeletIdentityId: uami.outputs.id
    kubeletIdentityClientId: uami.outputs.clientId
    kubeletIdentityPrincipalId: uami.outputs.principalId
    logAnalyticsWorkspaceId: law.id
    aadTenantId: aadTenantId
    adminGroupObjectIDs: adminGroupObjectIDs
    systemNodeVmSize: systemNodeVmSize
    systemNodeCount: systemNodeCount
    kubernetesVersion: kubernetesVersion
  }
  dependsOn: [ uamiAcrPull, uamiMiOperator ]
}

// ---------------------------------------------------------------------------
// 5) signed-in user 에게 AKS RBAC Cluster Admin 역할
//    disableLocalAccounts=true 환경에서 kubectl 사용 가능하게 함
// ---------------------------------------------------------------------------
module aksAdmin '../../modules/role-assignment-aks-cluster-admin.bicep' = [for principalId in adminGroupObjectIDs: {
  name: 'ra-aks-admin-${uniqueString(principalId)}'
  params: {
    aksName: aks.outputs.name
    principalId: principalId
    principalType: adminPrincipalType
  }
}]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output kubeletIdentityId string = uami.outputs.id
output kubeletIdentityPrincipalId string = uami.outputs.principalId
output aksName string = aks.outputs.name
output aksFqdn string = aks.outputs.fqdn
output aksNodeResourceGroup string = aks.outputs.nodeResourceGroup
output getCredentialsCommand string = 'az aks get-credentials --resource-group ${resourceGroup().name} --name ${aks.outputs.name} --overwrite-existing'
