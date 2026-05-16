"""
Azure Managed Redis (Microsoft.Cache/redisEnterprise) async client with AAD auth.

학습 경로 'enhance-ai-solutions-azure-managed-redis' / 모듈 1 단원 3
"클라이언트 라이브러리 및 개발 모범 사례" 를 코드로 매핑:

- redis-py asyncio + TLS
- AAD 토큰을 password 로 — Redis 측 user 는 'default' 고정, password 가 토큰 자체
- 토큰 만료 (~1h) 전 5분 마진으로 connection pool 재생성 (PgStore 와 동일 패턴)
- Phase 4·5 와 일관된 DefaultAzureCredential
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass

import redis.asyncio as redis
from azure.identity.aio import DefaultAzureCredential

# Azure Managed Redis 데이터 평면 토큰 audience
_REDIS_SCOPE = "https://redis.azure.com/.default"

# 토큰 만료 5분 전부터 풀 재생성 — TTL ≈ 60min 의 10% 안전 마진
_TOKEN_REFRESH_MARGIN_SEC = 300


@dataclass(slots=True, frozen=True)
class RedisSettings:
    host: str
    port: int
    username: str
    tls: bool = True

    @classmethod
    def from_env(cls) -> RedisSettings:
        # Azure Managed Redis 의 AAD 인증: username = principal objectId (UAMI 면 principalId).
        # /azure/redis/entra-for-authentication 명시. "default" 는 인증 실패.
        return cls(
            host=os.environ["REDIS_HOST"],
            port=int(os.environ.get("REDIS_PORT", "10000")),
            username=os.environ["REDIS_USERNAME"],
            tls=os.environ.get("REDIS_TLS", "true").lower() == "true",
        )


class RedisClient:
    """Connection pool wrapper. `.client` 로 redis.asyncio.Redis 핸들 노출."""

    def __init__(self, settings: RedisSettings) -> None:
        self._s = settings
        self._credential = DefaultAzureCredential()
        self._pool: redis.ConnectionPool | None = None
        self._client: redis.Redis | None = None
        self._token_expires_on: float = 0.0

    async def open(self) -> None:
        await self._ensure_client()

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None
        if self._pool is not None:
            await self._pool.aclose()
            self._pool = None
        await self._credential.close()

    @property
    def client(self) -> redis.Redis:
        if self._client is None:
            raise RuntimeError("RedisClient not opened — call await open() first")
        return self._client

    async def ensure_fresh(self) -> redis.Redis:
        """Public — 토큰 만료 임박 시 pool 재생성 후 client 반환."""
        return await self._ensure_client()

    # ---- 내부 ------------------------------------------------------------

    async def _get_fresh_token(self) -> str:
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
            token = await self._get_fresh_token()
            # Azure Managed Redis AAD 인증:
            #   user = principal objectId (UAMI 의 principalId)
            #   password = Entra access token (scope=https://redis.azure.com/.default)
            # username 으로 "default" 를 주면 invalid username-password pair 로 거부 — 함정 3.
            #
            # decode_responses=False — 벡터는 bytes 로 다뤄야 함 (HSET 으로 raw bytes 저장).
            # TLS 는 ssl kwarg 가 아니라 connection_class 지정으로 활성화한다 — 함정 2.
            # (redis-py 5.x — ConnectionPool 은 ssl kwarg 미수신, SSLConnection 필요)
            connection_class = redis.SSLConnection if self._s.tls else redis.Connection
            self._pool = redis.ConnectionPool(
                connection_class=connection_class,
                host=self._s.host,
                port=self._s.port,
                username=self._s.username,
                password=token,
                decode_responses=False,
                max_connections=20,
            )
            self._client = redis.Redis(connection_pool=self._pool)
        return self._client
