# 아키텍처

워크샵을 모두 완주한 시점의 최종 아키텍처입니다. 각 세션이 어떤 자원을 추가하는지는 [README.md 의 아젠다](../README.md#하루-일정) 참고.

---

## 데이터 흐름

```
                    ┌──────────────────────────────────────────────────────┐
                    │                  Azure AD / Entra ID                  │
                    │       (DefaultAzureCredential → UAMI 토큰)            │
                    └──────────────────────────────────────────────────────┘
                                          ▲
                                          │ (모든 호출이 키 없이 토큰으로 인증)
                                          │
[브라우저]  ──HTTPS──▶  [ACA: ca-web (Next.js)]  ──HTTP──▶  [ACA: ca-api (FastAPI)]
                                                                    │
                            ┌───────────────────────────────────────┼────────────────────────────────┐
                            ▼                                       ▼                                ▼
                    [Cosmos DB (vector)]                   [PostgreSQL pgvector]             [Managed Redis (semantic cache)]
                    chunks container                       chunks table                       RediSearch HNSW
                    DiskANN/quantizedFlat                  halfvec(3072) HNSW                 cosine ≥ 0.92 캐시 히트
                            ▲                                       ▲                                ▲
                            │                                       │                                │
                            │ ◀───── change feed ─────┐             │                                │
                            │                         ▼             │                                │
                    [Cosmos lease container]    [Function: on_cosmos_change]                          │
                                                                                                     │
                                                                                                     │
[사용자]  ──Blob 업로드──▶  [Storage]  ──Event Grid──▶  [Service Bus: ingest-queue]  ──▶  [Function: on_ingest_message]
                                                              │                                      │
                                                              │ (max delivery 5)                     │
                                                              ▼                                      │
                                                          [SB: DLQ]                                  │
                                                                                                     ▼
                                                                                          (청크 분할 → AOAI embed → Cosmos + PG upsert)

                    [Azure OpenAI]: gpt-4o-mini (chat) + text-embedding-3-large (embed)
                            ▲
                            │ (UAMI 토큰)
                            │
                    ca-api, Function 양쪽에서 호출

                                                  [App Configuration] ←── ca-api 가 polling (sentinel 30s)
                                                          │
                                                          ├── key/value (endpoints, hosts)
                                                          ├── feature flags (enable_semantic_cache, …)
                                                          └── Key Vault references → [Key Vault]

[모든 자원] ──OpenTelemetry──▶ [Application Insights] ──▶ [Log Analytics Workspace]
                                                                  │
                                                                  ├── Workbook (P95, hit rate, token cost)
                                                                  ├── Metric Alert (오류율 > 5%) → [Action Group] → 이메일
                                                                  └── KQL 직접 쿼리

(선택) [AKS]: embedding 재처리 워커 — Cosmos 의 null embedding chunk 를 K8s Job 으로 재처리
       └── Container Insights (DCR + DCRA) ──▶ Log Analytics Workspace
```

---

## 자원 매핑

각 세션이 추가하는 자원과 그 역할:

| 세션 | 추가 자원 | 역할 |
|---|---|---|
| session-00 | RG · AOAI · LAW · App Insights · KV · UAMI | 워크샵 전체의 기반 |
| session-01 | ACR · ACA Env · ca-api · ca-web · Cosmos | RAG MVP — 동기 호출 |
| session-02 | PostgreSQL Flex (pgvector) | 같은 RAG 를 PG 백엔드로 비교 |
| session-03 | Managed Redis (RediSearch) | 시맨틱 캐시 — 의미 유사 질문 흡수 |
| session-04 | Service Bus · Event Grid · Functions · Storage | 비동기 인제스션 파이프라인 |
| session-05 | App Configuration · Feature flag | 코드 재배포 없이 동작 토글 |
| session-06 | Workbook · Action Group · Metric Alert | 관측성 — 비즈니스 의미 span + 알람 |
| session-07 | AKS · Container Insights | ACA 대안 — embedding 재처리 워커 |

---

## 명명 규칙

`<리소스약어>-ai200ws-<env>` (또는 하이픈 금지 자원은 `<약어>ai200ws<env><suffix>`)

- `rg` 리소스 그룹 (`rg-ai200ws-dev`)
- `aoai` Azure OpenAI (`aoai-ai200ws-dev`)
- `cosmos` Cosmos DB (`cosmos-ai200ws-dev`)
- `pg` PostgreSQL (`pg-ai200ws-dev`)
- `redis` Managed Redis (`redis-ai200ws-dev`)
- `sb` Service Bus (`sb-ai200ws-dev`)
- `egt` Event Grid 토픽
- `func` Function App
- `kv` Key Vault
- `ac` App Configuration
- `ai` Application Insights
- `law` Log Analytics Workspace
- `id` UAMI
- `acr` Container Registry (하이픈 금지 → `acrai200wsdev<uniq>`)
- `st` Storage (`stai200wsdev<uniq>`)
- `cae` Container Apps Environment
- `ca` Container App (`ca-api-...`, `ca-web-...`)
- `aks` AKS

---

## 인증 전체 흐름

워크샵의 핵심 보안 원칙: **시크릿은 한 줄도 코드/`.env` 에 없다.**

```
[ca-api / ca-web / Function / AKS Pod]
    │
    │ DefaultAzureCredential
    │  ├─ (클라우드) UAMI 토큰
    │  └─ (로컬 개발) `az login` 자격
    ▼
[Entra ID] → 단명 OAuth2 토큰 (audience: 호출 대상 별)
    │
    ▼
[AOAI / Cosmos / KV / AC / SB / EG / Storage / Redis / ACR]
    Azure RBAC 으로 권한 검사
```

각 자원이 UAMI 에 부여해야 하는 역할:

| 자원 | 역할 |
|---|---|
| AOAI | Cognitive Services OpenAI User |
| Cosmos (data plane) | Cosmos DB Built-in Data Contributor |
| Key Vault | Key Vault Secrets User |
| App Configuration | App Configuration Data Reader |
| Service Bus | Azure Service Bus Data Receiver / Sender |
| Event Grid | EventGrid Data Sender |
| Storage Blob | Storage Blob Data Reader (또는 Contributor) |
| ACR | AcrPull |
| Managed Redis | (Access Policy 별도) |
| AKS (Workload Identity) | (Federated Credential 별도) |
