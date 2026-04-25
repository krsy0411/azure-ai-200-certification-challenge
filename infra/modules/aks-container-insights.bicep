// Container Insights — DCR + DCRA (AMA 기반 로그 수집 경로)
//
// 왜 이 모듈이 필요한가:
// - AKS 의 `addonProfiles.omsagent` 만 enable 해도 데이터 플레인(ama-logs DaemonSet)은
//   기동되지만, 실제 LAW 로 데이터를 흘려보내려면 **DCR(어디로 보낼지)** + **DCRA(클러스터
//   ↔ DCR 연결)** 라는 제어 플레인 리소스가 별도로 있어야 한다.
// - `az aks enable-addons -a monitoring` CLI 는 이 두 리소스를 자동 생성해 주지만, 순수
//   Bicep 으로 `addonProfiles.omsagent` 만 선언하면 자동 생성이 트리거되지 않아 ama-logs
//   파드는 떠 있는데도 LAW 에 데이터가 0 행으로 머문다 (Phase 3 에서 직접 부딪힌 함정).
// - 따라서 IaC 일관성을 위해 본 모듈로 DCR + DCRA 를 명시적으로 선언한다.
//
// 리소스 모양은 CLI 가 생성한 산출물을 동등하게 재현:
//   DCR 이름:  MSCI-<location>-<clusterName>  (Azure 표준 패턴)
//   DCR.kind: Linux
//   dataSources.extensions[0]: ContainerInsights / enableContainerLogV2=true
//   destinations.logAnalytics[0]: la-workspace → 외부 LAW
//   dataFlows[0]: Microsoft-ContainerInsights-Group-Default → la-workspace
//   DCRA 이름: ContainerInsightsExtension (cluster scope, 표준값)
//
// 주의: 본 모듈은 AKS 클러스터가 **이미 존재** 한다고 가정한다. main.bicep 에서
// aks 모듈에 dependsOn 으로 묶을 것.

@description('DCR 이름. Azure 가 CLI 로 자동생성할 때의 이름과 동일하게 맞춰 둔다 (재배포 멱등성).')
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('Container Insights 가 데이터를 보낼 Log Analytics Workspace resource ID')
param logAnalyticsWorkspaceId string

@description('DCRA 를 부착할 AKS 클러스터 이름 (existing 으로 참조)')
param aksClusterName string

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' existing = {
  name: aksClusterName
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: name
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          extensionName: 'ContainerInsights'
          streams: [
            'Microsoft-ContainerInsights-Group-Default'
          ]
          extensionSettings: {
            dataCollectionSettings: {
              enableContainerLogV2: true
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'la-workspace'
          workspaceResourceId: logAnalyticsWorkspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ContainerInsights-Group-Default'
        ]
        destinations: [
          'la-workspace'
        ]
      }
    ]
  }
}

resource dcra 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'ContainerInsightsExtension'
  scope: aks
  properties: {
    dataCollectionRuleId: dcr.id
    description: 'associates dataCollectionRule to the AKS'
  }
}

output dcrId string = dcr.id
output dcrName string = dcr.name
output dcraId string = dcra.id
