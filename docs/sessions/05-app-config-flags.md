# session-05 — App Configuration 피처 플래그

> **관련 Microsoft Learn 학습 경로**
>
> - [Manage app secrets and configuration](https://learn.microsoft.com/ko-kr/training/paths/manage-app-secrets-configuration/)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [session-00](./00-setup.md) ~ [session-04](./04-async-ingestion.md) 완료 — Azure Container Apps · Cosmos DB · PostgreSQL · Managed Redis · Key Vault · User Assigned Managed Identity · Application Insights · 비동기 인제스션 파이프라인이 본인 구독에 존재
> - 시작본 코드를 작업 폴더로 받기: `cp -a save-points/session-05/start/. workshop/` (자세한 안내는 §시작본 코드 받기)

---

## 0. 이 세션에서 경험하는 내용

- **한 문장 골** — 코드 한 줄도 고치지 않고, Azure Portal 의 피처 플래그 토글 하나로 시맨틱 캐시를 켜고 끌 수 있는 런타임 설정 분리를 도입
- **새로 프로비저닝되는 자원**
  - App Configuration `ac-ai200ws-dev` (Standard 등급)
  - App Configuration 안에 키/값 (`aoai:endpoint`, `cosmos:endpoint`, `pg:host`, `redis:host`, …)
  - App Configuration 안에 Key Vault reference (Application Insights connection string 같은 시크릿성 값)
  - Feature flag `enable_semantic_cache`, `enable_pg_backend`
  - User Assigned Managed Identity 역할 부여 — `App Configuration Data Reader` (`Key Vault Secrets User` 는 session-01 에서 이미 부여됨)
- **사용해볼 SDK / CLI**
  - `azure-appconfiguration-provider` Python 패키지 — Key Vault reference 자동 해석 + sentinel refresh 폴링
  - `azure.appconfiguration.feature_management` — 피처 플래그 평가
  - `az appconfig feature set` — CLI 로 플래그 토글
- **Portal 에서 확인할 지표 / 데이터**
  - App Configuration → Configuration explorer — 모든 키/값 + Key Vault reference 목록
  - App Configuration → Feature manager — 피처 플래그 토글 UI
  - Application Insights → Live Metrics — 토글 OFF 직후 `cache_hit` 메트릭이 0 으로 떨어지는 모습 실시간
  - Key Vault → Secrets — App Configuration 이 reference 하는 시크릿 이름은 노출, 실제 값은 비공개

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈 한눈에 보기

이 세션이 배포하는 Bicep 모듈 (`infra/sessions/05-app-config-flags/main.bicep`).

- `app-configuration.bicep` — Standard 등급 App Configuration 자원
- `app-configuration-keyvalue.bicep` (×N) — `aoai:endpoint`, `cosmos:endpoint`, `pg:host`, `redis:host` 같은 일반 키/값
- `app-configuration-keyvault-ref.bicep` — Application Insights connection string 처럼 시크릿성 값은 Key Vault reference 로
- `app-configuration-feature-flag.bicep` — `enable_semantic_cache`, `enable_pg_backend` 플래그
- `role-assignment-appconfig-data-reader.bicep` — User Assigned Managed Identity 에게 `App Configuration Data Reader` 역할 부여

### 1.2 변경사항 미리보기

```bash
OID=$(az ad signed-in-user show --query id -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/05-app-config-flags/main.bicep \
  --parameters infra/sessions/05-app-config-flags/main.bicepparam \
  --parameters userObjectId=$OID
```

### 1.3 실제 배포

```bash
az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/05-app-config-flags/main.bicep \
  --parameters infra/sessions/05-app-config-flags/main.bicepparam \
  --parameters userObjectId=$OID
```

> [!NOTE]
> App Configuration 자체 배포는 약 **1분** 으로 본 워크샵에서 가장 빠릅니다. 키/값 · Key Vault reference · 피처 플래그 등록까지 합쳐도 2분 안에 완료됩니다.

### 1.4 배포 완료 확인

```bash
# App Configuration 이 존재하는지
az appconfig show \
  --name ac-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --query "{state:provisioningState, sku:sku.name, endpoint:endpoint}" -o jsonc

# 피처 플래그 목록 확인
az appconfig feature list \
  --name ac-ai200ws-dev \
  --query "[].{key:key, state:state}" -o table
```

기대 — App Configuration 이 `Succeeded` 상태, 피처 플래그 2개 (`enable_semantic_cache`, `enable_pg_backend`) 모두 `on`.

---

## 2단계 · 복붙으로 경험해보기

### 2.1 왜 Key Vault 만으로는 부족한가

[session-01](./01-rag-mvp.md) 에서 이미 Key Vault 를 사용하고 있는데, 왜 App Configuration 을 추가로 도입할까요?

| 차원 | Key Vault | App Configuration |
|---|---|---|
| **목적** | 시크릿 (키 · 비밀번호 · 연결문자열) 보관 | 설정값 · 피처 플래그 · 환경 분리 |
| **버저닝 모델** | 시크릿 버전 (한 번에 하나만 활성) | 라벨 (`dev`/`prod`) + 시점 스냅샷 |
| **암호화** | HSM 옵션 지원 | 표준 |
| **접근 빈도** | 드물게 (앱 시작 시 1회 정도) | 자주 (런타임 refresh 폴링) |
| **요금 모델** | 작업당 과금 | 요청당 + 저장당 과금 |

핵심 차이는 다음과 같습니다 — **시크릿은 자주 읽으면 안 되고, 설정값은 자주 읽어야 합니다.** Key Vault 에 설정값을 보관하면 throttling 위험이 있습니다. App Configuration 은 설정 전용 캐시 · refresh · 라벨 기능을 제공합니다.

> [!TIP]
> **시험 단골 패턴** — "endpoint URL · 피처 플래그 · 일반 설정은 Key Vault 가 아닌 App Configuration 에 두기." 시크릿이 아닌 endpoint · 플래그 · 연결문자열의 비-시크릿 부분은 App Configuration 에, 진짜 시크릿만 Key Vault 에 둡니다. 두 자원을 함께 사용할 때는 App Configuration 의 Key Vault reference 기능으로 시크릿을 안전하게 참조합니다.

### 2.2 코드 복사·붙여넣기

> [!NOTE]
> 아래 파일을 그대로 복사해 해당 경로에 붙여넣습니다. 동작 원리는 코드 다음의 줄별 해설에서 다룹니다.

**파일 1** — `apps/api/src/config/loader.py`

```python
# (App Configuration Provider 사용.
#  핵심 구성:
#  - DefaultAzureCredential 로 App Configuration · Key Vault 양쪽 인증
#  - load() 호출 시 Key Vault reference 도 자동 해석 (User Assigned Managed Identity 의 Key Vault Secrets User 역할 사용)
#  - sentinel key 폴링 30s — 코드 재배포 없이 변경 감지
#  - feature_management 모듈로 enable_semantic_cache 등 플래그 평가
#
#  사용 예:
#    settings = load_settings()                                # 앱 시작 시 1회
#    if settings.feature_manager.is_enabled("enable_semantic_cache"):
#        # 캐시 미들웨어 적용
#    else:
#        # 캐시 우회
#  실제 코드 본문은 후속 구현 단계에서 작성합니다.)
```

**파일 2** — `apps/api/src/main.py` 의 변경 (3줄 추가)

```python
# import 추가
from .config.loader import load_settings, get_feature_manager

# 앱 시작 시
settings = load_settings()

# 요청 처리 안에서 (캐시 미들웨어 분기)
if get_feature_manager().is_enabled("enable_semantic_cache"):
    # session-03 에서 도입한 시맨틱 캐시 미들웨어 적용
    ...
else:
    # 캐시 우회 — 모든 요청이 RAG 파이프라인 전체를 수행
    ...
```

### 2.3 빌드 · 배포 · 토글 실험

다음 명령을 그대로 복사해 순서대로 실행합니다.

```bash
# 1) 재빌드 + 푸시
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/api:s05 apps/api
docker push $ACR_NAME.azurecr.io/api:s05

# 2) Azure Container Apps revision 업데이트
az containerapp update \
  --name ca-api-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --image $ACR_NAME.azurecr.io/api:s05

# 3) FQDN 가져오기
API_FQDN=$(az containerapp show -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)
```

#### 캐시 ON 상태에서 동일 질문 2회 호출 → 두 번째가 빠른지 확인

```bash
# 1회차 — 캐시 miss, 응답 시간 측정
time curl -sX POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q":"휴가 규정"}' > /dev/null

# 2회차 — 캐시 hit, 응답 시간 측정
time curl -sX POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q":"휴가 규정"}' > /dev/null
```

기대 — 1회차 약 800~1500ms, 2회차 100ms 이하.

#### CLI 로 피처 플래그 OFF 토글

```bash
az appconfig feature set \
  --name ac-ai200ws-dev \
  --feature enable_semantic_cache \
  --no-active

# sentinel refresh 폴링 주기 만큼 대기
sleep 60
```

#### 캐시 OFF 상태에서 동일 질문 2회 호출 → 둘 다 느린지 확인

```bash
# 1회차
time curl -sX POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q":"휴가 규정"}' > /dev/null

# 2회차 — 캐시 비활성이므로 여전히 RAG 파이프라인 전체 실행
time curl -sX POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q":"휴가 규정"}' > /dev/null
```

기대 — 1회차와 2회차 모두 약 800~1500ms (캐시 우회 확인).

---

## 3단계 · Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **App Configuration `ac-ai200ws-dev`** → **Configuration explorer**
   - 키 목록에 `aoai:endpoint`, `cosmos:endpoint`, `pg:host`, `redis:host` 가 노출
   - Key Vault reference 로 등록된 키는 자물쇠 아이콘 + 타입 컬럼이 `Key vault reference`
2. **App Configuration** → **Feature manager**
   - `enable_semantic_cache` 토글 확인
   - **포털에서 직접 토글 시연** — ON/OFF 클릭으로 상태 변경 후, 30~60초 안에 애플리케이션 동작이 바뀌는지 확인
3. **Application Insights** → **Live Metrics** → 토글 OFF 후 1분 안에 `customMetrics/cache_hit` 메트릭이 0 으로 떨어지는 모습 실시간 관측
4. **Key Vault** → **Secrets** → App Configuration 이 reference 하는 시크릿 이름이 노출 (실제 값은 권한이 있어야 조회 가능, 정상 동작)
5. (선택) **Application Insights** → **Logs** 에서 다음 KQL 실행

   ```kusto
   customMetrics
   | where name == "cache_hit"
   | summarize hits=countif(value==1), total=count() by bin(timestamp, 5m)
   | extend hit_rate = todouble(hits) / total
   | render timechart
   ```

   토글 OFF 직후 `hit_rate` 가 0 으로 내려가는 시점이 시각화되어야 합니다.

---

## 주의

> [!CAUTION]
> **`enableRbacAuthorization=true` Key Vault 의 Portal Data Explorer 접근 불가** — RBAC-only Key Vault 는 구독 owner 라도 명시적으로 `Key Vault Secrets User` 같은 역할이 부여되어야 시크릿을 조회할 수 있습니다. session-01 에서 본인 계정에 임시 RBAC 를 부여하지 않았다면 "Request is blocked" 메시지가 노출됩니다.

> [!WARNING]
> **App Configuration Provider 의 Key Vault credential 은 별도 ingest path** — Provider 가 Key Vault reference 를 해석할 때 사용하는 credential 은 App Configuration 본체의 credential 과 별개입니다. 여러 Key Vault 를 참조하려면 각각 매핑이 필요합니다. 본 워크샵은 하나의 Key Vault 만 사용해 이 복잡도를 피합니다.

> [!WARNING]
> **Sentinel refresh 는 폴링 방식** — 30~60초 지연이 발생하므로 토글 후 즉시 반영되지 않습니다. 실시간 반영이 필요하면 Event Grid 기반 push 모델을 별도로 구성해야 합니다.

> [!CAUTION]
> **Purge protection=false 면 7일 soft-delete 충돌** — Key Vault · App Configuration 모두 soft-delete 후 7일 동안 같은 이름으로 재생성 불가합니다. 자원 정리 후 재배포 시 이름 충돌을 피하려면 dev 환경도 `purgeProtectionEnabled: true` 설정을 권장합니다.

> [!NOTE]
> **`is_enabled()` 는 호출마다 dict lookup** — 내장 캐시가 없으므로 hot path 에서 너무 자주 호출하면 부담이 됩니다. 요청 시작 시 1회만 평가하고 결과를 변수에 저장해 재사용합니다.

> [!IMPORTANT]
> 더 자세한 함정 모음은 [docs/pitfalls/common.md](../pitfalls/common.md) 의 [Bicep · IaC](../pitfalls/common.md#bicep--iac) 섹션을 참고합니다.

---

## 마무리

- **save-point** — 본 세션의 모든 변경은 `save-points/session-05/complete/` 와 일치합니다. 다음 세션으로 넘어가려면 `cp -a save-points/session-06/start/. workshop/` 를 실행합니다 (다음 세션의 시작본이 `workshop/` 위에 덮입니다)
- **자원 정리** — App Configuration · Key Vault 는 후속 세션 ([session-06](./06-observability.md)) 에서 계속 사용됩니다. 정리하지 않습니다
- **다음 세션 미리보기** — [session-06](./06-observability.md) 에서는 지금까지 OpenTelemetry 가 자동으로 잡아주던 trace 를 RAG 의 비즈니스 의미가 담긴 커스텀 span (예: `rag.retrieve`, `rag.generate`, `cache.lookup`, `tokens.prompt`, `tokens.completion`) 으로 격상시키고, KQL Workbook 과 Metric Alert 로 한눈에 보이는 관측성을 구축합니다

---

## 참고 자료

- Microsoft Learn — [Manage app secrets and configuration](https://learn.microsoft.com/ko-kr/training/paths/manage-app-secrets-configuration/)
- Microsoft Learn — [App Configuration with Key Vault references](https://learn.microsoft.com/ko-kr/azure/azure-app-configuration/use-key-vault-references-spring-boot)
- 본 저장소 — `infra/sessions/05-app-config-flags/main.bicep`, `apps/api/src/config/loader.py`

---

👈 [session-04 — 비동기 인제스션 (Service Bus + Event Grid + Functions)](./04-async-ingestion.md) | [session-06 — Observability 심화](./06-observability.md) 👉
