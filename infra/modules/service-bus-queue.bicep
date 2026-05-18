// Service Bus queue — peek-lock + DLQ (max delivery 5)
//
// 학습 경로 모듈 1 단원 5 (안정적 처리) 매핑:
// - maxDeliveryCount=5 — 5회 abandon 후 자동 DLQ 이동
// - lockDuration=PT1M (default) — peek-lock 동안 다른 receiver 차단
// - requiresSession=false — 임베딩 작업은 stateless
// - deadLetteringOnMessageExpiration=true — TTL 만료 메시지도 DLQ 로

@description('상위 Service Bus namespace 이름')
param namespaceName string

@description('큐 이름')
@minLength(1)
@maxLength(260)
param queueName string

@description('peek-lock duration (ISO 8601, 최대 PT5M)')
param lockDuration string = 'PT1M'

@description('max delivery count — 초과 시 DLQ 이동')
@minValue(1)
param maxDeliveryCount int = 5

@description('message TTL (ISO 8601). default P14D')
param defaultMessageTimeToLive string = 'P14D'

resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: namespaceName
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: namespace
  name: queueName
  properties: {
    lockDuration: lockDuration
    maxDeliveryCount: maxDeliveryCount
    defaultMessageTimeToLive: defaultMessageTimeToLive
    deadLetteringOnMessageExpiration: true
    requiresSession: false
    requiresDuplicateDetection: false
    enableBatchedOperations: true
    enablePartitioning: false
    status: 'Active'
  }
}

output id string = queue.id
output name string = queue.name
