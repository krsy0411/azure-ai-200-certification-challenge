# 목표 아키텍처

엔터프라이즈 RAG 지식 비서의 최종(Phase 9 완료) 모습.

## 컴포넌트 다이어그램

```
                  ┌────────────┐
  end user ─────► │  Next.js    │  (ACA: web)
                  │  App Router │
                  └─────┬──────┘
                        │ HTTPS
                        ▼
                  ┌────────────┐       ┌────────────────────┐
                  │  FastAPI    │ ─────►  Azure OpenAI       │
                  │  (ACA: api) │       │  gpt-4o-mini        │
                  │             │       │  text-embedding-3-L │
                  └──┬──┬──┬───┘       └────────────────────┘
                     │  │  │
                     │  │  └───────────────► Managed Redis
                     │  │                   (시맨틱 캐시 · Pub/Sub)
                     │  │
                     │  └──► PostgreSQL Flexible Server
                     │         (pgvector · 관계형)
                     │
                     └──► Cosmos DB for NoSQL
                            (document · chunk · vector)

  Blob Storage ─► Event Grid ─► Azure Functions ─► Service Bus ─►  AKS Worker
  (업로드)        (CloudEvent)    (웹훅/이벤트 처리)   (추론 큐)      (임베딩 배치)

                  ┌──────────────────────────────────────────┐
  Key Vault ◄───► │  모든 서비스: Managed Identity 로 인증     │
  App Config ◄───► │  (Entra ID · RBAC)                       │
                  └──────────────────────────────────────────┘

  모든 서비스 ────► OpenTelemetry ────► Azure Monitor / App Insights
```

## 서비스별 책임

| 서비스 | 책임 | Phase |
|---|---|---|
| **Next.js** | 챗 UI, 문서 업로드, 관리자 뷰 | 1~ |
| **FastAPI** | REST API, RAG 오케스트레이션, LLM 호출 | 1~ |
| **AKS Worker** | 임베딩 배치 재처리 (대용량) | 3 |
| **Azure Functions** | Event Grid 웹훅, 추론 큐 디스패처 | 7 |
| **Cosmos DB** | 문서/청크/벡터의 기본 저장소 | 4 |
| **PostgreSQL** | 사용자·작업 공간·감사 로그 + pgvector 비교 실험 | 5 |
| **Managed Redis** | 시맨틱 캐시, 실시간 알림 Pub/Sub, 작업 Streams | 6 |
| **Service Bus** | 추론/임베딩 요청 큐, DLQ | 7 |
| **Event Grid** | Blob 업로드 이벤트 라우팅 | 7 |
| **Key Vault** | 모든 시크릿의 원천(Single source of truth) | 8 |
| **App Configuration** | 기능 플래그, 환경별 구성 | 8 |
| **Application Insights** | 분산 추적, 로그, 메트릭, 경고 | 9 |

## 인증 원칙

- 사용자는 초기엔 고정 토큰으로 로그인(Phase 1~7). Phase 8 이후 Entra ID 앱 등록 연동 고려.
- **서비스-투-서비스는 Managed Identity** 만 사용. 연결 문자열을 코드/환경변수로 넣지 않는다 (Phase 8 이후).

## 데이터 흐름: "문서를 업로드하고 질의하기"

1. 사용자 업로드 → Next.js → FastAPI `/documents` → Blob Storage
2. Blob 이벤트 → Event Grid → Azure Function → Service Bus `inference-queue` 에 메시지 enqueue
3. AKS Worker 컨슈머: 메시지 수신 → 청크 분할 → Azure OpenAI embeddings → **Cosmos DB** 에 벡터 저장
4. 동시에 PostgreSQL 감사 로그 insert
5. 완료 이벤트 → Redis Pub/Sub → Next.js 실시간 업데이트
6. 사용자가 질문 → FastAPI: Redis 시맨틱 캐시 히트 여부 확인 → miss 면 Cosmos `VectorDistance` 검색 → Azure OpenAI 응답 생성 → 캐시 적재 → 사용자에게 스트리밍
