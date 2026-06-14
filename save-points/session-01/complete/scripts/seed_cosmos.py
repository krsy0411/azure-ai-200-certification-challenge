#!/usr/bin/env python
"""scripts/seed_cosmos.py — Cosmos DB chunks 컨테이너에 학습용 문서 시드 (session-01).

RAG 파이프라인이 의미 있는 답변을 내려면 벡터 검색 대상이 되는 chunk 가 먼저
적재되어 있어야 한다. 본 스크립트는 학습용 사내 문서 코퍼스를 만들고,
`text-embedding-3-large` 로 임베딩해 Cosmos `chunks` 컨테이너에 upsert 한다.

인증 — Cosmos · Azure OpenAI 모두 DefaultAzureCredential (Entra ID 토큰).
키를 코드에 두지 않는다. 로컬에서는 `az login` 자격이, Azure 위에서는 Managed
Identity 가 자동 선택된다. 본인 계정으로 실행하려면 Azure OpenAI 에
`Cognitive Services OpenAI User`, Cosmos 에 `Cosmos DB Built-in Data Contributor`
역할이 있어야 한다 (session-00 · session-01 Bicep 의 (선택) 사용자 역할 부여).

실행 (apps/api 의 의존성 환경 사용):

    uv run --project apps/api python scripts/seed_cosmos.py

필요 환경변수:
    AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_EMBED_DEPLOYMENT, AZURE_OPENAI_API_VERSION
    COSMOS_ENDPOINT, COSMOS_DATABASE, COSMOS_CHUNKS_CONTAINER
"""

from __future__ import annotations

import asyncio
import os

from azure.cosmos.aio import CosmosClient
from azure.identity.aio import DefaultAzureCredential, get_bearer_token_provider
from openai import AsyncAzureOpenAI

_AOAI_SCOPE = "https://cognitiveservices.azure.com/.default"


def _env(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None:
        raise SystemExit(f"환경변수 {name} 가 필요합니다.")
    return value


def _build_corpus() -> list[tuple[str, str, str]]:
    """학습용 사내 문서 코퍼스 생성 — (doc_id, title, content) 약 120건.

    카테고리 × 항목 조합으로 서로 다른 짧은 문서를 만들어 벡터가 충분히 흩어지게 한다.
    """
    categories = {
        "휴가": ["연차 신청 절차", "반차 사용 규정", "경조사 휴가", "병가 처리", "리프레시 휴가"],
        "보안": ["VPN 접속 방법", "비밀번호 정책", "노트북 분실 신고", "문서 등급 분류", "외부 반출 승인"],
        "근태": ["유연근무제", "재택근무 신청", "초과근무 정산", "출장 비용 처리", "지각 처리 기준"],
        "복지": ["식대 지원", "건강검진 안내", "동호회 지원금", "교육비 환급", "경조금 지급"],
        "장비": ["모니터 추가 신청", "소프트웨어 라이선스", "사내 와이파이", "회의실 예약", "프린터 사용"],
    }
    regions = ["본사", "판교 지사", "부산 지사", "대전 지사", "원격"]
    corpus: list[tuple[str, str, str]] = []
    for cat, items in categories.items():
        for item in items:
            for region in regions:
                if len(corpus) >= 120:
                    break
                doc_id = f"{cat}-{item}-{region}".replace(" ", "_")
                title = f"[{cat}] {item} ({region})"
                content = (
                    f"{region} 기준 {cat} 관련 안내입니다. {item} 은 사내 포털에서 신청하며, "
                    f"승인권자는 팀장입니다. 처리 기한과 필요 서류는 {cat} 정책 문서를 따릅니다."
                )
                corpus.append((doc_id, title, content))
    return corpus


async def _embed_all(aoai: AsyncAzureOpenAI, deployment: str, texts: list[str]) -> list[list[float]]:
    """텍스트 묶음을 배치로 임베딩."""
    out: list[list[float]] = []
    batch = 64
    for i in range(0, len(texts), batch):
        resp = await aoai.embeddings.create(model=deployment, input=texts[i : i + batch])
        out.extend(d.embedding for d in resp.data)
    return out


async def main() -> None:
    credential = DefaultAzureCredential()
    aoai = AsyncAzureOpenAI(
        azure_endpoint=_env("AZURE_OPENAI_ENDPOINT"),
        azure_ad_token_provider=get_bearer_token_provider(credential, _AOAI_SCOPE),
        api_version=_env("AZURE_OPENAI_API_VERSION", "2024-08-01-preview"),
    )
    embed_deployment = _env("AZURE_OPENAI_EMBED_DEPLOYMENT", "text-embedding-3-large")

    corpus = _build_corpus()
    print(f"코퍼스 {len(corpus)} 건 임베딩 중...")
    embeddings = await _embed_all(aoai, embed_deployment, [c[2] for c in corpus])
    await aoai.close()

    print("Cosmos DB chunks 컨테이너에 적재 중...")
    client = CosmosClient(url=_env("COSMOS_ENDPOINT"), credential=credential)
    db = client.get_database_client(_env("COSMOS_DATABASE", "appdb"))
    container = db.get_container_client(_env("COSMOS_CHUNKS_CONTAINER", "chunks"))
    for (doc_id, title, content), emb in zip(corpus, embeddings, strict=True):
        await container.upsert_item(
            {"id": doc_id, "doc_id": doc_id, "title": title, "content": content, "embedding": emb}
        )
    await client.close()
    await credential.close()

    print(f"완료 — {len(corpus)} 건 적재.")


if __name__ == "__main__":
    asyncio.run(main())
