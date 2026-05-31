# save-points/session-06/ — Observability 심화

예정 스냅샷 — `start/` 와 `complete/` 의 차이는 다음 파일들의 핵심 로직.

- `infra/sessions/06-observability/main.bicep`
- `apps/api/src/observability/spans.py` — `@rag_span` 데코레이터 + custom attribute (`retrieval.count`, `tokens.prompt`, `tokens.completion`, `cache_hit`) 본문이 anchor 주석
- `apps/api/src/main.py` — `/api/chat` 안에 span context 추가 부분 + `/api/_chaos` 엔드포인트가 anchor 주석

세션 docs — [docs/sessions/06-observability.md](../../docs/sessions/06-observability.md)
