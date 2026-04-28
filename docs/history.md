# 작업 히스토리 — Claude Code 세션 컨텍스트

> **이 문서의 역할**: 컴퓨터를 자주 끄고 켜는 환경에서 Claude Code 대화 컨텍스트가 날아가도, 새 대화를 시작할 때 이 문서를 먼저 읽으면 즉시 작업을 이어갈 수 있도록 하는 **living document**.
>
> **갱신 규칙** (CLAUDE.md §8 와 일치):
> - 사용자 명시 요청 ("히스토리 갱신", "지금까지 정리해", "history 기록", "맥락 저장" 등) 시에만 갱신
> - 작업 도중 Claude 가 자동으로 갱신하지 않음
> - 갱신은 commit 을 별도로 동반하지 않음 (사용자가 push 시점 결정)
> - 자세한 함정·명령어·코드 인용은 `docs/learning-paths/0N-*.md` 에 두고 여기서는 짧게 포인터만

마지막 갱신: **2026-04-28** — Phase 5 Claude 책임 작업 완료, 사용자 배포·검증·측정 단계로 진입 대기.

---

## 현재 위치

- **마지막 완료 Phase**: **Phase 4** (Cosmos NoSQL 벡터 검색 + AOAI)
- **진행 중 Phase**: **Phase 5** — 코드·Bicep 작성 끝, **사용자 실배포·검증 대기**
- **마지막 commit**: `3ee6dc9 docs(rules): docs/history.md 컨텍스트 영속화 규칙 추가 + 초기 history 작성` (origin 미푸시)
- **uncommitted 변경** (Phase 5 산출물 + 신규 지침):
  - 새 Bicep: `infra/modules/postgres-{flexible-server,database,firewall-rule,aad-admin,server-config}.bicep`, `infra/phases/05-postgresql/{main.bicep,main.bicepparam}`
  - 새 앱 파일: `apps/api/src/stores/pg_store.py`, `apps/api/src/stores/pg_bootstrap.sql`
  - 수정: `apps/api/pyproject.toml` (psycopg/pgvector 추가), `apps/api/src/main.py` (lifespan PgStore + v0.5.0), `apps/api/src/routers/index_search.py` (?store=cosmos|pg, ?index_kind=hnsw|ivf), `apps/api/src/stores/cosmos_store.py` (lint), `CLAUDE.md` (§2 신설 — 공식 학습 경로 정독 의무화, 기존 §2~§7 → §3~§8), `docs/history.md` (§7→§8 정정), `docs/learning-paths/05-postgresql.md` (전면 리라이트)
  - `bicep build` 경고 없음, `ruff check` / `py_compile` 통과
- **Azure RG (`rg-ai200challenge-dev`) 잔여 리소스**:
  - Phase 1: `acrai200challengedev04` (이미지: `api:0.1.0`, `api:0.4.0`, `web:0.1.0`)
  - Phase 2: `id-ai200challenge-aca-dev`, `law-...`, `cae-...`, `ca-...-api-dev`, `ca-...-web-dev`
  - Phase 3: `id-ai200challenge-aks-dev`, `aks-ai200challenge-dev`, `MSCI-koreacentral-aks-...`
  - Phase 4: 이전에 정리 완료. 같은 이름 (`cosmos-...-dev04`, `aoai-...-dev04`) 으로 재배포 가능
  - **Phase 5 자원은 아직 미배포** — 배포 시 `pg-ai200challenge-dev05` 생성 예정

---

## 다음 액션 — 사용자 책임 (배포·검증)

순서:

1. **(선택) 지금까지의 변경 commit** — Phase 5 코드/문서 + 지침 §2.
2. **`uv sync`** — `cd apps/api && uv sync` (psycopg/psycopg-pool/pgvector 설치).
3. **이미지 빌드·푸시** — 0.5.0 태그.
   ```bash
   az acr login --name acrai200challengedev04
   docker build --platform linux/amd64 \
     -t acrai200challengedev04.azurecr.io/api:0.5.0 apps/api
   docker push acrai200challengedev04.azurecr.io/api:0.5.0
   ```
4. **`main.bicepparam` 의 `devClientIpAddress` 갱신** — `curl -s https://api.ipify.org` 결과로 교체.
5. **Phase 4 자원 재배포** (Phase 5 가 existing 참조하므로 cosmos / aoai 가 살아 있어야 함). Phase 4 main.bicep + bicepparam 으로 `az deployment group create` 한 번.
6. **what-if → 배포** — `az deployment group what-if/create -f infra/phases/05-postgresql/main.bicep -p .../main.bicepparam`.
7. **검증** — `docs/learning-paths/05-postgresql.md` "검증 시나리오" 그대로:
   - 본인 objectId 임시 admin 부여 → psql Entra 접속 → `\dx vector`, `\dt chunks_*` → 회수
   - ACA api ingress 임시 external → `?store=pg`, `?index_kind=hnsw|ivf`, `?store=cosmos` 비교 → internal 회수
8. **측정 표 + 함정 절 채움** (`docs/learning-paths/05-postgresql.md`).
9. **Phase 5 마무리 → Phase 6 (Managed Redis) 진입 결정**.

> ⚠ Phase 5 main.bicep 은 Phase 4 자원을 `existing` 참조한다. Phase 4 가 정리된 현 상태에서는 5 단계 (Phase 4 재배포) 를 먼저 해야 6 단계가 통과한다.

---

## Phase 진행 요약 표

| Phase | 학습 경로 | 상태 | 핵심 산출물 / 메모 |
|---|---|---|---|
| 1 | `implement-container-app-hosting-azure` | ✅ | App Service + ACR + Dockerfile 2종. App Service/ASP 만 정리, ACR 보존 |
| 2 | `deploy-manage-apps-azure-container-apps` | ✅ | ACA Env + api(internal)/web(external) + 공용 UAMI ACR pull |
| 3 | `deploy-monitor-apps-azure-kubernetes-service` | ✅ | AKS + Container Insights (DCR/DCRA IaC) + worker manifest |
| 4 | `develop-ai-solutions-azure-cosmos-db` | ✅ | Cosmos NoSQL Serverless + Vector(`quantizedFlat`) + AAD-only / AOAI(gpt-4o-mini + text-embedding-3-large). 검증 후 정리, 재배포 가능 |
| 5 | `develop-ai-solutions-azure-database-postgresql` | 🟡 코드 완료, 배포·검증 대기 | PG 16 / B1ms / Entra-only / `halfvec(3072)` / `chunks_hnsw` + `chunks_ivf` 두 테이블 / 내장 PgBouncer + psycopg_pool 이중 풀링. Cosmos 와 응답 키 일치 |
| 6 | `enhance-ai-solutions-azure-managed-redis` | 미착수 | 시맨틱 캐시 + Pub/Sub + Streams |
| 7 | `integrate-backend-services-ai-solutions` | 미착수 | Service Bus / Event Grid / Functions. **변경 피드 자동 임베딩이 여기로 이관됨** |
| 8 | `manage-app-secrets-configuration` | 미착수 | Key Vault + App Configuration. `.env` 제거 |
| 9 | `observe-troubleshoot-apps` | 미착수 | OpenTelemetry + Application Insights + KQL |
| 10 | (범위 외 / 포트폴리오 부스터) | 미착수 | `infra/main.bicep` 상위 조립 + GitHub Actions CI |

---

## Phase 5 결정 (반영 완료, 배포 후 검증)

이번 Phase 의 핵심 4가지 결정 — 코드/Bicep 에 이미 반영. 공식 학습 경로 정독 후 사용자 동의로 확정.

- **벡터 타입**: `halfvec(3072)` (`vector(3072)` 는 인덱스 한계 2000-d 초과)
- **Phase 4 동시 가동**: existing 참조 패턴 (Phase 5 main.bicep 에서 cosmos / aoai 재호출 X)
- **인증**: Entra-only (`passwordAuth=Disabled`), AAD admin = UAMI 단독, 사용자 본인은 검증 시 임시 부여→회수
- **인덱스 비교**: `chunks_hnsw` (m=16, ef_construction=64) / `chunks_ivf` (lists=100) 두 테이블 분리 적재
- **연결 최적화**: 내장 PgBouncer (`pgbouncer.enabled=true`, port 6432) + 클라이언트 측 `psycopg_pool` 이중 풀링

---

## Phase 4 에서 학습된 함정 (Phase 5 에도 영향)

자세한 본문: `docs/learning-paths/04-cosmos-db.md` "함정·교훈".

- **`disableLocalAuth=true` 자원의 Portal/psql 접근** — UAMI 만 RBAC 부여하면 사용자 본인은 차단. 검증 시 본인 objectId 에 임시 admin 부여 후 회수. **Phase 5 PG 도 동일 패턴**.
- **Bicep `for` 식은 `union()` 인자에 직접 못 들어감 (BCP138)** — 변수에 먼저 할당 후 함수 인자로.
- **AOAI deployment 동시 PUT 시 409** — `dependsOn` 으로 직렬화.
- **`gpt-4o-mini@2024-07-18` 는 koreacentral 에서 GlobalStandard SKU 만**.
- **ACA `AZURE_CLIENT_ID` envVar 미주입 시 DefaultAzureCredential UAMI 식별 실패** — Phase 5 PG 토큰 인증에도 동일하게 필요.

---

## 자세한 컨텍스트가 필요할 때 참조

- 9 Phase 로드맵 + 각 Phase DoD: `docs/roadmap.md`
- 각 Phase 의 자세한 내용 (Bicep 인용 / 명령어 / 함정): `docs/learning-paths/0N-*.md`
- 프로젝트 원칙·네이밍·스택·작업 원칙 §1~§8: `CLAUDE.md`
- 영속 메모리 (사용자 프로필·피드백): `~/.claude/projects/-Users-krsy0411-Desktop-portfolio-azure-ai-200-certification-challenge/memory/`
- 아키텍처 전체도: `docs/architecture.md`
