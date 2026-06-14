# `infra/modules/session-01/` — session-01 Bicep 모듈

[session-01](../../../docs/sessions/01-rag-mvp.md) 의 자원을 구성하는 10개 모듈.

| 모듈 | 역할 |
|---|---|
| [`acr.bicep`](./acr.bicep) | Azure Container Registry (Basic 등급, admin disabled) |
| [`container-apps-env.bicep`](./container-apps-env.bicep) | Azure Container Apps Environment (Log Analytics 연결) |
| [`container-app.bicep`](./container-app.bicep) | Azure Container Apps Container App (api / web 공용) |
| [`cosmos-account.bicep`](./cosmos-account.bicep) | Cosmos DB account (serverless, vector search 활성화, `disableLocalAuth=true`) |
| [`cosmos-sql-database.bicep`](./cosmos-sql-database.bicep) | Cosmos SQL database |
| [`cosmos-sql-container.bicep`](./cosmos-sql-container.bicep) | Cosmos SQL container (vector policy 포함, HNSW · 3072 차원) |
| [`key-vault-secret.bicep`](./key-vault-secret.bicep) | Key Vault Secret 등록 |
| [`role-assignment-acrpull.bicep`](./role-assignment-acrpull.bicep) | User Assigned Managed Identity 에 Azure Container Registry `AcrPull` 부여 |
| [`role-assignment-cosmos-data-contributor.bicep`](./role-assignment-cosmos-data-contributor.bicep) | User Assigned Managed Identity 에 Cosmos DB Built-in Data Contributor 부여 (data plane SQL RBAC) |
| [`role-assignment-keyvault-secrets-user.bicep`](./role-assignment-keyvault-secrets-user.bicep) | User Assigned Managed Identity 에 Key Vault Secrets User 부여 |

세션 엔트리 — `infra/sessions/01-rag-mvp/main.bicep` (후속 작성)
