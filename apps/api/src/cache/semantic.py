"""
시맨틱 캐시 — RediSearch 벡터 인덱스 (HNSW + FLOAT32 + DIM 3072 + COSINE) 기반.

학습 경로 'enhance-ai-solutions-azure-managed-redis' / 모듈 3 단원 2~3 의
FT.CREATE / KNN / HNSW + COSINE + FLOAT32 권장 조합을 그대로 구현.

키 / 인덱스 설계:
    PREFIX:      sc:<workspaceId>:<sha256(question)>
    INDEX:       idx:semantic  (HASH ON, prefix=['sc:'])
    SCHEMA:
        workspaceId TAG
        question    TEXT
        embedding   VECTOR HNSW M=16 EF_CONSTRUCTION=200
                    DIM=3072 TYPE=FLOAT32 DISTANCE_METRIC=COSINE
        answer      TEXT
        tokens      NUMERIC
        createdAt   NUMERIC SORTABLE
    TTL: 24h
    HIT 기준: 코사인 유사도 ≥ threshold (default 0.92) AND 같은 workspaceId

코사인 *유사도* = 1 - cosine *distance*. RediSearch 의 vector_score 는 distance.
"""

from __future__ import annotations

import hashlib
import logging
import os
import time
from dataclasses import dataclass
from typing import Any

import numpy as np
from redis.commands.search.field import NumericField, TagField, TextField, VectorField
from redis.commands.search.index_definition import IndexDefinition, IndexType
from redis.commands.search.query import Query
from redis.exceptions import ResponseError

from src.cache.redis_client import RedisClient

logger = logging.getLogger(__name__)

_VECTOR_DIM = 3072
_VECTOR_DTYPE = np.float32


@dataclass(slots=True, frozen=True)
class SemanticCacheSettings:
    index_name: str = "idx:semantic"
    key_prefix: str = "sc:"
    ttl_seconds: int = 86400  # 24h
    threshold: float = 0.92

    @classmethod
    def from_env(cls) -> SemanticCacheSettings:
        return cls(
            index_name=os.environ.get("REDIS_SEMANTIC_INDEX", "idx:semantic"),
            key_prefix=os.environ.get("REDIS_SEMANTIC_PREFIX", "sc:"),
            ttl_seconds=int(os.environ.get("REDIS_SEMANTIC_TTL_SECONDS", "86400")),
            threshold=float(os.environ.get("REDIS_SEMANTIC_THRESHOLD", "0.92")),
        )


@dataclass(slots=True)
class CacheHit:
    answer: str
    similarity: float
    cached_question: str
    cached_at: int


class SemanticCache:
    def __init__(self, redis: RedisClient, settings: SemanticCacheSettings) -> None:
        self._redis = redis
        self._s = settings

    # ---- 부트스트랩 -------------------------------------------------------

    async def ensure_index(self) -> None:
        """idx:semantic 이 없으면 FT.CREATE. 이미 있으면 noop."""
        client = await self._redis.ensure_fresh()
        try:
            await client.ft(self._s.index_name).info()
            return  # 이미 존재
        except ResponseError as e:
            if "unknown index" not in str(e).lower() and "no such index" not in str(e).lower():
                raise

        schema = (
            TagField("workspaceId"),
            TextField("question"),
            VectorField(
                "embedding",
                "HNSW",
                {
                    "TYPE": "FLOAT32",
                    "DIM": _VECTOR_DIM,
                    "DISTANCE_METRIC": "COSINE",
                    "M": 16,
                    "EF_CONSTRUCTION": 200,
                },
            ),
            TextField("answer"),
            NumericField("tokens"),
            NumericField("createdAt", sortable=True),
        )
        definition = IndexDefinition(prefix=[self._s.key_prefix], index_type=IndexType.HASH)
        await client.ft(self._s.index_name).create_index(schema, definition=definition)
        logger.info("semantic cache index created: %s", self._s.index_name)

    # ---- read -------------------------------------------------------------

    async def lookup(
        self,
        workspace_id: str,
        embedding: list[float],
    ) -> CacheHit | None:
        """KNN 1 검색. similarity ≥ threshold && workspace 일치 시 hit."""
        client = await self._redis.ensure_fresh()
        vec_bytes = np.asarray(embedding, dtype=_VECTOR_DTYPE).tobytes()

        # workspaceId TAG filter + KNN 1.
        # RediSearch TAG 값에 하이픈/특수문자가 있으면 토크나이저가 단어 경계로 인식해 Syntax error.
        # `-`, `.`, `:`, ` ` 등은 `\` 로 escape 필수 — 함정 4. (학습 경로 본문 밖)
        ws = _escape_tag(workspace_id)
        q = (
            Query(f"(@workspaceId:{{{ws}}})=>[KNN 1 @embedding $vec AS vector_score]")
            .sort_by("vector_score")
            .return_fields("question", "answer", "createdAt", "vector_score")
            .dialect(2)
        )
        try:
            result = await client.ft(self._s.index_name).search(
                q, query_params={"vec": vec_bytes}
            )
        except ResponseError as e:
            logger.warning("semantic cache lookup failed: %s", e)
            return None

        if not result.docs:
            return None

        doc = result.docs[0]
        distance = float(doc.vector_score)
        similarity = 1.0 - distance
        if similarity < self._s.threshold:
            return None

        return CacheHit(
            answer=_decode(doc.answer),
            similarity=similarity,
            cached_question=_decode(doc.question),
            cached_at=int(doc.createdAt),
        )

    # ---- write ------------------------------------------------------------

    async def store(
        self,
        workspace_id: str,
        question: str,
        embedding: list[float],
        answer: str,
        tokens: int = 0,
    ) -> str:
        """HSET sc:<ws>:<sha256(q)> + EXPIRE. 반환: 저장된 key."""
        client = await self._redis.ensure_fresh()
        key = self._key(workspace_id, question)
        vec_bytes = np.asarray(embedding, dtype=_VECTOR_DTYPE).tobytes()
        await client.hset(
            key,
            mapping={
                "workspaceId": workspace_id,
                "question": question,
                "embedding": vec_bytes,
                "answer": answer,
                "tokens": tokens,
                "createdAt": int(time.time()),
            },
        )
        await client.expire(key, self._s.ttl_seconds)
        return key

    async def invalidate_workspace(self, workspace_id: str) -> int:
        """workspace 의 모든 캐시 엔트리 삭제. 반환: 삭제 개수."""
        client = await self._redis.ensure_fresh()
        pattern = f"{self._s.key_prefix}{workspace_id}:*"
        deleted = 0
        async for key in client.scan_iter(match=pattern, count=100):
            await client.delete(key)
            deleted += 1
        return deleted

    # ---- 내부 ------------------------------------------------------------

    def _key(self, workspace_id: str, question: str) -> str:
        digest = hashlib.sha256(question.encode("utf-8")).hexdigest()
        return f"{self._s.key_prefix}{workspace_id}:{digest}"


def _decode(v: Any) -> str:
    if isinstance(v, bytes):
        return v.decode("utf-8", errors="replace")
    return str(v) if v is not None else ""


# RediSearch TAG 필드 값에서 escape 해야 하는 문자.
# 공식 문서 (https://redis.io/docs/latest/develop/interact/search-and-query/advanced-concepts/tags/):
#   ,.<>{}[]"':;!@#$%^&*()-+=~ 그리고 공백.
_TAG_ESCAPE_CHARS = set(",.<>{}[]\"':;!@#$%^&*()-+=~ ")


def _escape_tag(value: str) -> str:
    return "".join(f"\\{c}" if c in _TAG_ESCAPE_CHARS else c for c in value)
