# save-points/session-01/ — RAG MVP on Azure Container Apps + Key Vault + OpenTelemetry

예정 스냅샷:

- `start/infra/sessions/01-rag-mvp/main.bicep` — 모듈 호출 부분이 한국어 anchor 주석으로 비어 있는 시작본
- `start/apps/api/Dockerfile`, `pyproject.toml` — 완성본 그대로
- `start/apps/api/src/main.py` — FastAPI 앱 골격만, 핵심 의존성 주입 · `/api/chat` 본문은 anchor 주석
- `start/apps/api/src/clients/aoai.py` — DefaultAzureCredential + AzureOpenAI 클라이언트 생성 함수의 본문이 anchor 주석
- `start/apps/api/src/stores/cosmos_store.py` — CosmosClient 초기화와 vector search 본문이 anchor 주석
- `start/apps/api/src/rag/chain.py` — embed → 검색 → chat 조합 본문이 anchor 주석
- `start/apps/web/...` — Next.js 챗 UI 의 fetch 호출 본문이 anchor 주석

`complete/` — main 트리의 위 파일과 동일.

세션 docs — [docs/sessions/01-rag-mvp.md](../../docs/sessions/01-rag-mvp.md)
