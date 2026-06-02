"""비동기 인제스션 Functions (session-04) — Azure Functions Python v2.

흐름: Blob 업로드 → Event Grid(System Topic) → Service Bus(ingest-queue) → 본 함수.

- on_ingest_message (Service Bus queue trigger)
  큐 메시지(EventGrid BlobCreated 이벤트)에서 Blob URL 추출 → Managed Identity 로 다운로드
  → 청크 분할 → Azure OpenAI 배치 임베드 → Cosmos DB + PostgreSQL 양쪽 upsert.
  처리 실패 시 Service Bus 재시도(max delivery 5) 후 DLQ.

- on_cosmos_change (Cosmos DB change feed trigger)
  chunks 컨테이너에 새 chunk 가 들어오면 doc_id 별 개수를 doc_stats 컨테이너에 집계.
  lease container 는 Bicep 으로 사전 생성된 것을 참조한다 (자동 생성 silent-fail 회피).

인증은 전부 User Assigned Managed Identity (DefaultAzureCredential, AZURE_CLIENT_ID).
"""

import json
import logging
import os
import struct
from urllib.parse import urlparse

import azure.functions as func
import psycopg
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.storage.blob import BlobClient
from openai import AzureOpenAI
from pgvector import HalfVector
from pgvector.psycopg import register_vector

app = func.FunctionApp()

# --- 공용 자격/클라이언트 (콜드 스타트 시 1회 생성) ---
_credential = DefaultAzureCredential()
_PG_AAD_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"
_AOAI_SCOPE = "https://cognitiveservices.azure.com/.default"

_CHUNK_CHARS = 1500
_CHUNK_OVERLAP = 200


def _aoai() -> AzureOpenAI:
    return AzureOpenAI(
        azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
        azure_ad_token_provider=get_bearer_token_provider(_credential, _AOAI_SCOPE),
        api_version=os.environ.get("AZURE_OPENAI_API_VERSION", "2024-08-01-preview"),
    )


def _cosmos_container(name: str):
    client = CosmosClient(os.environ["COSMOS_ENDPOINT"], credential=_credential)
    db = client.get_database_client(os.environ.get("COSMOS_DATABASE", "appdb"))
    return db.get_container_client(name)


def _chunk_text(text: str) -> list[str]:
    """단순 문자 기반 청크 분할 (약 1500자, overlap 200). 학습용 단순화."""
    text = text.strip()
    if not text:
        return []
    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = start + _CHUNK_CHARS
        chunks.append(text[start:end])
        start = end - _CHUNK_OVERLAP
    return chunks


def _extract_text(blob_name: str, raw: bytes) -> str:
    """Markdown·텍스트는 그대로 디코드. PDF 는 pypdf 로 텍스트 추출."""
    if blob_name.lower().endswith(".pdf"):
        import io

        from pypdf import PdfReader

        reader = PdfReader(io.BytesIO(raw))
        return "\n".join(page.extract_text() or "" for page in reader.pages)
    return raw.decode("utf-8", errors="ignore")


def _doc_id_from_blob(blob_name: str) -> str:
    """policy/sample-policy.md → sample-policy."""
    base = blob_name.rsplit("/", 1)[-1]
    return base.rsplit(".", 1)[0]


def _to_float32_bytes(vec: list[float]) -> bytes:
    return struct.pack(f"<{len(vec)}f", *vec)


def _upsert_cosmos(doc_id: str, chunks: list[str], embeddings: list[list[float]]) -> None:
    container = _cosmos_container("chunks")
    for i, (content, emb) in enumerate(zip(chunks, embeddings, strict=True)):
        container.upsert_item(
            {
                "id": f"{doc_id}-{i}",
                "doc_id": doc_id,
                "title": doc_id,
                "content": content,
                "embedding": emb,
            }
        )


def _upsert_pg(doc_id: str, chunks: list[str], embeddings: list[list[float]]) -> None:
    token = _credential.get_token(_PG_AAD_SCOPE).token
    conninfo = (
        f"host={os.environ['POSTGRES_HOST']} port=5432 "
        f"dbname={os.environ.get('POSTGRES_DATABASE', 'appdb')} "
        f"user={os.environ['POSTGRES_USER']} password={token} sslmode=require"
    )
    with psycopg.connect(conninfo) as conn:
        register_vector(conn)
        with conn.cursor() as cur:
            for i, (content, emb) in enumerate(zip(chunks, embeddings, strict=True)):
                cur.execute(
                    "INSERT INTO chunks (id, doc_id, title, content, embedding) "
                    "VALUES (%s, %s, %s, %s, %s) "
                    "ON CONFLICT (id) DO UPDATE SET content = EXCLUDED.content, "
                    "embedding = EXCLUDED.embedding",
                    (f"{doc_id}-{i}", doc_id, doc_id, content, HalfVector(emb)),
                )


@app.service_bus_queue_trigger(
    arg_name="msg", queue_name="ingest-queue", connection="ServiceBusConnection"
)
def on_ingest_message(msg: func.ServiceBusMessage) -> None:
    """Blob 업로드 이벤트 → 청크·임베드·양쪽 적재."""
    event = json.loads(msg.get_body().decode("utf-8"))
    # Event Grid 가 배열로 보낼 수 있으므로 단일 이벤트로 정규화
    if isinstance(event, list):
        event = event[0]
    blob_url = event["data"]["url"]

    blob_name = urlparse(blob_url).path.split("/", 2)[-1]
    doc_id = _doc_id_from_blob(blob_name)

    raw = BlobClient.from_blob_url(blob_url, credential=_credential).download_blob().readall()
    text = _extract_text(blob_name, raw)
    chunks = _chunk_text(text)
    if not chunks:
        logging.warning("[on_ingest_message] %s — 추출된 텍스트 없음, skip", blob_name)
        return

    client = _aoai()
    deployment = os.environ.get("AZURE_OPENAI_EMBED_DEPLOYMENT", "text-embedding-3-large")
    embeddings = [d.embedding for d in client.embeddings.create(model=deployment, input=chunks).data]

    _upsert_cosmos(doc_id, chunks, embeddings)
    _upsert_pg(doc_id, chunks, embeddings)
    logging.info("[on_ingest_message] processed %s → %d chunks", blob_name, len(chunks))


@app.cosmos_db_trigger(
    arg_name="docs",
    connection="CosmosDbConnection",
    database_name="appdb",
    container_name="chunks",
    lease_container_name="leases",
    create_lease_container_if_not_exists=False,
)
def on_cosmos_change(docs: func.DocumentList) -> None:
    """새 chunk 등장 시 doc_id 별 누적 개수를 doc_stats 컨테이너에 집계."""
    if not docs:
        return
    counts: dict[str, int] = {}
    for doc in docs:
        doc_id = doc.get("doc_id")
        if doc_id:
            counts[doc_id] = counts.get(doc_id, 0) + 1

    stats = _cosmos_container("doc_stats")
    for doc_id, delta in counts.items():
        try:
            item = stats.read_item(item=doc_id, partition_key=doc_id)
            item["chunk_count"] = item.get("chunk_count", 0) + delta
        except Exception:  # noqa: BLE001 — 없으면 신규 생성
            item = {"id": doc_id, "doc_id": doc_id, "chunk_count": delta}
        stats.upsert_item(item)
    logging.info("[on_cosmos_change] %d doc_id 집계 갱신", len(counts))