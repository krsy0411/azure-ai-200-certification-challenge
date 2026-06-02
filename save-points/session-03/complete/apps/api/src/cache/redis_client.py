"""Managed Redis 비동기 클라이언트 — Entra ID 인증 (session-03).

본 워크샵 표준인 Entra ID 토큰 인증을 Redis 에도 적용한다. 저수준으로 토큰을
비밀번호 자리에 직접 넣는 대신, `redis-entraid` 의 credential provider 를 쓴다 —
토큰 발급·갱신·TLS 처리를 캡슐화하고 `DefaultAzureCredential` 과 그대로 연결된다.

> [!NOTE]
> Azure Managed Redis 는 포트 10000, TLS 필수. access key 인증은 Bicep 에서 꺼 두었으므로
> (`accessKeysAuthentication=Disabled`) Entra principal 이 access policy 에 부여되어 있어야
> 접속된다 (`redis-access-policy-assignment.bicep`).
"""

from redis.asyncio import Redis
from redis_entraid.cred_provider import create_from_default_azure_credential

from ..settings import Settings

# Azure Managed Redis 의 Entra ID 토큰 스코프.
_REDIS_AAD_SCOPE = "https://redis.azure.com/.default"


def build_redis_client(settings: Settings) -> Redis:
    """Entra ID credential provider 로 인증하는 비동기 Redis 클라이언트.

    `decode_responses=False` — 벡터 필드를 raw float32 bytes 로 다루므로 디코딩을 끄고,
    텍스트 필드는 사용하는 쪽에서 명시적으로 decode 한다.
    """
    credential_provider = create_from_default_azure_credential(
        (_REDIS_AAD_SCOPE,),
    )
    return Redis(
        host=settings.redis_host,
        port=settings.redis_port,
        ssl=True,
        credential_provider=credential_provider,
        decode_responses=False,
    )
