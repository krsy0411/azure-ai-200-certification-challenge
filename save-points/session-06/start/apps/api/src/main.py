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

from .cache.semantic import SemanticCache, build_semantic_cache
from .clients.aoai import build_aoai_client
from .config.loader import AppConfig, load_app_config
from .models import ChatRequest, ChatResponse
from .rag.chain import run_rag_chain
from .settings import get_settings
from .stores.base import VectorStore
from .stores.cosmos_store import build_cosmos_store
from .stores.pg_store import build_pg_store


async def build_store(settings, backend: str) -> VectorStore:
    """선택된 백엔드로 벡터 스토어를 만든다 (cosmos | pg)."""
    if backend == "pg":
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

    # App Configuration — 설정되면 피처 플래그로 동작을 제어 (session-05).
    app_config: AppConfig | None = None
    if settings.app_config_endpoint:
        app_config = await load_app_config(settings)

    # 백엔드 선택 — enable_pg_backend 플래그가 있으면 그 값을, 없으면 환경변수를 따른다.
    # (백엔드 전환은 시작 시 1회 — 캐시 토글과 달리 런타임 전환은 재시작 필요)
    backend = settings.store_backend
    if app_config is not None and app_config.is_enabled("enable_pg_backend"):
        backend = "pg"
    store = await build_store(settings, backend)

    # 시맨틱 캐시 — Redis 가 구성돼 있으면 객체를 만들어 둔다. 실제 사용 여부는
    # 요청마다 enable_semantic_cache 플래그로 결정 (App Configuration 없으면 cache_enabled).
    cache: SemanticCache | None = None
    if settings.redis_host and (settings.cache_enabled or app_config is not None):
        cache = await build_semantic_cache(settings)

    app.state.settings = settings
    app.state.aoai_client = aoai_client
    app.state.store = store
    app.state.cache = cache
    app.state.app_config = app_config

    try:
        yield
    finally:
        # 종료 시점 정리 — 토큰 갱신 백그라운드 스레드 · 연결 풀을 안전하게 종료
        await aoai_client.close()
        await store.close()
        if cache is not None:
            await cache.close()
        if app_config is not None:
            await app_config.close()


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


@app.post("/api/_chaos")
async def chaos() -> None:
    """의도적으로 500 을 반환해 오류율·알림(session-06)을 검증한다."""
    raise HTTPException(status_code=500, detail="intentional chaos")


@app.post("/api/chat", response_model=ChatResponse)
async def chat(request: ChatRequest) -> ChatResponse:
    """RAG 파이프라인을 통해 답변 생성.

    1. 질문 임베딩
    2. 선택된 벡터 스토어 (Cosmos DB 또는 PostgreSQL pgvector) 로 chunk top-k 검색
    3. 검색된 chunk 본문을 컨텍스트로 묶어 gpt-4o-mini 호출

    시맨틱 캐시 사용 여부는 App Configuration 의 enable_semantic_cache 플래그로 매 요청
    평가한다 (포털 토글이 30~60초 안에 반영). App Configuration 이 없으면 시작 시 구성을 따른다.
    """
    cache = app.state.cache
    app_config: AppConfig | None = app.state.app_config
    if app_config is not None:
        # 폴링 주기에 맞춰 플래그 변경을 반영한 뒤 평가
        await app_config.refresh()
        if not app_config.is_enabled("enable_semantic_cache"):
            cache = None

    try:
        return await run_rag_chain(
            question=request.q,
            aoai_client=app.state.aoai_client,
            store=app.state.store,
            settings=app.state.settings,
            cache=cache,
        )
    except Exception as exc:
        # 운영 환경에서는 더 정교한 에러 분류와 재시도 정책이 필요하다.
        # 학습 단계에서는 500 으로 묶고 OpenTelemetry exception 으로 기록.
        raise HTTPException(status_code=500, detail=f"RAG pipeline failed: {exc}") from exc
