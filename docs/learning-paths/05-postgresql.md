# Phase 5 — Azure Database for PostgreSQL로 AI 솔루션 개발

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-database-postgresql/ (3 모듈)

## 학습 경로 구성

1. **PostgreSQL 빌드 · 쿼리** — 스키마 설계, 효율적 SQL, Python + Microsoft Entra 인증.
2. **pgvector 벡터 검색 구현** — 포함 저장, 거리 메트릭(L2, 코사인, 내적), RAG 검색 패턴.
3. **벡터 검색 최적화** — 매개변수 튜닝, HNSW/IVFFlat 인덱스 선택, 효율적 데이터 레이아웃, 대용량 스케일링, 연결 풀링.

## 이 프로젝트에서의 적용

- 관계형 데이터(사용자, 워크스페이스, 감사 로그)의 **주 저장소**
- 동일 문서 청크를 PostgreSQL + pgvector에도 적재해 **Cosmos vs PG 벡터 검색 성능 비교**
- Entra ID 토큰 인증 (`azure-identity` → 토큰 → `psycopg` password)
- PgBouncer 대신 **flexible server 기본 커넥션 풀링** 사용 여부 비교

## 스키마 초안

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE workspaces (
  id           UUID PRIMARY KEY,
  name         TEXT NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE documents (
  id            UUID PRIMARY KEY,
  workspace_id  UUID REFERENCES workspaces(id),
  title         TEXT NOT NULL,
  source_url    TEXT,
  status        TEXT NOT NULL DEFAULT 'pending',
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE chunks (
  id            UUID PRIMARY KEY,
  document_id   UUID REFERENCES documents(id) ON DELETE CASCADE,
  ordinal       INT NOT NULL,
  text          TEXT NOT NULL,
  embedding     vector(3072),
  tokens        INT
);

-- HNSW 인덱스 (쿼리 우선)
CREATE INDEX ON chunks USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
```

## 비교 실험 기록지

| 항목 | Cosmos DB | PostgreSQL + pgvector |
|---|---|---|
| 상위 5 쿼리 p50 | TBD | TBD |
| 쓰기 처리량 | TBD | TBD |
| 운영 복잡도 | TBD | TBD |
| 비용 (월) | TBD | TBD |

## 체크리스트

- [ ] PostgreSQL Flexible Server 생성 + Entra 관리자 연결
- [ ] pgvector 확장 활성화
- [ ] 테이블 스키마 + HNSW 인덱스 생성
- [ ] psycopg + `DefaultAzureCredential` 토큰 인증 검증
- [ ] 동일 데이터셋 적재 후 벡터 검색 벤치마크 기록
