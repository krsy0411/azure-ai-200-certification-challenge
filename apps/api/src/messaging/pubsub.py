"""
Redis pub/sub — fire-and-forget 알림 채널.

학습 경로 모듈 2 단원 2 (pub/sub 게시·구독) + 단원 4 (pub/sub vs Streams 결정 표) 매핑.
본 레포 역할:
- 캐시 저장 알림 (cache:store / cache:invalidate)
- 문서 인덱싱 진행률 (index:progress)
- 챗 토큰 fanout (chat:token)

채널 네이밍: ws:<workspaceId>:events
- workspace 별로 분리해 권한·구독 범위 제한 (Phase 8 Key Vault·App Configuration 이후 ACL 강화)
"""

from __future__ import annotations

import json
import logging
from typing import Any

from src.cache.redis_client import RedisClient

logger = logging.getLogger(__name__)


def channel_for_workspace(workspace_id: str) -> str:
    return f"ws:{workspace_id}:events"


class PubSubPublisher:
    def __init__(self, redis: RedisClient) -> None:
        self._redis = redis

    async def publish(self, workspace_id: str, event_type: str, payload: dict[str, Any]) -> int:
        """
        반환: 메시지를 받은 구독자 수 (PUBLISH 의 정수 응답).
        구독자가 없을 때 0 — fire-and-forget 이므로 에러 아님.
        """
        client = await self._redis.ensure_fresh()
        channel = channel_for_workspace(workspace_id)
        message = json.dumps({"type": event_type, "payload": payload}, ensure_ascii=False)
        n = await client.publish(channel, message)
        logger.debug("pubsub publish channel=%s type=%s subscribers=%d", channel, event_type, n)
        return int(n)
