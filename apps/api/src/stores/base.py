"""벡터 스토어 추상화 — Cosmos DB / PostgreSQL pgvector 를 같은 인터페이스로.

session-02 에서 `STORE_BACKEND` 환경변수로 검색 백엔드를 전환할 수 있도록 도입한다.
RAG 체인 (`rag/chain.py`) 은 구체 백엔드를 모른 채 이 Protocol 에만 의존한다.

- `cosmos` → `CosmosVectorStore` (session-01)
- `pg` → `PgVectorStore` (session-02)
"""

from typing import Protocol, runtime_checkable

from ..models import Source


@runtime_checkable
class VectorStore(Protocol):
    """RAG retrieval 백엔드가 제공해야 하는 최소 인터페이스."""

    async def vector_search(self, query_embedding: list[float], top_k: int) -> list[Source]:
        """질문 임베딩과 가장 가까운 chunk top-k 의 메타데이터를 반환."""
        ...

    async def fetch_content(self, doc_id: str) -> str:
        """검색된 chunk 의 본문 텍스트를 반환."""
        ...

    async def close(self) -> None:
        """클라이언트·연결 풀·자격 증명을 정리한다 (앱 종료 시 호출)."""
        ...
