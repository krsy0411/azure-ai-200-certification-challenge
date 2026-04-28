# 작업 히스토리 — Claude Code 세션 컨텍스트

> **이 문서의 역할**: 컴퓨터를 자주 끄고 켜는 환경에서 Claude Code 대화 컨텍스트가 날아가도, 새 대화를 시작할 때 이 문서를 먼저 읽으면 즉시 작업을 이어갈 수 있도록 하는 **living document**.
>
> **갱신 규칙** (CLAUDE.md §7 와 일치):
> - 사용자 명시 요청 ("히스토리 갱신", "지금까지 정리해", "history 기록", "맥락 저장" 등) 시에만 갱신
> - 작업 도중 Claude 가 자동으로 갱신하지 않음
> - 갱신은 commit 을 별도로 동반하지 않음 (사용자가 push 시점 결정)
> - 자세한 함정·명령어·코드 인용은 `docs/learning-paths/0N-*.md` 에 두고 여기서는 짧게 포인터만

마지막 갱신: **2026-04-27** — Phase 5 진입 직전, 결정 포인트 3개 사용자 응답 대기 중.

---

## 현재 위치

- **마지막 완료 Phase**: **Phase 4** (Cosmos NoSQL 벡터 검색 + Azure OpenAI 통합)
- **진입 직전 Phase**: **Phase 5** (PostgreSQL Flexible Server + pgvector)
- **현재 상태**: Phase 5 결정 포인트 3개 사용자 응답 대기 중 (아래 "다음 액션" 참조)
- **마지막 커밋**: `042dbfe feat(phase-4): Cosmos NoSQL 벡터 검색 + AOAI 통합` (origin/main 푸시 완료)
- **Azure RG (`rg-ai200challenge-dev`) 잔여 리소스**:
  - Phase 1: `acrai200challengedev04` (이미지: `api:0.1.0`, `api:0.4.0`, `web:0.1.0` 보존)
  - Phase 2: `id-ai200challenge-aca-dev`, `law-...`, `cae-...`, `ca-...-api-dev` (image=0.1.0 / envCount=0 으로 원복됨), `ca-...-web-dev`
  - Phase 3: `id-ai200challenge-aks-dev`, `aks-ai200challenge-dev`, `MSCI-koreacentral-aks-...`
  - **Phase 4 자원은 검증 후 정리 완료** (Cosmos hard-delete + AOAI purge 까지). 같은 이름 (`cosmos-ai200challenge-dev04`, `aoai-ai200challenge-dev04`) 으로 재배포 가능.

---

## 다음 액션 — Phase 5 진입 전 사용자 결정 대기 중

마지막 메시지에서 사용자에게 던진 결정 3개. **사용자가 "추천대로 가" 또는 다른 선택을 답하는 즉시 Phase 5 구현 진입.**

### 결정 1 — 벡터 차원 / 데이터 타입 (초안 함정)

`docs/learning-paths/05-postgresql.md` 초안의 `vector(3072)` 는 **pgvector 인덱스 한계 (HNSW·IVFFlat 둘 다 2000-d) 초과**. 그대로 두면 `CREATE INDEX` 실패.

| 옵션 | 데이터 타입 | 메모 |
|---|---|---|
| **A (추천)** | `halfvec(3072)` | pgvector 0.7+, Azure Database for PG 의 0.8 GA 로 OK. **Phase 4 와 1:1 비교 가능**. 16-bit float 로 메모리 절반 |
| B | `vector(1536)` + AOAI `dimensions=1536` | 표준 vector 타입, 인덱스 자연스러움. 단 Phase 4 와 차원 달라 비교 가치 손상 |

### 결정 2 — Phase 4 자원 동시 가동?

- **Y (추천)**: Phase 5 main.bicep 안에 Phase 4 의 cosmos/aoai 모듈을 다시 호출 → 같은 데이터셋으로 vector search 두 곳에 적재 → "Cosmos vs PG" 비교 측정. **Phase 5 학습 산출물의 핵심.**
- N: PG 단독, 비교는 Phase 4 의 과거 측정값으로만.

### 결정 3 — 인증 모드

- **Entra-only (추천)**: passwordless. UAMI 토큰을 psycopg `password` 로 사용. AI-200 시험 + 본 레포의 AAD-only 일관성.
- admin user + Entra 병행: 부트스트랩 쉽지만 본 레포 표준에서 벗어남.

> 추천 종합: **A + Y + Entra-only**.

### Phase 5 자동 진행 (사용자 추가 결정 불필요)

- **PG SKU**: Burstable `B1ms` (1 vCore 2GB), HA off, storage 32GB, **PG 16**
- **벡터 인덱스**: HNSW (m=16, ef_construction=64) **+** IVFFlat (lists=100) **둘 다 빌드** → 같은 쿼리로 측정 후 비교 표 작성
- **public access**: 본인 IP + Azure services allow (Phase 9 까지 PE 도입 안 함)
- **테이블 모델**: 초안 (workspaces / documents / chunks) 그대로, `embedding` 만 `halfvec(3072)` 로
- **변경 피드/자동 임베딩**: Phase 7 (Functions) 로 이관 — Phase 4 와 동일 원칙
- **API 라우터**: Phase 4 의 `/api/index`, `/api/search` 에 query string `?store=pg|cosmos` 추가하여 분기 (별도 라우터 X)

---

## Phase 진행 요약 표

| Phase | 학습 경로 | 상태 | 핵심 산출물 / 메모 |
|---|---|---|---|
| 1 | `implement-container-app-hosting-azure` | ✅ | App Service + ACR + Dockerfile 2종. Phase 2 안정화 후 App Service/ASP 만 정리 (ACR 보존) |
| 2 | `deploy-manage-apps-azure-container-apps` | ✅ | ACA Env + api(internal)/web(external) + 공용 UAMI ACR pull. 현재 살아있음 |
| 3 | `deploy-monitor-apps-azure-kubernetes-service` | ✅ | AKS 클러스터 + Container Insights (DCR/DCRA IaC) + worker manifest. 현재 살아있음 |
| 4 | `develop-ai-solutions-azure-cosmos-db` | ✅ | Cosmos NoSQL Serverless + Vector(`quantizedFlat`) + AAD-only / AOAI(gpt-4o-mini + text-embedding-3-large, GlobalStandard chat / Standard embed). **검증 후 정리** — 재배포 가능 |
| 5 | `develop-ai-solutions-azure-database-postgresql` | ⏸ 진입 직전 | Cosmos vs PG 비교 측정. Entra-only, halfvec(3072), HNSW+IVFFlat 둘 다 |
| 6 | `enhance-ai-solutions-azure-managed-redis` | 미착수 | 시맨틱 캐시 + Pub/Sub + Streams |
| 7 | `integrate-backend-services-ai-solutions` | 미착수 | Service Bus / Event Grid / Functions. **변경 피드 자동 임베딩이 여기로 이관됨** |
| 8 | `manage-app-secrets-configuration` | 미착수 | Key Vault + App Configuration. `.env` 제거 |
| 9 | `observe-troubleshoot-apps` | 미착수 | OpenTelemetry + Application Insights + KQL |
| 10 | (범위 외 / 포트폴리오 부스터) | 미착수 | `infra/main.bicep` 상위 조립 + GitHub Actions CI |

---

## Phase 4 에서 학습된 함정 (다음 Phase 에 영향 가능)

다음 Phase 작업 시 미리 알고 있으면 좋은 것들. 자세한 본문은 `docs/learning-paths/04-cosmos-db.md` "함정·교훈" 절 참조.

- **`disableLocalAuth=true` 자원의 Portal Data Explorer 접근** — UAMI 만 RBAC 부여하면 사용자 본인은 차단됨. 검증 시 본인 objectId 에 임시 Data Contributor 부여 후 회수. PG 도 Entra-only 가면 동일 패턴 발생 가능.
- **Bicep `for` 식은 `union()` 같은 함수 인자에 직접 못 들어감 (BCP138)** — 변수에 먼저 할당 후 함수 인자로. PG 모듈에도 적용될 패턴.
- **AOAI deployment 동시 PUT 시 409** — 같은 계정에 여러 deployment 만들 때 `dependsOn` 으로 직렬화.
- **`gpt-4o-mini@2024-07-18` 는 koreacentral 에서 GlobalStandard SKU 만** (Standard 미지원) — Phase 5 에서도 AOAI 재호출 시 동일 제약.
- **ACA `AZURE_CLIENT_ID` envVar 미주입 시 DefaultAzureCredential UAMI 식별 실패** — Phase 5 의 PG 토큰 인증에도 동일하게 필요.

---

## 자세한 컨텍스트가 필요할 때 참조

- 9 Phase 로드맵 + 각 Phase DoD: `docs/roadmap.md`
- 각 Phase 의 자세한 내용 (Bicep 인용 / 명령어 / 함정): `docs/learning-paths/0N-*.md`
- 프로젝트 원칙·네이밍·스택: `CLAUDE.md`
- 영속 메모리 (사용자 프로필·피드백): `~/.claude/projects/-Users-krsy0411-Desktop-portfolio-azure-ai-200-certification-challenge/memory/`
- 아키텍처 전체도: `docs/architecture.md`
