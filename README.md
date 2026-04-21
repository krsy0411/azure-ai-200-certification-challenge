# azure-ai-200-certification-challenge

Microsoft Azure **AI-200** (Azure AI 클라우드 솔루션 개발) 자격증 챌린지 프로젝트.

자격증 9개 공식 학습 경로를 **하나의 완결된 엔터프라이즈 RAG 지식 비서**로 풀어내는 포트폴리오 레포입니다.

## 목표

- Microsoft Learn의 AI-200 학습 경로 9개를 **구현 → 실배포 → 문서화** 3단계로 모두 소화한다.
- 문서·커밋 이력·아키텍처를 자격증 학습 로드맵과 1:1 매핑한다.

## 기술 스택

| 계층 | 선택 |
|---|---|
| 프론트엔드 | Next.js 14+ (App Router) + TypeScript |
| 백엔드 | Python 3.12 + FastAPI |
| 기본 호스팅 | **Azure Container Apps (ACA)** 메인, **AKS** 보조 워크로드 1개 |
| 이미지 저장소 | Azure Container Registry (ACR) |
| AI | Azure OpenAI (gpt-4o-mini, text-embedding-3-large) |
| 벡터/문서 스토어 | Azure Cosmos DB for NoSQL |
| 관계형 + pgvector | Azure Database for PostgreSQL Flexible Server |
| 캐시/메시징 | Azure Managed Redis (시맨틱 캐시 · Pub/Sub · Streams) |
| 비동기 워크플로 | Azure Service Bus, Event Grid, Azure Functions |
| 보안/구성 | Microsoft Entra ID (관리형 ID), Azure Key Vault, Azure App Configuration |
| 관찰성 | OpenTelemetry + Azure Monitor / Application Insights |

## 디렉터리 구조

```
.
├── apps/
│   ├── api/              # Python FastAPI (메인 백엔드)
│   └── web/              # Next.js (챗 UI · 문서 업로드)
├── infra/                # Bicep/Terraform IaC (Phase 후반에 구축)
├── docs/
│   ├── roadmap.md        # 9 Phase 단계형 로드맵
│   ├── architecture.md   # 목표 아키텍처 다이어그램/설명
│   ├── learning-paths/   # 학습 경로별 노트 (MS Learn ↔ 구현 매핑)
│   └── decisions/        # ADR (아키텍처 결정 기록)
└── .claude/
    └── agents/           # Azure 개발 전용 서브에이전트
```

## Phase 로드맵 (요약)

| # | Phase | 대응 학습 경로 |
|---|---|---|
| 1 | 컨테이너 호스팅 기초 | implement-container-app-hosting-azure |
| 2 | ACA 배포·리비전·스케일링 | deploy-manage-apps-azure-container-apps |
| 3 | AKS 보조 워크로드 | deploy-monitor-apps-azure-kubernetes-service |
| 4 | Cosmos DB 문서 + 벡터 | develop-ai-solutions-azure-cosmos-db |
| 5 | PostgreSQL pgvector | develop-ai-solutions-azure-database-postgresql |
| 6 | Managed Redis (캐시/PubSub/Stream) | enhance-ai-solutions-azure-managed-redis |
| 7 | Service Bus / Event Grid / Functions | integrate-backend-services-ai-solutions |
| 8 | Key Vault / App Configuration | manage-app-secrets-configuration |
| 9 | OpenTelemetry / Monitor / KQL | observe-troubleshoot-apps |

자세한 단계 내용은 [docs/roadmap.md](docs/roadmap.md).
