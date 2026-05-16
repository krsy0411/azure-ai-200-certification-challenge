# Phase 6 — Azure Managed Redis 로 AI 솔루션 향상

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/ (3 모듈 × 7 단원 = 21 단원)

> Phase 6 는 RAG 파이프라인의 **L1 시맨틱 캐시** + **pub/sub 알림** + (학습용) **Streams 큐** 를 Azure Managed Redis 로 구현하고, `chat.py` 를 RAG (PostgreSQL pgvector 검색 + AOAI 답변 생성) 로 완성한다. 메인 retrieval 은 Phase 5 의 PG (`halfvec(3072)` `chunks_hnsw`), Redis 는 그 앞단 캐시.

---

## 학습 경로 구성 (정독 결과)

| 모듈 | 단원 (7개씩) |
|---|---|
| **1. Azure Managed Redis 에서 데이터 작업 구현** | ① 소개 ② Azure Managed Redis 살펴보기 (계층 4종: 메모리 최적화 / **균형** / 컴퓨팅 최적화 / 플래시 미리보기) ③ 클라이언트 라이브러리 및 개발 모범 사례 ④ 데이터 작업 구현 (TTL · 캐시 무효화 · 캐시 배제 패턴) ⑤ 연습 — 데이터 작업 수행 ⑥ 평가 ⑦ 요약 |
| **2. 이벤트 메시징 구현** | ① 소개 ② Redis pub/sub 게시·구독 ③ Redis Streams 작업 큐 (컨슈머 그룹 · `XACK` · `XPENDING`/`XCLAIM`) ④ pub/sub vs Streams + **하이브리드 패턴** ⑤ 연습 — 이벤트 게시·구독 ⑥ 평가 ⑦ 요약 |
| **3. 벡터 스토리지 구현** | ① 소개 ② 인덱스 / 쿼리 (RediSearch `FT.CREATE` · `KNN`) ③ 벡터 형식·인덱싱 전략 (FLOAT32/FLOAT64 · FLAT/HNSW · COSINE/L2/IP · `EF_RUNTIME`) ④ HASH vs JSON 최적화 ⑤ 연습 — 의미 체계 검색 구현 ⑥ 평가 ⑦ 요약 |

---

## MS Learn 경로 커버리지 — 사용 / 생략

| 단원 / 학습 항목 | 본 프로젝트 적용 | 비고 |
|---|---|---|
| 모듈 1 ② 계층 4종 | ✅ **메모리 최적화 M10** 채택 | 학습 경로의 "dev/test 권장" 그대로 |
| 모듈 1 ③ 클라이언트 모범 사례 | ✅ `redis-py` (async) + 연결 풀 단일 인스턴스 + 재연결 백오프 | Entra 토큰 만료 (~1h) → 자동 재인증 콜백 |
| 모듈 1 ④ TTL / 캐시 무효화 / 캐시 배제 | ✅ 시맨틱 캐시 항목 TTL 24h, workspace 변경 시 `DEL sc:<workspaceId>:*` 무효화 | 캐시 배제 패턴 (read-through) 적용 |
| 모듈 1 ⑤ 연습 (데이터 작업) | ⚠ 본 레포는 시맨틱 캐시 구현이 응용 — 별도 연습 미수행 | 학습 경로 평가는 사용자가 별도 |
| 모듈 2 ② pub/sub | ✅ `ws:<workspaceId>:events` 채널 — 인덱싱 진행률 / 챗 토큰 fanout 알림 | SSE/WebSocket fanout |
| 모듈 2 ③ Streams + 컨슈머 그룹 | 🟡 **학습용 1개 흐름만** — 임베딩 재처리 (`stream:reembed`), `XACK` / `XPENDING` 시연 | **메인 작업 큐는 Phase 7 Service Bus 로 이관** |
| 모듈 2 ④ pub/sub vs Streams 하이브리드 | ✅ 같은 이벤트에 pub/sub (브로드캐스트) + Streams (작업 처리) 분리 | 학습 경로 권장 패턴 적용 |
| 모듈 3 ② `FT.CREATE` / `KNN` | ✅ `idx:semantic` 인덱스 + `KNN 5` 쿼리 | `FT.SEARCH` 로 top-K |
| 모듈 3 ③ 벡터 형식·인덱싱 | ✅ **HNSW + FLOAT32 + DIM 3072 + COSINE** — 학습 경로 "텍스트 검색(대형)" 권장 | FLOAT16/BFLOAT16/INT8 양자화는 학습 경로 본문 밖 → 미적용 |
| 모듈 3 ④ HASH vs JSON | ✅ **HASH** — 평면 스키마 + 필드별 인덱스 자연 매칭 | JSON 은 학습 커버리지로만 인지, 사용 X |
| **(학습 경로 밖)** 인증 모드 (AAD vs key) | ✅ **AAD-only** — Phase 4·5 일관성 | UAMI 단독 데이터 액세스 정책 |
| **(학습 경로 밖)** chat.py RAG 화 | ✅ Phase 6 에서 함께 — 시맨틱 캐시와 자연 결합 | 메인 retrieval = Phase 5 PG `chunks_hnsw` |

---

## 결정 (사용자 승인: 2026-05-13, A 조합)

| # | 결정 | 채택 | 근거 |
|---|---|---|---|
| 1 | 계층 | **메모리 최적화 M10** (Balanced_B0 / Memory_M10 중 최저) | 학습 경로 dev/test 권장 + 최저 비용 + RediSearch 포함 |
| 2 | 인증 | **AAD-only (UAMI 단일)** | Phase 4·5 일관성, CLAUDE.md §8 |
| 3 | 시맨틱 캐시 인덱스 | **HNSW + FLOAT32 + DIM 3072 + COSINE + HASH** | 학습 경로 권장 + placeholder 와 일치 |
| 4 | 메인 RAG retrieval | **PostgreSQL pgvector (재배포) + Redis L1 시맨틱 캐시** | Phase 5 halfvec 학습 자산 활용, §7 의 "다음 Phase 진입 시 재배포" 패턴 |
| 5 | pub/sub vs Streams | **pub/sub = 알림 / Streams = 학습용 1개 큐 (임베딩 재처리)** | 학습 경로 모듈 2 ④ 하이브리드 패턴, Phase 7 메인 큐와 역할 분리 |
| 6 | chat.py RAG 화 | **Phase 6 에서 함께** | 시맨틱 캐시 도입과 자연 결합 |

### 시맨틱 캐시 히트 기준

- 임베딩 코사인 유사도 ≥ **0.92** AND 같은 `workspaceId`
- TTL: **24h** (`EXPIRE sc:<id> 86400`)
- 캐시 무효화: workspace 의 PG 문서 변경 시 (Phase 7 이벤트 후 자동) 또는 수동 `/admin/cache:invalidate?workspaceId=...`

---

## 이 프로젝트에서의 적용

- **시맨틱 캐시**: 질문 임베딩 → Redis `KNN` 검색 (top-1) → 유사도 ≥ 0.92 + workspace 일치 시 캐시된 답변 반환, 아니면 PG retrieval + AOAI 생성 후 캐시에 저장
- **pub/sub**: `ws:<workspaceId>:events` 채널 — 문서 인덱싱 진행률·챗 토큰 fanout. SSE/WebSocket 구독자가 받아 클라이언트에 push
- **Streams (학습용)**: `stream:reembed` — 임베딩 재처리 작업 큐. 컨슈머 그룹 `reembed-workers`, `XACK` / `XPENDING` 시연
- `redis-py` (async) + Azure AD 토큰 (`DefaultAzureCredential` → `https://redis.azure.com/.default`) 인증

---

## 시맨틱 캐시 키 설계

```
FT.CREATE idx:semantic ON HASH PREFIX 1 sc:
  SCHEMA
    workspaceId TAG
    question    TEXT
    embedding   VECTOR HNSW 6
                DIM 3072
                TYPE FLOAT32
                DISTANCE_METRIC COSINE
    answer      TEXT
    tokens      NUMERIC
    createdAt   NUMERIC SORTABLE
```

키 패턴: `sc:<workspaceId>:<sha256(question)>`

---

## 아키텍처

```
[chat 요청]
    ↓ (1) 질문 임베딩 (AOAI text-embedding-3-large)
    ↓ (2) Redis FT.SEARCH idx:semantic KNN 1 + workspaceId filter
    ↓
    ├─ 히트 (sim ≥ 0.92) → 캐시된 answer 반환  [응답 끝]
    └─ 미스 → (3) PG chunks_hnsw 검색 (top-K=5)
              ↓ (4) AOAI gpt-4o-mini 답변 생성
              ↓ (5) HSET sc:<ws>:<hash> + EXPIRE 86400 + PUBLISH ws:<ws>:events 'cache:store'
              ↓ 응답 반환
```

- **pub/sub 채널**: `ws:<workspaceId>:events` — `cache:store` / `cache:invalidate` / `index:progress` 메시지
- **Streams**: `stream:reembed` — 임베딩 재처리 작업, 컨슈머 그룹 `reembed-workers`

---

## Bicep 모듈 구성

| 모듈 | 책임 |
|---|---|
| `infra/modules/redis-enterprise.bicep` | `Microsoft.Cache/redisEnterprise` 클러스터 — Memory_M10 / koreacentral / TLS 1.2 |
| `infra/modules/redis-enterprise-database.bicep` | `databases` 자식 자원 — RediSearch 모듈 활성화, EvictionPolicy `NoEviction` (RediSearch 활성 시 강제) |
| `infra/modules/redis-access-policy-assignment.bicep` | UAMI 에 `Data Owner` 데이터 액세스 정책 부여 (AAD-only) |
| `infra/phases/06-managed-redis/main.bicep` | 위 모듈 + Phase 5 PG (`existing` 참조) + Phase 4 AOAI (`existing` 참조, `chat.py` RAG 답변 생성용) 조립 |
| `infra/phases/06-managed-redis/main.bicepparam` | `devClientIpAddress=''` / `userObjectId=''` default + 배포 시 `-p` override |

### 학습 경로 § 1 — 정독 결과를 그대로 Bicep 결정으로 매핑

- `kind: 'redisEnterprise'` + `sku.name: 'Memory_M10'` (학습 경로 모듈 1 ② dev/test 권장)
- `databases[0].properties.modules: [{ name: 'RediSearch' }]` (학습 경로 모듈 3 의 `FT.CREATE` 전제)
- `accessKeysAuthentication: 'Disabled'` + `accessPolicyAssignments` 로 UAMI 만 (§8)
- `databases[0].properties.clusteringPolicy: 'EnterpriseCluster'` + `evictionPolicy: 'NoEviction'` (**RediSearch 활성 시 강제** — 함정 1)
- TTL 캐시 정리는 evictionPolicy 가 아니라 키별 `EXPIRE 86400` 으로 처리

---

## 앱 코드

| 파일 | 역할 |
|---|---|
| `apps/api/src/cache/redis_client.py` | `redis-py.asyncio` 클라이언트 + Entra 토큰 재인증 콜백 |
| `apps/api/src/cache/semantic.py` | 시맨틱 캐시 read/write + `FT.SEARCH` KNN + 유사도 임계 |
| `apps/api/src/messaging/pubsub.py` | pub/sub publisher + subscriber (SSE 라우터에서 호출) |
| `apps/api/src/messaging/streams.py` | Streams `XADD` / `XREADGROUP` / `XACK` (학습용 1개 흐름) |
| `apps/api/src/routers/chat.py` | **RAG 화** — 시맨틱 캐시 → PG 검색 → AOAI 답변. SSE 스트리밍 |
| `apps/api/src/routers/index_search.py` | 기존 유지 (Cosmos/PG 비교용), 변경 없음 |
| `apps/api/src/main.py` | lifespan 에 RedisClient 추가, 버전 `0.6.0` |

### 핵심 동작

- **Entra 토큰 재인증**: `redis-py` 의 `credential_provider` 콜백으로 토큰 만료 (~1h) 시 자동 갱신
- **시맨틱 캐시 미스 시 동시 요청 race**: `SETNX sc:lock:<hash>` 단순 락 → 첫 요청만 PG/AOAI 호출, 나머지는 락 해제 후 캐시 재조회

---

## 이미지 빌드 · 푸시 (Phase 6 새 이미지)

```bash
cd apps/api
docker build --platform linux/amd64 -t acrai200challengedev04.azurecr.io/api:0.6.0 .
az acr login --name acrai200challengedev04
docker push acrai200challengedev04.azurecr.io/api:0.6.0
```

---

## 배포 명령

### 사전 조건 — Phase 5 PG / Phase 4 AOAI 재배포

§7 의 "다음 Phase 진입 시 재배포" 패턴. Phase 6 의 `main.bicep` 이 `existing` 참조하므로 먼저 살려둠.

override 변수 — 각 phase 의 main.bicep 이 `default` 없는 파라미터를 무엇으로 요구하는지에 따라 다름:
- Phase 4: 모든 값이 bicepparam 에 — override 불필요
- Phase 5: `devClientIpAddress` 만 override (CLAUDE.md §8 — IaC 에 IP 박지 않음)
- Phase 6: 모든 값이 bicepparam 에 — override 불필요 (Redis 는 firewall / 사용자 admin 없음)

```bash
# Phase 4 (Cosmos + AOAI) 재배포 — 같은 이름 충돌 시 dev05 로 접미사 ↑
az deployment group create \
  -g rg-ai200challenge-dev \
  -p infra/phases/04-cosmos-aoai/main.bicepparam

# Phase 5 (PG) 재배포 — soft-delete 7일 충돌 시 dev06 으로
az deployment group create \
  -g rg-ai200challenge-dev \
  -p infra/phases/05-postgresql/main.bicepparam \
  -p devClientIpAddress=$DEV_IP
```

### Phase 6 본 배포

```bash
az deployment group what-if \
  -g rg-ai200challenge-dev \
  -p infra/phases/06-managed-redis/main.bicepparam

az deployment group create \
  -g rg-ai200challenge-dev \
  -p infra/phases/06-managed-redis/main.bicepparam
```

배포 후 ACA api revision 갱신 (env 변수 `REDIS_HOST`, `AOAI_ENDPOINT`, `PG_HOST` 주입):

```bash
az containerapp update \
  -g rg-ai200challenge-dev \
  -n ca-ai200challenge-api-dev \
  --image acrai200challengedev04.azurecr.io/api:0.6.0 \
  --set-env-vars REDIS_HOST=<redis-fqdn> REDIS_PORT=10000
```

---

## 검증 시나리오 (단계 5 — `/phase-verify`)

### 1) 자원·권한 헬스

- `az redisenterprise show` → `provisioningState: Succeeded`, `Memory_M10`
- `az redisenterprise database show` → modules 에 `RediSearch` 포함
- `az redisenterprise access-policy-assignment list` → UAMI principalId 1개만, `Data Owner`

### 2) 시맨틱 캐시 — 콜드 → 웜 라운드트립

```bash
# 1차 (cold) — PG 검색 + AOAI 생성
time curl -X POST $API/chat -d '{"workspaceId":"ws-test","question":"Azure OpenAI 의 임베딩 모델은?"}'

# 2차 (warm) — 시맨틱 캐시 히트
time curl -X POST $API/chat -d '{"workspaceId":"ws-test","question":"AOAI 임베딩 모델이 뭔가요?"}'  # 의미 유사
```

기대: 1차 ~2s, 2차 < 0.3s (AOAI 호출 회피)

### 3) pub/sub 라운드트립

```bash
# 구독 (한 터미널)
redis-cli -h <redis-fqdn> -p 10000 --tls -a <token> SUBSCRIBE 'ws:ws-test:events'

# 발행 (다른 터미널 — API 가 자동으로)
curl -X POST $API/chat ... # cache:store 메시지가 구독자에 도착
```

### 4) Streams — `XACK` 흐름

```bash
redis-cli ... XADD stream:reembed '*' chunkId 'c-001'
redis-cli ... XREADGROUP GROUP reembed-workers worker-1 COUNT 1 STREAMS stream:reembed '>'
redis-cli ... XACK stream:reembed reembed-workers <id>
redis-cli ... XPENDING stream:reembed reembed-workers  # 미처리 0 확인
```

### 5) KQL — 캐시 히트율·p50

```kusto
ContainerAppConsoleLogs_CL
| where Log_s contains "semantic_cache"
| extend hit = tobool(parse_json(Log_s).hit)
| summarize total=count(), hits=countif(hit==true) by bin(TimeGenerated, 5m)
| extend hitRate = todouble(hits) / total
```

---

## 측정 결과 (실측, 2026-05-16, 5건 chunk dataset, api 0.6.3)

| 시나리오 | 응답시간 | cache_hit | similarity | 비고 |
|---|---|---|---|---|
| **run 1** — 첫 캐시 hit (이전 store 분, 동일 질문) | 1.50s | true | 1.0000 | 임베딩 호출만, AOAI chat / PG 검색 skip |
| **run 2** — paraphrase ("AOAI 의 embedding 모델?") | 1.52s | false | (miss) | threshold 0.92 미달 — 한국어 paraphrase 의 cosine 유사도가 보수적 임계값에 못 미침. PG retrieval + AOAI 생성 → store |
| **run 3** — 다른 topic ("PostgreSQL 벡터 검색?") | 1.62s | false | (miss) | sources 5건 정상, top score 0.36 = doc-pg |
| **run 4** — 다른 ws ("ws-other", 같은 Q) | 0.28s | false | (miss) | "워크스페이스에 답할 만한 문서 없음" — TAG filter 로 ws 격리 OK, AOAI 호출 skip |

### 관찰

- **임베딩 호출이 dominant**: AOAI text-embedding-3-large 호출이 시맨틱 캐시 hit/miss 결정에 매번 필요해 캐시 hit 응답시간조차 1.5s. Phase 5 측정과 동일 결론 (AOAI embed 가 stage 시간의 80%+).
- **paraphrase miss 는 *임계값* 의 의도된 효과**: similarity 0.92 가 한국어 paraphrase 까지 흡수하기엔 보수적. 0.85~0.88 로 낮추면 hit rate 증가하지만 *의미적으로 다른* 질문이 같이 잡힐 수 있음 — trade-off 는 향후 사용자 데이터 누적 후 `REDIS_SEMANTIC_THRESHOLD` 환경변수로 재조정.
- **ws 격리**: TAG filter 정확히 작동 (함정 4 escape 적용 후) — 다른 workspace 의 캐시 entry 가 lookup 에 안 잡힘.

### pub/sub / Streams — 별도 검증 미수행

별도 redis-cli + AAD 토큰 부여가 필요해 단계 5 에서는 *API 통한 간접 검증* 만 수행 (chat → `cache:store` publish 가 발생, KQL `INFO ... POST /api/chat 200 OK` 로 라우터 도달 확인). 정식 SSE/WebSocket fanout 측정은 Phase 7 에서 함께.

---

## 함정 · 교훈

1. **RediSearch 활성 database 는 evictionPolicy='NoEviction' 강제** — placeholder 와 학습 경로 권장 (VolatileLRU) 을 따라 Bicep 을 짰다가 what-if 단계에서 `BadRequest: 'properties.evictionPolicy' must be set to NoEviction when using the RediSearch module` 으로 차단됨. 학습 경로 본문에는 강조되지 않은 Azure Managed Redis 측 제약. **TTL 기반 캐시 정리는 키별 `EXPIRE` 로 충분**하므로 eviction 부재가 시맨틱 캐시 동작에 영향 없음 (만료된 키는 다음 접근 시 자연 삭제).

2. **redis-py 5.x 의 `ConnectionPool` 은 `ssl` kwarg 를 받지 않음** — `TypeError: AbstractConnection.__init__() got an unexpected keyword argument 'ssl'` 로 컨테이너가 ASGI lifespan 단계에서 죽음 (ACA revision Unhealthy + ActivationFailed). TLS 는 `ssl=True` 가 아니라 `connection_class=redis.asyncio.SSLConnection` 으로 지정해야 한다 (`Redis.from_url("rediss://...")` 도 가능하지만 토큰 갱신 패턴엔 부적합). `apps/api/src/cache/redis_client.py` 의 `_ensure_client` 에서 fix.
    ```python
    connection_class = redis.SSLConnection if self._s.tls else redis.Connection
    self._pool = redis.ConnectionPool(connection_class=connection_class, ...)
    ```

3. **Azure Managed Redis 의 AAD 인증 username 은 `'default'` 가 아닌 principal objectId** — TLS fix 후 다음 단계 (AUTH) 에서 `redis.exceptions.AuthenticationError: invalid username-password pair` 발생. Azure Managed Redis 의 AAD 인증 사양 (`/azure/redis/entra-for-authentication`) 에 명시: **User = Object ID of your managed identity or service principal**, Password = Entra access token. 학습 경로 본문에는 강조 안 됨. UAMI 의 경우 `clientId`(=Application ID, env `AZURE_CLIENT_ID`) 가 아니라 `principalId` (=objectId) 를 써야 한다 — 둘이 다른 UUID 이라 헷갈리기 쉬움. fix:
    - Bicep main.bicep: `REDIS_USERNAME: uami.properties.principalId` envVar 추가
    - 코드 `redis_client.py`: `RedisSettings.username` 필드 추가, `ConnectionPool(username=self._s.username, ...)` 로 전달

4. **RediSearch TAG 필드 값의 하이픈/특수문자는 escape 필수** — `@workspaceId:{ws-test}` 같이 짠 쿼리가 `Syntax error at offset 17 near ws` 로 실패. `ws-test` 의 하이픈이 토크나이저에서 단어 경계로 인식돼 파싱 깨짐. 첫 lookup 이 매번 ResponseError → cache miss → 시맨틱 캐시가 사실상 동작 안 함 (store 자체는 성공, lookup 만 실패). 공식 문서 (`/docs/develop/interact/search-and-query/advanced-concepts/tags/`) 에 escape 대상 문자 명시: `,.<>{}[]"':;!@#$%^&*()-+=~` 와 공백. fix — `_escape_tag()` 헬퍼로 모든 TAG 값을 `\` 로 escape:
    ```python
    ws = _escape_tag(workspace_id)  # ws-test → ws\-test
    Query(f"(@workspaceId:{{{ws}}})=>[KNN 1 @embedding $vec AS vector_score]")
    ```
    **재현 — 디버깅 우선순위 함정**: lookup 실패가 Exception → None 으로 흡수돼 정상 cache-miss 분기를 타기 때문에, API 응답만 보면 "캐시 store 가 안 됨" 으로 오해하기 쉬움. 반드시 컨테이너 로그 (`semantic cache lookup failed`) 확인.

5. **az CLI 의 redisenterprise 응답은 ARM properties 가 평면화됨** — 학습 경로/공식 ARM ref 의 JSON 구조는 `properties.hostName` 인데 `az redisenterprise show` 응답은 그냥 `hostName` (루트 레벨). 검증 시 `--query "properties.hostName"` 으로 짜면 null. 정정: `--query "hostName"`. databases 도 cluster show 응답의 `databases[]` 배열로 같이 옴.
6. *TBD* — Entra 토큰 만료 시 재인증 콜백 패턴 (현재 풀 재생성으로 처리, AUTH 명령 패턴 추가 검토)
7. *TBD* — RediSearch 인덱스 재생성 시 데이터 보존 여부
8. *TBD* — HNSW `EF_RUNTIME` 튜닝 vs 정확도

---

## 정리 (Phase 7 진입 직전)

사용자 명시 요청 후:

```bash
# Phase 6 phase-specific 자원
az redisenterprise delete -g rg-ai200challenge-dev -n <redis-name> --yes

# Phase 5 / 4 데이터 자원 (Phase 7 진입 직전 다시 정리)
az postgres flexible-server delete ... --yes
az cognitiveservices account delete ...  # AOAI
az cosmosdb delete ...
```

§7 룰: ACR / LAW / UAMI / CAE / AKS / Application Insights 는 보존.
