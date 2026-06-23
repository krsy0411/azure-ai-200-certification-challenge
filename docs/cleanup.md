# 자원 정리

> 워크샵이 끝났으면 **즉시 정리**합니다. 가장 비싼 idle 자원은 Managed Redis Enterprise M10 (~₩11,680/일) 입니다.

---

## 빠른 정리 — 리소스 그룹 통째로

가장 단순한 방법: 워크샵 RG 를 통째로 삭제.

```bash
az group delete \
  --name rg-ai200ws-dev \
  --yes \
  --no-wait
```

> ⚠️ **삭제 후 재배포 시 7일 제약**: KV / AC / Cognitive Services 는 soft-delete 후 7일 동안 같은 이름 재사용 불가. 다시 진행하려면:
> - 옵션 A: 7일 대기
> - 옵션 B: `bicepparam` 의 `env` 또는 접미사를 한 단계 올림 (`dev` → `dev2`)
> - 옵션 C: 명시적 purge (KV)
>   ```bash
>   az keyvault purge --name kv-ai200ws-dev
>   az cognitiveservices account purge --name aoai-ai200ws-dev \
>     --resource-group rg-ai200ws-dev --location koreacentral
>   ```

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

### session-07 의 AKS 만 정리 + 자동 생성된 `MC_...` RG

```bash
az aks delete \
  --name aks-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
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

CLAUDE.md §7 에 따라 다음 자원은 **정리하지 않는 것을 권장**:

- **ACR (Basic)** — storage 만 ~₩260/일, 이미지가 학습 자산
- **Log Analytics Workspace** — 5GB/월 free, ingest 만 과금
- **공용 UAMI** — 무료
- **Application Insights** — workspace-based 라 LAW 와 함께 ingest 만
- **Key Vault / App Configuration** — sub-원 단위 비용

이 자원만 남기고 정리하려면 **RG 통째 삭제 대신 세션별 부분 정리** 사용.

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

```bash
# Cost Management 에서 누적 추세 확인
az consumption usage list \
  --start-date $(date -v-7d +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName,'ai200ws')].{resource:instanceName, cost:pretaxCost, currency:currency}" \
  -o table
```

---

## 자주 막히는 정리 시나리오

### "이미 삭제했는데 청구가 계속 나와요"

- ACA Environment 가 삭제 안 됐을 수 있음 — Container App 삭제 ≠ Environment 삭제. `az containerapp env delete` 별도
- AKS 의 `MC_...` RG 가 남았을 수 있음
- Public IP / LB 가 별도 RG 에 흩어졌을 수 있음 — Cost Management → Cost analysis 에서 `Resource group` 별 보기

### "Cognitive Services account 가 삭제 안 돼요"

- AOAI account 는 deployment 부터 삭제해야 함
  ```bash
  az cognitiveservices account deployment list -n aoai-ai200ws-dev -g rg-ai200ws-dev \
    --query "[].name" -o tsv | xargs -I{} az cognitiveservices account deployment delete \
    -n aoai-ai200ws-dev -g rg-ai200ws-dev --deployment-name {}

  az cognitiveservices account delete -n aoai-ai200ws-dev -g rg-ai200ws-dev
  ```

### "PG soft-delete 가 안 보여요"

- PG Flex 는 soft-delete 가 없습니다. 즉시 삭제. 이름 재사용 가능

### "Cosmos 를 지운 직후 같은 이름으로 다시 배포하면 실패해요"

- Cosmos 계정은 삭제가 백엔드에서 완전히 끝나기 전까지 같은 이름으로 재생성하면 `BadRequest: ... database account ... state is not Online` 으로 실패합니다. 목록·restorable 에서 사라져도 백엔드 정리에 몇 분 더 걸리므로, `az cosmosdb show -n <name> -g rg-ai200ws-dev` 가 NotFound 가 될 때까지 기다린 뒤 재배포합니다 (이름은 `uniqueString(RG)` 기반이라 같은 RG 에서는 동일합니다).
