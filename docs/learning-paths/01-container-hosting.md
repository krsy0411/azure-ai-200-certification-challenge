# Phase 1 — Azure에서 컨테이너 애플리케이션 호스팅 구현

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/implement-container-app-hosting-azure/ (2 모듈)

## 학습 경로 구성

1. **Azure Container Registry에서 컨테이너 저장 및 관리**
   - ACR 레지스트리 계층 · 이미지 태깅 전략
   - 신뢰할 수 있는 배포를 위한 이미지 버전 관리
   - Managed Identity 기반 pull (키 없는 인증)
2. **Azure App Service에 컨테이너 배포**
   - `linuxFxVersion` 으로 사용자 지정 컨테이너 지정
   - 런타임 포트(`WEBSITES_PORT`) · 시작 명령 · 애플리케이션 설정
   - `acrUseManagedIdentityCreds` 로 키리스 pull

## 이 프로젝트에서의 적용

- FastAPI(`apps/api`) + Next.js(`apps/web`) 2개의 멀티스테이지 이미지
- ACR 한 개(`acrai200challengedev04`)에 두 이미지 푸시(`api:0.1.0`, `web:0.1.0`)
- Linux App Service 웹앱 2개를 Bicep 으로 동시 배포 → Phase 2 에서 ACA 로 이관

## 구현 스냅샷

| 컴포넌트 | 기술 | 엔드포인트/경로 |
|---|---|---|
| `apps/api` | FastAPI 0.115 + uv | `GET /healthz`, `POST /api/chat` |
| `apps/web` | Next.js 15.1 + React 19 | `GET /`, `POST /api/chat` (프록시) |
| `docker-compose.yml` | api + web 로컬 오케스트레이션 | api:8000, web:3000 |

---

## 아키텍처

```
Subscription
└─ rg-ai200challenge-dev
   ├─ acrai200challengedev04 (ACR, Basic)
   │     ├─ api:0.1.0
   │     └─ web:0.1.0
   ├─ asp-ai200challenge-dev (Linux B1, shared plan)
   ├─ app-ai200challenge-api-dev  (Web App, container)
   │     └─ System-assigned MI  ──AcrPull──▶ ACR
   └─ app-ai200challenge-web-dev  (Web App, container)
         ├─ System-assigned MI  ──AcrPull──▶ ACR
         └─ env: API_BASE_URL  ──────────▶ api 앱의 https URL
```

---

## Bicep 모듈 맵

| 파일 | 책임 |
|---|---|
| `infra/phases/01-container-hosting/main.bicep` | Phase 1 엔트리 (subscription 스코프) — RG 생성 + 아래 모듈 조립 |
| `infra/phases/01-container-hosting/main.bicepparam` | 리전·환경·ACR 접미사·이미지 태그 파라미터 |
| `infra/modules/acr.bicep` | ACR (Basic, admin 비활성) |
| `infra/modules/app-service-plan.bicep` | Linux App Service Plan |
| `infra/modules/app-service-container.bicep` | Web App (container) + System-assigned MI + `acrUseManagedIdentityCreds` |
| `infra/modules/role-assignment-acrpull.bicep` | MI → ACR `AcrPull` 역할 할당 |

---

## 스텝별 Bicep 하이라이트

### 스텝 0 — 스코프와 파라미터

Phase 1 은 RG 부터 만들기 때문에 **subscription 스코프**로 배포한다. `targetScope` 선언 + 네이밍 규칙을 변수로 묶는다.

```bicep
// infra/phases/01-container-hosting/main.bicep
targetScope = 'subscription'

@description('환경 라벨 (dev | prod)')
param environment string = 'dev'

@description('ACR 전역 유니크를 위한 2~4자 접미사')
@minLength(2)
@maxLength(4)
param acrSuffix string

var rgName     = 'rg-${projectId}-${environment}'
var acrName    = 'acr${projectId}${environment}${acrSuffix}'  // 하이픈 금지
var planName   = 'asp-${projectId}-${environment}'
var apiAppName = 'app-${projectId}-api-${environment}'
var webAppName = 'app-${projectId}-web-${environment}'
```

> **왜 `acrSuffix` 를 파라미터화 하나**: ACR 이름은 전역 유니크. 팀/실습자마다 다른 suffix 를 쓰도록 입력값으로 노출하는 편이 재사용성 ↑. Bicep 제약(`@minLength/@maxLength`)으로 규칙을 강제.

### 스텝 1 — 리소스 그룹

```bicep
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: commonTags
}
```

이 리소스만 subscription 스코프에서 선언 가능. 이후 모든 모듈은 `scope: rg` 로 이 RG 안에 배포된다.

### 스텝 2 — Azure Container Registry

`modules/acr.bicep` 은 Basic SKU + `adminUserEnabled: false` 가 핵심. admin 계정을 켜지 않는 이유는 **MI 기반 pull 을 강제하여 키를 없애기 위함**. Phase 8 의 Key Vault 이전에도 "키 없는 아키텍처" 기조를 유지.

```bicep
// modules/acr.bicep (발췌)
resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: { name: sku }
  properties: {
    adminUserEnabled: false       // 키 비활성
    publicNetworkAccess: 'Enabled' // Phase 8 에서 Private Endpoint 로 전환 예정
    zoneRedundancy: 'Disabled'
  }
}

output loginServer string = registry.properties.loginServer
```

### 스텝 3 — App Service Plan (Linux B1)

```bicep
// modules/app-service-plan.bicep (발췌)
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: sku }
  kind: 'linux'
  properties: {
    reserved: true  // Linux 플랜임을 명시 — 이게 없으면 Windows 로 생성됨
  }
}
```

> **함정**: `kind: 'linux'` 만으로는 충분치 않고 `properties.reserved = true` 가 **필수**. Bicep 문서에도 "Linux 플랜이면 true" 라고 명시.

### 스텝 4 — Web App (컨테이너) + Managed Identity

`linuxFxVersion` 포맷은 `DOCKER|<loginServer>/<image>:<tag>`. `acrUseManagedIdentityCreds=true` 를 `siteConfig` 안에 박으면 ACR pull 이 System-assigned MI 로 수행된다.

```bicep
// modules/app-service-container.bicep (발췌)
var linuxFxVersion = 'DOCKER|${acrLoginServer}/${imageName}:${imageTag}'

var appSettingsArray = [for key in objectKeys(appSettings): {
  name: key
  value: appSettings[key]
}]

resource site 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'   // 시스템 할당 MI 활성화
  }
  properties: {
    serverFarmId: planId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      acrUseManagedIdentityCreds: true  // ← MI 로 ACR pull
      alwaysOn: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: appSettingsArray
    }
  }
}

output principalId string = site.identity.principalId
output defaultHostName string = site.properties.defaultHostName
```

> **왜 `appSettings` 를 object 로 받고 배열로 변환하나**: Bicep 의 `siteConfig.appSettings` 는 `[{name, value}]` 형태를 요구. 상위에서 `{ WEBSITES_PORT: '8000' }` 처럼 선언적으로 쓰는 게 읽기 좋으므로 모듈 내부에서 `for-in objectKeys()` 로 변환.

### 스텝 5 — MI 에 AcrPull 역할 부여

별도 모듈로 뺀 이유: AcrPull 할당은 Phase 2 (ACA), Phase 3 (AKS) 등에서도 재사용되므로.

```bicep
// modules/role-assignment-acrpull.bicep (발췌)
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d' // built-in AcrPull

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, principalId, acrPullRoleId)  // 결정적 GUID → 재배포 시 중복 생성 방지
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'  // 웹앱의 MI 는 ServicePrincipal 로 등록됨
  }
}
```

> **왜 `guid(acr.id, principalId, roleId)`**: 역할 할당 리소스 이름은 GUID 여야 한다. `guid()` 는 결정적이므로 동일 입력이면 같은 이름 → 재배포/업데이트 시 중복 에러 없음.

### 스텝 6 — 두 웹앱 + 역할 할당을 조립

`main.bicep` 이 같은 모듈(`app-service-container.bicep`)을 api·web 두 번 호출. Web 앱은 API 의 defaultHostName 을 `appSettings.API_BASE_URL` 로 받는다 — 배포 시점에 Bicep 이 자동 결선.

```bicep
module apiApp '../../modules/app-service-container.bicep' = {
  name: 'deploy-app-api'
  scope: rg
  params: {
    name: apiAppName
    planId: plan.outputs.id
    acrLoginServer: acr.outputs.loginServer
    imageName: 'api'
    imageTag: imageTag
    appSettings: { WEBSITES_PORT: '8000' }
    // ...
  }
}

module apiAcrPull '../../modules/role-assignment-acrpull.bicep' = {
  name: 'ra-acrpull-api'
  scope: rg
  params: {
    acrName: acr.outputs.name
    principalId: apiApp.outputs.principalId
  }
}

module webApp '../../modules/app-service-container.bicep' = {
  name: 'deploy-app-web'
  scope: rg
  params: {
    name: webAppName
    planId: plan.outputs.id
    acrLoginServer: acr.outputs.loginServer
    imageName: 'web'
    imageTag: imageTag
    appSettings: {
      WEBSITES_PORT: '3000'
      API_BASE_URL: 'https://${apiApp.outputs.defaultHostName}'  // 순서 의존성 자동
    }
    // ...
  }
}
```

---

## 이미지 빌드 · ACR 푸시 (docker CLI)

Bicep 은 이미지를 빌드하지 못하므로 이 단계만 CLI. Apple Silicon (arm64) 에서는 App Service 의 amd64 런타임과 맞추기 위해 **`--platform linux/amd64` 필수**.

```bash
# 1) Azure 로그인 + ACR 토큰
az configure --defaults group=''   # 오염된 기본값 있으면 초기화
az acr login --name acrai200challengedev04

# 2) 빌드 (레포 루트에서 실행)
ACR_LOGIN_SERVER="acrai200challengedev04.azurecr.io"
TAG="0.1.0"

docker build --platform linux/amd64 \
  -t "$ACR_LOGIN_SERVER/api:$TAG" \
  apps/api

docker build --platform linux/amd64 \
  -t "$ACR_LOGIN_SERVER/web:$TAG" \
  apps/web

# 3) 푸시
docker push "$ACR_LOGIN_SERVER/api:$TAG"
docker push "$ACR_LOGIN_SERVER/web:$TAG"

# 4) 검증
az acr repository list --name acrai200challengedev04 --output table
az acr repository show-tags --name acrai200challengedev04 --repository api --output table
az acr repository show-tags --name acrai200challengedev04 --repository web --output table
```

**중요 순서**: 이미지는 **Bicep 배포 전에** 레지스트리에 있어야 한다. App Service 는 생성 즉시 이미지를 pull 하려 하므로, 이미지가 없으면 crash 루프 발생. 완화책으로 Bicep 을 먼저 돌려도 App Service 는 `Starting` 상태로 대기하며 이후 이미지가 올라오면 복구되지만, 깔끔한 교육 시나리오는 **이미지 푸시 → Bicep 배포** 순서.

---

## 배포

```bash
# 1) Bicep 빌드 (경고 없는지 확인)
az bicep build --file infra/phases/01-container-hosting/main.bicep

# 2) what-if (변경 미리보기) — subscription 스코프
az deployment sub what-if \
  --location koreacentral \
  --template-file infra/phases/01-container-hosting/main.bicep \
  --parameters infra/phases/01-container-hosting/main.bicepparam

# 3) 실제 배포
az deployment sub create \
  --location koreacentral \
  --name phase1-$(date +%Y%m%d-%H%M%S) \
  --template-file infra/phases/01-container-hosting/main.bicep \
  --parameters infra/phases/01-container-hosting/main.bicepparam
```

배포 완료 후 outputs 확인:

```bash
az deployment sub show \
  --name <방금-쓴-배포명> \
  --query properties.outputs
```

기대 예:

```json
{
  "resourceGroupName": { "value": "rg-ai200challenge-dev" },
  "acrLoginServer":    { "value": "acrai200challengedev04.azurecr.io" },
  "apiUrl":            { "value": "https://app-ai200challenge-api-dev.azurewebsites.net" },
  "webUrl":            { "value": "https://app-ai200challenge-web-dev.azurewebsites.net" }
}
```

### 이미 Portal 로 만든 리소스가 있다면

`rg-ai200challenge-dev` 와 `acrai200challengedev04` 가 Portal 로 선행 생성돼 있어도 Bicep 은 idempotent. `what-if` 결과에서 두 리소스는 **Ignore** 또는 **NoChange** 로 표시되면 정상. 만약 Modify 로 뜨면 태그 또는 속성이 템플릿과 다른 것이므로 원인 확인.

---

## 검증 (스모크 테스트)

```bash
API_URL="https://app-ai200challenge-api-dev.azurewebsites.net"
WEB_URL="https://app-ai200challenge-web-dev.azurewebsites.net"

# 1) API healthz
curl -s "$API_URL/healthz"
# 기대: {"status":"ok"}

# 2) API chat stub
curl -s -X POST "$API_URL/api/chat" \
  -H 'Content-Type: application/json' \
  -d '{"message":"Bicep 배포 테스트"}'
# 기대: {"reply":"[stub] Bicep 배포 테스트","model":"stub"}

# 3) Web UI 브라우저 확인
open "$WEB_URL"
# 기대: 챗 UI 로드 → 메시지 전송 시 API 프록시 경유 stub 응답
```

**세 개 모두 통과하면 Phase 1 DoD 충족.**

---

## 함정 · 교훈 (배포 후 기록)

- **hatchling 빌드가 README.md 를 요구** — `apps/api/pyproject.toml` 의 `readme = "README.md"` 필드 때문에 Dockerfile 이 README.md 를 COPY 하지 않으면 `uv sync` 단계에서 `OSError: Readme file does not exist: README.md` 로 빌드 실패. `apps/api/.dockerignore` 에서 `README.md` 제외 목록을 삭제하고, Dockerfile 의 builder 스테이지에 `COPY README.md ./` 를 추가해야 정상 빌드.
- **`az configure --defaults` 오염** — `az configure --defaults group=Test` 같은 과거 세션 잔재가 남아 있으면, 실제 RG 가 존재하더라도 `az acr login` 이 `Resource group 'Test' could not be found` 로 실패. 증상은 ACR 쪽 에러처럼 보이지만 원인은 CLI 기본값. `az configure --defaults group=''` 로 해제.
- **ACR 생성 직후 첫 `az acr login` 실패, 재시도로 해결** — `az deployment sub create` 가 `Succeeded` 로 리턴된 직후에도 `az acr login` 이 `Could not connect to the registry login server` 로 실패하는 경우가 있음. DNS/백엔드 전파 지연으로 보이며, 1~2분 후 재시도 시 성공. 진단은 `az acr check-health -n <acr> --yes`, 확인은 `nslookup <acr>.azurecr.io`.
- **`az acr show --query "{...}"` 가 nested 속성을 null 로 리턴** — `--query "{loginServer:properties.loginServer}"` 형식이 null 값을 반환해 "ACR 이 깨진 건가?" 로 오해하기 쉬움. 실제로는 스키마 차이 (최상위 `loginServer` / `provisioningState`) 때문. `--query` 생략하고 JSON 전체를 받으면 정상 값 확인 가능.
- **`--platform linux/amd64` 는 필수, 옵션 아님** — Apple Silicon (arm64) 로컬에서 빌드한 이미지를 App Service Linux (amd64) 에서 돌리면 런타임 대신 `exec format error` 로 조용히 죽음. 빌드 시점에 platform 을 명시하는 습관.

---

## 체크리스트

- [x] `apps/api/Dockerfile` 멀티스테이지 (uv 기반)
- [x] `apps/web/Dockerfile` 멀티스테이지 (Next.js standalone)
- [x] FastAPI 로컬 smoke test 성공
- [x] Next.js 타입 체크 · 프로덕션 빌드 성공
- [x] Phase 1 Bicep 모듈 + main.bicep 작성
- [x] `docker build --platform linux/amd64` 후 `docker push` 로 `api:0.1.0`, `web:0.1.0` 푸시 완료
- [x] `az deployment sub what-if` 로 변경 내역 검토
- [x] `az deployment sub create` 로 Phase 1 배포 완료 (`phase1-20260423-140402`, `provisioningState: Succeeded`)
- [x] `/healthz`, `/api/chat` 자동 스모크 테스트 통과 · Web `/` 200 OK
- [x] Web UI 브라우저 육안 확인 (채팅 입력 → stub 응답 렌더링)
- [x] 본 문서 "함정 · 교훈" 에 실제 삽질 기록 추가
