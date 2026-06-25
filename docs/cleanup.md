# 자원 정리

챌린지 세션이 끝났으면 **즉시 정리**합니다. compute 자원은 유휴(idle) 상태에서도 비용이 누적됩니다.

---

## 빠른 정리 — 리소스 그룹 통째로

가장 단순한 방법: 리소스 그룹을 통째로 삭제합니다.

```bash
az group delete \
  --name rg-ai200ws-dev \
  --yes \
  --no-wait
```

```powershell
# Windows PowerShell
az group delete `
  --name rg-ai200ws-dev `
  --yes `
  --no-wait
```

> [!WARNING]
> **삭제 후 재배포 시 이름 충돌 주의** — 아래 자원은 삭제 후에도 이름이 일정 기간 예약됩니다.
>
> | 자원 | soft-delete | purge 방법 | 비고 |
> |---|---|---|---|
> | **Key Vault** | 7일~ | ❌ `enablePurgeProtection: true` — purge 불가 | **절대 삭제 금지**. 삭제하면 이름 7일 이상 잠김, 재생성 불가 |
> | **Azure OpenAI** | 48시간 | ✅ `az cognitiveservices account purge --name <name> -g <rg> --location <region>` | 삭제 직후 즉시 purge 실행 필수 |
> | **App Configuration** | ~12분 | ✅ `az appconfig purge --name <name> --location <region> --yes` | `disableLocalAuth` store. 삭제만 하면 같은 이름(`uniqueString` 고정 시드) 재배포가 `NameUnavailable` 로 충돌 → 삭제 직후 즉시 purge. Key Vault 와 달리 purge protection 없어 purge 가능 |
> | **Log Analytics Workspace** | 14일 (데이터) | ✅ 삭제 시 `--force` 플래그 추가 | `--force` 없으면 데이터 보존(복구 가능), 이름은 해제됨 |
> | 기타 (Cosmos DB, PostgreSQL, Managed Redis, Azure Container Apps 등) | 없음 | — | 즉시 이름 해제. Cosmos DB 는 백엔드 정리에 수 분 소요 |

---

## 세션별 부분 정리 (특정 세션만 다시 진행하고 싶을 때)

학습 흐름을 유지하면서 **비싼 자원만** 정리하고 싶을 때 권장:

### session-03 의 Redis 만 정리

```bash
az redisenterprise delete \
  --name redis-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --yes
```

```powershell
# Windows PowerShell
az redisenterprise delete `
  --name redis-ai200ws-dev `
  --resource-group rg-ai200ws-dev `
  --yes
```

### session-07 의 AKS 만 정리 + 자동 생성된 `MC_...` 리소스 그룹

```bash
az aks delete \
  --name aks-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --yes --no-wait

# `MC_rg-ai200ws-dev_aks-ai200ws-dev_koreacentral` 는 AKS 삭제 시 자동 정리됨
# 안 되면 수동으로:
# az group delete --name MC_rg-ai200ws-dev_aks-ai200ws-dev_koreacentral --yes --no-wait
```

```powershell
# Windows PowerShell
az aks delete `
  --name aks-ai200ws-dev `
  --resource-group rg-ai200ws-dev `
  --yes --no-wait

# `MC_rg-ai200ws-dev_aks-ai200ws-dev_koreacentral` 는 AKS 삭제 시 자동 정리됨
# 안 되면 수동으로:
# az group delete --name MC_rg-ai200ws-dev_aks-ai200ws-dev_koreacentral --yes --no-wait
```

### session-04 의 Functions + Service Bus + Event Grid 정리

```bash
az functionapp delete --name func-ai200ws-dev -g rg-ai200ws-dev
az functionapp plan delete --name plan-flex-ai200ws-dev -g rg-ai200ws-dev --yes
az servicebus namespace delete --name sb-ai200ws-dev -g rg-ai200ws-dev
az eventgrid system-topic delete --name egt-ai200ws-dev -g rg-ai200ws-dev
```

---

## 보존 권장 자원 (사실상 무료)

CLAUDE.md 자원 라이프사이클 룰에 따라 다음 자원은 **정리하지 않는 것을 권장**합니다.

- **ACR (Basic)** — storage 만 ~₩260/일, 이미지가 학습 자산
- **Log Analytics Workspace** — 5GB/월 free, ingest 만 과금
- **공용 User Assigned Managed Identity** — 무료
- **Application Insights** — workspace-based 라 Log Analytics Workspace 와 함께 ingest 만
- **Key Vault** — sub-원 단위 비용. **전체 정리 시에도 절대 삭제하지 않습니다** — purge protection (`enablePurgeProtection: true`) + 고정 시드 이름이라 한 번 삭제하면 7일간 purge·같은 이름 재배포가 모두 막힙니다

이 자원만 남기고 정리하려면 **리소스 그룹 통째 삭제 대신 세션별 부분 정리**를 사용합니다.

> [!NOTE]
> **App Configuration 은 보존 자원이 아닙니다** — 비용은 sub-원 단위로 작지만, `disableLocalAuth` store 라 삭제 후 같은 이름(`uniqueString` 고정 시드)으로 재배포하면 `NameUnavailable` 로 충돌합니다(soft-delete 이름 예약 ~12분). Key Vault 와 달리 purge protection 이 없어 purge 가 가능하므로, 전체 정리 시에는 **삭제 + `az appconfig purge`** 로 이름을 회수합니다. 절차는 [자주 막히는 정리 시나리오](#자주-막히는-정리-시나리오)의 App Configuration 항목을 참고합니다.

---

## 정리 후 검증

```bash
# 청구 자원이 남아있는지
az resource list -g rg-ai200ws-dev \
  --query "[?type=='Microsoft.Cache/redisEnterprise' || \
            type=='Microsoft.DocumentDB/databaseAccounts' || \
            type=='Microsoft.DBforPostgreSQL/flexibleServers' || \
            type=='Microsoft.ContainerService/managedClusters' || \
            type=='Microsoft.App/containerApps' || \
            type=='Microsoft.Web/sites' || \
            type=='Microsoft.ServiceBus/namespaces'].{name:name, type:type}" \
  -o table
# 기대: 빈 결과 (전체 정리 시) 또는 보존 권장 자원만
```

```powershell
# Windows PowerShell
# JMESPath 쿼리를 한 줄 문자열 변수에 담아 넘긴다 (PowerShell 에서 멀티라인 쿼리 깨짐 방지)
$QUERY = "[?type=='Microsoft.Cache/redisEnterprise' || type=='Microsoft.DocumentDB/databaseAccounts' || type=='Microsoft.DBforPostgreSQL/flexibleServers' || type=='Microsoft.ContainerService/managedClusters' || type=='Microsoft.App/containerApps' || type=='Microsoft.Web/sites' || type=='Microsoft.ServiceBus/namespaces'].{name:name, type:type}"
az resource list -g rg-ai200ws-dev `
  --query $QUERY `
  -o table
# 기대: 빈 결과 (전체 정리 시) 또는 보존 권장 자원만
```

```bash
# macOS · WSL (BSD date)
az consumption usage list \
  --start-date $(date -v-7d +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName,'ai200ws')].{resource:instanceName, cost:pretaxCost, currency:currency}" \
  -o table
```

```bash
# Linux (GNU date)
az consumption usage list \
  --start-date $(date -d '7 days ago' +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName,'ai200ws')].{resource:instanceName, cost:pretaxCost, currency:currency}" \
  -o table
```

```powershell
# Windows PowerShell
$START = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
$END   = (Get-Date).ToString("yyyy-MM-dd")
az consumption usage list `
  --start-date $START `
  --end-date $END `
  --query "[?contains(instanceName,'ai200ws')].{resource:instanceName, cost:pretaxCost, currency:currency}" `
  -o table
```

---

## 자주 막히는 정리 시나리오

### "이미 삭제했는데 청구가 계속 나와요"

- Azure Container Apps Environment 가 삭제 안 됐을 수 있습니다 — Container App 삭제 ≠ Environment 삭제. `az containerapp env delete` 별도 실행 필요
- AKS 의 `MC_...` 리소스 그룹이 남았을 수 있습니다
- Public IP / LB 가 별도 리소스 그룹에 흩어졌을 수 있습니다 — Cost Management → Cost analysis 에서 `Resource group` 별 보기

### "Cognitive Services account 가 삭제 안 돼요"

Azure OpenAI account 는 deployment 를 먼저 삭제해야 합니다. 삭제 후에는 즉시 purge 해야 이름을 재사용할 수 있습니다.

1단계: deployment 를 먼저 삭제합니다.

```bash
# Linux · macOS · WSL
az cognitiveservices account deployment list \
  -n aoai-ai200ws-dev-<suffix> -g rg-ai200ws-dev \
  --query "[].name" -o tsv \
  | xargs -I{} az cognitiveservices account deployment delete \
    -n aoai-ai200ws-dev-<suffix> -g rg-ai200ws-dev --deployment-name {}
```

```powershell
# Windows PowerShell
az cognitiveservices account deployment list `
  -n aoai-ai200ws-dev-<suffix> -g rg-ai200ws-dev `
  --query "[].name" -o tsv `
  | ForEach-Object { az cognitiveservices account deployment delete `
      -n aoai-ai200ws-dev-<suffix> -g rg-ai200ws-dev --deployment-name $_ }
```

2단계: account 를 삭제합니다.

```bash
az cognitiveservices account delete \
  -n aoai-ai200ws-dev-<suffix> -g rg-ai200ws-dev
```

```powershell
# Windows PowerShell
az cognitiveservices account delete `
  -n aoai-ai200ws-dev-<suffix> -g rg-ai200ws-dev
```

3단계: 즉시 purge 합니다. purge 하지 않으면 48시간 동안 같은 이름으로 재배포할 수 없습니다.

```bash
az cognitiveservices account purge \
  --name aoai-ai200ws-dev-<suffix> \
  --resource-group rg-ai200ws-dev \
  --location koreacentral
```

```powershell
# Windows PowerShell
az cognitiveservices account purge `
  --name aoai-ai200ws-dev-<suffix> `
  --resource-group rg-ai200ws-dev `
  --location koreacentral
```

### "App Configuration 을 지운 직후 같은 이름으로 다시 배포하면 실패해요"

App Configuration 은 `disableLocalAuth` store 라 삭제 후 같은 이름이 약 12분간 예약됩니다. 이 상태에서 같은 이름(`uniqueString` 고정 시드)으로 재배포하면 `NameUnavailable` 로 충돌합니다. 삭제 후에는 즉시 purge 해야 이름을 바로 재사용할 수 있습니다.

1단계: store 를 삭제합니다.

```bash
az appconfig delete \
  --name ac-ai200ws-dev \
  -g rg-ai200ws-dev --yes
```

```powershell
# Windows PowerShell
az appconfig delete `
  --name ac-ai200ws-dev `
  -g rg-ai200ws-dev --yes
```

2단계: 즉시 purge 합니다. purge 하지 않으면 약 12분 동안 같은 이름으로 재배포할 수 없습니다. Key Vault 와 달리 purge protection 이 없어 purge 가 가능합니다.

```bash
az appconfig purge \
  --name ac-ai200ws-dev \
  --location koreacentral --yes
```

```powershell
# Windows PowerShell
az appconfig purge `
  --name ac-ai200ws-dev `
  --location koreacentral --yes
```

### "PG soft-delete 가 안 보여요"

- PostgreSQL Flexible Server 는 soft-delete 가 없습니다. 즉시 삭제되고 이름도 즉시 재사용 가능합니다.

### "Log Analytics Workspace 를 지웠는데 14일 보존 기간이 적용돼요"

`az monitor log-analytics workspace delete` 는 기본적으로 14일 soft-delete (복구 가능) 상태로 전환합니다.

즉시 완전 삭제하려면 `--force` 플래그를 추가합니다.

```bash
az monitor log-analytics workspace delete \
  --workspace-name law-ai200ws-dev \
  -g rg-ai200ws-dev --yes --force
```

```powershell
# Windows PowerShell
az monitor log-analytics workspace delete `
  --workspace-name law-ai200ws-dev `
  -g rg-ai200ws-dev --yes --force
```

> [!NOTE]
> 이름은 soft-delete 상태에서도 재사용 가능합니다. Azure 가 자동으로 `createMode: recover` 로 처리합니다.

### "Cosmos 를 지운 직후 같은 이름으로 다시 배포하면 실패해요"

- Cosmos 계정은 삭제가 백엔드에서 완전히 끝나기 전까지 같은 이름으로 재생성하면 `BadRequest: ... database account ... state is not Online` 으로 실패합니다. 목록·restorable 에서 사라져도 백엔드 정리에 몇 분 더 걸리므로, `az cosmosdb show -n <name> -g rg-ai200ws-dev` 가 NotFound 가 될 때까지 기다린 뒤 재배포합니다 (이름은 `uniqueString(resourceGroup().id)` 기반이라 같은 리소스 그룹 안에서는 동일합니다).
