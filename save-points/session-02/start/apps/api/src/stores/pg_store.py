"""PostgreSQL pgvector 벡터 스토어 — VectorStore 구현 (session-02).

`chunks` 테이블에는 `halfvec(3072)` 컬럼과 HNSW 인덱스가 있다 (docs/sessions/02-pgvector.md
2.2 의 SQL 로 사전 생성). `text-embedding-3-large` 가 반환하는 3072 차원은 `vector` 타입의
HNSW 2000 차원 한계에 막히므로 `halfvec(3072)` + `halfvec_cosine_ops` 를 사용한다.

인증 — Entra ID 전용. `DefaultAzureCredential` 로 받은 토큰을 비밀번호 자리에 넣는다.

> [!WARNING]
> Burstable 등급은 서버 측 PgBouncer 를 지원하지 않으므로 연결 풀은 클라이언트 측
> `psycopg_pool` 로 관리한다. `register_vector_async` 는 `vector` extension 이 이미
> 있어야 동작한다 (chicken-and-egg) — docs 2.2 의 CREATE EXTENSION 을 먼저 실행한다.

본 파일은 시작본 stub 이다. 아래 anchor 주석을 따라 메서드 본체를 채운다.
완성본은 save-points/session-02/complete/ 또는 docs/sessions/02-pgvector.md 참고.
"""

from azure.identity.aio import DefaultAzureCredential
from pgvector import HalfVector
from pgvector.psycopg import register_vector_async
from psycopg_pool import AsyncConnectionPool

from ..models import Source
from ..settings import Settings

# Azure Database for PostgreSQL 의 Entra ID 토큰 스코프.
_PG_AAD_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"

# 코사인 거리 연산자 <=> + halfvec_cosine_ops 인덱스. 연산자와 ops 클래스가
# 일치해야 HNSW 인덱스가 사용된다 (불일치 시 Seq Scan 으로 강등).
_SEARCH_SQL = """
    SELECT doc_id, title, embedding <=> %s AS distance
    FROM chunks
    ORDER BY distance
    LIMIT %s
"""

_CONTENT_SQL = "SELECT content FROM chunks WHERE doc_id = %s LIMIT 1"


class PgVectorStore:
    """PostgreSQL pgvector (HNSW + halfvec) 기반 VectorStore."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._credential = DefaultAzureCredential()
        self._pool: AsyncConnectionPool | None = None

    async def open(self) -> None:
        # Entra 토큰을 받아 conninfo 의 password 자리에 넣고, configure 콜백에서
        # register_vector_async 를 호출하는 AsyncConnectionPool 을 연다.
        # 힌트: self._credential.get_token(_PG_AAD_SCOPE) → conninfo(host/port/dbname/
        #       user/password=token/sslmode=require) → AsyncConnectionPool(..., open=False,
        #       configure=_configure_connection) → await pool.open()
        raise NotImplementedError("pg_store.open 을 구현하세요.")

    async def vector_search(self, query_embedding: list[float], top_k: int) -> list[Source]:
        # hnsw_ef_search 설정이 있으면 SET LOCAL 로 트랜잭션 단위 정확도를 조절한 뒤,
        # _SEARCH_SQL 로 top_k 검색. distance → score(1-distance, 0~1 클램프) 로 Source 생성.
        # 힌트: async with pool.connection() / conn.transaction(): SET LOCAL hnsw.ef_search,
        #       conn.execute(_SEARCH_SQL, (HalfVector(query_embedding), top_k)), fetchall()
        raise NotImplementedError("pg_store.vector_search 를 구현하세요.")

    async def fetch_content(self, doc_id: str) -> str:
        # _CONTENT_SQL 로 doc_id 의 content 본문을 가져온다.
        raise NotImplementedError("pg_store.fetch_content 를 구현하세요.")

    async def close(self) -> None:
        # 연결 풀과 자격 증명을 정리한다.
        raise NotImplementedError("pg_store.close 를 구현하세요.")


async def _configure_connection(conn) -> None:  # noqa: ANN001 — psycopg 콜백 시그니처
    """새 연결마다 호출 — pgvector 타입 어댑터 (vector · halfvec) 등록."""
    await register_vector_async(conn)


async def build_pg_store(settings: Settings) -> PgVectorStore:
    """PgVectorStore 인스턴스 생성 + 풀 open.

    호출자는 앱 종료 시 `store.close()` 를 책임진다 (main.py lifespan).
    """
    store = PgVectorStore(settings)
    await store.open()
    return store
