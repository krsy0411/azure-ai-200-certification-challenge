# Phase 10 — 수동 Portal 배포 → CLI → Bicep IaC 이전

**대응 경로**: (AI-200 범위 밖 · 포트폴리오 완성도 부스터)

Phase 1~9 에서 **Azure Portal GUI 로 수동 구축한 모든 리소스**를,
먼저 `az` CLI 명령어 시퀀스로 재현한 뒤, 그 위에 Bicep 모듈을 얹어
"**수동 → 스크립트 → 선언형 IaC**" 3단 스토리를 완결한다.

## 진행 방식

| 서브 페이즈 | 산출물 | 검증 |
|---|---|---|
| **10-A** CLI 재현 | 각 Phase별 `## Phase N — CLI 재현` 섹션 (이 문서) | Portal 로 생성한 리소스를 삭제 → 동일 이름으로 CLI로 재배포 → 스모크 테스트 통과 |
| **10-B** Bicep 모듈화 | `infra/modules/*.bicep` + `infra/main.bicep` | `bicep build` 성공 + `what-if` diff 0 |
| **10-C** 전체 재배포 | `az deployment group create` 실행 로그 | Phase 1~9 전체 재배포 후 엔드투엔드 테스트 |
| **10-D** CI 자동화 (선택) | `.github/workflows/deploy.yml` | PR 에서 `what-if`, main merge 시 배포 |

---

## 공통 변수

```bash
SUB_ID="<구독 ID>"
LOCATION="koreacentral"
RG="rg-ai200challenge-dev"
ACR_SUFFIX="7k"          # Phase 1 Portal 단계에서 정한 것과 동일
ACR="acrai200challengedev${ACR_SUFFIX}"

az login
az account set --subscription "$SUB_ID"
```

---

## Phase 1 — CLI 재현 (컨테이너 호스팅 기초)

Portal 가이드: [01-container-hosting.md](01-container-hosting.md)

### 1. 리소스 그룹

```bash
az group create -n "$RG" -l "$LOCATION" \
  --tags project=ai200challenge env=dev phase=1
```

### 2. ACR 생성

```bash
az acr create -n "$ACR" -g "$RG" --sku Basic --admin-enabled false \
  --tags project=ai200challenge env=dev tier=shared
```

### 3. ACR Tasks 로 이미지 빌드·푸시 (로컬 소스 업로드)

```bash
TAG="0.1.0"
az acr build -r "$ACR" -t "api:$TAG" apps/api
az acr build -r "$ACR" -t "web:$TAG" apps/web
```

> GitHub 연동 빌드는 `az acr task create --context https://github.com/<user>/<repo> --file apps/api/Dockerfile ...` 형태. Quick task 대신 **정기 빌드**가 필요할 때 사용.

### 4. App Service Plan + 웹앱 2개 (컨테이너)

```bash
ASP="asp-ai200challenge-dev"
APP_API="app-ai200challenge-api-dev"
APP_WEB="app-ai200challenge-web-dev"

az appservice plan create -n "$ASP" -g "$RG" --is-linux --sku B1

# --- API 앱 ---
az webapp create -n "$APP_API" -g "$RG" --plan "$ASP" \
  --container-image-name "$ACR.azurecr.io/api:$TAG"

# 시스템 할당 Managed Identity
az webapp identity assign -n "$APP_API" -g "$RG"
API_PRINCIPAL=$(az webapp identity show -n "$APP_API" -g "$RG" --query principalId -o tsv)
ACR_ID=$(az acr show -n "$ACR" --query id -o tsv)

# AcrPull 역할 할당
az role assignment create \
  --assignee "$API_PRINCIPAL" \
  --role AcrPull \
  --scope "$ACR_ID"

# Managed Identity로 ACR pull 하도록 설정
az webapp config set -n "$APP_API" -g "$RG" --generic-configurations \
  '{"acrUseManagedIdentityCreds": true}'

# 포트 + 재시작
az webapp config appsettings set -n "$APP_API" -g "$RG" \
  --settings WEBSITES_PORT=8000
az webapp restart -n "$APP_API" -g "$RG"

# --- WEB 앱 (동일 패턴) ---
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
az webapp restart -n "$APP_WEB" -g "$RG"
```

### 5. 스모크 테스트

```bash
curl -s "https://$APP_API.azurewebsites.net/healthz"
# 기대: {"status":"ok"}

curl -s -X POST "https://$APP_API.azurewebsites.net/api/chat" \
  -H 'Content-Type: application/json' \
  -d '{"message":"CLI 재배포 테스트"}'
# 기대: {"reply":"[stub] CLI 재배포 테스트","model":"stub"}

open "https://$APP_WEB.azurewebsites.net"
```

### 6. Bicep 모듈 초안 (10-B 에서 확정)

```
infra/
  main.bicep
  modules/
    rg.bicep           # 태그·이름만 받는 얇은 wrapper
    acr.bicep          # ACR + 진단 로그
    appservice.bicep   # Plan + 2 개 WebApp + Identity + AcrPull role assignment
```

각 모듈의 `output` 으로 리소스 ID 를 넘겨 `main.bicep` 에서 연결.

---

## Phase 2 — CLI 재현 (ACA)

> 작성 예정. Phase 2 Portal 가이드가 확정된 뒤 동일 구조로 추가.

---

## Phase 3~9

> 각 Phase Portal 가이드가 완료된 뒤에 이 문서에 섹션을 차례로 추가한다. CLI 블록이 완성되면 Bicep 모듈로 리프트해 10-B 단계로 진입.

---

## 교훈 (CLI 재현 과정에서 발견한 것)

- (TBD — 각 Phase 재배포 후 기록)
