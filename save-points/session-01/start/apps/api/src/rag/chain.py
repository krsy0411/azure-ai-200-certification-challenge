"""RAG 파이프라인 조립 — embed → retrieve → generate.

session-01 의 RAG MVP 는 다음 3 단계로 동작한다.

1. **embed** — 사용자 질문을 `text-embedding-3-large` 로 임베딩
2. **retrieve** — Cosmos DB 벡터 검색으로 가장 가까운 chunk top-k 를 가져옴
3. **generate** — 검색된 chunk 의 본문을 컨텍스트로 묶어 `gpt-4o-mini` 에 전달, 답변 생성

후속 세션에서 이 파이프라인이 확장된다.
- session-03 — 시맨틱 캐시가 1~2 단계 앞에 추가
- session-05 — 피처 플래그로 캐시 ON/OFF 토글
- session-06 — 각 단계에 OpenTelemetry 커스텀 span 부여
"""

from azure.cosmos.aio import ContainerProxy
from openai import AsyncAzureOpenAI

from ..clients.aoai import chat_with_context, embed_text
from ..models import ChatResponse, Source
from ..settings import Settings
from ..stores.cosmos_store import fetch_chunk_content, vector_search


async def run_rag_chain(
    question: str,
    aoai_client: AsyncAzureOpenAI,
    cosmos_container: ContainerProxy,
    settings: Settings,
) -> ChatResponse:
    """질문 한 건을 RAG 파이프라인 전체에 통과시켜 답변과 출처를 반환."""

    # 1) embed — 질문을 임베딩 벡터로 변환하기

    # 2) retrieve — Cosmos 에서 가장 가까운 chunk top-k 를 검색하기
    sources: list[Source] = []  # 채울 자리

    # 검색 결과가 비어있으면 "관련 문서를 찾을 수 없습니다" 응답을 바로 돌려주기
    if not sources:
        return ChatResponse(
            answer="관련 문서를 찾을 수 없습니다.",
            sources=[],
        )

    # 검색된 chunk 들의 본문을 가져와 컨텍스트 문자열로 묶기
    # 힌트: fetch_chunk_content 를 각 source 마다 호출, "## 제목\n본문" 형식으로 join

    # 3) generate — chat_with_context 로 답변 생성하기

    # ChatResponse 반환하기 (answer + sources)
    raise NotImplementedError("RAG 체인 본체를 채워 넣으세요.")
