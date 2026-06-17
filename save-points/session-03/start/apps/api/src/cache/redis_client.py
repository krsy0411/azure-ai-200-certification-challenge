"""Managed Redis 비동기 클라이언트 — Entra ID 인증 (session-03).

본 워크샵 표준인 Entra ID 토큰 인증을 Redis 에도 적용한다. 저수준으로 토큰을
비밀번호 자리에 직접 넣는 대신, `redis-entraid` 의 credential provider 를 쓴다 —
토큰 발급·갱신·TLS 처리를 캡슐화하고 `DefaultAzureCredential` 과 그대로 연결된다.

본 파일은 시작본 stub 이다. anchor 주석을 따라 build_redis_client 본체를 채운다.
완성본은 save-points/session-03/complete/ 또는 docs/sessions/03-redis-cache.md 참고.
"""

from redis.asyncio import Redis
from redis_entraid.cred_provider import create_from_default_azure_credential

from ..settings import Settings

# Azure Managed Redis 의 Entra ID 토큰 스코프.
_REDIS_AAD_SCOPE = "https://redis.azure.com/.default"


def build_redis_client(settings: Settings) -> Redis:
    # 힌트: create_from_default_azure_credential((_REDIS_AAD_SCOPE,)) 로 credential_provider 를
    # 만들고, Redis(host=settings.redis_host, port=settings.redis_port, ssl=True,
    # credential_provider=..., decode_responses=False, protocol=2) 를 반환합니다.
    # decode_responses=False — 벡터를 raw float32 bytes 로 다루므로 디코딩은 사용처에서.
    # protocol=2 — Azure Managed Redis 는 redis-py 8.x 와 RESP3 로 협상하는데 고수준
    #   ft().search() 파서가 RESP3 를 못 다뤄 캐시가 항상 miss 한다. RESP2 로 고정한다.
    raise NotImplementedError("build_redis_client 를 구현하세요.")