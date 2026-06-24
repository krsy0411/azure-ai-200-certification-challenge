# CLAUDE.md

이 레포는 **Microsoft Azure AI-200 자격증**의 핵심 스택을 다루는 RAG 지식 비서를 **참가자가 문서만 보고 본인 구독에 직접 올리는 "Challenge in a Day"** 산출물입니다. Claude Code에게 주는 컨텍스트를 여기에 모읍니다.

## 프로젝트 성격

- **챌린지 자료(참가자가 따라 하는 문서·코드·IaC)** 가 1차 산출물. 동시에 학습 + 포트폴리오 + 자격증 대비도 목표.
- 모든 변경은 **§11 "챌린지 참가자 관점 우선"** 을 기준으로 한다 — 개인적으로 Claude 와 함께 실행하는 맥락이 아니라, 처음 보는 참가자가 다양한 OS·환경에서 문서를 따라 할 때 동작하는지로 판단.
- 실사용 트래픽은 없음. 비용 최적화 < 학습 커버리지.

## 절대 지켜야 할 작업 원칙

1. **session 경계를 임의로 넘지 말 것.** session N 완료 전에는 N+1에 해당하는 구현을 선제적으로 하지 않는다.
   - session 매핑·전체 흐름: `README.md` 의 세션 표 참고 (session-00 ~ session-07).
   - 한 session 은 (구현 → 실배포 검증 → 문서 업데이트) 3단계가 모두 끝나야 완료.
2. **session 계획 전 공식 학습 경로 정독.** session N 의 설계·결정·구현 작업을 시작하기 전에 해당 MS Learn 학습 경로의 **모든 모듈 페이지와 모든 단원(unit) 제목·학습 목표·연습 시나리오를 직접 fetch 해서 확인**한다.
   - 추측·기억·인접 session 의 지식으로 대체 금지. 사용자에게 보여주는 매핑 표·결정 옵션은 이 정독을 거친 결과여야 한다.
   - 정독에서 얻은 단원 단위 흐름은 §3 의 "MS Learn 경로 커버리지 — 사용/생략" 표 작성의 근거가 된다 — 단원 제목을 그대로 표 행으로 쓸 정도로 1:1 매핑.
   - 새 대화에서 session 을 이어 받을 때도 동일. 메모리·자동 요약만 보고 바로 구현에 들어가지 말고, 해당 session 학습 경로를 다시 정독하고 시작.
3. **문서 업데이트는 구현의 일부.** `docs/sessions/0N-*.md`에 실제 사용한 명령어·SDK 호출·함정 포인트를 남긴다. 또한 각 session 문서에는 **"MS Learn 경로 커버리지 — 사용/생략"** 섹션을 반드시 포함해, 공식 경로의 어떤 모듈·기능을 프로젝트에서 사용했고 어떤 부분을 의도적으로 생략했는지(비용·학습 범위·다른 session 으로 이관 등) 표로 드러낸다.
4. **언어**: 사용자 커뮤니케이션·문서는 한국어. 코드 주석은 최소화(영문/한국어 모두 허용).
5. **배포 방식 — Bicep IaC 우선.** session 00~07 의 모든 리소스 프로비저닝·구성은 **Bicep 모듈**로 선언하고, 각 session 은 단일 엔트리 `infra/sessions/0N-*/main.bicep` 에서 모듈을 조립해 `az deployment group create` / `az deployment sub create` 로 배포한다. Portal GUI 는 스크린샷·교육 산출물이 아니라 **결과 확인용**으로만 사용한다. **예외 — 컨테이너 이미지 빌드·ACR 푸시**: IaC 로 선언할 수 없는 작업이므로 `docker build --platform linux/amd64` + `docker push` + `az acr login` CLI 를 각 session 문서의 "이미지 빌드·푸시" 하위에서 사용. **(향후) CI 세션**은 각 session 의 `main.bicep` 을 `infra/main.bicep` 에 상위 조립하고 GitHub Actions CI 로 자동화하는 **축소된 범위**다.
6. **실제 배포 실행은 사용자가 수행.** Claude 는 Bicep 모듈·파라미터·배포 명령어를 준비하고, 사용자가 `az deployment ... what-if` 로 검토 후 실제 배포를 실행한다. 문서의 "함정·교훈" 섹션은 배포 후 사용자/Claude 가 같이 채운다.
7. **자원 라이프사이클 — session 단위 정리 + 무료/사실상-무료 자원만 보존.** 비용 통제와 학습 격리를 위해 session 마다 자원이 살았다 정리되는 사이클을 갖는다.
   - **비용 현실 (session-04 실측, 7일 108,569 KRW, docs/sessions/04-async-ingestion.md 함정 8)**: dev 환경이라도 idle 자원이 **시간당** 누적된다. Redis Enterprise Memory_M10 = ~11,680 KRW/일, ACA Container App (min replica 1) = ~1,743 KRW/일, AKS LB+IP = ~1,125 KRW/일, PG B1ms = ~700 KRW/일. **compute 가 있는 자원은 idle 만으로도 빠르게 누적**.
   - **검증 보존**: session 검증·측정이 끝났더라도 Claude 는 자원을 자동 삭제하지 않는다. 사용자가 Portal·브라우저·외부 도구로 추가 검증을 할 수 있으므로, **"정리해" / "삭제해" / "drop" 등 명시 요청 전까지** 모든 Azure 자원과 임시 권한 (예: AAD admin 부여, ACA ingress external 토글) 을 그대로 둔다.
   - **session 종료 시 정리 + 다음 session 진입 시 재배포**: 사용자 명시 요청을 받으면 해당 session 의 **모든 compute/유료 자원** 을 정리한다. 다음 session 의 `main.bicep` 이 그 자원을 `existing` 참조한다면 다음 session 진입 직전에 해당 session 의 `main.bicep` 을 한 번 다시 돌려 재배포한다 (이전 session 의 데이터 자원을 다음 session 이 `existing` 참조하는 패턴). 같은 이름의 자원이 soft-delete 충돌하면 접미사를 한 단계 올린다 (`dev04` → `dev06`).
   - **보존 / 정리 분류 (session-04 실측 기반, 2026-05-18 룰 갱신)**:
     - **보존 (무료 또는 사실상-무료)**:
       - **ACR Basic** (`acr...`) — storage 만 ~260 KRW/일, 이미지가 학습 자산
       - **Log Analytics** (`law-...`) — 5GB/월 free, ingest 만 과금
       - **공용 UAMI** (`id-...-aca-...`, `id-...-aks-...`) — 무료
       - **ACA Environment** (`cae-...`) — Container App 이 살아있을 때만 과금. 자체는 무료
       - **Application Insights** (`ai-...`) — workspace-based 라 LAW 와 같이 ingest 만
       - **Key Vault / App Configuration** (Key Vault 는 session-00·01, App Configuration 은 session-05) — sub-원 단위 비용
     - **정리 (compute 또는 유의미한 idle 비용)**:
       - **Cosmos DB / Azure OpenAI / PostgreSQL / Managed Redis** — session 01·02·03 데이터 자원 (Azure OpenAI 는 session-00 기반 자원)
       - **Service Bus / Event Grid / Function App / Storage** — session-04 신규
       - **ACA Container Apps (api / web)** — session 단위 정리, 다음 session 진입 시 image tag 와 함께 재배포 (CAE 는 보존이므로 컨테이너만 정리)
       - **AKS 클러스터 + 자동 생성된 `MC_...` RG** — session-07 학습 산출물이지만 LB+IP idle 비용. 학습 완료 후 정리. (향후) CI/포트폴리오 세션에서 단순 manifest 시연이면 재배포
   - **임시 권한 회수는 정리 룰의 예외**: 본인 objectId 임시 admin 부여, ACA ingress 임시 external 토글 등 **검증 흐름의 일부로 잠시 부여한 권한** 은 검증 종료 시점에 같은 흐름 안에서 회수한다 (별도 사용자 요청 불필요). 자원 삭제와 권한 회수는 다른 결정이다.
   - **이전 룰 (2026-05-18 이전) 과의 차이**: 이전 룰은 **공용 UAMI / CAE / AKS / ACA api·web** 도 보존이었다. 실측 비용 (session-04) 으로 ACA + AKS 가 **진짜** idle 비용 발생 자원임이 드러나 보존 목록에서 제외. UAMI / CAE / LAW / ACR / AI 만 무료 또는 사실상 무료.
8. **보안**: 시크릿은 session-01 부터 Key Vault + 관리형 ID 가 표준이고 (session-05 에서 App Configuration 으로 런타임 설정 분리), 로컬 개발용 `.env` 는 `.gitignore` 로 반드시 제외한다.
   - **IaC 파라미터 파일에 사용자 식별 정보 박지 말 것.** `*.bicepparam` 의 `devClientIpAddress`, 본인 Entra objectId, 거주지·근무지 단서가 되는 값은 default 를 `'0.0.0.0'` / `''` 로 두고, 배포 시점에 `az deployment ... -p key=$VAR` 로 **override** 한다. 이유: firewall allowlist · admin 부여 정보와 함께 git history 에 영구 남으면 공격면 정보 + 포트폴리오용 public 레포 노출 위험. 동일 원칙을 `principalId` 등 모든 사용자별 값에 적용.
9. **작업 컨텍스트 — Claude Code 네이티브 메모리.** 사용자는 컴퓨터를 자주 켜고 끄며 대화 컨텍스트가 자주 날아간다. 진행 중인 session·미해결 결정·다음 액션은 **Claude Code 의 프로젝트 메모리**(자동 요약 + 메모리 파일)에 남겨 새 대화에서 복원되게 한다.
   - 별도의 커밋 문서(`docs/history.md`)는 두지 않는다 — session 별 세부 진행 내역은 각 `docs/sessions/0N-*.md` 가 보유하고, 그 위에서 학습 경로를 다시 정독해 맥락을 복원한다.
   - 새 대화 시작 시 Claude 는 메모리·해당 session 문서로 맥락을 복원한 뒤 사용자에게 한두 문장으로 "이어서 무엇을 할지" 제안한다.
10. **session 진행 7-단계 워크플로우 — Skills 진입.** 각 session 작업은 ① 학습 경로 정독 → ② 사용자 결정 승인 → ③ 구현 → ④ lint → ⑤ 문서 그대로 실행·재현 → ⑥ 사용자 GUI 검증 → ⑦ 자원 정리 의 7 단계로 진행한다. Claude/사용자는 다음 슬래시 커맨드로 단계를 진입:
    - **`/phase-start <N>`** — 단계 1 + 2 (`phase-learning-fetcher` subagent 가 학습 경로 정독, main 이 결정 옵션 표 제시 후 사용자 승인 대기)
    - **(단계 3 구현)** — 자유, Skill 외부. 단계 4 (lint) 는 PostToolUse hook 으로 자동 (`*.bicep`, `apps/api/src/**/*.py`)
    - **`/phase-verify <N>`** — 단계 5. 세션 문서(`docs/sessions/0N-*.md`)를 처음 보는 참가자처럼 **그대로 따라** 코드를 순서대로 생성하고 명령을 실행·배포한 뒤, `save-points/session-NN/complete` 정답지와 대조해 "문서만으로 재현되는가"(§11) 결함을 리포트. 검증 종료 시 사용자에게 단계 6 진입 안내
    - **(단계 6 GUI 검증)** — 사용자가 Portal·브라우저로 직접 수행. "GUI 검증 끝" / "정리해" 등 명시 메시지가 다음 단계 트리거
    - **`/phase-cleanup`** — 단계 7 (§7 룰대로 session-specific 자원만 정리, 공통 자원 보존)
    - 단계 detail 은 `.claude/skills/phase-{start,verify,cleanup}/SKILL.md` 에. PreToolUse hook (`block-az-delete.sh`) 이 사용자 명시 정리 요청 마커 (`/phase-cleanup` 이 만드는 `.claude/cleanup-approved`) 없이는 `az ... delete` 차단.
    - **자동 invoke 금지**: 세 Skill 모두 `disable-model-invocation: true`. 사용자 또는 Claude 가 명시적으로 슬래시 커맨드로 호출.
11. **챌린지 참가자 관점 우선 (challenge-participant-first) — 모든 문서·코드 변경의 기본 시점.** 이 레포는 **참가자가 문서만 보고 본인 구독·본인 컴퓨터에서 따라 하는 챌린지** 산출물이다. 무언가를 수정·반영할 때는 **"나(사용자)와 Claude 가 이 세션에서 함께 실행하는 개인적 맥락"이 아니라, 처음 보는 참가자가 문서를 따라 할 때 동작하는가** 를 기준으로 결정한다.
    - **재현성**: 문서만으로 재현 가능해야 한다. 일회용 임시 스크립트·임시 경로(`/tmp/...`)나 "Claude 가 대신 실행해 줌" 전제 금지. 검증·캡쳐·트래픽 생성 등 필요한 도구는 레포에 커밋(`scripts/` 등)하고 문서에서 명령으로 안내한다.
    - **크로스 환경(다양한 OS·셸·설치 버전)**: Windows·macOS·Linux, 서로 다른 셸·도구 버전·Python 버전에서 깨지지 않게 작성한다. 가능하면 고정된 의존성 환경(`uv run --project apps/api ...`)을 쓰고, macOS 인증서(`SSL_CERT_FILE`/`certifi`) 같은 알려진 함정을 회피하며, bash 전용·특정 CLI 버전 전용 가정을 피한다(또는 문서에 명시).
    - **개인 환경 의존 금지**: 특정 사용자만 가진 상태(로컬 절대경로, 이미 떠 있는 자원, 수동으로 부여한 권한, 본인만 아는 이름)를 전제로 하지 않는다. 사용자 식별 정보는 §8 대로 배포 시점 override.
    - **검증·캡쳐 방식도 동일 기준**: 모든 참가자가 재현 가능한 방법을 택한다. 예) ACA scale-to-zero 환경에서 replica 가 0 이면 실시간 스트림이 끊겨 캡쳐가 비실용적인 Live Metrics 보다, scale-to-zero 와 무관하게 영구 데이터로 남는 KQL(Logs) 기반 검증을 선호한다. 부득이 개인 맥락에서 먼저 실행해 본 결과라도, 문서에는 참가자가 따라 할 수 있는 형태로만 반영한다.

## Azure 리소스 네이밍 · 리전 규칙 (고정)

- **기본 리전**: `koreacentral` (Azure OpenAI 사용 가능 확인됨)
- **환경 라벨**: `dev`, `prod` (session-05 App Configuration 레이블과 일치)
- **프로젝트 식별자**: `ai200ws`
- **일반 규칙**: `<리소스약어>-ai200ws-<env>` 예) `rg-ai200ws-dev`, `cae-ai200ws-dev`, `kv-ai200ws-dev`
- **하이픈 금지 리소스**(ACR·Storage 등): `<약어>ai200ws<env><2~4자 고유접미사>` 예) `acrai200wsdevXX`, `stai200wsdevXX`
- **약어 표준**:
  - `rg` 리소스 그룹 | `acr` Container Registry | `cae` ACA Environment | `ca` Container App | `aks` Kubernetes 클러스터
  - `cosmos` Cosmos DB | `pg` PostgreSQL | `redis` Managed Redis
  - `sb` Service Bus | `egt` Event Grid 토픽 | `func` Azure Functions | `st` Storage
  - `kv` Key Vault | `ac` App Configuration | `ai` Application Insights | `law` Log Analytics Workspace | `id` User-Assigned Managed Identity
  - `asp` App Service Plan (Azure Functions 호스팅 플랜)

## 기술 스택 (고정)

- Backend: Python 3.12, FastAPI, uvicorn, Pydantic v2
- Frontend: Next.js 14+ (App Router), TypeScript
- LLM: Azure OpenAI (gpt-5-mini + text-embedding-3-large)
- Data: Cosmos DB for NoSQL, PostgreSQL Flexible Server(pgvector), Azure Managed Redis
- Hosting: ACA(메인) + AKS(보조 워커) + ACR
- Async: Service Bus, Event Grid, Azure Functions
- Secrets/Config: Key Vault, App Configuration, Managed Identity
- Observability: OpenTelemetry → Azure Monitor/Application Insights

스택 변경은 사용자 승인 필요.

## 커밋 규칙

- 커밋 메시지는 session 번호와 해당 학습 경로 이름을 포함: 예) `feat(session-01): ACA 환경 + 컨테이너 앱 배포`.
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
