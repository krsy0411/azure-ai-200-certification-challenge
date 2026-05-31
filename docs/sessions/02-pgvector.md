# session-02 — PostgreSQL pgvector 비교

> **관련 Microsoft Learn 학습 경로**
>
> - [Develop AI solutions with Azure Database for PostgreSQL](https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-database-postgresql/)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [session-00](./00-setup.md), [session-01](./01-rag-mvp.md) 완료 — Resource Group · Azure OpenAI · Cosmos DB (벡터 인덱스 + 시드 데이터) · User Assigned Managed Identity 가 본인 구독에 존재
> - 시작본 코드를 작업 폴더로 받기: `cp -a save-points/session-02/start/. workshop/` (자세한 안내는 §시작본 코드 받기)

---

## 0. 이 세션에서 경험하는 내용

- **한 문장 골** — Cosmos DB 와 PostgreSQL pgvector 두 벡터 백엔드에 같은 데이터를 적재하고 검색해, 두 백엔드의 트레이드오프를 직접 측정한 숫자로 비교
- **새로 프로비저닝되는 자원**
  - PostgreSQL Flexible Server `pg-ai200ws-dev` (Burstable B1ms 등급)
  - 서버 파라미터 `azure.extensions=VECTOR` — pgvector extension 사용 사전 허용
  - 데이터베이스 `appdb`
  - 본인 PC IP 를 허용하는 firewall rule
  - 본인 Entra ID 사용자를 PostgreSQL Entra ID admin 으로 부여
- **사용해볼 SDK / CLI**
  - `psql` — Entra ID 토큰을 비밀번호로 사용
  - `psycopg` async + `psycopg_pool` — 클라이언트 측 연결 풀
  - `pgvector.psycopg.register_vector_async` — Python ↔ `halfvec` 타입 매핑
  - `halfvec(3072)` 컬럼 + HNSW 인덱스 (`halfvec_cosine_ops`)
- **Portal 에서 확인할 지표 / 데이터**
  - PostgreSQL Flexible Server → Server parameters — `azure.extensions` 가 `VECTOR` 포함
  - PostgreSQL Flexible Server → Metrics — seed 직후 CPU · 활성 연결 수 스파이크
  - PostgreSQL Flexible Server → Query performance insight — HNSW 검색 쿼리 plan

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈 한눈에 보기

이 세션이 배포하는 Bicep 모듈 (`infra/sessions/02-pgvector/main.bicep`).

- `postgres-flexible-server.bicep` — Burstable B1ms 등급, Entra ID 전용 인증
- `postgres-database.bicep` — `appdb` 데이터베이스
- `postgres-server-config.bicep` — `azure.extensions = VECTOR` 사전 허용
- `postgres-firewall-rule.bicep` — 본인 PC IP 허용
- `postgres-aad-admin.bicep` — 본인 Entra ID 사용자를 admin 으로 부여

### 1.2 변경사항 미리보기

```bash
# 본인 식별 정보를 환경변수로 저장 — 배포 명령 인자로 직접 전달
OID=$(az ad signed-in-user show --query id -o tsv)
UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)
MY_IP=$(curl -s ifconfig.me)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/02-pgvector/main.bicep \
  --parameters infra/sessions/02-pgvector/main.bicepparam \
  --parameters userObjectId=$OID userPrincipalName=$UPN devClientIpAddress=$MY_IP
```

> [!CAUTION]
> `userObjectId`, `userPrincipalName`, `devClientIpAddress` 는 `bicepparam` 파일에 작성해두지 않습니다. git history 에 영구히 남아 포트폴리오 공개 시 본인 식별 정보가 노출됩니다. 배포 명령을 실행할 때마다 `--parameters key=value` 인자로 직접 넘겨주는 방식으로 전달합니다.

### 1.3 실제 배포

```bash
az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/02-pgvector/main.bicep \
  --parameters infra/sessions/02-pgvector/main.bicepparam \
  --parameters userObjectId=$OID userPrincipalName=$UPN devClientIpAddress=$MY_IP
```

> [!NOTE]
> PostgreSQL Flexible Server 생성에 약 **5분** 소요됩니다. 진행되는 동안 [2단계 · 복붙으로 경험해보기](#2단계--복붙으로-경험해보기) 의 트레이드오프 박스를 미리 정독합니다.

### 1.4 배포 완료 확인

```bash
az postgres flexible-server show \
  --name pg-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --query "{state:state, version:version, extensions:azureExtensions}" -o jsonc
```

기대 — `state: Ready`, `extensions` 에 `VECTOR` 포함.

---

## 2단계 · 복붙으로 경험해보기

### 2.1 Cosmos DB 와 PostgreSQL pgvector 트레이드오프

| 차원 | Cosmos DB ([session-01](./01-rag-mvp.md) 에서 사용) | PostgreSQL pgvector |
|---|---|---|
| **쿼리 언어** | SQL-like (JSON 중심) | 표준 SQL — `JOIN`, `WHERE` 자유 |
| **인덱스 종류** | DiskANN · quantizedFlat · flat | HNSW · IVFFlat |
| **3072 차원 벡터** | 네이티브 지원 (`vector` policy) | `halfvec(3072)` 사용 강제 — `vector(3072)` HNSW 는 2000 차원 한계 |
| **디버깅** | Data Explorer 만 | `psql` · `EXPLAIN ANALYZE` · 표준 PostgreSQL 클라이언트 모두 |
| **트랜잭션** | 단일 파티션 안에서만 | 표준 ACID |
| **비용 모델** | serverless RU 사용량 기반 | 시간당 컴퓨트 (Burstable 최소 등급 기준 월 ~$13) |
| **메타데이터 결합 필터** | partition key + 단순 필터 | 임의 SQL 조건 + JOIN |
| **언제 사용하면 좋은가** | 전역 분산 · 큰 partition · 단순 조회 | 풍부한 메타데이터 필터 · 분석 SQL · ACID 트랜잭션 |

> [!TIP]
> **시험 단골 패턴** — "벡터 + 복잡한 SQL 필터" 가 필요하면 PostgreSQL, "전역 저지연 + 큰 partition" 이 필요하면 Cosmos DB. 두 백엔드는 RAG 의 검색 단계에서 서로 대체재라기보다 다른 워크로드에 적합한 도구로 이해합니다.

### 2.2 PostgreSQL 데이터베이스 초기화

먼저 Entra ID 토큰을 비밀번호로 사용해 `psql` 로 접속합니다.

```bash
UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)

PGPASSWORD=$(az account get-access-token \
  --resource-url https://ossrdbms-aad.database.windows.net \
  --query accessToken -o tsv) \
psql "host=pg-ai200ws-dev.postgres.database.azure.com \
  port=5432 \
  dbname=appdb \
  user=$UPN \
  sslmode=require"
```

접속한 `psql` 안에서 다음 SQL 을 그대로 복사해 실행합니다.

```sql
-- 1) pgvector extension 활성화
--    azure.extensions 서버 파라미터에 VECTOR 가 사전 허용되어 있어야 동작합니다 (Bicep 에서 설정 완료).
CREATE EXTENSION IF NOT EXISTS vector;

-- 2) chunks 테이블 생성
--    text-embedding-3-large 는 3072 차원 임베딩을 반환합니다.
--    vector(3072) 는 HNSW 의 2000 차원 한계에 막히므로 halfvec(3072) 를 사용합니다.
CREATE TABLE IF NOT EXISTS chunks (
  id         TEXT PRIMARY KEY,
  doc_id     TEXT NOT NULL,
  title      TEXT,
  content    TEXT NOT NULL,
  embedding  halfvec(3072) NOT NULL,
  metadata   JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3) HNSW 인덱스 — halfvec 전용 코사인 거리 ops 클래스 사용
CREATE INDEX IF NOT EXISTS chunks_embedding_hnsw
  ON chunks USING hnsw (embedding halfvec_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- 4) 메타데이터 필터를 위한 보조 인덱스 (선택)
CREATE INDEX IF NOT EXISTS chunks_doc_id_idx ON chunks (doc_id);

-- 5) 테이블 구조 확인
\d chunks
```

### 2.3 PostgreSQL store 코드 복사·붙여넣기

> [!NOTE]
> 아래 두 파일은 그대로 복사해 해당 경로에 붙여넣습니다. 동작 원리는 코드 다음의 줄별 해설에서 다룹니다.

**파일 1** — `apps/api/src/stores/pg_store.py`

```python
# (psycopg async + psycopg_pool + pgvector.psycopg.register_vector_async 를 사용한 PostgreSQL store.
#  핵심 구성:
#  - DefaultAzureCredential 로 Entra ID 토큰을 받아 비밀번호로 사용
#  - psycopg_pool.AsyncConnectionPool 로 클라이언트 측 연결 풀 관리 (Burstable 등급은 PgBouncer 미지원)
#  - register_vector_async 는 CREATE EXTENSION vector 가 끝난 *후* 호출되어야 함
#  - 검색: SELECT id, title, content, embedding <=> $1::halfvec AS distance
#          FROM chunks ORDER BY distance LIMIT $2
#  실제 코드 본문은 후속 구현 단계에서 작성합니다.)
```

**파일 2** — `scripts/seed_both.py`

```python
# (같은 문서 셋을 Cosmos DB · PostgreSQL 양쪽에 임베드 + 적재한 뒤,
#  동일한 쿼리에 대한 P50 · P95 latency 와 recall@5 를 측정해 비교 표로 출력하는 스크립트.
#  핵심 구성:
#  - DefaultAzureCredential 로 양쪽 동시 인증
#  - 동일 chunk 셋을 100~200개 적재
#  - 동일 질문 셋을 두 백엔드에 N회 호출, 응답 시간 측정
#  - markdown 표로 결과 출력
#  실제 코드 본문은 후속 구현 단계에서 작성합니다.)
```

### 2.4 비교 실행

```bash
# 1) seed 동시 적재 + latency 측정
python scripts/seed_both.py
```

기대 출력 형태.

```
| backend  | docs | p50 (ms) | p95 (ms) | recall@5 |
|----------|------|----------|----------|----------|
| cosmos   |  120 |       45 |       78 |     1.00 |
| pg       |  120 |       32 |       61 |     1.00 |
```

```bash
# 2) 환경변수로 backend 선택해 동일 질문 호출 — PostgreSQL 경로
API_FQDN=$(az containerapp show -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)

# (애플리케이션이 STORE_BACKEND 환경변수를 읽도록 구현되어 있다는 전제)
az containerapp update \
  --name ca-api-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --set-env-vars STORE_BACKEND=pg

# 호출
curl -X POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q": "회사 휴가 정책 알려줘"}' | jq .sources
```

---

## 3단계 · Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **PostgreSQL Flexible Server `pg-ai200ws-dev`** → **Server parameters** → 검색창에 `azure.extensions` 입력 → 값에 `VECTOR` 가 포함되어 있는지 확인
2. **PostgreSQL Flexible Server** → **Metrics** → 두 메트릭 추가
   - `CPU percent` — seed 실행 직후 스파이크
   - `Active Connections` — 풀 크기 만큼 일시적으로 증가
3. **PostgreSQL Flexible Server** → **Query performance insight** (또는 **Server logs**) → 가장 비싼 쿼리 상위에 `SELECT ... ORDER BY embedding <=> ...` 가 노출
4. (선택) **psql 안에서 `EXPLAIN ANALYZE` 실행**

   ```sql
   EXPLAIN ANALYZE
   SELECT id, title, embedding <=> $1::halfvec AS distance
   FROM chunks ORDER BY distance LIMIT 5;
   ```

   plan 에 `Index Scan using chunks_embedding_hnsw` 가 노출되어야 정상입니다. `Seq Scan` 이 나오면 인덱스가 사용되지 않은 상태이므로, [주의](#주의) 섹션의 함정을 참고합니다.

---

## 주의

> [!CAUTION]
> **`vector(3072)` HNSW 는 2000 차원 한계로 인덱스 생성 실패** — text-embedding-3-large 가 반환하는 3072 차원을 HNSW 로 색인하려면 `halfvec(3072)` 와 `halfvec_cosine_ops` 를 사용해야 합니다. `vector` 타입은 indexed search 시 2000 차원 한계가 있습니다.

> [!WARNING]
> **PgBouncer 는 Burstable 등급에서 미지원** — `ServerParameterToCMSPgBouncerNotSupportedForBurstable` 오류가 발생합니다. 본 워크샵은 학습용 Burstable 등급을 사용하므로, 서버 측 PgBouncer 대신 클라이언트 측 `psycopg_pool` 로 연결 풀을 관리합니다.

> [!WARNING]
> **`register_vector_async` chicken-and-egg** — 풀 초기화 콜백에서 `register_vector_async` 를 호출하는데, 그 시점에 데이터베이스에 `vector` extension 이 없으면 풀 초기화 자체가 실패합니다 (30초 PoolTimeout 후 앱 종료). 부트스트랩 스크립트로 `CREATE EXTENSION vector` 를 먼저 실행한 뒤 앱을 시작합니다.

> [!CAUTION]
> **PostgreSQL 서버 파라미터 set 순서는 알파벳 정렬 의존** — `pgbouncer.enabled` 같은 상위 파라미터가 그 하위 파라미터들보다 먼저 적용되어야 하는데, Bicep `params` 배열의 적용 순서가 알파벳 정렬을 따릅니다. 본 워크샵은 PgBouncer 를 끄므로 이 함정에 노출되지 않지만, 다른 시나리오에서 PostgreSQL 파라미터를 추가할 때 주의가 필요합니다.

> [!NOTE]
> 더 자세한 함정 모음은 [docs/pitfalls/common.md](../pitfalls/common.md) 의 [벡터 · 인덱싱](../pitfalls/common.md#벡터--인덱싱) 섹션을 참고합니다.

---

## 마무리

- **save-point** — 본 세션의 모든 변경은 `save-points/session-02/complete/` 와 일치합니다. 다음 세션으로 넘어가려면 `cp -a save-points/session-03/start/. workshop/` 를 실행합니다 (다음 세션의 시작본이 `workshop/` 위에 덮입니다)
- **자원 정리** — PostgreSQL Flexible Server 는 후속 세션 (특히 [session-04](./04-async-ingestion.md) 의 비동기 인제스션) 에서 계속 사용됩니다. 정리하지 않습니다
- **다음 세션 미리보기** — [session-03](./03-redis-cache.md) 에서는 같은 질문을 두 번 호출하면 두 번째 응답을 1ms 수준으로 만드는 Managed Redis 시맨틱 캐시를 도입합니다

---

## 참고 자료

- Microsoft Learn — [Develop AI solutions with Azure Database for PostgreSQL](https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-database-postgresql/)
- pgvector — [github.com/pgvector/pgvector](https://github.com/pgvector/pgvector)
- 본 저장소 — `infra/sessions/02-pgvector/main.bicep`, `apps/api/src/stores/pg_store.py`, `scripts/seed_both.py`

---

👈 [session-01 — RAG MVP on Azure Container Apps + Key Vault + OpenTelemetry](./01-rag-mvp.md) | [session-03 — Managed Redis 시맨틱 캐시](./03-redis-cache.md) 👉
