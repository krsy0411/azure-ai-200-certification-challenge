# `infra/modules/` — 공유 Bicep 모듈

각 세션 (`infra/sessions/0N-*/main.bicep`) 이 조립하는 *재사용 가능한* Bicep 모듈입니다. 본 디렉터리의 모듈은 **세션 간 공유** 됩니다.

> 본 디렉터리는 워크샵 구조 단계의 placeholder 입니다. 실제 `*.bicep` 파일은 후속 구현 단계에서 작성됩니다.

## 예정된 모듈 목록 (세션별)

### S00 — 사전 설정
- `resource-group.bicep`
- `log-analytics.bicep`
- `application-insights.bicep`
- `key-vault.bicep`
- `user-assigned-identity.bicep`
- `aoai-account.bicep`
- `aoai-deployment.bicep`
- `role-assignment-aoai-user.bicep`

### S01 — RAG MVP
- `acr.bicep`
- `container-apps-env.bicep`
- `container-app.bicep`
- `cosmos-account.bicep`
- `cosmos-sql-database.bicep`
- `cosmos-sql-container.bicep`
- `key-vault-secret.bicep`
- `role-assignment-acrpull.bicep`
- `role-assignment-cosmos-data-contributor.bicep`
- `role-assignment-keyvault-secrets-user.bicep`

### S02 — pgvector
- `postgres-flexible-server.bicep`
- `postgres-database.bicep`
- `postgres-server-config.bicep`
- `postgres-firewall-rule.bicep`
- `postgres-aad-admin.bicep`

### S03 — Managed Redis
- `redis-enterprise.bicep`
- `redis-enterprise-database.bicep`
- `redis-access-policy-assignment.bicep`

### S04 — 비동기 인제스션
- `service-bus-namespace.bicep`
- `service-bus-queue.bicep`
- `event-grid-system-topic.bicep`
- `event-grid-subscription.bicep`
- `storage-account.bicep`
- `function-app-plan-flex.bicep`
- `function-app-flex.bicep`
- `cosmos-lease-container.bicep`
- `role-assignment-servicebus-data-receiver.bicep`
- `role-assignment-eventgrid-data-sender.bicep`
- `role-assignment-storage-blob-data-reader.bicep`

### S05 — App Configuration
- `app-configuration.bicep`
- `app-configuration-keyvalue.bicep`
- `app-configuration-keyvault-ref.bicep`
- `app-configuration-feature-flag.bicep`
- `role-assignment-appconfig-data-reader.bicep`

### S06 — Observability 심화
- `monitor-workbook.bicep`
- `monitor-action-group.bicep`
- `monitor-metric-alert.bicep`

### S07 — AKS
- `aks-cluster.bicep`
- `aks-container-insights-dcr.bicep`
- `aks-container-insights-dcra.bicep`
- `role-assignment-aks-acr-pull.bicep`

## 모듈 작성 규칙

1. **하나의 모듈은 하나의 리소스 종류** (또는 그 종속 sub-resource)
2. **사용자 식별 정보는 파라미터로** — `bicepparam` 기본값에 박지 말 것 (`docs/pitfalls/common.md` 참고)
3. **시크릿 출력 시 `@secure()`** 데코레이터 사용
4. **명명 규칙** — `<리소스약어>-ai200ws-<env>` (`docs/architecture.md` 참고)
5. **role assignment 는 별도 모듈** — 가독성 + 재사용 + `dependsOn` 직렬화 용이
