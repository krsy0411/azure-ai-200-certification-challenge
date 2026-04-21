# apps/api — FastAPI Backend

Python 3.12 · FastAPI · `uv` 패키지 매니저.

## Phase 1 엔드포인트

| Method | Path | 설명 |
|---|---|---|
| GET | `/healthz` | 헬스체크(`{"status":"ok"}`) |
| POST | `/api/chat` | 메시지 에코 stub (Phase 4+에서 RAG 통합) |

## 로컬 실행

```bash
# 의존성 설치
uv sync

# 개발 서버 실행 (reload 포함)
uv run uvicorn src.main:app --reload --port 8000

# 스모크 테스트
curl http://localhost:8000/healthz
curl -X POST http://localhost:8000/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"hello"}'
```

## 컨테이너 빌드

```bash
# 레포 루트에서
docker build -t ai200challenge-api:0.1.0 apps/api
docker run --rm -p 8000:8000 ai200challenge-api:0.1.0
```

## 구조 (현재)

```
apps/api/
├── pyproject.toml
├── Dockerfile
├── .dockerignore
├── .env.example
└── src/
    ├── __init__.py
    ├── main.py
    └── routers/
        ├── __init__.py
        ├── health.py
        └── chat.py
```

Phase 진행에 따라 `src/services/`, `src/stores/`, `src/messaging/`, `src/config/`, `src/telemetry/`가 추가됩니다.
