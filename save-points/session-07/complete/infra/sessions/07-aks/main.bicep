// =============================================================================
// session-07 — Azure Kubernetes Service 대안 배포
//
// 배포 명령:
//   OID=$(az ad signed-in-user show --query id -o tsv)
//   az deployment group create \
//     --resource-group rg-ai200ws-dev \
//     --template-file workshop/infra/sessions/07-aks/main.bicep \
//     --parameters workshop/infra/sessions/07-aks/main.bicepparam \
//     --parameters userObjectId=$OID
//
// 의존성 (existing): session-00 UAMI(워크로드용, AOAI·Cosmos 접근), session-01 ACR,
//                    session-00 Log Analytics Workspace.
//
// 본 세션에서 신규 생성:
//   - AKS 전용 UAMI (control plane + kubelet) + AcrPull + Managed Identity Operator
//   - AKS 클러스터 (Workload Identity·Entra RBAC·disableLocalAccounts·CNI Overlay·omsagent)
//   - Container Insights DCR + DCRA
//   - 워크로드용 federated identity credential (session-00 UAMI ↔ apps-api-sa)
//   - 배포 사용자에 Cluster User Role
// =============================================================================

targetScope = 'resourceGroup'

@description('환경 라벨')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('Azure 자원 기본 리전')
param location string = resourceGroup().location

@description('배포 실행자의 Entra objectId. Cluster User Role 부여. CLI override.')
param userObjectId string = ''

@description('워크로드가 사용할 Kubernetes ServiceAccount (namespace:name)')
param workloadServiceAccount string = 'default:apps-api-sa'

// -------- 공용 태그 ------------------------------------------------------------

var commonTags = {
  project: projectId
  env: env
  workshop: 'azure-ai-200'
  managedBy: 'bicep'
  session: 'session-07'
}

// -------- 자원 이름 ------------------------------------------------------------

var aksName = 'aks-${projectId}-${env}'
var aksUamiName = 'id-aks-${projectId}-${env}'
var dcrName = 'dcr-${projectId}-${env}-ci'

// session-00·01 자원 이름
var uamiName = 'id-${projectId}-${env}'
var lawName = 'law-${projectId}-${env}'
var acrName = take('acr${projectId}${env}${uniqueString(resourceGroup().id, projectId, env)}', 50)

// -------- existing 참조 --------------------------------------------------------

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: lawName
}

// -------- AKS 전용 UAMI (control plane + kubelet) --------------------------------

resource aksUami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: aksUamiName
  location: location
  tags: commonTags
}

// -------- 1) 역할 — AKS UAMI 에 AcrPull + Managed Identity Operator(자기 자신) -----

module acrPull '../../modules/session-07/role-assignment-acrpull.bicep' = {
  name: 'acrPull-aksUami'
  params: {
    acrName: acrName
    principalId: aksUami.properties.principalId
  }
}

module miOperator '../../modules/session-07/role-assignment-mi-operator.bicep' = {
  name: 'miOperator-aksUami'
  params: {
    targetUamiName: aksUamiName
    principalId: aksUami.properties.principalId
  }
}

// -------- 2) AKS 클러스터 -------------------------------------------------------

module aks '../../modules/session-07/aks-cluster.bicep' = {
  name: 'aks'
  params: {
    name: aksName
    location: location
    aksUamiId: aksUami.id
    kubeletClientId: aksUami.properties.clientId
    kubeletObjectId: aksUami.properties.principalId
    logAnalyticsWorkspaceId: law.id
    tags: commonTags
  }
  dependsOn: [
    acrPull
    miOperator
  ]
}

// -------- 3) Container Insights — DCR + DCRA ------------------------------------

module dcr '../../modules/session-07/aks-container-insights-dcr.bicep' = {
  name: 'dcr'
  params: {
    name: dcrName
    location: location
    logAnalyticsWorkspaceId: law.id
    tags: commonTags
  }
}

module dcra '../../modules/session-07/aks-container-insights-dcra.bicep' = {
  name: 'dcra'
  params: {
    clusterName: aks.outputs.name
    dataCollectionRuleId: dcr.outputs.id
  }
}

// -------- 4) 워크로드 federated identity credential (session-00 UAMI) ------------

module fic '../../modules/session-07/federated-identity-credential.bicep' = {
  name: 'fic'
  params: {
    uamiName: uamiName
    name: 'aks-workload'
    issuer: aks.outputs.oidcIssuerUrl
    subject: 'system:serviceaccount:${workloadServiceAccount}'
  }
}

// -------- 5) 배포 사용자에 Cluster User Role ------------------------------------

module clusterUser '../../modules/session-07/role-assignment-aks-cluster-user.bicep' = if (!empty(userObjectId)) {
  name: 'clusterUser-user'
  params: {
    clusterName: aks.outputs.name
    principalId: userObjectId
  }
}

// -------- 출력 -----------------------------------------------------------------

output aksName string = aks.outputs.name
output oidcIssuerUrl string = aks.outputs.oidcIssuerUrl
output acrName string = acrName