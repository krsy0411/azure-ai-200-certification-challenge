"""
Cosmos DB for NoSQL data-plane store.

- DefaultAzureCredential 로 AAD 인증 (ACA UAMI / 로컬 az login)
- documents / chunks 컨테이너 CRUD
- chunks: text-embedding-3-large 임베딩 (/embedding, 3072-d float32) 와 함께 저장
- 검색: VectorDistance 기반 top-K (메타데이터 필터 + 벡터 거리)
- Bicep 에서 disableLocalAuth=true 로 키 비활성, sqlRoleAssignments 로 UAMI 에 Built-in Data Contributor 부여
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any

from azure.cosmos.aio import ContainerProxy, CosmosClient
from azure.identity.aio import DefaultAzureCredential


@dataclass(slots=True, frozen=True)
class CosmosSettings:
    endpoint: str
    database: str
    container_documents: str
    container_chunks: str

    @classmethod
    def from_env(cls) -> CosmosSettings:
        return cls(
            endpoint=os.environ["COSMOS_ENDPOINT"],
            database=os.environ.get("COSMOS_DB", "kb"),
            container_documents=os.environ.get("COSMOS_CONTAINER_DOCUMENTS", "documents"),
            container_chunks=os.environ.get("COSMOS_CONTAINER_CHUNKS", "chunks"),
        )


class CosmosStore:
    def __init__(self, settings: CosmosSettings) -> None:
        self._settings = settings
        self._credential = DefaultAzureCredential()
        self._client = CosmosClient(settings.endpoint, credential=self._credential)
        self._db = self._client.get_database_client(settings.database)
        self._documents: ContainerProxy = self._db.get_container_client(
            settings.container_documents
        )
        self._chunks: ContainerProxy = self._db.get_container_client(
            settings.container_chunks
        )

    async def close(self) -> None:
        await self._client.close()
        await self._credential.close()

    # --- documents ----------------------------------------------------------
    async def upsert_document(self, doc: dict[str, Any]) -> dict[str, Any]:
        return await self._documents.upsert_item(doc)

    async def get_document(
        self, workspace_id: str, doc_id: str
    ) -> dict[str, Any] | None:
        from azure.cosmos.exceptions import CosmosResourceNotFoundError

        try:
            return await self._documents.read_item(
                item=doc_id, partition_key=workspace_id
            )
        except CosmosResourceNotFoundError:
            return None

    # --- chunks -------------------------------------------------------------
    async def upsert_chunk(self, chunk: dict[str, Any]) -> dict[str, Any]:
        # chunk 는 'embedding' 키에 list[float] (3072-d) 보유
        return await self._chunks.upsert_item(chunk)

    async def upsert_chunks(
        self, chunks: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        # 학습용 단순 직렬 처리. 대량은 transactional batch 또는 bulk 모드 고려.
        results: list[dict[str, Any]] = []
        for c in chunks:
            results.append(await self.upsert_chunk(c))
        return results

    async def vector_search_chunks(
        self,
        workspace_id: str,
        query_vector: list[float],
        top_k: int = 5,
        document_id: str | None = None,
    ) -> list[dict[str, Any]]:
        """
        VectorDistance 기반 top-K 검색.
        - WHERE 절에서 workspaceId 로 partition pruning
        - document_id 가 주어지면 추가 필터 (하이브리드 검색의 메타데이터 부분)
        - ORDER BY VectorDistance ASC = 가까운 순
        """
        params: list[dict[str, Any]] = [
            {"name": "@ws", "value": workspace_id},
            {"name": "@qv", "value": query_vector},
            {"name": "@k", "value": top_k},
        ]
        filter_clause = "WHERE c.workspaceId = @ws"
        if document_id is not None:
            filter_clause += " AND c.documentId = @doc"
            params.append({"name": "@doc", "value": document_id})

        query = f"""
        SELECT TOP @k
            c.id, c.documentId, c.ordinal, c.text,
            VectorDistance(c.embedding, @qv) AS score
        FROM c
        {filter_clause}
        ORDER BY VectorDistance(c.embedding, @qv)
        """  # noqa: S608 — 파라미터 바인딩으로 안전, filter_clause 는 상수 문자열만 결합

        items: list[dict[str, Any]] = []
        # query_items 는 비동기 iterator. partition_key 지정으로 cross-partition 회피.
        async for item in self._chunks.query_items(
            query=query,
            parameters=params,
            partition_key=workspace_id,
        ):
            items.append(item)
        return items
