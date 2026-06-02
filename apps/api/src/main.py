"""FastAPI 엔트리 — RAG 파이프라인을 HTTP 로 노출.

엔드포인트:
- `GET /healthz` — Azure Container Apps liveness/readiness probe
- `POST /api/chat` — 사용자 질문 → 답변 + 출처

부팅 시점에 `azure-monitor-opentelemetry` 자동 계측을 활성화한다:
- 인입 HTTP, 외부 HTTP (Azure OpenAI 등), Cosmos SDK 호출이 trace 로 기록됨
- session-06 에서 비즈니스 의미가 담긴 커스텀 span 이 추가된다.
"""

from contextlib import asynccontextmanager

from azure.monitor.opentelemetry import configure_azure_monitor
from fastapi import FastAPI, HTTPException

from .clients.aoai import build_aoai_client
from .models import ChatRequest, ChatResponse
from .rag.chain import run_rag_chain
from .settings import get_settings
from .stores.base import VectorStore
from .stores.cosmos_store import build_cosmos_store
from .stores.pg_store import build_pg_store


async def build_store(settings) -> VectorStore:
    """STORE_BACKEND 환경변수에 따라 벡터 스토어를 선택해 만든다."""
    if settings.store_backend == "pg":
        return await build_pg_store(settings)
    return build_cosmos_store(settings)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """앱 시작 시점에 Azure 클라이언트 초기화, 종료 시 정리.

    클라이언트는 `app.state` 에 보관해 요청 핸들러가 가져다 쓴다.
    """
    settings = get_settings()

    # Azure Monitor + OpenTelemetry 자동 계측 활성화.
    # APPLICATIONINSIGHTS_CONNECTION_STRING 환경변수가 설정되어 있을 때만 동작.
    if settings.applicationinsights_connection_string:
        configure_azure_monitor(
            connection_string=settings.applicationinsights_connection_string,
        )

    aoai_client = build_aoai_client(settings)
    store = await build_store(settings)

    app.state.settings = settings
    app.state.aoai_client = aoai_client
    app.state.store = store

    try:
        yield
    finally:
        # 종료 시점 정리 — 토큰 갱신 백그라운드 스레드 · 연결 풀을 안전하게 종료
        await aoai_client.close()
        await store.close()


app = FastAPI(
    title="AI-200 Workshop — RAG MVP",
    description="사내 문서 RAG 지식 비서 (Azure Container Apps + Key Vault + OpenTelemetry)",
    version="0.1.0",
    lifespan=lifespan,
)


@app.get("/healthz")
async def healthz() -> dict[str, bool]:
    """Azure Container Apps probe 용 — 의존 자원 호출 없이 200 응답."""
    return {"ok": True}


@app.post("/api/chat", response_model=ChatResponse)
async def chat(request: ChatRequest) -> ChatResponse:
    """RAG 파이프라인을 통해 답변 생성.

    1. 질문 임베딩
    2. 선택된 벡터 스토어 (Cosmos DB 또는 PostgreSQL pgvector) 로 chunk top-k 검색
    3. 검색된 chunk 본문을 컨텍스트로 묶어 gpt-4o-mini 호출
    """
    try:
        return await run_rag_chain(
            question=request.q,
            aoai_client=app.state.aoai_client,
            store=app.state.store,
            settings=app.state.settings,
        )
    except Exception as exc:
        # 운영 환경에서는 더 정교한 에러 분류와 재시도 정책이 필요하다.
        # 학습 단계에서는 500 으로 묶고 OpenTelemetry exception 으로 기록.
        raise HTTPException(status_code=500, detail=f"RAG pipeline failed: {exc}") from exc
