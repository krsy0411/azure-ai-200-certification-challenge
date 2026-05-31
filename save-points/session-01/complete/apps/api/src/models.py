"""API 의 요청 / 응답 Pydantic 모델."""

from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    """`/api/chat` 의 요청 본문."""

    q: str = Field(..., min_length=1, max_length=2000, description="사용자 질문")
    session_id: str | None = Field(
        default=None,
        description="OpenTelemetry span attribute 로 기록할 세션 식별자. 없으면 익명 호출.",
    )


class Source(BaseModel):
    """RAG retrieval 결과의 chunk 메타데이터."""

    doc_id: str
    title: str | None = None
    score: float = Field(..., ge=0.0, le=1.0, description="벡터 유사도 점수 (0 ~ 1)")


class ChatResponse(BaseModel):
    """`/api/chat` 의 응답 본문."""

    answer: str
    sources: list[Source]
