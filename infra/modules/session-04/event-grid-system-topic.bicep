@description('Event Grid system topic name')
param name string

@description('Azure region')
param location string

@description('이벤트 소스 자원 id (Storage account). Blob Created 이벤트를 발행한다.')
param sourceStorageAccountId string

@description('Tags')
param tags object = {}

// SystemAssigned 관리 ID — 이 ID 로 Service Bus 큐에 이벤트를 전달한다
// (deliveryWithResourceIdentity). 따라서 이 principalId 에 Service Bus Data Sender 부여 필요.
resource systemTopic 'Microsoft.EventGrid/systemTopics@2024-06-01-preview' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    source: sourceStorageAccountId
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

output id string = systemTopic.id
output name string = systemTopic.name
output principalId string = systemTopic.identity.principalId