# save-points/session-02/ — PostgreSQL pgvector 비교

예정 스냅샷 — `start/` 와 `complete/` 의 차이는 다음 파일들의 핵심 로직.

- `infra/sessions/02-pgvector/main.bicep`
- `apps/api/src/stores/pg_store.py` — psycopg async + psycopg_pool + register_vector_async 호출 부분이 anchor 주석
- `scripts/seed_both.py` — Cosmos vs PostgreSQL 적재 / 비교 로직이 anchor 주석

세션 docs — [docs/sessions/02-pgvector.md](../../docs/sessions/02-pgvector.md)
