# Azure AI-200 Challenge — 사내 문서 RAG 지식 비서

> [!NOTE]
> **Azure AI-200 자격증의 핵심 기술 스택 전부**를 직접 만지며 **동작하는 사내 문서 RAG 지식 비서** 를 본인의 Azure 구독 위에 올립니다.

## 사전 준비

챌린지 시작 전 [PREREQUISITES.md](./PREREQUISITES.md) 의 체크리스트를 순서대로 모두 완료합니다. 특히 Azure OpenAI 액세스 신청은 승인까지 시간이 걸릴 수 있으므로 가장 먼저 신청해두는 것을 권장합니다.

---

## 챌린지 로드맵

이 챌린지를 마치면 아래 각 세션의 **"본인 손으로 경험하는 것"** 을 **코드 한 줄까지 직접** 만지게 됩니다.

| # | 제목 | 본인 손으로 경험하는 것 | 핵심 자원 |
|---|---|---|---|
| **session-00** | [사전 설정 & 구독 준비](./docs/sessions/00-setup.md) | X (이후 모든 세션의 기반 자원 준비) | 리소스 그룹 · Azure OpenAI · Log Analytics · Application Insights · Key Vault · 관리 ID(사용자 할당) |
| **session-01** | [RAG 최소 기능 제품 — Azure Container Apps · Key Vault · OpenTelemetry](./docs/sessions/01-rag-mvp.md) | Azure OpenAI (chat + embedding) 로 RAG 파이프라인 구축 | Azure Container Registry · Azure Container Apps · Cosmos DB(벡터) |
| **session-02** | [PostgreSQL pgvector 비교](./docs/sessions/02-pgvector.md) | Cosmos DB 와 PostgreSQL pgvector 의 벡터 검색 비교 | PostgreSQL Flexible Server · pgvector · `halfvec(3072)` |
| **session-03** | [Managed Redis 시맨틱 캐시](./docs/sessions/03-redis-cache.md) | Managed Redis 시맨틱 캐시 | Redis Enterprise · RediSearch |
| **session-04** | [비동기 인제스션 (Service Bus + Event Grid + Azure Functions)](./docs/sessions/04-async-ingestion.md) | Service Bus · Event Grid · Azure Functions 로 비동기 인제스션 | Service Bus · Event Grid · Azure Functions(Flex Consumption) · Storage |
| **session-05** | [App Configuration 피처 플래그](./docs/sessions/05-app-config-flags.md) | Key Vault + App Configuration + Managed Identity 로 시크릿·런타임 설정 분리 | App Configuration · Key Vault 참조 · Feature flag |
| **session-06** | [Observability 심화](./docs/sessions/06-observability.md) | Application Insights · OpenTelemetry · KQL 로 관측성 | OpenTelemetry 커스텀 span · KQL Workbook · Alert |
| **session-07** | [Azure Kubernetes Service 대안 배포](./docs/sessions/07-aks.md) | Azure Container Apps (메인) 와 Azure Kubernetes Service (대안) 양쪽 배포 | Azure Kubernetes Service · Container Insights(Data Collection Rule + Association) · `apps/worker` |

각 세션 (session-00 제외) 은 동일한 3단계 흐름을 따릅니다:

1. **프로비저닝** — Bicep 으로 자원 배포 (배포되는 동안 아래 2단계 진행)
2. **복붙으로 경험해보기** — docs 의 검증된 코드 스니펫을 **그대로** 복사·붙여넣기 → 실행
3. **Azure Portal UI 에서 확인** — 방금 발생한 트래픽·데이터를 Portal 의 해당 블레이드에서 직접 확인

---

## 진행 중 막혔을 때 (save-points)

본 챌린지는 **단일 `main` 브랜치 + 폴더 복사** 방식의 save-point 메커니즘을 사용합니다. 학습자는 아래 예시처럼 `save-points/session-NN/{start,complete}/` 안의 코드를 `workshop/` 폴더로 복사해 그 위에서 작업합니다.

```bash
# 세션 시작 — 시작본을 작업 폴더로
mkdir -p workshop && \
  cp -a save-points/session-03/start/. workshop/

# 막혔을 때 — 완성본으로 덮어쓰기
cp -a save-points/session-03/complete/. workshop/
```

`workshop/` 폴더는 `.gitignore` 에 등록되어 있어 안에서 무엇을 하든 본 저장소의 git 상태는 깨끗하게 유지됩니다. 자세한 사용법은 [save-points/README.md](./save-points/README.md) 를 참고합니다.

특정 단계에서 막혔다면 [docs/pitfalls/common.md](./docs/pitfalls/common.md) 에서 **모든 세션의 함정·주의를 한곳에서** 검색합니다. 인증·RBAC, Bicep·IaC, 벡터·인덱싱, 관찰 가능성 등 카테고리별로 묶여 있으며 증상·원인·회피로 정리되어 있습니다.

---

## 비용

> [!IMPORTANT]
> 챌린지 종료 후 **곧바로 자원을 정리할 경우** 약 **$10~20 (USD)** 수준입니다. 정리를 잊을 경우 가장 큰 누적 비용은 Managed Redis Enterprise M10와 AKS LB+IP입니다.
> 
> 챌린지 제작자가 일주일동안 session-00 ~ session-04까지 진행한 후 약 7일동안 자원을 정리하지 않았더니 약 13만원 사용했습니다. 그러나 챌린지 진행 직후 바로 정리한다면 1만원도 사용하지 않습니다.
> 
> 그러니 하루 안에 챌린지를 수행하는 것을 권장드립니다.
>
> 모든 내용을 진행했다면 [docs/cleanup.md](./docs/cleanup.md)의 정리 절차를 반드시 수행합니다.

---

## AI-200 학습 경로 매핑

| AI-200 공식 학습 경로 | 본 챌린지 세션 |
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

## 라이선스 / 기여

본 챌린지 자료는 학습 목적의 포트폴리오 프로젝트입니다. 기술 스택과 모범 사례는 시간이 지나면 변경될 수 있으니, 챌린지 진행 시점의 Azure 공식 문서를 항상 우선하는 것을 권장합니다.
