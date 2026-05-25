# session-07 — AKS 대안 배포

> 학습 경로 매핑: [Deploy and monitor apps on Azure Kubernetes Service](https://learn.microsoft.com/ko-kr/training/paths/deploy-monitor-apps-azure-kubernetes-service/)  
> 사전 조건: session-00~session-06 완료, `git checkout session-07-start`

---

## 0. 이 세션에서 무엇을 경험하나

- **한 문장 골**: 같은 워크로드 (embedding 재처리 워커) 를 AKS 위에 올려보고, ACA 와의 트레이드오프를 K8s 매니페스트·`kubectl`·Container Insights 로 직접 비교.
- **새로 프로비저닝되는 자원**:
  - AKS 클러스터 (Standard_D2s_v3 × 2)
  - Container Insights (**DCR + DCRA 명시 선언!**)
  - UAMI for kubelet (control plane 도 UserAssigned 강제)
  - ACR pull RBAC (kubelet 의 UAMI 가 ACR Pull)
- **사용해볼 SDK/CLI**:
  - `kubectl` (apply · get · logs · describe)
  - `az aks get-credentials`
  - K8s Job 매니페스트 (CronJob 이 아닌 일회성 Job)
- **Portal 에서 확인할 지표/데이터**:
  - AKS → Workloads — Job/Pod 노출
  - AKS → Insights — 노드/Pod 메트릭 (Container Insights 동작 검증)
  - AKS → Logs (KQL) — `ContainerLogV2`
  - Cosmos DB → Data Explorer — 워커가 재처리한 chunk

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈

- `aks-cluster.bicep` — DSv3 × 2, control plane **UserAssigned identity**, kubelet UAMI, Entra ID + Azure RBAC, `disableLocalAccounts=true`
- `aks-container-insights-dcr.bicep` — Data Collection Rule (KubeMonAgent, KubePodInventory, …)
- `aks-container-insights-dcra.bicep` — DCR Association (AKS ↔ DCR)
- `role-assignment-aks-acr-pull.bicep` — kubelet UAMI → ACR Pull

### 1.2 쿼터 확인 (배포 전 필수)

```bash
# DSv5 는 koreacentral 기본 쿼터 0 → DSv3 사용
az vm list-usage --location koreacentral -o table | grep -E "DSv3|Standard_D2s_v3"
# 최소 4 vCPU 가용 확인
```

### 1.3 배포

```bash
OID=$(az ad signed-in-user show --query id -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/07-aks/main.bicep \
  --parameters infra/sessions/07-aks/main.bicepparam \
  --parameters userObjectId=$OID

az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/07-aks/main.bicep \
  --parameters infra/sessions/07-aks/main.bicepparam \
  --parameters userObjectId=$OID
```

> ⏱ AKS 가 **8~12분** 으로 본 워크샵에서 session-03 Redis 와 함께 가장 오래. 진행되는 동안 §2 의 ACA vs AKS 트레이드오프 박스 + Bicep walkthrough 정독.
>
> 💰 **비용**: AKS LB + Public IP idle = ~₩1,125/일. 워크샵 끝나면 정리.

### 1.4 배포 완료 확인 & 자격증명

```bash
# 상태 확인
az aks show -n aks-ai200ws-dev -g rg-ai200ws-dev \
  --query "{state:powerState.code, version:kubernetesVersion}" -o jsonc

# kubeconfig 가져오기 (--admin 안 씀, Entra+Azure RBAC)
az aks get-credentials -n aks-ai200ws-dev -g rg-ai200ws-dev

kubectl get nodes
# 기대: 2개 노드 Ready
```

---

## 2단계 · 복붙으로 경험해보기

### 2.1 ACA vs AKS 트레이드오프

| 차원 | ACA (session-01) | AKS (session-07) |
|---|---|---|
| **추상화 수준** | 컨테이너만 (K8s 숨김) | 풀 K8s API |
| **세팅 비용** | 거의 0 | 클러스터 운영 학습 곡선 |
| **자동 스케일** | KEDA 내장 (HTTP, queue, …) | HPA/VPA/KEDA 별도 설정 |
| **idle 비용** | min replica 0 가능 (≈ 0) | LB+IP 최소 ~$1/일 |
| **mTLS · sidecar · CRD** | 제한 (Dapr 만) | 완전 자유 |
| **GPU · 특수 노드 풀** | 불가 (현 시점) | 가능 |
| **언제** | 표준 마이크로서비스, REST/gRPC | 복잡한 시스템 (mesh, CRD, GPU, multi-tenant) |

본 워크샵의 워커는 ACA 로도 충분합니다. 그래도 AKS 를 다루는 이유: **AI-200 시험 범위** + 실무에서 GPU 워크로드/복잡한 시스템 때 필요.

> 🎯 **AI-200 시험 포인트**: "ACA 와 AKS 중 선택?" → 추상화 vs 제어. 비즈니스가 K8s 의 모든 것이 필요한가?

### 2.2 코드 복사·붙여넣기

**파일 1**: `apps/worker/main.py`

```python
# (embedding 재처리 워커:
#  - 환경 변수 BATCH_SIZE, RUN_ONCE=true
#  - Cosmos 에서 embedding=null 인 chunk 를 모아 AOAI 로 다시 임베드
#  - 끝나면 exit 0 → K8s Job 이 Completed 상태로
#  실제 코드는 후속 구현.)
```

**파일 2**: `apps/worker/Dockerfile`

```dockerfile
# (Python 3.12-slim 베이스, --platform linux/amd64 안전,
#  azure-identity, azure-cosmos, openai 설치, ENTRYPOINT ["python", "main.py"])
```

**파일 3**: `infra/sessions/07-aks/manifests/worker-job.yaml`

```yaml
# (K8s Job 매니페스트:
#  - image: <acr>.azurecr.io/worker:s07
#  - serviceAccountName: worker-sa (Workload Identity 와 연결, 후속 구현)
#  - env: AZURE_CLIENT_ID = kubelet UAMI's clientId (Workload Identity)
#  - restartPolicy: OnFailure, backoffLimit: 3
#  - resources.requests/limits 명시)
```

### 2.3 빌드·푸시·실행

```bash
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)

# 1) 워커 이미지 빌드 (ARM Mac 필수 옵션)
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/worker:s07 apps/worker
az acr login --name $ACR_NAME
docker push $ACR_NAME.azurecr.io/worker:s07

# 2) Job 실행
kubectl apply -f infra/sessions/07-aks/manifests/worker-job.yaml

# 3) 진행 보기
kubectl get jobs -w
# Ctrl+C 후
kubectl get pods --selector=job-name=embedding-reprocess
kubectl logs -l job-name=embedding-reprocess --tail=50
```

**기대 출력 (logs)**:
```
[worker] starting, batch_size=32
[worker] fetched 12 chunks with null embedding
[worker] embedded 12/12, upserting to Cosmos
[worker] done, exit 0
```

---

## 3단계 · Azure Portal UI 에서 확인

1. **AKS** (`aks-ai200ws-dev`) → **Workloads** → Jobs 탭 → `embedding-reprocess` 가 `Completed` 상태로
2. **AKS** → **Workloads** → Pods 탭 → 해당 Job 의 Pod 가 `Succeeded`
3. **AKS** → **Insights** → 노드 메트릭 (CPU/Memory), Pod 메트릭. Container Insights 가 *정상 동작* 한다는 증거 = 데이터가 보임
   > ⚠️ 데이터가 비어있다면 DCR + DCRA 누락 (`주의` 섹션 참고)
4. **AKS** → **Logs** → 다음 KQL:
   ```kusto
   ContainerLogV2
   | where ContainerName == "worker"
   | order by TimeGenerated desc
   | take 100
   ```
   `[worker] embedded 12/12` 같은 로그 노출
5. **Cosmos DB** → Data Explorer → `SELECT VALUE COUNT(1) FROM c WHERE IS_NULL(c.embedding)` — 워커 실행 전 12, 후 0

---

## 주의 (Heads-up)

- ⚠️ **Custom kubelet identity 는 control plane 도 UserAssigned 강제** — 실패 시 `CustomKubeletIdentityOnlySupportedOnUserAssignedMSICluster`. **`what-if` 가 못 잡음** (배포 시점에 cryptic 에러)
- ⚠️ **`addonProfiles.omsagent` 만으론 LAW 에 데이터 안 흐름** — DCR + DCRA 명시 선언 필수. 이 함정으로만 *34시간 디버깅* (이전 학습 단계 측정). Container Insights → Insights 가 "no data" 면 99% 이 문제
- ⚠️ **`koreacentral` DSv5 vCPU 쿼터 = 0** — DSv3 사용. 쿼터 확인 후 배포
- ⚠️ **Burstable B-series 는 CPU 크레딧 throttling** — 메트릭이 왜곡되어 디버깅 어려워짐. 학습용이라도 DSv3 권장
- ⚠️ **Entra ID + Azure RBAC + `disableLocalAccounts=true`** — `az aks get-credentials --admin` 못 씀 (정상). 본인 AAD 사용자에 `Azure Kubernetes Service Cluster User Role` 필요
- 💰 **비용**: AKS LB + Public IP idle = ~₩1,125/일. 워크샵 끝나면 정리

---

## 마무리

- **save-point**: `git tag session-07-complete`
- **워크샵 종료**: 축하합니다! 이제 [docs/cleanup.md](../cleanup.md) 로 자원 정리를 수행하세요. 정리하지 않으면 Redis Enterprise (M10) + AKS 가 매일 약 ₩13K 누적됩니다
- **자격증 시험 가이드**: AI-200 시험은 본 워크샵의 8개 학습 경로를 다룹니다. 시험 직전 [학습 경로 매핑 표](../../README.md#ai-200-학습-경로-매핑) 를 다시 보면 좋습니다

---

## 참고 자료

- MS Learn: [Deploy and monitor apps on AKS](https://learn.microsoft.com/ko-kr/training/paths/deploy-monitor-apps-azure-kubernetes-service/)
- MS Learn: [Azure Workload Identity](https://learn.microsoft.com/ko-kr/azure/aks/workload-identity-overview)
- 본 레포: `infra/sessions/07-aks/main.bicep`, `apps/worker/`, `infra/sessions/07-aks/manifests/`
