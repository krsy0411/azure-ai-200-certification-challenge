# session-01 — RAG MVP on Azure Container Apps + Key Vault + OpenTelemetry

> **관련 Microsoft Learn 학습 경로**
>
> - [Implement container app hosting on Azure](https://learn.microsoft.com/ko-kr/training/paths/implement-container-app-hosting-azure/)
> - [Deploy and manage apps on Azure Container Apps](https://learn.microsoft.com/ko-kr/training/paths/deploy-manage-apps-azure-container-apps/)
> - [Develop AI solutions with Azure Cosmos DB](https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-cosmos-db/)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [session-00](./00-setup.md) 완료 — Resource Group · Azure OpenAI · Log Analytics · Application Insights · Key Vault · User Assigned Managed Identity 가 본인 구독에 존재
> - `git checkout session-01-start` 명령어 수행

---

## 0. 이 세션에서 경험하는 내용

- **한 문장 골** — 사내 문서 RAG 의 최소 동작 버전을 Azure Container Apps 위에 올리고, 코드·`.env`·디스크 어디에도 시크릿이 없는 상태로 Azure OpenAI · Cosmos DB 를 호출
- **새로 프로비저닝되는 자원**
  - Azure Container Registry — 컨테이너 이미지 저장 (Basic 등급, admin user disabled)
  - Azure Container Apps Environment — Log Analytics Workspace 와 연결된 Azure Container Apps 환경
  - Azure Container Apps Container App `ca-api-ai200ws-dev` — FastAPI 백엔드
  - Azure Container Apps Container App `ca-web-ai200ws-dev` — Next.js 프런트엔드
  - Cosmos DB account + database + container — vector policy 포함 (HNSW)
  - Key Vault Secret — Azure OpenAI endpoint URL
  - User Assigned Managed Identity 역할 부여 — `AcrPull` · `Cosmos DB Built-in Data Contributor` · `Key Vault Secrets User`
- **사용해볼 SDK / CLI**
  - `azure.identity.DefaultAzureCredential` — 로컬·클라우드 동일 인증 인터페이스
  - `azure.cosmos.aio.CosmosClient` — Cosmos vector search
  - `openai.AzureOpenAI` with token provider — 키 없이 Azure OpenAI 호출
  - `docker build --platform linux/amd64` → `az acr login` → `docker push` → `az containerapp update`
- **Portal 에서 확인할 지표 / 데이터**
  - Cosmos DB → Data Explorer — 시드된 chunk 확인
  - Azure Container Apps → Log stream — FastAPI 요청 로그 실시간 확인
  - Application Insights → Live Metrics — `/api/chat` 호출이 그래프에 반영
  - Key Vault → Access control (IAM) — User Assigned Managed Identity 가 `Key Vault Secrets User` 역할 보유 확인

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈 한눈에 보기

이 세션이 배포하는 Bicep 모듈 (`infra/sessions/01-rag-mvp/main.bicep`).

- `acr.bicep` — Azure Container Registry (Basic 등급, admin user disabled)
- `container-apps-env.bicep` — Log Analytics 와 연결된 Azure Container Apps Environment
- `container-app.bicep` (×2) — `ca-api` (FastAPI), `ca-web` (Next.js)
- `cosmos-account.bicep` — serverless, `disableLocalAuth=true`
- `cosmos-sql-database.bicep` — 데이터베이스
- `cosmos-sql-container.bicep` — vector policy 포함 컨테이너
- `key-vault-secret.bicep` — Azure OpenAI endpoint secret
- `role-assignment-acrpull.bicep` — User Assigned Managed Identity 가 Azure Container Registry 에서 이미지 pull
- `role-assignment-cosmos-data-contributor.bicep` — User Assigned Managed Identity 가 Cosmos data plane 호출
- `role-assignment-keyvault-secrets-user.bicep` — User Assigned Managed Identity 가 Key Vault Secret 읽기

### 1.2 변경사항 미리보기

```bash
OID=$(az ad signed-in-user show --query id -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/01-rag-mvp/main.bicep \
  --parameters infra/sessions/01-rag-mvp/main.bicepparam \
  --parameters userObjectId=$OID
```

> [!NOTE]
> `what-if` 출력에서 `AcrPull` 역할 할당이 `Unsupported` 로 표기되는 경우가 있습니다. 정상 노이즈이며, 실제 배포는 성공합니다.

### 1.3 실제 배포

```bash
az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/01-rag-mvp/main.bicep \
  --parameters infra/sessions/01-rag-mvp/main.bicepparam \
  --parameters userObjectId=$OID
```

> [!NOTE]
> Cosmos DB account 생성이 가장 오래 걸려 약 **8~10분** 소요됩니다. 진행되는 동안 [2단계 · 복붙으로 경험해보기](#2단계--복붙으로-경험해보기) 의 비교 박스와 복붙 코드를 미리 정독합니다.

### 1.4 배포 완료 확인

```bash
# Cosmos DB 가 준비되었는지
az cosmosdb show \
  --name cosmos-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --query "{state:provisioningState, kind:kind}" -o jsonc

# Azure Container Apps Environment 가 준비되었는지
az containerapp env show \
  --name cae-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --query "{state:properties.provisioningState}" -o tsv
```

기대 — 양쪽 모두 `Succeeded`.

---

## 2단계 · 복붙으로 경험해보기

### 2.1 왜 `.env` 가 아니라 Key Vault + Managed Identity 인가

본 워크샵에서 가장 자주 묻는 질문에 대한 답입니다. 같은 작업 (Azure OpenAI 호출) 을 두 가지 방식으로 비교합니다.

#### 방식 A — `.env` (본 워크샵에서 사용하지 않음, 비교용)

```bash
# 1) 키를 꺼냄
az cognitiveservices account keys list \
  -n aoai-ai200ws-dev \
  -g rg-ai200ws-dev \
  --query key1 -o tsv

# 2) 디스크에 평문으로 저장
cat <<EOF >> apps/api/.env
AZURE_OPENAI_API_KEY=sk-...
AZURE_OPENAI_ENDPOINT=https://aoai-ai200ws-dev.openai.azure.com/
EOF
```

```python
# 3) 코드 — 키를 직접 전달
from openai import AzureOpenAI

client = AzureOpenAI(
    api_key=os.getenv("AZURE_OPENAI_API_KEY"),
    azure_endpoint=os.getenv("AZURE_OPENAI_ENDPOINT"),
    api_version="2024-08-01-preview",
)
```

문제점.

- 키가 디스크에 평문으로 남음 — 실수로 `git add` 하면 즉시 노출. GitHub 시크릿 스캔이 곧바로 알람
- 키 회전 시 모든 환경 (로컬 · CI · Azure Container Apps) 의 `.env` 를 수동으로 갱신
- 누가 언제 키를 썼는지 감사 로그 없음
- Entra ID · RBAC 거버넌스를 우회 — 키만 있으면 누구나 호출

#### 방식 B — Key Vault + Managed Identity (본 워크샵 채택)

```python
# 키 없음 — Entra ID 가 토큰을 즉석에서 발급
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

token_provider = get_bearer_token_provider(
    DefaultAzureCredential(),
    "https://cognitiveservices.azure.com/.default",
)

client = AzureOpenAI(
    azure_endpoint=os.getenv("AZURE_OPENAI_ENDPOINT"),   # 비밀이 아님 — endpoint URL 만
    azure_ad_token_provider=token_provider,
    api_version="2024-08-01-preview",
)
```

배포 측.

- Bicep 으로 User Assigned Managed Identity 생성 (session-00 에서 완료)
- Azure OpenAI 에 `Cognitive Services OpenAI User` 역할 부여 (session-00 에서 완료)
- Azure Container Apps Container App 에 User Assigned Managed Identity 연결 (본 세션에서 진행)
- 로컬 개발은 `az login` 자격을 `DefaultAzureCredential` 이 자동 선택 — 코드 동일

이점.

- 코드 · 디스크 · git 어디에도 키 없음
- 키 회전은 Azure 가 자동 처리
- Entra ID 감사 로그에 모든 호출 기록
- 로컬과 클라우드 인증 방식 동일 — "로컬은 다르게" 가 사라짐

> [!TIP]
> **시험 단골 패턴** — "Azure OpenAI 호출 시 키를 쓰지 않으려면?" 의 답은 `DefaultAzureCredential` + `Cognitive Services OpenAI User` 역할입니다.

### 2.2 코드 복사·붙여넣기

> [!NOTE]
> 아래 두 파일은 그대로 복사해 해당 경로에 붙여넣습니다. 후속 세션에서 점진적으로 확장됩니다. 동작 원리는 코드 다음의 줄별 해설에서 다룹니다.

**파일 1** — `apps/api/src/main.py`

```python
# (FastAPI /api/chat 엔드포인트 — DefaultAzureCredential + Cosmos vector search + Azure OpenAI 호출.
#  실제 코드 본문은 후속 구현 단계에서 작성. 골격은 다음을 포함:
#  - DefaultAzureCredential 로 Cosmos · Azure OpenAI 양쪽 인증
#  - OpenTelemetry 자동 계측 (azure-monitor-opentelemetry)
#  - /api/chat: 사용자 질문 → embed → cosmos vector search → 컨텍스트로 chat → 답변 + sources
#  - /healthz: Azure Container Apps probe 용)
```

**파일 2** — `apps/web/app/page.tsx`

```tsx
// (Next.js 최소 챗 UI — 질문 입력 + 답변 표시 + sources 목록.
//  apps/api 의 /api/chat 을 호출.
//  실제 코드 본문은 후속 구현 단계에서.)
```

### 2.3 빌드 · 배포 · 호출

다음 명령을 그대로 복사해 순서대로 실행합니다.

```bash
# 1) Azure Container Registry 로그인
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)
az acr login --name $ACR_NAME

# 2) API 이미지 빌드 — ARM Mac 환경도 동일하므로 --platform 옵션 필수
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/api:s01 apps/api
docker push $ACR_NAME.azurecr.io/api:s01

# 3) Azure Container Apps revision 업데이트
az containerapp update \
  --name ca-api-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --image $ACR_NAME.azurecr.io/api:s01

# 4) 외부 FQDN 가져오기
API_FQDN=$(az containerapp show \
  -n ca-api-ai200ws-dev \
  -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)

# 5) 호출
curl -X POST "https://$API_FQDN/api/chat" \
  -H "Content-Type: application/json" \
  -d '{"q": "회사 휴가 정책 알려줘"}' | jq
```

기대 출력 형태.

```json
{
  "answer": "...",
  "sources": [
    { "title": "휴가-규정.md", "score": 0.87 }
  ]
}
```

---

## 3단계 · Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **Cosmos DB account `cosmos-ai200ws-dev`** → **Data Explorer** → `chunks` 컨테이너 → **Items** 에 시드된 chunk (id · content · embedding 필드) 노출
2. **Azure Container Apps `ca-api-ai200ws-dev`** → **Log stream** → 방금 `curl` 한 요청이 FastAPI 로그에 실시간으로 노출
3. **Application Insights** → **Live Metrics** → 요청 그래프에 `/api/chat` 호출이 즉시 반영. Server response time 도 측정됨
4. **Application Insights** → **Transaction search** → 한 요청 안에 (HTTP 인입 → Cosmos query → Azure OpenAI 호출) span 트리 노출
5. **Key Vault** → **Access control (IAM)** → User Assigned Managed Identity 가 `Key Vault Secrets User` 역할 보유 확인
6. (선택) **Application Insights** → **Logs** 에서 다음 KQL 실행

   ```kusto
   requests
   | where name == "POST /api/chat"
   | summarize p95 = percentile(duration, 95), count() by bin(timestamp, 1m)
   ```

> [!WARNING]
> Cosmos DB Data Explorer 진입 시 401 응답이 나오는 경우가 있습니다. **Cosmos data plane RBAC 가 부여되지 않은 상태** 입니다. 본인에게 임시로 `Cosmos DB Built-in Data Contributor` 역할을 부여하는 방법은 [docs/pitfalls/common.md](../pitfalls/common.md#cosmos-data-plane-rbac--control-plane-session-01session-04) 를 참고합니다.

---

## 주의

> [!CAUTION]
> **Cosmos data plane RBAC 와 control plane RBAC 는 별개** — `Cosmos DB Account Reader` 역할만으로는 데이터 읽기·쓰기가 차단됩니다. Data Explorer 도 본인 계정에 명시적인 data plane RBAC 가 필요합니다.

> [!WARNING]
> **Cosmos vector policy 는 컨테이너 생성 시점에만 설정 가능** — 나중에 추가하려면 컨테이너 drop & recreate 가 필요합니다. 본 워크샵의 Bicep 은 컨테이너 생성 시점에 vector policy 를 포함합니다.

> [!WARNING]
> **ARM Mac 환경에서 `--platform linux/amd64` 옵션 필수** — 누락하면 Azure Container Apps 안에서 `exec format error` 가 silent 하게 발생합니다.

> [!CAUTION]
> **`az configure --defaults group=...` 잔여 효과** — 이전에 default group 을 설정한 적이 있다면 `az acr login` 등의 명령이 잘못된 컨텍스트를 받습니다. 막힐 때는 `az configure --defaults group=""` 로 초기화 후 재시도합니다.

> [!NOTE]
> **Internal ingress 의 HTTP 404 응답** — Azure Container Apps 에서 `ingress.external = false` 로 두면 외부 호출이 TCP 거부가 아닌 HTTP 404 응답으로 돌아옵니다. "앱이 죽었나?" 로 오해하기 쉬우므로 본 세션은 `external = true` 로 시작합니다.

---

## 마무리

- **save-point** — `git tag session-01-complete`
- **자원 정리** — 이 세션의 자원들은 session-02 이후에서 계속 사용됩니다. 정리하지 않습니다
- **다음 세션 미리보기** — session-02 에서는 Cosmos DB 만으로는 알 수 없는 PostgreSQL pgvector 의 강점 (표준 SQL 디버깅, `EXPLAIN ANALYZE`) 을 같은 데이터로 직접 비교합니다

---

## 참고 자료

- Microsoft Learn — [Develop AI solutions with Azure Cosmos DB](https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-cosmos-db/)
- Microsoft Learn — [Azure Container Apps overview](https://learn.microsoft.com/ko-kr/azure/container-apps/overview)
- 본 저장소 — `infra/sessions/01-rag-mvp/main.bicep`, `apps/api/`, `apps/web/`
