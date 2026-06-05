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