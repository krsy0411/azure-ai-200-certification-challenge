# S07 — AKS Bicep

세션 문서: [docs/sessions/07-aks.md](../../../docs/sessions/07-aks.md)

예정 파일:
- `main.bicep`, `main.bicepparam`
- `manifests/worker-job.yaml` — K8s Job 매니페스트

배포 자원: AKS 클러스터 (DSv3 × 2, control plane UAMI, kubelet UAMI, Entra ID + Azure RBAC, `disableLocalAccounts=true`) · Container Insights (DCR + DCRA 명시) · ACR Pull RBAC.

> placeholder — 실제 Bicep 은 후속 구현 단계에서 작성.
> ⚠️ DCR + DCRA 누락 함정 (`docs/pitfalls/common.md`) — 반드시 둘 다 명시.
> 💰 비용 경고: AKS LB + Public IP idle ≈ ₩1,125/일.
