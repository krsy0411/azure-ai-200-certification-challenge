# `infra/modules/` — 세션별 Bicep 모듈

각 세션 (`infra/sessions/NN-*/main.bicep`) 이 조립하는 재사용 가능한 Bicep 모듈입니다. **세션별 폴더로 분리** 되어 있어 각 모듈이 어느 세션의 자원 구성에 속하는지 파일 시스템 수준에서 명확합니다.

## 디렉터리 구조

```
infra/modules/
├── session-00/   # 사전 설정 — RG · Log Analytics · App Insights · Key Vault · UAMI · Azure OpenAI
├── session-01/   # RAG MVP — ACR · ACA · Cosmos DB (vector)
├── session-02/   # PostgreSQL pgvector (후속 작성)
├── session-03/   # Managed Redis 시맨틱 캐시 (후속 작성)
├── session-04/   # 비동기 인제스션 (후속 작성)
├── session-05/   # App Configuration (후속 작성)
├── session-06/   # Observability 심화 (후속 작성)
└── session-07/   # Azure Kubernetes Service (후속 작성)
```

> [!NOTE]
> 두 개 이상의 세션이 같은 모듈을 실제로 호출하는 시점에 `modules/common/` 으로 승격합니다. 현재는 추정 없이 세션별로만 분리합니다.

## session-00 — 사전 설정 (배포 완료)

[infra/modules/session-00/](./session-00/)

- `resource-group.bicep` — Resource Group (subscription scope)
- `log-analytics.bicep` — Log Analytics Workspace
- `application-insights.bicep` — Application Insights (workspace-based)
- `key-vault.bicep` — Key Vault (RBAC-only)
- `user-assigned-identity.bicep` — 공용 User Assigned Managed Identity
- `aoai-account.bicep` — Azure OpenAI account (`disableLocalAuth=true`)
- `aoai-deployment.bicep` — Azure OpenAI 모델 deployment (chat / embedding 공용)
- `role-assignment-aoai-user.bicep` — Cognitive Services OpenAI User 역할 부여

## session-01 — RAG MVP (배포 완료)

[infra/modules/session-01/](./session-01/)

- `acr.bicep` — Azure Container Registry (Basic, admin disabled)
- `container-apps-env.bicep` — Azure Container Apps Environment (Log Analytics 연결)
- `container-app.bicep` — Azure Container Apps Container App (api / web 공용)
- `cosmos-account.bicep` — Cosmos DB account (serverless, vector search 활성화)
- `cosmos-sql-database.bicep` — Cosmos SQL database
- `cosmos-sql-container.bicep` — Cosmos SQL container (vector policy 포함)
- `key-vault-secret.bicep` — Key Vault Secret 등록
- `role-assignment-acrpull.bicep` — Azure Container Registry pull 권한
- `role-assignment-cosmos-data-contributor.bicep` — Cosmos DB data plane RBAC
- `role-assignment-keyvault-secrets-user.bicep` — Key Vault Secrets 읽기 권한

## session-02 ~ session-07

후속 구현 단계에서 작성됩니다. 각 세션 폴더에 placeholder 가 들어 있습니다.

## 모듈 작성 규칙

1. **하나의 모듈은 하나의 리소스 종류** (또는 그 종속 sub-resource)
2. **사용자 식별 정보는 파라미터로** — `bicepparam` 기본값에 작성해두지 않습니다 (`docs/pitfalls/common.md` 참고)
3. **시크릿 출력 시 `@secure()`** 데코레이터 사용
4. **명명 규칙** — `<리소스약어>-ai200ws-<env>` ([docs/architecture.md](../../docs/architecture.md) 참고)
5. **역할 할당은 별도 모듈** — 가독성 + 재사용 + `dependsOn` 직렬화 용이
