"""FastAPI 엔트리 — RAG 파이프라인을 HTTP 로 노출.

엔드포인트:
- `GET /healthz` — Azure Container Apps liveness/readiness probe
- `POST /api/chat` — 사용자 질문 → 답변 + 출처

부팅 시점에 `azure-monitor-opentelemetry` 자동 계측을 활성화한다:
- 인입 HTTP (FastAPI), 외부 HTTP (Azure OpenAI · Cosmos) 가 trace 로 기록됨
- session-06 에서 비즈니스 의미가 담긴 커스텀 span 이 추가된다.

자동 계측은 FastAPI app 인스턴스가 만들어지기 전에 켜야 한다. configure_azure_monitor 가
app 생성 후(lifespan)에 호출되면, FastAPI 자동 계측이 이미 만들어진 app 에 적용되지 않아
요청 span 이 기록되지 않는다. 따라서 아래 계측 블록은 import 최상단에 두며 완성되어 제공된다.
학습자는 lifespan 의 클라이언트 초기화와 /api/chat 본문을 채운다.
"""

import os

from azure.monitor.opentelemetry import configure_azure_monitor

if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    # connection string 은 환경변수에서 자동으로 읽는다.
    configure_azure_monitor()
    # azure-monitor-opentelemetry 가 자동 활성화하지 않는 async HTTP 클라이언트 계측을
    # 명시적으로 켜, Azure OpenAI(httpx) · Cosmos(aiohttp) 호출이 dependency span 으로 남게 한다.
    from opentelemetry.instrumentation.aiohttp_client import AioHttpClientInstrumentor
    from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

    HTTPXClientInstrumentor().instrument()
    AioHttpClientInstrumentor().instrument()

from contextlib import asynccontextmanager  # noqa: E402

from fastapi import FastAPI, HTTPException  # noqa: E402

from .clients.aoai import build_aoai_client  # noqa: E402
from .models import ChatRequest, ChatResponse  # noqa: E402
from .rag.chain import run_rag_chain  # noqa: E402
from .settings import get_settings  # noqa: E402
from .stores.cosmos_store import build_cosmos_client, get_chunks_container  # noqa: E402


@asynccontextmanager
async def lifespan(app: FastAPI):
    """앱 시작 시점에 Azure 클라이언트 초기화, 종료 시 정리.

    클라이언트는 `app.state` 에 보관해 요청 핸들러가 가져다 쓴다.
    """
    settings = get_settings()

    aoai_client = build_aoai_client(settings)
    cosmos_client, cosmos_credential = build_cosmos_client(settings)
    cosmos_container = await get_chunks_container(cosmos_client, settings)

    app.state.settings = settings
    app.state.aoai_client = aoai_client
    app.state.cosmos_client = cosmos_client
    app.state.cosmos_credential = cosmos_credential
    app.state.cosmos_container = cosmos_container

    try:
        yield
    finally:
        # 종료 시점 정리 — 토큰 갱신 백그라운드 스레드 등을 안전하게 종료
        await aoai_client.close()
        await cosmos_client.close()
        await cosmos_credential.close()


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
    2. Cosmos DB 벡터 검색으로 chunk top-k 검색
    3. 검색된 chunk 본문을 컨텍스트로 묶어 gpt-5-mini 호출
    """
    try:
        return await run_rag_chain(
            question=request.q,
            aoai_client=app.state.aoai_client,
            cosmos_container=app.state.cosmos_container,
            settings=app.state.settings,
        )
    except Exception as exc:
        # 운영 환경에서는 더 정교한 에러 분류와 재시도 정책이 필요하다.
        # 학습 단계에서는 500 으로 묶고 OpenTelemetry exception 으로 기록.
        raise HTTPException(status_code=500, detail=f"RAG pipeline failed: {exc}") from exc
