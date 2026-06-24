# 사전 준비 체크리스트

👈 [챌린지 홈](./README.md)

> [!IMPORTANT]
> 본 챌린지를 시작하기 전 다음 체크리스트를 **순서대로 모두 완료** 합니다. 가장 큰 리스크는 **Azure OpenAI 액세스 승인** 입니다 — 신청 후 승인까지 시간이 걸릴 수 있으므로 가장 먼저 신청하는 것을 권장합니다.

본 체크리스트는 다음 5단계로 구성됩니다.

1. [Azure 구독 준비](#1-azure-구독-준비)
2. [Azure OpenAI 액세스 신청](#2-azure-openai-액세스-신청)
3. [로컬 개발 도구 설치](#3-로컬-개발-도구-설치)
4. [Git 및 GitHub 준비](#4-git-및-github-준비)
5. [최종 검증](#5-최종-검증)

---

## 1. Azure 구독 준비

본 챌린지는 Azure 구독을 제공하지 않습니다. 학습자가 **본인의 개인 Azure 계정** 으로 본인 구독에 배포합니다.

- 종량제 (Pay-As-You-Go), Visual Studio Subscription, 학생·스타트업 구독 모두 사용 가능합니다
- 구독에 대한 **Contributor 또는 Owner** 권한이 필요합니다 (RBAC 역할 할당을 위해 Owner 권장)

> [!WARNING]
> **회사 / 학교 구독 주의** — 조직 정책 (Conditional Access, 리전 제한, 비용 정책 등) 으로 막힐 수 있고, Azure OpenAI 액세스 신청도 별도 절차가 필요합니다. 가능하면 개인 구독 사용을 권장합니다.

---

## 2. Azure OpenAI 액세스 신청

신청 링크 — [aka.ms/oaiapply](https://aka.ms/oaiapply)

> [!CAUTION]
> 승인까지 시간이 걸릴 수 있으므로, 본 체크리스트 중 가장 먼저 신청해두는 것을 매우 권장합니다.
>
> 신청이 승인되기 전에는 Azure OpenAI 자원을 배포할 수 없으므로, 승인이 완료된 뒤에 본 챌린지의 첫 번째 세션 ([session-00](./docs/sessions/00-setup.md)) 을 진행합니다.

---

## 3. 로컬 개발 도구 설치

본 챌린지는 학습자 본인 PC 에서 진행합니다 (Codespaces 사용하지 않음).

### 3.1 도구 버전 요구사항

각 도구의 **확인 명령** 으로 이미 설치되어 있는지·버전이 최소 요건을 만족하는지 점검하고, 없거나 버전이 낮으면 **설치** 열의 공식 설치 페이지를 열어 본인 OS(Windows / macOS / Linux) 에 맞는 안내를 따릅니다. 설치 후 PATH 갱신을 위해 **새 터미널** 을 엽니다.

| 도구 | 버전 | 확인 명령 | 설치 |
|---|---|---|---|
| uv (Python 런타임·패키지 관리) | 최신 | `uv --version` | [uv 설치](https://docs.astral.sh/uv/getting-started/installation/) |
| Node.js | 최신 **LTS** | `node --version` | [nodejs.org/en/download](https://nodejs.org/en/download) |
| Docker Desktop | 4.30+ | `docker info` | [Docker Desktop 설치](https://docs.docker.com/get-started/get-docker/) |
| Azure CLI | 2.65+ | `az --version` | [Azure CLI 설치](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Bicep | 0.30+ | `az bicep version` | [Bicep 설치](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (Azure CLI 설치 후 `az bicep install`) |
| Azure Functions Core Tools | 4.x | `func --version` | [Core Tools 설치](https://learn.microsoft.com/azure/azure-functions/functions-run-local) |
| kubectl (session-07 진행 시) | 1.30+ | `kubectl version --client` | [kubectl 설치](https://kubernetes.io/docs/tasks/tools/) |
| git | 2.40+ | `git --version` | [git-scm.com/downloads](https://git-scm.com/downloads) |

> [!NOTE]
> **Python 은 직접 설치하지 않습니다.** 본 챌린지의 Python 코드·스크립트는 항상 `uv run` 으로 실행하며, `uv` 가 프로젝트에 고정된 Python 버전(`.python-version` = 3.12) 을 읽어 필요한 Python 3.12 를 **자동으로 내려받아** 사용합니다. 따라서 시스템에 Python 이 없거나 3.13 / 3.14 가 깔려 있어도 무방합니다 — 설치할 도구는 `uv` 하나입니다.

> [!NOTE]
> **Node.js 는 "LTS" 버전을 받습니다.** 설치 페이지에 **LTS** 와 **Current** 두 갈래가 보이면 반드시 **LTS**(현재 가장 높은 LTS) 쪽을 받습니다. 버전 번호를 외울 필요 없이 LTS 표시만 따라가면 됩니다. Current(홀수 메이저) 버전은 빌드 호환성이 보장되지 않습니다.

> [!TIP]
> **`func` (Functions Core Tools)**
>
> - 설치 페이지가 막히면 `npm i -g azure-functions-core-tools@4 --unsafe-perm true` 명령어를 터미널에 입력해 설치 가능합니다.
> 
> **Docker Desktop 은 선택**
>
> - 이미지 빌드를 `az acr build` 로 클라우드에서 수행하면 로컬 Docker 없이도 가능합니다 (`az acr build --registry <acr> --image api:tag apps/api`).

### 3.2 Azure CLI 확장 설치

본 챌린지 진행에 다음 확장이 필요합니다.

```bash
az extension add --name containerapp --upgrade
az extension add --name redisenterprise --upgrade
az extension add --name appconfig --upgrade
```

### 3.3 Docker 이미지 사전 다운로드 (권장)

첫 빌드를 빠르게 진행하기 위해 미리 받아둡니다.

```bash
docker pull mcr.microsoft.com/azure-cli:latest
docker pull python:3.12-slim
docker pull node:20-alpine
```

### 3.4 VS Code 확장 (권장)

- Bicep
- Python
- Pylance
- Azure Tools (Container Apps, Functions, Bicep)

---

## 4. Git 및 GitHub 준비

본 챌린지는 GitHub 에 호스팅된 저장소를 클론해서 진행합니다.

### 4.1 GitHub 계정

- [github.com](https://github.com) 에 가입되어 있어야 합니다
- 본인의 GitHub username 을 알고 있어야 합니다

### 4.2 Git 사용자 정보 설정

처음 git 을 사용한다면 다음 한 번만 설정합니다.

```bash
git config --global user.name "본인 이름"
git config --global user.email "본인 이메일"

# 설정 확인
git config --global --list | grep -E "user\.(name|email)"
```

### 4.3 GitHub 인증 방식 : HTTPS + Personal Access Token (PAT)

[GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens) 에서 토큰 생성 후, `git push` 시 비밀번호 대신 토큰을 입력합니다.

지금 당장은 PAT를 사용하지 않으므로, 메모장에 PAT를 복사해두고 본 챌린지 진행 도중 필요할 때 사용합니다.

### 4.4 챌린지 저장소 클론

터미널(Terminal), PowerShell, Git Bash 등에서 아래 명령어를 실행해 챌린지 저장소를 클론합니다.

```bash
git clone https://github.com/krsy0411/azure-ai-200-certification-challenge.git azure-ai-200-challenge
cd azure-ai-200-challenge
```

---

## 5. 최종 검증

위 1~4 단계가 모두 끝났다면 다음 명령으로 한 번에 점검합니다.

### 5.1 도구 버전 일괄 점검

다음 명령을 한 줄씩 실행해 필요한 도구가 모두 설치되어 있는지 확인합니다. 하나가 실패해도 나머지 점검은 이어서 진행합니다.

```bash
# uv — Python 은 uv 가 자동 관리하므로 uv 만 확인합니다
uv --version
```

```bash
# Node.js — 최신 LTS 인지 확인
node --version
```

```bash
# Azure CLI
az --version | head -1
```

```bash
# Bicep
az bicep version
```

```bash
# Azure Functions Core Tools
func --version
```

```bash
# Git
git --version
```

```bash
# Docker — 데몬이 실행 중이면 Docker OK 가 출력됩니다
docker info >/dev/null && echo "Docker OK"
```

### 5.2 Azure 개인 계정으로 로그인 및 구독 선택

```bash
# 개인 계정으로 로그인 (브라우저가 열립니다)
az login
```

```bash
# 사용 가능한 구독 목록 확인
az account list --output table
```

```bash
# 본인 챌린지용 구독을 명시적으로 선택
az account set --subscription "<Name 또는 SubscriptionId>"
```

```bash
# 현재 활성 구독 + 본인 계정 확인
az account show --query "{name:name, id:id, tenantId:tenantId, user:user.name}" -o jsonc
```

> [!WARNING]
> 출력의 `user` 가 본인의 개인 계정 (예: `@gmail.com`, `@outlook.com`, 또는 본인이 Azure 가입에 사용한 계정) 인지 반드시 확인합니다. 회사 / 학교 이메일로 로그인되어 있다면 `az logout` 후 다시 로그인합니다.

### 5.3 비용 모니터링 알람 설정 (강력 권장)

챌린지 진행 중 누적 비용이 예상보다 커지지 않도록 예산 알람을 설정합니다.

- Azure 포털 → Cost Management → Budgets → 새 예산
- 권장 설정 — 금액 `$30`, 임계치 80% 도달 시 이메일 알림

---

## 막혔을 때

- **Azure OpenAI 액세스 미승인** — 승인이 완료된 뒤에 [session-00](./docs/sessions/00-setup.md) 을 진행합니다. 승인 진행 상황은 [Azure 포털 → Azure OpenAI](https://portal.azure.com/#blade/Microsoft_Azure_ProjectOxford/CognitiveServicesHub/OpenAI) 또는 신청 시 입력한 이메일에서 확인합니다
- **할당량 부족** — 모델 배포 시 `capacity: 10` (분당 10K 토큰) 으로 낮춥니다. 그래도 부족하면 `eastus` 또는 `japaneast` 리전 사용
- **`bicep` 명령 실패** — `az bicep install` 후 `az bicep upgrade`
- **Docker `linux/amd64` 빌드 느림 (ARM Mac 환경)** — `--platform linux/amd64` 옵션은 필수입니다. 대안으로 `az acr build` 를 사용하면 클라우드에서 빌드하므로 Docker Desktop 이 불필요합니다
- **그 외** — [docs/pitfalls/common.md](./docs/pitfalls/common.md) 참고
