"""시맨틱 캐시 (session-03) — RediSearch 벡터 인덱스 기반.

의미상 같은 질문 (paraphrase) 을 임베딩 유사도로 묶어 캐시 hit 시킨다.

- 인덱스: RediSearch FLAT (정확 최근접). 캐시 엔트리 수가 수백~수천이라 학습 경로 기준상
  FLAT 이 적합 — HNSW 의 근사 오차 없이 잘못된 hit 위험을 낮춘다.
- 거리: COSINE. RediSearch 는 distance(0=동일 ~ 2=반대) 를 반환하므로 similarity = 1 - distance
  로 환산해 임계값과 비교한다 (이 환산을 빼먹으면 전부-hit/전부-miss 침묵 버그).
- 저장: Redis Hash. FT.SEARCH 는 인덱스 prefix 와 일치하는 hash 키만 인덱싱하므로,
  임베딩·답변·출처를 한 hash 키에 함께 둔다 (SET 단독 저장은 인덱싱되지 않음).
"""

import json
import struct
import uuid

from opentelemetry import trace
from redis.asyncio import Redis
from redis.commands.search.field import TextField, VectorField
from redis.commands.search.index_definition import IndexDefinition, IndexType
from redis.commands.search.query import Query
from redis.exceptions import ResponseError

from ..models import ChatResponse, Source
from ..settings import Settings
from .redis_client import build_redis_client

_tracer = trace.get_tracer(__name__)

_INDEX_NAME = "rag_cache_idx"
_KEY_PREFIX = "rag:"


def _to_float32_bytes(vec: list[float]) -> bytes:
    """float 리스트를 RediSearch 가 기대하는 little-endian float32 바이트로 직렬화."""
    return struct.pack(f"<{len(vec)}f", *vec)


def _decode(value: bytes | str) -> str:
    return value.decode() if isinstance(value, bytes) else value


class SemanticCache:
    """RAG 응답의 시맨틱 캐시."""

    def __init__(self, client: Redis, settings: Settings) -> None:
        self._r = client
        self._threshold = settings.cache_similarity_threshold
        self._ttl = settings.cache_ttl_seconds
        self._dim = settings.cache_vector_dim

    async def ensure_index(self) -> None:
        """FLAT 벡터 인덱스를 (없으면) 생성. prefix rag:, hash 기반."""
        try:
            await self._r.ft(_INDEX_NAME).info()
            return  # 이미 존재
        except ResponseError:
            pass

        schema = (
            VectorField(
                "embedding",
                "FLAT",
                {"TYPE": "FLOAT32", "DIM": self._dim, "DISTANCE_METRIC": "COSINE"},
            ),
            TextField("answer"),
            TextField("sources"),
        )
        definition = IndexDefinition(prefix=[_KEY_PREFIX], index_type=IndexType.HASH)
        await self._r.ft(_INDEX_NAME).create_index(schema, definition=definition)

    async def lookup(self, query_embedding: list[float]) -> ChatResponse | None:
        """질문 임베딩으로 KNN(1) 검색. similarity ≥ 임계값이면 캐시된 응답 반환."""
        with _tracer.start_as_current_span("cache.lookup") as span:
            vec = _to_float32_bytes(query_embedding)
            query = (
                Query("*=>[KNN 1 @embedding $vec AS dist]")
                .sort_by("dist")
                .return_fields("answer", "sources", "dist")
                .dialect(2)
            )
            result = await self._r.ft(_INDEX_NAME).search(query, query_params={"vec": vec})

            if result.docs:
                # RediSearch COSINE 은 distance(0~2). similarity 로 환산해 비교.
                similarity = 1.0 - float(_decode(result.docs[0].dist))
                if similarity >= self._threshold:
                    span.set_attribute("cache_hit", True)
                    span.set_attribute("cache_similarity", similarity)
                    return _to_response(result.docs[0])

            span.set_attribute("cache_hit", False)
            return None

    async def store(
        self, query_embedding: list[float], question: str, response: ChatResponse
    ) -> None:
        """캐시 miss 였던 응답을 hash 로 저장 + TTL 부여."""
        key = f"{_KEY_PREFIX}{uuid.uuid4().hex}"
        mapping = {
            "embedding": _to_float32_bytes(query_embedding),
            "question": question,
            "answer": response.answer,
            "sources": json.dumps(
                [s.model_dump() for s in response.sources], ensure_ascii=False
            ),
        }
        await self._r.hset(key, mapping=mapping)
        await self._r.expire(key, self._ttl)

    async def close(self) -> None:
        await self._r.aclose()


def _to_response(doc) -> ChatResponse:  # noqa: ANN001 — redis Document 동적 타입
    """RediSearch Document → ChatResponse 복원."""
    sources = [Source(**s) for s in json.loads(_decode(doc.sources))]
    return ChatResponse(answer=_decode(doc.answer), sources=sources)


async def build_semantic_cache(settings: Settings) -> SemanticCache:
    """Redis 클라이언트 생성 + 인덱스 보장 후 SemanticCache 반환.

    호출자는 앱 종료 시 `cache.close()` 를 책임진다 (main.py lifespan).
    """
    client = build_redis_client(settings)
    cache = SemanticCache(client, settings)
    await cache.ensure_index()
    return cache
