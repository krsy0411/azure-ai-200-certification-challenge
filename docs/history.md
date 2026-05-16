# 작업 히스토리 — Claude Code 세션 컨텍스트

> **이 문서의 역할**: 컴퓨터를 자주 끄고 켜는 환경에서 Claude Code 대화 컨텍스트가 날아가도, 새 대화를 시작할 때 이 문서를 먼저 읽으면 즉시 작업을 이어갈 수 있도록 하는 **living document**.
>
> **갱신 규칙** (CLAUDE.md §9 와 일치):
> - 사용자 명시 요청 ("히스토리 갱신", "지금까지 정리해", "history 기록", "맥락 저장" 등) 시에만 갱신
> - 작업 도중 Claude 가 자동으로 갱신하지 않음
> - 갱신은 commit 을 별도로 동반하지 않음 (사용자가 push 시점 결정)
> - 자세한 함정·명령어·코드 인용은 `docs/learning-paths/0N-*.md` 에 두고 여기서는 짧게 포인터만

마지막 갱신: **2026-05-16** — Phase 6 완전 종료 (구현·검증·정리), Phase 7 진입 대기. **4-layer 워크플로우 시스템 첫 실운용 검증 통과** + `/commit` Skill 신규 추가 (5번째 Skill).

---

## 현재 위치

- **마지막 완료 Phase**: **Phase 6** (Azure Managed Redis — 시맨틱 캐시 + pub/sub + Streams 학습용 + chat.py RAG 화) — 한 세션에 구현·검증·정리까지 완전 종료
- **다음 진입 Phase**: **Phase 7** (Service Bus / Event Grid / Functions — 변경 피드 자동 임베딩 이관)
- **마지막 commit**: `0751135 docs(rules): CLAUDE.md §10 — Phase 진행 7-단계 워크플로우 (Skills 진입점)` (origin 미푸시, **+9 commits 누적**)
- **Phase 6 작업 트리 (커밋 안 됨, `/commit` 대기 중)**:
  - 신규 Bicep: `infra/modules/redis-{enterprise,enterprise-database,access-policy-assignment}.bicep`, `infra/phases/06-managed-redis/{main.bicep,main.bicepparam}`
  - 신규 앱 코드: `apps/api/src/cache/{redis_client.py,semantic.py}`, `apps/api/src/messaging/{pubsub.py,streams.py}`
  - 수정: `apps/api/pyproject.toml` (redis[hiredis] / numpy 추가, v0.6.3), `apps/api/src/main.py` (lifespan RedisClient + SemanticCache + PubSub), `apps/api/src/routers/chat.py` (전면 RAG 화 — 시맨틱 캐시 → PG vector_search → AOAI 답변), `docs/learning-paths/06-managed-redis.md` (전면 리라이트 + 실측 + 함정 5개), `docs/history.md` (이 갱신)
  - 신규 Skill: `.claude/skills/commit/SKILL.md`
- **Azure RG (`rg-ai200challenge-dev`) 잔여 자원** (Phase 6 정리 후 9개 공통 자원만):
  - Phase 1: `acrai200challengedev04` (이미지: `api:0.1.0`, `0.4.0`, `0.5.0`, `0.5.1`, `0.6.0`, `0.6.1`, `0.6.2`, `0.6.3`, `web:0.1.0`)
  - Phase 2: `id-ai200challenge-aca-dev`, `law-...`, `cae-...`, `ca-...-api-dev`, `ca-...-web-dev`
  - Phase 3: `id-ai200challenge-aks-dev`, `aks-...`, `MSCI-koreacentral-aks-...`
  - **Phase 4·5·6 데이터 자원 모두 정리 완료** — Cosmos / AOAI (purge 까지) / PG / Redis (soft-delete 7일 충돌 시 접미사 ↑)
  - ⚠ ACA api 컨테이너는 PG/Cosmos/AOAI/Redis 사라져 다시 unhealthy 상태 — Phase 7 진입 시 필요한 데이터 자원 재배포로 회복

---

## 다음 액션 — Phase 7 진입

CLAUDE.md §10 의 7-단계 워크플로우대로:

1. **(선택)** `/commit` 슬래시 커맨드 — Phase 6 작업 트리 commit (의미 단위 분할). Phase 7 진입 전 정리해두면 깨끗.
2. **`/phase-start 7`** — phase-learning-fetcher subagent 가 `integrate-backend-services-ai-solutions` 학습 경로 정독, 결정 옵션 표 제시 후 사용자 승인 대기.
3. 사용자 승인 후 구현. Phase 4·5·6 의 데이터 자원 중 어떤 것을 `existing` 참조하는지 정독 결과로 결정.
4. 배포 → `/phase-verify` → 사용자 GUI 검증 → `/phase-cleanup`.

### Phase 7 진입 전 고려해야 할 결정 (정독 후 확정)

- **변경 피드 자동 임베딩 흐름** (Phase 4·5 에서 이관됨): Cosmos change feed → Service Bus → Function App → AOAI embed → PG/Redis 갱신
- **Service Bus vs Phase 6 의 Redis Streams 역할 분리**: Phase 6 docs 에서 "메인 큐는 Phase 7 의 Service Bus" 로 명시. Streams 는 학습 산출물로만 잔존.
- **재배포 필요 자원** (현재 모두 정리됨): 최소한 Cosmos (change feed source) + AOAI (embed) + PG (chunks 적재 대상) 가 필요할 가능성. Redis 는 Phase 7 에서 필수 아닐 수도.

---

## 새 세션 시작 시 검증 체크리스트

Claude Code 를 재시작하거나 새 대화로 옮길 때, 4-layer 시스템이 정상 인식되는지 다음 순서로 확인. **Phase 6 에서 실운용 검증 통과 완료** — 시스템 자체는 정상 작동 확인됨.

### 1. CLAUDE.md / docs/history.md 자동 로드 확인
- 새 대화 첫 응답에서 Claude 가 §10 워크플로우 룰을 인지하고 있는지
- `docs/history.md` 의 "마지막 갱신: **2026-05-16**" 와 "Phase 7 진입 대기" 컨텍스트 복원하는지

### 2. Skill 5개 인식 확인
- `phase-start` / `phase-verify` / `phase-cleanup` / `commit` 모두 `disable-model-invocation: true` — 자동 invoke X
- `/phase-start 7` 또는 `/commit` 명시 호출 시 SKILL.md body 가 컨텍스트에 들어와야

### 3. Hook 작동 확인 (Phase 6 에서 검증됨)
- PostToolUse `python-lint.sh` — Phase 6 진행 중 ruff E501 2회 즉시 차단 (정상)
- PreToolUse `block-az-delete.sh` — `/phase-cleanup` 의 `.claude/cleanup-approved` 마커로 통과, 마커 없으면 `az ... delete` 차단

### 4. phase-learning-fetcher subagent
- Phase 6 정독 round-trip 성공 — 3 모듈 × 7 단원 = 21 단원 표 + 결정 6개 + 본 레포 적용 검토 형식으로 반환됨

---

## Phase 진행 요약 표

| Phase | 학습 경로 | 상태 | 핵심 산출물 / 메모 |
|---|---|---|---|
| 1 | `implement-container-app-hosting-azure` | ✅ | App Service + ACR + Dockerfile 2종. App Service/ASP 만 정리, ACR 보존 |
| 2 | `deploy-manage-apps-azure-container-apps` | ✅ | ACA Env + api(internal)/web(external) + 공용 UAMI ACR pull |
| 3 | `deploy-monitor-apps-azure-kubernetes-service` | ✅ | AKS + Container Insights (DCR/DCRA IaC) + worker manifest |
| 4 | `develop-ai-solutions-azure-cosmos-db` | ✅ | Cosmos NoSQL Serverless + Vector(`quantizedFlat`) + AAD-only / AOAI(gpt-4o-mini + text-embedding-3-large). 정리 완료, 재배포 가능 |
| 5 | `develop-ai-solutions-azure-database-postgresql` | ✅ | PG 16 / B1ms / Entra-only / `halfvec(3072)` / `chunks_hnsw` + `chunks_ivf` / **PgBouncer 의도적 생략**. 함정 6개. 정리 완료 |
| 6 | `enhance-ai-solutions-azure-managed-redis` | ✅ | Memory_M10 + RediSearch + AAD-only / `idx:semantic` (HNSW+FLOAT32+3072+COSINE) / chat.py RAG (PG L2 + Redis L1) / pub/sub + Streams 학습용 / **함정 5개**. 정리 완료 |
| 7 | `integrate-backend-services-ai-solutions` | 🟡 진입 대기 | Service Bus / Event Grid / Functions. **변경 피드 자동 임베딩**, Streams 메인 큐 이관 |
| 8 | `manage-app-secrets-configuration` | 미착수 | Key Vault + App Configuration. `.env` 제거 |
| 9 | `observe-troubleshoot-apps` | 미착수 | OpenTelemetry + Application Insights + KQL. **시맨틱 캐시 hit률 / RAG 품질 정식 측정도 여기로** |
| 10 | (범위 외 / 포트폴리오 부스터) | 미착수 | `infra/main.bicep` 상위 조립 + GitHub Actions CI |

---

## Phase 6 학습 산출물 요약 (자세한 건 `docs/learning-paths/06-managed-redis.md`)

**결정 (사용자 승인 A 조합, 검증 후 확정)**:
- 계층: **MemoryOptimized_M10** (학습 경로 dev/test 권장, RediSearch 포함)
- 인증: AAD-only — `accessKeysAuthentication=Disabled`, UAMI 에 `default` access policy
- 시맨틱 캐시 인덱스: **HNSW + FLOAT32 + DIM 3072 + COSINE + HASH** (학습 경로 "텍스트 검색(대형)" 권장)
- 메인 RAG retrieval: **PG `chunks_hnsw` (Phase 5 산출물) + Redis L1 시맨틱 캐시**
- pub/sub = 알림 fanout / Streams = 학습용 1개 큐. **메인 큐는 Phase 7 Service Bus 로 이관**
- chat.py RAG 화 — 시맨틱 캐시 lookup → PG vector_search → AOAI 답변 → cache store + pub/sub publish

**측정 결과** (5건 chunks, api 0.6.3 검증):
- 첫 캐시 hit (sim=1.0, 동일 질문): 1.50s — 임베딩 호출만 발생, AOAI chat / PG 검색 skip
- 캐시 miss + PG retrieval + AOAI 생성: 1.5~1.6s — AOAI 호출이 dominant (Phase 5 결론과 동일)
- workspace 격리 (다른 ws, 같은 Q): TAG filter 정상 작동
- paraphrase miss — threshold 0.92 가 한국어 paraphrase 까지 흡수하기엔 보수적. 향후 `REDIS_SEMANTIC_THRESHOLD` 튜닝 항목

**함정·교훈 (5개)** — Phase 6 의 fix 사이클 0.6.0 → 0.6.1 → 0.6.2 → 0.6.3 모두 함정으로 인한 것:
1. **RediSearch 활성 database 는 evictionPolicy='NoEviction' 강제** — Bicep what-if 단계에서 차단. 학습 경로 본문 밖. TTL 정리는 키별 EXPIRE 로
2. **redis-py 5.x `ConnectionPool` 은 `ssl` kwarg 미지원** — TLS 는 `connection_class=SSLConnection` 으로
3. **Azure Managed Redis AAD 인증 username = principal objectId** (`'default'` 가 아님). UAMI 의 경우 `clientId` 가 아니라 **`principalId`** — 두 UUID 가 다름
4. **RediSearch TAG 값의 하이픈/특수문자는 `\` escape 필수** — `ws-test` 가 `Syntax error` 로 lookup 매번 실패. **디버깅 우선순위 함정** — Exception 흡수돼 정상 miss 로 보임
5. **az CLI `redisenterprise` 응답은 ARM properties 평면화** — `--query "properties.hostName"` 이 아니라 `--query "hostName"`

---

## 신규 룰 / 워크플로우 (Phase 6 세션에서 추가)

- **`/commit` Skill 신규** — 변경 사항을 의미 단위로 분할 commit. 본 레포의 commit 컨벤션 (`<type>(<scope>): <한국어 메시지>`) 강제. `disable-model-invocation: true`. CLAUDE.md "커밋 규칙" 의 자동 강제 도구. `.claude/skills/commit/SKILL.md` 참조.

> 신규 룰 자체는 없음 (CLAUDE.md §1~§10 유지). Phase 6 검증을 통해 **4-layer 워크플로우 시스템 실운용 검증 통과** 가 가장 큰 성과.

---

## Phase 4·5·6 에서 학습된 함정 (다음 Phase 에 영향)

자세한 본문: `docs/learning-paths/04-cosmos-db.md` / `05-postgresql.md` / `06-managed-redis.md`.

- **`disableLocalAuth=true` / AAD-only 자원의 Portal/CLI 접근** — UAMI 만 RBAC 부여하면 사용자 본인은 차단. Cosmos / PG / AOAI / Redis 모두 동일 패턴.
- **AAD 인증 username 의 자원별 차이**: Redis 는 `principalId` (objectId), PG 는 `principalName` (UAMI display name), AOAI 는 토큰 그대로. Phase 7 Service Bus / Functions 도 자원별 확인 필수.
- **Bicep `for` 식은 `union()` 인자에 직접 못 들어감 (BCP138)** — 변수에 먼저 할당.
- **AOAI deployment 동시 PUT 시 409** — `dependsOn` 직렬화.
- **`gpt-4o-mini@2024-07-18` 는 koreacentral 에서 GlobalStandard SKU 만**.
- **ACA `AZURE_CLIENT_ID` envVar 미주입 시 DefaultAzureCredential UAMI 식별 실패**.
- **server config 의 sub-parameter 순서 의존** — Bicep `items()` 알파벳 정렬로 PUT 순서가 뒤집힘.
- **PostgreSQL Flexible Server 는 Failed deployment 후 ServerIsBusy 가 자주 — 60s grace** 필요.
- **az CLI 응답의 ARM properties 평면화** (Phase 6 발견) — `redisenterprise show` 등 일부 자원의 properties.* 가 루트로 펼쳐짐. JMESPath 쿼리 작성 시 주의.

---

## 자세한 컨텍스트가 필요할 때 참조

- 9 Phase 로드맵 + 각 Phase DoD: `docs/roadmap.md`
- 각 Phase 의 자세한 내용 (Bicep 인용 / 명령어 / 함정): `docs/learning-paths/0N-*.md`
- 프로젝트 원칙·네이밍·스택·작업 원칙 §1~§10: `CLAUDE.md`
- 영속 메모리 (사용자 프로필·피드백): `~/.claude/projects/-Users-krsy0411-Desktop-portfolio-azure-ai-200-certification-challenge/memory/`
- 아키텍처 전체도: `docs/architecture.md`
- Skill 정의: `.claude/skills/{phase-start,phase-verify,phase-cleanup,commit}/SKILL.md`
- Hook 정의: `.claude/hooks/{bicep-build,python-lint,block-az-delete}.sh`
