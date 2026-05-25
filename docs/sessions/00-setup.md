# session-00 — 사전 설정 & 구독 준비

> **관련 Microsoft Learn 학습 경로**
>
> - [Manage app secrets and configuration](https://learn.microsoft.com/ko-kr/training/paths/manage-app-secrets-configuration/)
> - [Observe and troubleshoot apps](https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [PREREQUISITES.md](../../PREREQUISITES.md) 내용 수행
> - `git checkout session-00-start` 명령어 수행

---

## 0. 이 세션에서 경험하는 내용

- **한 문장 골** — 워크샵의 기반 자원 (Resource Group · Azure OpenAI · 로그 · Key Vault · User Assigned Managed Identity) 을 Bicep 한 번으로 배포하고, Azure AI Foundry 포털에서 모델 deployment 두 개가 살아있음을 직접 확인
- **새로 프로비저닝되는 자원**
  - `rg-ai200ws-dev` — 본 워크샵 전체가 들어갈 Resource Group
  - Azure OpenAI account + 두 개 deployment (`gpt-4o-mini`, `text-embedding-3-large`)
  - Log Analytics Workspace — 워크샵 전체의 중앙 로그
  - Application Insights (workspace-based) — APM
  - Key Vault — session-01 부터 시크릿·구성 보관
  - User Assigned Managed Identity — session-01 부터 Azure Container Apps / Azure Functions 가 사용
  - RBAC — User Assigned Managed Identity 에 `Cognitive Services OpenAI User` 부여
- **사용해볼 CLI**
  - `az deployment sub create` — subscription scope 배포
  - `az cognitiveservices account deployment list` — 모델 배포 검증
- **Portal 에서 확인할 지표/데이터**
  - Azure AI Foundry → Deployments — 두 모델 노출 확인
  - Resource Group 블레이드 → Overview — 8개 자원 확인
  - Key Vault → Access policies / IAM — User Assigned Managed Identity 부여 확인

> [!TIP]
> 이 세션은 `도구 점검 → Bicep 배포 → Portal 확인` 흐름으로 진행합니다.

---

## 1단계 · 도구 점검

### 1.1 환경 한 줄 점검

```bash
python --version && node --version && docker info >/dev/null && echo "Docker OK" && \
  az --version | head -1 && az bicep version && func --version && git --version
```

모두 [PREREQUISITES.md](../../PREREQUISITES.md) 의 최소 버전 이상이어야 합니다.

### 1.2 Azure 로그인 (개인 계정 사용)

> [!IMPORTANT]
> 본 워크샵은 워크샵 전용 구독을 제공하지 않습니다. 학습자가 **본인의 개인 Azure 계정** 으로 로그인해 본인 구독에 배포합니다. 회사·학교 계정으로 잘못 로그인하면 조직 정책 (Conditional Access, 리전 제한, 비용 정책 등) 에 막힐 수 있습니다.

개인 계정으로 로그인합니다.

```bash
# 기존 로그인 세션 초기화 (필요 시)
az logout

# 개인 계정으로 새로 로그인 (브라우저가 열립니다)
az login

# 본인 구독이 active 인지 확인
az account show --query "{sub:name, id:id, user:user.name, tenant:tenantId}" -o jsonc
```

> [!WARNING]
> 출력의 `user` 가 본인의 개인 계정 (예: `@gmail.com`, `@outlook.com`, 또는 본인이 Azure 가입에 사용한 계정) 인지 반드시 확인합니다. 회사 이메일로 로그인되어 있다면 `az login --use-device-code` 또는 브라우저 시크릿 모드로 다시 로그인합니다.

구독이 여러 개라면 본인 워크샵용 구독을 명시적으로 선택합니다.

```bash
az account list --output table
az account set --subscription "<본인-개인-구독-이름-또는-ID>"
```

### 1.3 본인 objectId 메모

```bash
# 이 값은 본 워크샵 전반에서 RBAC 할당 등에 반복 사용합니다.
az ad signed-in-user show --query id -o tsv
```

> [!CAUTION]
> 이 objectId 는 `bicepparam` 파일에 작성해두지 않습니다. git history 에 영구히 남아 포트폴리오 공개 시 노출됩니다. 배포 명령을 실행할 때마다 `--parameters principalId=$OID` 형태로 명령어 인자에 직접 넘겨주는 방식 (예: `az deployment ... --parameters principalId=$OID`) 으로만 전달합니다.

---

## 2단계 · Bicep 배포

### 2.1 모듈 한눈에 보기

이 세션이 배포하는 Bicep 모듈 (`infra/sessions/00-setup/main.bicep`).

- `resource-group.bicep` — Resource Group 자체 (subscription scope 에서 작성)
- `log-analytics.bicep` — 워크샵 전체 중앙 로그
- `application-insights.bicep` — workspace-based Application Insights
- `key-vault.bicep` — RBAC-only (Standard 등급)
- `user-assigned-identity.bicep` — 공용 User Assigned Managed Identity
- `aoai-account.bicep` — Azure OpenAI account (S0)
- `aoai-deployment.bicep` (×2) — `gpt-4o-mini` chat + `text-embedding-3-large` embedding
- `role-assignment-aoai-user.bicep` — User Assigned Managed Identity 에 `Cognitive Services OpenAI User`

### 2.2 변경사항 미리보기

```bash
OID=$(az ad signed-in-user show --query id -o tsv)

az deployment sub what-if \
  --location koreacentral \
  --template-file infra/sessions/00-setup/main.bicep \
  --parameters infra/sessions/00-setup/main.bicepparam \
  --parameters userObjectId=$OID
```

### 2.3 실제 배포

```bash
az deployment sub create \
  --location koreacentral \
  --template-file infra/sessions/00-setup/main.bicep \
  --parameters infra/sessions/00-setup/main.bicepparam \
  --parameters userObjectId=$OID
```

> [!NOTE]
> Azure OpenAI deployment 두 개를 순차적으로 (하나가 끝난 후 다음 하나를) 만들기 때문에 약 **5~8분** 소요됩니다. 진행되는 동안 [3단계 · Azure Portal UI 에서 확인](#3단계--azure-portal-ui-에서-확인) 의 Portal 경로를 미리 익혀둡니다.

> [!WARNING]
> Azure OpenAI deployment 를 동시에 생성하면 409 Conflict 가 발생합니다. Bicep 에서 `dependsOn` 으로 순차 실행되도록 지정되어 있는지 확인합니다.

### 2.4 배포 완료 확인

```bash
# 두 모델 deployment 가 보여야 합니다
az cognitiveservices account deployment list \
  -n aoai-ai200ws-dev \
  -g rg-ai200ws-dev \
  --query "[].{name:name, model:properties.model.name, sku:sku.name}" -o table
```

기대 출력.

```
Name                       Model                       Sku
-------------------------  --------------------------  ----------
gpt-4o-mini                gpt-4o-mini                 Standard
text-embedding-3-large     text-embedding-3-large      Standard
```

---

## 3단계 · Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **Azure AI Foundry** ([ai.azure.com](https://ai.azure.com)) → 좌측 메뉴 **Models + endpoints** (또는 **Deployments**) → `gpt-4o-mini` 와 `text-embedding-3-large` 두 카드 노출
   - 카드 클릭 → `Endpoint`, `Key` (사용 안 함, Managed Identity 사용), `Capacity (TPM)` 확인
2. **Resource Group `rg-ai200ws-dev`** → **Overview** → 자원 8개
   - Azure OpenAI account + Azure OpenAI deployment (Cognitive Services 카테고리)
   - Log Analytics Workspace
   - Application Insights
   - Key Vault
   - User Assigned Managed Identity
3. **Key Vault** → **Access control (IAM)** → **Role assignments** 탭 → User Assigned Managed Identity 가 어떤 역할도 갖지 않음 (session-01 에서 부여 예정)
4. **Azure OpenAI account** → **Access control (IAM)** → User Assigned Managed Identity 에 `Cognitive Services OpenAI User` 가 보임

---

## 주의

> [!WARNING]
> **Azure OpenAI 동시 생성 시 409 Conflict** — deployment 두 개를 동시에 생성하면 `Conflict` 가 발생합니다. Bicep `dependsOn` 으로 순차 실행되도록 지정해야 합니다.

> [!WARNING]
> **`koreacentral` 모델 미가용** — 일부 모델이 가용하지 않을 때가 있습니다. `aoaiLocation` 파라미터를 `eastus` 또는 `japaneast` 로 override 합니다.

> [!CAUTION]
> **`bicepparam` 에 사용자 식별 정보 작성 금지** — 본인 objectId, IP 는 `bicepparam` 파일에 작성해두지 않고, 배포 명령을 실행할 때마다 `--parameters key=value` 인자로 직접 넘겨주는 방식으로 전달합니다 ([docs/pitfalls/common.md](../pitfalls/common.md) 참고).

> [!IMPORTANT]
> **Azure OpenAI 액세스 미승인** — Azure OpenAI 자원은 액세스 승인 ([aka.ms/oaiapply](https://aka.ms/oaiapply)) 이 완료된 구독에서만 배포할 수 있습니다. 승인까지 시간이 걸릴 수 있으므로 [PREREQUISITES.md](../../PREREQUISITES.md) 의 [2. Azure OpenAI 액세스 신청](../../PREREQUISITES.md#2-azure-openai-액세스-신청) 단계를 가장 먼저 진행해야 합니다.

---

## 마무리

- **save-point** — `git tag session-00-complete`
- **자원 정리** — 이 세션의 자원들은 후속 세션 전부에서 재사용됩니다. **정리하지 않습니다** (워크샵 끝에 한 번에 정리)
- **다음 세션 미리보기** — session-01 에서는 방금 만든 Azure OpenAI · Key Vault · User Assigned Managed Identity 를 묶어 Azure Container Apps 위에 RAG MVP 를 올립니다

---

## 참고 자료

- Microsoft Learn — [Manage app secrets and configuration](https://learn.microsoft.com/ko-kr/training/paths/manage-app-secrets-configuration/)
- Microsoft Learn — [Azure OpenAI Service](https://learn.microsoft.com/ko-kr/azure/ai-services/openai/)
- 본 저장소 — `infra/sessions/00-setup/main.bicep`, `infra/modules/aoai-*.bicep`

---

👈 [워크샵 홈](../../README.md) | [session-01 — RAG MVP on Azure Container Apps + Key Vault + OpenTelemetry](./01-rag-mvp.md) 👉
