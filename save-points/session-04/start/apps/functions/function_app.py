"""비동기 인제스션 Functions (session-04) — Azure Functions Python v2.

흐름: Blob 업로드 → Event Grid(System Topic) → Service Bus(ingest-queue) → 본 함수.

- on_ingest_message (Service Bus queue trigger): Blob URL 추출 → MI 다운로드 → 청크 →
  배치 임베드 → Cosmos + PostgreSQL upsert. 실패 시 재시도(max 5) 후 DLQ.
- on_cosmos_change (Cosmos change feed trigger): doc_id 별 개수를 doc_stats 에 집계.

본 파일은 시작본 stub 이다. anchor 주석을 따라 함수 본체를 채운다.
완성본은 save-points/session-04/complete/ 또는 docs/sessions/04-async-ingestion.md 참고.
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


def _doc_id_from_blob(blob_name: str) -> str:
    base = blob_name.rsplit("/", 1)[-1]
    return base.rsplit(".", 1)[0]


def _to_float32_bytes(vec: list[float]) -> bytes:
    return struct.pack(f"<{len(vec)}f", *vec)


def _extract_text(blob_name: str, raw: bytes) -> str:
    # 힌트: .pdf 면 pypdf.PdfReader 로 페이지 텍스트 추출, 아니면 raw.decode("utf-8").
    raise NotImplementedError("_extract_text 를 구현하세요.")


def _upsert_cosmos(doc_id: str, chunks: list[str], embeddings: list[list[float]]) -> None:
    # 힌트: _cosmos_container("chunks") 에 id=f"{doc_id}-{i}", doc_id, title, content,
    # embedding 으로 upsert_item.
    raise NotImplementedError("_upsert_cosmos 를 구현하세요.")


def _upsert_pg(doc_id: str, chunks: list[str], embeddings: list[list[float]]) -> None:
    # 힌트: Entra 토큰으로 psycopg.connect → register_vector →
    # INSERT ... VALUES (..., HalfVector(emb)) ON CONFLICT (id) DO UPDATE.
    raise NotImplementedError("_upsert_pg 를 구현하세요.")


@app.service_bus_queue_trigger(
    arg_name="msg", queue_name="ingest-queue", connection="ServiceBusConnection"
)
def on_ingest_message(msg: func.ServiceBusMessage) -> None:
    # 힌트: 메시지(EventGrid BlobCreated, 배열일 수 있음)에서 data.url 추출 →
    # blob_name·doc_id 도출 → BlobClient.from_blob_url(.., credential=_credential) 다운로드 →
    # _extract_text → _chunk_text → _aoai().embeddings.create(model, input=chunks) →
    # _upsert_cosmos + _upsert_pg. 빈 텍스트면 skip.
    raise NotImplementedError("on_ingest_message 를 구현하세요.")


@app.cosmos_db_trigger(
    arg_name="docs",
    connection="CosmosDbConnection",
    database_name="appdb",
    container_name="chunks",
    lease_container_name="leases",
    create_lease_container_if_not_exists=False,
)
def on_cosmos_change(docs: func.DocumentList) -> None:
    # 힌트: docs 를 doc_id 별로 카운트 → doc_stats 컨테이너의 chunk_count 를 누적 upsert.
    raise NotImplementedError("on_cosmos_change 를 구현하세요.")