# session-07 — Azure Kubernetes Service 대안 배포

> **관련 Microsoft Learn 학습 경로**
>
> - [Deploy and monitor apps on Azure Kubernetes Service](https://learn.microsoft.com/ko-kr/training/paths/deploy-monitor-apps-azure-kubernetes-service/)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [session-00](./00-setup.md) ~ [session-06](./06-observability.md) 완료 — Azure OpenAI · Cosmos DB · Azure Container Registry · User Assigned Managed Identity · Log Analytics Workspace 가 본인 구독에 존재
> - 시작본 코드를 작업 폴더로 받기: `cp -a save-points/session-07/start/. workshop/` (자세한 안내는 §시작본 코드 받기)
> - `kubectl` 1.30+ 설치 확인 — [PREREQUISITES.md 의 도구 버전 요구사항](../../PREREQUISITES.md#41-도구-버전-요구사항) 참고

---

## 0. 이 세션에서 경험하는 내용

- **한 문장 골** — 같은 embedding 재처리 워커로드를 Azure Container Apps 대신 Azure Kubernetes Service Job 으로 배포해보고, 두 호스팅 모델의 트레이드오프를 K8s 매니페스트 · `kubectl` · Container Insights 로 직접 비교
- **새로 프로비저닝되는 자원**
  - Azure Kubernetes Service 클러스터 `aks-ai200ws-dev` (Standard_D2s_v3 노드 2개, Entra ID + Azure RBAC, `disableLocalAccounts=true`)
  - User Assigned Managed Identity for kubelet — control plane identity 도 UserAssigned 강제
  - Container Insights — DCR (Data Collection Rule) + DCRA (Data Collection Rule Association) 명시 선언
  - Azure Container Registry pull RBAC — kubelet 의 User Assigned Managed Identity 가 `AcrPull` 보유
- **사용해볼 SDK / CLI**
  - `kubectl` — `apply` · `get` · `logs` · `describe`
  - `az aks get-credentials` — kubeconfig 가져오기 (`--admin` 사용 안 함, Entra ID + Azure RBAC)
  - K8s Job 매니페스트 — CronJob 이 아닌 일회성 Job
- **Portal 에서 확인할 지표 / 데이터**
  - Azure Kubernetes Service → Workloads — Job · Pod 노출
  - Azure Kubernetes Service → Insights — 노드 · Pod 메트릭 (Container Insights 동작 검증)
  - Azure Kubernetes Service → Logs (KQL) — `ContainerLogV2` 테이블 조회
  - Cosmos DB → Data Explorer — 워커가 재처리한 chunk 확인

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈 한눈에 보기

이 세션이 배포하는 Bicep 모듈 (`infra/sessions/07-aks/main.bicep`).

- `aks-cluster.bicep` — Standard_D2s_v3 노드 2개, control plane UserAssigned identity, kubelet UserAssigned identity, Entra ID + Azure RBAC, `disableLocalAccounts=true`
- `aks-container-insights-dcr.bicep` — Data Collection Rule (KubeMonAgent, KubePodInventory, … 데이터 스트림 정의)
- `aks-container-insights-dcra.bicep` — Data Collection Rule Association (Azure Kubernetes Service ↔ DCR 연결)
- `role-assignment-aks-acr-pull.bicep` — kubelet 의 User Assigned Managed Identity 에 `AcrPull` 역할 부여

### 1.2 할당량 확인 (배포 전 필수)

```bash
# DSv5 는 koreacentral 기본 vCPU 할당량이 0 이므로 DSv3 사용. 최소 4 vCPU 가용 확인
az vm list-usage \
  --location koreacentral \
  -o table | grep -E "DSv3|Standard_D2s_v3"
```

### 1.3 변경사항 미리보기

```bash
OID=$(az ad signed-in-user show --query id -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/07-aks/main.bicep \
  --parameters infra/sessions/07-aks/main.bicepparam \
  --parameters userObjectId=$OID
```

### 1.4 실제 배포

```bash
az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/07-aks/main.bicep \
  --parameters infra/sessions/07-aks/main.bicepparam \
  --parameters userObjectId=$OID
```

> [!NOTE]
> Azure Kubernetes Service 클러스터 생성에 약 **8~12분** 소요됩니다. session-03 의 Managed Redis 와 함께 본 워크샵에서 가장 오래 걸리는 배포입니다. 진행되는 동안 [2단계 · 복붙으로 경험해보기](#2단계--복붙으로-경험해보기) 의 트레이드오프 박스와 Bicep walkthrough 부분을 정독합니다.

> [!CAUTION]
> **비용 안내** — Azure Kubernetes Service Load Balancer + Public IP 가 idle 상태에서도 약 ₩1,125/일 발생합니다. 본 세션 학습이 끝나면 [자원 정리](../cleanup.md) 의 `session-07 의 AKS 만 정리` 절차로 즉시 정리하는 것을 권장합니다.

### 1.5 배포 완료 확인 + kubeconfig 가져오기

```bash
# 1) Azure Kubernetes Service 상태 확인
az aks show \
  --name aks-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --query "{state:powerState.code, version:kubernetesVersion, fqdn:fqdn}" -o jsonc
```

기대 — `state: Running`.

```bash
# 2) kubeconfig 가져오기 — --admin 사용 안 함, Entra ID + Azure RBAC 흐름
az aks get-credentials \
  --name aks-ai200ws-dev \
  --resource-group rg-ai200ws-dev

# 3) 노드 상태 확인
kubectl get nodes
```

기대 — 2개 노드가 `Ready` 상태.

---

## 2단계 · 복붙으로 경험해보기

### 2.1 Azure Container Apps 와 Azure Kubernetes Service 트레이드오프

| 차원 | Azure Container Apps ([session-01](./01-rag-mvp.md) 사용) | Azure Kubernetes Service (본 세션) |
|---|---|---|
| **추상화 수준** | 컨테이너만 다룸 — K8s 내부 숨김 | 풀 K8s API 노출 |
| **세팅 비용** | 거의 0 | 클러스터 운영 학습 곡선 |
| **자동 스케일** | KEDA 내장 (HTTP · queue · …) | HPA · VPA · KEDA 별도 설정 |
| **idle 비용** | min replica 0 가능 (사실상 0) | Load Balancer + Public IP 최소 ~$1/일 |
| **mTLS · sidecar · CRD** | 제한적 (Dapr 통해서만) | 완전 자유 |
| **GPU · 특수 노드 풀** | 현재 시점 미지원 | 지원 |
| **언제 사용하면 좋은가** | 표준 마이크로서비스 · REST · gRPC | 복잡한 시스템 (service mesh · CRD · GPU 워크로드 · multi-tenant) |

본 워크샵의 embedding 재처리 워커는 Azure Container Apps 만으로도 충분히 호스팅 가능합니다. 그럼에도 Azure Kubernetes Service 를 다루는 이유는 **AI-200 시험 범위에 포함** 되며, 실무에서 GPU 워크로드 또는 복잡한 시스템 (service mesh · CRD 활용) 이 필요할 때 선택지가 되기 때문입니다.

> [!TIP]
> **시험 단골 패턴** — "Azure Container Apps 와 Azure Kubernetes Service 중 어느 쪽을 선택할 것인가?" 는 *추상화* 와 *제어* 의 트레이드오프 질문입니다. 비즈니스 요구가 K8s 의 모든 기능을 필요로 하지 않는다면 Azure Container Apps 가 운영 부담이 훨씬 낮습니다.

### 2.2 코드 복사·붙여넣기

> [!NOTE]
> 아래 세 파일을 그대로 복사해 해당 경로에 붙여넣습니다. 동작 원리는 코드 다음의 줄별 해설에서 다룹니다.

**파일 1** — `apps/worker/main.py`

```python
# (embedding 재처리 워커.
#  핵심 구성:
#  - 환경변수 BATCH_SIZE, RUN_ONCE=true
#  - DefaultAzureCredential 로 Cosmos DB · Azure OpenAI 양쪽 인증
#  - Cosmos DB 에서 embedding 이 null 인 chunk 를 BATCH_SIZE 만큼 가져옴
#  - Azure OpenAI text-embedding-3-large 로 재임베드
#  - Cosmos DB upsert
#  - 처리할 chunk 가 없으면 exit 0 → K8s Job 이 Completed 상태로 종료
#  실제 코드 본문은 후속 구현 단계에서 작성합니다.)
```

**파일 2** — `apps/worker/Dockerfile`

```dockerfile
# (Python 3.12-slim 베이스.
#  ARM Mac 환경에서도 --platform linux/amd64 로 빌드.
#  azure-identity, azure-cosmos, openai 설치.
#  ENTRYPOINT ["python", "main.py"])
```

**파일 3** — `infra/sessions/07-aks/manifests/worker-job.yaml`

```yaml
# (K8s Job 매니페스트.
#  핵심 구성:
#  - image: <acr>.azurecr.io/worker:s07
#  - serviceAccountName: worker-sa (Workload Identity 와 연결, 후속 구현 단계에서 완성)
#  - env: AZURE_CLIENT_ID = kubelet User Assigned Managed Identity 의 clientId
#  - restartPolicy: OnFailure
#  - backoffLimit: 3
#  - resources.requests / limits 명시 (200m CPU, 256Mi memory 예시))
```

### 2.3 빌드 · 푸시 · Job 실행

```bash
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)

# 1) Azure Container Registry 로그인
az acr login --name $ACR_NAME

# 2) 워커 이미지 빌드 — ARM Mac 환경 안전을 위해 --platform 옵션 필수
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/worker:s07 apps/worker
docker push $ACR_NAME.azurecr.io/worker:s07

# 3) Job 실행
kubectl apply -f infra/sessions/07-aks/manifests/worker-job.yaml

# 4) Job 진행 상황 보기 (Ctrl+C 로 빠져나옴)
kubectl get jobs -w
```

```bash
# 5) Job 안의 Pod 상태 확인
kubectl get pods --selector=job-name=embedding-reprocess

# 6) Pod 로그 확인
kubectl logs -l job-name=embedding-reprocess --tail=50
```

기대 출력 (logs).

```
[worker] starting, batch_size=32
[worker] fetched 12 chunks with null embedding
[worker] embedded 12/12, upserting to Cosmos DB
[worker] done, exit 0
```

---

## 3단계 · Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **Azure Kubernetes Service `aks-ai200ws-dev`** → **Workloads** → **Jobs** 탭 → `embedding-reprocess` Job 이 `Completed` 상태
2. **Azure Kubernetes Service** → **Workloads** → **Pods** 탭 → 해당 Job 의 Pod 가 `Succeeded` 상태
3. **Azure Kubernetes Service** → **Insights** → 노드 메트릭 (CPU · Memory) · Pod 메트릭. Container Insights 가 정상 동작한다는 증거 — 데이터가 보임

   > [!WARNING]
   > 이 화면이 비어 있다면 DCR + DCRA 누락 함정에 빠진 상태입니다 — [주의](#주의) 섹션 참고.

4. **Azure Kubernetes Service** → **Logs** → 다음 KQL 실행

   ```kusto
   ContainerLogV2
   | where ContainerName == "worker"
   | order by TimeGenerated desc
   | take 100
   ```

   `[worker] embedded 12/12` 같은 로그가 노출되어야 합니다.

5. **Cosmos DB** → **Data Explorer** → 다음 쿼리 실행

   ```sql
   SELECT VALUE COUNT(1) FROM c WHERE IS_NULL(c.embedding)
   ```

   워커 실행 전에는 12 (예시), 워커 실행 후에는 0 으로 줄어들어야 합니다.

---

## 주의

> [!CAUTION]
> **Custom kubelet identity 사용 시 control plane identity 도 UserAssigned 강제** — 한쪽만 UserAssigned 로 설정하면 배포 시점에 `CustomKubeletIdentityOnlySupportedOnUserAssignedMSICluster` 오류가 발생합니다. `what-if` 가 이 오류를 사전에 잡지 못하므로, Bicep 작성 시 양쪽 모두 `identity: { type: 'UserAssigned' }` 로 명시합니다.

> [!CAUTION]
> **`addonProfiles.omsagent` 단독으로는 Log Analytics Workspace 에 데이터가 흐르지 않음** — 최신 Container Insights 는 DCR (Data Collection Rule) + DCRA (Data Collection Rule Association) 둘 다 명시 선언이 필요합니다. 이 함정으로 인한 디버깅에 가장 오래 걸린 사례는 약 34시간 소요되었습니다. Azure Kubernetes Service → Insights 화면이 "no data" 라면 99% 이 함정이 원인입니다.

> [!WARNING]
> **`koreacentral` DSv5 vCPU 할당량 = 0** — Azure Kubernetes Service 배포 시 quota exceeded 오류가 발생합니다. DSv5 Family 의 기본 할당량은 0 이므로 별도 신청이 필요하며, 본 워크샵은 DSv3 (기본 10 vCPU) 를 사용합니다.

> [!NOTE]
> **Burstable B-series 는 CPU 크레딧 throttling** — 메트릭이 왜곡되어 디버깅이 어려워집니다. 학습용이라도 DSv3 사용을 권장합니다.

> [!WARNING]
> **Entra ID + Azure RBAC + `disableLocalAccounts=true`** — `az aks get-credentials --admin` 명령은 사용할 수 없습니다 (정상 동작). 본인 Entra ID 사용자에 `Azure Kubernetes Service Cluster User Role` 역할이 부여되어 있어야 `kubectl` 명령이 동작합니다. 본 워크샵의 Bicep 은 배포 시점에 해당 역할을 자동 부여합니다.

> [!IMPORTANT]
> 더 자세한 함정 모음은 [docs/pitfalls/common.md](../pitfalls/common.md) 의 [Azure Kubernetes Service](../pitfalls/common.md#azure-kubernetes-service) 섹션을 참고합니다.

---

## 마무리

- **save-point** — 본 세션의 모든 변경은 `save-points/session-07/complete/` 와 일치합니다. 본 세션이 워크샵의 마지막 세션이므로 다음 `cp -a` 는 없습니다. [자원 정리](../cleanup.md) 절차를 진행합니다
- **워크샵 종료** — 본 세션이 마지막 세션입니다. 모든 자원의 정리는 [docs/cleanup.md](../cleanup.md) 의 절차를 참고합니다. 정리하지 않으면 Azure Kubernetes Service Load Balancer · Managed Redis Memory_M10 등 idle 자원이 매일 누적되므로 즉시 정리를 권장합니다
- **자격증 시험 가이드** — Azure AI-200 시험은 본 워크샵에서 다룬 8개 학습 경로 전부를 커버합니다. 시험 응시 전 [README.md 의 AI-200 학습 경로 매핑](../../README.md#ai-200-학습-경로-매핑) 표를 다시 살펴보고, 각 학습 경로 안의 Microsoft Learn 모듈을 정독하는 것을 권장합니다

---

## 참고 자료

- Microsoft Learn — [Deploy and monitor apps on Azure Kubernetes Service](https://learn.microsoft.com/ko-kr/training/paths/deploy-monitor-apps-azure-kubernetes-service/)
- Microsoft Learn — [Azure Workload Identity](https://learn.microsoft.com/ko-kr/azure/aks/workload-identity-overview)
- 본 저장소 — `infra/sessions/07-aks/main.bicep`, `apps/worker/`, `infra/sessions/07-aks/manifests/`

---

👈 [session-06 — Observability 심화](./06-observability.md) | [자원 정리](../cleanup.md) 👉
