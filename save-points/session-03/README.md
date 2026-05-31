# save-points/session-03/ — Managed Redis 시맨틱 캐시

예정 스냅샷 — `start/` 와 `complete/` 의 차이는 다음 파일들의 핵심 로직.

- `infra/sessions/03-redis-cache/main.bicep`
- `apps/api/src/cache/redis_client.py` — Entra ID 토큰을 비밀번호로 쓰는 redis-py 클라이언트 생성 본문이 anchor 주석
- `apps/api/src/cache/semantic.py` — RediSearch 벡터 인덱스 생성 · KNN 조회 · TTL 저장 본문이 anchor 주석

세션 docs — [docs/sessions/03-redis-cache.md](../../docs/sessions/03-redis-cache.md)
