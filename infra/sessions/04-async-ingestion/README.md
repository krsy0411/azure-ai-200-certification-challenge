# S04 — 비동기 인제스션 Bicep

세션 문서: [docs/sessions/04-async-ingestion.md](../../../docs/sessions/04-async-ingestion.md)

예정 파일: `main.bicep`, `main.bicepparam`.

배포 자원: Service Bus Namespace + Queue + DLQ · Event Grid System Topic + Subscription · Storage Account (`allowSharedKeyAccess=false`, OAC+RBAC) · Function App Plan (Flex) · Function App · Cosmos lease container · 관련 RBAC.

> placeholder — 실제 Bicep 은 후속 구현 단계에서 작성.
> ⚠️ lease container 는 *Bicep 으로 사전 생성* 필수 — auto-create silent fail 함정 (`docs/pitfalls/common.md`).
