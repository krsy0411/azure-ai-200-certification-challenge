@description('대상 AKS cluster name')
param clusterName string

@description('연결할 Data Collection Rule 자원 id')
param dataCollectionRuleId string

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: clusterName
}

// DCRA 는 AKS 클러스터에 scope 를 두는 extension 자원. 이 연결이 있어야 omsagent 가
// 수집한 데이터가 DCR 을 거쳐 Log Analytics 로 흐른다.
resource dcra 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'ContainerInsightsExtension'
  scope: aks
  properties: {
    dataCollectionRuleId: dataCollectionRuleId
  }
}

output id string = dcra.id