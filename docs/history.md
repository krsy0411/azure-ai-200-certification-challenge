# 작업 히스토리 — Claude Code 세션 컨텍스트

> **이 문서의 역할**: 컴퓨터를 자주 끄고 켜는 환경에서 Claude Code 대화 컨텍스트가 날아가도, 새 대화를 시작할 때 이 문서를 먼저 읽으면 즉시 작업을 이어갈 수 있도록 하는 **living document**.
>
> **갱신 규칙** (CLAUDE.md §9 와 일치):
> - 사용자 명시 요청 ("히스토리 갱신", "지금까지 정리해", "history 기록", "맥락 저장" 등) 시에만 갱신
> - 작업 도중 Claude 가 자동으로 갱신하지 않음
> - 갱신은 commit 을 별도로 동반하지 않음 (사용자가 push 시점 결정)
> - 자세한 함정·명령어·코드 인용은 `docs/learning-paths/0N-*.md` 에 두고 여기서는 짧게 포인터만

마지막 갱신: **2026-05-19** — Phase 7 완전 종료 + Phase 8 **단계 1·2 완료** + **CLAUDE.md §7 자원 라이프사이클 룰 갱신** (Phase 7 실측 비용 7일 108,569 KRW 기반, Redis Memory_M10 dominant 75%). 보존 목록 축소 — *무료/사실상-무료 자원만 보존*, compute 자원 (ACA / AKS 포함) 은 모두 정리.

---

## 현재 위치

- **마지막 완료 Phase**: **Phase 7** (Service Bus / Event Grid / Functions / App Insights) — 정리까지 완료, 함정 7개 학습
- **진행 중 Phase**: **Phase 8** (Key Vault + App Configuration) — 단계 1·2 완료 (학습 경로 정독 + 결정 13개 승인 + plan 기록), **단계 3 (구현) 진입 직전**
- **마지막 commit**: `374875c docs(history): Phase 6 완전 종료 + Phase 7 진입 대기 반영` (origin 미푸시, +14 commits 누적 — Phase 7·8 작업 트리 모두 미커밋)
- **Phase 7·8 작업 트리 (커밋 안 됨)**:
  - Phase 7 산출물: Bicep 모듈 11개 (service-bus / event-grid / function-app-flex / storage / application-insights / role-assignment 5개) + `infra/phases/07-backend-services/{main.bicep,main.bicepparam}` + `apps/functions/` (function_app.py + clients/ 5개 + pyproject + host.json + requirements.txt) + `docs/learning-paths/07-backend-services.md` (전면 리라이트 + 측정 + 함정 7개)
  - Phase 8 산출물 (이번 갱신): `docs/learning-paths/08-secrets-config.md` (전면 리라이트 — 16 단원 표 + 결정 13개 A 조합 + 분류 결정 4축 + 아키텍처 + Bicep 모듈 10개 예정 + 검증 시나리오 6종 + 함정 TBD), `docs/history.md` (이 갱신)
- **Azure RG (`rg-ai200challenge-dev`) 현재 자원** (Phase 7 cleanup 후):
  - **(2026-05-18 룰 갱신 전 보존된)** 9개: `acrai200challengedev04`, `id-...-aca-dev`, `id-...-aks-dev`, `law-...`, `cae-...`, `ca-...-api-dev`, `ca-...-web-dev`, `aks-...`, `MSCI-koreacentral-aks-...`
  - **§7 갱신 후 정리 대상으로 분류된 자원** (idle 비용 누적): `ca-...-api-dev` (~1,743 KRW/일), `ca-...-web-dev` (~동일), `aks-...` + `MC_...` RG (~1,125 KRW/일) — Phase 8 본 작업 진입 전 또는 진행 중 정리 권장
  - **신규 룰상 진짜 보존 (5개)**: `acrai200challengedev04` (storage-only), `law-...` (5GB free), `id-...-aca-dev`, `id-...-aks-dev` (UAMI 무료), `cae-...` (Container App 없을 때 무료)
  - Phase 4·5·6·7 데이터 자원은 0건 (이미 Phase 7 cleanup 으로 정리)

---

## 다음 액션 — Phase 8 단계 3 (구현) 부터 재개

`docs/learning-paths/08-secrets-config.md` 의 결정 표·Bicep 모듈 목록·앱 코드 변경 가이드가 단계 3 진입의 *완전한 청사진*. 다음 순서로 재개:

### Step 0 — 사전 조건 확인

Phase 8 은 데이터 자원 (Phase 4·5·6·7) 의존성 없음 → **재배포 불필요**. 현재 RG 의 공통 자원 9개만으로 충분.

### Step 1 — Phase 8 Bicep 작성

`docs/learning-paths/08-secrets-config.md` 의 "Bicep 모듈 구성" 표 그대로 (총 10개 모듈):

- `infra/modules/key-vault.bicep` — RBAC mode, soft-delete on, purge protection **off** (§7 라이프사이클 충돌 회피)
- `infra/modules/key-vault-secret.bicep` — 비밀 1건 등록 (다중 호출용)
- `infra/modules/app-configuration.bicep` — standard SKU, `disableLocalAuth=true`
- `infra/modules/app-configuration-keyvalue.bicep` — 일반 key-value (label=dev)
- `infra/modules/app-configuration-feature-flag.bicep` — feature flag 1건 등록
- `infra/modules/app-configuration-keyvault-ref.bicep` — KV reference (`{"uri":"..."}` JSON)
- `infra/modules/role-assignment-keyvault-secrets-user.bicep`
- `infra/modules/role-assignment-appconfig-data-reader.bicep`
- `infra/phases/08-secrets-config/{main.bicep,main.bicepparam}` — 위 모듈 + UAMI/LAW existing 참조

### Step 2 — 앱 코드 변경 (`apps/api/`)

- `apps/api/src/config/azure_config.py` 신설 — App Config provider + sentinel refresh 단일 진입점
- 기존 Phase 4~7 의 `os.environ[...]` 호출을 `cfg("...")` 로 치환
- `pyproject.toml` 에 `azure-appconfiguration-provider` 추가, version `0.8.0`
- `.env` 완전 제거 (결정 12)

### Step 3 — 배포 → `/phase-verify` → GUI → `/phase-cleanup`

표준 워크플로우. 검증 시나리오 6종 (학습 경로 + 본 레포 적용):
1. 자원·권한 (KV RBAC / AC AAD-only / UAMI role 부여)
2. AC 에서 KV 참조 자동 resolution (`{"uri":"..."}` 형식)
3. `/admin/config` 엔드포인트 — AC 로드 결과 + 마스킹된 KV 값
4. **학습용 비밀 회전 시뮬레이션** — KV `external-stub-api-key` 새 버전 → api 인식 latency 측정 (결정 3 의 학습 가치 실증)
5. 기능 플래그 토글 — `enable_semantic_cache` off + sentinel bump → 30s 후 분기 변경 확인
6. `.env` 완전 제거 확인 (`find apps -name ".env*"` 빈 결과)

### 사전 결정 확정 사항 (재개 시 그대로 사용)

- **결정 13개 모두 A 조합** — Azure RBAC / standard SKU / 학습용 샘플 비밀 등록 / standard AC / public+RBAC 네트워크 / 단일 load() / sentinel refresh / dev·prod 레이블 / 기능 플래그 3개 / 환경변수 모두 AC 이관 / **App Insights connection string → KV** / `.env` 완전 제거 / 공통 자원만 (재배포 X)
- **결정 3·11 의 학습 가치** — 본 레포 §1~§7 Entra-only 라 진짜 비밀 부재 → 학습용 샘플 비밀 (`external-stub-api-key` / `webhook-signing-secret` 등) + App Insights connection string 을 *의도적으로* KV 에 넣어 학습 경로의 4축 분류 + 회전·캐싱 시나리오 실증
- **분류 결정 (모듈 2 단원 5 의 4축)** — AC 10개 항목 (모든 endpoint·deployment name·flag) + KV 4개 항목 (App Insights connection + 학습용 샘플 3개) — docs 의 "분류 결정" 절 참조
- **purge protection off** — §7 의 phase 라이프사이클 (같은 이름 재배포) 과 KV 의 purge protection (보존 기간 강제) 이 직접 충돌, dev 환경이라 보안 우선순위 낮음

---

## 새 세션 시작 시 검증 체크리스트

Claude Code 를 재시작하거나 새 대화로 옮길 때, 4-layer 시스템이 정상 인식되는지 다음 순서로 확인. **Phase 6·7 에서 실운용 검증 통과 완료** — 시스템 자체는 정상 작동 확인됨.

### 1. CLAUDE.md / docs/history.md 자동 로드 확인
- 새 대화 첫 응답에서 Claude 가 §10 워크플로우 룰을 인지하고 있는지
- `docs/history.md` 의 "마지막 갱신: **2026-05-19**" 와 "Phase 8 단계 3 진입 직전" 컨텍스트 복원하는지

### 2. Skill 5개 인식 확인
- `phase-start` / `phase-verify` / `phase-cleanup` / `commit` 모두 `disable-model-invocation: true`
- `/phase-start 9` 또는 `/commit` 명시 호출 시 SKILL.md body 가 컨텍스트에 들어와야

### 3. Hook 작동 확인 (Phase 6·7 에서 검증됨)
- PostToolUse `python-lint.sh` — ruff E501 / I001 즉시 차단
- PreToolUse `block-az-delete.sh` — `/phase-cleanup` 의 `.claude/cleanup-approved` 마커로만 통과

### 4. phase-learning-fetcher subagent
- Phase 8 정독 round-trip 성공 — 2 모듈 × 8 단원 = 16 단원 표 + 결정 7개 핵심 + 본 레포 적용 검토 형식으로 반환됨

---

## Phase 진행 요약 표

| Phase | 학습 경로 | 상태 | 핵심 산출물 / 메모 |
|---|---|---|---|
| 1 | `implement-container-app-hosting-azure` | ✅ | App Service + ACR + Dockerfile 2종 |
| 2 | `deploy-manage-apps-azure-container-apps` | ✅ | ACA Env + api(internal)/web(external) + 공용 UAMI |
| 3 | `deploy-monitor-apps-azure-kubernetes-service` | ✅ | AKS + Container Insights (DCR/DCRA IaC) |
| 4 | `develop-ai-solutions-azure-cosmos-db` | ✅ | Cosmos NoSQL Serverless + Vector + AAD-only / AOAI |
| 5 | `develop-ai-solutions-azure-database-postgresql` | ✅ | PG 16 / B1ms / Entra-only / `halfvec(3072)` / 함정 6개 |
| 6 | `enhance-ai-solutions-azure-managed-redis` | ✅ | Memory_M10 + RediSearch + chat.py RAG / 함정 5개 |
| 7 | `integrate-backend-services-ai-solutions` | ✅ | Service Bus / Event Grid / Functions Flex / App Insights / 데이터 파이프라인 1.5s/chunk / **함정 7개** |
| 8 | `manage-app-secrets-configuration` | 🟡 단계 1·2 완료 | Key Vault + App Configuration. `.env` 제거. 결정 13개 A 조합 (분류 4축 + 학습용 샘플 비밀 + App Insights → KV) |
| 9 | `observe-troubleshoot-apps` | 미착수 | OpenTelemetry + KQL + 워크북. 시맨틱 캐시 hit율 / RAG 품질 정식 측정 |
| 10 | (범위 외 / 포트폴리오 부스터) | 미착수 | `infra/main.bicep` 상위 조립 + GitHub Actions CI |

---

## Phase 7 학습 산출물 요약 (자세한 건 `docs/learning-paths/07-backend-services.md`)

**결정 (사용자 승인 A 조합, 검증 후 확정)**:
- Service Bus Standard / 큐 단독 (`inference-queue`) / AAD-only
- Event Grid CloudEvents 1.0 / 사용자 지정 토픽 1개 / AAD-only
- Functions Flex Consumption (koreacentral) / Cosmos DB change feed trigger
- MCP 서버 *생략* / Function App settings 임시 (Phase 8 에서 KV/AC 이관)
- Application Insights 추가 (Phase 7 의 옵션 A — Microsoft Learn 의 "built-in integration" 기준)

**측정 결과** (1 chunk end-to-end):
- queue_to_embed 처리 시간: **1,519 ms** (AOAI embed dominant, Phase 5·6 결론과 일치)
- Cosmos change feed lag: 5~30s
- SB peek-lock + ack: < 1s
- DLQ 손실: 0건

**함정·교훈 (7개)**:
1. UAMI-only mode 의 `identity.principalId` 없음 (Bicep output)
2. Flex Consumption deprecated app settings (`FUNCTIONS_WORKER_RUNTIME` 등)
3. `az functionapp show` 의 properties 비평면화 (Phase 6 Redis 와 반대)
4. Cosmos change feed lease 컨테이너 자동 생성 권한 부재 → Bicep 사전 생성
5. Function App resource log 는 diagnostic setting 명시 필요
6. `azure-identity.aio` 의 `aiohttp` transient dependency
7. App Insights AAD ingest 는 UAMI 에 `Monitoring Metrics Publisher` 필요 → instrumentation key 폴백

---

## Phase 4·5·6·7 에서 학습된 함정 (다음 Phase 에 영향)

자세한 본문: `docs/learning-paths/04-cosmos-db.md` / `05-postgresql.md` / `06-managed-redis.md` / `07-backend-services.md`.

- **`disableLocalAuth=true` / AAD-only 자원의 Portal/CLI 접근** — UAMI 만 RBAC 부여하면 사용자 본인은 차단. Cosmos / PG / AOAI / Redis / Service Bus / Event Grid / KV / AC 모두 동일 패턴.
- **AAD 인증 username 의 자원별 차이**: Redis 는 `principalId` (objectId), PG 는 `principalName` (UAMI display name), AOAI 는 토큰 그대로. Phase 8 KV/AC 도 자원별 확인 필수.
- **Bicep `for` 식은 `union()` 인자에 직접 못 들어감 (BCP138)** — 변수에 먼저 할당.
- **AOAI deployment 동시 PUT 시 409** — `dependsOn` 직렬화.
- **ACA `AZURE_CLIENT_ID` envVar 미주입 시 DefaultAzureCredential UAMI 식별 실패**.
- **az CLI 응답의 ARM properties 평면화 (자원별 일관성 부족)** — Redis 는 루트 평면화, Function App 은 properties.* 안. 새 자원은 `az ... show -o json` raw 결과로 키 위치 확인 후 query 작성.
- **azure-identity.aio 의 transient dependency** (`aiohttp`) — `requirements.txt` 에 명시 박아야 함.
- **App Insights AAD ingest** 는 UAMI 에 `Monitoring Metrics Publisher` RBAC 필요 — 안 박으면 instrumentation key 폴백.

---

## 신규 룰 / 워크플로우

- **`/commit` Skill** (Phase 6 추가) — 변경 사항을 의미 단위로 분할 commit
- **CLAUDE.md §7 갱신 (2026-05-18 / Phase 8 세션)** — 보존 목록 축소. 이전: ACR / LAW / UAMI / CAE / AKS / KV / AC / ACA api·web. 이후: ACR / LAW / UAMI / CAE / AI / KV / AC 만 (즉 **AKS + ACA api·web 정리 대상으로 이동**). 근거: Phase 7 실측 비용 함정 8 — ACA min replica 1 ~1,743 KRW/일, AKS LB+IP ~1,125 KRW/일. 자세한 분류 표: CLAUDE.md §7 본문 / `.claude/skills/phase-cleanup/SKILL.md` Step 1.
- **phase-cleanup Skill 갱신** — 새 분류 표 반영.

---

## 자세한 컨텍스트가 필요할 때 참조

- 9 Phase 로드맵 + 각 Phase DoD: `docs/roadmap.md`
- 각 Phase 의 자세한 내용 (Bicep 인용 / 명령어 / 함정): `docs/learning-paths/0N-*.md`
- 프로젝트 원칙·네이밍·스택·작업 원칙 §1~§10: `CLAUDE.md`
- 영속 메모리 (사용자 프로필·피드백): `~/.claude/projects/-Users-krsy0411-Desktop-portfolio-azure-ai-200-certification-challenge/memory/`
- 아키텍처 전체도: `docs/architecture.md`
- Skill 정의: `.claude/skills/{phase-start,phase-verify,phase-cleanup,commit}/SKILL.md`
- Hook 정의: `.claude/hooks/{bicep-build,python-lint,block-az-delete}.sh`
</content>
</invoke>