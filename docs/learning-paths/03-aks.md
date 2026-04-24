# Phase 3 — Azure Kubernetes Service 에서 앱 배포 및 모니터링

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/deploy-monitor-apps-azure-kubernetes-service/ (3 모듈)

## 학습 경로 구성

1. **AKS 에 애플리케이션 배포** — Deployment/Service/HPA 매니페스트, 이미지 레지스트리 연동, replicas 관리.
2. **AKS 에서 애플리케이션 구성** — ConfigMap / Secret / PV·PVC 로 구성·비밀·상태 관리.
3. **AKS 모니터링 · 문제 해결** — Container Insights, 로그·메트릭, Pod/Service 트러블슈팅.

## 이 프로젝트에서의 적용

- **보조 클러스터 포지셔닝**: Phase 2 ACA 가 "메인 호스팅" 이고, AKS 는 **같은 api 이미지를 Kubernetes 네이티브로도 돌려 본다**는 학습용 보조 클러스터. 외부 공개하지 않고 ClusterIP + `kubectl port-forward` 로만 검증 → 비용/공격면 축소.
- **system 노드 풀 `Standard_D2s_v3` × 2**: AKS 권장 최소(2 vCPU, 8 GiB) 충족. koreacentral 구독의 **기본 쿼터가 `DSv3 Family` 에 10 vCPU 할당**되어 있어 쿼터 상향 요청 없이 바로 배포 가능. DSv5 는 기본 쿼터 0 이므로 회피. B-series 는 Burstable (CPU credit 방식) 이라 AKS 학습 중 메트릭/스케일 동작이 credit 고갈 여부에 좌우돼 관측 결과가 왜곡되므로 회피. 별도 user 풀 없이 system 풀에서 워크로드도 돌림.
- **Entra ID + Azure RBAC, 로컬 계정 disable** — "AI-200 시험 출제 1순위" 패턴. 클러스터 인증을 전적으로 Azure AD 로 위임 → 별도 kubeconfig 관리 불필요.
- **kubelet identity 를 UAMI 로 주입**: ACR pull 을 kubelet 이 해결. `az aks update --attach-acr` (암묵적 identity 생성) 대신, Bicep 레벨에서 UAMI + AcrPull 역할 할당을 명시해 재배포 안전.
- **Container Insights 애드온으로 Phase 2 LAW 재사용**: 새 LAW 를 만들지 않고 `law-ai200challenge-dev` 를 그대로 사용 → 로그 싱크 단일화.
- **Phase 3 검증 완료 후 `az aks stop`** 으로 비용 절감. 포트폴리오 가시성 유지하면서 시간당 요금은 발생하지 않도록.
- **ConfigMap/Secret/PV·PVC** 는 본 Phase 에서 스킵 → Phase 8 에서 Key Vault CSI Driver / Azure Files CSI 로 통합. 이유: 한 번 써 두면 Phase 8 에서 "재작성" 을 강요당하기 때문.

## 구현 스냅샷

| 컴포넌트 | 리소스 | 이름 |
|---|---|---|
| User-Assigned MI | kubelet identity | `id-ai200challenge-aks-dev` |
| AKS 클러스터 | Entra ID + Azure RBAC | `aks-ai200challenge-dev` |
| AKS system nodepool | `Standard_D2s_v3` × 2 | (Azure CNI Overlay) |
| Role — `AcrPull` | UAMI → Phase 1 ACR | |
| Role — `Azure Kubernetes Service RBAC Cluster Admin` | signed-in user → AKS | |
| Container Insights 애드온 | `omsagent` → Phase 2 LAW | `law-ai200challenge-dev` |
| k8s Namespace | 워크로드 격리 | `ai200` |
| k8s Deployment | api 2 replicas | `api` (containerPort 8000) |
| k8s Service | ClusterIP (외부 노출 없음) | `api` (port 8000) |
| k8s HPA | CPU 50%, 1~5 | `api` |

---

## 아키텍처

```
rg-ai200challenge-dev
├─ law-ai200challenge-dev                       (Phase 2 LAW, existing 참조)
├─ id-ai200challenge-aks-dev                    (kubelet UAMI)
│     └─ AcrPull on acrai200challengedev04      (Phase 1 ACR)
├─ aks-ai200challenge-dev                       (AKS 클러스터)
│     ├─ aadProfile: managed + enableAzureRBAC + tenantID
│     ├─ disableLocalAccounts=true
│     ├─ system nodepool × 2 (Standard_D2s_v3)
│     ├─ networkProfile: Azure CNI Overlay (pod 10.244.0.0/16, svc 10.0.0.0/16)
│     ├─ identityProfile.kubeletidentity → UAMI 위
│     └─ addonProfile.omsagent → law-ai200challenge-dev  (Container Insights)
│
├─ signed-in user
│     └─ RBAC: "Azure Kubernetes Service RBAC Cluster Admin" on aks  (for loop)
│
└─ acrai200challengedev04                       (Phase 1 ACR, existing 참조)

(클러스터 배포 후 kubectl 로 별도 배포)
aks-ai200challenge-dev
└─ Namespace ai200
      ├─ Deployment api (replicas=2, acrai200challengedev04.azurecr.io/api:0.1.0)
      │     ├─ readinessProbe /healthz:8000 (5s/10s)
      │     └─ livenessProbe  /healthz:8000 (15s/30s)
      ├─ Service api (ClusterIP :8000)
      └─ HorizontalPodAutoscaler api (CPU 50%, 1~5)
```

> **Phase 1/2 와의 관계**: ACR · LAW 만 재사용. ACA 와 AKS 가 동일한 `api:0.1.0` 이미지를 **각자 다른 런타임으로 돌려 보는** 구조.

---

## Bicep 모듈 맵

| 파일 | 책임 |
|---|---|
| `infra/phases/03-aks/main.bicep` | Phase 3 엔트리 (resourceGroup 스코프). Phase 1 ACR · Phase 2 LAW 를 네이밍 규칙으로 역산. |
| `infra/phases/03-aks/main.bicepparam` | 리전·환경·acrSuffix + **민감값 env var 주입** (`AZURE_TENANT_ID`, `AKS_ADMIN_OBJECT_IDS`) |
| `infra/phases/03-aks/k8s/api-deployment.yaml` | k8s 매니페스트 (Namespace/Deployment/Service/HPA). 이미지 경로는 `__ACR_LOGIN_SERVER__` 플레이스홀더 |
| `infra/modules/aks-cluster.bicep` | AKS 클러스터 1개. aadProfile, Azure CNI Overlay, kubelet UAMI 주입, Container Insights |
| `infra/modules/role-assignment-aks-cluster-admin.bicep` | principalId 1개에 "AKS RBAC Cluster Admin" 역할 부여 (AKS 스코프) |
| `infra/modules/user-assigned-identity.bicep` | **재사용** — UAMI |
| `infra/modules/role-assignment-acrpull.bicep` | **재사용** — UAMI → ACR `AcrPull` |

---

## 스텝별 Bicep 하이라이트

### 스텝 0 — 스코프 · 파라미터 · OSS 안전성

Phase 1 RG · Phase 2 LAW · Phase 1 ACR 이 이미 존재 → `targetScope = 'resourceGroup'`. 리소스 이름은 **항상 `projectId` / `environment` / `acrSuffix` 에서 derive** — bicepparam 에 개별 리소스의 고유 이름을 박지 않는다.

민감값(`aadTenantId`, `adminGroupObjectIDs`) 은 레포에 직접 커밋하면 안 되므로 **`readEnvironmentVariable(name, default)`** 패턴으로 주입한다. default 는 zero-GUID 플레이스홀더라 에디터 경고는 없지만 배포 시 AAD 가 거절 → "env export 없이 배포 금지" 게이트 유지.

```bicep
// infra/phases/03-aks/main.bicepparam
using 'main.bicep'

param location = 'koreacentral'
param environment = 'dev'
param projectId = 'ai200challenge'
param acrSuffix = '04'

// 민감값은 레포에 박지 않는다. 배포 전 셸에서 export 필요:
//   export AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
//   export AKS_ADMIN_OBJECT_IDS=$(az ad signed-in-user show --query id -o tsv)
// 여러 사용자를 admin 으로 지정하려면 쉼표로 구분:
//   export AKS_ADMIN_OBJECT_IDS='<guid1>,<guid2>'
param aadTenantId = readEnvironmentVariable('AZURE_TENANT_ID', '00000000-0000-0000-0000-000000000000')
param adminGroupObjectIDs = split(readEnvironmentVariable('AKS_ADMIN_OBJECT_IDS', '00000000-0000-0000-0000-000000000000'), ',')
```

```bicep
// infra/phases/03-aks/main.bicep
targetScope = 'resourceGroup'

var acrName = 'acr${projectId}${environment}${acrSuffix}'
var lawName = 'law-${projectId}-${environment}'
var uamiName = 'id-${projectId}-aks-${environment}'
var aksName = 'aks-${projectId}-${environment}'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: lawName
}
```

> **왜 ACR 은 `existing` 으로 잡지 않는가**: `acrName` 문자열만 있으면 모듈(`role-assignment-acrpull.bicep`) 안에서 existing 으로 참조하므로 상위 main 에선 중복 선언 불필요. LAW 는 `law.id` (resource ID) 를 AKS addon 에 넘겨야 해서 `existing` 이 필요.

### 스텝 1 — kubelet UAMI

```bicep
module uami '../../modules/user-assigned-identity.bicep' = {
  name: 'deploy-uami-aks'
  params: {
    name: uamiName
    location: location
    tags: commonTags
  }
}
```

> **왜 kubelet identity 에 UAMI 를 직접 주입하나**: `az aks create --attach-acr` 는 암묵적으로 UAMI 를 만들지만, Bicep 으로 그걸 재현하려면 결국 동일한 UAMI 를 선언해야 한다. 차라리 처음부터 UAMI 를 **먼저** 만들고 `identityProfile.kubeletidentity.resourceId` 로 명시 주입 → 재배포·drift 에 안정.

### 스텝 2 — UAMI → ACR AcrPull (Phase 1/2 모듈 재사용)

```bicep
module uamiAcrPull '../../modules/role-assignment-acrpull.bicep' = {
  name: 'ra-acrpull-aks-uami'
  params: {
    acrName: acrName
    principalId: uami.outputs.principalId
  }
}
```

### 스텝 3 — AKS 클러스터 (Entra ID + Azure RBAC + Azure CNI Overlay)

```bicep
// modules/aks-cluster.bicep (발췌)
resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: name
  location: location
  identity: { type: 'SystemAssigned' }            // control plane identity
  properties: {
    dnsPrefix: '${name}-dns'
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    enableRBAC: true
    disableLocalAccounts: true                    // kubeconfig 로컬 admin 금지

    aadProfile: {                                 // Entra ID 통합
      managed: true
      enableAzureRBAC: true                       // Azure RBAC 로 k8s 권한 관리
      tenantID: aadTenantId
      adminGroupObjectIDs: adminGroupObjectIDs    // 초기 admin (fallback)
    }

    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: systemNodeCount                    // 2
        vmSize: systemNodeVmSize                  // Standard_D2s_v3
        osType: 'Linux'
        osSKU: 'Ubuntu'
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: false
        osDiskType: 'Managed'
        osDiskSizeGB: 64
      }
    ]

    networkProfile: {                             // Azure CNI Overlay
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'none'
      loadBalancerSku: 'standard'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      podCidr: '10.244.0.0/16'
    }

    identityProfile: {                            // kubelet identity → UAMI
      kubeletidentity: {
        resourceId: kubeletIdentityId
        clientId: kubeletIdentityClientId
        objectId: kubeletIdentityPrincipalId
      }
    }

    addonProfiles: {                              // Container Insights
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
    }
  }
}
```

> **왜 Azure CNI Overlay 인가**: kubenet 은 deprecated (AKS 1.30+ 에서 경고), 풀 Azure CNI 는 각 pod 이 VNet IP 를 먹어 큰 서브넷이 필요. Overlay 는 pod CIDR (`10.244.0.0/16`) 을 VNet 밖에서 운용 → 중소 클러스터 기본값으로 적합.
>
> **`useAADAuth: 'true'` — 문자열** — Bicep 스키마상 omsagent config 는 모두 문자열 맵. `true` (bool) 로 넣으면 `InvalidTemplate`. KEDA metadata 와 같은 함정.

### 스텝 4 — Cluster Admin 역할 할당 (for loop)

`disableLocalAccounts=true` 환경에서는 Azure RBAC 역할 없이는 `kubectl` 도 안 된다. signed-in user (또는 팀) 에게 "AKS RBAC Cluster Admin" 역할을 클러스터 스코프로 부여.

```bicep
// modules/role-assignment-aks-cluster-admin.bicep (발췌)
var clusterAdminRoleId = 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' existing = {
  name: aksName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, principalId, clusterAdminRoleId)
  scope: aks
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', clusterAdminRoleId)
    principalId: principalId
    principalType: principalType
  }
}
```

```bicep
// infra/phases/03-aks/main.bicep
module aksAdmin '../../modules/role-assignment-aks-cluster-admin.bicep' = [for principalId in adminGroupObjectIDs: {
  name: 'ra-aks-admin-${uniqueString(principalId)}'
  params: {
    aksName: aks.outputs.name
    principalId: principalId
    principalType: adminPrincipalType
  }
}]
```

> **왜 `aadProfile.adminGroupObjectIDs` 만으로는 부족한가**: `adminGroupObjectIDs` 는 클러스터 인증(kubeconfig 발급) 레벨의 "AAD 그룹 admin" 이지, Azure RBAC 역할이 아니다. `enableAzureRBAC=true` 환경에서는 **둘 다 필요** — AAD 로 인증되더라도 Azure RBAC 역할이 없으면 `kubectl get nodes` 가 403. 그래서 같은 objectId 를 둘 다에 주입.

---

## 이미지 준비

Phase 1 에서 이미 `acrai200challengedev04.azurecr.io/api:0.1.0` 가 푸시되어 있으므로 **재빌드 불필요**. 확인만:

```bash
az acr repository show-tags --name acrai200challengedev04 --repository api --output table
```

---

## 배포

### 1) 민감값 env var 주입

```bash
export AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
export AKS_ADMIN_OBJECT_IDS=$(az ad signed-in-user show --query id -o tsv)

# 확인
echo "tenant:  $AZURE_TENANT_ID"
echo "admins:  $AKS_ADMIN_OBJECT_IDS"
```

> **둘 중 하나라도 누락되면 zero-GUID default 가 쓰이고, 배포는 AAD lookup 단계에서 실패**. 의도한 gate.

### 2) Bicep 컴파일 · what-if · 배포

```bash
# Bicep 컴파일 검증
az bicep build --file infra/phases/03-aks/main.bicep

# what-if (resourceGroup 스코프)
az deployment group what-if \
  --resource-group rg-ai200challenge-dev \
  --template-file infra/phases/03-aks/main.bicep \
  --parameters infra/phases/03-aks/main.bicepparam

# 실제 배포 (AKS 클러스터 생성은 5~10분 소요)
az deployment group create \
  --resource-group rg-ai200challenge-dev \
  --name phase3-$(date +%Y%m%d-%H%M%S) \
  --template-file infra/phases/03-aks/main.bicep \
  --parameters infra/phases/03-aks/main.bicepparam

# outputs 확인
az deployment group show \
  --resource-group rg-ai200challenge-dev \
  --name <방금-쓴-배포명> \
  --query properties.outputs
```

기대 outputs:

```json
{
  "aksFqdn":               { "value": "aks-ai200challenge-dev-dns-xxxxxxxx.hcp.koreacentral.azmk8s.io" },
  "aksName":               { "value": "aks-ai200challenge-dev" },
  "aksNodeResourceGroup":  { "value": "MC_rg-ai200challenge-dev_aks-ai200challenge-dev_koreacentral" },
  "getCredentialsCommand": { "value": "az aks get-credentials --resource-group rg-ai200challenge-dev --name aks-ai200challenge-dev --overwrite-existing" },
  "kubeletIdentityId":     { "value": "/subscriptions/.../userAssignedIdentities/id-ai200challenge-aks-dev" },
  "kubeletIdentityPrincipalId": { "value": "<guid>" }
}
```

---

## 검증 (스모크 테스트)

### 1) kubeconfig 획득 + 인증

```bash
az aks get-credentials \
  --resource-group rg-ai200challenge-dev \
  --name aks-ai200challenge-dev \
  --overwrite-existing

# disableLocalAccounts=true 이므로 AAD 흐름으로 인증됨
kubectl get nodes -o wide
```

기대: system 노드 2 개가 `Ready`. VM size `Standard_D2s_v3`. 최초 `kubectl` 명령에서 **device code flow** 가 뜰 수 있음 → 브라우저에서 인증 완료 후 다시 돌아오면 성공.

### 2) k8s 매니페스트 배포 (sed 로 ACR loginServer 치환)

```bash
ACR_LOGIN_SERVER="acrai200challengedev04.azurecr.io"

sed "s|__ACR_LOGIN_SERVER__|$ACR_LOGIN_SERVER|g" \
  infra/phases/03-aks/k8s/api-deployment.yaml \
  | kubectl apply -f -
```

기대:
```
namespace/ai200 created
deployment.apps/api created
service/api created
horizontalpodautoscaler.autoscaling/api created
```

### 3) Pod · Service · HPA 상태

```bash
kubectl -n ai200 get all
kubectl -n ai200 describe deployment api | head -40
kubectl -n ai200 logs deployment/api --tail=30
```

기대: 2 개 pod `Running`, uvicorn 로그 + `/healthz 200` 반복, HPA `TARGETS` 에 실제 CPU % 숫자 (처음엔 `<unknown>` → metrics-server 가 수집 시작하면 정상화).

### 4) Service 도달 확인 (port-forward)

ClusterIP 라서 외부 노출 없음. port-forward 로만 검증.

```bash
kubectl -n ai200 port-forward svc/api 18000:8000 &
PF_PID=$!

curl -s http://127.0.0.1:18000/healthz
# 기대: {"status":"ok"}

kill $PF_PID
```

### 5) Container Insights 로그 (Phase 2 LAW 에 함께 적재)

```bash
# 1~2 분 후 LAW 에 데이터 도달
LAW_ID=$(az monitor log-analytics workspace show \
  -g rg-ai200challenge-dev -n law-ai200challenge-dev \
  --query customerId -o tsv)

az monitor log-analytics query \
  --workspace "$LAW_ID" \
  --analytics-query "ContainerLogV2 | where PodNamespace == 'ai200' | project TimeGenerated, PodName, ContainerName, LogMessage | top 10 by TimeGenerated desc" \
  -o table
```

기대: ai200 네임스페이스 pod 의 stdout 로그가 LAW 의 `ContainerLogV2` 테이블에 적재되어 있음.

### DoD

- 1~5 모두 통과 시 Phase 3 완료. MS Learn 경로 3 모듈의 핵심 경로를 모두 밟은 상태.

---

## Phase 3 종료 — 비용 절감

AI-200 포트폴리오 목적이므로 검증 완료 후 클러스터를 멈춰 시간당 요금을 끊는다. 리소스는 남기되 control plane · node VM 이 dealloc 된다 → 포트폴리오 가시성은 유지.

```bash
# 정지 (control plane + node 모두 dealloc, ~몇 분 소요)
az aks stop \
  --resource-group rg-ai200challenge-dev \
  --name aks-ai200challenge-dev

# 상태 확인
az aks show \
  -g rg-ai200challenge-dev -n aks-ai200challenge-dev \
  --query powerState -o table

# 나중에 다시 검증할 때
az aks start \
  --resource-group rg-ai200challenge-dev \
  --name aks-ai200challenge-dev
```

> **`az aks stop` vs 클러스터 삭제**: stop 은 30일 내 재시작 가능, 상태 보존. 완전 삭제를 원하면 `az aks delete` + `az deployment group create` 재실행. 포트폴리오 용도라면 stop 이 최적.

---

## 함정 · 교훈 (배포 후 기록)

- **koreacentral 의 `DSv5 Family` 기본 쿼터는 0** — 처음엔 `Standard_D2s_v5 × 2` 로 선언했다가 `az deployment group what-if` 단계의 Preflight 에서 `ErrCode_InsufficientVCPUQuota — requested 4, remaining 0 for family standardDSv5Family` 로 거절. 이게 해당 구독의 개인 계정에만 오는 이슈가 아니라 **대부분의 subscription 에서 koreacentral DSv5 기본 한도가 0** (DSv4/DSv3 는 10). 해결: `Standard_D2s_v3` 로 갈아탐 → DSv3 Family 쿼터 10 안에서 4 vCPU 사용. 시험 관점 교훈은 "region × family 별 기본 쿼터가 제각각 → 배포 전 `az vm list-usage -l <region>` 로 limit 확인 필수". what-if 가 ARM 스키마 검증 + Preflight 쿼터 체크까지 돌려 주므로, 본 배포 전에 반드시 통과시켜야 함.
- **B-series 를 회피한 이유 정정** — 이전 문서 초안에 "B-series 는 ARM 제약" 이라 잘못 썼지만 B-series 는 Intel Burstable (x86). 실제 회피 이유는 **Burstable CPU credit 이 고갈되면 throttle 되어 AKS 학습용 메트릭/스케일 동작이 credit 잔량에 좌우** 되어 관측 결과가 일관되지 않게 보이는 것. DSv3 는 performance consistent.

---

## MS Learn 경로 커버리지 — 사용 / 생략

공식 경로: https://learn.microsoft.com/ko-kr/training/paths/deploy-monitor-apps-azure-kubernetes-service/ (3 모듈)

### 모듈 1 — AKS 에 애플리케이션 배포

| 영역 | 상태 | 비고 |
|---|---|---|
| AKS 클러스터 프로비저닝 (Entra ID + Azure RBAC) | ✓ | `aadProfile.managed=true` + `enableAzureRBAC=true` + `disableLocalAccounts=true` |
| kubelet identity (UAMI) + ACR 연동 | ✓ | `identityProfile.kubeletidentity` 에 UAMI 주입, UAMI 에 `AcrPull` |
| Namespace / Deployment / Service (ClusterIP) | ✓ | 매니페스트 `api-deployment.yaml` |
| Readiness / Liveness probe (HTTP) | ✓ | `/healthz:8000` |
| Horizontal Pod Autoscaler (CPU) | ✓ | CPU 50%, 1~5 |
| resource requests/limits | ✓ | cpu 250m~500m, memory 256Mi~512Mi |
| Service — LoadBalancer (public IP) | ✗ | 보조 클러스터라 외부 노출 불필요. `kubectl port-forward` 로 검증 |
| Service — NodePort | ✗ | LoadBalancer 와 같은 이유 |
| Ingress Controller (NGINX / AGIC) | ✗ | Phase 8 에서 Application Gateway Ingress Controller 검토 여지 |
| user nodepool 추가 (taint/toleration) | ✗ | 단일 system 풀로 충분. 시험 주제긴 하지만 실리 없음 |
| spot nodepool | ✗ | 학습 비용 관점에서 불필요 (시험 주제) |
| Cluster Autoscaler | ✗ | `enableAutoScaling=false`. HPA 만 사용 |

### 모듈 2 — AKS 에서 애플리케이션 구성

| 영역 | 상태 | 비고 |
|---|---|---|
| ConfigMap | ✗ | **Phase 8** App Configuration 과 통합해 구성하는 편이 일관. Phase 3 에서 먼저 쓰면 Phase 8 재작성 강요 |
| Secret (k8s 내장) | ✗ | **Phase 8** Key Vault + Secrets Store CSI Driver 로 대체 예정 |
| PersistentVolume / PersistentVolumeClaim | ✗ | 본 워크로드 stateless. Phase 5 PostgreSQL + Phase 6 Redis 가 상태 외부화 담당 |
| StorageClass (Azure Files / Disk CSI) | ✗ | PVC 요구 없음. 필요 시 Phase 8 에서 Key Vault CSI 와 같은 CSI 계통 학습 |
| StatefulSet | ✗ | 상태 외부화했으므로 필요 없음 |
| Init Container | ✗ | 초기화 로직 없음 |
| Network Policy (Calico / Azure) | ✗ | `networkPolicy: 'none'` — 단일 네임스페이스 내부 통신만. 시험 주제이지만 보조 클러스터라 과함 |
| Private Cluster | ✗ | 포트폴리오 범위 외 |

### 모듈 3 — AKS 모니터링 · 문제 해결

| 영역 | 상태 | 비고 |
|---|---|---|
| Container Insights 애드온 (omsagent) | ✓ | `addonProfiles.omsagent` → Phase 2 LAW 재사용, `useAADAuth: 'true'` |
| Pod 로그 (`kubectl logs`) + LAW `ContainerLogV2` | ✓ | 검증 5) KQL 쿼리로 확인 |
| 리소스 진단 (`kubectl describe` / `get events`) | ✓ | 검증 3) 에서 사용 |
| Azure Monitor 메트릭 (CPU / 메모리 / 네트워크) | ✓ | Container Insights 를 통해 자동 수집 |
| HPA 메트릭 (metrics-server) | ✓ | `kubectl get hpa` `TARGETS` 열 |
| Workload Identity (pod → Azure 리소스) | ✗ | **Phase 8** 에서 pod → Key Vault / Cosmos 연결 시 도입 |
| Azure AD Pod Identity (legacy) | ✗ | Deprecated. Workload Identity 로 대체 |
| Application Insights (APM) | ✗ | **Phase 9** Observability 에서 계측 |
| Prometheus 관리형 서비스 | ✗ | Container Insights 로 일관. 관리형 Prometheus 는 AI-200 주제 외 |
| `kubectl top` (metrics-server) | ✓ | 기본 활성 |

> **Phase 3 DoD 는 "배포 + Container Insights + Entra/RBAC"** 로 한정. ConfigMap/Secret/PVC/Workload Identity/Private Cluster 는 Phase 8 또는 별도 Phase 에서 재방문.

---

## 체크리스트

- [x] Phase 3 Bicep 모듈 2 개(`aks-cluster.bicep`, `role-assignment-aks-cluster-admin.bicep`) + main.bicep/param 작성
- [x] k8s 매니페스트 `api-deployment.yaml` 작성 (`__ACR_LOGIN_SERVER__` 플레이스홀더 + sed 치환 패턴)
- [x] `az bicep build` 경고 없음 (`az bicep build-params` 로 parametersJson + templateJson 클린 생성 확인)
- [ ] `AZURE_TENANT_ID` / `AKS_ADMIN_OBJECT_IDS` env export 후 `az deployment group what-if` 검토
- [ ] `az deployment group create` 로 Phase 3 배포 완료
- [ ] `az aks get-credentials` 후 `kubectl get nodes` Ready × 2 확인 (AAD device code flow 경험)
- [ ] `sed ... | kubectl apply -f -` 로 ai200 네임스페이스 배포, 2 pod Running
- [ ] `kubectl port-forward svc/api 18000:8000` 후 `/healthz` 200 확인
- [ ] Container Insights `ContainerLogV2` 에서 ai200 네임스페이스 로그 확인 (Phase 2 LAW 재사용 검증)
- [ ] `az aks stop` 으로 비용 절감 상태 전환
- [ ] 본 문서 "함정 · 교훈" 에 실제 삽질 기록 추가
