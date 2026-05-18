"""Phase 7 Function App entry — Cosmos change feed + Service Bus trigger.

데이터 파이프라인 (docs/learning-paths/07-backend-services.md):
    Cosmos chunks 변경 → cosmos_to_queue (Function A) → SB inference-queue
        → queue_to_embed (Function B) → AOAI embed → PG UPSERT
        → Redis workspace invalidate → EventGrid publish (CloudEvents 1.0)

학습 경로 모듈 3:
- ② 호스팅: Flex Consumption (instanceMemoryMB=2048, max 100)
- ④ 트리거·바인딩: Cosmos DB trigger + Service Bus queue trigger
- ⑥ ID·액세스: UAMI (공용 ACA UAMI 단일) — connection prefix 패턴
"""

from __future__ import annotations

import json
import logging
import uuid

import azure.functions as func

from clients.aoai_embed import embed
from clients.eventgrid_publisher import publish_document_indexed
from clients.pg_writer import get_pg_writer
from clients.redis_invalidator import get_redis_invalidator
from clients.servicebus_sender import enqueue_chunk

logger = logging.getLogger(__name__)

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


# ============================================================================
# Function A — Cosmos change feed trigger
# ============================================================================
# COSMOS_CONNECTION prefix 가 COSMOS_CONNECTION__accountEndpoint + __credential 로 resolve
# (학습 경로 functions-bindings-cosmosdb-v2-trigger AAD 인증 패턴).
# lease 컨테이너는 자동 생성 (Function 의 UAMI 가 Cosmos data-plane RBAC 필요).
@app.cosmos_db_trigger(
    arg_name="documents",
    database_name="%COSMOS_DB%",
    container_name="%COSMOS_CONTAINER_CHUNKS%",
    lease_container_name="leases",
    create_lease_container_if_not_exists=True,
    connection="COSMOS_CONNECTION",
)
async def cosmos_to_queue(documents: func.DocumentList) -> None:
    """Cosmos chunks 변경 → SB inference-queue enqueue (1:1)."""
    if not documents:
        return
    for doc in documents:
        try:
            data = doc.to_dict() if hasattr(doc, "to_dict") else dict(doc)
            chunk_id = str(data.get("id"))
            workspace_id = str(data.get("workspaceId") or data.get("workspace_id", ""))
            document_id = str(data.get("documentId") or data.get("document_id", ""))
            ordinal = int(data.get("ordinal", 0))
            text = str(data.get("text", ""))
            if not (chunk_id and workspace_id and document_id and text):
                logger.warning("cosmos_to_queue: skipping incomplete doc id=%s", chunk_id)
                continue
            correlation_id = str(uuid.uuid4())
            await enqueue_chunk(
                workspace_id=workspace_id,
                document_id=document_id,
                chunk_id=chunk_id,
                ordinal=ordinal,
                text=text,
                correlation_id=correlation_id,
            )
            logger.info(
                "cosmos_to_queue enqueued chunk=%s ws=%s corr=%s",
                chunk_id, workspace_id, correlation_id,
            )
        except Exception as e:
            logger.exception("cosmos_to_queue failed for doc: %s", e)
            # change feed 는 batch 처리이므로 1건 실패는 로그만 — 무한 retry 회피
            continue


# ============================================================================
# Function B — Service Bus queue trigger
# ============================================================================
# SERVICEBUS_CONNECTION prefix 가 __fullyQualifiedNamespace + __credential 로 resolve.
# 메시지 처리 실패 시 raise → SB 가 abandon, max delivery 5 초과 후 DLQ 자동 이동.
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="%SERVICE_BUS_QUEUE_NAME%",
    connection="SERVICEBUS_CONNECTION",
)
async def queue_to_embed(msg: func.ServiceBusMessage) -> None:
    """SB 메시지 → AOAI embed → PG UPSERT → Redis invalidate → EG publish."""
    body = json.loads(msg.get_body().decode("utf-8"))
    workspace_id = body["workspaceId"]
    document_id = body["documentId"]
    chunk_id = body["chunkId"]
    ordinal = int(body.get("ordinal", 0))
    text = body["text"]
    correlation_id = body.get("correlationId", str(uuid.uuid4()))

    logger.info(
        "queue_to_embed start chunk=%s ws=%s corr=%s",
        chunk_id, workspace_id, correlation_id,
    )

    # (1) AOAI embed
    embedding = await embed(text)

    # (2) PG UPSERT
    pg = get_pg_writer()
    await pg.upsert_chunk(
        chunk_id=chunk_id,
        workspace_id=workspace_id,
        document_id=document_id,
        ordinal=ordinal,
        text=text,
        embedding=embedding,
    )

    # (3) Redis workspace 캐시 invalidate (이전 답변이 stale 일 수 있음)
    redis_inv = get_redis_invalidator()
    deleted = await redis_inv.invalidate_workspace(workspace_id)
    if deleted:
        logger.info("redis invalidate ws=%s deleted=%d", workspace_id, deleted)

    # (4) EventGrid publish — 사용자 알림 / 다음 단계 trigger
    await publish_document_indexed(
        workspace_id=workspace_id,
        document_id=document_id,
        chunk_id=chunk_id,
        correlation_id=correlation_id,
    )

    logger.info(
        "queue_to_embed done chunk=%s ws=%s corr=%s",
        chunk_id, workspace_id, correlation_id,
    )
