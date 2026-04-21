from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter()


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    workspace_id: str | None = None


class ChatResponse(BaseModel):
    reply: str
    model: str = "stub"


@router.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest) -> ChatResponse:
    # Phase 1 stub: echoes input. Phase 4+ will orchestrate Cosmos retrieval + Azure OpenAI.
    return ChatResponse(reply=f"[stub] {req.message}", model="stub")
