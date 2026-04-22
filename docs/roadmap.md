# 9-Phase 단계형 로드맵

엔터프라이즈 RAG 지식 비서를 AI-200의 9개 학습 경로 순서대로 쌓아 올린다. 각 Phase는 **(1) 구현 → (2) 실제 Azure 배포/검증 → (3) 문서 업데이트** 3단계로 구성되며, 세 단계가 모두 끝나야 다음 Phase로 넘어간다.

## 전 Phase 공통 Definition of Done

- [ ] 코드가 로컬에서 동작 (Docker로 실행 가능)
- [ ] **Azure Portal GUI로 배포**되고 엔드포인트가 살아 있음 (브라우저/API 테스트 탭으로 검증) — Phase 1~9 는 CLI/IaC 사용 금지
- [ ] Portal 단계마다 스크린샷을 `docs/learning-paths/screenshots/0N/` 에 추가
- [ ] `docs/learning-paths/0N-*.md` 에 Portal 탐색 경로·필드값·검증 포인트·함정 기록
- [ ] 의미 있는 커밋 메시지 (`feat(phase-N): ...`)
- [ ] 사용자 리뷰 요청 후 승인 → 다음 Phase 착수

---

## Phase 1 — 컨테이너 호스팅 기초

**대응 경로**: `implement-container-app-hosting-azure`
**목표**: FastAPI + Next.js를 컨테이너로 빌드 → ACR에 푸시 → Azure App Service(컨테이너) 로 1차 배포해 기본 경로 검증.

- FastAPI 헬로 엔드포인트(`/healthz`, `/api/chat` stub)
- Next.js 최소 챗 UI (API 호출 연결)
- 멀티스테이지 Dockerfile 2종
- ACR 생성 → `az acr build` 또는 `docker push`
- Azure App Service에 컨테이너 이미지로 배포 + 환경 변수 주입

**산출물**: `apps/api/Dockerfile`, `apps/web/Dockerfile`, `docs/learning-paths/01-container-hosting.md`

---

## Phase 2 — ACA 배포·리비전·스케일링

**대응 경로**: `deploy-manage-apps-azure-container-apps`
**목표**: App Service → **ACA로 이관**. 이후 모든 서비스의 기본 호스팅이 ACA가 된다.

- ACA Environment(Log Analytics 포함) 생성
- api/web 컨테이너 앱 2개 배포, Managed Identity 연결
- readiness/liveness 프로브, 리비전 라벨 기반 블루/그린
- HTTP/CPU 스케일 규칙, KEDA 스칼라 1개 실험

**산출물**: `infra/aca/*.bicep`(초안), `docs/learning-paths/02-container-apps.md`

---

## Phase 3 — AKS 보조 워크로드

**대응 경로**: `deploy-monitor-apps-azure-kubernetes-service`
**목표**: **백그라운드 임베딩 재처리 워커**를 별도 AKS 클러스터에 배포해 AKS 경로를 자연스럽게 커버.

- AKS 클러스터 + ACR 통합(Managed Identity 기반 pull)
- 워커 Deployment/Service 매니페스트 + ConfigMap/Secret/PVC
- Container Insights 활성화, 문제 해결 시나리오 문서화

**산출물**: `apps/worker/`, `infra/aks/*.yaml`, `docs/learning-paths/03-aks.md`

---

## Phase 4 — Cosmos DB: 문서 + 벡터 저장

**대응 경로**: `develop-ai-solutions-azure-cosmos-db`
**목표**: 업로드된 문서 메타데이터·청크·임베딩을 Cosmos DB에 저장하고 RAG 검색을 `VectorDistance` 로 수행.

- 리소스 모델: workspace / document / chunk
- azure-cosmos SDK CRUD + SQL 쿼리
- 벡터 인덱스·하이브리드 검색(메타데이터 필터 + 벡터 거리)
- 변경 피드로 임베딩 동기화

**산출물**: `apps/api/src/stores/cosmos_store.py`, `docs/learning-paths/04-cosmos-db.md`

---

## Phase 5 — PostgreSQL pgvector 비교 실험

**대응 경로**: `develop-ai-solutions-azure-database-postgresql`
**목표**: 동일 데이터셋을 PostgreSQL + pgvector에도 저장해 **Cosmos vs PG 벡터 검색 성능 비교** 문서 작성. Entra 인증 + 연결 풀링.

- PostgreSQL Flexible Server + pgvector 확장
- HNSW vs IVFFlat 인덱스 비교
- psycopg + Entra ID 토큰 인증

**산출물**: `apps/api/src/stores/pg_store.py`, `docs/learning-paths/05-postgresql.md`

---

## Phase 6 — Managed Redis 시맨틱 캐시 + Streams

**대응 경로**: `enhance-ai-solutions-azure-managed-redis`
**목표**: LLM 응답 시맨틱 캐시, 업로드 이벤트 Pub/Sub 알림, 비동기 작업 Streams 큐.

- RediSearch 벡터 인덱스로 시맨틱 캐시
- Pub/Sub: 챗 세션 업데이트 브로드캐스트
- Streams: 임베딩 재처리 작업 전달

**산출물**: `apps/api/src/caches/redis_semantic.py`, `docs/learning-paths/06-managed-redis.md`

---

## Phase 7 — Service Bus / Event Grid / Functions

**대응 경로**: `integrate-backend-services-ai-solutions`
**목표**: 문서 업로드/추론 파이프라인을 이벤트 기반으로 리팩터링.

- Blob 업로드 → Event Grid → Azure Function이 추론 큐(Service Bus) 에 메시지 등록
- AKS 워커 또는 Functions 컨슈머가 큐에서 꺼내 임베딩 수행
- 데드레터 큐 + 재시도 정책

**산출물**: `apps/functions/`, `docs/learning-paths/07-backend-services.md`

---

## Phase 8 — Key Vault + App Configuration

**대응 경로**: `manage-app-secrets-configuration`
**목표**: `.env` 제거, 관리형 ID + Key Vault + App Configuration 체제로 이관.

- Cosmos·PG·Redis·AOAI·Service Bus 연결 문자열을 Key Vault로
- App Configuration: feature flags(예: `enable_semantic_cache`) + Key Vault 참조
- 로컬 개발은 `DefaultAzureCredential` 사용

**산출물**: `apps/api/src/config/`, `docs/learning-paths/08-secrets-config.md`

---

## Phase 9 — OpenTelemetry + Monitor + KQL

**대응 경로**: `observe-troubleshoot-apps`
**목표**: 엔드-투-엔드 분산 추적 + 맞춤 KQL 대시보드 + 경고.

- OpenTelemetry로 FastAPI · Next.js · AKS 워커 · Functions 계측
- Application Insights로 내보내기, RAG 파이프라인에 커스텀 span(토큰 수, cache hit/miss)
- KQL 기반 `workbook` 2종 + 경고 규칙 (오류율·지연·예산)

**산출물**: `docs/learning-paths/09-observability.md`, `docs/dashboards/`

---

## Phase 10 — 수동 Portal 배포 → CLI → Bicep IaC 이전

**대응 경로**: (AI-200 범위 밖 · 포트폴리오 완성도 부스터)
**목표**: Phase 1~9 에서 **Azure Portal 로 수동 구축한 모든 리소스**를, 먼저 `az` CLI 명령어 시퀀스로 재현한 뒤, 그 위에 Bicep 모듈을 얹어 "수동 → 스크립트 → 선언형 IaC" 라는 3단 스토리를 완결한다.

- **10-A**: 각 Phase 별 Portal 작업을 `az` CLI 블록으로 재작성 (`docs/learning-paths/10-iac-migration.md`)
- **10-B**: CLI → Bicep 모듈화 (리소스 그룹 단위 `infra/modules/*.bicep` + `main.bicep` 조립)
- **10-C**: `bicep what-if` → `az deployment group create` 로 Phase 1~9 전체 재배포 가능 검증
- **10-D**: GitHub Actions workflow 로 CI 자동화(선택)

**Why:** 자격증 교육 자료로서 "Portal vs 코드" 대비가 강력한 학습 포인트. 또한 실무 관점에서 "재현 가능성"을 입증.

**산출물**: `docs/learning-paths/10-iac-migration.md`, `infra/modules/*.bicep`, `infra/main.bicep`, `infra/envs/dev.bicepparam`
