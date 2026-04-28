-- Phase 5 부트스트랩 SQL — lifespan 시작 시 1회 실행 (idempotent).
--
-- 학습 경로 모듈 1 단원 4 "스키마 만들기 및 관리" + 모듈 2 단원 2 "pgvector 임베딩 저장" 충족.
--
-- 결정 ④ a) 같은 데이터를 두 테이블 (chunks_hnsw / chunks_ivf) 에 각각 적재해 인덱스 종류별 비교.
-- pgvector 는 단일 컬럼에 여러 인덱스를 만들 수는 있지만 query planner 가 한 인덱스만 선택하므로,
-- 깔끔한 비교를 위해 테이블 분리.
--
-- 차원 = 3072 (text-embedding-3-large). vector(2000) 한계 회피 위해 halfvec 사용.
-- halfvec_cosine_ops 는 pgvector 0.7+ (Azure flex 의 0.8 GA 기준 사용 가능).

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS workspaces (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS documents (
    id            TEXT PRIMARY KEY,
    workspace_id  TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    title         TEXT,
    source_url    TEXT,
    status        TEXT NOT NULL DEFAULT 'ready',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_documents_workspace ON documents (workspace_id);

-- ---- chunks_hnsw -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS chunks_hnsw (
    id            TEXT PRIMARY KEY,
    workspace_id  TEXT NOT NULL,
    document_id   TEXT NOT NULL,
    ordinal       INT  NOT NULL,
    text          TEXT NOT NULL,
    embedding     halfvec(3072) NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chunks_hnsw_workspace ON chunks_hnsw (workspace_id);
CREATE INDEX IF NOT EXISTS idx_chunks_hnsw_doc      ON chunks_hnsw (document_id);
CREATE INDEX IF NOT EXISTS idx_chunks_hnsw_vec
    ON chunks_hnsw USING hnsw (embedding halfvec_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- ---- chunks_ivf ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chunks_ivf (
    id            TEXT PRIMARY KEY,
    workspace_id  TEXT NOT NULL,
    document_id   TEXT NOT NULL,
    ordinal       INT  NOT NULL,
    text          TEXT NOT NULL,
    embedding     halfvec(3072) NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chunks_ivf_workspace ON chunks_ivf (workspace_id);
CREATE INDEX IF NOT EXISTS idx_chunks_ivf_doc      ON chunks_ivf (document_id);
CREATE INDEX IF NOT EXISTS idx_chunks_ivf_vec
    ON chunks_ivf USING ivfflat (embedding halfvec_cosine_ops)
    WITH (lists = 100);
