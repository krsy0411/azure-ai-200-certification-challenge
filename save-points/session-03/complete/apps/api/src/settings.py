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
    azure_openai_chat_deployment: str = "gpt-5-mini"
    azure_openai_embed_deployment: str = "text-embedding-3-large"
    azure_openai_api_version: str = "2024-08-01-preview"

    # 벡터 스토어 백엔드 선택 — "cosmos" (session-01) | "pg" (session-02)
    store_backend: str = "cosmos"

    # Cosmos DB
    cosmos_endpoint: str | None = None
    cosmos_database: str = "appdb"
    cosmos_chunks_container: str = "chunks"

    # PostgreSQL pgvector (session-02). store_backend=pg 일 때만 사용.
    postgres_host: str | None = None
    postgres_port: int = 5432
    postgres_database: str = "appdb"
    # Entra 인증 사용자 — 로컬 개발은 본인 UPN, 컨테이너는 UAMI 이름.
    postgres_user: str | None = None
    # B1ms 동시 연결 한도(50)를 고려한 클라이언트 풀 최대 크기.
    postgres_pool_max_size: int = 10
    # HNSW 쿼리 정확도. 설정 시 검색 전 SET LOCAL hnsw.ef_search.
    # 낮추면 빠르지만 recall 저하 — 학습용 시연 (None 이면 서버 기본값 40).
    hnsw_ef_search: int | None = None

    # Application Insights (OpenTelemetry 자동 계측이 사용)
    applicationinsights_connection_string: str | None = None

    # User Assigned Managed Identity client ID — Azure Container Apps 안에서
    # DefaultAzureCredential 이 어떤 UAMI 를 쓸지 결정. 로컬 개발 시에는 비어 있어도
    # az login 자격이 자동으로 사용된다.
    azure_client_id: str | None = None

    # RAG 검색 파라미터
    retrieval_top_k: int = 5

    # Managed Redis 시맨틱 캐시 (session-03). cache_enabled=false 면 캐시 계층 비활성.
    cache_enabled: bool = False
    redis_host: str | None = None
    redis_port: int = 10000
    # cosine 유사도 컷오프 — 이 값 이상이면 캐시 hit. RediSearch 는 distance(0~2)를
    # 반환하므로 코드에서 similarity = 1 - distance 로 환산해 비교한다.
    cache_similarity_threshold: float = 0.92
    cache_ttl_seconds: int = 86400  # 24h
    cache_vector_dim: int = 3072  # text-embedding-3-large

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
