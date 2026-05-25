# `apps/functions/` — Azure Functions (S04 이후)

비동기 인제스션 파이프라인.

예정 파일:
- `function_app.py` (Python v2 데코레이터 스타일)
  - `on_ingest_message` — Service Bus queue trigger → Blob 다운로드 → 청크 분할 → AOAI embed → Cosmos + PG upsert
  - `on_cosmos_change` — Cosmos change feed trigger → 다운스트림 통계 업데이트
- `host.json`
- `requirements.txt` (`azure-functions`, `azure-identity`, `azure-storage-blob`, `azure-cosmos`, `openai`, `psycopg[binary]`, `pgvector`)
- `local.settings.json` (gitignored)

> placeholder — 실제 코드는 후속 구현 단계.
> ⚠️ Flex Consumption 신 스키마. 환경변수 `FUNCTIONS_WORKER_RUNTIME` 사용하지 않음 (`docs/pitfalls/common.md`).
