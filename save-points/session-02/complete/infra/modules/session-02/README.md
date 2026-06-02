# `infra/modules/session-02/` — session-02 Bicep 모듈 (후속 작성)

[session-02](../../../docs/sessions/02-pgvector.md) 의 PostgreSQL pgvector 자원을 구성할 모듈.

예정 모듈:

- `postgres-flexible-server.bicep` — Burstable B1ms 등급, Entra ID 전용 인증
- `postgres-database.bicep` — `appdb` 데이터베이스
- `postgres-server-config.bicep` — `azure.extensions=VECTOR` 사전 허용
- `postgres-firewall-rule.bicep` — 본인 PC IP 허용
- `postgres-aad-admin.bicep` — 본인 Entra ID 사용자를 admin 으로

세션 엔트리 — `infra/sessions/02-pgvector/main.bicep` (후속 작성)
