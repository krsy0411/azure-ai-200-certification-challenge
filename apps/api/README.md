# apps/api — FastAPI Backend

Python 3.12 기반의 RAG 백엔드. Phase 1에서 스캐폴딩 예정.

## 계획된 모듈 구조 (Phase 진행에 따라 생성)

```
apps/api/
├── pyproject.toml             # uv/poetry
├── Dockerfile                 # 멀티스테이지
├── src/
│   ├── main.py                # FastAPI 진입점
│   ├── routers/
│   │   ├── health.py
│   │   ├── chat.py
│   │   └── documents.py
│   ├── services/
│   │   ├── rag.py             # RAG 오케스트레이션
│   │   └── openai_client.py   # Azure OpenAI 래퍼
│   ├── stores/
│   │   ├── cosmos_store.py    # Phase 4
│   │   ├── pg_store.py        # Phase 5
│   │   └── redis_semantic.py  # Phase 6
│   ├── messaging/
│   │   ├── service_bus.py     # Phase 7
│   │   └── event_grid.py      # Phase 7
│   ├── config/
│   │   └── azure_config.py    # Phase 8
│   └── telemetry/
│       └── otel.py            # Phase 9
└── tests/
```

## 로컬 실행 (Phase 1 이후)

```bash
# 추후 추가 예정
uv sync
uv run uvicorn src.main:app --reload --port 8000
```
