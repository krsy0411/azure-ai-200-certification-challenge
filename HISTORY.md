# HISTORY — 작업 인계용 임시 문서

maintainer 전용. 새 세션이 이어받을 때 먼저 읽는다. 작업 완료 후 삭제.

---

## 완료 (커밋 + origin push 됨)

- **session-00** 사전 설정 Bicep
- **session-01** RAG MVP on ACA (apps/api · apps/web)
- **session-02** PostgreSQL pgvector — VectorStore 프로토콜 + pg_store + seed_both
- **session-03** Managed Redis 시맨틱 캐시 — redis_client/semantic + chain 캐시 통합 (FLAT · redis-entraid · Balanced_B0)
- **session-04** 비동기 인제스션 — Bicep 11모듈 + apps/functions (SB trigger + Cosmos change feed, 양쪽 적재)
- **session-05** App Configuration 피처 플래그 — Bicep 5모듈(Free) + config/loader.py + main 통합 (동적 refresh, enable_semantic_cache 토글)

모두 로컬 검증 통과(az bicep build · ruff · py_compile · import). **실배포는 아직 안 함 (아래 보류).**

---

## 보류 — 실배포 검증 (당분간 어려움)

구독(`4df6af87-...`)이 회사 계정이라 결제·활성화가 당장 어려움. 활성화되면 session-00 부터 순서대로 배포하며 검증. 배포 순서: 00(RG+UAMI+AOAI 필수 선행) → 01(Cosmos) → 02(PG) → 03(Redis) → 04(SB/EG/Func) → 05(App Config). 이름은 uniqueString 접미사라 `az ... list --query "[0].name"` 로 조회.

세션별 확인 함정:
- **02**: PG Entra-only + 자식 자원 직렬화(409) / register_vector chicken-and-egg / ef_search recall
- **03**: Redis Entra 전용 + access policy assignment / FT.SEARCH hash 인덱싱 / cosine distance 환산
- **04**: Flex Consumption 신 스키마 / Storage allowSharedKeyAccess=false 시 Functions 부팅(MI 역할) / Cosmos lease 사전 생성 / EG→SB 는 System Topic 관리 ID에 SB Data Sender
- **05**: 피처 플래그 refresh 4박자(feature_flag_refresh_enabled 누락 주의) / App Config Free 등급 / store 이름 uniqueString

---

## 다음 작업 — session-06 (Observability 심화)

현재 상태: `docs/sessions/06-observability.md` 골격만, Bicep·코드·save-point 미작성.

**착수 전 필수**: 학습 경로 정독(`phase-learning-fetcher`) → 결정 옵션 사용자 승인 → 구현.
- 학습 경로: https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/

대략 범위: 지금까지 자동 계측이 잡던 trace 를 RAG 비즈니스 의미가 담긴 **커스텀 OpenTelemetry span** (`rag.retrieve`·`rag.generate`·`cache.lookup`·토큰 카운트) 으로 격상 + **KQL Workbook** + **Metric Alert** (예: Azure OpenAI 429, 토큰 비용). 신규 `apps/api/src/observability/spans.py`. Bicep: Workbook + Alert rule (Application Insights/Log Analytics 기반, 둘 다 session-00 존재). chain/cache 코드에 span 부여. 참고: session-03 의 cache.lookup span 은 이미 있음 — 일관되게 확장.

**session-00 에서 확립한 패턴 (그대로 따를 것)**:
- start 의 main.bicep 만 모듈 호출을 `// -------- N) ... 모듈 호출하기` anchor 로 비우고 모듈 본체는 완성본 제공. 앱 핵심 로직은 `raise NotImplementedError` + anchor.
- docs 는 "anchor 를 찾아 그 아래에 코드 추가" + 중간 검증(az bicep build · ruff/py_compile) + complete 덮어쓰기 TIP + MS Learn 커버리지 표. **문서 인용 anchor = start 파일 실제 anchor 와 정합**.
- "## 시작본 코드 받기"(bash+PowerShell), 이후 명령은 `workshop/` 안에서 실행 가정.
- save-point: 학습자 fill 파일만 stub, 나머지 scaffolding. 변경/신규 파일만 delta.
- 커밋 분리: 모듈 / main+param / 앱코드 / save-points / docs. 끝줄 `Co-Authored-By: Claude Opus 4.8`.

---

## 환경 / 인프라 메모

- Azure CLI 2.86.0 + Bicep 0.43.8 설치됨. **Bash 툴엔 `az` 없음 → PowerShell 툴에서 전체 경로** `C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd`. 기존 터미널은 PATH 미반영 → 새 터미널/새로고침.
- 앱 의존성: `apps/api` 에서 `uv run ...` (`.venv` gitignore). apps/functions 린트도 `uv run --project apps/api ruff/py_compile`.
- **git push**: origin = `https://krsy0411@github.com/krsy0411/...` (계정 분리 — 이 저장소는 krsy0411, 다른 건 ComentoSyung).
- **함정(common.md 추가 필요)**: 한국어 Windows PowerShell `az bicep build --stdout` 가 em대시를 cp949 로 인코딩하다 크래시(컴파일은 성공). → `$env:PYTHONIOENCODING='utf-8'` 또는 `--outfile`.
- API 버전 메모: Redis `2025-04-01`, Functions Flex `Microsoft.Web/sites@2024-04-01`+FC1, App Configuration `2024-05-01`(피처 플래그 키의 '/'는 `~2F` 이스케이프).
