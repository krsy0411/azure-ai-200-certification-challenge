#!/usr/bin/env python
"""scripts/seed_both.py — Cosmos DB vs PostgreSQL pgvector 비교 (session-02).

같은 문서 셋을 Cosmos DB 와 PostgreSQL pgvector 양쪽에 임베드 + 적재한 뒤, 동일한
질문 셋으로 검색해 두 백엔드의 P50 / P95 latency 와 recall@5 를 측정해 markdown 표로
출력한다.

추가로 PostgreSQL 은 `hnsw.ef_search` 를 높은 값부터 낮은 값까지 바꿔가며 측정해,
ef_search 를 낮추면 검색이 빨라지지만 recall 이 떨어지는 ANN 트레이드오프를 드러낸다.

인증 — Cosmos · PostgreSQL · Azure OpenAI 모두 DefaultAzureCredential (Entra ID 토큰).
키를 코드에 두지 않는다.

실행 (apps/api 의 의존성 환경 사용):

    uv run --project apps/api python scripts/seed_both.py

필요 환경변수:
    AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_EMBED_DEPLOYMENT, AZURE_OPENAI_API_VERSION
    COSMOS_ENDPOINT, COSMOS_DATABASE, COSMOS_CHUNKS_CONTAINER
    POSTGRES_HOST, POSTGRES_DATABASE, POSTGRES_USER, (POSTGRES_PORT 기본 5432)
"""

from __future__ import annotations

import asyncio
import math
import os
import statistics
import time

import psycopg
from azure.cosmos.aio import CosmosClient
from azure.identity.aio import DefaultAzureCredential, get_bearer_token_provider
from openai import AsyncAzureOpenAI
from pgvector import HalfVector
from pgvector.psycopg import register_vector_async

_AOAI_SCOPE = "https://cognitiveservices.azure.com/.default"
_PG_AAD_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"

TOP_K = 5
# PostgreSQL 에서 측정할 hnsw.ef_search 값들 — 높은 값(정확) → 낮은 값(빠르지만 recall 저하).
EF_SEARCH_VALUES = [100, 20, 4]


def _env(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None:
        raise SystemExit(f"환경변수 {name} 가 필요합니다.")
    return value


def _build_corpus() -> list[tuple[str, str, str]]:
    """학습용 사내 문서 코퍼스 생성 — (doc_id, title, content) 약 120건.

    카테고리 × 항목 조합으로 서로 다른 짧은 문서를 만들어 벡터가 충분히 흩어지게 한다.
    """
    categories = {
        "휴가": ["연차 신청 절차", "반차 사용 규정", "경조사 휴가", "병가 처리", "리프레시 휴가"],
        "보안": ["VPN 접속 방법", "비밀번호 정책", "노트북 분실 신고", "문서 등급 분류", "외부 반출 승인"],
        "근태": ["유연근무제", "재택근무 신청", "초과근무 정산", "출장 비용 처리", "지각 처리 기준"],
        "복지": ["식대 지원", "건강검진 안내", "동호회 지원금", "교육비 환급", "경조금 지급"],
        "장비": ["모니터 추가 신청", "소프트웨어 라이선스", "사내 와이파이", "회의실 예약", "프린터 사용"],
    }
    regions = ["본사", "판교 지사", "부산 지사", "원격"]
    corpus: list[tuple[str, str, str]] = []
    for cat, items in categories.items():
        for item in items:
            for region in regions:
                if len(corpus) >= 120:
                    break
                doc_id = f"{cat}-{item}-{region}".replace(" ", "_")
                title = f"[{cat}] {item} ({region})"
                content = (
                    f"{region} 기준 {cat} 관련 안내입니다. {item} 은 사내 포털에서 신청하며, "
                    f"승인권자는 팀장입니다. 처리 기한과 필요 서류는 {cat} 정책 문서를 따릅니다."
                )
                corpus.append((doc_id, title, content))
    return corpus


QUERIES = [
    "연차는 어떻게 신청하나요",
    "재택근무 하려면 어떤 절차가 필요해",
    "노트북을 잃어버렸을 때 신고 방법",
    "건강검진 일정 알려줘",
    "회의실 예약은 어디서 하나요",
    "초과근무 수당 정산 기준",
    "VPN 접속이 안 될 때",
    "교육비 환급 받는 법",
]


def _cosine_distance(a: list[float], b: list[float]) -> float:
    """코사인 거리 (0 = 동일). pgvector 의 <=> 와 동일 정의."""
    dot = sum(x * y for x, y in zip(a, b, strict=True))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0 or nb == 0:
        return 1.0
    return 1.0 - dot / (na * nb)


def _percentile(values: list[float], pct: float) -> float:
    """단순 백분위 (정렬 후 보간 없이 nearest-rank)."""
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, int(math.ceil(pct / 100.0 * len(ordered))) - 1)
    return ordered[max(0, idx)]


def _recall_at_k(got: list[str], truth: list[str]) -> float:
    """got 의 상위 k 가 정답 top-k 를 얼마나 포함하는지 (교집합 / k)."""
    if not truth:
        return 0.0
    return len(set(got) & set(truth)) / len(truth)


async def _embed_all(aoai: AsyncAzureOpenAI, deployment: str, texts: list[str]) -> list[list[float]]:
    """텍스트 묶음을 배치로 임베딩."""
    out: list[list[float]] = []
    batch = 64
    for i in range(0, len(texts), batch):
        resp = await aoai.embeddings.create(model=deployment, input=texts[i : i + batch])
        out.extend(d.embedding for d in resp.data)
    return out


async def _load_cosmos(
    credential: DefaultAzureCredential,
    corpus: list[tuple[str, str, str]],
    embeddings: list[list[float]],
) -> None:
    client = CosmosClient(url=_env("COSMOS_ENDPOINT"), credential=credential)
    db = client.get_database_client(_env("COSMOS_DATABASE", "appdb"))
    container = db.get_container_client(_env("COSMOS_CHUNKS_CONTAINER", "chunks"))
    for (doc_id, title, content), emb in zip(corpus, embeddings, strict=True):
        await container.upsert_item(
            {"id": doc_id, "doc_id": doc_id, "title": title, "content": content, "embedding": emb}
        )
    await client.close()


async def _search_cosmos(
    credential: DefaultAzureCredential, query_emb: list[float]
) -> list[str]:
    client = CosmosClient(url=_env("COSMOS_ENDPOINT"), credential=credential)
    db = client.get_database_client(_env("COSMOS_DATABASE", "appdb"))
    container = db.get_container_client(_env("COSMOS_CHUNKS_CONTAINER", "chunks"))
    sql = (
        "SELECT TOP @topK c.doc_id, VectorDistance(c.embedding, @e) AS d "
        "FROM c ORDER BY VectorDistance(c.embedding, @e)"
    )
    params = [{"name": "@topK", "value": TOP_K}, {"name": "@e", "value": query_emb}]
    got = [item["doc_id"] async for item in container.query_items(query=sql, parameters=params)]
    await client.close()
    return got


def _pg_conninfo(token: str) -> str:
    return (
        f"host={_env('POSTGRES_HOST')} "
        f"port={os.environ.get('POSTGRES_PORT', '5432')} "
        f"dbname={_env('POSTGRES_DATABASE', 'appdb')} "
        f"user={_env('POSTGRES_USER')} "
        f"password={token} "
        f"sslmode=require"
    )


async def _load_pg(
    credential: DefaultAzureCredential,
    corpus: list[tuple[str, str, str]],
    embeddings: list[list[float]],
) -> None:
    """extension · 테이블 · HNSW 인덱스를 idempotent 하게 만든 뒤 적재."""
    token = (await credential.get_token(_PG_AAD_SCOPE)).token
    # 첫 연결은 register 없이 — vector extension 이 아직 없을 수 있으므로 (chicken-and-egg).
    async with await psycopg.AsyncConnection.connect(_pg_conninfo(token), autocommit=True) as conn:
        await conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
        await conn.execute(
            "CREATE TABLE IF NOT EXISTS chunks ("
            "id TEXT PRIMARY KEY, doc_id TEXT NOT NULL, title TEXT, content TEXT NOT NULL, "
            "embedding halfvec(3072) NOT NULL, metadata JSONB, created_at TIMESTAMPTZ DEFAULT NOW())"
        )
        await conn.execute(
            "CREATE INDEX IF NOT EXISTS chunks_embedding_hnsw "
            "ON chunks USING hnsw (embedding halfvec_cosine_ops) WITH (m = 16, ef_construction = 64)"
        )
        # extension 이 생긴 뒤에 register — 이제 halfvec 어댑터를 쓸 수 있다.
        await register_vector_async(conn)
        for (doc_id, title, content), emb in zip(corpus, embeddings, strict=True):
            await conn.execute(
                "INSERT INTO chunks (id, doc_id, title, content, embedding) "
                "VALUES (%s, %s, %s, %s, %s) ON CONFLICT (id) DO UPDATE SET embedding = EXCLUDED.embedding",
                (doc_id, doc_id, title, content, HalfVector(emb)),
            )


async def _search_pg(
    credential: DefaultAzureCredential, query_emb: list[float], ef_search: int
) -> list[str]:
    token = (await credential.get_token(_PG_AAD_SCOPE)).token
    async with await psycopg.AsyncConnection.connect(_pg_conninfo(token)) as conn:
        await register_vector_async(conn)
        async with conn.transaction():
            await conn.execute("SET LOCAL hnsw.ef_search = %s", (ef_search,))
            cur = await conn.execute(
                "SELECT doc_id, embedding <=> %s AS d FROM chunks ORDER BY d LIMIT %s",
                (HalfVector(query_emb), TOP_K),
            )
            rows = await cur.fetchall()
    return [r[0] for r in rows]


def _print_row(label: str, docs: int, latencies: list[float], recalls: list[float]) -> None:
    p50 = _percentile(latencies, 50) * 1000
    p95 = _percentile(latencies, 95) * 1000
    recall = statistics.mean(recalls) if recalls else 0.0
    print(f"| {label:<16} | {docs:>4} | {p50:>8.1f} | {p95:>8.1f} | {recall:>8.2f} |")


async def main() -> None:
    credential = DefaultAzureCredential()
    # 임베딩은 토큰 provider 로 — 매 요청 토큰 자동 부착.
    aoai = AsyncAzureOpenAI(
        azure_endpoint=_env("AZURE_OPENAI_ENDPOINT"),
        azure_ad_token_provider=get_bearer_token_provider(credential, _AOAI_SCOPE),
        api_version=_env("AZURE_OPENAI_API_VERSION", "2024-08-01-preview"),
    )
    embed_deployment = _env("AZURE_OPENAI_EMBED_DEPLOYMENT", "text-embedding-3-large")

    corpus = _build_corpus()
    print(f"코퍼스 {len(corpus)} 건 임베딩 중...")
    doc_embeddings = await _embed_all(aoai, embed_deployment, [c[2] for c in corpus])
    query_embeddings = await _embed_all(aoai, embed_deployment, QUERIES)
    await aoai.close()

    # 정답 top-k — 전체 코퍼스에 대한 정확 코사인 검색 (브루트포스).
    doc_ids = [c[0] for c in corpus]
    truth: list[list[str]] = []
    for q_emb in query_embeddings:
        dists = sorted(
            ((_cosine_distance(q_emb, d_emb), doc_ids[i]) for i, d_emb in enumerate(doc_embeddings)),
            key=lambda t: t[0],
        )
        truth.append([doc_id for _, doc_id in dists[:TOP_K]])

    print("Cosmos DB · PostgreSQL 적재 중...")
    await _load_cosmos(credential, corpus, doc_embeddings)
    await _load_pg(credential, corpus, doc_embeddings)

    print()
    print(f"| {'backend':<16} | docs | p50 (ms) | p95 (ms) | recall@5 |")
    print(f"|{'-' * 18}|------|----------|----------|----------|")

    # Cosmos
    lat: list[float] = []
    rec: list[float] = []
    for q_emb, gt in zip(query_embeddings, truth, strict=True):
        t0 = time.perf_counter()
        got = await _search_cosmos(credential, q_emb)
        lat.append(time.perf_counter() - t0)
        rec.append(_recall_at_k(got, gt))
    _print_row("cosmos", len(corpus), lat, rec)

    # PostgreSQL — ef_search 값별
    for ef in EF_SEARCH_VALUES:
        lat = []
        rec = []
        for q_emb, gt in zip(query_embeddings, truth, strict=True):
            t0 = time.perf_counter()
            got = await _search_pg(credential, q_emb, ef)
            lat.append(time.perf_counter() - t0)
            rec.append(_recall_at_k(got, gt))
        _print_row(f"pg (ef={ef})", len(corpus), lat, rec)

    await credential.close()


if __name__ == "__main__":
    asyncio.run(main())
