"""환경변수 → 타입 안전 설정 객체.

Azure Container Apps 의 환경변수 (Bicep envVars 로 주입) 를 Pydantic Settings 로 읽어
모듈 전반에서 type-safe 하게 사용한다. 본 모듈에는 시크릿이 평문으로 들어오지 않는다 —
모든 자원 호출은 DefaultAzureCredential 토큰 인증을 사용한다.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """본 워크샵의 모든 환경변수를 한 객체로 모은다."""

    # Azure OpenAI
    azure_openai_endpoint: str
    azure_openai_chat_deployment: str = "gpt-4o-mini"
    azure_openai_embed_deployment: str = "text-embedding-3-large"
    azure_openai_api_version: str = "2024-08-01-preview"

    # Cosmos DB
    cosmos_endpoint: str
    cosmos_database: str = "appdb"
    cosmos_chunks_container: str = "chunks"

    # Application Insights (OpenTelemetry 자동 계측이 사용)
    applicationinsights_connection_string: str | None = None

    # User Assigned Managed Identity client ID — Azure Container Apps 안에서
    # DefaultAzureCredential 이 어떤 UAMI 를 쓸지 결정. 로컬 개발 시에는 비어 있어도
    # az login 자격이 자동으로 사용된다.
    azure_client_id: str | None = None

    # RAG 검색 파라미터
    retrieval_top_k: int = 5

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """앱 시작 시 한 번만 호출되도록 캐싱."""
    return Settings()  # type: ignore[call-arg]
