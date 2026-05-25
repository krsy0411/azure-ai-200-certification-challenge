# session-02 — PostgreSQL pgvector 비교

> 학습 경로 매핑: [Develop AI solutions with Azure Database for PostgreSQL](https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-database-postgresql/)  
> 사전 조건: session-01 완료, `git checkout session-02-start`

---

## 0. 이 세션에서 무엇을 경험하나

- **한 문장 골**: Cosmos 와 PostgreSQL pgvector 두 벡터 백엔드에 *같은 데이터* 를 적재하고 검색해, 트레이드오프를 숫자로 확인.
- **새로 프로비저닝되는 자원**:
  - PostgreSQL Flexible Server (Burstable B1ms)
  - `azure.extensions=vector` 서버 파라미터
  - `pgvector` extension 활성화
  - AAD admin 부여 (본인 → 첫 부트스트랩용)
  - Firewall rule (본인 IP 허용)
- **사용해볼 SDK/CLI**:
  - `psycopg` async + `psycopg_pool`
  - `pgvector.psycopg.register_vector_async`
  - `halfvec(3072)` 컬럼 + HNSW 인덱스
- **Portal 에서 확인할 지표/데이터**:
  - PG Flex → Server parameters → `azure.extensions` 가 `VECTOR` 포함
  - PG Flex → Metrics → seed 직후 CPU/연결 수 스파이크
  - PG Flex → Query performance insight → HNSW 검색 plan

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈

- `postgres-flexible-server.bicep` — B1ms, Entra-only auth, AAD admin
- `postgres-database.bicep` — `appdb` 데이터베이스
- `postgres-server-config.bicep` — `azure.extensions = VECTOR` 사전 설정
- `postgres-firewall-rule.bicep` — 본인 IP 허용
- `postgres-aad-admin.bicep` — 본인을 AAD admin 으로

### 1.2 배포

> ⚠️ **함정 회피**: `devClientIpAddress` 와 `userObjectId` 는 bicepparam 에 박지 말고 CLI override 로만 전달. git history 누출 방지.

```bash
OID=$(az ad signed-in-user show --query id -o tsv)
MY_IP=$(curl -s ifconfig.me)
UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/02-pgvector/main.bicep \
  --parameters infra/sessions/02-pgvector/main.bicepparam \
  --parameters userObjectId=$OID userPrincipalName=$UPN devClientIpAddress=$MY_IP

az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/02-pgvector/main.bicep \
  --parameters infra/sessions/02-pgvector/main.bicepparam \
  --parameters userObjectId=$OID userPrincipalName=$UPN devClientIpAddress=$MY_IP
```

> ⏱ PG Flex 배포 약 **5분**. 진행되는 동안 §2 의 트레이드오프 박스 정독.

### 1.3 배포 완료 확인

```bash
az postgres flexible-server show \
  -n pg-ai200ws-dev -g rg-ai200ws-dev \
  --query "{state:state, version:version, extensions:azureExtensions}" -o jsonc
```

---

## 2단계 · 복붙으로 경험해보기

### 2.1 Cosmos vs PostgreSQL pgvector

| 차원 | Cosmos DB (session-01) | PostgreSQL pgvector |
|---|---|---|
| **쿼리 언어** | SQL-like (JSON 중심) | 표준 SQL — `JOIN`, `WHERE` 자유 |
| **인덱스 종류** | DiskANN, quantizedFlat, flat | HNSW, IVFFlat |
| **3072-d 벡터** | 네이티브 (`vector` policy) | **`halfvec(3072)` 강제** (`vector(3072)` HNSW 2000-d 한계) |
| **디버깅** | Data Explorer 만 | `psql`, `EXPLAIN ANALYZE`, 어떤 DB 클라이언트나 |
| **트랜잭션** | 단일 파티션만 | full ACID |
| **비용 모델** | serverless RU | 시간당 컴퓨트 (Burstable 최소 ~$13/월) |
| **메타데이터 결합 필터** | partition key + 단순 필터 | 임의 SQL 조건 + JOIN |
| **언제 쓰나** | 전역 분산, 큰 partition, 단순 조회 | 풍부한 메타데이터 필터, 분석 SQL, ACID |

> 🎯 **AI-200 시험 포인트**: "벡터 + 복잡한 SQL 필터" 는 PG. "전역 저지연 + 큰 partition" 은 Cosmos.

### 2.2 SQL 스니펫 복붙 (먼저 DB 초기화)

```bash
# psql 로 접속 — AAD 토큰을 비밀번호로 사용
PGPASSWORD=$(az account get-access-token \
  --resource-url https://ossrdbms-aad.database.windows.net \
  --query accessToken -o tsv) \
psql "host=pg-ai200ws-dev.postgres.database.azure.com \
  port=5432 dbname=appdb user=$UPN sslmode=require"
```

DB 안에서:

```sql
-- 1) extension 활성화 (이미 azure.extensions 에 등록되어 있어야 함)
CREATE EXTENSION IF NOT EXISTS vector;

-- 2) chunks 테이블 — text-embedding-3-large 가 3072-d 라 halfvec 강제
CREATE TABLE IF NOT EXISTS chunks (
  id        TEXT PRIMARY KEY,
  doc_id    TEXT NOT NULL,
  title     TEXT,
  content   TEXT NOT NULL,
  embedding halfvec(3072) NOT NULL,
  metadata  JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3) HNSW 인덱스 — halfvec 전용 ops 사용
CREATE INDEX IF NOT EXISTS chunks_embedding_hnsw
  ON chunks USING hnsw (embedding halfvec_cosine_ops)
  WITH (m = 16, ef_construction = 64);

\d chunks
```

### 2.3 Python store 복붙

**파일**: `apps/api/src/stores/pg_store.py`

```python
# (psycopg async + psycopg_pool + pgvector.psycopg.register_vector_async.
#  주의: register_vector_async 는 CREATE EXTENSION vector 가 끝난 *후* 호출되어야 함.
#  실제 코드는 후속 구현 단계에서.)
```

**파일**: `scripts/seed_both.py`

```python
# (동일 문서 셋을 Cosmos·PG 양쪽에 임베드+적재 → 동일 쿼리로 P50/P95 latency 측정.
#  결과를 표로 출력. 실제 코드는 후속 구현 단계.)
```

### 2.4 실행

```bash
# 1) seed 동시 적재
python scripts/seed_both.py

# 기대 출력 예시:
# | backend  | docs | p50 (ms) | p95 (ms) | recall@5 |
# |----------|------|----------|----------|----------|
# | cosmos   |  120 |    45    |    78    |   1.00   |
# | pg       |  120 |    32    |    61    |   1.00   |

# 2) backend 토글로 API 재호출 (env 로 백엔드 선택)
STORE_BACKEND=pg curl -X POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q": "회사 휴가 정책 알려줘"}' | jq .sources
```

---

## 3단계 · Azure Portal UI 에서 확인

1. **PG Flex `pg-ai200ws-dev`** → **Server parameters** → `azure.extensions` 검색 → 값에 `VECTOR` 포함 (대문자)
2. **PG Flex** → **Metrics** → `CPU percent` · `Active connections` → seed 실행 직후 스파이크
3. **PG Flex** → **Query performance insight** (또는 **Logs**) → 가장 비싼 쿼리 상위에 `SELECT ... ORDER BY embedding <=> ...` 가 보임
4. **(선택) `EXPLAIN ANALYZE`** — psql 안에서:
   ```sql
   EXPLAIN ANALYZE
   SELECT id, title, embedding <=> $1::halfvec AS distance
   FROM chunks ORDER BY distance LIMIT 5;
   ```
   plan 에 `Index Scan using chunks_embedding_hnsw` 가 보여야 함

---

## 주의 (Heads-up)

- ⚠️ **`vector(3072)` HNSW 는 2000-d 한계로 실패** — `text-embedding-3-large` 는 `halfvec(3072)` + `halfvec_cosine_ops` 강제
- ⚠️ **`register_vector_async` chicken-and-egg** — `CREATE EXTENSION vector` 전에 호출되면 풀 init 실패 (30초 PoolTimeout 후 앱 dead). 부트스트랩 스크립트 분리 권장
- ⚠️ **PgBouncer 는 Burstable 미지원** — `ServerParameterToCMSPgBouncerNotSupportedForBurstable`. 클라이언트풀 (`psycopg_pool`) 로 충분
- ⚠️ **`devClientIpAddress` · `userObjectId` 는 bicepparam 박지 말 것** — git history 누출. CLI override 강제
- ⚠️ **PG 파라미터 set 순서는 알파벳 정렬** — `pgbouncer.enabled` 가 sub-param 들 *전에* 와야 함

---

## 마무리

- **save-point**: `git tag session-02-complete`
- **다음 세션 미리보기**: session-03 — 같은 질문을 두 번 호출하면 두 번째는 1ms 라면 어떨까? Managed Redis 시맨틱 캐시 도입

---

## 참고 자료

- MS Learn: [Develop AI solutions with PostgreSQL](https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-database-postgresql/)
- pgvector: [github.com/pgvector/pgvector](https://github.com/pgvector/pgvector)
- 본 레포: `infra/sessions/02-pgvector/main.bicep`, `apps/api/src/stores/pg_store.py`, `scripts/seed_both.py`
