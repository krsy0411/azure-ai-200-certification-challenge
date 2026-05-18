"""Service Bus message sender (Cosmos trigger 에서 inference-queue 로 enqueue).

학습 경로 모듈 1 단원 3 인증 + UAMI 권장. DefaultAzureCredential.
"""

from __future__ import annotations

import json
import os
from functools import lru_cache

from azure.identity.aio import DefaultAzureCredential
from azure.servicebus import ServiceBusMessage
from azure.servicebus.aio import ServiceBusClient


@lru_cache(maxsize=1)
def _get_client() -> ServiceBusClient:
    fqdn = os.environ["SERVICEBUS_CONNECTION__fullyQualifiedNamespace"]
    credential = DefaultAzureCredential()
    return ServiceBusClient(fully_qualified_namespace=fqdn, credential=credential)


async def enqueue_chunk(
    *,
    workspace_id: str,
    document_id: str,
    chunk_id: str,
    ordinal: int,
    text: str,
    correlation_id: str,
) -> None:
    """inference-queue 에 JSON payload enqueue."""
    queue_name = os.environ.get("SERVICE_BUS_QUEUE_NAME", "inference-queue")
    body = json.dumps(
        {
            "workspaceId": workspace_id,
            "documentId": document_id,
            "chunkId": chunk_id,
            "ordinal": ordinal,
            "text": text,
            "correlationId": correlation_id,
        },
        ensure_ascii=False,
    )
    client = _get_client()
    async with client:
        sender = client.get_queue_sender(queue_name=queue_name)
        async with sender:
            await sender.send_messages(ServiceBusMessage(body))
