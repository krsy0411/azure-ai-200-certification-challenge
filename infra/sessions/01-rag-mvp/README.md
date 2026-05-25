# S01 — RAG MVP Bicep

세션 문서: [docs/sessions/01-rag-mvp.md](../../../docs/sessions/01-rag-mvp.md)

예정 파일:
- `main.bicep` — resource group scope
- `main.bicepparam`

배포되는 자원: ACR · ACA Env · ACA `ca-api` + `ca-web` · Cosmos account · DB · container (vector policy) · KV secret · UAMI 3개 역할 부여 (`AcrPull`, `Cosmos Data Contributor`, `Key Vault Secrets User`).

> placeholder — 실제 Bicep 은 후속 구현 단계에서 작성.
