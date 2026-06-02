"""RAG 파이프라인 조립 — embed → retrieve → generate.

session-01 의 RAG MVP 는 다음 3 단계로 동작한다.

1. **embed** — 사용자 질문을 `text-embedding-3-large` 로 임베딩
2. **retrieve** — Cosmos DB 벡터 검색으로 가장 가까운 chunk top-k 를 가져옴
3. **generate** — 검색된 chunk 의 본문을 컨텍스트로 묶어 `gpt-4o-mini` 에 전달, 답변 생성

검색 백엔드는 `VectorStore` Protocol 로 추상화되어 있어, session-02 에서
`STORE_BACKEND` 환경변수로 Cosmos DB / PostgreSQL pgvector 를 전환할 수 있다.

session-03 에서 임베딩 직후 시맨틱 캐시 lookup 이 추가됐다 — hit 면 retrieve·generate 를
건너뛰고 캐시된 응답을 즉시 반환한다. `cache` 가 None 이면 (cache_enabled=false) 캐시 계층은
없는 것처럼 동작한다.

후속 세션에서 이 파이프라인이 확장된다.
- session-05 — 피처 플래그로 캐시 ON/OFF 토글
- session-06 — 각 단계에 OpenTelemetry 커스텀 span 부여
"""

from openai import AsyncAzureOpenAI

from ..cache.semantic import SemanticCache
from ..clients.aoai import chat_with_context, embed_text
from ..models import ChatResponse, Source
from ..settings import Settings
from ..stores.base import VectorStore


async def run_rag_chain(
    question: str,
    aoai_client: AsyncAzureOpenAI,
    store: VectorStore,
    settings: Settings,
    cache: SemanticCache | None = None,
) -> ChatResponse:
    """질문 한 건을 RAG 파이프라인 전체에 통과시켜 답변과 출처를 반환."""

    # 1) embed — 질문을 임베딩 벡터로 변환
    query_embedding = await embed_text(aoai_client, settings, question)

    # 1.5) 시맨틱 캐시 lookup — hit 면 RAG 를 우회해 즉시 반환
    if cache is not None:
        cached = await cache.lookup(query_embedding)
        if cached is not None:
            return cached

    # 2) retrieve — 선택된 벡터 스토어에서 가장 가까운 chunk 메타데이터 검색
    sources: list[Source] = await store.vector_search(
        query_embedding,
        top_k=settings.retrieval_top_k,
    )

    if not sources:
        return ChatResponse(
            answer="관련 문서를 찾을 수 없습니다.",
            sources=[],
        )

    # 검색된 chunk 들의 본문을 가져와 컨텍스트로 묶음
    contents: list[str] = []
    for source in sources:
        content = await store.fetch_content(source.doc_id)
        if content:
            heading = source.title or source.doc_id
            contents.append(f"## {heading}\n{content}")
    context = "\n\n".join(contents)

    # 3) generate — gpt-4o-mini 가 컨텍스트 기반 답변 생성
    answer = await chat_with_context(aoai_client, settings, question, context)
    response = ChatResponse(answer=answer, sources=sources)

    # 4) 캐시 store — miss 였던 응답을 시맨틱 캐시에 저장 (다음 paraphrase 호출이 hit)
    if cache is not None:
        await cache.store(query_embedding, question, response)

    return response
