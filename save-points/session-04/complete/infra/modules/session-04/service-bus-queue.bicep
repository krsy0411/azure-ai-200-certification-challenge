@description('Parent Service Bus namespace name')
param namespaceName string

@description('Queue name')
param name string = 'ingest-queue'

@description('최대 전달 시도 횟수 — 초과 시 메시지가 DLQ 로 이동')
param maxDeliveryCount int = 5

resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: namespaceName
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: namespace
  name: name
  properties: {
    maxDeliveryCount: maxDeliveryCount
    // DLQ — 만료·최대 전달 초과 메시지를 ingest-queue/$DeadLetterQueue 로 격리
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT5M'
    defaultMessageTimeToLive: 'P14D'
  }
}

output name string = queue.name