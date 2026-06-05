# HISTORY — 작업 인계용 임시 문서

maintainer 전용. 새 세션이 이어받을 때 먼저 읽는다. 작업 완료 후 삭제.

---

## 완료 (커밋 + origin push 됨)

- **session-00** 사전 설정 Bicep
- **session-01** RAG MVP on ACA (apps/api · apps/web)
- **session-02** PostgreSQL pgvector — VectorStore 프로토콜 + pg_store + seed_both
- **session-03** Managed Redis 시맨틱 캐시 — redis_client/semantic + chain 캐시 통합
- **session-04** 비동기 인제스션 — Bicep 11모듈 + apps/functions (SB trigger + Cosmos change feed)
- **session-05** App Configuration 피처 플래그 — Bicep 5모듈(Free) + config/loader.py (동적 refresh)
- **session-06** Observability 심화 — Bicep 3모듈(Log Search Alert·Workbook·Action Group) + observability/spans.py (커스텀 span + OTEL Counter 메트릭) + chain/aoai/main 통합

모두 로컬 검증 통과(az bicep build · ruff · py_compile · import). **실배포는 아직 안 함 (아래 보류).**

남은 세션: **session-07 (AKS 대안 배포)** 1개. 그 외 README/architecture/pitfalls/cleanup 등 문서는 작성됨.

---

## 보류 — 실배포 검증 (당분간 어려움)

구독(`4df6af87-...`)이 회사 계정이라 결제·활성화가 당장 어려움. 활성화되면 session-00 부터 순서대로 배포·검증. 배포 순서: 00(RG+UAMI+AOAI 필수 선행) → 01(Cosmos·ACA) → 02(PG) → 03(Redis) → 04(SB/EG/Func) → 05(App Config) → 06(Workbook/Alert). 이름은 uniqueString 접미사라 `az ... list --query "[0].name"` 로 조회.

세션별 확인 함정:
- **02**: PG Entra-only + 자식 자원 직렬화(409) / register_vector chicken-and-egg / ef_search recall
- **03**: Redis Entra 전용 + access policy assignment / FT.SEARCH hash 인덱싱 / cosine distance 환산
- **04**: Flex Consumption 신 스키마 / Storage allowSharedKeyAccess=false 시 Functions 부팅(MI 역할) / Cosmos lease 사전 생성 / EG→SB 는 System Topic 관리 ID에 SB Data Sender
- **05**: 피처 플래그 refresh 4박자(feature_flag_refresh_enabled) / App Config Free / store 이름 uniqueString
- **06**: 커스텀 메트릭은 OTEL Counter 라야 customMetrics 에 노출 / Log Search Alert(scheduledQueryRules) / Workbook ARM JSON 임베드 / 커스텀 루트 span 만들지 않음(자동 request span 자식)

---

## 다음 작업 — session-07 (Azure Kubernetes Service 대안 배포)

현재 상태: `docs/sessions/07-aks.md` 골격만, Bicep·매니페스트·save-point 미작성. **워크샵 마지막 세션.**

**착수 전 필수**: 학습 경로 정독(`phase-learning-fetcher`) → 결정 옵션 사용자 승인 → 구현.
- 학습 경로: https://learn.microsoft.com/ko-kr/training/paths/deploy-monitor-apps-azure-kubernetes-service/

대략 범위: 같은 RAG 워크로드를 ACA 대신 AKS 로 배포해 두 호스팅 모델 트레이드오프 비교. K8s 매니페스트(Deployment/Service/Workload Identity) + `kubectl` + Container Insights. 신규 `apps/worker`(또는 기존 api 이미지 재사용) + `infra/sessions/07-aks/` Bicep. 알려진 함정(common.md): AKS DCR+DCRA 명시 선언(addonProfiles.omsagent 단독 동작 안 함), Workload Identity(UAMI federated credential). CLAUDE.md §7: AKS 는 LB+IP idle 비용 → 학습 후 정리, MC_ RG 자동 생성.

**session-00 에서 확립한 패턴 (그대로 따를 것)**:
- start 의 main.bicep 만 모듈 호출을 anchor 로 비우고 모듈 본체는 완성본 제공. 앱/매니페스트 핵심은 stub + anchor.
- docs: anchor 채우기 + 중간 검증(az bicep build · kubectl) + complete 덮어쓰기 TIP + MS Learn 커버리지 표. 문서 인용 anchor = start 파일과 정합.
- "## 시작본 코드 받기"(bash+PowerShell), 명령은 `workshop/` 안 실행 가정.
- save-point: 학습자 fill 파일만 stub, 나머지 scaffolding, delta 만 담음.
- 커밋 분리: 모듈 / main+param / 매니페스트·앱 / save-points / docs (+ HISTORY 사용자 요청 시). 끝줄 `Co-Authored-By: Claude Opus 4.8`.

---

## 환경 / 인프라 메모

- Azure CLI 2.86.0 + Bicep 0.43.8. **Bash 툴엔 `az` 없음 → PowerShell 툴 전체 경로** `C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd`. (kubectl 도 필요 시 설치 확인)
- 앱: `apps/api` 에서 `uv run ...` (`.venv` gitignore). 린트도 `uv run --project apps/api ruff/py_compile`.
- **git push**: origin = `https://krsy0411@github.com/krsy0411/...` (계정 분리 — 이 저장소 krsy0411).
- **함정(common.md 추가 필요)**: 한국어 Windows PowerShell `az bicep build --stdout` em대시 cp949 크래시 → `$env:PYTHONIOENCODING='utf-8'` 또는 `--outfile`.
- API 버전: Redis `2025-04-01`, Functions Flex `Microsoft.Web/sites@2024-04-01`+FC1, App Config `2024-05-01`(피처 플래그 키 '/'는 `~2F`), Monitor `scheduledQueryRules@2023-03-15-preview`·`workbooks@2023-06-01`·`actionGroups@2023-01-01`.