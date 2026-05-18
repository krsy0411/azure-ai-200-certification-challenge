"""EventGrid CloudEvents 1.0 publisher.

학습 경로 모듈 2 단원 3·5 매핑:
- inputSchema=CloudEventSchemaV1_0 토픽에는 CloudEvent 객체로 publish
- DefaultAzureCredential (AAD) 인증 — topic 의 disableLocalAuth=true 와 일치

Function instance singleton.
"""

from __future__ import annotations

import os
import uuid
from functools import lru_cache

from azure.core.messaging import CloudEvent
from azure.eventgrid.aio import EventGridPublisherClient
from azure.identity.aio import DefaultAzureCredential


@lru_cache(maxsize=1)
def _get_publisher() -> EventGridPublisherClient:
    endpoint = os.environ["EVENT_GRID_TOPIC_ENDPOINT"]
    credential = DefaultAzureCredential()
    return EventGridPublisherClient(endpoint, credential)


async def publish_document_indexed(
    *,
    workspace_id: str,
    document_id: str,
    chunk_id: str,
    correlation_id: str,
) -> None:
    """ai200challenge.document.indexed 이벤트 publish."""
    publisher = _get_publisher()
    event_type = os.environ.get(
        "EVENT_GRID_EVENT_TYPE", "ai200challenge.document.indexed"
    )
    event = CloudEvent(
        source=f"/ai200challenge/workspaces/{workspace_id}",
        type=event_type,
        subject=f"workspaces/{workspace_id}/documents/{document_id}/chunks/{chunk_id}",
        data={
            "workspaceId": workspace_id,
            "documentId": document_id,
            "chunkId": chunk_id,
            "correlationId": correlation_id,
        },
        id=str(uuid.uuid4()),
    )
    await publisher.send(event)
