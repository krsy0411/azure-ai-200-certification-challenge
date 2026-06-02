"""Cosmos DB 벡터 스토어 — VectorStore 구현 (session-01).

Cosmos `chunks` 컨테이너에는 다음 vector policy 가 설정되어 있다 (Bicep
`cosmos-sql-container.bicep` 참고).

- path: `/embedding`
- dataType: `float32`
- dimensions: `3072` — `text-embedding-3-large` 와 일치
- distanceFunction: `cosine`
- indexType: `quantizedFlat`

Cosmos DB 의 NoSQL Vector Search 는 `VectorDistance()` 함수와 `ORDER BY` 의
`TOP N` 으로 KNN 검색을 표현한다.

> [!IMPORTANT]
> Cosmos data plane RBAC ≠ control plane RBAC. 본 스토어는 User Assigned
> Managed Identity 가 `Cosmos DB Built-in Data Contributor` SQL role 을
> 보유한다는 전제로 동작한다 (Bicep 의 `role-assignment-cosmos-data-contributor.bicep`).
> 일반 `Reader` / `Contributor` Azure RBAC 로는 401 응답이 발생한다.
"""

from azure.cosmos.aio import CosmosClient
from azure.identity.aio import DefaultAzureCredential

from ..models import Source
from ..settings import Settings


class CosmosVectorStore:
    """Cosmos DB NoSQL Vector Search 기반 VectorStore.

    `azure.identity.aio.DefaultAzureCredential` (비동기) 로 토큰을 매 요청마다
    발급한다. `disableLocalAuth=true` 인 Cosmos 계정은 Entra ID 토큰만 허용한다.
    """

    def __init__(self, settings: Settings) -> None:
        self._credential = DefaultAzureCredential()
        self._client = CosmosClient(url=settings.cosmos_endpoint, credential=self._credential)
        database = self._client.get_database_client(settings.cosmos_database)
        self._container = database.get_container_client(settings.cosmos_chunks_container)

    async def vector_search(self, query_embedding: list[float], top_k: int) -> list[Source]:
        """`VectorDistance()` 로 가장 가까운 chunk top-k 를 검색.

        파라미터 바인딩 `@embedding` 으로 SQL injection 을 회피한다.
        """
        sql = """
            SELECT TOP @topK
                c.doc_id,
                c.title,
                VectorDistance(c.embedding, @embedding) AS similarity
            FROM c
            ORDER BY VectorDistance(c.embedding, @embedding)
        """
        parameters = [
            {"name": "@topK", "value": top_k},
            {"name": "@embedding", "value": query_embedding},
        ]

        sources: list[Source] = []
        # enable_cross_partition_query 는 SDK 기본값으로 동작 — 학습 단계에서는 전수 스캔 허용.
        # 운영 환경에서는 partition_key 를 명시해 RU 폭주를 막아야 한다
        # (docs/pitfalls/common.md 참고).
        async for item in self._container.query_items(query=sql, parameters=parameters):
            sources.append(
                Source(
                    doc_id=item["doc_id"],
                    title=item.get("title"),
                    # VectorDistance 는 cosine distance (0 = 동일, 2 = 반대). 학습 단순화를
                    # 위해 1 - distance 를 0~1 로 클램프해 유사도 점수로 본다.
                    score=max(0.0, min(1.0, 1.0 - item["similarity"])),
                )
            )
        return sources

    async def fetch_content(self, doc_id: str) -> str:
        """검색된 chunk 의 `content` 본문을 단일 partition 조회로 가져온다.

        `doc_id` 가 partition key 라는 가정으로 cross-partition 비용을 피한다.
        """
        sql = "SELECT VALUE c.content FROM c WHERE c.doc_id = @docId"
        parameters = [{"name": "@docId", "value": doc_id}]

        async for item in self._container.query_items(
            query=sql,
            parameters=parameters,
            partition_key=doc_id,
        ):
            return item
        return ""

    async def close(self) -> None:
        """클라이언트와 자격 증명을 정리한다."""
        await self._client.close()
        await self._credential.close()


def build_cosmos_store(settings: Settings) -> CosmosVectorStore:
    """CosmosVectorStore 인스턴스 생성.

    호출자는 앱 종료 시 `store.close()` 를 책임진다 (main.py lifespan).
    """
    return CosmosVectorStore(settings)
