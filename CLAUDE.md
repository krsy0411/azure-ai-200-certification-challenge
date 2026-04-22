# CLAUDE.md

이 레포는 **Microsoft Azure AI-200 자격증**을 커버하는 엔터프라이즈 RAG 지식 비서를 구축하는 포트폴리오 챌린지 프로젝트입니다. Claude Code에게 주는 컨텍스트를 여기에 모읍니다.

## 프로젝트 성격

- 학습 + 포트폴리오 + 자격증 대비가 동시에 목표인 **개인 레포**.
- 실사용 트래픽은 없음. 비용 최적화 < 학습 커버리지.

## 절대 지켜야 할 작업 원칙

1. **Phase 경계를 임의로 넘지 말 것.** Phase N 완료 전에는 N+1에 해당하는 구현을 선제적으로 하지 않는다.
   - Phase 매핑: `docs/roadmap.md` 참고.
   - 한 Phase는 (구현 → 실배포 검증 → 문서 업데이트) 3단계가 모두 끝나야 완료.
2. **문서 업데이트는 구현의 일부.** `docs/learning-paths/0N-*.md`에 실제 사용한 명령어·SDK 호출·함정 포인트를 남긴다.
3. **언어**: 사용자 커뮤니케이션·문서는 한국어. 코드 주석은 최소화(영문/한국어 모두 허용).
4. **배포 방식 — Portal 우선, CLI는 Phase 10.** Phase 1~9 의 실배포는 반드시 **Azure Portal GUI 단계별 가이드** 형식으로 문서화하고 스크린샷 슬롯을 남긴다(교육 자료 목적). `az` CLI · `kubectl` · Helm 등 커맨드 스크립트는 **Phase 10(IaC 이전)** 에서만 등장. Phase 1~9 문서에 선제적으로 CLI 를 쓰지 말 것. Portal 에서 어려운 작업은 Deployment Center · ACR Tasks(Git 연동) 등 Portal 네이티브 경로로 푼다.
5. **실제 Azure 배포 실행은 사용자가 수행.** Claude 는 Portal 경로 가이드와 필드값만 준비하고, 사용자가 Portal에서 직접 클릭한 뒤 스크린샷을 `docs/learning-paths/screenshots/0N/` 에 추가한다.
6. **보안**: 시크릿은 Phase 8 이후 Key Vault + 관리형 ID가 표준. 그 전에는 `.env`를 쓰되 `.gitignore`로 반드시 제외.

## Azure 리소스 네이밍 · 리전 규칙 (고정)

- **기본 리전**: `koreacentral` (Azure OpenAI 사용 가능 확인됨)
- **환경 라벨**: `dev`, `prod` (Phase 8 App Configuration 레이블과 일치)
- **프로젝트 식별자**: `ai200challenge`
- **일반 규칙**: `<리소스약어>-ai200challenge-<env>` 예) `rg-ai200challenge-dev`, `cae-ai200challenge-dev`, `kv-ai200challenge-dev`
- **하이픈 금지 리소스**(ACR·Storage 등): `<약어>ai200challenge<env><2~4자 고유접미사>` 예) `acrai200challengedevXX`, `stai200challengedevXX`
- **약어 표준**:
  - `rg` 리소스 그룹 | `acr` Container Registry | `cae` ACA Environment | `aks` Kubernetes 클러스터
  - `cosmos` Cosmos DB | `pg` PostgreSQL | `redis` Managed Redis
  - `sb` Service Bus | `egt` Event Grid 토픽 | `func` Azure Functions | `st` Storage
  - `kv` Key Vault | `ac` App Configuration | `ai` Application Insights | `law` Log Analytics Workspace

## 기술 스택 (고정)

- Backend: Python 3.12, FastAPI, uvicorn, Pydantic v2
- Frontend: Next.js 14+ (App Router), TypeScript
- LLM: Azure OpenAI (gpt-4o-mini + text-embedding-3-large)
- Data: Cosmos DB for NoSQL, PostgreSQL Flexible Server(pgvector), Azure Managed Redis
- Hosting: ACA(메인) + AKS(보조 워커) + ACR
- Async: Service Bus, Event Grid, Azure Functions
- Secrets/Config: Key Vault, App Configuration, Managed Identity
- Observability: OpenTelemetry → Azure Monitor/Application Insights

스택 변경은 사용자 승인 필요.

## 커밋 규칙

- 커밋 메시지는 Phase 번호와 해당 학습 경로 이름을 포함: 예) `feat(phase-2): ACA 환경 + 컨테이너 앱 배포`.
- Claude가 자동으로 커밋하지 않음. 사용자 요청 시에만 커밋.

## 전용 서브에이전트

- `azure-architect` — Azure 리소스 설계·IaC 결정
- `rag-engineer` — 벡터 검색·임베딩·RAG 파이프라인
- `observability-expert` — OpenTelemetry·KQL·알림 설계

필요 시 `.claude/agents/*.md`에서 정의 확인.

## 참고 링크 (AI-200 공식 학습 경로)

- https://learn.microsoft.com/ko-kr/training/paths/implement-container-app-hosting-azure/
- https://learn.microsoft.com/ko-kr/training/paths/deploy-manage-apps-azure-container-apps/
- https://learn.microsoft.com/ko-kr/training/paths/deploy-monitor-apps-azure-kubernetes-service/
- https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-cosmos-db/
- https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-database-postgresql/
- https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/
- https://learn.microsoft.com/ko-kr/training/paths/integrate-backend-services-ai-solutions/
- https://learn.microsoft.com/ko-kr/training/paths/manage-app-secrets-configuration/
- https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/
