import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.clients.aoai_client import AOAIClient
from src.routers import chat, health, index_search
from src.stores.cosmos_store import CosmosSettings, CosmosStore
from src.stores.pg_store import PgSettings, PgStore


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 환경변수가 있을 때만 각 백엔드 초기화 → Phase 1~3 의 단독 실행에서도 health/chat stub 동작.
    cosmos_endpoint = os.environ.get("COSMOS_ENDPOINT")
    aoai_endpoint = os.environ.get("AOAI_ENDPOINT")
    pg_host = os.environ.get("PG_HOST")

    cosmos: CosmosStore | None = None
    aoai: AOAIClient | None = None
    pg: PgStore | None = None

    if cosmos_endpoint:
        cosmos = CosmosStore(CosmosSettings.from_env())
    if aoai_endpoint:
        aoai = AOAIClient(
            endpoint=aoai_endpoint,
            chat_deployment=os.environ.get("AOAI_DEPLOYMENT_CHAT", "gpt-4o-mini"),
            embed_deployment=os.environ.get(
                "AOAI_DEPLOYMENT_EMBED", "text-embedding-3-large"
            ),
        )
    if pg_host:
        pg = PgStore(PgSettings.from_env())
        await pg.open()

    app.state.cosmos = cosmos
    app.state.aoai = aoai
    app.state.pg = pg
    try:
        yield
    finally:
        if cosmos is not None:
            await cosmos.close()
        if aoai is not None:
            await aoai.close()
        if pg is not None:
            await pg.close()


app = FastAPI(
    title="AI-200 Challenge API",
    version="0.5.0",
    description="Enterprise RAG assistant backend (Phase 5 — Cosmos + PostgreSQL pgvector + AOAI).",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(chat.router, prefix="/api")
app.include_router(index_search.router, prefix="/api")
