"""
PostgreSQL Flexible Server + pgvector data-plane store.

학습 경로 'develop-ai-solutions-azure-database-postgresql' 의 3 모듈을 코드로 매핑:
- 모듈 1 단원 3 "PostgreSQL 에 연결":
    DefaultAzureCredential 로 OSSRDBMS 토큰 획득 → psycopg password 로 사용
- 모듈 2 단원 2 "pgvector 임베딩 저장 / 쿼리":
    halfvec(3072) + register_vector_async + <=> (cosine distance)
- 모듈 3 단원 6 "연결 최적화":
    PgBouncer 는 Burstable B1ms 에서 미지원이라 생략.
    클라이언트 측 psycopg_pool.AsyncConnectionPool 단일 풀링만 사용.

설계 결정:
- chunks_hnsw / chunks_ivf 두 테이블에 동일 데이터 적재 → 인덱스 종류별 정확한 비교 (결정 ④ a)
- 토큰은 약 1시간 만료 — pool 재생성으로 단순 대응 (운영용은 connection factory 권장, 함정 문서화)
- ssl=require, AAD-only (passwordAuth=Disabled) 이므로 토큰 외 경로 없음
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

import psycopg
from azure.identity.aio import DefaultAzureCredential
from pgvector.psycopg import register_vector_async
from psycopg_pool import AsyncConnectionPool

# Azure Database for PostgreSQL Entra 토큰 audience.
_OSSRDBMS_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"

# 토큰 만료 5분 전부터 풀 재생성 — TTL ≈ 60min 의 10% 안전 마진.
_TOKEN_REFRESH_MARGIN_SEC = 300

_BOOTSTRAP_SQL_PATH = Path(__file__).with_name("pg_bootstrap.sql")

IndexKind = Literal["hnsw", "ivf"]


@dataclass(slots=True, frozen=True)
class PgSettings:
    host: str
    port: int
    database: str
    user: str

    @classmethod
    def from_env(cls) -> PgSettings:
        return cls(
            host=os.environ["PG_HOST"],
            port=int(os.environ.get("PG_PORT", "5432")),
            database=os.environ.get("PG_DATABASE", "kb"),
            user=os.environ["PG_USER"],
        )


class PgStore:
    def __init__(self, settings: PgSettings) -> None:
        self._s = settings
        self._credential = DefaultAzureCredential()
        self._pool: AsyncConnectionPool | None = None
        self._token_expires_on: float = 0.0
        self._bootstrapped: bool = False

    # ---- 라이프사이클 ------------------------------------------------------

    async def open(self) -> None:
        # 부트스트랩을 풀 *밖*에서 먼저 — pool 의 _configure 가 register_vector_async 를 부르는데,
        # cold-start PG 에는 vector type 이 아직 없어서 풀 connection 자체가 실패한다
        # ('vector type not found in the database' → PoolTimeout). 부트스트랩이 CREATE EXTENSION
        # vector 를 먼저 실행하도록 분리. 자세한 함정은 docs/learning-paths/05-postgresql.md.
        if not self._bootstrapped:
            await self._run_bootstrap()
            self._bootstrapped = True
        await self._ensure_pool()

    async def close(self) -> None:
        if self._pool is not None:
            await self._pool.close()
            self._pool = None
        await self._credential.close()

    # ---- 토큰·풀 관리 ------------------------------------------------------

    async def _get_fresh_token(self) -> str:
        token = await self._credential.get_token(_OSSRDBMS_SCOPE)
        self._token_expires_on = float(token.expires_on)
        return token.token

    async def _open_pool(self) -> AsyncConnectionPool:
        token = await self._get_fresh_token()
        # password 안에 공백/특수문자가 들어올 수 있어 conninfo 대신 keyword args 사용.
        kwargs: dict[str, Any] = {
            "host": self._s.host,
            "port": self._s.port,
            "dbname": self._s.database,
            "user": self._s.user,
            "password": token,
            "sslmode": "require",
        }

        async def _configure(conn: psycopg.AsyncConnection) -> None:
            # 새 connection 마다 vector / halfvec 어댑터 등록.
            await register_vector_async(conn)

        pool = AsyncConnectionPool(
            min_size=1,
            max_size=10,
            kwargs=kwargs,
            configure=_configure,
            open=False,
        )
        await pool.open()
        return pool

    async def _ensure_pool(self) -> AsyncConnectionPool:
        # 토큰 만료 임박 또는 풀 미생성 시 재생성.
        if self._pool is None or time.time() > self._token_expires_on - _TOKEN_REFRESH_MARGIN_SEC:
            if self._pool is not None:
                await self._pool.close()
            self._pool = await self._open_pool()
        return self._pool

    # ---- 부트스트랩 -------------------------------------------------------

    async def _run_bootstrap(self) -> None:
        # 풀(_configure 안의 register_vector_async) 을 거치지 않는 short-lived connection.
        # CREATE EXTENSION vector 를 먼저 실행하기 위해 vector adapter 등록을 회피한다.
        # 부트스트랩 SQL 은 DDL 텍스트만 보내므로 vector 어댑터가 필요 없다.
        sql = _BOOTSTRAP_SQL_PATH.read_text(encoding="utf-8")
        token = await self._get_fresh_token()
        conn = await psycopg.AsyncConnection.connect(
            host=self._s.host,
            port=self._s.port,
            dbname=self._s.database,
            user=self._s.user,
            password=token,
            sslmode="require",
            autocommit=False,
        )
        try:
            async with conn.cursor() as cur:
                await cur.execute(sql)
            await conn.commit()
        finally:
            await conn.close()

    # ---- chunks 쓰기 ------------------------------------------------------

    async def upsert_chunks(self, chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """
        chunks_hnsw / chunks_ivf 양쪽에 동일 데이터 upsert.
        items 의 dict 키: id, workspaceId, documentId, ordinal, text, embedding (list[float]).
        documents / workspaces 테이블도 미존재 시 자동 보강 (학습용 단순화).
        """
        if not chunks:
            return []

        pool = await self._ensure_pool()
        async with pool.connection() as conn:
            async with conn.cursor() as cur:
                # workspaces / documents 보강 (FK 제약 위반 방지). 학습용 stub.
                workspaces = {c["workspaceId"] for c in chunks}
                documents = {(c["workspaceId"], c["documentId"]) for c in chunks}

                for ws in workspaces:
                    await cur.execute(
                        "INSERT INTO workspaces (id, name) VALUES (%s, %s) "
                        "ON CONFLICT (id) DO NOTHING;",
                        (ws, ws),
                    )
                for ws, doc in documents:
                    await cur.execute(
                        """
                        INSERT INTO documents (id, workspace_id, status)
                        VALUES (%s, %s, 'ready')
                        ON CONFLICT (id) DO NOTHING;
                        """,
                        (doc, ws),
                    )

                # chunks 본체 — 두 테이블에 동일 row.
                for table in ("chunks_hnsw", "chunks_ivf"):
                    await cur.executemany(
                        f"""
                        INSERT INTO {table}
                            (id, workspace_id, document_id, ordinal, text, embedding)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        ON CONFLICT (id) DO UPDATE SET
                            workspace_id = EXCLUDED.workspace_id,
                            document_id  = EXCLUDED.document_id,
                            ordinal      = EXCLUDED.ordinal,
                            text         = EXCLUDED.text,
                            embedding    = EXCLUDED.embedding;
                        """,
                        [
                            (
                                c["id"],
                                c["workspaceId"],
                                c["documentId"],
                                c["ordinal"],
                                c["text"],
                                c["embedding"],
                            )
                            for c in chunks
                        ],
                    )
            await conn.commit()
        return chunks

    # ---- chunks 검색 ------------------------------------------------------

    async def vector_search_chunks(
        self,
        workspace_id: str,
        query_vector: list[float],
        top_k: int = 5,
        document_id: str | None = None,
        index_kind: IndexKind = "hnsw",
    ) -> list[dict[str, Any]]:
        """
        cosine distance (`<=>`) 기준 top-K.
        score 는 거리 그대로 (작을수록 가까움) — Cosmos VectorDistance 와 키·의미 일관.
        """
        if index_kind not in ("hnsw", "ivf"):
            raise ValueError(f"unsupported index_kind: {index_kind}")
        table = "chunks_hnsw" if index_kind == "hnsw" else "chunks_ivf"

        params: list[Any] = [query_vector, workspace_id]
        doc_filter = ""
        if document_id is not None:
            doc_filter = "AND document_id = %s"
            params.append(document_id)
        params.extend([query_vector, top_k])

        # column alias 를 cosmos_store 반환 키와 일치시켜 (documentId) 라우터에서 분기 불필요.
        # noqa: S608 — table 은 위 화이트리스트로 결정, doc_filter 는 상수.
        sql = f"""
        SELECT id,
               document_id AS "documentId",
               ordinal,
               text,
               (embedding <=> %s::halfvec) AS score
        FROM {table}
        WHERE workspace_id = %s
          {doc_filter}
        ORDER BY embedding <=> %s::halfvec
        LIMIT %s;
        """  # noqa: S608

        pool = await self._ensure_pool()
        async with pool.connection() as conn:
            async with conn.cursor() as cur:
                await cur.execute(sql, params)
                rows = await cur.fetchall()
                cols = [d.name for d in cur.description] if cur.description else []
        return [dict(zip(cols, r, strict=True)) for r in rows]
