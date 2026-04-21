# ADR 0001 — 기술 스택 및 프로젝트 범위

- **상태**: Accepted
- **결정일**: 2026-04-21
- **결정자**: 사용자(leesyungg@gmail.com), Claude Code

## 컨텍스트

Microsoft Azure **AI-200** 자격증(Azure AI 클라우드 솔루션 개발)에 대응되는 9개 공식 학습 경로를 하나의 포트폴리오 애플리케이션으로 커버하려는 목표. 자격증 학습과 포트폴리오·블로그 글감 확보를 동시에 달성해야 함.

## 결정

### 애플리케이션 도메인

**엔터프라이즈 RAG 지식 비서**. 9개 학습 경로(컨테이너/ACA/AKS/Cosmos/PostgreSQL/Redis/백엔드 통합/비밀·구성/관찰성)를 가장 자연스럽게 녹일 수 있는 시나리오.

### 기술 스택

- Backend: **Python 3.12 + FastAPI** — MS Learn 샘플 대부분이 Python 기반이라 학습 자료 매핑 비용이 최소.
- Frontend: **Next.js 14+ (App Router) + TypeScript** — 챗 UI/업로드/관리 대시보드를 한 SSR 앱으로.
- LLM: **Azure OpenAI** (gpt-4o-mini + text-embedding-3-large) — 관리형 ID, Key Vault, 자격증 정합.
- Hosting: **ACA 메인 + AKS 보조 워커** — ACA는 자격증의 배포 타깃으로 실제 주력, AKS는 매니페스트 경험용 별도 워크로드 1개.
- Data: **Cosmos DB + PostgreSQL(pgvector) + Managed Redis** 전부 사용 — Phase 4~6에서 순차 통합, Cosmos vs PG 벡터 비교 실험 포함.

### 배포 전략

- 실제 Azure 구독에 배포 검증까지 수행(비용 감수).
- IaC(Bicep)는 Phase 10(옵션)으로 나중에 통합. Phase 1~9에선 `az` CLI 수동 명령어를 문서에 남김.

### 진행 방법론

- **9 Phase 단계형** — 학습 경로와 1:1 매핑. 각 Phase 는 구현 → 실배포 → 문서화 3단계 완료 시 다음으로. Phase 경계에서 사용자 리뷰 필수.

## 대안

1. **단일 호스팅(ACA 전용)**: 간단하지만 AKS 학습 경로 커버 불가 → 기각.
2. **Cosmos 단일 벡터 스토어**: 구현은 쉬우나 PostgreSQL 경로 전체, Redis 벡터 경로를 스킵해야 함 → 기각.
3. **상향식 통합 구축 후 일괄 문서화**: 빠르지만 자격증 학습 연동성이 낮음 → 기각.

## 결과

- 스택·도메인·방법론이 AI-200 9개 경로를 전부 커버하도록 정렬됨.
- 각 Phase 의 산출물이 자격증 학습 노트이자 블로그/포트폴리오 근거가 됨.
- 단점: 데이터 스토어 3종을 모두 다루므로 초기 셋업 오버헤드가 있음. 대신 Phase 단위 점진 도입으로 완화.
