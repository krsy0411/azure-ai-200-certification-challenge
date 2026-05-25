# session-05 — App Configuration 피처 플래그

> 학습 경로 매핑: [Manage app secrets and configuration](https://learn.microsoft.com/ko-kr/training/paths/manage-app-secrets-configuration/)  
> 사전 조건: session-01~session-04 완료, `git checkout session-05-start`

---

## 0. 이 세션에서 무엇을 경험하나

- **한 문장 골**: 코드 한 줄 안 고치고, 포털의 토글 하나로 *시맨틱 캐시를 켜고 끌 수 있게* 만든다.
- **새로 프로비저닝되는 자원**:
  - App Configuration (Standard 등급)
  - AC 안에 키/값 + KV reference (session-01 의 KV 재사용) + Feature flag
  - UAMI 에 `App Configuration Data Reader` 부여
  - UAMI 에 KV `Key Vault Secrets User` 가 이미 있어 KV ref 도 자동 해석 가능
- **사용해볼 SDK/CLI**:
  - `azure.appconfiguration.provider.load` (KV ref 자동 해석 + sentinel refresh)
  - `azure.appconfiguration.feature_management` (피처 플래그)
- **Portal 에서 확인할 지표/데이터**:
  - App Configuration → Configuration explorer — key/value · KV ref 목록
  - App Configuration → Feature manager — flag 토글 UI
  - Application Insights → Live Metrics — flag OFF 직후 `cache_hit` 메트릭이 0 으로 떨어지는 모습

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈

- `app-configuration.bicep` — Standard 등급 (피처 플래그는 Free 도 OK 지만 PG ref 등 키 개수 고려)
- `app-configuration-keyvalue.bicep` (×N) — `aoai:endpoint`, `cosmos:endpoint`, `pg:host`, `redis:host`, …
- `app-configuration-keyvault-ref.bicep` — App Insights connection string 같은 시크릿성 값은 KV ref 로
- `app-configuration-feature-flag.bicep` — `enable_semantic_cache`, `enable_pg_backend`
- `role-assignment-appconfig-data-reader.bicep` — UAMI 에 부여

### 1.2 배포

```bash
OID=$(az ad signed-in-user show --query id -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/05-app-config-flags/main.bicep \
  --parameters infra/sessions/05-app-config-flags/main.bicepparam \
  --parameters userObjectId=$OID

az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/05-app-config-flags/main.bicep \
  --parameters infra/sessions/05-app-config-flags/main.bicepparam \
  --parameters userObjectId=$OID
```

> ⏱ AC 자체는 약 **1분**. 매우 빠릅니다.

---

## 2단계 · 복붙으로 경험해보기

### 2.1 왜 KV 만으로는 부족한가 (트레이드오프)

session-01 에서 이미 KV 를 쓰고 있는데 왜 AC 를 추가하나?

| 차원 | Key Vault | App Configuration |
|---|---|---|
| **목적** | 시크릿 (키, 비밀번호, 연결문자열) | **설정값, 피처 플래그, 환경 분리** |
| **버저닝** | 시크릿 버전 (1개씩 활성) | 라벨 (`dev`/`prod`) + 시점 스냅샷 |
| **암호화** | HSM 가능 | 표준 |
| **접근 빈도** | 드물게 (시작 시) | **자주** (refresh 폴링) |
| **요금** | 작업당 | 요청당 + 저장 |

핵심 차이: **시크릿은 절대 자주 읽지 않는다, 설정은 자주 읽는다**. KV 에 설정을 박으면 throttling 위험. AC 가 설정 전용 캐시·refresh·라벨 제공.

> 🎯 **AI-200 시험 포인트**: "endpoint URL 은 KV 에 박지 말고 AC 에" — 단골 패턴. 시크릿이 아닌 endpoint·플래그·연결문자열의 비-시크릿 부분은 AC.

### 2.2 코드 복사·붙여넣기

**파일**: `apps/api/src/config/loader.py`

```python
# (App Configuration Provider 사용:
#  - DefaultAzureCredential 로 인증
#  - load() 가 KV ref 도 자동 해석 (UAMI 의 KV Secrets User 권한 사용)
#  - sentinel key 폴링 30s (코드 재배포 없이 변경 감지)
#  - feature_management 로 enable_semantic_cache 등 조회
#
#  사용:
#    settings = load_settings()                    # 시작 시 1회
#    if settings.feature_manager.is_enabled("enable_semantic_cache"):
#        ...
#  실제 코드는 후속 구현.)
```

**파일**: `apps/api/src/main.py` 의 변경 (1줄 추가):

```python
# import 추가
from .config.loader import load_settings, get_feature_manager

# 시작 시
settings = load_settings()

# 캐시 미들웨어 안
if get_feature_manager().is_enabled("enable_semantic_cache"):
    # session-03 의 캐시 미들웨어 적용
    ...
else:
    # 캐시 우회
    ...
```

### 2.3 빌드·배포·토글 실험

```bash
# 1) 재배포
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/api:s05 apps/api
docker push $ACR_NAME.azurecr.io/api:s05
az containerapp update -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --image $ACR_NAME.azurecr.io/api:s05

# 2) 캐시 ON 상태에서 두 번 호출 (두 번째 hit 확인)
API_FQDN=$(az containerapp show -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)
time curl -sX POST "https://$API_FQDN/api/chat" -H "Content-Type: application/json" \
  -d '{"q":"휴가 규정"}' > /dev/null
time curl -sX POST "https://$API_FQDN/api/chat" -H "Content-Type: application/json" \
  -d '{"q":"휴가 규정"}' > /dev/null    # hit, fast

# 3) 포털 또는 CLI 로 플래그 OFF
az appconfig feature set \
  --name ac-ai200ws-dev \
  --feature enable_semantic_cache \
  --no-active

# 4) 30~60초 대기 (sentinel refresh)
sleep 60

# 5) 다시 호출 → 두 번째도 느림 (캐시 우회)
time curl -sX POST "https://$API_FQDN/api/chat" -H "Content-Type: application/json" \
  -d '{"q":"휴가 규정"}' > /dev/null
time curl -sX POST "https://$API_FQDN/api/chat" -H "Content-Type: application/json" \
  -d '{"q":"휴가 규정"}' > /dev/null    # 캐시 비활성 — 여전히 느림
```

---

## 3단계 · Azure Portal UI 에서 확인

1. **App Configuration** (`ac-ai200ws-dev`) → **Configuration explorer**
   - 키 목록에 `aoai:endpoint`, `cosmos:endpoint`, `pg:host`, `redis:host` 보임
   - KV reference 키는 자물쇠 아이콘 + `Key vault reference` 타입
2. **App Configuration** → **Feature manager**
   - `enable_semantic_cache` 토글
   - **수동 토글 UI**: 클릭으로 ON/OFF — 직접 해보세요
3. **Application Insights** → **Live Metrics** — 토글 OFF 후 1분 안에 `customMetrics/cache_hit` 가 0 으로 떨어지는 모습 실시간
4. **Key Vault** → **Secrets** — AC 가 reference 하는 시크릿 이름은 보이지만 값은 안 보임 (정상)
5. **(선택) KQL**:
   ```kusto
   customMetrics
   | where name == "cache_hit"
   | summarize hits=countif(value==1), total=count() by bin(timestamp, 5m)
   | extend hit_rate = todouble(hits) / total
   | render timechart
   ```
   토글 OFF 직후 `hit_rate` 가 0 으로 내려가는 시점 시각화

---

## 주의 (Heads-up)

- ⚠️ **`enableRbacAuthorization=true` KV** 는 Portal Data Explorer 가 RBAC 없는 사용자에게 invisible — owner 도 "Request is blocked". session-01 에서 본인에게 임시 RBAC 부여
- ⚠️ **App Config provider 의 `key_vault_options` credential 은 별도 ingest path** — 여러 KV 를 쓰면 credential 매핑 필요. 본 워크샵은 하나의 KV
- ⚠️ **Sentinel refresh 는 폴링** — 30~60초 지연 (즉시 반영 X). 실시간이 필요하면 push 모델 (Event Grid) 별도 구성
- ⚠️ **Purge protection=false 면 7일 soft-delete 충돌** — 같은 이름 재배포 차단. dev 라도 purge protection 권장
- ⚠️ **`is_enabled()` 는 per-call dict lookup** (내장 캐시 없음) — hot path 에서 너무 자주 호출하면 부담. 요청 시작 시 1회만 평가하고 결과 재사용

---

## 마무리

- **save-point**: `git tag session-05-complete`
- **다음 세션 미리보기**: session-06 — 지금까지 OTel 이 자동으로 잡아주던 trace 를 *RAG 비즈니스 의미* 가 담긴 커스텀 span 으로 격상

---

## 참고 자료

- MS Learn: [Manage app secrets and configuration](https://learn.microsoft.com/ko-kr/training/paths/manage-app-secrets-configuration/)
- MS Learn: [App Configuration with Key Vault references](https://learn.microsoft.com/ko-kr/azure/azure-app-configuration/use-key-vault-references-spring-boot)
- 본 레포: `infra/sessions/05-app-config-flags/main.bicep`, `apps/api/src/config/loader.py`
