# `scripts/` — 헬퍼 스크립트

제공 스크립트:

- `check_redis.py` (S03) — Managed Redis 캐시 내용 확인 (읽기 전용). 표준 라이브러리만으로 Entra 토큰을 받아 접속, `FT._LIST`·`FT.INFO`·`KEYS rag:*`·`TTL` 출력. redis-cli 설치 불필요. 실행: `python scripts/check_redis.py`
- `seed_both.py` (S02) — 동일 문서 셋을 Cosmos · PG 양쪽에 임베드+적재. 동일 쿼리의 P50/P95 latency 비교 표 출력

예정 스크립트:
- `verify_session_NN.sh` (각 세션) — 세션 종료 시 자동 검증 (`curl` + `az` + `jq`). "끝났습니까?" 를 강사가 묻지 않게
- `cleanup-session.sh` — 세션별 자원 정리 ([docs/cleanup.md](../docs/cleanup.md) 참고)

> placeholder — 실제 스크립트는 후속 구현 단계.
