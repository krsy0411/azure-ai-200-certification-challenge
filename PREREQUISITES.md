# 사전 준비 체크리스트

> [!IMPORTANT]
> 본 워크샵을 시작하기 전 다음 체크리스트를 **순서대로 모두 완료** 합니다. 가장 큰 리스크는 **Azure OpenAI 액세스 승인** 입니다 — 신청 후 승인까지 시간이 걸릴 수 있으므로 가장 먼저 신청하는 것을 권장합니다.

본 체크리스트는 다음 6단계로 구성됩니다.

1. [Azure 구독 준비](#1-azure-구독-준비)
2. [Azure OpenAI 액세스 신청](#2-azure-openai-액세스-신청)
3. [리전별 할당량 확인](#3-리전별-할당량-확인)
4. [로컬 개발 도구 설치](#4-로컬-개발-도구-설치)
5. [Git 및 GitHub 준비](#5-git-및-github-준비)
6. [최종 검증](#6-최종-검증)

---

## 1. Azure 구독 준비

본 워크샵은 워크샵 전용 구독을 제공하지 않습니다. 학습자가 **본인의 개인 Azure 계정** 으로 본인 구독에 배포합니다.

- 종량제 (Pay-As-You-Go), Visual Studio Subscription, 학생·스타트업 구독 모두 사용 가능합니다
- 구독에 대한 **Contributor 또는 Owner** 권한이 필요합니다 (RBAC 역할 할당을 위해 Owner 권장)

> [!WARNING]
> **회사 / 학교 구독 주의** — 조직 정책 (Conditional Access, 리전 제한, 비용 정책 등) 으로 막힐 수 있고, Azure OpenAI 액세스 신청도 별도 절차가 필요합니다. 가능하면 개인 구독 사용을 권장합니다.

구독 확인 명령은 본 문서의 [6. 최종 검증](#6-최종-검증) 단계에서 한 번에 실행합니다.

---

## 2. Azure OpenAI 액세스 신청

> [!CAUTION]
> **본 항목이 가장 큰 리스크입니다.** 승인까지 시간이 걸릴 수 있으므로, 본 체크리스트 중 가장 먼저 신청해두는 것을 강력히 권장합니다.

신청 링크 — [aka.ms/oaiapply](https://aka.ms/oaiapply)

> [!TIP]
> 신청이 승인되기 전에는 Azure OpenAI 자원을 배포할 수 없으므로, 승인이 완료된 뒤에 본 워크샵의 첫 번째 세션 ([session-00](./docs/sessions/00-setup.md)) 을 진행합니다.

---

## 3. 리전별 할당량 확인

Azure 의 각 리전은 자원 종류별로 **사용 가능한 한도** (CPU 코어 수, 분당 토큰 수 등) 가 정해져 있습니다. 워크샵 기본 리전은 `koreacentral` (한국 중부) 이며, 다음 한도가 필요합니다.

| 자원 | 필요한 한도 |
|---|---|
| Azure OpenAI `gpt-4o-mini` | 분당 60K 토큰 |
| Azure OpenAI `text-embedding-3-large` | 분당 50K 토큰 |
| Azure Container Apps Consumption | 10 vCPU |
| PostgreSQL Flexible (Burstable) | 1 vCPU |
| Redis Enterprise | E10 |
| Service Bus | Standard 등급 |
| AKS (session-07): Standard_D2s_v3 노드 | 4 vCPU (DSv3 계열) |
| Cosmos DB | 무제한 (serverless 사용) |

한도 확인 명령은 다음과 같습니다.

```bash
# Azure OpenAI 사용량 확인 (Azure OpenAI 계정 배포 후 가능)
az cognitiveservices usage list --location koreacentral -o table

# 가상 머신 CPU 코어 한도 확인
az vm list-usage --location koreacentral -o table | grep -E "DSv3|Standard_D"
```

> [!NOTE]
> **`koreacentral` 미가용 모델 대응** — 일부 Azure OpenAI 모델이 `koreacentral` 에서 제공되지 않을 수 있습니다. 이 경우 Bicep 의 `aoaiLocation` 파라미터를 `eastus` 또는 `japaneast` 로 변경해 Azure OpenAI 자원만 다른 리전에 배포합니다 (각 세션 docs 에서 안내).

---

## 4. 로컬 개발 도구 설치

본 워크샵은 학습자 본인 PC 에서 진행합니다 (Codespaces 사용하지 않음).

### 4.1 도구 버전 요구사항

| 도구 | 최소 버전 | 확인 명령 |
|---|---|---|
| Python | 3.12+ | `python --version` |
| Node.js | 20+ | `node --version` |
| Docker Desktop | 4.30+ | `docker info` |
| Azure CLI | 2.65+ | `az --version` |
| Bicep | 0.30+ | `az bicep version` |
| Azure Functions Core Tools | 4.x | `func --version` |
| kubectl (session-07 진행 시) | 1.30+ | `kubectl version --client` |
| git | 2.40+ | `git --version` |

### 4.2 Azure CLI 확장 설치

본 워크샵 진행에 다음 확장이 필요합니다.

```bash
az extension add --name containerapp --upgrade
az extension add --name redisenterprise --upgrade
az extension add --name appconfig --upgrade
```

### 4.3 Docker 이미지 사전 다운로드 (권장)

첫 빌드를 빠르게 진행하기 위해 미리 받아둡니다.

```bash
docker pull mcr.microsoft.com/azure-cli:latest
docker pull python:3.12-slim
docker pull node:20-alpine
```

### 4.4 VS Code 확장 (권장)

- Bicep
- Python
- Pylance
- Azure Tools (Container Apps, Functions, Bicep)

---

## 5. Git 및 GitHub 준비

본 워크샵은 GitHub 에 호스팅된 저장소를 클론해서 진행합니다.

### 5.1 GitHub 계정

- [github.com](https://github.com) 에 가입되어 있어야 합니다
- 본인의 GitHub username 을 알고 있어야 합니다

### 5.2 Git 사용자 정보 설정

처음 git 을 사용한다면 다음 한 번만 설정합니다.

```bash
git config --global user.name "본인 이름"
git config --global user.email "본인 이메일"

# 설정 확인
git config --global --list | grep -E "user\.(name|email)"
```

### 5.3 GitHub 인증 방식 (둘 중 하나 선택)

- **HTTPS + Personal Access Token (PAT)** — 가장 간단합니다. [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens) 에서 토큰 생성 후, `git push` 시 비밀번호 대신 토큰을 입력합니다
- **SSH 키** — 한 번 설정하면 매번 인증할 필요가 없습니다. [GitHub 공식 가이드 — SSH 키 생성](https://docs.github.com/ko/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) 참고

### 5.4 워크샵 저장소 클론

```bash
git clone <워크샵-저장소-URL> azure-ai-200-workshop
cd azure-ai-200-workshop

# 시작 시점 코드로 체크아웃
git checkout session-00-start
```

> [!TIP]
> **본인 저장소로 Fork 후 진행하는 방법 (선택)** — 학습 진행 상황을 본인 GitHub 에 기록하고 싶다면, 워크샵 저장소를 본인 계정으로 Fork 한 뒤 그 Fork 를 클론합니다. 본인이 작성한 코드를 push 해두면 포트폴리오로 활용할 수 있습니다.

---

## 6. 최종 검증

위 1~5 단계가 모두 끝났다면 다음 명령으로 한 번에 점검합니다.

### 6.1 도구 버전 일괄 점검

```bash
python --version && node --version && docker info >/dev/null && \
  echo "Docker OK" && az --version | head -1 && \
  az bicep version && func --version && git --version
```

### 6.2 Azure 개인 계정으로 로그인 및 구독 선택

```bash
# 개인 계정으로 로그인 (브라우저가 열립니다)
az login

# 사용 가능한 구독 목록 확인
az account list --output table

# 본인 워크샵용 구독을 명시적으로 선택
az account set --subscription "<본인-개인-구독-이름-또는-ID>"

# 현재 활성 구독 + 본인 계정 확인
az account show --query "{name:name, id:id, tenantId:tenantId, user:user.name}" -o jsonc
```

> [!WARNING]
> 출력의 `user` 가 본인의 개인 계정 (예: `@gmail.com`, `@outlook.com`, 또는 본인이 Azure 가입에 사용한 계정) 인지 반드시 확인합니다. 회사 / 학교 이메일로 로그인되어 있다면 `az logout` 후 다시 로그인합니다.

### 6.3 비용 모니터링 알람 설정 (강력 권장)

워크샵 진행 중 누적 비용이 예상보다 커지지 않도록 예산 알람을 설정합니다.

- Azure 포털 → Cost Management → Budgets → 새 예산
- 권장 설정 — 금액 `$30`, 임계치 80% 도달 시 이메일 알림

---

## 막혔을 때

- **Azure OpenAI 액세스 미승인** — 승인이 완료된 뒤에 [session-00](./docs/sessions/00-setup.md) 을 진행합니다. 승인 진행 상황은 [Azure 포털 → Azure OpenAI](https://portal.azure.com/#blade/Microsoft_Azure_ProjectOxford/CognitiveServicesHub/OpenAI) 또는 신청 시 입력한 이메일에서 확인합니다
- **할당량 부족** — 모델 배포 시 `capacity: 10` (분당 10K 토큰) 으로 낮춥니다. 그래도 부족하면 `koreaeast` 또는 `japaneast` 리전 사용
- **`bicep` 명령 실패** — `az bicep install` 후 `az bicep upgrade`
- **Docker `linux/amd64` 빌드 느림 (ARM Mac 환경)** — `--platform linux/amd64` 옵션은 필수입니다. 대안으로 `az acr build` 를 사용하면 클라우드에서 빌드하므로 Docker Desktop 이 불필요합니다
- **그 외** — [docs/pitfalls/common.md](./docs/pitfalls/common.md) 참고
