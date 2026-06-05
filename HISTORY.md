# HISTORY — 작업 인계용 임시 문서

maintainer 전용. 새 세션이 이어받을 때 먼저 읽는다. 작업 완료 후 삭제.

---

## 완료 (커밋 + origin push 됨) — 7개 세션 전부 작성 완료

- **session-00** 사전 설정 Bicep
- **session-01** RAG MVP on ACA (apps/api · apps/web)
- **session-02** PostgreSQL pgvector — VectorStore 프로토콜 + pg_store + seed_both
- **session-03** Managed Redis 시맨틱 캐시 — redis_client/semantic + chain 통합
- **session-04** 비동기 인제스션 — Bicep 11모듈 + apps/functions
- **session-05** App Configuration 피처 플래그 — config/loader.py (동적 refresh)
- **session-06** Observability — observability/spans.py (커스텀 span + OTEL 메트릭) + Workbook/Alert
- **session-07** AKS 대안 배포 — Bicep 7모듈 + K8s 매니페스트(Deployment+Service, Workload Identity) — apps/api 이미지 재사용

각 세션 산출물: docs(조립 walkthrough) + Bicep(모듈+main+param) + save-points(start/complete) + (해당 시 앱 코드). 모두 로컬 검증 통과(az bicep build · ruff · py_compile · import). 그 외 README/PREREQUISITES/architecture/pitfalls/cleanup/_style 문서 작성됨.

**→ 워크샵 콘텐츠 작성은 사실상 완료.** 남은 것은 ① 실배포 E2E 검증, ② (검증 후) 사용자 지시 시 HISTORY.md 삭제.

---

## 남은 일 — 실배포 E2E 검증 (구독 활성화 후)

구독(`4df6af87-...`)이 회사 계정이라 결제·활성화가 당장 어려움. 활성화되면 session-00 부터 순서대로 배포·검증:

배포 순서: 00(RG+UAMI+AOAI) → 01(Cosmos·ACR·ACA) → 02(PG) → 03(Redis) → 04(SB/EG/Func) → 05(App Config) → 06(Workbook/Alert) → 07(AKS). 이름은 uniqueString 접미사라 `az ... list --query "[0].name"` 로 조회.

세션별 핵심 함정 (배포 시 집중 확인):
- **02**: PG Entra-only + 자식 자원 직렬화(409) / register_vector chicken-and-egg / ef_search recall
- **03**: Redis Entra 전용 + access policy / FT.SEARCH hash 인덱싱 / cosine distance 환산
- **04**: Flex Consumption 신 스키마 / Storage allowSharedKeyAccess=false 부팅 / Cosmos lease 사전 생성 / EG→SB 는 System Topic 관리 ID에 SB Data Sender
- **05**: 피처 플래그 refresh 4박자 / App Config Free / store 이름 uniqueString
- **06**: 커스텀 메트릭은 OTEL Counter / Log Search Alert / Workbook ARM JSON / 커스텀 루트 span 금지
- **07**: custom kubelet identity → cp도 UserAssigned / Container Insights DCR+DCRA / DSv5 할당량 0(DSv3 사용) / disableLocalAccounts→Cluster User Role / Workload Identity subject 일치(매니페스트 SA = federated subject) / 매니페스트 placeholder(__ACR_LOGIN_SERVER__ 등) sed 치환 후 kubectl apply

검증 후 docs 의 "함정·교훈" 보강 + (선택) common.md 에 cp949 함정 추가.

---

## 환경 / 인프라 메모

- Azure CLI 2.86.0 + Bicep 0.43.8. **Bash 툴엔 `az` 없음 → PowerShell 툴 전체 경로** `C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd`. kubectl 은 session-07 검증 시 필요(설치 확인).
- 앱: `apps/api` 에서 `uv run ...` (`.venv` gitignore). 린트 `uv run --project apps/api ruff/py_compile`.
- **git push**: origin = `https://krsy0411@github.com/krsy0411/...` (계정 분리 — 이 저장소 krsy0411).
- **함정(common.md 추가 필요)**: 한국어 Windows PowerShell `az bicep build --stdout` em대시 cp949 크래시 → `$env:PYTHONIOENCODING='utf-8'` 또는 `--outfile`.
- 자원 라이프사이클(§7): 검증 후 정리 — PG·Redis·Cosmos·AOAI·SB/EG/Func/Storage·ACA·**AKS(LB+IP idle)**. 보존 — LAW·App Insights·ACR·UAMI·CAE·Key Vault·App Config(Free).
- API 버전: Redis `2025-04-01`, Functions Flex `Web/sites@2024-04-01`+FC1, App Config `2024-05-01`(피처 플래그 키 '/'→`~2F`), Monitor(`scheduledQueryRules@2023-03-15-preview`·`workbooks@2023-06-01`·`dataCollectionRules@2023-03-11`), AKS `managedClusters@2024-09-01`.