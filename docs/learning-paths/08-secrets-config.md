# Phase 8 — AI 솔루션 비밀·구성 관리

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/manage-app-secrets-configuration/ (2 모듈 × 8 단원 = 16 단원)

> Phase 8 은 *Phase 4·5·6·7 의 모든 endpoint·deployment name·connection string* 을 **Azure App Configuration + Key Vault 통합 아키텍처** 로 이관한다. ACA api / Function App 의 평문 envVars 가 사라지고, **단일 `load()` 호출** 로 모든 설정·비밀이 코드에 주입된다. `.env` 도 완전 제거 — 로컬도 `DefaultAzureCredential` 로 동일 코드 경로.
>
> **Phase 8 의 독특한 도전**: §1~§7 일관성으로 모든 데이터 자원이 Entra-only (키 인증 비활성) → KV 에 넣을 *진짜 비밀* 이 거의 없음. **학습 가치 확보를 위해 의도적으로 샘플 비밀 + App Insights connection string 을 KV 로 분류** 하는 결정 (결정 3·11) 이 본 phase 의 핵심 학습 포인트.

---

## 학습 경로 구성 (정독 결과)

| 모듈 | 단원 (8개씩) |
|---|---|
| **1. Azure Key Vault 로 비밀 관리** (8 단원) | ① 소개 ② **비밀·키·인증서 저장 및 구성** (SKU / **RBAC vs access policy** / soft-delete / purge protection) ③ **SDK 비밀 검색** (Managed Identity + DefaultAzureCredential) ④ **버전 관리·회전** (무중단 자격증명 업데이트) ⑤ **캐싱 전략** (KV 호출 감소 + 신선도 균형) ⑥ 연습 — KV 비밀 관리 (Python Flask, 20분) ⑦ 평가 ⑧ 요약 |
| **2. Azure App Configuration 으로 설정 관리** (8 단원) | ① 소개 ② **App Config 연결** (Python provider + Managed Identity) ③ **레이블 + 기능 플래그** (환경별 변형 + 재배포 없는 토글) ④ **KV 참조** (단일 `load()` 통합) ⑤ **AC vs KV 분류 4축** (민감도 / 회전 / 감사 / 액세스 추적) ⑥ 연습 — AC + KV 통합 (Python Flask + sentinel refresh, 30분) ⑦ 평가 ⑧ 요약 |

---

## MS Learn 경로 커버리지 — 사용 / 생략

| 단원 / 학습 항목 | 본 프로젝트 적용 | 비고 |
|---|---|---|
| 모듈 1 ② SKU 계층 | ✅ **standard** | 학습 경로 "대부분 시나리오 충분", premium 은 HSM 키 필요 시만 |
| 모듈 1 ② **RBAC vs access policy** | ✅ **Azure RBAC** | 학습 경로가 명시적으로 권장 / access policy 는 *레거시* 로 분류 |
| 모듈 1 ② soft-delete / purge protection | ✅ soft-delete 활성 (기본) + **purge protection 비활성** | §7 라이프사이클 (같은 이름 재배포) 과 충돌 회피, dev 환경 |
| 모듈 1 ③ Managed Identity + DefaultAzureCredential | ✅ 공용 UAMI (`id-ai200challenge-aca-dev`) 재사용 | Phase 2~7 일관성 |
| 모듈 1 ④ 버전 관리·회전 | ✅ **학습용 샘플 비밀 회전 시나리오** (결정 3 의 학습 가치) | 진짜 비밀 부재 → 의도적 샘플 회전 |
| 모듈 1 ⑤ 시간 기반 캐싱 | ✅ App Config provider 의 내장 캐싱 (30~60s) + sentinel refresh | KV 직접 호출 제거 |
| 모듈 1 — Vault access policy | ❌ **생략** | 학습 경로가 *레거시* 분류, 본 레포는 RBAC 만 |
| 모듈 1 — premium SKU (HSM) | ❌ **생략** | 학습 경로 권장 외 (규제 요구사항 없음) |
| 모듈 2 ② Python provider 연결 | ✅ `azure-appconfiguration-provider` + DefaultAzureCredential | 학습 경로 권장 라이브러리 |
| 모듈 2 ③ 레이블 (`dev` / `prod`) | ✅ 2개 레이블 — `dev` (현재) + `prod` (placeholder 만 등록) | 학습 경로 환경별 변형 패턴 |
| 모듈 2 ③ 기능 플래그 | ✅ **3개** — `enable_semantic_cache` / `use_pg_for_vector_search` / `rollout_new_ranker` | placeholder 의 3개 유지, Phase 4~6 흐름과 정확 매핑 |
| 모듈 2 ④ **KV 참조 + 단일 `load()`** | ✅ App Config 의 `{"uri":"..."}` reference → 한 번의 `load()` 호출 | 학습 경로 권장 "통합 아키텍처", 코드에서 따로 호출은 *안티패턴* |
| 모듈 2 ⑤ **AC vs KV 분류 4축** | ✅ **결정 3·11 의 근거** — 본 문서 "분류 결정" 절 참조 | 학습 경로의 핵심 의사결정 프레임워크 |
| 모듈 2 ⑥ sentinel 동적 새로 고침 | ✅ `refresh_all_sentinel` key + 30~60s 폴링 | 재시작 없이 변경 반영 |
| 각 모듈 평가 / 요약 | ❌ 학습 경로 평가는 사용자가 별도 |

---

## 결정 (사용자 승인: 2026-05-19, A 조합 13개)

| # | 결정 | 채택 | 근거 |
|---|---|---|---|
| 1 | KV 권한 모델 | **Azure RBAC** | 학습 경로 명시 권장, §1~§7 일관성 |
| 2 | KV SKU | **standard** | 학습 경로 "대부분 시나리오 충분" |
| 3 | KV 학습용 샘플 비밀 | **2~3개 명시 등록** | §1~§7 Entra-only 라 진짜 비밀 부재 — 회전·캐싱 단원 실증 위한 학습 자산 |
| 4 | App Config SKU | **standard** | 스냅샷 + sentinel 폴링 여유, free 의 360 req/h 제한 회피 |
| 5 | KV/AC 네트워크 | **public + RBAC** | 가장 단순, AAD 토큰만으로 보호 (Phase 9·10 의 Private Endpoint 별도 결정) |
| 6 | KV 참조 패턴 | **App Config 의 `{"uri":"..."}` reference + 단일 `load()`** | 학습 경로 권장 "통합 아키텍처" |
| 7 | 동적 새로 고침 | **sentinel key + 30~60s 폴링** | 학습 경로 권장 |
| 8 | 레이블 전략 | **`dev` / `prod`** 2개 | placeholder 유지, 학습 커버리지 충족 |
| 9 | 기능 플래그 셋 | **placeholder 3개 유지** | Phase 4~6 흐름과 정확 매핑 |
| 10 | 환경변수 이관 범위 | **모든 endpoint·deployment name 을 AC 로** | Phase 4·5·6·7 의 평문 envVars 제거 |
| 11 | App Insights connection string 위치 | **KV** | 학습 경로 분류 4축 ("값만으로 접근 권한 부여") 상 자격증명 포함 |
| 12 | `.env` 제거 범위 | **로컬도 KV/AC 완전 이관** | 로컬 `az login` 의 DefaultAzureCredential 로 동일 코드 경로 |
| 13 | 재배포 범위 | **공통 자원만** (Phase 4~7 데이터 자원 재배포 X) | Phase 8 본 책임은 KV/AC 자체, 데이터 자원 의존성 없음 |

---

## 분류 결정 — *모듈 2 단원 5 의 4축 적용* (Phase 8 의 핵심 학습)

학습 경로 모듈 2 단원 5 는 "App Configuration 과 Key Vault 에 저장할 내용 결정" 을 위한 **4가지 축** 을 명시한다. 본 레포의 모든 환경변수·비밀을 이 축에 대입한 결과:

### 4축

| 축 | 질문 | KV 가는 경우 | AC 가는 경우 |
|---|---|---|---|
| **민감도** | "값만으로 리소스 접근 권한이 부여되는가?" | Yes | No |
| **회전** | 일정 회전 + 회전 증명 필요? | Yes | 운영 결정 |
| **감사 세분성** | 개체별 감사 필요? | Yes | 저장소 수준 RBAC 충분 |
| **권장 아키텍처** | 단일 진입점 + 보안 백엔드 분리 | KV (back) | AC (front) |

### 본 레포 자산 분류

#### App Configuration 으로 가는 항목 (10개) — *값만으로 접근 권한 안 주어짐*

| 키 (label=`dev`) | 값 | 근거 |
|---|---|---|
| `cosmos:endpoint` | `https://cosmos-...windows.net:443/` | endpoint URL — Cosmos 는 disableLocalAuth=true 라 *URL 만으로는 접근 불가* (AAD 토큰 필수) |
| `cosmos:database` | `kb` | DB 이름 — 식별자 |
| `cosmos:container:chunks` | `chunks` | 컨테이너 이름 |
| `aoai:endpoint` | `https://aoai-...openai.azure.com/` | endpoint URL — 마찬가지 |
| `aoai:deployment:chat` | `gpt-4o-mini` | deployment name |
| `aoai:deployment:embed` | `text-embedding-3-large` | deployment name |
| `pg:host` | `pg-...postgres.database.azure.com` | host — AAD 토큰 필요 |
| `pg:database` | `kb` | DB 이름 |
| `redis:host` | `redis-...redis.azure.net` | host |
| `servicebus:fqdn` | `sb-...servicebus.windows.net` | namespace FQDN |
| **기능 플래그** | `enable_semantic_cache`, `use_pg_for_vector_search`, `rollout_new_ranker` | 운영 토글, 민감도 0 |

→ 모두 **AC** — 4축 모두에서 "AC 가는 경우" 매칭.

#### Key Vault 로 가는 항목 (4개) — *값 자체로 접근 권한·자격증명*

| 시크릿 이름 | 분류 근거 (4축 적용) |
|---|---|
| `app-insights-connection-string` (결정 11) | **민감도 Yes** — connection string 안에 `InstrumentationKey=...` 가 평문. AAD ingest 비활성 시 이 키만으로 telemetry 위조·송신 가능. **회전 Yes** — 보안 사고 시 재발급 필요. **감사 Yes** — 누가 언제 읽었는지 추적. → **KV** |
| `external-stub-api-key` (결정 3, 학습용) | **민감도 Yes** — 가상 외부 API 인증키 placeholder. *실제 호출은 없음, 학습용 자산.* 회전 시나리오 실증용. → **KV** |
| `webhook-signing-secret` (결정 3, 학습용) | **민감도 Yes** — HMAC 서명용 secret. *실제 webhook 흐름은 없음.* 시간 기반 캐싱 단원 실증용. → **KV** |
| `legacy-db-password` (결정 3, 학습용 — *선택*) | 만약 등록한다면 — 무중단 회전 시나리오 (모듈 1 단원 4) 의 *복잡한 회전* (constraint: old/new 둘 다 잠시 유효) 실증용 |

→ 모두 **KV** — 4축 중 민감도/회전/감사 적어도 2개에 해당.

### 결정 3·11 의 학습 가치

학습 경로의 4축이 **"무엇을 KV 에, 무엇을 AC 에 둘지" 라는 실무 의사결정 프레임워크** 인데, 본 레포는 §1~§7 Entra-only 정책으로 *진짜 비밀이 거의 없음*. 그래서:

- **결정 3 (학습용 샘플 비밀 등록)** — 의도적으로 비밀을 만들지 않으면 모듈 1 단원 4 (회전) / 단원 5 (캐싱) 의 *실증 시나리오* 를 돌릴 수 없음. 학습 경로의 핵심 기능을 "이론으로만" 마치는 게 아니라 *실제 회전 시뮬레이션 + 캐시 만료 측정* 까지 검증.
- **결정 11 (App Insights connection string 을 KV)** — 학습 경로의 4축을 *엄격히* 적용한 결과. instrumentation key 가 connection string 안에 평문으로 들어있고, AAD ingest 가 활성화돼있지 않으면 이 키 만으로 telemetry ingest 가능 (= "값만으로 접근 권한 부여" Yes). Phase 7 함정 7 에서 우리는 AAD ingest 를 비활성화하고 instrumentation key 폴백을 선택했으니 → 4축 기준상 분명히 KV.

**두 결정이 없다면** Phase 8 은 *AC 만 다루는 phase* 가 되고 KV 학습 가치가 0. 두 결정이 *Phase 8 의 학습 균형* 을 잡는다.

---

## 자원 이름 규칙

| 리소스 | 이름 |
|---|---|
| Key Vault | `kv-ai200challenge-dev` |
| App Configuration | `ac-ai200challenge-dev` |
| App Configuration store URL | `https://ac-ai200challenge-dev.azconfig.io` |
| sentinel refresh key | `refresh_all_sentinel` |

---

## 아키텍처

```
[apps/api/src/config/azure_config.py]
    ↓ (앱 시작 시 1회 + 30~60s 폴링)
DefaultAzureCredential (로컬 = az login / ACA = UAMI)
    ↓ AAD 토큰
App Configuration `ac-ai200challenge-dev`
    ├─ key=cosmos:endpoint, label=dev    → "https://cosmos-...azure.com/"
    ├─ key=aoai:endpoint, label=dev      → "https://aoai-...openai.azure.com/"
    ├─ ... (10개 AC 항목, label=dev)
    ├─ feature_flag=enable_semantic_cache → true
    ├─ feature_flag=use_pg_for_vector_search → false
    ├─ feature_flag=rollout_new_ranker    → 0% rollout
    └─ key=app-insights:connection-string, value={"uri":"https://kv-.../secrets/app-insights-connection-string"}
                                              ↓ (자동 resolution, 같은 load() 안에서)
                                          Key Vault `kv-ai200challenge-dev`
                                              ├─ app-insights-connection-string
                                              ├─ external-stub-api-key (학습용)
                                              └─ webhook-signing-secret (학습용)
    ↓ 단일 load() 의 결과 dict
config["cosmos:endpoint"]                  # AC 값
config["app-insights:connection-string"]   # KV 에서 자동 fetch
config.feature_flag.is_enabled("enable_semantic_cache")
```

### 동적 새로 고침 흐름

```
Admin 이 App Config 에서 'cosmos:endpoint' 값 변경
    ↓
Admin 이 sentinel key 'refresh_all_sentinel' 값 bump (예: '2' → '3')
    ↓ (30~60s 폴링)
api 컨테이너 의 background poller 가 sentinel 변경 감지
    ↓
config.refresh() — KV 참조 자동 재해결
    ↓
다음 요청부터 새 cosmos:endpoint 사용 — *재시작 없음*
```

---

## Bicep 모듈 구성 (예정)

| 모듈 | 책임 |
|---|---|
| `infra/modules/key-vault.bicep` | RBAC mode (`enableRbacAuthorization=true`), soft-delete on, purge protection off, public network |
| `infra/modules/key-vault-secret.bicep` | 비밀 1건 등록 (모듈 호출 N번 으로 학습용 샘플 비밀 + App Insights connection string 등록) |
| `infra/modules/app-configuration.bicep` | standard SKU, AAD-only (`disableLocalAuth=true`), public network |
| `infra/modules/app-configuration-keyvalue.bicep` | AC key-value 1건 등록 (label=dev) — endpoint·deployment name 모두 |
| `infra/modules/app-configuration-feature-flag.bicep` | feature flag 1건 등록 — 3개 호출 |
| `infra/modules/app-configuration-keyvault-ref.bicep` | AC 의 KV reference (contentType=`application/vnd.microsoft.appconfig.keyvaultref+json`) |
| `infra/modules/role-assignment-keyvault-secrets-user.bicep` | UAMI 에 `Key Vault Secrets User` (subscription scope = `4633458b-17de-...`) |
| `infra/modules/role-assignment-appconfig-data-reader.bicep` | UAMI 에 `App Configuration Data Reader` |
| `infra/phases/08-secrets-config/main.bicep` | 위 모듈 + 공통 자원 existing 참조 (UAMI / LAW 등) |
| `infra/phases/08-secrets-config/main.bicepparam` | 접미사 / SKU override |

---

## 앱 코드 변경 (예정)

`apps/api/src/config/azure_config.py` 신설 — App Config provider + sentinel refresh 단일 진입점:

```python
from azure.appconfiguration.provider import (
    load, SettingSelector, WatchKey
)
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient  # 필요시 별도 호출 (현재는 AC 의 KV ref 만 사용)


_credential = DefaultAzureCredential()

_config = load(
    endpoint="https://ac-ai200challenge-dev.azconfig.io",
    credential=_credential,
    key_vault_options={"credential": _credential},
    feature_flag_enabled=True,
    selects=[SettingSelector(key_filter="*", label_filter="dev")],
    refresh_on=[WatchKey("refresh_all_sentinel")],
    refresh_interval=30,  # 30s 폴링
)


def cfg(key: str) -> str:
    """AC 값 (KV 참조 자동 resolve) 조회."""
    return _config[key]


def feature_enabled(flag: str) -> bool:
    return _config.feature_flag.is_enabled(flag)
```

기존 코드 변경 (예시):
```python
# 변경 전 (Phase 4~7)
import os
COSMOS_ENDPOINT = os.environ["COSMOS_ENDPOINT"]

# 변경 후 (Phase 8)
from src.config.azure_config import cfg
COSMOS_ENDPOINT = cfg("cosmos:endpoint")
```

---

## 검증 시나리오 (단계 5 — `/phase-verify`)

### 1) 자원·권한
- `az keyvault show` → `enableRbacAuthorization=true`, `enableSoftDelete=true`, `enablePurgeProtection=null/false`
- `az appconfig show` → SKU=`standard`, `disableLocalAuth=true`
- UAMI 의 role assignment: `Key Vault Secrets User` (KV scope) + `App Configuration Data Reader` (AC scope)

### 2) AC 에서 값 조회 + KV 참조 자동 resolution
```bash
# AC 의 cosmos:endpoint (일반 키)
az appconfig kv show --name ac-ai200challenge-dev --key cosmos:endpoint --label dev

# AC 의 app-insights:connection-string (KV reference)
az appconfig kv show --name ac-ai200challenge-dev --key app-insights:connection-string --label dev
# → value 가 {"uri":"https://kv-.../secrets/app-insights-connection-string"} 형식 JSON

# KV 비밀 직접 조회 (UAMI 권한으로)
az keyvault secret show --vault-name kv-ai200challenge-dev --name app-insights-connection-string
```

### 3) api 컨테이너의 `/admin/config` 엔드포인트
- AC 로드 결과 + KV 참조 resolution 결과 (마스킹) 표시
- feature flag 3개 현재 상태 표시
- 모든 endpoint 가 AC 에서 왔는지 확인 (기존 env vars 가 사용 안 됨)

### 4) 학습용 비밀 회전 시뮬레이션 (`/admin/secret/rotate-sim`)
```bash
# 1) KV 의 external-stub-api-key 새 버전 생성
az keyvault secret set --vault-name kv-ai200challenge-dev --name external-stub-api-key --value "new-version-$(date +%s)"
# 2) api 의 다음 30s 폴링 후 sentinel 가 변하지 않으면 cache 만료까지 기다림 (provider 내장 캐싱)
# 3) /admin/secret/rotate-sim 으로 새 값 반영 시간 측정 (회전 단원 검증)
```

### 5) 기능 플래그 토글
```bash
# 1) enable_semantic_cache off
az appconfig feature set --name ac-ai200challenge-dev --feature enable_semantic_cache --label dev
# 2) sentinel bump
az appconfig kv set --name ac-ai200challenge-dev --key refresh_all_sentinel --value "$(date +%s)"
# 3) 30s 후 /api/chat 요청 — 캐시 lookup skip 되는지 확인
```

### 6) `.env` 완전 제거 검증
- `find apps -name ".env*"` → 빈 결과
- 로컬 `uv run python -m src.main` → `az login` 한 사용자 자격으로 AC/KV 정상 조회

---

## 측정 결과 — TBD (검증 후 사용자와 같이 채움)

| 시나리오 | 측정값 | 비고 |
|---|---|---|
| 단일 `load()` 호출 시간 (cold start) | TBD | KV 참조 resolution 포함 |
| sentinel bump 후 새 값 반영 latency | TBD | 30s 폴링 + provider 캐시 만료 |
| 학습용 비밀 회전 → api 인식 latency | TBD | provider 캐시 만료 후 |
| 기능 플래그 토글 → 코드 분기 변경 시간 | TBD | sentinel + 30s |

---

## 함정·교훈 — TBD (배포·검증 중 채움)

1. *TBD* — `enableRbacAuthorization=true` 로 KV 만들면 *기존 access policy 무시*. portal 에서 secret 못 보는 함정 가능 (UAMI 만 RBAC 가지면 사용자 본인은 차단)
2. *TBD* — App Config provider 의 `key_vault_options={"credential": cred}` 가 *KV 마다 따로* 인증 — 여러 KV 사용 시 별도 매핑
3. *TBD* — purge protection 비활성으로 둬도 soft-delete 7일 은 강제 (Phase cleanup 시 같은 이름 충돌 가능)
4. *TBD* — feature flag 의 `is_enabled` 호출이 매번 dict lookup — 캐시 redundant 호출 여부
5. *TBD* — sentinel key 가 *어떤 키 변경에도 같이 bump 돼야* refresh 트리거 — 운영 절차

---

## 정리 (Phase 9 진입 직전)

§7 룰 (2026-05-18 갱신, Phase 7 함정 8 기반) — **무료/사실상-무료 자원만 보존**. KV/AC 는 sub-원 단위 비용이라 보존 가능하나, Phase 9 진입 후에도 필요하면 유지, 아니면 정리.

사용자 명시 요청 후:

```bash
# Phase 8 phase-specific (선택 — sub-원 단위 비용이라 보존도 가능)
az keyvault delete -g rg-ai200challenge-dev -n kv-ai200challenge-dev
az keyvault purge -n kv-ai200challenge-dev --location koreacentral  # 같은 이름 재생성 위해
az appconfig delete -g rg-ai200challenge-dev -n ac-ai200challenge-dev --yes
az appconfig purge -n ac-ai200challenge-dev --yes
```

**보존**: ACR / LAW / UAMI×2 / CAE / Application Insights. KV/AC 는 Phase 9·10 에서도 사용되면 보존 유지.
