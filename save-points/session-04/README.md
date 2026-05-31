# save-points/session-04/ — 비동기 인제스션 (Service Bus + Event Grid + Azure Functions)

예정 스냅샷 — `start/` 와 `complete/` 의 차이는 다음 파일들의 핵심 로직.

- `infra/sessions/04-async-ingestion/main.bicep`
- `apps/functions/function_app.py` — Service Bus queue trigger 본문 + Cosmos change feed trigger 본문이 anchor 주석
- `apps/functions/requirements.txt` — 완성본 그대로

세션 docs — [docs/sessions/04-async-ingestion.md](../../docs/sessions/04-async-ingestion.md)
