# `infra/modules/session-00/` — session-00 Bicep 모듈

[session-00](../../../docs/sessions/00-setup.md) 의 자원을 구성하는 8개 모듈.

| 모듈 | 역할 |
|---|---|
| [`resource-group.bicep`](./resource-group.bicep) | Resource Group (subscription scope 에서 작성) |
| [`log-analytics.bicep`](./log-analytics.bicep) | Log Analytics Workspace |
| [`application-insights.bicep`](./application-insights.bicep) | Application Insights (workspace-based) |
| [`key-vault.bicep`](./key-vault.bicep) | Key Vault (RBAC-only · purge protection) |
| [`user-assigned-identity.bicep`](./user-assigned-identity.bicep) | 공용 User Assigned Managed Identity |
| [`aoai-account.bicep`](./aoai-account.bicep) | Azure OpenAI account (`disableLocalAuth=true`) |
| [`aoai-deployment.bicep`](./aoai-deployment.bicep) | Azure OpenAI 모델 deployment (chat · embedding 공용) |
| [`role-assignment-aoai-user.bicep`](./role-assignment-aoai-user.bicep) | Cognitive Services OpenAI User 역할 부여 |

세션 엔트리 — [`infra/sessions/00-setup/main.bicep`](../../sessions/00-setup/main.bicep)
