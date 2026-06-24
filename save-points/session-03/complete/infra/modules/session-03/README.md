# `infra/modules/session-03/` — session-03 Bicep 모듈 (후속 작성)

[session-03](../../../docs/sessions/03-redis-cache.md) 의 Managed Redis 시맨틱 캐시 자원을 구성할 모듈.

예정 모듈:

- `redis-enterprise.bicep` — Balanced_B0 클러스터 (최소 등급)
- `redis-enterprise-database.bicep` — RediSearch 모듈 포함, `evictionPolicy=NoEviction`
- `redis-access-policy-assignment.bicep` — User Assigned Managed Identity 의 `principalId` 부여

세션 엔트리 — `infra/sessions/03-redis-cache/main.bicep` (후속 작성)
