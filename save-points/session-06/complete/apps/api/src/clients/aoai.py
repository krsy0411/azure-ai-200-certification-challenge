"""Azure OpenAI 클라이언트 — DefaultAzureCredential 기반 토큰 인증.

본 모듈은 본 워크샵의 핵심 보안 원칙을 코드로 표현한다:
**키를 코드 · 디스크 · git 어디에도 두지 않고 Entra ID 가 발급한 단명 토큰만 사용한다.**

session-01 docs 의 `.env` vs Key Vault + Managed Identity 비교 박스의 "방식 B" 가
이 모듈 그대로 동작 형태다.
"""

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AsyncAzureOpenAI

from ..settings import Settings


def build_aoai_client(settings: Settings) -> AsyncAzureOpenAI:
    """Azure OpenAI 비동기 클라이언트 생성.

    인증 흐름:
    1. `DefaultAzureCredential` 이 환경별로 적절한 자격을 자동 선택
       - Azure Container Apps 안: `AZURE_CLIENT_ID` 가 가리키는 User Assigned Managed Identity
       - 로컬 개발: `az login` 자격
    2. `get_bearer_token_provider` 가 `cognitiveservices.azure.com` 토큰을 매 요청마다 발급
    3. `AsyncAzureOpenAI` 의 `azure_ad_token_provider` 가 이 토큰을 Authorization 헤더에 자동 부착

    결과 — 코드에 API 키가 등장하지 않는다.
    """
    credential = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(
        credential,
        "https://cognitiveservices.azure.com/.default",
    )
    return AsyncAzureOpenAI(
        azure_endpoint=settings.azure_openai_endpoint,
        azure_ad_token_provider=token_provider,
        api_version=settings.azure_openai_api_version,
    )


async def embed_text(client: AsyncAzureOpenAI, settings: Settings, text: str) -> list[float]:
    """텍스트 한 줄을 임베딩 벡터로 변환.

    `text-embedding-3-large` 는 3072 차원 float32 벡터를 반환한다.
    Cosmos DB `chunks` 컨테이너의 vector policy 차원 (3072) 과 일치한다.
    """
    response = await client.embeddings.create(
        model=settings.azure_openai_embed_deployment,
        input=text,
    )
    return response.data[0].embedding


async def chat_with_context(
    client: AsyncAzureOpenAI,
    settings: Settings,
    question: str,
    context: str,
) -> tuple[str, int, int]:
    """검색된 chunk 컨텍스트와 질문을 받아 `gpt-5-mini` 로 답변 생성.

    프롬프트 전략 — 시스템 메시지로 RAG 규칙을 고정하고, 사용자 메시지에
    `context` 와 `question` 을 분리해 전달한다. 학습용 단순 형태로, 본격 운영
    환경에서는 더 정교한 프롬프트 엔지니어링과 인용 처리가 필요하다.

    반환 — (답변 텍스트, 프롬프트 토큰 수, 컴플리션 토큰 수). 토큰 수는 session-06
    의 커스텀 span/메트릭에서 사용한다.
    """
    system_prompt = (
        "당신은 사내 문서를 근거로 답변하는 AI 어시스턴트입니다. "
        "주어진 컨텍스트만을 사용해 한국어로 간결하게 답변하세요. "
        "컨텍스트에 답이 없다면 '관련 문서를 찾을 수 없습니다' 라고 답하세요."
    )
    user_prompt = f"# 컨텍스트\n{context}\n\n# 질문\n{question}"

    response = await client.chat.completions.create(
        model=settings.azure_openai_chat_deployment,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        # gpt-5 계열(reasoning 모델)은 temperature 커스텀과 max_tokens 를 지원하지 않는다.
        # temperature 는 기본값(1)만 허용되므로 생략하고, 토큰 상한은 max_completion_tokens 로 준다.
        # reasoning 토큰이 출력 토큰과 함께 차감되므로 여유 있게 둔다.
        max_completion_tokens=2048,
    )
    usage = response.usage
    prompt_tokens = usage.prompt_tokens if usage else 0
    completion_tokens = usage.completion_tokens if usage else 0
    return (response.choices[0].message.content or "", prompt_tokens, completion_tokens)
