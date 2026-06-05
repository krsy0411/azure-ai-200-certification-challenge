# `infra/modules/session-07/` — session-07 Bicep 모듈 (후속 작성)

[session-07](../../../docs/sessions/07-aks.md) 의 Azure Kubernetes Service 자원을 구성할 모듈.

예정 모듈:

- `aks-cluster.bicep` — Standard_D2s_v3 × 2 노드, control plane UserAssigned identity, kubelet UserAssigned identity, Entra ID + Azure RBAC, `disableLocalAccounts=true`
- `aks-container-insights-dcr.bicep` — Data Collection Rule (KubeMonAgent, KubePodInventory 등)
- `aks-container-insights-dcra.bicep` — Data Collection Rule Association (Azure Kubernetes Service ↔ DCR)
- `role-assignment-aks-acr-pull.bicep` — kubelet User Assigned Managed Identity 에 `AcrPull` 부여

세션 엔트리 — `infra/sessions/07-aks/main.bicep` (후속 작성)
