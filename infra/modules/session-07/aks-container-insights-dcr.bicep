@description('Data Collection Rule name')
param name string

@description('Azure region')
param location string

@description('대상 Log Analytics Workspace 자원 id')
param logAnalyticsWorkspaceId string

@description('Tags')
param tags object = {}

// Container Insights 는 addonProfiles.omsagent 단독으로는 데이터가 흐르지 않는다.
// DCR(ContainerInsights extension) + DCRA(AKS 연결) 를 명시 선언해야 한다 (docs §주의).
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
            'Microsoft-ContainerLogV2'
            'Microsoft-KubeMonAgentEvents'
            'Microsoft-InsightsMetrics'
            'Microsoft-KubePodInventory'
            'Microsoft-KubeNodeInventory'
          ]
          // enableContainerLogV2 를 켜지 않으면 컨테이너 stdout/stderr 로그가 신규
          // ContainerLogV2 가 아니라 레거시 ContainerLog 테이블로 흘러간다 (docs §3 KQL 은
          // ContainerLogV2 를 조회하므로 빈 결과로 보인다). namespaceFilteringMode=Off 로 모든
          // 네임스페이스(kube-system 제외)의 로그를 수집한다.
          extensionSettings: {
            dataCollectionSettings: {
              interval: '1m'
              namespaceFilteringMode: 'Off'
              namespaces: []
              enableContainerLogV2: true
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'ciworkspace'
          workspaceResourceId: logAnalyticsWorkspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ContainerLogV2'
          'Microsoft-KubeMonAgentEvents'
          'Microsoft-InsightsMetrics'
          'Microsoft-KubePodInventory'
          'Microsoft-KubeNodeInventory'
        ]
        destinations: [
          'ciworkspace'
        ]
      }
    ]
  }
}

output id string = dcr.id