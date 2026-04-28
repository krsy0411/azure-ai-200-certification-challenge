# Phase 5 — Azure Database for PostgreSQL Flexible Server + pgvector

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-database-postgresql/ (3 모듈)

## 학습 경로 구성

| 모듈 | 단원 (요약) |
|---|---|
| **1. PostgreSQL 빌드 · 쿼리** (9 단원) | 1) 소개 · 2) PG 살펴보기 · 3) **PG 에 연결 (Entra + TLS)** · 4) 스키마 만들기 · 5) 쿼리 · 6) **SDK · 앱 통합 (Python)** · 7) 연습 (에이전트 도구 백엔드) · 8) 평가 · 9) 요약 |
| **2. pgvector 벡터 검색 구현** (9 단원) | 1) 소개 · 2) **pgvector 임베딩 저장 · 쿼리** · 3) 빠른 유사성 검색 · 4) 인덱스 수명 주기 · 임베딩 업데이트 · 5) 의미 체계 검색 · 6) **RAG 검색 패턴** · 7) 연습 · 8) 평가 · 9) 요약 |
| **3. 벡터 검색 최적화** (9 단원) | 1) 소개 · 2) **PG · pgvector 튜닝** · 3) **인덱스 선택 · 구성 (HNSW vs IVFFlat)** · 4) 데이터 레이아웃 · 5) 대용량 워크로드 스케일링 · 6) **연결 최적화 (PgBouncer)** · 7) 연습 · 8) 평가 · 9) 요약 |

---

## MS Learn 경로 커버리지 — 사용 / 생략

| 모듈 | 단원 | 사용 / 생략 | 프로젝트 적용 위치 |
|---|---|---|---|
| 1 | 2 PG 살펴보기 (Flexible Server 아키텍처) | **사용** | `infra/modules/postgres-flexible-server.bicep` (PG 16, B1ms, public access) |
| 1 | 3 **PG 에 연결 (Entra + TLS)** | **사용** | `apps/api/src/stores/pg_store.py` `_get_fresh_token()` + `sslmode=require` |
| 1 | 4 스키마 만들기 · 관리 | **사용** | `apps/api/src/stores/pg_bootstrap.sql` (workspaces / documents / chunks_*) |
| 1 | 5 쿼리 데이터 (SQL 기본) | **부분 사용** | upsert / SELECT 만 사용. 학습용 단순 쿼리 |
| 1 | 6 **SDK · 앱 통합 (Python)** | **사용** | psycopg + psycopg_pool (`pg_store.py`) |
| 1 | 7 연습 (에이전트 도구 백엔드) | **이관** | Phase 7 (Functions 변경 피드 자동 임베딩) 와 결합 예정 |
| 2 | 2 **pgvector 임베딩 저장 · 쿼리** | **사용** | `halfvec(3072)` + `register_vector_async` |
| 2 | 3 빠른 유사성 검색 | **사용** | `<=>` (cosine) 연산자 |
| 2 | 4 인덱스 수명 주기 · 임베딩 업데이트 | **부분 사용** | 부트스트랩 SQL 의 `CREATE INDEX IF NOT EXISTS` 까지. **자동 갱신 (CDC) 은 Phase 7 로 이관** (Phase 4 와 일관) |
| 2 | 5 의미 체계 검색 | **사용** | `/api/search?store=pg` 라우터 |
| 2 | 6 **RAG 검색 패턴** | **사용** | 메타데이터 필터 (`workspace_id`, `document_id`) + 벡터 거리 결합 (`vector_search_chunks`) |
| 3 | 2 **PG · pgvector 튜닝** | **부분 사용** | `m=16, ef_construction=64`, `lists=100` 까지. `maintenance_work_mem` 같은 server param 은 학습 산출물로 이번 Phase 에서 단일 값 비교만 수행 |
| 3 | 3 **인덱스 선택 · 구성** | **사용** (핵심) | `chunks_hnsw` / `chunks_ivf` 두 테이블 분리 적재 → 같은 쿼리로 비교 측정 |
| 3 | 4 데이터 레이아웃 (TOAST · 파티셔닝) | **생략** | 단일 워크스페이스 · 단일 문서 데이터셋이라 측정 가치 낮음. Phase 9 에서 KQL 로 IO 패턴 관측 시 재방문 가능 |
| 3 | 5 대용량 스케일링 (read replica 등) | **생략** | B1ms 단일 노드 학습용. 실험 트래픽 없음 |
| 3 | 6 **연결 최적화** | **부분 사용** | 내장 PgBouncer 는 **Burstable B1ms 에서 미지원** (`ServerParameterToCMSPgBouncerNotSupportedForBurstable`) — 의도적 생략. 클라이언트 측 `psycopg_pool.AsyncConnectionPool` 단일 풀링으로 커버. PgBouncer 활성 시나리오는 General Purpose / Memory Optimized SKU 로 향후 재방문 |

각 모듈의 8 (평가) · 9 (요약) 단원은 학습자 본인의 자기 진단 영역이라 표에서 일관 생략.

---

## 이 프로젝트에서의 적용

- 동일 청크 데이터셋을 **Cosmos DB (Phase 4)** 와 **PostgreSQL pgvector (Phase 5)** 양쪽에 적재 → 검색 latency / recall / 운영 복잡도 / 비용을 비교한 학습 산출물 작성.
- Phase 4 자원은 그대로 살려두고 Phase 5 main.bicep 에서는 **`existing` 참조**만 → ACA api 의 `envVars` 만 cosmos+aoai+pg 로 갱신해 한 컨테이너가 두 백엔드를 동시에 다룸.
- **Entra-only 인증**: AAD admin (UAMI) 외에는 어떤 password 도 만들지 않음. psql 검증 시 사용자 본인은 임시 admin 부여 후 회수.
- **HNSW + IVFFlat 동시 보유**: pgvector 는 한 컬럼에 여러 인덱스가 있어도 planner 가 하나만 선택하므로, 깔끔한 비교를 위해 동일 row 를 두 테이블에 적재.

## 구현 스냅샷

| 컴포넌트 | 리소스 | 이름 |
|---|---|---|
| PostgreSQL Flexible Server | PG 16 / B1ms / 32 GiB | `pg-ai200challenge-dev05` |
| Database | 워크스페이스 데이터 컨테이너 | `kb` |
| AAD admin | UAMI 등록 (passwordAuth=Disabled) | `id-ai200challenge-aca-dev` |
| Server params | `azure.extensions=VECTOR` (단일 — PgBouncer 는 Burstable 미지원) | (configurations sub-resource) |
| Firewall | Azure services + 사용자 IP | `AllowAllAzureServices…`, `DevClient` |
| ACA api (갱신) | env: `PG_HOST`, `PG_USER`, `PG_PORT=5432`, … | `ca-ai200challenge-api-dev` |

(Phase 4 의 cosmos / aoai / acr / cae / uami 는 existing 참조 상태로 유지)

---

## 아키텍처

```
rg-ai200challenge-dev
├─ acrai200challengedev04                         (Phase 1, existing)
├─ id-ai200challenge-aca-dev                      (Phase 2, existing)
├─ cae-ai200challenge-dev                         (Phase 2, existing)
├─ cosmos-ai200challenge-dev04                    (Phase 4, existing)
├─ aoai-ai200challenge-dev04                      (Phase 4, existing)
└─ pg-ai200challenge-dev05                        (Phase 5, NEW — PG 16 / B1ms)
   ├─ databases/kb
   ├─ administrators/<UAMI principalId>           (AAD admin, ServicePrincipal)
   ├─ configurations
   │     └─ azure.extensions = VECTOR              (PgBouncer 는 Burstable 미지원으로 생략)
   └─ firewallRules
         ├─ AllowAllAzureServicesAndResourcesWithinAzureIps  (0.0.0.0)
         └─ DevClient                                        (사용자 IP)

ca-ai200challenge-api-dev (ACA, internal)
   ├─ env: COSMOS_*, AOAI_*  (Phase 4 그대로)
   └─ env: PG_HOST=<fqdn>, PG_PORT=5432, PG_DATABASE=kb, PG_USER=id-ai200challenge-aca-dev,
           AZURE_CLIENT_ID=<UAMI clientId>
```

PG_PORT = 5432 직결. PgBouncer 는 Burstable B1ms 에서 활성 불가라 클라이언트 측 `psycopg_pool` 단일 풀링만 사용.

---

## Bicep 모듈 구성

| 모듈 | 책임 |
|---|---|
| `postgres-flexible-server.bicep` | 서버 자체 (버전 / SKU / 스토리지 / `authConfig`) |
| `postgres-database.bicep` | `kb` 데이터베이스 |
| `postgres-aad-admin.bicep` | `administrators` sub-resource — UAMI 등록 |
| `postgres-firewall-rule.bicep` | 단일 IP 범위 allow 규칙 |
| `postgres-server-config.bicep` | `configurations` 일괄 (vector 확장 + PgBouncer) |

조립: `infra/phases/05-postgresql/main.bicep`. Phase 4 의 cosmos / aoai 는 `existing` 으로만 가져오고, ACA api 는 `container-app.bicep` 모듈을 같은 이름·같은 사양으로 다시 호출해 envVars 만 갱신.

### Bicep 핵심 인용

**Entra-only auth**

```bicep
// modules/postgres-flexible-server.bicep
authConfig: {
  activeDirectoryAuth: 'Enabled'
  passwordAuth: entraOnlyAuth ? 'Disabled' : 'Enabled'
  tenantId: subscription().tenantId
}
```

**AAD admin 등록 (UAMI principalId 가 sub-resource name)**

```bicep
// modules/postgres-aad-admin.bicep
resource admin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = {
  parent: server
  name: principalObjectId          // UAMI 의 objectId == principalId
  properties: {
    principalType: 'ServicePrincipal'
    principalName: principalName   // 이 값이 PG role 이름이 됨 → psycopg user 와 일치
    tenantId: subscription().tenantId
  }
}
```

> ⚠ `principalName` 이 곧 PostgreSQL 의 role 이름이 된다. psycopg 의 `user` 파라미터 (= 환경변수 `PG_USER`) 가 정확히 이 값과 일치해야 로그인 가능. 본 레포에서는 둘 다 UAMI 의 리소스 이름 `id-ai200challenge-aca-dev` 로 고정.

**Server parameters 일괄 (vector + PgBouncer)**

```bicep
// phases/05-postgresql/main.bicep
module pgServerConfig '../../modules/postgres-server-config.bicep' = {
  params: {
    serverName: pgServer.outputs.name
    parameters: {
      'azure.extensions': 'VECTOR'
      'pgbouncer.enabled': 'true'
      'pgbouncer.pool_mode': 'transaction'
      'pgbouncer.default_pool_size': '50'
    }
  }
  dependsOn: [ pgAadAdmin ]   // admin 등록 전에는 사실상 사용 불가 → 직렬화
}
```

> ⚠ `azure.extensions` 의 값은 **대문자 `VECTOR`** (Azure flex 의 extension allowlist 케이스). 소문자로 넣으면 `CREATE EXTENSION vector` 가 권한 거부로 실패한다.

**ACA api envVars 갱신 (cosmos + aoai + pg 동시 주입)**

```bicep
envVars: {
  COSMOS_ENDPOINT: cosmos.properties.documentEndpoint
  AOAI_ENDPOINT:   aoai.properties.endpoint
  PG_HOST: pgServer.outputs.fqdn
  PG_PORT: '6432'
  PG_DATABASE: pgDb.outputs.name
  PG_USER: uamiName
  AZURE_CLIENT_ID: uami.properties.clientId
  // ... (기타)
}
```

---

## 앱 코드 — `pg_store.py`

### Entra 토큰 → psycopg password

```python
_OSSRDBMS_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"

async def _get_fresh_token(self) -> str:
    token = await self._credential.get_token(_OSSRDBMS_SCOPE)
    self._token_expires_on = float(token.expires_on)
    return token.token
```

토큰의 `expires_on` (epoch sec) 을 보관 → 만료 5분 전 임박 시 풀 자체를 재생성. psycopg_pool 이 conninfo / kwargs 에 박힌 password 만 받기 때문에 토큰 회전을 connection 단위로 하기 어려운 한계를 **풀 단위 재생성** 으로 단순화 (학습용). 운영용 권장은 connection factory + token cache.

### 연결 풀 + vector 어댑터

```python
async def _open_pool(self) -> AsyncConnectionPool:
    token = await self._get_fresh_token()
    kwargs = {
        "host": self._s.host, "port": self._s.port,
        "dbname": self._s.database, "user": self._s.user,
        "password": token, "sslmode": "require",
    }

    async def _configure(conn: psycopg.AsyncConnection) -> None:
        # 새 connection 마다 vector / halfvec 어댑터 등록
        await register_vector_async(conn)

    pool = AsyncConnectionPool(
        min_size=1, max_size=10,
        kwargs=kwargs, configure=_configure, open=False,
    )
    await pool.open()
    return pool
```

### 검색 SQL — column alias 로 Cosmos 키와 일치

```python
sql = f"""
SELECT id,
       document_id AS "documentId",
       ordinal,
       text,
       (embedding <=> %s::halfvec) AS score
FROM {table}                       -- chunks_hnsw / chunks_ivf
WHERE workspace_id = %s
  {doc_filter}
ORDER BY embedding <=> %s::halfvec
LIMIT %s;
"""
```

`document_id AS "documentId"` 큰따옴표 alias 는 Cosmos 의 SELECT 컬럼명과 **응답 키를 동일**하게 유지하기 위한 장치. 라우터 (`index_search.py`) 는 store 에 무관하게 같은 dict 키를 가정하고 응답을 만든다.

---

## 부트스트랩 SQL — `pg_bootstrap.sql`

`PgStore.open()` 이 lifespan 시작 시 1회 실행 (idempotent).

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS chunks_hnsw (
    id            TEXT PRIMARY KEY,
    workspace_id  TEXT NOT NULL,
    document_id   TEXT NOT NULL,
    ordinal       INT  NOT NULL,
    text          TEXT NOT NULL,
    embedding     halfvec(3072) NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chunks_hnsw_vec
    ON chunks_hnsw USING hnsw (embedding halfvec_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- chunks_ivf: 같은 스키마, 다른 인덱스
CREATE INDEX IF NOT EXISTS idx_chunks_ivf_vec
    ON chunks_ivf USING ivfflat (embedding halfvec_cosine_ops)
    WITH (lists = 100);
```

> ⚠ **차원 = 3072 인데 왜 `halfvec` 인가?** pgvector 의 `vector` 타입은 인덱스 한계가 2000 차원 (HNSW · IVFFlat 둘 다). `text-embedding-3-large` 는 3072 차원이라 `vector(3072)` 로 선언하면 `CREATE INDEX` 가 실패한다. `halfvec(3072)` (16-bit float) 는 인덱스 한계 4000 차원이라 그대로 가능 + 메모리 절반.

---

## 이미지 빌드 · 푸시 (Phase 5 새 이미지)

PgStore 가 추가된 새 이미지 `0.5.0` 을 ACR 에 푸시한다 (Bicep IaC 예외 — 사용자 직접 실행).

```bash
# 1) ACR 로그인
az acr login --name acrai200challengedev04

# 2) linux/amd64 강제 빌드 (Apple Silicon 호환)
docker build \
  --platform linux/amd64 \
  -t acrai200challengedev04.azurecr.io/api:0.5.0 \
  apps/api

# 3) 푸시
docker push acrai200challengedev04.azurecr.io/api:0.5.0
```

이 단계가 끝나야 `imageTag = '0.5.0'` 인 main.bicepparam 으로 ACA 가 새 이미지를 가져올 수 있다.

---

## 배포 명령

`devClientIpAddress` 는 **bicepparam 의 default `'0.0.0.0'` 을 그대로 두고 CLI 에서 override**. 본인 공인 IP 를 git 에 박지 않기 위함 — CLAUDE.md §7 참조.

```bash
# 사용자 IP 확인 + 환경변수로
MY_IP=$(curl -s https://api.ipify.org); echo "$MY_IP"

# what-if 검토 (-p devClientIpAddress=$MY_IP 로 override)
az deployment group what-if \
  --resource-group rg-ai200challenge-dev \
  --template-file infra/phases/05-postgresql/main.bicep \
  --parameters infra/phases/05-postgresql/main.bicepparam \
  --parameters devClientIpAddress=$MY_IP

# 실제 배포
az deployment group create \
  --resource-group rg-ai200challenge-dev \
  --template-file infra/phases/05-postgresql/main.bicep \
  --parameters infra/phases/05-postgresql/main.bicepparam \
  --parameters devClientIpAddress=$MY_IP
```

> ⚠ 배포 직후 PostgreSQL 메이저 버전·SKU 변경은 거의 불가능 (재생성 필요). what-if 의 PG 모듈 변경 라인을 반드시 사람 눈으로 한 번 검토 후 진행.

---

## 검증 시나리오

### 1) AAD admin 로그인 확인 (사용자 본인 IP 에서)

배포 후 사용자 본인은 PG role 이 없는 상태 (UAMI 만 admin). 검증 시간을 위해 본인 objectId 를 일시 admin 에 추가해 psql 로 접속 → 끝나면 회수.

```bash
# 본인 objectId 임시 admin 부여
ME_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
az postgres flexible-server ad-admin create \
  --resource-group rg-ai200challenge-dev \
  --server-name pg-ai200challenge-dev05 \
  --object-id $ME_OBJECT_ID \
  --display-name "$(az ad signed-in-user show --query userPrincipalName -o tsv)" \
  --type User

# Entra 토큰으로 psql 접속 (PgBouncer 경유, 6432)
TOKEN=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)
PGPASSWORD=$TOKEN psql \
  "host=pg-ai200challenge-dev05.postgres.database.azure.com port=6432 \
   dbname=kb user=$(az ad signed-in-user show --query userPrincipalName -o tsv) \
   sslmode=require"

# 안에서: \dx vector ; \dt chunks_* ; SELECT count(*) FROM chunks_hnsw;

# 검증 종료 후 본인 admin 회수
az postgres flexible-server ad-admin delete \
  --resource-group rg-ai200challenge-dev \
  --server-name pg-ai200challenge-dev05 \
  --object-id $ME_OBJECT_ID --yes
```

### 2) RAG 라우터 검증 — `?store=pg`

ACA api 는 internal ingress 라 한 번에 외부에서 못 친다. 검증 옵션 두 가지:
- (a) 같은 ACA 환경의 `web` 컨테이너 또는 별도 `console` 컨테이너에서 internal FQDN 호출
- (b) 임시로 ingress=external 토글 후 회수

(b) 최단 검증 흐름 (학습용):

```bash
# 임시 external 토글
az containerapp ingress update \
  --name ca-ai200challenge-api-dev \
  --resource-group rg-ai200challenge-dev \
  --type external

API_FQDN=$(az containerapp show -n ca-ai200challenge-api-dev -g rg-ai200challenge-dev \
  --query properties.configuration.ingress.fqdn -o tsv)

# index — pg 백엔드
curl -X POST "https://$API_FQDN/api/index?store=pg" \
  -H "content-type: application/json" \
  -d '{
    "workspace_id": "ws-eval",
    "chunks": [
      {"document_id": "doc-1", "ordinal": 0, "text": "Azure Database for PostgreSQL은 관리형 PG 서비스입니다."},
      {"document_id": "doc-1", "ordinal": 1, "text": "pgvector는 임베딩 벡터를 저장·검색하는 PostgreSQL 확장입니다."}
    ]
  }'

# 같은 데이터로 cosmos 도 적재 (비교용)
curl -X POST "https://$API_FQDN/api/index?store=cosmos" -H "content-type: application/json" -d '{...}'

# 검색 — pg / hnsw
curl -X POST "https://$API_FQDN/api/search?store=pg&index_kind=hnsw" \
  -H "content-type: application/json" \
  -d '{"workspace_id":"ws-eval","query":"벡터 검색이 뭐야?","top_k":3}'

# 검색 — pg / ivf
curl -X POST "https://$API_FQDN/api/search?store=pg&index_kind=ivf" -d '...'

# 검색 — cosmos (Phase 4 검증과 동일)
curl -X POST "https://$API_FQDN/api/search?store=cosmos" -d '...'

# external 회수
az containerapp ingress update \
  --name ca-ai200challenge-api-dev \
  --resource-group rg-ai200challenge-dev \
  --type internal
```

---

## Cosmos vs PG 비교 측정 (실측)

**측정 환경**: 5개 chunk (text-embedding-3-large = 3072-d) 적재 후 동일 한국어 쿼리("3072 차원 임베딩을 PostgreSQL 에 저장하려면 어떤 타입을 써야 하나요?") 로 워밍업 1회 + 측정 3회. ACA api (Korea Central) → AOAI embed → store. 데이터셋 규모가 작아 절대 수치는 트렌드 참고용.

| 항목 | Cosmos NoSQL (`quantizedFlat`) | PG `chunks_hnsw` (m=16, ef=64) | PG `chunks_ivf` (lists=100) |
|---|---|---|---|
| 평균 응답 (s, 3회 평균, end-to-end) | **0.22** | **0.16** | **0.17** |
| top-1 doc 일치 | doc-pg | doc-pg | doc-pg |
| top-1 raw distance | 0.5463 | 0.4537 | 0.4537 |
| 인덱스 빌드 시간 | n/a (자동) | 부트스트랩 즉시 (5건 < 1ms) | 부트스트랩 즉시 |
| 쓰기 처리량 (5건 batch 한 번) | 정상 | 정상 (양쪽 테이블에 동시 적재) | (HNSW 와 같은 한 호출) |
| 운영 복잡도 (체감) | 매니지드 인덱스, 키 회수만 | extension·인덱스 정의·풀·token 회전 모두 의식 | (HNSW 와 동일 기반) |
| 비용 (월, 학습 트래픽) | Serverless RU, 거의 0 | B1ms ~$13 | (PG 동일) |

> 관찰:
> - **end-to-end 시간의 dominant factor 는 AOAI embed 호출** (~150ms 추정). vector search 자체 latency 차이는 5건 규모에서 측정 불가.
> - **HNSW vs IVFFlat 차이는 무의미한 수준** (5건). N≥10⁴ 에서 HNSW 의 recall/latency 우위가 드러나는데, 학습용 데이터셋에는 의미 없음.
> - **score 척도**: 둘 다 cosine distance 기반이지만 raw 값은 store 별 표기 (Cosmos `VectorDistance` vs PG `<=>`). 직접 비교 X, top-1 매핑 일치만 확인.
> - **PgBouncer 측정은 SKU 제약으로 미수행** — General Purpose 이상에서 향후 재방문.

---

## 함정 · 교훈

- **사용자 식별 정보의 IaC 파일 노출 회피.** `devClientIpAddress` 같은 본인 공인 IP / Entra objectId / 거주지 단서를 `bicepparam` 에 박아 commit 하면 firewall allowlist 와 함께 git 에 영구 남아 공격면 정보가 된다. default 는 `'0.0.0.0'` / `''` 로 두고 배포 시점에 `-p key=$VAR` 로 override 주입. **CLAUDE.md §7 표준 룰로 반영함.**

- **PgBouncer 는 Burstable 컴퓨트 티어에서 미지원** (`ServerParameterToCMSPgBouncerNotSupportedForBurstable`). B1ms 같은 학습용 SKU 에서 `pgbouncer.enabled=true` 를 set 하면 즉시 deployment 실패. **결정**: SKU 를 General Purpose 로 올리는 비용을 부담하지 않고, 클라이언트 측 `psycopg_pool` 단일 풀링만으로 진행. PgBouncer 부분은 모듈 3 단원 6 의 의도적 생략으로 커버리지 표에 명시. AI-200 시험 운영 결정 포인트로 자주 등장.

- **PgBouncer sub-parameter 와 `pgbouncer.enabled` 의 순서 의존** (사실상 옵션 A 채택으로 무관해졌지만 학습 메모로 남김): `pgbouncer.default_pool_size`, `pgbouncer.pool_mode` 는 `pgbouncer.enabled=true` 가 *먼저 적용* 된 후에만 변경 가능 (`ServerParameterToCMSBlockedUpdateForDisabledPgBouncer`). Bicep 의 `items()` 함수는 키를 알파벳 순으로 정렬하므로 `default_pool_size` < `enabled` < `pool_mode` 순서가 되어 `default_pool_size` 가 먼저 시도되며 실패한다. 대처: 모듈 호출을 `enable` (→ `enabled`) 와 `tune` (→ sub-params) 둘로 쪼개고 `dependsOn` 으로 직렬화.

- **`register_vector_async` chicken-and-egg** — *cold start PG 에서 `psycopg_pool.AsyncConnectionPool.configure` 안에 `register_vector_async(conn)` 를 박으면 lifespan startup 이 실패한다.* vector type 이 PG 에 아직 없는데 (CREATE EXTENSION 미실행) 풀이 connection 마다 vector adapter 등록을 시도 → "vector type not found in the database" → connection 0개 → 30초 PoolTimeout → app 죽음. **대처**: 부트스트랩 SQL (`CREATE EXTENSION vector` 포함) 은 풀 *밖*의 short-lived `psycopg.AsyncConnection.connect()` 로 한 번 실행한 후, 그 다음에야 `_ensure_pool()` (= configure 에 register 포함) 을 호출해야 한다. 한 번이라도 vector extension 이 catalog 에 들어간 PG 라면 풀의 register 가 통과하므로, 운영 중 재시작은 문제 없음. (Phase 5 첫 배포 검증 시 임시로 본인 admin 권한으로 `CREATE EXTENSION vector` 수동 실행 후 ACA revision restart 로 우회 — 코드 fix 는 0.5.1 에서.)

- **AAD admin 등록 CLI 는 `microsoft-entra-admin` 서브명령어** (`az postgres flexible-server microsoft-entra-admin create ...`). 인터넷의 옛 문서에 보이는 `ad-admin` 은 현재 az CLI 에서 인식 안 됨 (`'ad-admin' is misspelled or not recognized`). 본 레포 검증 시나리오 / 학습 경로 문서 인용 시 항상 `microsoft-entra-admin` 사용.

- **Failed deployment 직후 즉시 재배포 시 `ServerIsBusy`**. PG flexible server 의 state 가 Ready 로 보여도 backend sub-operation (예: 파라미터 변경 롤백) 이 진행 중일 수 있다. 재시도 전 30~60초 grace 두기. 폴링하려면 `az postgres flexible-server show ... --query state` 로 Ready 확인 + 추가 30초 대기.

---

## 정리 (Phase 6 진입 직전)

본 Phase 의 PG 자원은 **Phase 6 (Redis 시맨틱 캐시) 진입 시점에 정리**한다. Cosmos 와 동일하게:

```bash
az postgres flexible-server delete \
  --name pg-ai200challenge-dev05 \
  --resource-group rg-ai200challenge-dev --yes
```

같은 이름 (`pg-ai200challenge-dev05`) 은 약 7일 간 soft-delete 상태로 남아 즉시 재배포 충돌 가능. 다른 접미사 (`dev06` 등) 를 사용해 재배포 가능.
