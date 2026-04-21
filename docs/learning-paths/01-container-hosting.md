# Phase 1 — Azure에서 컨테이너 애플리케이션 호스팅 구현

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/implement-container-app-hosting-azure/ (2 모듈)

## 학습 경로 구성

1. **Azure Container Registry에서 컨테이너 저장 및 관리**
   - ACR 레지스트리 계층 · 이미지 태깅 전략
   - ACR Tasks 로 클라우드 빌드 (`az acr build`)
   - 신뢰할 수 있는 배포를 위한 이미지 버전 관리
2. **Azure App Service에 컨테이너 배포**
   - 사용자 지정 컨테이너 원본
   - 런타임 포트 · 시작 명령 · 영구 스토리지
   - 애플리케이션 설정으로 환경별 구성 외부화
   - 진단 로그 · 컨테이너 로그 스트리밍

## 이 프로젝트에서의 적용

- FastAPI(`apps/api`) + Next.js(`apps/web`) 2개의 멀티스테이지 Dockerfile
- ACR 하나(예: `acrai200challenge<고유접미사>`)에 두 이미지 푸시(`api:0.1.0`, `web:0.1.0`)
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
- [ ] ACR 업로드 → App Service 배포 — **`az login` 후 아래 명령어 실행**

## 배포 명령어 (로컬에서 실행)

변수 정의:

```bash
SUB_ID="<구독 ID>"
LOCATION="koreacentral"
RG="rg-ai200challenge-dev"
ACR="acrai200challengedev$(openssl rand -hex 2)"   # 전역 유니크
ASP="asp-ai200challenge-dev"                        # App Service Plan
APP_API="app-ai200challenge-api-dev"
APP_WEB="app-ai200challenge-web-dev"
TAG="0.1.0"
```

### 1. 로그인 · 리소스 그룹 · ACR

```bash
az login
az account set --subscription "$SUB_ID"
az group create -n "$RG" -l "$LOCATION"
az acr create -n "$ACR" -g "$RG" --sku Basic --admin-enabled false
```

### 2. ACR Tasks 로 클라우드 빌드 · 푸시

```bash
az acr build -r "$ACR" -t "api:$TAG" apps/api
az acr build -r "$ACR" -t "web:$TAG" apps/web
```

### 3. App Service Plan + 웹앱(컨테이너) 2개

```bash
az appservice plan create -n "$ASP" -g "$RG" --is-linux --sku B1

# api 앱
az webapp create -n "$APP_API" -g "$RG" --plan "$ASP" \
  --container-image-name "$ACR.azurecr.io/api:$TAG"

# ACR pull 권한: 시스템 관리형 ID 사용
az webapp identity assign -n "$APP_API" -g "$RG"
API_PRINCIPAL=$(az webapp identity show -n "$APP_API" -g "$RG" --query principalId -o tsv)
ACR_ID=$(az acr show -n "$ACR" --query id -o tsv)
az role assignment create --assignee "$API_PRINCIPAL" --role AcrPull --scope "$ACR_ID"
az webapp config set -n "$APP_API" -g "$RG" --generic-configurations \
  '{"acrUseManagedIdentityCreds": true}'

# 포트 8000 노출 (FastAPI 기본)
az webapp config appsettings set -n "$APP_API" -g "$RG" \
  --settings WEBSITES_PORT=8000

# web 앱 (동일 패턴)
az webapp create -n "$APP_WEB" -g "$RG" --plan "$ASP" \
  --container-image-name "$ACR.azurecr.io/web:$TAG"
az webapp identity assign -n "$APP_WEB" -g "$RG"
WEB_PRINCIPAL=$(az webapp identity show -n "$APP_WEB" -g "$RG" --query principalId -o tsv)
az role assignment create --assignee "$WEB_PRINCIPAL" --role AcrPull --scope "$ACR_ID"
az webapp config set -n "$APP_WEB" -g "$RG" --generic-configurations \
  '{"acrUseManagedIdentityCreds": true}'
az webapp config appsettings set -n "$APP_WEB" -g "$RG" \
  --settings WEBSITES_PORT=3000 \
            API_BASE_URL="https://$APP_API.azurewebsites.net"
```

### 4. 스모크 테스트

```bash
curl -s https://$APP_API.azurewebsites.net/healthz
curl -X POST https://$APP_API.azurewebsites.net/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"Azure 배포 테스트"}'
# 브라우저: https://$APP_WEB.azurewebsites.net
```

## 함정 · 교훈 (배포 진행 중 업데이트)

- (TBD — 실제 배포 시 기록)

## 체크리스트

- [x] `apps/api/Dockerfile` 멀티스테이지 작성 (uv 기반)
- [x] `apps/web/Dockerfile` 멀티스테이지 작성 (Next.js standalone)
- [x] FastAPI 로컬 smoke test 성공
- [x] Next.js 타입 체크 · 프로덕션 빌드 성공
- [ ] `docker compose build` + `docker compose up` — 로컬 엔드투엔드
- [ ] ACR 생성 + 이미지 2종 푸시
- [ ] App Service 2 개 배포 + 관리형 ID ACR pull
- [ ] web → api 프록시 호출 성공(브라우저 검증)
- [ ] 이 문서 "함정 · 교훈"에 실제 삽질 기록
