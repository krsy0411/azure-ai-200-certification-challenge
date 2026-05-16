import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.cache.redis_client import RedisClient, RedisSettings
from src.cache.semantic import SemanticCache, SemanticCacheSettings
from src.clients.aoai_client import AOAIClient
from src.messaging.pubsub import PubSubPublisher
from src.routers import chat, health, index_search
from src.stores.cosmos_store import CosmosSettings, CosmosStore
from src.stores.pg_store import PgSettings, PgStore


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 환경변수가 있을 때만 각 백엔드 초기화 → Phase 1~3 의 단독 실행에서도 health/chat stub 동작.
    cosmos_endpoint = os.environ.get("COSMOS_ENDPOINT")
    aoai_endpoint = os.environ.get("AOAI_ENDPOINT")
    pg_host = os.environ.get("PG_HOST")
    redis_host = os.environ.get("REDIS_HOST")

    cosmos: CosmosStore | None = None
    aoai: AOAIClient | None = None
    pg: PgStore | None = None
    redis_client: RedisClient | None = None
    semantic_cache: SemanticCache | None = None
    pubsub: PubSubPublisher | None = None

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
    if redis_host:
        redis_client = RedisClient(RedisSettings.from_env())
        await redis_client.open()
        semantic_cache = SemanticCache(redis_client, SemanticCacheSettings.from_env())
        await semantic_cache.ensure_index()
        pubsub = PubSubPublisher(redis_client)

    app.state.cosmos = cosmos
    app.state.aoai = aoai
    app.state.pg = pg
    app.state.redis = redis_client
    app.state.semantic_cache = semantic_cache
    app.state.pubsub = pubsub
    try:
        yield
    finally:
        if cosmos is not None:
            await cosmos.close()
        if aoai is not None:
            await aoai.close()
        if pg is not None:
            await pg.close()
        if redis_client is not None:
            await redis_client.close()


app = FastAPI(
    title="AI-200 Challenge API",
    version="0.6.3",
    description=(
        "Enterprise RAG assistant backend "
        "(Phase 6 — + Azure Managed Redis 시맨틱 캐시 + pub/sub + chat.py RAG)."
    ),
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
