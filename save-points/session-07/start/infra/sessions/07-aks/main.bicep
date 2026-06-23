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
// 본 세션에서 할 일:
//   아래 그룹별 모듈 호출과 출력 블록을 직접 채운다. 모듈 본체는
//   ../../modules/session-07/ 에 이미 완성되어 있다 (수정하지 않는다).
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

// -------- 1) 역할 — AKS UAMI 에 AcrPull + Managed Identity Operator 모듈 호출하기 ---
// 힌트: role-assignment-acrpull.bicep (acrName, principalId=aksUami.properties.principalId)
//       + role-assignment-mi-operator.bicep (targetUamiName=aksUamiName, 같은 principalId).

// -------- 2) AKS 클러스터 모듈 호출하기 --------------------------------------
// 힌트: aks-cluster.bicep. aksUamiId=aksUami.id, kubeletClientId=aksUami.properties.clientId,
//       kubeletObjectId=aksUami.properties.principalId, logAnalyticsWorkspaceId=law.id.
//       dependsOn 에 1)의 역할 2개 (클러스터 생성 전 RBAC 보장).

// -------- 3) Container Insights — DCR + DCRA 모듈 호출하기 -------------------
// 힌트: aks-container-insights-dcr.bicep (name=dcrName, logAnalyticsWorkspaceId=law.id) →
//       aks-container-insights-dcra.bicep (clusterName=aks.outputs.name, dcr.outputs.id).

// -------- 4) 워크로드 federated identity credential 모듈 호출하기 ------------
// 힌트: federated-identity-credential.bicep. uamiName=uamiName(session-00),
//       issuer=aks.outputs.oidcIssuerUrl,
//       subject='system:serviceaccount:${workloadServiceAccount}'.

// -------- 5) 배포 사용자에 Cluster User Role + RBAC Cluster Admin 모듈 호출하기 ---
// 힌트: 둘 다 if (!empty(userObjectId)) 조건부, clusterName=aks.outputs.name, principalId=userObjectId.
//       role-assignment-aks-cluster-user.bicep — kubeconfig 다운로드용 Cluster User Role.
//       role-assignment-aks-rbac-admin.bicep   — enableAzureRBAC=true 라 kubectl get/apply
//                                                 데이터플레인 권한이 별도로 필요 (없으면 Forbidden).

// -------- 출력 -----------------------------------------------------------------
// 힌트: aksName, oidcIssuerUrl(aks.outputs.oidcIssuerUrl), acrName.