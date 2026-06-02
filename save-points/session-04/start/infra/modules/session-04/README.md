# `infra/modules/session-04/` — session-04 Bicep 모듈 (후속 작성)

[session-04](../../../docs/sessions/04-async-ingestion.md) 의 비동기 인제스션 파이프라인 자원을 구성할 모듈.

예정 모듈:

- `service-bus-namespace.bicep` — Standard 등급 네임스페이스
- `service-bus-queue.bicep` — `ingest-queue` + DLQ
- `event-grid-system-topic.bicep` — Blob Storage 이벤트 토픽
- `event-grid-subscription.bicep` — Service Bus Queue 로 라우팅
- `storage-account.bicep` — `allowSharedKeyAccess=false`, OAC + RBAC
- `function-app-plan-flex.bicep` — Flex Consumption 플랜
- `function-app-flex.bicep` — Python v2, `functionAppConfig.runtime` 신 스키마
- `cosmos-lease-container.bicep` — change feed lease container (Bicep 으로 사전 생성)
- `role-assignment-servicebus-data-receiver.bicep`
- `role-assignment-eventgrid-data-sender.bicep`
- `role-assignment-storage-blob-data-reader.bicep`

세션 엔트리 — `infra/sessions/04-async-ingestion/main.bicep` (후속 작성)
