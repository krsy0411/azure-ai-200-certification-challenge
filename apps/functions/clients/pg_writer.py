"""PG chunks_hnsw + chunks_ivf UPSERT (Phase 5 pg_store.py 패턴 재사용).

함정 4 (Phase 5) — register_vector_async chicken-and-egg 해결:
  _bootstrap 은 vector adapter 등록 *전에* 실행 (CREATE EXTENSION vector).
  본 Function 은 Phase 5 의 bootstrap 이 *이미 실행됐다는 전제* — Phase 5 main.bicep 배포
  + 검증 시점에 chunks_hnsw/chunks_ivf 테이블 + vector extension 모두 생성 완료.
  Function 은 INSERT/UPSERT 만.

Function instance lifecycle: singleton pool, 토큰 만료 5분 전 재생성.
"""

from __future__ import annotations

import os
import time
from typing import Any

import psycopg
from azure.identity.aio import DefaultAzureCredential
from pgvector.psycopg import register_vector_async
from psycopg_pool import AsyncConnectionPool

_OSSRDBMS_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"
_TOKEN_REFRESH_MARGIN_SEC = 300


class PgWriter:
    """모듈 싱글톤. instance 가 살아있는 동안 pool 재사용."""

    def __init__(self) -> None:
        self._credential = DefaultAzureCredential()
        self._pool: AsyncConnectionPool | None = None
        self._token_expires_on: float = 0.0

    async def close(self) -> None:
        if self._pool is not None:
            await self._pool.close()
            self._pool = None
        await self._credential.close()

    async def _get_token(self) -> str:
        token = await self._credential.get_token(_OSSRDBMS_SCOPE)
        self._token_expires_on = float(token.expires_on)
        return token.token

    async def _ensure_pool(self) -> AsyncConnectionPool:
        if (
            self._pool is None
            or time.time() > self._token_expires_on - _TOKEN_REFRESH_MARGIN_SEC
        ):
            if self._pool is not None:
                await self._pool.close()
            token = await self._get_token()
            kwargs: dict[str, Any] = {
                "host": os.environ["PG_HOST"],
                "port": int(os.environ.get("PG_PORT", "5432")),
                "dbname": os.environ.get("PG_DATABASE", "kb"),
                "user": os.environ["PG_USER"],
                "password": token,
                "sslmode": "require",
            }

            async def _configure(conn: psycopg.AsyncConnection) -> None:
                await register_vector_async(conn)

            self._pool = AsyncConnectionPool(
                min_size=1,
                max_size=5,
                kwargs=kwargs,
                configure=_configure,
                open=False,
            )
            await self._pool.open()
        return self._pool

    async def upsert_chunk(
        self,
        *,
        chunk_id: str,
        workspace_id: str,
        document_id: str,
        ordinal: int,
        text: str,
        embedding: list[float],
    ) -> None:
        """chunks_hnsw 단일 UPSERT (Function 은 메시지당 1 chunk 처리)."""
        pool = await self._ensure_pool()
        async with pool.connection() as conn:
            async with conn.cursor() as cur:
                # workspace/document 보강 (FK 제약)
                await cur.execute(
                    "INSERT INTO workspaces (id, name) VALUES (%s, %s) "
                    "ON CONFLICT (id) DO NOTHING;",
                    (workspace_id, workspace_id),
                )
                await cur.execute(
                    """
                    INSERT INTO documents (id, workspace_id, status)
                    VALUES (%s, %s, 'ready')
                    ON CONFLICT (id) DO NOTHING;
                    """,
                    (document_id, workspace_id),
                )
                # chunks_hnsw UPSERT (메인 retrieval 테이블)
                await cur.execute(
                    """
                    INSERT INTO chunks_hnsw
                        (id, workspace_id, document_id, ordinal, text, embedding)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (id) DO UPDATE SET
                        workspace_id = EXCLUDED.workspace_id,
                        document_id  = EXCLUDED.document_id,
                        ordinal      = EXCLUDED.ordinal,
                        text         = EXCLUDED.text,
                        embedding    = EXCLUDED.embedding;
                    """,
                    (chunk_id, workspace_id, document_id, ordinal, text, embedding),
                )
            await conn.commit()


_writer: PgWriter | None = None


def get_pg_writer() -> PgWriter:
    global _writer
    if _writer is None:
        _writer = PgWriter()
    return _writer
