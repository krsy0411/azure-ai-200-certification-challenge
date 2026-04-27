"""
Phase 4 학습 검증용 RAG 엔드포인트.
- POST /api/index   : 텍스트 chunks 를 임베딩 → Cosmos chunks 컨테이너에 저장
- POST /api/search  : 쿼리 텍스트를 임베딩 → VectorDistance top-K 결과 반환
chat.py 는 Phase 5/6 에서 PG/Redis 를 합치며 RAG 화 예정 — 여기서는 stub 유지.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

router = APIRouter()


class ChunkInput(BaseModel):
    document_id: str = Field(min_length=1, max_length=128)
    ordinal: int = Field(ge=0)
    text: str = Field(min_length=1, max_length=8000)


class IndexRequest(BaseModel):
    workspace_id: str = Field(min_length=1, max_length=128)
    chunks: list[ChunkInput] = Field(min_length=1, max_length=64)


class IndexedChunk(BaseModel):
    id: str
    document_id: str
    ordinal: int


class IndexResponse(BaseModel):
    indexed: list[IndexedChunk]


class SearchRequest(BaseModel):
    workspace_id: str = Field(min_length=1, max_length=128)
    query: str = Field(min_length=1, max_length=2000)
    top_k: int = Field(default=5, ge=1, le=20)
    document_id: str | None = None


class SearchHit(BaseModel):
    id: str
    document_id: str
    ordinal: int
    text: str
    score: float


class SearchResponse(BaseModel):
    hits: list[SearchHit]


@router.post("/index", response_model=IndexResponse)
async def index_chunks(req: IndexRequest, request: Request) -> IndexResponse:
    cosmos = getattr(request.app.state, "cosmos", None)
    aoai = getattr(request.app.state, "aoai", None)
    if cosmos is None or aoai is None:
        raise HTTPException(503, "RAG backend not initialized (Cosmos/AOAI)")

    texts = [c.text for c in req.chunks]
    embeddings = await aoai.embed_batch(texts)

    items: list[dict] = []
    indexed: list[IndexedChunk] = []
    for c, vec in zip(req.chunks, embeddings, strict=True):
        chunk_id = f"chunk_{c.document_id}_{c.ordinal}"
        items.append(
            {
                "id": chunk_id,
                "workspaceId": req.workspace_id,
                "documentId": c.document_id,
                "ordinal": c.ordinal,
                "text": c.text,
                "embedding": vec,
            }
        )
        indexed.append(
            IndexedChunk(id=chunk_id, document_id=c.document_id, ordinal=c.ordinal)
        )

    await cosmos.upsert_chunks(items)
    return IndexResponse(indexed=indexed)


@router.post("/search", response_model=SearchResponse)
async def search_chunks(req: SearchRequest, request: Request) -> SearchResponse:
    cosmos = getattr(request.app.state, "cosmos", None)
    aoai = getattr(request.app.state, "aoai", None)
    if cosmos is None or aoai is None:
        raise HTTPException(503, "RAG backend not initialized (Cosmos/AOAI)")

    qv = await aoai.embed(req.query)
    rows = await cosmos.vector_search_chunks(
        workspace_id=req.workspace_id,
        query_vector=qv,
        top_k=req.top_k,
        document_id=req.document_id,
    )

    return SearchResponse(
        hits=[
            SearchHit(
                id=r["id"],
                document_id=r["documentId"],
                ordinal=r["ordinal"],
                text=r["text"],
                score=float(r["score"]),
            )
            for r in rows
        ]
    )
