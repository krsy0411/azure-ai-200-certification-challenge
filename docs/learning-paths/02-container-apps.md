# Phase 2 — Azure Container Apps 에서 앱 배포 및 관리

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/deploy-manage-apps-azure-container-apps/ (3 모듈)

## 학습 경로 구성

1. **Azure Container Apps 에 컨테이너 배포** — Managed Environment 개념, UAMI 기반 레지스트리 인증, ingress (external/internal), 배포 확인.
2. **Azure Container Apps 에서 컨테이너 관리** — 이미지 업데이트, 리비전(Single → Multiple) 전환, 실패 진단 (프로브·로그), 리소스·스케일 조정.
3. **Azure Container Apps 에서 컨테이너 크기 조정** — HTTP/TCP/CPU 스케일 규칙, KEDA 이벤트 기반 스케일, 리비전 모드와 트래픽 관리.

## 이 프로젝트에서의 적용

- 단일 ACA Environment (`cae-ai200challenge-dev`) 안에 `api`, `web` 두 Container App 배포
- **ingress 패턴**: `api` = internal (ACA Env 내부에서만 도달), `web` = external — "내부 통신" 학습
- **UAMI 공용**: `id-ai200challenge-aca-dev` 하나로 두 앱의 ACR pull 처리. System-assigned 를 쓰면 "앱 생성 → MI 생성 → registry 연결" 순환이 생기므로 ACA 는 UAMI 가 정석
- **Single Revision Mode** 로 시작 (Phase 7 에서 Multiple + 트래픽 분할로 전환)
- HTTP concurrency ≥ 30 → 1~5 복제본
- Phase 1 의 App Service 는 Phase 2 배포·검증 완료 후 **정리 섹션** 지시대로 수동 제거 (Phase 1 문서·IaC 는 교육 산출물로 보존)

## 구현 스냅샷

| 컴포넌트 | 리소스 | 이름 |
|---|---|---|
| Log Analytics Workspace | 로그 싱크 | `law-ai200challenge-dev` |
| User-Assigned MI | ACR pull 자격 | `id-ai200challenge-aca-dev` |
| ACA Environment | 공용 네트워크·로그 경계 | `cae-ai200challenge-dev` |
| API Container App | FastAPI, 8000, **internal** | `ca-ai200challenge-api-dev` |
| Web Container App | Next.js, 3000, **external** | `ca-ai200challenge-web-dev` |

---

## 아키텍처

```
rg-ai200challenge-dev
├─ law-ai200challenge-dev                     (Log Analytics)
├─ id-ai200challenge-aca-dev                  (UAMI)
│     └─ AcrPull on acrai200challengedev04    (role assignment, Phase 1 ACR 에)
├─ cae-ai200challenge-dev                     (ACA Environment)
│     ├─ ca-ai200challenge-api-dev   (ingress=internal, :8000, /healthz probe)
│     │     └─ UAMI → acrai200challengedev04/api:0.1.0
│     └─ ca-ai200challenge-web-dev   (ingress=external, :3000, /probe)
│           ├─ UAMI → acrai200challengedev04/web:0.1.0
│           └─ env: API_BASE_URL = https://<api 의 internal FQDN>
│
└─ acrai200challengedev04  (Phase 1 에서 생성, existing 참조)
```

> **Phase 1 과의 관계**: ACR 만 재사용. Phase 1 의 App Service Plan/Web App 2개는 Phase 2 가 안정화되면 제거.

---

## Bicep 모듈 맵

| 파일 | 책임 |
|---|---|
| `infra/phases/02-container-apps/main.bicep` | Phase 2 엔트리 (resourceGroup 스코프). Phase 1 ACR 을 `existing` 으로 참조. |
| `infra/phases/02-container-apps/main.bicepparam` | 리전·환경·ACR 이름·이미지 태그 파라미터 |
| `infra/modules/log-analytics.bicep` | LAW (PerGB2018, 기본 30일 보존) |
| `infra/modules/user-assigned-identity.bicep` | UAMI (principalId·clientId·resourceId outputs) |
| `infra/modules/container-apps-env.bicep` | ACA Env + LAW 연동 (customerId + sharedKey) |
| `infra/modules/container-app.bicep` | Container App 1개 — UAMI registries, ingress, probes, HTTP scale |
| `infra/modules/role-assignment-acrpull.bicep` | **재사용** — UAMI → ACR `AcrPull` |

---

## 스텝별 Bicep 하이라이트

### 스텝 0 — 스코프와 파라미터

Phase 1 에서 RG 가 이미 존재 → `targetScope = 'resourceGroup'`. Phase 1 의 ACR 은 이름을 파라미터로 직접 받지 않고, 같은 `projectId` / `environment` / `acrSuffix` 로부터 **네이밍 규칙으로 역산**한다. 이렇게 하면 bicepparam 에 ACR 고유 이름이 들어가지 않아 OSS 레포에 안전하게 커밋 가능하고, fork 하는 사람은 `acrSuffix` 하나만 바꾸면 자기 ACR 로 돌아간다.

```bicep
// infra/phases/02-container-apps/main.bicep
targetScope = 'resourceGroup'

@description('ACR 전역 유니크 접미사 (Phase 1 에서 쓴 값과 동일해야 같은 ACR 을 참조)')
@minLength(2)
@maxLength(4)
param acrSuffix string

var acrName = 'acr${projectId}${environment}${acrSuffix}'

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}
```

> **왜 `acrName` 을 직접 받지 않고 `acrSuffix` 에서 derive 하나**: 네이밍 규칙 (`acr<projectId><env><suffix>`) 을 레포에 고정해두면 OSS reader 가 자기 값으로 fork 하기 쉽고, bicepparam 에 특정 사용자의 ACR 고유 이름이 노출되지 않는다. Phase 3 의 Log Analytics 참조도 같은 원리.

### 스텝 1 — Log Analytics Workspace

ACA Environment 의 로그·진단 싱크. Phase 9 에서 Application Insights 의 workspace-based 백엔드로도 재사용한다.

```bicep
// modules/log-analytics.bicep (발췌)
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output customerId string = workspace.properties.customerId

@secure()
output sharedKey string = workspace.listKeys().primarySharedKey
```

> **`@secure()` output 이 필수**: `sharedKey` 는 민감값. ACA Env 로 그대로 주입되며, 이를 secure 로 선언해야 배포 로그/what-if 결과에 평문 노출되지 않는다.

### 스텝 2 — UAMI (User-Assigned Managed Identity)

```bicep
// modules/user-assigned-identity.bicep (발췌)
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: name
  location: location
}

output id string = identity.id
output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
```

> **왜 System-assigned 가 아니라 UAMI 인가**: ACA 는 Container App 생성 시점에 `registries[].identity` 로 pull MI 를 받아야 한다. System-assigned MI 는 앱이 "먼저" 생성되어야 만들어지므로 "앱 생성 → MI 생성 → registry 주입" 순환이 성립하지 않는다. UAMI 는 앱보다 먼저 만들 수 있어 이 문제를 해결한다.

### 스텝 3 — UAMI → ACR AcrPull

Phase 1 에서 만든 모듈을 그대로 재사용. 결정적 GUID 덕분에 재배포 안전.

```bicep
module uamiAcrPull '../../modules/role-assignment-acrpull.bicep' = {
  name: 'ra-acrpull-uami'
  params: {
    acrName: acrName
    principalId: uami.outputs.principalId
  }
}
```

### 스텝 4 — ACA Managed Environment

```bicep
// modules/container-apps-env.bicep (발췌)
resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output defaultDomain string = env.properties.defaultDomain
```

> **`defaultDomain` 이 중요한 이유**: internal ingress 의 FQDN 은 `<app>.internal.<defaultDomain>` 형태로 뽑힌다. 같은 Env 안의 다른 앱만 resolve 가능. Phase 2 에서는 `webApp.envVars.API_BASE_URL` 에 `apiApp.outputs.fqdn` (internal FQDN) 을 그대로 넣으면 Bicep 이 결선까지 해 준다.

### 스텝 5 — Container App (internal / external)

핵심: `identity` 블록에 UAMI 주입, `registries[].identity` 에 **UAMI resourceId**, `ingress.external` 로 공개 여부 결정.

```bicep
// modules/container-app.bicep (발췌)
resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: ingressExternal            // api=false, web=true
        targetPort: targetPort               // api=8000, web=3000
        transport: 'Auto'
        allowInsecure: false
        traffic: [ { weight: 100, latestRevision: true } ]
      }
      registries: [
        {
          server: acrLoginServer
          identity: userAssignedIdentityId   // UAMI 로 ACR pull
        }
      ]
    }
    template: {
      containers: [
        {
          name: imageName
          image: '${acrLoginServer}/${imageName}:${imageTag}'
          resources: { cpu: json(cpu), memory: memory }
          env: envArray
          probes: [
            {
              type: 'Readiness'
              httpGet: { path: healthProbePath, port: targetPort, scheme: 'HTTP' }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
            {
              type: 'Liveness'
              httpGet: { path: healthProbePath, port: targetPort, scheme: 'HTTP' }
              initialDelaySeconds: 15
              periodSeconds: 30
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-concurrency'
            http: {
              metadata: { concurrentRequests: string(httpConcurrency) }
            }
          }
        ]
      }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
```

> **`cpu: json(cpu)`**: Container App 의 CPU 는 `number`(0.25, 0.5, 1.0) 를 요구하지만 Bicep 파라미터는 문자열로 받는 편이 자릿수 정밀도 유지에 안전. 삽입 직전에 `json()` 으로 number 캐스팅.
>
> **`concurrentRequests: string(httpConcurrency)`**: KEDA metadata 는 무조건 문자열 맵. 숫자 파라미터를 그대로 넣으면 스키마 에러.

### 스텝 6 — 두 앱 조립 (api → web 의존)

```bicep
module apiApp '../../modules/container-app.bicep' = {
  name: 'deploy-ca-api'
  params: {
    name: 'ca-ai200challenge-api-dev'
    ingressExternal: false                      // ← internal
    targetPort: 8000
    healthProbePath: '/healthz'
    // ...
  }
  dependsOn: [ uamiAcrPull ]                    // pull 권한이 먼저 있어야 이미지 받음
}

module webApp '../../modules/container-app.bicep' = {
  name: 'deploy-ca-web'
  params: {
    name: 'ca-ai200challenge-web-dev'
    ingressExternal: true                       // ← external
    targetPort: 3000
    healthProbePath: '/'
    envVars: {
      API_BASE_URL: 'https://${apiApp.outputs.fqdn}'   // internal FQDN 주입
    }
  }
  dependsOn: [ uamiAcrPull ]
}
```

---

## 이미지 준비

Phase 1 에서 이미 `acrai200challengedev04.azurecr.io/{api,web}:0.1.0` 가 푸시되어 있으므로 **재빌드 불필요**. 확인만:

```bash
az acr repository show-tags --name acrai200challengedev04 --repository api --output table
az acr repository show-tags --name acrai200challengedev04 --repository web --output table
```

이미지가 없으면 Phase 1 문서의 "이미지 빌드·ACR 푸시" 섹션을 먼저 실행.

---

## 배포

```bash
# 1) Bicep 컴파일 검증
az bicep build --file infra/phases/02-container-apps/main.bicep

# 2) what-if (resourceGroup 스코프)
az deployment group what-if \
  --resource-group rg-ai200challenge-dev \
  --template-file infra/phases/02-container-apps/main.bicep \
  --parameters infra/phases/02-container-apps/main.bicepparam

# 3) 실제 배포
az deployment group create \
  --resource-group rg-ai200challenge-dev \
  --name phase2-$(date +%Y%m%d-%H%M%S) \
  --template-file infra/phases/02-container-apps/main.bicep \
  --parameters infra/phases/02-container-apps/main.bicepparam

# 4) outputs 확인
az deployment group show \
  --resource-group rg-ai200challenge-dev \
  --name <방금-쓴-배포명> \
  --query properties.outputs
```

기대 outputs:

```json
{
  "apiInternalFqdn":  { "value": "ca-ai200challenge-api-dev.internal.<defaultDomain>" },
  "apiInternalUrl":   { "value": "https://ca-ai200challenge-api-dev.internal.<defaultDomain>" },
  "containerAppsEnvDefaultDomain": { "value": "<region>-<random>.azurecontainerapps.io" },
  "userAssignedIdentityId": { "value": "/subscriptions/.../userAssignedIdentities/id-ai200challenge-aca-dev" },
  "webFqdn": { "value": "ca-ai200challenge-web-dev.<defaultDomain>" },
  "webUrl":  { "value": "https://ca-ai200challenge-web-dev.<defaultDomain>" }
}
```

---

## 검증 (스모크 테스트)

### 1) 리비전 · 프로브 · 로그 (ACA 관리 면)

```bash
# 최신 리비전 상태
az containerapp revision list \
  -n ca-ai200challenge-api-dev \
  -g rg-ai200challenge-dev \
  --query "[].{name:name,active:properties.active,healthState:properties.healthState,traffic:properties.trafficWeight}" -o table

# 로그 스트림 (Ctrl-C 로 종료)
az containerapp logs show \
  -n ca-ai200challenge-api-dev \
  -g rg-ai200challenge-dev \
  --follow --tail 50
```

기대: `healthState = Healthy`, active=true, trafficWeight=100. 로그에 `uvicorn` 기동 라인 + `/healthz 200` 프로브 라인 주기적 출력.

### 2) 외부에서 web → 브라우저

```bash
WEB_URL=$(az deployment group show \
  -g rg-ai200challenge-dev --name <배포명> \
  --query properties.outputs.webUrl.value -o tsv)
open "$WEB_URL"
```

기대: 채팅 UI 로드 → 메시지 전송 → `[stub] <입력>` 응답. 이 응답은 **web 컨테이너가 internal FQDN 으로 api 를 호출** → 내부 통신 패턴 확인.

### 3) internal ingress 도달 불가 확인

```bash
API_URL=$(az deployment group show \
  -g rg-ai200challenge-dev --name <배포명> \
  --query properties.outputs.apiInternalUrl.value -o tsv)

curl -v "$API_URL/healthz" 2>&1 | head -20
```

기대: DNS resolve 실패 또는 타임아웃. `*.internal.<defaultDomain>` 은 **ACA Environment 내부에서만** 도달 가능하기 때문. 이게 바로 internal ingress 의 역할.

### 4) HTTP concurrency 스케일 (선택)

```bash
# hey 로 30 동시 요청 60초
hey -z 60s -c 50 "$WEB_URL/"

# 다른 터미널에서 복제본 변화 관찰
watch -n 2 'az containerapp revision show \
  -n ca-ai200challenge-web-dev -g rg-ai200challenge-dev \
  --revision $(az containerapp revision list -n ca-ai200challenge-web-dev -g rg-ai200challenge-dev --query "[0].name" -o tsv) \
  --query "properties.replicas" -o tsv'
```

기대: 부하 동안 복제본이 1 → 2~5 로 증가 후, 부하 종료 후 1 로 수렴.

### DoD

- 위 1~3 통과 시 Phase 2 완료. 4 는 AI-200 스케일 규칙 학습용 추가 검증.

---

## Phase 1 정리 (Phase 2 검증 후 실행)

Phase 2 가 안정적으로 도는 것을 확인한 **다음에만** Phase 1 의 App Service 리소스를 삭제. Phase 1 의 Bicep/문서는 교육 산출물로 보존한다.

```bash
RG="rg-ai200challenge-dev"

# 1) 두 Web App 삭제
az webapp delete -g "$RG" -n app-ai200challenge-api-dev
az webapp delete -g "$RG" -n app-ai200challenge-web-dev

# 2) App Service Plan 삭제 (남은 앱 없을 때만 성공)
az appservice plan delete -g "$RG" -n asp-ai200challenge-dev --yes

# 3) 남은 App Service 관련 리소스 확인
az resource list -g "$RG" --resource-type "Microsoft.Web/sites"       -o table
az resource list -g "$RG" --resource-type "Microsoft.Web/serverFarms" -o table
```

> **ACR 은 절대 삭제하지 말 것** — Phase 2 의 ACA 가 계속 이 ACR 에서 pull 한다.
>
> **Phase 10 상위 조립** 에서는 Phase 1 모듈을 포함하지 않거나 조건부 플래그로 건너뛰어, "Phase 1 은 기록으로만 남는" 상태를 IaC 로도 표현할 예정.

---

## 함정 · 교훈 (배포 후 기록)

- **Internal ingress 는 외부에서 "연결 거부" 가 아니라 `404` 로 응답한다** — `curl https://<app>.internal.<env>.azurecontainerapps.io/healthz` 가 DNS 는 resolve 되고(Traffic Manager → Env 정적 IP 까지는 모두 public) TCP 핸드셰이크도 성공. 다만 ACA 엣지 라우터가 "해당 hostname 은 외부 공개 대상이 아니다" 로 판단해 HTTP 404 로 거부. "404 가 나니 앱이 죽었나?" 로 오인하기 쉬움. 실제로는 **격리가 정상 동작 중인 증거**. 내부 도달성은 로그의 요청 source IP (`100.100.0.0/16` = ACA Env 내부 VNet) 로만 확증 가능.
- **`what-if` 의 AcrPull `Unsupported` 는 Phase 1/2 공통 노이즈** — UAMI 의 `principalId` 가 배포 시점에 생성되므로 what-if 가 미리 resource ID 를 계산할 수 없어 `Unsupported` 진단이 뜸. `reference(...).principalId` 를 쓰는 role assignment 는 모든 Phase 에서 이 패턴. 실제 배포에서는 정상 생성됨.
- **Container App 의 KEDA scale rule metadata 는 문자열 맵** — `concurrentRequests: 30` (숫자) 로 넣으면 Bicep 컴파일은 통과해도 배포 시 `InvalidTemplate` 로 실패. `string(httpConcurrency)` 로 감싸야 함. 같은 규칙이 CPU/메모리 스케일 rule, Service Bus queueLength 등 **모든 KEDA metadata** 에 적용.
- **`cpu` 는 Bicep 측에서 문자열로 받고 삽입 직전 `json()` 으로 number 캐스팅** — `Microsoft.App/containerApps` 스키마는 `resources.cpu` 를 `number` (0.25, 0.5, 1.0) 로 요구. 하지만 Bicep 파라미터를 number 로 선언하면 `0.5` 가 내부적으로 `0.5000000001` 등으로 직렬화될 위험. 문자열 파라미터 → `json(cpu)` 로 방어.
- **Log Analytics `sharedKey` 는 반드시 `@secure()` output** — `listKeys().primarySharedKey` 를 평문 output 으로 뽑으면 `az deployment ... show` 결과에 그대로 노출. `@secure()` 로 선언하면 Bicep 런타임이 평문 직렬화를 막음. 이게 ACA Env 로 전달될 때에도 Azure 측이 "secret 은 secret 처리" 하는 힌트가 됨.

---

## MS Learn 경로 커버리지 — 사용 / 생략

공식 경로: https://learn.microsoft.com/ko-kr/training/paths/deploy-manage-apps-azure-container-apps/ (3 모듈)

### 모듈 1 — Azure Container Apps 에 컨테이너 배포

| 영역 | 상태 | 비고 |
|---|---|---|
| Managed Environment 생성 + Log Analytics 연동 | ✓ | `cae-ai200challenge-dev` + `law-ai200challenge-dev` |
| External ingress (public FQDN) | ✓ | web 앱 |
| Internal ingress (Env 내부 only) | ✓ | api 앱 — 내부 통신 패턴 학습 |
| UAMI 로 registry 인증 (`registries[].identity`) | ✓ | `id-ai200challenge-aca-dev` 공용 |
| `--environment-variables` / env 주입 | ✓ | `API_BASE_URL` 을 api 의 internal FQDN 으로 결선 |
| Consumption workload profile | ✓ | 단일 `Consumption` 프로파일 |
| Dedicated workload profile (D4/E4 등) | ✗ | 비용·안정성 이점 없음. Consumption 으로 충분 |
| Bring Your Own VNet (커스텀 VNet 주입) | ✗ | **Phase 8** Private Endpoint 계열로 이관 |
| Custom domain + managed certificate | ✗ | 포트폴리오 범위 외 |

### 모듈 2 — Container Apps 관리 (리비전·진단)

| 영역 | 상태 | 비고 |
|---|---|---|
| Single Revision Mode | ✓ | Phase 2 기본값 |
| readiness / liveness probe (HTTP) | ✓ | api `/healthz`, web `/` |
| 로그 스트림 (`az containerapp logs show`) | ✓ | stdout/stderr → Log Analytics |
| Container Insights 메트릭 (CPU/메모리) | ✓ | **Phase 9** 에서 Application Insights 와 함께 확장 |
| Multiple Revision Mode + 트래픽 분할 | ✗ | **Phase 7** (백엔드 통합) 에서 Blue/Green 데모로 도입 예정 |
| Dapr 통합 (service invocation, pub/sub) | ✗ | **Phase 7** 에서 Service Bus + Event Grid 로 직접 처리하므로 Dapr 층 불필요 |
| Startup probe | ✗ | 현재 이미지는 기동 빨라 불필요. 필요 시 모듈에 추가 |
| Secrets 관리 (`containerApp.properties.configuration.secrets`) | ✗ | **Phase 8** 에서 Key Vault + `secretref` 로 통합 |
| Container App Jobs (schedule / event / manual) | ✗ | **Phase 7** 비동기 워커로 고려 대상 |

### 모듈 3 — Container Apps 스케일

| 영역 | 상태 | 비고 |
|---|---|---|
| HTTP concurrency 스케일 규칙 | ✓ | `concurrentRequests: 30`, 1~5 replicas |
| `minReplicas=0` 콜드 스타트 | ✗ | 학습용 실시간성 위해 min=1 고정. Phase 7 워커에선 0 시도 여지 |
| TCP scale rule | ✗ | HTTP 만 사용. AI-200 시험 단골이지만 본 프로젝트 워크로드는 HTTP 전용 |
| CPU / Memory scale rule | ✗ | HTTP concurrency 로 일관 |
| KEDA — Service Bus queue length | ✗ | **Phase 7** 에서 워커 스케일로 도입 예정 |
| KEDA — Cron (시간 기반) | ✗ | 본 프로젝트 요구 없음 |
| KEDA — Azure Storage Queue / Event Hubs | ✗ | 본 프로젝트는 Service Bus + Event Grid 조합 |

> **Phase 2 DoD 는 "Deploy + Manage 기본 + HTTP Scale"** 로 한정. Multiple Revision · Dapr · 다종 KEDA 는 Phase 7 (백엔드 통합) 에서 재방문.

---

## 체크리스트

- [x] Phase 2 Bicep 모듈 4개 + main.bicep/param 작성
- [x] `az bicep build` 경고 없음
- [x] `az deployment group what-if` 로 변경 내역 검토 (5 Create · 1 Unsupported(AcrPull 노이즈) · 4 Ignore(Phase 1 자원))
- [x] `az deployment group create` 로 Phase 2 배포 완료 (`phase2-20260423-161132`, 3m28s, `Succeeded`)
- [x] `az containerapp revision list` 로 리비전 Healthy 확인 (api/web 양쪽 active=true, traffic=100%, replica=1)
- [x] `az containerapp logs show` 로 /healthz 프로브 확인 (10s 간격 readiness, 30s 간격 liveness 모두 200)
- [x] Web 외부 URL 브라우저에서 채팅 동작 확인 (→ web → api internal 통신 증명)
- [x] API internal URL 은 외부 curl 로 도달 불가 확인 (404 = ACA 엣지 거부, `100.100.0.0/16` source IP 로만 실제 도달 확인)
- [x] Phase 1 App Service · ASP 삭제 (ACR 만 보존)
- [x] 본 문서 "함정 · 교훈" 에 실제 삽질 기록 추가
