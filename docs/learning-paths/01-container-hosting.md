# Phase 1 — Azure에서 컨테이너 애플리케이션 호스팅 구현

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/implement-container-app-hosting-azure/ (2 모듈)

## 학습 경로 구성

1. **Azure Container Registry에서 컨테이너 저장 및 관리**
   - ACR 레지스트리 계층 · 이미지 태깅 전략
   - ACR Tasks 로 클라우드 빌드 (Portal에서 Git 연동)
   - 신뢰할 수 있는 배포를 위한 이미지 버전 관리
2. **Azure App Service에 컨테이너 배포**
   - 사용자 지정 컨테이너 원본
   - 런타임 포트 · 시작 명령 · 영구 스토리지
   - 애플리케이션 설정으로 환경별 구성 외부화
   - 진단 로그 · 컨테이너 로그 스트리밍

## 이 프로젝트에서의 적용

- FastAPI(`apps/api`) + Next.js(`apps/web`) 2개의 멀티스테이지 Dockerfile
- ACR 하나(예: `acrai200challengedevXX`)에 두 이미지 푸시(`api:0.1.0`, `web:0.1.0`)
- Azure App Service 웹앱 2개로 먼저 배포해 **이미지가 정상 기동되는지 검증** → Phase 2에서 ACA로 이관

## 구현 스냅샷

| 컴포넌트 | 기술 | 엔드포인트/경로 |
|---|---|---|
| `apps/api` | FastAPI 0.136 + uv | `GET /healthz`, `POST /api/chat` |
| `apps/web` | Next.js 15.1 + React 19 | `GET /`, `POST /api/chat` (프록시) |
| `docker-compose.yml` | api + web 로컬 오케스트레이션 | api:8000, web:3000 |

## 로컬 검증 결과 (2026-04-22 기준)

- [x] `uv sync` 성공 — 29 패키지 설치
- [x] `python -c "from src.main import app"` — 라우트 등록 확인
  ```
  ['/openapi.json', '/docs', '/docs/oauth2-redirect', '/redoc', '/healthz', '/api/chat']
  ```
- [x] `npm install` 성공, `npx tsc --noEmit` 오류 없음
- [x] `npm run build` — 홈(static) + `/api/chat`(dynamic) 번들링 성공
- [x] uvicorn 로컬 실행 후 스모크 테스트
  - `GET /healthz` → `{"status":"ok"}`
  - `POST /api/chat {"message":"hello"}` → `{"reply":"[stub] hello","model":"stub"}`
  - `POST /api/chat {"message":""}` → 422 (Pydantic `min_length=1` 검증)
  - `POST /api/chat {}` → 422 (`message` 필드 필수)
- [ ] `docker compose build` — **사용자 Docker Desktop 기동 후 실행 필요**
- [ ] ACR 업로드 → App Service 배포 — **아래 Portal 가이드 따라 진행**

---

## Portal 배포 가이드

> Phase 1 은 **Azure Portal GUI 전용**입니다. 모든 단계는 브라우저에서 Portal(https://portal.azure.com) 을 통해 진행하고, 각 단계 마지막에 스크린샷을 `docs/learning-paths/screenshots/01/` 아래 지정된 파일명으로 저장합니다. `az` CLI / `kubectl` / Bicep 으로 동일한 작업을 재현하는 방법은 [Phase 10](10-iac-migration.md) 에 정리됩니다.

### 공통 준비물

- Azure 구독 로그인 (소유자 또는 기여자 권한)
- 기본 리전: **Korea Central** (`koreacentral`)
- 공통 태그: `project=ai200challenge`, `env=dev`, `phase=1`
- ACR 이름용 2자리 고유 접미사 1개 정해두기 (예: `7k`) — 이후 단계 전부 동일하게 재사용

### 단계 1 — 리소스 그룹 생성

**목적**: 이 Phase 에서 만드는 모든 리소스를 담을 논리적 컨테이너. Phase 별로 한 개의 리소스 그룹 `rg-ai200challenge-dev` 를 공유한다.

1. Portal → 상단 검색 "Resource groups" → **+ Create**
2. **Basics** 탭:
   - Subscription: 사용 중인 구독
   - Resource group: `rg-ai200challenge-dev`
   - Region: `Korea Central`
3. **Tags** 탭:
   - `project=ai200challenge`
   - `env=dev`
4. **Review + create** → **Create**

> **[스크린샷]** `screenshots/01/01-rg-create.png` — Basics 탭 필드값 전체
> **[스크린샷]** `screenshots/01/02-rg-overview.png` — 생성 완료 후 Overview 화면

**검증**: Resource groups 목록에서 `rg-ai200challenge-dev` 가 Korea Central 리전으로 보이면 OK.

---

### 단계 2 — Azure Container Registry(ACR) 생성

**목적**: 두 개의 컨테이너 이미지(`api`, `web`)를 저장할 프라이빗 레지스트리. Phase 2 이후 ACA/AKS 도 이 ACR 을 공유한다.

1. Portal → 상단 검색 "Container registries" → **+ Create**
2. **Basics** 탭:
   - Subscription: 동일 구독
   - Resource group: `rg-ai200challenge-dev`
   - Registry name: `acrai200challengedev<2자리 고유접미사>` (소문자·영숫자만, 5~50자, 전역 유니크)
   - Location: `Korea Central`
   - Pricing plan: **Basic** (학습용 최저가)
3. **Networking** 탭: Public access 기본값 유지 (Phase 8 에서 프라이빗 엔드포인트 연결 예정)
4. **Encryption** 탭: 기본값 (Microsoft-managed keys)
5. **Identity** 탭: 건너뜀 (사용처에서 Managed Identity 로 pull)
6. **Tags** 탭: 공통 태그 + `tier=shared`
7. **Review + create** → **Create**

> **[스크린샷]** `screenshots/01/03-acr-create-basics.png` — Basics 탭
> **[스크린샷]** `screenshots/01/04-acr-overview.png` — 배포 완료 후 ACR Overview (Login server 표시)

**검증**: 리소스 그룹 내 ACR 리소스 클릭 → Overview 에 `acrai200challengedev<...>.azurecr.io` 형태의 Login server 가 표시되면 OK.

---

### 단계 3 — ACR Tasks 로 이미지 빌드 (Git 연동)

**목적**: 로컬 Docker 없이 ACR 이 GitHub 레포지토리를 직접 클론해 이미지를 빌드·푸시. 교육 자료에 "Portal 만으로 이미지 업로드" 플로우를 남기기 위함.

> 전제: 본 레포가 GitHub 에 푸시되어 있어야 한다. ACR → Services → **Tasks** 에서 "Quick task"(`Run now`) 또는 "Tasks(반복)" 중 선택. Phase 1 에서는 **Quick task** 두 번으로 진행.

1. ACR 리소스 → 왼쪽 메뉴 **Services** → **Tasks** → 상단 **Quick task** (또는 `Run now`)
2. API 이미지 빌드 (첫 번째 실행):
   - Source location type: **GitHub** (최초 1회 OAuth 연결 필요)
   - Repository: 이 레포
   - Branch: `main`
   - Dockerfile path: `apps/api/Dockerfile`
   - Image name and tag: `api:0.1.0`
   - Context path: `apps/api`
   - Platform: `linux` / `amd64`
   - **Run**
3. 실행 로그가 실시간 스트리밍됨. `Successfully pushed ...` 출력 후 **Succeeded** 상태 확인.
4. 동일 절차로 두 번째 실행(Web 이미지):
   - Dockerfile path: `apps/web/Dockerfile`
   - Context path: `apps/web`
   - Image name and tag: `web:0.1.0`

> **[스크린샷]** `screenshots/01/05-acr-task-api-form.png` — API Quick task 입력 폼
> **[스크린샷]** `screenshots/01/06-acr-task-api-log.png` — 빌드 성공 로그 tail
> **[스크린샷]** `screenshots/01/07-acr-task-web-form.png` — Web Quick task 입력 폼
> **[스크린샷]** `screenshots/01/08-acr-repositories.png` — Services → **Repositories** 에 `api`, `web` 두 개 저장소와 `0.1.0` 태그 확인

**검증**: ACR → Services → **Repositories** 에 `api`, `web` 두 개가 생기고 각 태그에 `0.1.0` 이 존재하면 OK.

**함정**:
- GitHub OAuth 연결은 Azure 계정 당 최초 1회만. 거부되면 Azure DevOps 또는 **Upload context**(로컬 zip 업로드) 로 우회 가능.
- 빌드가 OOM 으로 실패하면 Platform 을 `linux/amd64` 로 강제하거나, Agent pool 을 기본(Standard) 유지 — Basic SKU 는 agent pool 커스터마이징 불가.

---

### 단계 4 — App Service Plan 생성

**목적**: 두 웹앱(api, web)이 공유할 Linux 기반 App Service Plan.

1. Portal → "App Service plans" → **+ Create**
2. **Basics** 탭:
   - Resource group: `rg-ai200challenge-dev`
   - Name: `asp-ai200challenge-dev`
   - Operating System: **Linux**
   - Region: `Korea Central`
   - Pricing plan: **Basic B1** (학습용. P0V3 이상이면 Always On 기본 켜짐이지만 비용↑)
3. **Tags** 탭: 공통 태그
4. **Review + create** → **Create**

> **[스크린샷]** `screenshots/01/09-asp-create.png` — App Service Plan Basics 탭

**검증**: 생성된 플랜의 OS 가 Linux, SKU 가 B1 으로 표시.

---

### 단계 5 — App Service (API 컨테이너) 생성

**목적**: FastAPI 이미지를 서비스하는 웹앱 1번.

1. Portal → "App Services" → **+ Create** → **Web App**
2. **Basics** 탭:
   - Resource group: `rg-ai200challenge-dev`
   - Name: `app-ai200challenge-api-dev` (전역 유니크, 필요시 접미사 추가)
   - Publish: **Container**
   - Operating System: **Linux**
   - Region: `Korea Central`
   - Linux Plan: `asp-ai200challenge-dev` (방금 만든 것 선택)
3. **Container** 탭:
   - Image Source: **Azure Container Registry**
   - Registry: `acrai200challengedev<고유접미사>`
   - Image: `api`
   - Tag: `0.1.0`
   - Startup command: 비워둠 (Dockerfile `CMD` 사용)
4. **Deployment** 탭: 기본값
5. **Networking** 탭: Public access On (Phase 8 에서 축소)
6. **Monitoring** 탭: Application Insights **Disable** (Phase 9 에서 연결)
7. **Tags**: 공통 + `component=api`
8. **Review + create** → **Create**

> **[스크린샷]** `screenshots/01/10-app-api-basics.png` — Basics 탭
> **[스크린샷]** `screenshots/01/11-app-api-container.png` — Container 탭 (ACR/이미지/태그)

**검증**: 배포 완료 후 Overview 의 Default domain (`app-ai200challenge-api-dev.azurewebsites.net`) 이 노출되고, Status 가 Running.

---

### 단계 6 — API 앱에 Managed Identity + AcrPull 권한

**목적**: 키 없이 ACR 이미지를 pull 하도록, 시스템 할당 관리형 ID에 AcrPull 역할을 부여.

1. API 앱 → 왼쪽 메뉴 **Settings** → **Identity** → **System assigned** 탭
2. Status: **On** → **Save** → 확인 프롬프트에서 Yes
3. 저장 후 표시된 **Object (principal) ID** 복사 (혹시 나중에 필요).
4. 하단 **Azure role assignments** 버튼 → **+ Add role assignment**:
   - Scope: **Resource**
   - Subscription: 동일 구독
   - Resource: `acrai200challengedev<고유접미사>`
   - Role: **AcrPull**
   - **Save**
5. API 앱 → **Settings** → **Configuration** (또는 Environment variables) → **General settings** (포털 최신 UI 에서는 `Deployment` 탭 하위) → **Admin Credentials** / **Use managed identity for pulling images**: **On** → **Save** → 앱 재시작

> **[스크린샷]** `screenshots/01/12-app-api-identity-on.png` — System assigned On 상태
> **[스크린샷]** `screenshots/01/13-app-api-acrpull-role.png` — AcrPull role assignment 확인
> **[스크린샷]** `screenshots/01/14-app-api-mi-pull-toggle.png` — Use managed identity for pulling images 토글 On

**검증**: API 앱 → **Deployment Center** → **Logs** 에서 이미지 pull 성공 로그 확인. 또는 **Log stream** 에 컨테이너 부팅 로그.

**함정**: 역할 할당이 전파되는 데 1~3분 걸릴 수 있음. "Unauthorized" 가 나오면 앱을 **Restart** 한 번 해주면 반영.

---

### 단계 7 — API 앱 환경 변수 · 포트 설정

**목적**: FastAPI 는 기본 8000 포트로 listen. App Service 에 `WEBSITES_PORT` 를 8000 으로 지정해야 리버스 프록시가 정확히 라우팅.

1. API 앱 → **Settings** → **Environment variables** (구 UI 의 **Configuration** → **Application settings**)
2. **+ Add** 로 다음 키/값 추가:
   - `WEBSITES_PORT` = `8000`
3. **Apply** → 앱 자동 재시작 확인

> **[스크린샷]** `screenshots/01/15-app-api-env-websites-port.png` — Environment variables 목록에 `WEBSITES_PORT=8000`

**검증**: **Log stream** 에 `Uvicorn running on http://0.0.0.0:8000` 출력.

---

### 단계 8 — App Service (Web 컨테이너) 생성

**목적**: Next.js 이미지를 서비스하는 웹앱 2번. 단계 5 와 동일 패턴.

1. Portal → "App Services" → **+ Create** → **Web App**
2. **Basics**:
   - Name: `app-ai200challenge-web-dev`
   - Publish: **Container** / OS: Linux / Plan: `asp-ai200challenge-dev`
3. **Container**:
   - Image Source: **Azure Container Registry**
   - Image: `web` / Tag: `0.1.0`
4. **Tags**: 공통 + `component=web`
5. **Review + create** → **Create**

> **[스크린샷]** `screenshots/01/16-app-web-basics.png` — Basics 탭
> **[스크린샷]** `screenshots/01/17-app-web-container.png` — Container 탭

---

### 단계 9 — Web 앱 Managed Identity + AcrPull + 환경 변수

**목적**: 단계 6~7 과 동일 작업을 `app-ai200challenge-web-dev` 에 반복. Next.js standalone 은 기본 3000 포트. 추가로 API 주소를 환경 변수로 주입.

1. **Identity** → System assigned **On** → Save
2. **Azure role assignments** → ACR 에 **AcrPull** 할당
3. **Deployment** → Use managed identity for pulling images **On**
4. **Environment variables** → **+ Add**:
   - `WEBSITES_PORT` = `3000`
   - `API_BASE_URL` = `https://app-ai200challenge-api-dev.azurewebsites.net`
5. **Apply** → 재시작 확인

> **[스크린샷]** `screenshots/01/18-app-web-identity-on.png` — System assigned On
> **[스크린샷]** `screenshots/01/19-app-web-acrpull-role.png` — AcrPull role
> **[스크린샷]** `screenshots/01/20-app-web-envvars.png` — 환경 변수 2개 (`WEBSITES_PORT`, `API_BASE_URL`)

**검증**: Web 앱 Log stream 에 `Next.js ... ready on http://0.0.0.0:3000` 출력.

---

### 단계 10 — 엔드-투-엔드 스모크 테스트 (브라우저)

**목적**: Portal 외부에서 두 앱이 실제로 HTTP 응답을 내는지 확인. Phase 1 종료 기준.

1. 새 탭: `https://app-ai200challenge-api-dev.azurewebsites.net/healthz`
   - 기대: `{"status":"ok"}`
2. 새 탭: `https://app-ai200challenge-api-dev.azurewebsites.net/docs`
   - 기대: Swagger UI 에 `/healthz`, `/api/chat` 두 엔드포인트 노출
3. Swagger UI 에서 `POST /api/chat` → **Try it out** → `{"message":"Azure 배포 테스트"}` 실행
   - 기대: 200 응답, `{"reply":"[stub] Azure 배포 테스트","model":"stub"}`
4. 새 탭: `https://app-ai200challenge-web-dev.azurewebsites.net`
   - 기대: Next.js 챗 UI 로드, 메시지 입력 시 API 프록시를 통해 stub 응답 반환

> **[스크린샷]** `screenshots/01/21-smoke-healthz.png` — `/healthz` 브라우저 응답
> **[스크린샷]** `screenshots/01/22-smoke-swagger-chat.png` — Swagger 에서 `/api/chat` 200 응답
> **[스크린샷]** `screenshots/01/23-smoke-web-ui.png` — Web 앱 UI 에서 챗 왕복 성공

**검증**: 세 스크린샷이 모두 성공이면 Phase 1 DoD 충족.

---

## 함정 · 교훈 (배포 진행 중 업데이트)

- (TBD — 실제 배포 시 기록)

## 체크리스트

- [x] `apps/api/Dockerfile` 멀티스테이지 작성 (uv 기반)
- [x] `apps/web/Dockerfile` 멀티스테이지 작성 (Next.js standalone)
- [x] FastAPI 로컬 smoke test 성공
- [x] Next.js 타입 체크 · 프로덕션 빌드 성공
- [ ] `docker compose build` + `docker compose up` — 로컬 엔드투엔드
- [ ] Portal 단계 1~4 완료 (RG + ACR + 이미지 2개 빌드 + App Service Plan)
- [ ] Portal 단계 5~9 완료 (App Service 2개 + Managed Identity + 환경 변수)
- [ ] Portal 단계 10 스모크 테스트 3종 성공
- [ ] 스크린샷 23장 `screenshots/01/` 에 저장
- [ ] 이 문서 "함정 · 교훈" 섹션에 실제 삽질 기록
