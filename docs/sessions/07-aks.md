# session-07 (Azure Kubernetes Service 대안 배포)

👈 [session-06](./06-observability.md)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [session-00](./00-setup.md) ~ [session-06](./06-observability.md) 완료 — Azure OpenAI · Cosmos DB · Azure Container Registry(apps/api 이미지) · User Assigned Managed Identity · Log Analytics Workspace 가 본인 구독에 존재
> - 시작본 코드를 작업 폴더로 받기 — [시작본 코드 받기](#시작본-코드-받기) 참고
> - `kubectl` 1.30+ 설치 확인 — [PREREQUISITES.md](../../PREREQUISITES.md) 참고

---

## 시작본 코드 받기

[session-06](./06-observability.md) 결과물이 들어 있는 `workshop/` 위에 본 세션 시작본을 덮습니다.

```bash
# Linux · macOS · WSL
cp -a save-points/session-07/start/. workshop/
```

```powershell
# Windows PowerShell
Copy-Item -Path save-points/session-07/start/* -Destination workshop -Recurse -Force
```

이후 본 세션의 모든 명령은 `workshop/` 안에서 실행한다고 가정합니다.

학습자가 채우는 파일은 세 개입니다 — `infra/sessions/07-aks/main.bicep` (모듈 조립), `infra/sessions/07-aks/manifests/deployment.yaml` · `infra/sessions/07-aks/manifests/service.yaml` (K8s 매니페스트). apps/api 는 [session-01](./01-rag-mvp.md) 이미지를 그대로 재사용하므로 앱 코드 변경은 없습니다.

---

## 1 단계 : 프로비저닝

`workshop/infra/sessions/07-aks/main.bicep` 을 열고, 그룹별 주석을 찾아 코드를 채웁니다.

### 1.1 호출할 모듈 한눈에 보기

`infra/modules/session-07/` 에 완성되어 있는 모듈입니다.

```text
infra/modules/session-07/
├── aks-cluster.bicep                    # Workload Identity·Entra RBAC·disableLocalAccounts·CNI Overlay·omsagent
├── aks-container-insights-dcr.bicep     # Container Insights — DCR
├── aks-container-insights-dcra.bicep    # Container Insights — DCRA
├── federated-identity-credential.bicep  # 워크로드 SA ↔ session-00 User Assigned Managed Identity 신뢰 연결
├── role-assignment-acrpull.bicep        # AKS UAMI 에 AcrPull
├── role-assignment-mi-operator.bicep    # AKS UAMI 에 Managed Identity Operator
├── role-assignment-aks-cluster-user.bicep # 본인 계정에 Cluster User Role (kubeconfig 다운로드)
└── role-assignment-aks-rbac-admin.bicep   # 본인 계정에 RBAC Cluster Admin (kubectl 데이터플레인)
```

### 1.2 역할 + AKS 클러스터

`main.bicep` 의 `// -------- 1) 역할 — AKS UAMI 에 AcrPull + Managed Identity Operator 모듈 호출하기` 주석 아래에 `acrPull` · `miOperator` 두 모듈을 추가합니다.

```bicep
module acrPull '../../modules/session-07/role-assignment-acrpull.bicep' = {
  name: 'acrPull-aksUami'
  params: {
    acrName: acrName
    principalId: aksUami.properties.principalId
  }
}

module miOperator '../../modules/session-07/role-assignment-mi-operator.bicep' = {
  name: 'miOperator-aksUami'
  params: {
    targetUamiName: aksUamiName
    principalId: aksUami.properties.principalId
  }
}
```

`main.bicep` 의 `// -------- 2) AKS 클러스터 모듈 호출하기` 주석 아래에 `aks` 모듈을 추가합니다.

```bicep
module aks '../../modules/session-07/aks-cluster.bicep' = {
  name: 'aks'
  params: {
    name: aksName
    location: location
    aksUamiId: aksUami.id
    kubeletClientId: aksUami.properties.clientId
    kubeletObjectId: aksUami.properties.principalId
    logAnalyticsWorkspaceId: law.id
    tags: commonTags
  }
  dependsOn: [
    acrPull
    miOperator
  ]
}
```

### 1.3 Container Insights (DCR + DCRA)

`main.bicep` 의 `// -------- 3) Container Insights — DCR + DCRA 모듈 호출하기` 주석 아래에 `dcr` · `dcra` 두 모듈을 추가합니다.

```bicep
module dcr '../../modules/session-07/aks-container-insights-dcr.bicep' = {
  name: 'dcr'
  params: {
    name: dcrName
    location: location
    logAnalyticsWorkspaceId: law.id
    tags: commonTags
  }
}

module dcra '../../modules/session-07/aks-container-insights-dcra.bicep' = {
  name: 'dcra'
  params: {
    clusterName: aks.outputs.name
    dataCollectionRuleId: dcr.outputs.id
  }
}
```

### 1.4 Workload Identity + Cluster User Role + RBAC Cluster Admin + 출력

`main.bicep` 의 `// -------- 4) 워크로드 federated identity credential 모듈 호출하기` 주석 아래에 `fic` 모듈을 추가합니다.

```bicep
module fic '../../modules/session-07/federated-identity-credential.bicep' = {
  name: 'fic'
  params: {
    uamiName: uamiName
    name: 'aks-workload'
    issuer: aks.outputs.oidcIssuerUrl
    subject: 'system:serviceaccount:${workloadServiceAccount}'
  }
}
```

`main.bicep` 의 `// -------- 5) 배포 사용자에 Cluster User Role + RBAC Cluster Admin 모듈 호출하기` 주석 아래에 `clusterUser` · `clusterRbacAdmin` 두 모듈을 추가합니다.

```bicep
module clusterUser '../../modules/session-07/role-assignment-aks-cluster-user.bicep' = if (!empty(userObjectId)) {
  name: 'clusterUser-user'
  params: {
    clusterName: aks.outputs.name
    principalId: userObjectId
  }
}

// Cluster User Role 은 kubeconfig 다운로드만 허용. enableAzureRBAC=true 클러스터의 실제
// kubectl get/apply 에는 RBAC 데이터플레인 역할(RBAC Cluster Admin)이 추가로 필요하다.
module clusterRbacAdmin '../../modules/session-07/role-assignment-aks-rbac-admin.bicep' = if (!empty(userObjectId)) {
  name: 'clusterRbacAdmin-user'
  params: {
    clusterName: aks.outputs.name
    principalId: userObjectId
  }
}
```

`main.bicep` 의  `// -------- 출력` 주석 아래에 출력 3개를 추가합니다.

```bicep
output aksName string = aks.outputs.name
output oidcIssuerUrl string = aks.outputs.oidcIssuerUrl
output acrName string = acrName
```

### 1.5 할당량 확인 + 조립 검증 + 배포

```bash
# DSv5 는 koreacentral 기본 vCPU 할당량이 0 이므로 DSv3 사용. 최소 4 vCPU 가용 확인
az vm list-usage --location koreacentral -o table | grep -E "DSv3"
```

```bash
az bicep build --file infra/sessions/07-aks/main.bicep --outfile /tmp/main.json && echo "BUILD OK"
```

```bash
OID=$(az ad signed-in-user show --query id -o tsv)
az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/07-aks/main.bicep \
  --parameters infra/sessions/07-aks/main.bicepparam \
  --parameters userObjectId=$OID
```

> [!NOTE]
> AKS 클러스터 생성에 약 **8~12분** 소요됩니다.

### 1.6 배포 확인 + kubeconfig

```bash
AKS=$(az aks list -g rg-ai200ws-dev --query "[0].name" -o tsv)
az aks show -n $AKS -g rg-ai200ws-dev --query "{state:powerState.code, version:kubernetesVersion}" -o jsonc

# --admin 사용 안 함 — Entra ID + Azure RBAC (Cluster User Role)
az aks get-credentials -n $AKS -g rg-ai200ws-dev
kubectl get nodes
```

기대 — `state: Running`, 노드 2개 `Ready`.

---

## 2 단계 : 복붙으로 경험해보기

### 2.1 매니페스트 작성

`infra/sessions/07-aks/manifests/` 의 `deployment.yaml` 와 `service.yaml` 가 stub 으로 비어 있습니다 — 아래 내용으로 채웁니다. 같은 폴더의 `serviceaccount.yaml` · `configmap.yaml` · `container-insights-config.yaml` 은 제공됩니다. apps/api 이미지를 그대로 올리되, **Workload Identity** label 로 파드가 시크릿 없이 Azure 자원에 접근하게 합니다.

`infra/sessions/07-aks/manifests/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apps-api
  namespace: default
  labels:
    app: apps-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: apps-api
  template:
    metadata:
      labels:
        app: apps-api
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: apps-api-sa
      containers:
        - name: api
          image: __ACR_LOGIN_SERVER__/api:s01
          ports:
            - containerPort: 8000
          envFrom:
            - configMapRef:
                name: apps-api-config
          env:
            - name: AZURE_CLIENT_ID
              value: "__UAMI_CLIENT_ID__"
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 20
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 500m
              memory: 1Gi
```

`infra/sessions/07-aks/manifests/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: apps-api
  namespace: default
spec:
  type: LoadBalancer
  selector:
    app: apps-api
  ports:
    - port: 80
      targetPort: 8000
```

### 2.2 placeholder 치환 + 배포

매니페스트의 `__ACR_LOGIN_SERVER__` · `__UAMI_CLIENT_ID__` · `__AOAI_ENDPOINT__` · `__COSMOS_ENDPOINT__` 를 `az` 로 조회한 실제 값으로 치환합니다. 사용하는 셸에 맞는 블록 하나만 실행합니다. placeholder 가 없는 `service.yaml` · `container-insights-config.yaml` 은 그대로 둡니다.

```bash
# Linux · macOS · WSL
RG=rg-ai200ws-dev
ACR_LOGIN_SERVER=$(az acr list -g $RG --query "[0].loginServer" -o tsv)
UAMI_CLIENT_ID=$(az identity show -n id-ai200ws-dev -g $RG --query clientId -o tsv)
ACCT=$(az cognitiveservices account list -g $RG --query "[0].name" -o tsv)
AOAI_ENDPOINT=$(az cognitiveservices account show -n $ACCT -g $RG --query "properties.endpoint" -o tsv)
COSMOS=$(az cosmosdb list -g $RG --query "[0].name" -o tsv)
COSMOS_ENDPOINT=$(az cosmosdb show -n $COSMOS -g $RG --query "documentEndpoint" -o tsv)

# sed -i 는 GNU(Linux)·BSD(macOS) 동작이 달라, 두 OS 에서 동일한 perl 로 제자리 치환 (perl 은 기본 탑재).
perl -i -pe "s|__ACR_LOGIN_SERVER__|$ACR_LOGIN_SERVER|g; s|__UAMI_CLIENT_ID__|$UAMI_CLIENT_ID|g; s|__AOAI_ENDPOINT__|$AOAI_ENDPOINT|g; s|__COSMOS_ENDPOINT__|$COSMOS_ENDPOINT|g" \
  infra/sessions/07-aks/manifests/*.yaml
```

```powershell
# Windows PowerShell
$RG = "rg-ai200ws-dev"
$ACR_LOGIN_SERVER = az acr list -g $RG --query "[0].loginServer" -o tsv
$UAMI_CLIENT_ID = az identity show -n id-ai200ws-dev -g $RG --query clientId -o tsv
$ACCT = az cognitiveservices account list -g $RG --query "[0].name" -o tsv
$AOAI_ENDPOINT = az cognitiveservices account show -n $ACCT -g $RG --query "properties.endpoint" -o tsv
$COSMOS = az cosmosdb list -g $RG --query "[0].name" -o tsv
$COSMOS_ENDPOINT = az cosmosdb show -n $COSMOS -g $RG --query "documentEndpoint" -o tsv

Get-ChildItem infra/sessions/07-aks/manifests/*.yaml | ForEach-Object {
  (Get-Content $_) `
    -replace '__ACR_LOGIN_SERVER__', $ACR_LOGIN_SERVER `
    -replace '__UAMI_CLIENT_ID__', $UAMI_CLIENT_ID `
    -replace '__AOAI_ENDPOINT__', $AOAI_ENDPOINT `
    -replace '__COSMOS_ENDPOINT__', $COSMOS_ENDPOINT | Set-Content $_
}
```

```bash
# 적용 — ServiceAccount · ConfigMap · Deployment · Service · Container Insights 에이전트 ConfigMap
kubectl apply -f infra/sessions/07-aks/manifests/
```

`container-insights-config.yaml` 은 Container Insights 에이전트 ConfigMap(`container-azm-ms-agentconfig`, `kube-system`) 으로, 컨테이너 stdout/stderr 로그를 신규 `ContainerLogV2` 스키마로 수집하도록 설정합니다. 에이전트가 이 설정을 반영하려면 재시작이 필요합니다.

```bash
# Container Insights 에이전트가 ContainerLogV2 스키마 설정을 반영하도록 재시작
kubectl rollout restart daemonset/ama-logs deployment/ama-logs-rs -n kube-system
```

```bash
# Pod 가 Ready 인지, LoadBalancer 외부 IP 가 할당됐는지 확인
kubectl get pods -l app=apps-api
kubectl get service apps-api -w   # EXTERNAL-IP 가 <pending> → IP 로 바뀌면 Ctrl+C
```

### 2.3 호출 테스트

```bash
LB_IP=$(kubectl get service apps-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -sX POST "http://$LB_IP/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q":"휴가 규정 알려줘"}' | jq .
```

기대 — session-01 의 Azure Container Apps 와 동일한 RAG 응답(answer + sources). 같은 이미지가 다른 호스트에서 동작합니다.

---

## 3 단계 : Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **AKS** → **Workloads** → **Deployments** → `apps-api` 가 2/2 Ready

   ![apps-api Deployment 가 2/2 Ready 상태인 Workloads 화면을 보여 주는 Azure Portal 스크린샷](images/session-07/3a-aks-workloads-deployment-ready.png)

   `kubectl apply` 로 배포한 `apps-api` Deployment 가 Workloads 블레이드의 **Deployments** 탭에 **Ready 2/2** 로 표시되는지 확인합니다. Pods 탭에서 두 파드 모두 **Running** 상태인지도 함께 확인합니다.

2. **AKS** → **Services and ingresses** → `apps-api` 의 External IP 노출

   ![apps-api Service 에 External IP 가 할당된 Services and ingresses 화면을 보여 주는 Azure Portal 스크린샷](images/session-07/3b-aks-service-external-ip.png)

   `apps-api` Service 의 Type 이 **Load balancer** 이고, External IP 가 [2.3 호출 테스트](#23-호출-테스트) 에서 사용한 `LB_IP` 와 같은 값인지 확인합니다.

3. **AKS** → **Insights** → 노드 · Pod 메트릭 (Container Insights 동작 증거)

   ![노드와 Pod 의 CPU·메모리 메트릭 차트가 표시된 AKS Insights 화면을 보여 주는 Azure Portal 스크린샷](images/session-07/3c-aks-insights-node-pod-metrics.png)

   노드 2개와 `apps-api` Pod 의 CPU·메모리 사용량 차트에 데이터가 채워져 있는지 확인합니다. 차트가 보이면 DCR + DCRA 로 선언한 Container Insights 가 정상 동작한다는 증거입니다.

4. **AKS** → **Logs** 에서 KQL 실행

   ```kusto
   ContainerLogV2
   | where ContainerName == "api"
   | order by TimeGenerated desc
   | take 100
   ```

   > [!NOTE]
   > `ContainerLogV2` 는 [2.2 placeholder 치환 + 배포](#22-placeholder-치환--배포) 에서 적용한 `container-insights-config.yaml` 과 에이전트 재시작 이후 몇 분(첫 수집까지 약 5~15분) 지나야 채워집니다. 재배포 직후 즉시 조회하면 빈 결과일 수 있으므로 잠시 기다린 뒤 다시 실행합니다.

   ![ContainerLogV2 테이블 KQL 결과로 api 컨테이너 로그가 조회된 Logs 화면을 보여 주는 Azure Portal 스크린샷](images/session-07/3d-aks-logs-containerlogv2.png)

   쿼리 결과에 `api` 컨테이너의 최근 로그 행이 표시되는지 확인합니다. 행이 비어 있다면 `container-insights-config.yaml` 적용·에이전트 재시작 이후 수집이 시작되기까지 몇 분 기다렸는지, 또는 로그가 레거시 `ContainerLog` 테이블로 흘러가고 있지 않은지 확인합니다.

5. (검증) `kubectl logs -l app=apps-api --tail=50` — Workload Identity 로 Azure OpenAI · Cosmos 호출이 성공하는지 (인증 오류 없이 RAG 응답)

---

## 마무리

- **save-point** — 본 세션의 모든 변경은 `save-points/session-07/complete/` 와 일치합니다. 본 세션이 챌린지의 마지막 세션이므로 다음 `cp -a` 는 없습니다
- **챌린지 종료** — 모든 자원 정리는 [docs/cleanup.md](../cleanup.md) 절차를 참고합니다. 정리하지 않으면 AKS Load Balancer · Managed Redis 등 idle 자원이 매일 누적되므로 즉시 정리를 권장합니다
- **자격증 시험 가이드** — Azure AI-200 시험은 본 챌린지 8개 학습 경로 전부를 커버합니다. 응시 전 [README.md](../../README.md) 의 학습 경로 매핑 표를 다시 살펴보고 각 Microsoft Learn 모듈을 정독하는 것을 권장합니다

---

👈 [session-06](./06-observability.md) | [챌린지 홈](../../README.md) 👉