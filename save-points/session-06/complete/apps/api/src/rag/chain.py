"""RAG 파이프라인 조립 — embed → retrieve → generate.

session-01 의 RAG MVP 는 다음 3 단계로 동작한다.

1. **embed** — 사용자 질문을 `text-embedding-3-large` 로 임베딩
2. **retrieve** — Cosmos DB 벡터 검색으로 가장 가까운 chunk top-k 를 가져옴
3. **generate** — 검색된 chunk 의 본문을 컨텍스트로 묶어 `gpt-5-mini` 에 전달, 답변 생성

검색 백엔드는 `VectorStore` Protocol 로 추상화되어 있어, session-02 에서
`STORE_BACKEND` 환경변수로 Cosmos DB / PostgreSQL pgvector 를 전환할 수 있다.

session-03 에서 임베딩 직후 시맨틱 캐시 lookup 이 추가됐다 — hit 면 retrieve·generate 를
건너뛰고 캐시된 응답을 즉시 반환한다. `cache` 가 None 이면 (cache_enabled=false) 캐시 계층은
없는 것처럼 동작한다.

session-06 에서 retrieve · generate 단계에 커스텀 OpenTelemetry span 과 토큰/캐시
메트릭이 부여됐다 (자동 request span 의 자식으로 중첩).
"""

from openai import AsyncAzureOpenAI

from ..cache.semantic import SemanticCache
from ..clients.aoai import chat_with_context, embed_text
from ..models import ChatResponse, Source
from ..observability.spans import rag_span, record_cache, record_tokens
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

    # 1.5) 시맨틱 캐시 lookup — hit 면 RAG 를 우회해 즉시 반환. 결과를 메트릭으로 발행.
    if cache is not None:
        cached = await cache.lookup(query_embedding)
        record_cache(cached is not None)
        if cached is not None:
            return cached

    # 2) retrieve — 선택된 벡터 스토어에서 가장 가까운 chunk 메타데이터 검색
    with rag_span("rag.retrieve") as span:
        sources: list[Source] = await store.vector_search(
            query_embedding,
            top_k=settings.retrieval_top_k,
        )
        span.set_attribute("retrieval.count", len(sources))

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

    # 3) generate — gpt-5-mini 가 컨텍스트 기반 답변 생성. 토큰 수를 span/메트릭에 기록.
    with rag_span("rag.generate") as span:
        answer, prompt_tokens, completion_tokens = await chat_with_context(
            aoai_client, settings, question, context
        )
        span.set_attribute("tokens.prompt", prompt_tokens)
        span.set_attribute("tokens.completion", completion_tokens)
        record_tokens(prompt_tokens, completion_tokens)
    response = ChatResponse(answer=answer, sources=sources)

    # 4) 캐시 store — miss 였던 응답을 시맨틱 캐시에 저장 (다음 paraphrase 호출이 hit)
    if cache is not None:
        await cache.store(query_embedding, question, response)

    return response
