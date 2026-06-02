"""PostgreSQL pgvector 벡터 스토어 — VectorStore 구현 (session-02).

`chunks` 테이블에는 `halfvec(3072)` 컬럼과 HNSW 인덱스가 있다 (docs/sessions/02-pgvector.md
2.2 의 SQL 로 사전 생성). `text-embedding-3-large` 가 반환하는 3072 차원은 `vector` 타입의
HNSW 2000 차원 한계에 막히므로 `halfvec(3072)` + `halfvec_cosine_ops` 를 사용한다.

인증 — Entra ID 전용. `DefaultAzureCredential` 로 받은 토큰을 비밀번호 자리에 넣는다.

> [!NOTE]
> Entra 토큰은 약 1시간 후 만료된다. 본 워크샵은 단명 실행 (seed_both.py) 과 학습용
> 컨테이너를 가정하므로 풀 생성 시점의 토큰을 그대로 쓴다. 장시간 구동 서비스라면
> 만료 전 토큰 갱신 (connection factory 재발급) 이 필요하다.

> [!WARNING]
> Burstable 등급은 서버 측 PgBouncer 를 지원하지 않는다
> (`ServerParameterToCMSPgBouncerNotSupportedForBurstable`). 따라서 연결 풀은
> 클라이언트 측 `psycopg_pool` 로 관리한다. B1ms 동시 연결 한도 (50) 를 고려해
> `postgres_pool_max_size` 를 작게 둔다.

> [!WARNING]
> `register_vector_async` 는 데이터베이스에 `vector` extension 이 이미 있어야 동작한다.
> 풀 초기화 콜백에서 호출하므로, extension 이 없으면 풀 자체가 열리지 않는다
> (chicken-and-egg). docs 2.2 의 `CREATE EXTENSION vector` 를 먼저 실행한 뒤 앱을 시작한다.
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
        """Entra 토큰으로 연결 풀을 연다.

        `build_cosmos_store` 와 달리 PostgreSQL 은 비동기 풀 초기화가 필요하므로
        생성자와 분리된 async 메서드로 둔다 (main.py lifespan 에서 await).
        """
        token = await self._credential.get_token(_PG_AAD_SCOPE)
        conninfo = (
            f"host={self._settings.postgres_host} "
            f"port={self._settings.postgres_port} "
            f"dbname={self._settings.postgres_database} "
            f"user={self._settings.postgres_user} "
            f"password={token.token} "
            f"sslmode=require"
        )
        self._pool = AsyncConnectionPool(
            conninfo,
            min_size=1,
            max_size=self._settings.postgres_pool_max_size,
            open=False,
            configure=_configure_connection,
        )
        await self._pool.open()

    async def vector_search(self, query_embedding: list[float], top_k: int) -> list[Source]:
        """`embedding <=> %s` 코사인 거리로 가장 가까운 chunk top-k 검색.

        `hnsw_ef_search` 설정이 있으면 `SET LOCAL` 로 트랜잭션 단위 정확도를 조절한다.
        값을 낮추면 ANN 검색 속도가 빨라지지만 recall 이 떨어질 수 있다 — 학습용 시연.
        """
        assert self._pool is not None, "open() 을 먼저 호출해야 합니다."
        ef_search = self._settings.hnsw_ef_search

        sources: list[Source] = []
        async with self._pool.connection() as conn:
            # SET LOCAL 은 트랜잭션 안에서만 유효 — 풀로 반환된 연결에 설정이 새지 않는다.
            async with conn.transaction():
                if ef_search is not None:
                    await conn.execute("SET LOCAL hnsw.ef_search = %s", (ef_search,))
                cur = await conn.execute(_SEARCH_SQL, (HalfVector(query_embedding), top_k))
                rows = await cur.fetchall()

        for doc_id, title, distance in rows:
            sources.append(
                Source(
                    doc_id=doc_id,
                    title=title,
                    # <=> 는 cosine distance (0 = 동일). 1 - distance 를 0~1 로 클램프.
                    score=max(0.0, min(1.0, 1.0 - float(distance))),
                )
            )
        return sources

    async def fetch_content(self, doc_id: str) -> str:
        """검색된 chunk 의 `content` 본문을 가져온다."""
        assert self._pool is not None, "open() 을 먼저 호출해야 합니다."
        async with self._pool.connection() as conn:
            cur = await conn.execute(_CONTENT_SQL, (doc_id,))
            row = await cur.fetchone()
        return row[0] if row else ""

    async def close(self) -> None:
        """연결 풀과 자격 증명을 정리한다."""
        if self._pool is not None:
            await self._pool.close()
        await self._credential.close()


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
