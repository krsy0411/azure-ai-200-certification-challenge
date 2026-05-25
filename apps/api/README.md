# `apps/api/` — FastAPI 백엔드

세션별 점진 확장:

| 세션 | 추가되는 코드 |
|---|---|
| S01 | `src/main.py` (/api/chat), `src/stores/cosmos_store.py`, `src/rag/chain.py` |
| S02 | `src/stores/pg_store.py`, env 기반 backend 선택 |
| S03 | `src/cache/redis_client.py`, `src/cache/semantic.py` |
| S05 | `src/config/loader.py` (App Configuration provider) |
| S06 | `src/observability/spans.py` (커스텀 OTel span) |

예정 파일:
- `Dockerfile` (Python 3.12-slim, `--platform linux/amd64` 안전)
- `pyproject.toml` 또는 `requirements.txt`
- `src/main.py` (FastAPI app)

> placeholder — 실제 코드는 후속 구현 단계에서 작성. 세션 docs 의 코드 스니펫 placeholder 를 그대로 옮겨오는 작업.
