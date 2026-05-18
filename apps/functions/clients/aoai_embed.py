"""AOAI embedding client (Phase 4 aoai_client.py 패턴 재사용).

Function instance 재사용 시 매번 재인증 회피 위해 module-level 싱글톤으로 생성.
"""

from __future__ import annotations

import os
from functools import lru_cache

from azure.identity.aio import DefaultAzureCredential, get_bearer_token_provider
from openai import AsyncAzureOpenAI

_AOAI_SCOPE = "https://cognitiveservices.azure.com/.default"


@lru_cache(maxsize=1)
def get_aoai_client() -> AsyncAzureOpenAI:
    endpoint = os.environ["AOAI_ENDPOINT"]
    credential = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(credential, _AOAI_SCOPE)
    return AsyncAzureOpenAI(
        azure_endpoint=endpoint,
        api_version="2024-10-21",
        azure_ad_token_provider=token_provider,
    )


async def embed(text: str) -> list[float]:
    client = get_aoai_client()
    deployment = os.environ.get("AOAI_DEPLOYMENT_EMBED", "text-embedding-3-large")
    resp = await client.embeddings.create(model=deployment, input=text)
    return resp.data[0].embedding
