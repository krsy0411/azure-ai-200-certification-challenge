# session-03 — Managed Redis 시맨틱 캐시

> 학습 경로 매핑: [Enhance AI solutions with Azure Managed Redis](https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/)  
> 사전 조건: session-01·session-02 완료, `git checkout session-03-start`

---

## 0. 이 세션에서 무엇을 경험하나

- **한 문장 골**: "회사 휴가 정책 알려줘" 와 "휴가 규정이 어떻게 돼?" 가 의미상 같다는 걸 Redis 가 알아채서 두 번째 호출은 캐시 히트.
- **새로 프로비저닝되는 자원**:
  - Redis Enterprise (Memory_M10) — Azure Managed Redis
  - Redis Enterprise Database (RediSearch 모듈, `NoEviction`)
  - Access policy assignment (UAMI 에 entra 인증)
- **사용해볼 SDK/CLI**:
  - `redis-py` 5.x + `azure.identity` (AAD 토큰 인증)
  - RediSearch `FT.CREATE` (벡터 인덱스) + `FT.SEARCH` (KNN)
- **Portal 에서 확인할 지표/데이터**:
  - Redis Enterprise → Console — `FT.INFO`, `KEYS *` 확인
  - Redis Enterprise → Metrics — Ops/sec, Cache hits 그래프
  - App Insights → Logs (KQL) → `cache_hit` 커스텀 메트릭 분포

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈

- `redis-enterprise.bicep` — Memory_M10 클러스터
- `redis-enterprise-database.bicep` — RediSearch 모듈 포함, `evictionPolicy=NoEviction`
- `redis-access-policy-assignment.bicep` — UAMI 의 **objectId** 를 access policy 에 부여

### 1.2 배포

```bash
OID=$(az ad signed-in-user show --query id -o tsv)
UAMI_OID=$(az identity show -n id-ai200ws-dev -g rg-ai200ws-dev --query principalId -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/03-redis-cache/main.bicep \
  --parameters infra/sessions/03-redis-cache/main.bicepparam \
  --parameters userObjectId=$OID uamiObjectId=$UAMI_OID

az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/03-redis-cache/main.bicep \
  --parameters infra/sessions/03-redis-cache/main.bicepparam \
  --parameters userObjectId=$OID uamiObjectId=$UAMI_OID
```

> ⏱ Redis Enterprise 가 **8~12분** 으로 본 워크샵에서 가장 오래 걸립니다. 진행되는 동안 §2 의 캐시 전략 강의를 정독.
>
> ⚠️ **비용 경고**: Memory_M10 ≈ ₩11,680/일. 워크샵 끝나면 즉시 정리.

### 1.3 배포 완료 확인

```bash
az redisenterprise show -n redis-ai200ws-dev -g rg-ai200ws-dev \
  --query "{state:resourceState, sku:sku.name}" -o jsonc
# 기대: provisioningState=Succeeded, sku=EnterpriseMemoryOptimized_M10
```

---

## 2단계 · 복붙으로 경험해보기

### 2.1 캐시 전략 트레이드오프

| 전략 | 키 | 히트 조건 | 장점 | 단점 |
|---|---|---|---|---|
| **정확 일치** | `hash(question)` | 문자열 동일 | 단순, 빠름 | "휴가 정책 알려줘" ≠ "휴가 규정이 어떻게 돼?" |
| **시맨틱 유사도** | embedding 벡터 | 의미 유사 (cosine ≥ 임계) | paraphrase 흡수 | 임계 튜닝 / 잘못된 히트 위험 |
| **RAG-aware (튜플)** | `(question_emb, doc_set)` | 의미 + 문서셋 동일 | 문서 변경 시 자동 무효화 | 키 공간이 큼 |

본 워크샵은 **시맨틱 유사도 + 임계 0.92** (한국어 paraphrase 에 보수적) + TTL 24h.

> 🎯 **AI-200 시험 포인트**: "RAG 응답 캐싱은 단순 string 매칭이 안 통한다 — 임베딩 유사도 캐시" — 단골 패턴.

### 2.2 코드 복사·붙여넣기

**파일 1**: `apps/api/src/cache/redis_client.py`

```python
# (redis-py 5.x 비동기 클라이언트.
#  - AAD 토큰을 비밀번호로 사용 (DefaultAzureCredential)
#  - username = UAMI 의 principal objectId (clientId 아님!)
#  - ssl=True 가 아니라 connection_class=redis.SSLConnection 사용 (redis-py 5.x kwarg 미지원)
#  - 토큰 만료 시 재발급
#  실제 코드는 후속 구현 단계.)
```

**파일 2**: `apps/api/src/cache/semantic.py`

```python
# (시맨틱 캐시 미들웨어.
#  - RediSearch FT.CREATE: HNSW 벡터 인덱스 + VECTOR DIM 3072 + DISTANCE_METRIC COSINE
#  - lookup: 질문을 embed → FT.SEARCH KNN(1) → cosine ≥ 0.92 면 hit
#  - store: miss 일 때 답변·sources 와 함께 SET, TTL 24h
#  - OTel span: cache.lookup 에 cache_hit=true/false 속성
#  - TAG 필드에 하이픈 들어가면 escape 필수 (\\-)
#  실제 코드는 후속 구현.)
```

### 2.3 빌드·배포·호출

```bash
# 1) 이미지 빌드·푸시 (이번엔 :s03 태그)
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/api:s03 apps/api
docker push $ACR_NAME.azurecr.io/api:s03

# 2) ACA 업데이트
az containerapp update -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --image $ACR_NAME.azurecr.io/api:s03

# 3) 동일한 의미의 질문 2회 호출 → 두 번째가 훨씬 빠른지
API_FQDN=$(az containerapp show -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)

time curl -sX POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q": "회사 휴가 정책 알려줘"}' > /dev/null

time curl -sX POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q": "휴가 규정이 어떻게 돼?"}' > /dev/null
# 두 번째가 < 200ms 면 시맨틱 캐시 hit
```

---

## 3단계 · Azure Portal UI 에서 확인

1. **Redis Enterprise** (`redis-ai200ws-dev`) → **Console** (브라우저 redis-cli) — 다음 명령으로 직접 확인:
   ```
   FT._LIST
   FT.INFO rag_cache_idx
   KEYS rag:*
   ```
   `FT._LIST` 에 `rag_cache_idx` 가 노출. `FT.INFO` 에 `num_docs` 가 호출 횟수만큼 증가
2. **Redis Enterprise** → **Metrics** → `Ops/sec`, `Cache hits` 그래프 — 호출 직후 스파이크
3. **Application Insights** → **Logs** → 다음 KQL 붙여넣기:
   ```kusto
   customMetrics
   | where name == "cache_hit"
   | summarize hit=countif(value==1), miss=countif(value==0) by bin(timestamp, 1m)
   | render columnchart
   ```
   분포가 (1차 miss → 2차 hit) 패턴

---

## 주의 (Heads-up)

- ⚠️ **RediSearch DB 는 `evictionPolicy=NoEviction` 필수** — VolatileLRU 등으로 두면 인덱스 동작 안 함
- ⚠️ **redis-py 5.x `ConnectionPool` 은 `ssl=` 미지원** — `connection_class=redis.SSLConnection` 사용
- ⚠️ **AAD username 은 principal objectId** (clientId 아님!) — 둘 다 UUID 라 헷갈림. UAMI 라면 `principalId` 사용
- ⚠️ **RediSearch TAG 하이픈은 escape 필수** (`ws\-test`) — 미escape 면 silent miss, 캐시 항상 0%
- ⚠️ **`az redisenterprise show` 응답은 flat 구조** — 다른 ARM 리소스처럼 `properties` 중첩 X. Bicep output 작성 시 주의
- 💰 **비용**: Memory_M10 ≈ ₩11,680/일. **워크샵 끝나면 즉시 정리** ([cleanup.md](../cleanup.md))

---

## 마무리

- **save-point**: `git tag session-03-complete`
- **다음 세션 미리보기**: session-04 — 지금까지는 동기 호출만 했다면, 이제 사용자가 PDF 를 업로드하면 비동기로 청크·임베드·인덱스 — Service Bus + Event Grid + Functions

---

## 참고 자료

- MS Learn: [Enhance AI solutions with Azure Managed Redis](https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/)
- RediSearch: [Vector similarity search](https://redis.io/docs/latest/develop/interact/search-and-query/advanced-concepts/vectors/)
- 본 레포: `infra/sessions/03-redis-cache/main.bicep`, `apps/api/src/cache/`
