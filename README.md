# Azure AI-200 Workshop in a Day — 사내 문서 RAG 지식 비서

> 하루 안에 **Azure AI-200 자격증의 핵심 기술 스택 전부**를 직접 만지며 *동작하는 사내 문서 RAG 지식 비서* 를 본인의 Azure 구독 위에 올립니다.

이 워크샵을 마치면 다음을 *코드 한 줄까지 본인 손으로* 경험합니다:

- Azure OpenAI (chat + embedding) 로 RAG 파이프라인 구축
- Cosmos DB 와 PostgreSQL pgvector 의 벡터 검색 비교
- Managed Redis 시맨틱 캐시
- Service Bus · Event Grid · Azure Functions 로 비동기 인제스션
- Key Vault + App Configuration + Managed Identity 로 시크릿·런타임 설정 분리
- Application Insights · OpenTelemetry · KQL 로 관측성
- Azure Container Apps (메인) 와 AKS (대안) 양쪽 배포

---

## 누구를 위한 워크샵인가

- **Azure AI-200 자격증 응시자** — 시험 범위인 8개 학습 경로를 한 앱에서 모두 경험
- **Azure 기반 RAG/생성형 AI 앱 입문자** — "코드 한 번 호출 → 클라우드 자원에 흔적이 남는다" 를 Portal UI 에서 직접 확인
- **사내 RAG 도입 검토자** — Cosmos vs PG, 캐시 전략, 비동기 인제스션 등 실전 트레이드오프를 체감

전제 지식: Python 기본 / Docker 기본 / Azure 가입 경험.

---

## AI-200 학습 경로 매핑

| AI-200 공식 학습 경로 | 본 워크샵 세션 |
|---|---|
| [Implement container app hosting on Azure](https://learn.microsoft.com/ko-kr/training/paths/implement-container-app-hosting-azure/) | session-01 |
| [Deploy and manage apps on Azure Container Apps](https://learn.microsoft.com/ko-kr/training/paths/deploy-manage-apps-azure-container-apps/) | session-01 |
| [Deploy and monitor apps on AKS](https://learn.microsoft.com/ko-kr/training/paths/deploy-monitor-apps-azure-kubernetes-service/) | session-07 |
| [Develop AI solutions with Cosmos DB](https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-cosmos-db/) | session-01 |
| [Develop AI solutions with PostgreSQL](https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-database-postgresql/) | session-02 |
| [Enhance AI solutions with Managed Redis](https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/) | session-03 |
| [Integrate backend services for AI](https://learn.microsoft.com/ko-kr/training/paths/integrate-backend-services-ai-solutions/) | session-04 |
| [Manage app secrets and configuration](https://learn.microsoft.com/ko-kr/training/paths/manage-app-secrets-configuration/) | session-00·session-01·session-05 |
| [Observe and troubleshoot apps](https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/) | session-00·session-01·session-06 |

---

## 사전 준비

워크샵 시작 전 [PREREQUISITES.md](./PREREQUISITES.md) 의 체크리스트를 순서대로 모두 완료합니다. 특히 Azure OpenAI 액세스 신청은 승인까지 시간이 걸릴 수 있으므로 가장 먼저 신청해두는 것을 권장합니다.

---

## 하루 일정

| # | 제목 | 핵심 자원 | 문서 |
|---|---|---|---|
| **session-00** | 사전 설정 & 구독 준비 | RG · AOAI · Log Analytics · App Insights · Key Vault · UAMI | [00-setup.md](./docs/sessions/00-setup.md) |
| **session-01** | RAG MVP on ACA + KV + OTel | ACR · ACA · Cosmos (vector) | [01-rag-mvp.md](./docs/sessions/01-rag-mvp.md) |
| **session-02** | PostgreSQL pgvector 비교 | PG Flex · pgvector · `halfvec(3072)` | [02-pgvector.md](./docs/sessions/02-pgvector.md) |
| **session-03** | Managed Redis 시맨틱 캐시 | Redis Enterprise · RediSearch | [03-redis-cache.md](./docs/sessions/03-redis-cache.md) |
| **session-04** | 비동기 인제스션 (SB+EG+Functions) | Service Bus · Event Grid · Functions (Flex) · Storage | [04-async-ingestion.md](./docs/sessions/04-async-ingestion.md) |
| **session-05** | App Configuration 피처 플래그 | App Configuration · KV refs · Feature flag | [05-app-config-flags.md](./docs/sessions/05-app-config-flags.md) |
| **session-06** | Observability 심화 | OTel 커스텀 span · KQL Workbook · Alert | [06-observability.md](./docs/sessions/06-observability.md) |
| **session-07** | AKS 대안 배포 | AKS · Container Insights (DCR+DCRA) · `apps/worker` | [07-aks.md](./docs/sessions/07-aks.md) |

각 세션 (session-00 제외) 은 동일한 3단계 흐름을 따릅니다:

1. **프로비저닝** — Bicep 으로 자원 배포 (배포되는 동안 §2 준비)
2. **복붙으로 경험해보기** — docs 의 검증된 코드 스니펫을 *그대로* 복사·붙여넣기 → 실행
3. **Azure Portal UI 에서 확인** — 방금 발생한 트래픽·데이터를 Portal 의 해당 블레이드에서 직접 확인

---

## 비용 견적

워크샵 종료 후 **곧바로 자원을 정리할 경우** 약 **$10~20 (USD)** 수준입니다. 정리를 잊으면 가장 큰 누적 비용은 Managed Redis Enterprise M10 (~$8/일) 와 AKS LB+IP (~$1/일) 입니다. [docs/cleanup.md](./docs/cleanup.md) 의 정리 절차를 반드시 수행합니다.

---

## 진행 중 막혔을 때 (save-points)

각 세션 시작 시점은 git 태그 `session-NN-start`, 종료 시점은 `session-NN-complete` 입니다. 따라잡기:

```bash
# 예: session-03 시작 시점에서 다시 시작하고 싶을 때
git checkout session-03-start -- apps/ infra/sessions/03-redis-cache/
```

자세한 함정과 회피법은 [docs/pitfalls/common.md](./docs/pitfalls/common.md) 에 모았습니다.

---

## 라이선스 / 기여

본 워크샵 자료는 학습 목적의 포트폴리오 프로젝트입니다. 기술 스택과 모범 사례는 시간이 지나면 변경될 수 있으니, 워크샵 진행 시점의 Azure 공식 문서를 항상 우선하세요.
