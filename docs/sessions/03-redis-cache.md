# session-03 — Managed Redis 시맨틱 캐시

> **관련 Microsoft Learn 학습 경로**
>
> - [Enhance AI solutions with Azure Managed Redis](https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [session-00](./00-setup.md), [session-01](./01-rag-mvp.md) 완료 — Azure OpenAI · Azure Container Apps · User Assigned Managed Identity · Application Insights 가 본인 구독에 존재
> - (선택) [session-02](./02-pgvector.md) 완료 — 두 벡터 백엔드의 latency 베이스라인이 있으면 캐시 효과 비교가 풍부함
> - 시작본 코드를 작업 폴더로 받기 — [시작본 코드 받기](#시작본-코드-받기) 참고

---

## 0. 이 세션에서 경험하는 내용

- **한 문장 골** — "회사 휴가 정책 알려줘" 와 "휴가 규정이 어떻게 돼?" 처럼 의미상 같은 두 질문을 Managed Redis 가 같다고 판단해, 두 번째 호출이 빠르게 응답되는 시맨틱 캐시를 도입
- **새로 프로비저닝되는 자원**
  - Azure Managed Redis 클러스터 (Balanced_B0 — 최소 등급)
  - 데이터베이스 default — RediSearch 모듈 포함, `evictionPolicy=NoEviction`, Entra ID 전용 인증
  - access policy assignment 2개 — User Assigned Managed Identity + 배포 사용자
- **이 세션의 학습 포인트**
  - 완성된 Redis Bicep 모듈 3개를 `main.bicep` 에서 조립
  - `redis-entraid` credential provider 로 Entra ID 인증 Redis 클라이언트 구성
  - RediSearch FLAT 벡터 인덱스 + KNN 으로 시맨틱 캐시 lookup / store 구현
- **사용해볼 SDK / CLI**
  - `redis-py` 5.x async + `redis-entraid` credential provider
  - RediSearch `FT.CREATE` (FLAT 벡터 인덱스) + `FT.SEARCH` KNN
  - OpenTelemetry 커스텀 span `cache.lookup` 에 `cache_hit` 속성 부여
- **Portal 에서 확인할 지표 / 데이터**
  - Managed Redis → Console — `FT.INFO`, `KEYS rag:*` 로 캐시 키 직접 조회
  - Managed Redis → Metrics — Ops/sec · Cache hits
  - Application Insights → Logs (KQL) — `cache_hit` 분포

> [!TIP]
> 이 세션은 `Bicep 조립 → 배포 → 코드 채우기 → 이미지 빌드·배포 → 캐시 효과 측정 → Portal 확인` 흐름으로 진행합니다.

---

## 시작본 코드 받기

[session-02](./02-pgvector.md) 의 결과물이 들어 있는 작업 폴더 `workshop/` 위에 본 세션의 시작본 코드가 덮입니다.

```bash
# Linux · macOS · WSL
cp -a save-points/session-03/start/. workshop/
```

```powershell
# Windows PowerShell
Copy-Item -Path save-points/session-03/start/* -Destination workshop -Recurse -Force
```

이후 본 세션의 모든 명령은 `workshop/` 안에서 실행한다고 가정합니다.

학습자가 채우는 파일은 세 개입니다 — `infra/sessions/03-redis-cache/main.bicep` (모듈 조립), `apps/api/src/cache/redis_client.py` (Redis 클라이언트), `apps/api/src/cache/semantic.py` (시맨틱 캐시). 나머지 (모듈 3개 · 캐시 배선) 는 완성되어 제공됩니다.

---

## 1단계 · 프로비저닝

`workshop/infra/sessions/03-redis-cache/main.bicep` 을 열고, 아래 순서대로 각 주석을 찾아 코드를 채웁니다.

### 1.1 호출할 모듈 한눈에 보기

`infra/modules/session-03/` 에 완성되어 있는 모듈입니다.

- `redis-enterprise.bicep` — Azure Managed Redis 클러스터 (Balanced_B0)
- `redis-enterprise-database.bicep` — RediSearch 모듈 + `evictionPolicy=NoEviction` + Entra 전용 인증
- `redis-access-policy-assignment.bicep` — Entra principal 을 기본 access policy 에 부여

### 1.2 클러스터 + 데이터베이스

`// -------- 1) Azure Managed Redis 클러스터 모듈 호출하기` 와 `// -------- 2) 데이터베이스 default 모듈 호출하기` 주석 아래에 각각 추가합니다.

```bicep
module redis '../../modules/session-03/redis-enterprise.bicep' = {
  name: 'redis'
  params: {
    name: redisName
    location: location
    skuName: 'Balanced_B0'
    tags: commonTags
  }
}

module redisDatabase '../../modules/session-03/redis-enterprise-database.bicep' = {
  name: 'redisDatabase'
  params: {
    clusterName: redis.outputs.name
  }
}
```

### 1.3 access policy assignment (User Assigned Managed Identity + 사용자)

`// -------- 3) ...` 과 `// -------- 4) ...` 주석 아래에 각각 추가합니다. access policy assignment 를 동시에 만들면 클러스터가 Updating 상태라 충돌할 수 있으므로 `dependsOn` 으로 직렬화합니다.

```bicep
module accessUami '../../modules/session-03/redis-access-policy-assignment.bicep' = {
  name: 'accessUami'
  params: {
    clusterName: redis.outputs.name
    principalObjectId: uami.properties.principalId
  }
  dependsOn: [
    redisDatabase
  ]
}

module accessUser '../../modules/session-03/redis-access-policy-assignment.bicep' = if (!empty(userObjectId)) {
  name: 'accessUser'
  params: {
    clusterName: redis.outputs.name
    principalObjectId: userObjectId
  }
  dependsOn: [
    accessUami
  ]
}
```

### 1.4 출력값

`// -------- 출력` 주석 아래에 추가합니다.

```bicep
output redisName string = redis.outputs.name
output redisHostName string = redis.outputs.hostName
output redisPort int = redisDatabase.outputs.port
```

### 1.5 조립 검증 + 배포

```bash
az bicep build --file infra/sessions/03-redis-cache/main.bicep --outfile /tmp/main.json && echo "BUILD OK"
```

```bash
OID=$(az ad signed-in-user show --query id -o tsv)

az deployment group what-if `
  --resource-group rg-ai200ws-dev `
  --template-file infra/sessions/03-redis-cache/main.bicep `
  --parameters infra/sessions/03-redis-cache/main.bicepparam `
  --parameters userObjectId=$OID
```

what-if 결과가 의도대로면 `what-if` 를 `create` 로 바꿔 배포합니다.

> [!NOTE]
> Azure Managed Redis 클러스터 생성에 약 **8~12분** 소요됩니다. 본 워크샵에서 가장 오래 걸리는 배포 중 하나입니다. 진행되는 동안 [2단계 · 복붙으로 경험해보기](#2단계--복붙으로-경험해보기) 의 캐시 전략과 코드를 정독합니다.

> [!CAUTION]
> **비용 안내** — Managed Redis 는 본 워크샵에서 가장 비싼 idle 자원입니다 (최소 등급 Balanced_B0 라도 시간당 누적). 세션을 마친 뒤에는 즉시 [자원 정리](../cleanup.md) 를 수행하는 것을 권장합니다.

### 1.6 배포 완료 확인

클러스터 이름은 글로벌 unique 보장을 위해 접미사가 붙으므로 (예: `redis-ai200ws-dev-xxxxx`), 이름과 호스트를 조회해 환경변수에 담아둡니다.

```bash
REDIS_NAME=$(az redisenterprise list -g rg-ai200ws-dev --query "[0].name" -o tsv)
REDIS_HOST=$(az redisenterprise list -g rg-ai200ws-dev --query "[0].hostName" -o tsv)

az redisenterprise show -n $REDIS_NAME -g rg-ai200ws-dev \
  --query "{state:resourceState, sku:sku.name, host:hostName}" -o jsonc
```

기대 — `state: Running`, `sku: Balanced_B0`.

---

## 2단계 · 복붙으로 경험해보기

### 2.1 캐시 전략 트레이드오프

RAG 응답을 캐싱할 때 세 가지 전략이 있습니다.

| 전략 | 캐시 키 | 히트 조건 | 장점 | 단점 |
|---|---|---|---|---|
| **정확 매칭** | `hash(질문 문자열)` | 두 질문의 문자열이 완전히 동일 | 구현 단순 · 검색 비용 거의 0 | "휴가 정책 알려줘" 와 "휴가 규정이 어떻게 돼?" 가 다른 키로 분리되어 hit 율이 매우 낮음 |
| **시맨틱 유사도** | 질문 임베딩 벡터 | 새 질문 임베딩이 기존 캐시 키와 cosine 유사도 ≥ 임계값 | paraphrase 흡수 · hit 율 높음 | 임계값 튜닝 필요 · 잘못된 hit 위험 |
| **RAG 인지 (튜플)** | (질문 임베딩, 사용 문서 셋) | 의미 + 문서 셋 모두 일치 | 문서 변경 시 자동 무효화 | 캐시 키 공간이 커지고 hit 율이 다소 떨어짐 |

본 워크샵은 **시맨틱 유사도 + 임계값 0.92** (한국어 paraphrase 에 보수적) + TTL 24h 를 채택합니다.

> [!TIP]
> **시험 단골 패턴** — "RAG 응답 캐싱은 문자열 매칭으로 부족하다 — 임베딩 기반 시맨틱 캐시" 가 정답입니다. 임계값을 너무 낮추면 잘못된 hit, 너무 높이면 캐시가 거의 비어 있으므로 0.90 ~ 0.95 범위에서 튜닝합니다.

### 2.2 Redis 클라이언트 구현

`apps/api/src/cache/redis_client.py` 의 `build_redis_client` 본체가 비어 있습니다. 주석 아래에 채웁니다. 저수준으로 토큰을 비밀번호에 넣는 대신 `redis-entraid` 의 credential provider 를 써서 토큰 발급·갱신·TLS 를 캡슐화합니다.

```python
    credential_provider = create_from_default_azure_credential(
        (_REDIS_AAD_SCOPE,),
    )
    return Redis(
        host=settings.redis_host,
        port=settings.redis_port,
        ssl=True,
        credential_provider=credential_provider,
        decode_responses=False,
    )
```

### 2.3 시맨틱 캐시 구현

`apps/api/src/cache/semantic.py` 의 `SemanticCache` 메서드를 채웁니다.

`ensure_index` — RediSearch **FLAT** 벡터 인덱스를 (없으면) 생성합니다. 캐시 엔트리 수가 수백~수천이라 FLAT (정확 최근접) 이 적합합니다.

```python
        try:
            await self._r.ft(_INDEX_NAME).info()
            return  # 이미 존재
        except ResponseError:
            pass

        schema = (
            VectorField(
                "embedding",
                "FLAT",
                {"TYPE": "FLOAT32", "DIM": self._dim, "DISTANCE_METRIC": "COSINE"},
            ),
            TextField("answer"),
            TextField("sources"),
        )
        definition = IndexDefinition(prefix=[_KEY_PREFIX], index_type=IndexType.HASH)
        await self._r.ft(_INDEX_NAME).create_index(schema, definition=definition)
```

`lookup` — 질문 임베딩으로 KNN(1) 검색. RediSearch 의 COSINE 은 distance(0~2) 를 반환하므로 `similarity = 1 - distance` 로 환산해 임계값과 비교합니다.

```python
        with _tracer.start_as_current_span("cache.lookup") as span:
            vec = _to_float32_bytes(query_embedding)
            query = (
                Query("*=>[KNN 1 @embedding $vec AS dist]")
                .sort_by("dist")
                .return_fields("answer", "sources", "dist")
                .dialect(2)
            )
            result = await self._r.ft(_INDEX_NAME).search(query, query_params={"vec": vec})

            if result.docs:
                similarity = 1.0 - float(_decode(result.docs[0].dist))
                if similarity >= self._threshold:
                    span.set_attribute("cache_hit", True)
                    span.set_attribute("cache_similarity", similarity)
                    return _to_response(result.docs[0])

            span.set_attribute("cache_hit", False)
            return None
```

`store` 와 `close` 를 마저 채웁니다. 저장은 **Hash** 로 합니다 — `FT.SEARCH` 는 인덱스 prefix 와 일치하는 hash 키만 인덱싱합니다.

```python
    async def store(
        self, query_embedding: list[float], question: str, response: ChatResponse
    ) -> None:
        key = f"{_KEY_PREFIX}{uuid.uuid4().hex}"
        mapping = {
            "embedding": _to_float32_bytes(query_embedding),
            "question": question,
            "answer": response.answer,
            "sources": json.dumps(
                [s.model_dump() for s in response.sources], ensure_ascii=False
            ),
        }
        await self._r.hset(key, mapping=mapping)
        await self._r.expire(key, self._ttl)

    async def close(self) -> None:
        await self._r.aclose()
```

> [!NOTE]
> 캐시 계층은 `apps/api/src/rag/chain.py` 에 이미 배선되어 있습니다 — 질문 임베딩 직후 `cache.lookup` 으로 hit 면 즉시 반환, miss 면 retrieve·generate 후 `cache.store`. `STORE_BACKEND` 분기처럼 `CACHE_ENABLED=false` 면 캐시 계층이 없는 것처럼 동작합니다.

### 2.4 이미지 빌드 · 배포 · 호출

```bash
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)
az acr login --name $ACR_NAME

docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/api:s03 apps/api
docker push $ACR_NAME.azurecr.io/api:s03

# 이미지 교체 + 캐시 환경변수 주입 (REDIS_HOST 는 1.6 에서 조회한 값)
az containerapp update \
  --name ca-api-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --image $ACR_NAME.azurecr.io/api:s03 \
  --set-env-vars CACHE_ENABLED=true REDIS_HOST=$REDIS_HOST

API_FQDN=$(az containerapp show -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)
```

의미는 같지만 표현이 다른 두 질문으로 캐시 효과를 측정합니다.

```bash
# 첫 호출 — 캐시 miss 예상
time curl -sX POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q": "회사 휴가 정책 알려줘"}' > /dev/null

# 두 번째 — 의미상 같은 paraphrase. 시맨틱 캐시 hit 예상
time curl -sX POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q": "휴가 규정이 어떻게 돼?"}' > /dev/null
```

기대 — 첫 호출은 약 800~1500ms, 두 번째 호출은 그보다 크게 짧습니다.

---

## 3단계 · Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **Managed Redis** → **Console** (브라우저 안의 redis-cli) — 다음을 한 줄씩 실행

   ```
   FT._LIST
   FT.INFO rag_cache_idx
   KEYS rag:*
   ```

   기대 — `FT._LIST` 에 `rag_cache_idx` 노출, `FT.INFO` 의 `num_docs` 가 호출 횟수만큼 증가, `KEYS rag:*` 에 캐시 키들이 노출됩니다.

   <!-- 📸 capture: images/session-03/3a-redis-console-ft-info.png -->
   <!--
   ![Azure Managed Redis Console 에서 FT._LIST 와 FT.INFO, KEYS 명령 실행 결과를 보여 주는 Azure Portal 스크린샷](../../images/session-03/3a-redis-console-ft-info.png)

   Console 에서 실행한 `FT._LIST` 결과에 `rag_cache_idx` 가 나타나고, `KEYS rag:*` 에 캐시 키가 노출되는지 확인합니다. `FT.INFO` 의 `num_docs` 가 호출 횟수와 일치하는지 함께 확인합니다.
   -->

2. **Managed Redis** → **Metrics** → `Operations Per Second` · `Cache Hits` 추가

   <!-- 📸 capture: images/session-03/3b-redis-metrics-ops-cache-hits.png -->
   <!--
   ![Azure Managed Redis 의 Operations Per Second 와 Cache Hits 메트릭 차트를 보여 주는 Azure Portal 스크린샷](../../images/session-03/3b-redis-metrics-ops-cache-hits.png)

   API 호출 시점에 **Operations Per Second** 가 튀고, 캐시 hit 가 발생한 시점에 **Cache Hits** 가 증가하는지 확인합니다.
   -->

3. **Application Insights** → **Logs** 에서 다음 KQL 실행

   ```kusto
   dependencies
   | where name == "cache.lookup"
   | extend hit = tobool(customDimensions["cache_hit"])
   | summarize hits=countif(hit==true), misses=countif(hit==false) by bin(timestamp, 1m)
   | render columnchart
   ```

   기대 — 첫 호출 시점에 miss 1, 두 번째 호출 시점에 hit 1 로 시각화됩니다.

   <!-- 📸 capture: images/session-03/3c-app-insights-cache-hit-columnchart.png -->
   <!--
   ![cache_hit 분포를 막대 차트로 시각화한 Application Insights Logs 결과를 보여 주는 Azure Portal 스크린샷](../../images/session-03/3c-app-insights-cache-hit-columnchart.png)

   첫 호출 시점에는 misses 1, 두 번째 호출 시점에는 hits 1 로 집계되는지 차트에서 확인합니다.
   -->

4. **Application Insights** → **Transaction search** → 최근 `POST /api/chat` 두 건 비교
   - 첫 건은 `cache.lookup` (miss) 뒤에 retrieve · generate span 이 이어짐
   - 두 번째 건은 `cache.lookup` 만 보이고 그 뒤 span 이 없음 (캐시 hit 라 RAG 우회)

   <!-- 📸 capture: images/session-03/3d-transaction-search-cache-hit-trace.png -->
   <!--
   ![캐시 miss 와 hit 두 건의 POST /api/chat 트랜잭션 상세를 비교해 보여 주는 Application Insights Transaction search 의 Azure Portal 스크린샷](../../images/session-03/3d-transaction-search-cache-hit-trace.png)

   첫 번째 건은 `cache.lookup` 뒤에 retrieve · generate span 이 이어지고, 두 번째 건은 `cache.lookup` 만 남고 후속 span 이 없는지 확인합니다.
   -->

---

## Microsoft Learn 경로 커버리지 — 사용 / 생략

[Enhance AI solutions with Azure Managed Redis](https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/) 학습 경로 3개 모듈을 본 세션에서 어떻게 다루는지 정리합니다.

| 모듈 | 단원 핵심 | 본 세션 |
|---|---|---|
| **1. 데이터 작업 구현** | Managed Redis 살펴보기 · 클라이언트 라이브러리 + TLS + Entra ID · SET/GET·TTL·캐시-어사이드·무효화 | **사용** — Entra ID 인증(`redis-entraid`), TTL 24h, 캐시 store/lookup (2.2 · 2.3) |
| **2. 이벤트 메시징 구현** | pub/sub · Redis Streams 작업 큐 · 브로드캐스트 vs 조정 배포 | **생략** — session-04 의 Service Bus · Event Grid · Functions 와 개념 중복. 본 워크샵은 Azure 네이티브 메시징을 session-04 에서 다룸 |
| **3. 벡터 스토리지 구현** | 인덱스/쿼리 (FT.CREATE · KNN) · 인덱스 전략 (FLAT vs HNSW · 메트릭 · FLOAT32) · 데이터 구조 (해시 vs JSON) | **사용** — FLAT + COSINE + FLOAT32 + Hash 로 시맨틱 캐시 (2.3). HNSW·JSON 은 캐시 규모상 미채택 |

> [!NOTE]
> **인덱스 선택 근거** — 학습 경로 기준 10,000 벡터 미만 · 완벽한 정확도면 FLAT 권장. 시맨틱 캐시는 엔트리가 수백~수천이라 FLAT 이 적합하며, 근사 오차로 인한 잘못된 hit 위험도 낮습니다. HNSW 는 캐시가 수만 건 이상으로 커질 때 고려합니다.

---

## 주의

> [!CAUTION]
> **RediSearch 데이터베이스는 `evictionPolicy=NoEviction` 필수** — 다른 eviction policy 는 RediSearch 인덱스와 충돌해 `FT.SEARCH` 결과가 stale 해집니다. Bicep `redis-enterprise-database.bicep` 에서 `NoEviction` 으로 고정되어 있습니다.

> [!CAUTION]
> **cosine 유사도 vs distance 환산** — RediSearch 의 COSINE 은 distance(0=동일 ~ 2=반대) 를 반환합니다. "유사도 ≥ 0.92" 컷오프는 코드에서 `1 - distance ≥ 0.92` 로 환산해야 합니다. 이 환산을 빼먹으면 전부-hit 또는 전부-miss 가 되는데 원인 추적이 어렵습니다.

> [!CAUTION]
> **FT.SEARCH 는 hash 키만 인덱싱** — 인덱스 prefix 와 일치하는 Redis Hash 키만 인덱싱됩니다. 임베딩·답변·출처를 한 hash 키에 함께 저장합니다 (`hset`). 일반 `SET` 으로 저장한 값은 인덱싱되지 않아 항상 캐시 miss 가 됩니다.

> [!CAUTION]
> **Entra 전용 인증 + access policy assignment** — 클러스터는 access key 인증을 끈 상태입니다 (`accessKeysAuthentication=Disabled`). Entra principal (User Assigned Managed Identity · 사용자) 이 access policy 에 부여되어 있어야 접속됩니다. 연결이 인증 오류로 실패하면 `redis-access-policy-assignment` 가 배포됐는지 확인합니다.

> [!NOTE]
> **`az redisenterprise show` 응답 구조** — 일반 ARM 자원의 `properties.xxx` 가 아니라 평탄화된 구조 (`resourceState`, `hostName` 등이 최상위) 입니다.

> [!TIP]
> 진행 중 막혔다면 완성본 코드를 그대로 덮어쓰고 비교할 수 있습니다.
>
> ```bash
> cp -a save-points/session-03/complete/. workshop/
> ```

---

## 마무리

- **save-point** — 본 세션의 모든 변경은 `save-points/session-03/complete/` 와 일치합니다. 다음 세션으로 넘어가려면 `workshop/` 을 그대로 두고 `cp -a save-points/session-04/start/. workshop/` 를 실행합니다
- **자원 정리** — Managed Redis 는 idle 비용이 누적됩니다. 본 세션 학습이 끝났다면 [자원 정리](../cleanup.md) 의 Redis 정리 절차로 즉시 정리하는 것을 권장합니다. 후속 세션에서 캐시를 다시 쓰려면 본 세션 Bicep 을 재배포합니다
- **다음 세션 미리보기** — [session-04](./04-async-ingestion.md) 에서는 동기 호출이 아닌 비동기 인제스션 (ingestion) 파이프라인을 구축합니다. Blob 업로드 한 번이 Event Grid → Service Bus → Azure Functions 경로로 자동 청크 분할 · 임베드 · 적재됩니다

---

## 참고 자료

- Microsoft Learn — [Enhance AI solutions with Azure Managed Redis](https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/)
- RediSearch — [Vector similarity search](https://redis.io/docs/latest/develop/interact/search-and-query/advanced-concepts/vectors/)
- 본 저장소 — `infra/sessions/03-redis-cache/main.bicep`, `apps/api/src/cache/`

---

👈 [session-02 — PostgreSQL pgvector 비교](./02-pgvector.md) | [session-04 — 비동기 인제스션 (Service Bus + Event Grid + Functions)](./04-async-ingestion.md) 👉