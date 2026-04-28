"""
Phase 4/5 학습 검증용 RAG 엔드포인트.

- POST /api/index?store=cosmos|pg                  : 텍스트 chunks 를 임베딩 → 선택한 store 에 저장
- POST /api/search?store=cosmos|pg&index_kind=...  : 쿼리 텍스트를 임베딩 → top-K
                                                      pg 인 경우 index_kind=hnsw|ivf 로 비교 측정.

store 미지정 시 cosmos (Phase 4 호환). chat.py 는 Phase 6 에서 Redis 와 함께 RAG 화 예정.
"""

from __future__ import annotations

from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field

router = APIRouter()

StoreKind = Literal["cosmos", "pg"]
PgIndexKind = Literal["hnsw", "ivf"]


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
    store: StoreKind


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
    store: StoreKind
    index_kind: PgIndexKind | None = None


def _resolve_store(request: Request, store: StoreKind):
    if store == "cosmos":
        s = getattr(request.app.state, "cosmos", None)
        if s is None:
            raise HTTPException(503, "cosmos store not initialized")
        return s
    s = getattr(request.app.state, "pg", None)
    if s is None:
        raise HTTPException(503, "pg store not initialized")
    return s


@router.post("/index", response_model=IndexResponse)
async def index_chunks(
    req: IndexRequest,
    request: Request,
    store: Annotated[StoreKind, Query()] = "cosmos",
) -> IndexResponse:
    aoai = getattr(request.app.state, "aoai", None)
    if aoai is None:
        raise HTTPException(503, "AOAI not initialized")
    backend = _resolve_store(request, store)

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

    await backend.upsert_chunks(items)
    return IndexResponse(indexed=indexed, store=store)


@router.post("/search", response_model=SearchResponse)
async def search_chunks(
    req: SearchRequest,
    request: Request,
    store: Annotated[StoreKind, Query()] = "cosmos",
    index_kind: Annotated[PgIndexKind, Query()] = "hnsw",
) -> SearchResponse:
    aoai = getattr(request.app.state, "aoai", None)
    if aoai is None:
        raise HTTPException(503, "AOAI not initialized")
    backend = _resolve_store(request, store)

    qv = await aoai.embed(req.query)

    if store == "cosmos":
        rows = await backend.vector_search_chunks(
            workspace_id=req.workspace_id,
            query_vector=qv,
            top_k=req.top_k,
            document_id=req.document_id,
        )
        used_index_kind: PgIndexKind | None = None
    else:
        rows = await backend.vector_search_chunks(
            workspace_id=req.workspace_id,
            query_vector=qv,
            top_k=req.top_k,
            document_id=req.document_id,
            index_kind=index_kind,
        )
        used_index_kind = index_kind

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
        ],
        store=store,
        index_kind=used_index_kind,
    )
