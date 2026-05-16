"""
Redis Streams — 학습용 작업 큐 (임베딩 재처리).

학습 경로 모듈 2 단원 3 (Streams + 컨슈머 그룹 + XACK + XPENDING/XCLAIM) 매핑.

본 레포 역할:
- *학습 산출물* — XADD / XREADGROUP / XACK / XPENDING 흐름 시연 1개만.
- 프로덕션 메인 작업 큐는 Phase 7 의 Service Bus 가 담당. 학습 경로 모듈 2 ④ 의
  "pub/sub vs Streams 결정 표" 에서 Streams 의 ack 보장 / exactly-one-worker 특성을
  실제 코드로 보여주는 목적.

스트림 / 그룹:
    STREAM:  stream:reembed
    GROUP:   reembed-workers
    CONSUMER: 호출 측에서 부여 (예: 'worker-1')
"""

from __future__ import annotations

import logging
from typing import Any

from redis.exceptions import ResponseError

from src.cache.redis_client import RedisClient

logger = logging.getLogger(__name__)

STREAM_REEMBED = "stream:reembed"
GROUP_REEMBED_WORKERS = "reembed-workers"


class ReembedStream:
    def __init__(self, redis: RedisClient) -> None:
        self._redis = redis

    async def ensure_group(self) -> None:
        """consumer group 이 없으면 생성. 이미 있으면 BUSYGROUP 무시."""
        client = await self._redis.ensure_fresh()
        try:
            await client.xgroup_create(
                name=STREAM_REEMBED,
                groupname=GROUP_REEMBED_WORKERS,
                id="0",
                mkstream=True,
            )
            logger.info("xgroup created: %s / %s", STREAM_REEMBED, GROUP_REEMBED_WORKERS)
        except ResponseError as e:
            if "BUSYGROUP" not in str(e):
                raise

    async def enqueue(self, chunk_id: str, workspace_id: str) -> bytes:
        """XADD — 반환: stream entry id (e.g. b'1700000000000-0')."""
        client = await self._redis.ensure_fresh()
        entry_id = await client.xadd(
            STREAM_REEMBED,
            {"chunkId": chunk_id, "workspaceId": workspace_id},
        )
        return entry_id

    async def consume_one(
        self,
        consumer: str,
        block_ms: int = 5000,
    ) -> tuple[bytes, dict[bytes, bytes]] | None:
        """
        XREADGROUP COUNT 1 — 한 건 가져옴. 반환: (entry_id, fields) 또는 None.
        호출자가 작업 처리 후 반드시 ack() 호출해야 XPENDING 에서 빠짐.
        """
        client = await self._redis.ensure_fresh()
        result = await client.xreadgroup(
            groupname=GROUP_REEMBED_WORKERS,
            consumername=consumer,
            streams={STREAM_REEMBED: ">"},
            count=1,
            block=block_ms,
        )
        if not result:
            return None
        # result = [(stream_name, [(entry_id, {fields})])]
        _stream, entries = result[0]
        if not entries:
            return None
        entry_id, fields = entries[0]
        return entry_id, fields

    async def ack(self, entry_id: bytes | str) -> int:
        """XACK — 반환: ack 된 개수 (성공 시 1)."""
        client = await self._redis.ensure_fresh()
        n = await client.xack(STREAM_REEMBED, GROUP_REEMBED_WORKERS, entry_id)
        return int(n)

    async def pending_summary(self) -> dict[str, Any]:
        """XPENDING 요약 — 미처리 건수 확인 용도."""
        client = await self._redis.ensure_fresh()
        return await client.xpending(STREAM_REEMBED, GROUP_REEMBED_WORKERS)
