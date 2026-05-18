"""Redis workspace 캐시 invalidate (Phase 6 semantic.py 패턴 재사용).

Phase 6 함정 적용:
- 함정 2: ConnectionPool 의 ssl kwarg 미지원 → connection_class=SSLConnection
- 함정 3: AAD 인증 username = principalId (REDIS_USERNAME env)
- 함정 4: TAG 값 escape — invalidate 는 SCAN MATCH 사용이라 TAG escape 불필요 (key prefix 기반)

Function instance singleton.
"""

from __future__ import annotations

import os
import time

import redis.asyncio as redis
from azure.identity.aio import DefaultAzureCredential

_REDIS_SCOPE = "https://redis.azure.com/.default"
_TOKEN_REFRESH_MARGIN_SEC = 300


class RedisInvalidator:
    def __init__(self) -> None:
        self._credential = DefaultAzureCredential()
        self._pool: redis.ConnectionPool | None = None
        self._client: redis.Redis | None = None
        self._token_expires_on: float = 0.0

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None
        if self._pool is not None:
            await self._pool.aclose()
            self._pool = None
        await self._credential.close()

    async def _get_token(self) -> str:
        token = await self._credential.get_token(_REDIS_SCOPE)
        self._token_expires_on = float(token.expires_on)
        return token.token

    async def _ensure_client(self) -> redis.Redis:
        if (
            self._client is None
            or time.time() > self._token_expires_on - _TOKEN_REFRESH_MARGIN_SEC
        ):
            if self._client is not None:
                await self._client.aclose()
            if self._pool is not None:
                await self._pool.aclose()
            token = await self._get_token()
            tls = os.environ.get("REDIS_TLS", "true").lower() == "true"
            connection_class = redis.SSLConnection if tls else redis.Connection
            self._pool = redis.ConnectionPool(
                connection_class=connection_class,
                host=os.environ["REDIS_HOST"],
                port=int(os.environ.get("REDIS_PORT", "10000")),
                username=os.environ["REDIS_USERNAME"],
                password=token,
                decode_responses=False,
                max_connections=5,
            )
            self._client = redis.Redis(connection_pool=self._pool)
        return self._client

    async def invalidate_workspace(self, workspace_id: str) -> int:
        """문서 변경 시 해당 workspace 의 모든 시맨틱 캐시 entry 삭제."""
        client = await self._ensure_client()
        prefix = os.environ.get("REDIS_SEMANTIC_PREFIX", "sc:")
        pattern = f"{prefix}{workspace_id}:*"
        deleted = 0
        async for key in client.scan_iter(match=pattern, count=100):
            await client.delete(key)
            deleted += 1
        return deleted


_invalidator: RedisInvalidator | None = None


def get_redis_invalidator() -> RedisInvalidator:
    global _invalidator
    if _invalidator is None:
        _invalidator = RedisInvalidator()
    return _invalidator
