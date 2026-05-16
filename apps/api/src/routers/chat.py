"""
Chat 라우터 — RAG 파이프라인 (Phase 6).

흐름:
    (1) 질문 임베딩 (AOAI text-embedding-3-large)
    (2) Redis 시맨틱 캐시 lookup (KNN 1, similarity ≥ threshold + workspace 일치)
        - 히트  → 캐시 답변 반환 (model=cache)
        - 미스 → 다음 단계
    (3) PostgreSQL pgvector (chunks_hnsw) top-K 검색
    (4) AOAI gpt-4o-mini 답변 생성 (검색 context 를 system prompt 에 주입)
    (5) Redis HSET + EXPIRE + PUBLISH ws:<ws>:events 'cache:store'

학습 경로 'enhance-ai-solutions-azure-managed-redis' 모듈 3 단원 5 (의미 체계 검색 연습)
의 응용 + 모듈 1 단원 4 (캐시 배제 패턴 = read-through).

캐시 의존 자원이 미설치된 환경 (Phase 1~3 단독) 에서는 stub 으로 폴백.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from src.cache.semantic import CacheHit
from src.messaging.pubsub import PubSubPublisher

logger = logging.getLogger(__name__)

router = APIRouter()


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    workspace_id: str | None = None
    top_k: int = Field(default=5, ge=1, le=20)


class ChatResponse(BaseModel):
    reply: str
    model: str
    cache_hit: bool = False
    similarity: float | None = None
    sources: list[dict] = Field(default_factory=list)


_SYSTEM_PROMPT = (
    "당신은 워크스페이스 문서를 기반으로 답하는 전문 비서입니다. "
    "아래 컨텍스트만 사용해 한국어로 간결히 답하세요. "
    "컨텍스트에 답이 없으면 모른다고 말하세요."
)


@router.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest, request: Request) -> ChatResponse:
    aoai = request.app.state.aoai
    pg = request.app.state.pg
    redis_cache = getattr(request.app.state, "semantic_cache", None)
    pubsub: PubSubPublisher | None = getattr(request.app.state, "pubsub", None)

    # Phase 1~3 단독 환경 — 기존 stub 동작 유지.
    if aoai is None or pg is None:
        return ChatResponse(reply=f"[stub] {req.message}", model="stub")

    if req.workspace_id is None:
        raise HTTPException(status_code=400, detail="workspace_id required for RAG chat")

    # (1) 질문 임베딩.
    embedding = await aoai.embed(req.message)

    # (2) 시맨틱 캐시 lookup.
    if redis_cache is not None:
        hit: CacheHit | None = await redis_cache.lookup(req.workspace_id, embedding)
        if hit is not None:
            logger.info(
                "semantic cache HIT workspace=%s sim=%.4f",
                req.workspace_id,
                hit.similarity,
            )
            return ChatResponse(
                reply=hit.answer,
                model="cache",
                cache_hit=True,
                similarity=hit.similarity,
            )

    # (3) PG vector 검색.
    rows = await pg.vector_search_chunks(
        workspace_id=req.workspace_id,
        query_vector=embedding,
        top_k=req.top_k,
        index_kind="hnsw",
    )
    if not rows:
        reply = "워크스페이스에 답할 만한 문서가 없습니다."
        return ChatResponse(reply=reply, model="gpt-4o-mini", sources=[])

    # (4) AOAI 답변 생성.
    context = "\n\n".join(
        f"[chunk {i + 1}] (doc={r['documentId']}, ord={r['ordinal']})\n{r['text']}"
        for i, r in enumerate(rows)
    )
    user_prompt = f"# 컨텍스트\n{context}\n\n# 질문\n{req.message}"
    answer = await aoai.chat(system=_SYSTEM_PROMPT, user=user_prompt)

    # (5) 캐시 저장 + pub/sub.
    if redis_cache is not None:
        try:
            key = await redis_cache.store(
                workspace_id=req.workspace_id,
                question=req.message,
                embedding=embedding,
                answer=answer,
            )
            if pubsub is not None:
                await pubsub.publish(
                    req.workspace_id,
                    "cache:store",
                    {"key": key, "preview": answer[:80]},
                )
        except Exception as e:  # noqa: BLE001 — 캐시 저장 실패는 응답을 막지 않음
            logger.warning("semantic cache store failed: %s", e)

    sources = [
        {
            "documentId": r["documentId"],
            "ordinal": r["ordinal"],
            "score": float(r["score"]),
        }
        for r in rows
    ]
    return ChatResponse(reply=answer, model="gpt-4o-mini", sources=sources)
