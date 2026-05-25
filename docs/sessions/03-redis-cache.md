# session-03 — Managed Redis 시맨틱 캐시

> **관련 Microsoft Learn 학습 경로**
>
> - [Enhance AI solutions with Azure Managed Redis](https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [session-00](./00-setup.md), [session-01](./01-rag-mvp.md) 완료 — Azure OpenAI · Azure Container Apps · User Assigned Managed Identity · Application Insights 가 본인 구독에 존재
> - (선택) [session-02](./02-pgvector.md) 완료 — 두 벡터 백엔드의 latency 베이스라인이 있으면 캐시 효과 측정 시 비교가 풍부함
> - `git checkout session-03-start` 명령어 수행

---

## 0. 이 세션에서 경험하는 내용

- **한 문장 골** — "회사 휴가 정책 알려줘" 와 "휴가 규정이 어떻게 돼?" 처럼 의미상 같은 두 질문을 Managed Redis 가 동일하다고 판단해, 두 번째 호출이 100ms 이하로 응답되는 시맨틱 캐시를 도입
- **새로 프로비저닝되는 자원**
  - Managed Redis 클러스터 `redis-ai200ws-dev` (Azure Managed Redis · Memory_M10 등급)
  - Managed Redis Database — RediSearch 모듈 포함, `evictionPolicy=NoEviction`
  - Access policy assignment — User Assigned Managed Identity 의 principal objectId 를 Redis access policy 에 부여
- **사용해볼 SDK / CLI**
  - `redis-py` 5.x async 클라이언트 + `azure.identity` 토큰 인증
  - RediSearch `FT.CREATE` (벡터 인덱스 생성) + `FT.SEARCH` KNN (시맨틱 검색)
  - OpenTelemetry 커스텀 span 에 `cache_hit` 속성 부여
- **Portal 에서 확인할 지표 / 데이터**
  - Managed Redis → Console — 브라우저 안의 redis-cli 에서 `FT.INFO`, `KEYS *` 로 캐시 키 직접 조회
  - Managed Redis → Metrics — Ops/sec · Cache hits 그래프
  - Application Insights → Logs (KQL) — `cache_hit` 커스텀 메트릭의 hit / miss 분포

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈 한눈에 보기

이 세션이 배포하는 Bicep 모듈 (`infra/sessions/03-redis-cache/main.bicep`).

- `redis-enterprise.bicep` — Memory_M10 클러스터 (Azure Managed Redis Enterprise)
- `redis-enterprise-database.bicep` — RediSearch 모듈 포함, `evictionPolicy=NoEviction` 명시
- `redis-access-policy-assignment.bicep` — User Assigned Managed Identity 의 principal objectId 를 Redis access policy 에 부여

### 1.2 변경사항 미리보기

```bash
# 본인 식별 정보 + 공용 User Assigned Managed Identity 의 objectId 를 명령어 인자로 직접 전달
OID=$(az ad signed-in-user show --query id -o tsv)
UAMI_OID=$(az identity show \
  --name id-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --query principalId -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/03-redis-cache/main.bicep \
  --parameters infra/sessions/03-redis-cache/main.bicepparam \
  --parameters userObjectId=$OID uamiObjectId=$UAMI_OID
```

> [!CAUTION]
> **`uamiObjectId` 는 User Assigned Managed Identity 의 `principalId`** 입니다. `clientId` 와 헷갈리기 쉽지만 둘은 다른 UUID 입니다. Redis access policy 는 반드시 `principalId` (= objectId) 를 사용합니다.

### 1.3 실제 배포

```bash
az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/03-redis-cache/main.bicep \
  --parameters infra/sessions/03-redis-cache/main.bicepparam \
  --parameters userObjectId=$OID uamiObjectId=$UAMI_OID
```

> [!NOTE]
> Managed Redis Enterprise 클러스터 생성에 약 **8~12분** 소요됩니다. 본 워크샵에서 가장 오래 걸리는 배포 중 하나입니다. 진행되는 동안 [2단계 · 복붙으로 경험해보기](#2단계--복붙으로-경험해보기) 의 캐시 전략 트레이드오프와 복붙 코드를 정독합니다.

> [!CAUTION]
> **비용 안내** — Memory_M10 등급은 약 ₩11,680/일 (시간당 약 ₩487) 의 idle 비용이 발생합니다. 본 워크샵에서 가장 비싼 단일 자원입니다. 세션을 마친 뒤에는 즉시 [자원 정리](../cleanup.md) 를 수행합니다.

### 1.4 배포 완료 확인

```bash
az redisenterprise show \
  --name redis-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --query "{state:resourceState, sku:sku.name, host:hostName}" -o jsonc
```

기대 — `state: Running`, `sku: EnterpriseMemoryOptimized_M10`.

---

## 2단계 · 복붙으로 경험해보기

### 2.1 캐시 전략 트레이드오프

RAG 응답을 캐싱할 때 세 가지 전략이 있습니다.

| 전략 | 캐시 키 | 히트 조건 | 장점 | 단점 |
|---|---|---|---|---|
| **정확 매칭** | `hash(질문 문자열)` | 두 질문의 문자열이 완전히 동일 | 구현 단순 · 검색 비용 거의 0 | "휴가 정책 알려줘" 와 "휴가 규정이 어떻게 돼?" 가 다른 키로 분리되어 hit 율이 매우 낮음 |
| **시맨틱 유사도** | 질문 임베딩 벡터 | 새 질문의 임베딩이 기존 캐시 키의 임베딩과 cosine 유사도 ≥ 임계값 | paraphrase 흡수 · hit 율 높음 | 임계값 튜닝 필요 · 잘못된 hit 위험 |
| **RAG 인지 (튜플)** | (질문 임베딩, 사용 문서 셋) | 의미 + 문서 셋 모두 일치 | 문서 변경 시 자동 무효화 | 캐시 키 공간이 커지고 hit 율이 다소 떨어짐 |

본 워크샵은 **시맨틱 유사도 + 임계값 0.92** (한국어 paraphrase 에 대해 보수적) + TTL 24h 를 채택합니다.

> [!TIP]
> **시험 단골 패턴** — "RAG 응답 캐싱은 문자열 매칭으로 부족하다 — 임베딩 기반 시맨틱 캐시" 가 정답입니다. 임계값을 너무 낮추면 잘못된 hit, 너무 높이면 캐시가 거의 비어 있으므로 0.90 ~ 0.95 범위에서 튜닝합니다.

### 2.2 코드 복사·붙여넣기

> [!NOTE]
> 아래 두 파일은 그대로 복사해 해당 경로에 붙여넣습니다. 동작 원리는 코드 다음의 줄별 해설에서 다룹니다.

**파일 1** — `apps/api/src/cache/redis_client.py`

```python
# (redis-py 5.x 비동기 클라이언트 — Entra ID 토큰을 비밀번호로 사용.
#  핵심 구성:
#  - DefaultAzureCredential 로 Redis access scope 토큰 획득
#  - username = User Assigned Managed Identity 의 principal objectId (clientId 가 아님)
#  - SSL 옵션은 redis-py 5.x 에서 ssl=True 가 ConnectionPool 에 직접 전달되지 않으므로
#    connection_class=redis.SSLConnection 로 지정
#  - 토큰 만료 시 자동 재발급
#  실제 코드 본문은 후속 구현 단계에서 작성합니다.)
```

**파일 2** — `apps/api/src/cache/semantic.py`

```python
# (시맨틱 캐시 미들웨어.
#  핵심 구성:
#  - FT.CREATE: HNSW 벡터 인덱스 + VECTOR DIM 3072 + DISTANCE_METRIC COSINE
#  - lookup(질문): 질문을 임베드 → FT.SEARCH KNN(1) → cosine ≥ 0.92 면 hit 반환
#  - store(질문, 답변, sources): miss 인 경우 결과를 SET 으로 저장, TTL 24h
#  - OpenTelemetry span 'cache.lookup' 에 cache_hit=true/false 속성 부여
#  - TAG 필드에 하이픈 (-) 이 들어가는 경우 escape 처리 (예: 'ws\\-test')
#  실제 코드 본문은 후속 구현 단계에서 작성합니다.)
```

### 2.3 빌드 · 배포 · 호출

다음 명령을 그대로 복사해 순서대로 실행합니다.

```bash
# 1) Azure Container Registry 로그인
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)
az acr login --name $ACR_NAME

# 2) API 이미지 빌드 — 세션 태그 :s03
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/api:s03 apps/api
docker push $ACR_NAME.azurecr.io/api:s03

# 3) Azure Container Apps revision 업데이트
az containerapp update \
  --name ca-api-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --image $ACR_NAME.azurecr.io/api:s03

# 4) 외부 FQDN 가져오기
API_FQDN=$(az containerapp show \
  -n ca-api-ai200ws-dev \
  -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)
```

#### 캐시 효과 측정 — 의미는 같지만 표현이 다른 두 질문

```bash
# 첫 호출 — 캐시 miss 예상 (응답 시간 측정)
time curl -sX POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q": "회사 휴가 정책 알려줘"}' > /dev/null

# 두 번째 호출 — 의미상 같은 paraphrase. 시맨틱 캐시 hit 예상
time curl -sX POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q": "휴가 규정이 어떻게 돼?"}' > /dev/null
```

기대 결과 — 첫 호출은 약 800~1500ms, 두 번째 호출은 100ms 이하.

---

## 3단계 · Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **Managed Redis `redis-ai200ws-dev`** → **Console** (브라우저 안의 redis-cli) — 다음 명령을 한 줄씩 실행

   ```
   FT._LIST
   FT.INFO rag_cache_idx
   KEYS rag:*
   ```

   기대 — `FT._LIST` 결과에 `rag_cache_idx` 가 노출, `FT.INFO` 의 `num_docs` 가 위에서 호출한 횟수만큼 증가, `KEYS rag:*` 에 캐시된 키들이 노출됩니다.

2. **Managed Redis** → **Metrics** → 다음 두 메트릭 추가
   - `Operations Per Second` — `curl` 호출 직후 스파이크
   - `Cache Hits` — 두 번째 호출 시점에 1 증가

3. **Application Insights** → **Logs** 에서 다음 KQL 실행

   ```kusto
   customMetrics
   | where name == "cache_hit"
   | summarize hit=countif(value==1), miss=countif(value==0) by bin(timestamp, 1m)
   | render columnchart
   ```

   기대 — 첫 호출 시점에 miss 가 1, 두 번째 호출 시점에 hit 가 1 로 시각화됩니다.

4. **Application Insights** → **Transaction search** → 가장 최근의 `POST /api/chat` 두 건 비교
   - 첫 건은 `cache.lookup` span 의 duration 이 짧고 (miss 라 곧바로 빠져나옴) 그 뒤 `rag.retrieve` · `rag.generate` span 이 이어짐
   - 두 번째 건은 `cache.lookup` 만 보이고 그 뒤 span 들이 없음 (캐시 hit 라 RAG 우회)

---

## 주의

> [!CAUTION]
> **RediSearch 데이터베이스는 `evictionPolicy=NoEviction` 필수** — `VolatileLRU` 같은 eviction policy 와 RediSearch 인덱스가 충돌해 `FT.SEARCH` 결과가 stale 해집니다. Bicep 에서 `evictionPolicy: 'NoEviction'` 을 명시합니다.

> [!CAUTION]
> **Entra ID username 자리에 principal objectId 사용** — `clientId` 와 `principalId` 모두 UUID 형식이지만 다른 값입니다. Redis 연결이 `NOAUTH` 또는 `WRONGPASS` 로 실패하면 `principalId` 가 맞는지 다시 확인합니다. User Assigned Managed Identity 의 경우 `az identity show --query principalId -o tsv` 로 확인합니다.

> [!WARNING]
> **redis-py 5.x `ConnectionPool` 은 `ssl=` kwarg 미지원** — `ssl=True` 를 그대로 전달하면 무시되거나 오류가 발생합니다. `connection_class=redis.SSLConnection` 으로 지정해야 SSL 이 적용됩니다.

> [!WARNING]
> **RediSearch TAG 필드의 하이픈은 escape 필수** — 예를 들어 TAG 값에 `ws-test` 가 있으면 쿼리에서 `ws\\-test` 로 escape 해야 합니다. escape 누락 시 silent miss 가 발생해 캐시 hit 율이 항상 0% 로 나타나는데, 원인이 매우 추적하기 어렵습니다.

> [!NOTE]
> **`az redisenterprise show` 응답 구조는 다른 ARM 자원과 다름** — 일반적인 ARM 자원의 `properties.xxx` 형태가 아니라 평탄화된 구조 (`resourceState`, `hostName` 등이 최상위) 입니다. Bicep output 작성 시 이 점을 고려합니다.

> [!IMPORTANT]
> 더 자세한 함정 모음은 [docs/pitfalls/common.md](../pitfalls/common.md) 의 [벡터 · 인덱싱](../pitfalls/common.md#벡터--인덱싱) 섹션을 참고합니다.

---

## 마무리

- **save-point** — `git tag session-03-complete`
- **자원 정리** — Managed Redis 는 본 워크샵에서 가장 비싼 idle 자원입니다. 본 세션 학습이 끝났다면 [자원 정리](../cleanup.md) 의 `session-03 의 Redis 만 정리` 절차로 즉시 정리하는 것을 권장합니다. 후속 세션에서 캐시를 다시 쓰고 싶으면 본 세션 Bicep 을 재배포합니다
- **다음 세션 미리보기** — [session-04](./04-async-ingestion.md) 에서는 동기 호출이 아닌 *비동기 인제스션 파이프라인* 을 구축합니다. PDF 한 장을 Blob Storage 에 업로드하면 Event Grid → Service Bus → Azure Functions 경로로 자동 청크 분할 · 임베드 · 인덱스 적재가 일어납니다

---

## 참고 자료

- Microsoft Learn — [Enhance AI solutions with Azure Managed Redis](https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/)
- RediSearch — [Vector similarity search](https://redis.io/docs/latest/develop/interact/search-and-query/advanced-concepts/vectors/)
- 본 저장소 — `infra/sessions/03-redis-cache/main.bicep`, `apps/api/src/cache/`

---

👈 [session-02 — PostgreSQL pgvector 비교](./02-pgvector.md) | [session-04 — 비동기 인제스션 (Service Bus + Event Grid + Functions)](./04-async-ingestion.md) 👉
