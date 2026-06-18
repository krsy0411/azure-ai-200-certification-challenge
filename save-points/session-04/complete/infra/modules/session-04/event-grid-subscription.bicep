@description('Parent Event Grid system topic name')
param systemTopicName string

@description('Event subscription name')
param name string = 'to-service-bus'

@description('대상 Service Bus 큐 자원 id')
param serviceBusQueueId string

@description('subject prefix 필터 — 지정 컨테이너 blob 만 트리거. 예: /blobServices/default/containers/documents/. 빈 값이면 전체.')
param subjectBeginsWith string = ''

resource systemTopic 'Microsoft.EventGrid/systemTopics@2024-06-01-preview' existing = {
  name: systemTopicName
}

// 시스템 토픽의 관리 ID 로 Service Bus 큐에 전달. BlobCreated 이벤트만 필터.
resource subscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2024-06-01-preview' = {
  parent: systemTopic
  name: name
  properties: {
    deliveryWithResourceIdentity: {
      identity: {
        type: 'SystemAssigned'
      }
      destination: {
        endpointType: 'ServiceBusQueue'
        properties: {
          resourceId: serviceBusQueueId
        }
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      // documents 컨테이너 blob 만 인제스션. deployments 컨테이너(함수 배포 zip 의
      // 임시 blob)까지 트리거하면 BlobNotFound 로 큐가 오염되므로 prefix 로 제한.
      subjectBeginsWith: subjectBeginsWith
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}

output id string = subscription.id