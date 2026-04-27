"""
Azure OpenAI client with AAD (DefaultAzureCredential) auth.

- ACA 위에서는 UAMI (env AZURE_CLIENT_ID 가 가리키는 ID) 로 토큰 자동 획득
- 로컬에서는 az login 한 사용자 자격증명 사용
- API key 비활성 (Bicep 에서 disableLocalAuth=true) 이므로 토큰 외 경로 없음
"""

from __future__ import annotations

from azure.identity.aio import DefaultAzureCredential, get_bearer_token_provider
from openai import AsyncAzureOpenAI

# https://cognitiveservices.azure.com/.default = AOAI 데이터 plane 토큰 audience
_AOAI_SCOPE = "https://cognitiveservices.azure.com/.default"


class AOAIClient:
    """Async wrapper. embed(text) / embed_batch(list[str]) / chat(...) 만 노출."""

    def __init__(
        self,
        endpoint: str,
        chat_deployment: str,
        embed_deployment: str,
        api_version: str = "2024-10-21",
    ) -> None:
        self._credential = DefaultAzureCredential()
        token_provider = get_bearer_token_provider(self._credential, _AOAI_SCOPE)
        self._client = AsyncAzureOpenAI(
            azure_endpoint=endpoint,
            api_version=api_version,
            azure_ad_token_provider=token_provider,
        )
        self._chat_deployment = chat_deployment
        self._embed_deployment = embed_deployment

    async def embed(self, text: str) -> list[float]:
        resp = await self._client.embeddings.create(
            model=self._embed_deployment,
            input=text,
        )
        return resp.data[0].embedding

    async def embed_batch(self, texts: list[str]) -> list[list[float]]:
        # AOAI 임베딩은 배치 입력을 지원 — 한 번 호출로 N 개 벡터
        resp = await self._client.embeddings.create(
            model=self._embed_deployment,
            input=texts,
        )
        return [item.embedding for item in resp.data]

    async def chat(
        self,
        system: str,
        user: str,
        max_output_tokens: int = 512,
        temperature: float = 0.2,
    ) -> str:
        resp = await self._client.chat.completions.create(
            model=self._chat_deployment,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            temperature=temperature,
            max_tokens=max_output_tokens,
        )
        return resp.choices[0].message.content or ""

    async def close(self) -> None:
        await self._client.close()
        await self._credential.close()
