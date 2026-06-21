# 워크샵 문서 스타일 가이드 (docs-writer 전용)

본 문서는 학습자가 읽는 자료가 아니라 **워크샵 문서 작성 시 따라야 하는 규칙** 입니다. 다음 문서가 본 가이드의 적용 대상입니다.

- `docs/sessions/*.md` (session-00 ~ session-07)
- `docs/architecture.md`
- `docs/cleanup.md`
- `docs/pitfalls/common.md`
- `README.md`
- `PREREQUISITES.md`

**docs-writer 에이전트는 위 문서를 작성·수정하기 전에 본 가이드를 처음부터 끝까지 정독합니다.** 구 `docs/_style.md` (현재 삭제됨) 의 모든 규칙은 사용자 피드백이 누적된 결과물이며, 본 가이드에 하나도 빠짐없이 승계되어 있습니다. 본 가이드가 문서 스타일의 단일 진실 공급원입니다.

> [!NOTE]
> 본 가이드 자체는 작성자용 메타 문서입니다. 가이드 본문에 등장하는 "금지 예시" (예: 표의 "금지" 컬럼, grep 체크리스트의 패턴) 와 가이드 내부 참조 표기 (`§1`, `§7`) 는 가이드 자체의 가독성을 위한 것이므로 가이드의 일반 규칙 적용 대상이 아닙니다. 학습자 대상 문서 (`docs/sessions/*.md`, `README.md` 등) 에서는 모든 규칙을 엄격히 따릅니다.

---

## 0. 문서 사용 컨텍스트

본 워크샵 자료는 **오프라인 워크샵 행사 전용이 아닙니다**. 온라인에서 학습자가 혼자 자율 학습할 때도 동일하게 사용됩니다.

따라서 다음 가정을 **절대 깔지 않습니다**.

- 강사가 있다 (X)
- 워크샵 당일이라는 특정 날짜가 있다 (X)
- 시작일이 정해져 있다 (X)
- 학습자 전원이 같은 시각에 진행한다 (X)
- 오프라인 공유 키·공유 자원이 있다 (X)

학습자는 본인의 일정에 맞춰 본인의 Azure 구독에서 본인 페이스로 진행합니다.

---

## 1. 레퍼런스 분석 요약

본 가이드의 신규 규칙 (특히 §6 캡쳐 이미지, §3.8 기대 출력, §3.9 Azure Portal 조작 표기) 은 다음 Microsoft 공식 자료를 실제로 정독한 결과에 기반합니다.

| # | 자료 | URL | 차용한 스타일 포인트 |
|---|---|---|---|
| 1 | Microsoft Learn ko-kr 학습 경로 — Azure에서 컨테이너 애플리케이션 호스팅 구현 | https://learn.microsoft.com/ko-kr/training/paths/implement-container-app-hosting-azure/ | 학습 경로 → 모듈 → 단원 구조, "사전 요구 사항" 불릿 구성 |
| 2 | Microsoft Learn ko-kr 학습 경로 — AI 솔루션을 위한 백 엔드 서비스 통합 | https://learn.microsoft.com/ko-kr/training/paths/integrate-backend-services-ai-solutions/ | 모듈 설명문의 "~하는 것으로 시작합니다 → 그런 다음 → 마지막으로" 흐름 서술 |
| 3 | Microsoft Learn ko-kr 연습 단원 — 연습: ACR 작업을 사용하여 컨테이너 이미지 빌드 및 관리 | https://learn.microsoft.com/ko-kr/training/modules/store-manage-containers-azure-container-registry/5-exercise-build-manage-acr-tasks | 연습 도입부의 "이 연습에서 수행된 작업" 불릿 요약, "시작하기 전에" 사전 조건 섹션, 단추 이미지 alt text `단추를 사용하여 연습을 시작합니다.` (ko-kr 의 `~합니다.` 종결 alt text 관행) |
| 4 | Microsoft Learn ko-kr 연습 단원 — 연습: Azure Service Bus를 사용하여 메시지 처리 | https://learn.microsoft.com/ko-kr/training/modules/queue-process-operations-service-bus/6-exercise-process-messages | 연습 시나리오를 1~2문단으로 먼저 제시한 뒤 작업 불릿으로 요약하는 도입 패턴, alt text `연습을 시작하는 단추입니다.` |
| 5 | MicrosoftLearning 공식 lab 지침 — Process messages with Azure Service Bus (mslearn-azure-ai) | https://microsoftlearning.github.io/mslearn-azure-ai/instructions/integrate-services/01-svcbus-process-messages.html | 번호 목록 + "명령어 앞 한 문장 설명 → 코드 블록" 패턴, `> **Note:**` / `> **CAUTION:**` 블록을 코드 블록 직후에 배치, 자원 정리 단계의 CAUTION 관행 |
| 6 | microsoft/moaw — Deploying to Azure Container Apps 워크샵 | https://raw.githubusercontent.com/microsoft/moaw/main/workshops/deploying-to-azure-container-apps/workshop.md | 행동 동사 기반 단계 헤더 (`Set up ...`, `Add the ...`), 변수 선언 → 명령 재사용 패턴, 이미지를 절차 직후 결과 확인용으로 배치 |
| 7 | microsoft/moaw — Static Web Apps + Cosmos DB 워크샵 (스크린샷 다용) | https://raw.githubusercontent.com/microsoft/moaw/main/workshops/swa-cosmosdb/workshop.md | 스크린샷 배치 시점 (폼 작성 지시 직후, 실행 결과 확인 시점), 기대 출력을 JSON 블록·텍스트 설명·스크린샷 셋 중 상황에 맞게 혼합 제시 |
| 8 | Azure 공식 문서 ko-kr — 빠른 시작: Azure 포털을 사용하여 첫 번째 컨테이너 앱 배포 | https://learn.microsoft.com/ko-kr/azure/container-apps/quickstart-portal | Portal UI 레이블 볼드 표기 (`**검토 + 만들기**를 선택합니다`), 폼 입력을 "설정 | 작업" 2열 표로 제시, 스크린샷 alt text 원문 `브라우저 페이지의 스크린샷: Hello World 이미지로 실행되는 컨테이너 앱에 대한 메시지와, 컨테이너 앱에 대한 기타 정보가 담겨 있습니다.`, 마지막 "리소스 정리" 섹션 관행 |

분석에서 얻은 **반면교사** — ko-kr Learn 의 기계 번역 (MT) 페이지에는 `Container Apps**를 선택합니다**` (볼드 경계 깨짐), `중요합니다` (Alert 제목의 어색한 직역), `사용하십시오` 같은 번역체 결함이 있습니다. 본 워크샵 문서는 ko-kr Learn 의 **구조** (단계 구성·표·스크린샷 배치) 는 차용하되, **문장** 은 번역체가 아닌 자연스러운 한국어 (§2 규칙) 로 작성합니다.

---

## 2. 문장·어조 규칙

### 2.1 문장 종결

문장은 항상 다음 셋 중 하나로 끝납니다.

- `~합니다` / `~합니다.`
- `~다` / `~다.`
- 서술어 없이 명사구로 종결 (예: `Log Analytics Workspace — 워크샵 전체의 중앙 로그`)

**금지 종결**

- `~요` / `~요.` (예: `확인하세요` → `확인합니다`)
- `~하세요` 명령형 어조 (예: `시작하세요` → `시작합니다` 또는 `시작하는 것을 권장합니다`)
- `~하십시오` / `~십시오` — ko-kr Learn MT 페이지에 자주 나타나는 번역체 종결. 사용하지 않습니다 (예: `Visual Studio Code를 사용하십시오` → `Visual Studio Code 를 사용합니다`)

> [!TIP]
> 표·불릿·짧은 안내문은 명사구로 끝내면 깔끔합니다. 명령·권고가 들어가야 할 때만 `~합니다` / `~하는 것을 권장합니다` 형태를 씁니다.

### 2.2 슬랭·구어체 금지

공식 문서 어조를 유지합니다.

| 금지 | 권장 |
|---|---|
| `bicepparam 에 박지 않습니다` | `bicepparam 에 작성해두지 않습니다` |
| `값을 박아둡니다` | `값을 작성해둡니다` |
| `먼저 박아두고` | `먼저 작성해두고` |

### 2.3 기울임체 (`*텍스트*`) 사용 금지

강조가 필요하면 **볼드** (`**텍스트**`) 만 사용합니다. 기울임체는 사용하지 않습니다.

> [!NOTE]
> 단, 인라인 코드 (`` `aoai-*.bicep` ``) 안의 글로브 패턴 `*` 는 기울임체가 아니므로 허용됩니다.

### 2.4 번역체 회피 (Microsoft Learn 분석 보강)

ko-kr Learn MT 페이지에서 관찰된 번역체 결함을 그대로 따라 쓰지 않습니다.

| 금지 (번역체) | 권장 |
|---|---|
| `다음 사항이 필요합니다` 류의 직역 나열 | `다음이 필요합니다` 뒤 불릿 |
| `~할 수 있습니다` 의 남발 (모든 문장 종결) | 행동 지시는 `~합니다`, 선택지는 `~할 수 있습니다` 로 구분 |
| `완료하는 데 약 30분이 걸립니다` 같은 소요 시간 단정 | (§4.6 시간 길이 표기 규칙 적용 — 세션·단계 길이는 적지 않음) |
| 볼드 경계가 조사까지 삼키는 표기 (`Container Apps**를 선택합니다**`) | 볼드는 UI 레이블·고유 명칭까지만 — `**Container Apps** 를 선택합니다` |

### 2.5 약어는 풀어쓰기

처음 등장하는 자리에서 풀어쓰고, 같은 문단·섹션 내 반복 시에도 가능하면 풀어쓴 표현을 유지합니다.

| 금지 (약어) | 권장 (풀어쓰기) |
|---|---|
| AOAI | Azure OpenAI |
| RG | Resource Group |
| UAMI | User Assigned Managed Identity |
| KV | Key Vault |
| ACA | Azure Container Apps |
| AKS | Azure Kubernetes Service (또는 AKS — 고유명사 성격이라 그대로도 허용) |
| MI | Managed Identity |
| AC | App Configuration |
| AI (Application Insights 의 약어로 쓸 때) | Application Insights |
| LAW | Log Analytics Workspace |
| MS Learn | Microsoft Learn |
| SB | Service Bus |
| EG | Event Grid |

> [!NOTE]
> 자원 *이름* 안의 약어 (`rg-ai200ws-dev`, `kv-ai200ws-dev` 등) 는 명명 규칙이므로 그대로 둡니다.

### 2.6 한국어 친화 표현

입문자가 이해할 수 있도록 영어 IT 용어를 한국어로 풀어쓰거나 부연합니다.

| 금지 | 권장 |
|---|---|
| 직렬 | 순차적으로 (하나가 끝난 후 다음 하나를) |
| 병렬 | 동시에 |
| 병렬로 PUT | 동시에 생성 |
| 쿼터 | 사용 가능한 한도 / 할당량 |
| 폴백 | 대체 리전 사용 / 대안으로 ~ 사용 / 승인이 안 된 경우 ~ 사용 |
| 레포 | 저장소 |
| CLI override | 배포 명령을 실행할 때마다 `--parameters key=value` 인자로 직접 넘겨주는 방식 |
| 인젝션 (잘못된 표기) | 인제스션 (ingestion) — 외부 데이터를 시스템 안으로 수집·적재하는 행위 |

> [!IMPORTANT]
> **ingestion vs injection 혼동 주의** — 한국어로 옮길 때 두 단어를 혼동해서는 안 됩니다.
>
> - `ingestion` → **인제스션** — 데이터를 받아들이는 행위 (예: Blob → Cosmos · PostgreSQL 적재). 본 워크샵의 비동기 인제스션 파이프라인이 여기에 해당합니다
> - `injection` → 인젝션 — 외부에서 무언가를 주입 (예: SQL Injection, Prompt Injection, Dependency Injection). *주입* 의미가 살아있는 곳에서만 사용합니다
>
> 첫 등장 시 영문 병기를 권장합니다 — `비동기 인제스션 (ingestion) 파이프라인`.

### 2.7 시간 단정 표현 금지

특정 날짜·시점을 가정하는 표현을 모두 제거합니다.

| 금지 | 권장 |
|---|---|
| T-7일 / T-1일 / T-0 | (시점 표기 제거. 대신 순서 기반 단계로 구성) |
| 일주일 전 / 1주일 전부터 | 가장 먼저 / 본 체크리스트 중 가장 먼저 |
| 며칠 전 | (특정 시간 명시 없이 일반화) |
| 워크샵 당일 | 본 워크샵 진행 중 / 워크샵을 시작할 때 |
| 당일 아침 | (제거) |
| 시작 직전 | (제거) |
| 시작 전 가장 먼저 | 본 체크리스트 중 가장 먼저 |
| 시작일 기준 | (제거) |
| 1~3일 소요 | 승인까지 시간이 걸릴 수 있으므로 |
| 최대 7일 걸림 | 승인까지 시간이 걸릴 수 있으므로 |

> [!IMPORTANT]
> 학습자의 시작 시점이 정해져 있지 않습니다. "당일", "전", "후" 같은 상대 시간 표현은 학습자 일정을 가정하는 셈이므로 사용하지 않습니다.

### 2.8 세션 식별자 표기

세션을 가리킬 때는 항상 **풀 표기** 를 사용합니다.

| 금지 | 권장 |
|---|---|
| S00, S01, ..., S07 | session-00, session-01, ..., session-07 |
| S00·S01·S05 | session-00·session-01·session-05 |

### 2.9 "강사" 등장 금지

본 워크샵은 강사 진행을 가정하지 않습니다.

| 금지 | 권장 |
|---|---|
| 강사에게 공유 키 요청 | 승인이 완료된 뒤에 `[session-00](./sessions/00-setup.md)` 을 진행합니다 |
| 강사 공유 자원 사용 | (제거 — 학습자 본인 구독 사용) |
| 강사가 사전 배포 | (제거) |

### 2.10 오프라인 행사 가정 금지

`S00 자원의 사전 배포는 학습 가치를 위해 금지합니다` 같이 *워크샵 행사 운영자의 시각* 에서 쓰는 문장은 사용하지 않습니다. 학습자는 본인 페이스로 진행하므로 "사전 배포 금지" 같은 통제는 의미가 없습니다.

---

## 3. 구조 규칙

### 3.1 세션 문서의 헤더 메타 블록

모든 세션 문서는 **타이틀 다음 줄** 에 두 개의 분리된 `>` 블록을 둡니다.

```markdown
# session-NN — <세션 제목>

> **관련 Microsoft Learn 학습 경로**
>
> - [<학습 경로 이름>](<URL>)
> - [<학습 경로 이름>](<URL>)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - <조건 1>
> - `git checkout session-NN-start` 명령어 수행
```

규칙:

- 첫 번째 블록은 일반 `>` 인용. 헤더는 `**관련 Microsoft Learn 학습 경로**`. 학습 경로는 **불릿 사용**
- 두 번째 블록은 `> [!IMPORTANT]` GitHub Alert. 헤더는 `**사전 준비 조건**`. 조건은 불릿 사용
- 두 블록 사이 빈 줄 1개로 분리
- `학습 경로 매핑` 같은 표현 금지 → 항상 `관련 Microsoft Learn 학습 경로`
- `사전 조건` 금지 → 항상 `사전 준비 조건`

### 3.2 헤더 명명

| 위치 | 권장 헤더 |
|---|---|
| §0 | `## 0. 이 세션에서 경험하는 내용` (서술어 없는 명사형) |
| 단계 | `## 1단계 · <제목>` / `## 2단계 · <제목>` / `## 3단계 · <제목>` (시간 표기 금지) |
| 함정 모음 | `## 주의` ( `(Heads-up)` 등 영문 부가 금지) |

`## N단계 · <제목> — 약 N분` 처럼 시간 길이를 헤더 끝에 붙이지 않습니다.

**보강 (moaw·MicrosoftLearning lab 분석)** — 단계 제목은 행동 동사가 드러나는 명사형으로 짓습니다. 예: `1단계 · Service Bus 네임스페이스 프로비저닝`, `2단계 · 메시지 송신 코드 작성`, `3단계 · Azure Portal UI 에서 확인`. "개요", "기타" 같이 행동이 드러나지 않는 제목은 단계 헤더로 쓰지 않습니다.

### 3.3 `## 0. 이 세션에서 경험하는 내용` 의 구성 (Learn 연습 단원 차용)

Microsoft Learn ko-kr 연습 단원의 도입 패턴 ("이 연습에서는 ~합니다" 시나리오 1~2문단 → "이 연습에서 수행된 작업" 불릿) 을 따라, §0 은 다음 순서로 구성합니다.

1. 이 세션이 전체 워크샵에서 차지하는 맥락을 1~2문단으로 서술
2. 수행하는 작업을 불릿으로 요약 (각 불릿은 명사구 종결)

### 3.4 섹션 링크

문서 내 다른 섹션을 가리킬 때는 `§3`, `§2.1` 같은 표기 대신 **마크다운 헤더 앵커** 를 사용합니다.

```markdown
[3단계 · Azure Portal UI 에서 확인](#3단계--azure-portal-ui-에서-확인)
```

GitHub 의 헤더 앵커 규칙:

- 소문자로 변환
- 공백은 `-` 로 치환
- ` · ` (가운뎃점) 은 제거되지만 그 자리의 공백은 유지 → `--` 두 개의 하이픈

> [!TIP]
> 앵커가 맞는지 확신이 없으면, 해당 헤더를 GitHub 에서 본 뒤 헤더 우측 `🔗` 아이콘으로 실제 앵커 URL 을 확인합니다.

### 3.5 GitHub Alert 문법

[GitHub 공식 Alert 문법](https://docs.github.com/ko/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts) 을 적극 사용합니다. 의미별 분류:

| Alert | 의미 | 사용 예 |
|---|---|---|
| `> [!NOTE]` | 일반 안내 | 배포 소요 시간 안내, 부가 설명 |
| `> [!TIP]` | 학습 도움말, 선택 옵션 | "본인 저장소로 Fork 후 진행하는 방법 (선택)" |
| `> [!IMPORTANT]` | 반드시 확인할 정보 | 개인 계정 사용, Azure OpenAI 액세스, 사전 준비 조건 |
| `> [!WARNING]` | 실수 시 문제 발생 | 회사 계정 잘못 로그인, 동시 생성 시 409 Conflict |
| `> [!CAUTION]` | 강한 경고, 위험 회피 | `bicepparam` 에 사용자 식별 정보 작성 금지, 시크릿 노출 위험 |

각 Alert 블록은 다음 패턴을 따릅니다.

```markdown
> [!WARNING]
> **<짧은 제목>** — <설명 문장>
```

또는 더 긴 설명이 필요할 때:

```markdown
> [!IMPORTANT]
> <제목 문장>
>
> - <불릿 1>
> - <불릿 2>
```

> [!WARNING]
> `> ⚠️`, `> ⏱`, `> 💡`, `> 🎯` 같이 emoji prefix 만 있는 일반 인용 블록은 사용하지 않습니다. 의미가 GitHub Alert 와 겹치므로 항상 Alert 문법으로 통일합니다.

**Alert 배치 위치 (MicrosoftLearning lab 분석 보강)** — 주의가 필요한 명령·코드 블록의 **직후** 에 배치합니다 (예: 터미널을 닫으면 안 되는 명령 직후에 `> [!NOTE] 이 터미널을 닫지 않습니다 — ...`). 단계 도입부에 Alert 를 몰아두지 않습니다. 자원 삭제를 안내하는 곳에는 항상 `> [!CAUTION]` 으로 삭제 범위 (Resource Group 삭제 시 포함된 모든 자원이 함께 삭제됨) 를 알립니다.

### 3.6 세션 네비게이션 (이전 / 다음)

모든 세션 문서의 **마지막 줄** 에 좌우 화살표 손가락 이모지와 함께 이전·다음 세션 링크를 둡니다.

```markdown
---

👈 [session-NN-1 — 이전 세션 제목](./NN-1-slug.md) | [session-NN+1 — 다음 세션 제목](./NN+1-slug.md) 👉
```

규칙.

- 첫 세션 (`session-00`) 은 이전 자리에 `[← 워크샵 홈](../../README.md)` 을 둡니다
- 마지막 세션 (`session-07`) 은 다음 자리에 `[자원 정리 →](../cleanup.md)` 를 둡니다
- 가운데 구분자는 ` | ` (앞뒤 공백 1칸씩)
- 좌측 이모지는 `👈`, 우측 이모지는 `👉`
- 링크 텍스트는 `session-NN — <세션 제목>` 형태

### 3.7 시간 길이 표기

세션이나 단계의 길이를 분 단위로 적지 않습니다.

| 금지 | 권장 |
|---|---|
| `> 소요 시간: 약 60분 (유연)` | (헤더 메타 블록에서 줄 자체를 삭제) |
| `## 1단계 · 프로비저닝 — 약 10분` | `## 1단계 · 프로비저닝` |
| 단계당 시간 분배 표 | 시간 분배 없이 단계 흐름만 |

> [!NOTE]
> **예외 — 프로비저닝 대기 시간 안내** — `> [!NOTE] Azure OpenAI deployment ... 약 5~8분 소요됩니다` 같이 *Azure 자원이 만들어지는 데 실제로 걸리는 시간* 은 학습자의 대기 결정에 필요하므로 유지합니다. 학습자에게 "그동안 무엇을 할지" 를 알려주는 정보입니다.

### 3.8 기대 출력 (expected output) 제시 (Learn·moaw 분석 신규)

행동 지시 뒤에는 학습자가 **성공 여부를 스스로 판단할 수 있는 확인 수단** 을 둡니다. 셋 중 상황에 맞는 것을 사용합니다 (moaw swa-cosmosdb 의 혼합 제시 패턴 차용).

1. **출력 블록** — 명령 실행 결과를 보여줄 때. 도입 문장은 `다음과 비슷한 출력이 표시됩니다.` 로 통일하고, 출력 블록은 언어 태그 없이 ` ``` ` 만 사용합니다 (§5.2). 출력이 길면 전체를 싣지 않고 확인 포인트가 되는 줄만 남기고 `...` 으로 생략합니다
2. **텍스트 확인 문장** — UI 변화·간단한 상태를 확인할 때. 예: `브라우저에 채팅 화면이 나타나면 성공입니다.`
3. **스크린샷** — Azure Portal 등 GUI 결과를 확인할 때 (§6 캡쳐 이미지 규칙)

출력 블록 사용 예:

````markdown
다음과 비슷한 출력이 표시됩니다.

```
{
  "provisioningState": "Succeeded",
  ...
}
```

`provisioningState` 가 `Succeeded` 인지 확인합니다.
````

출력 블록 뒤에는 **무엇을 확인해야 하는지** 한 문장을 둡니다. 출력만 던져놓고 끝내지 않습니다.

### 3.9 Azure Portal 조작 표기 (ko-kr Learn 분석 신규)

Azure Portal 에서의 GUI 조작을 안내할 때는 ko-kr 공식 문서의 관행을 따릅니다.

- **UI 레이블은 볼드** — 단추·메뉴·탭·필드 이름을 화면 표기 그대로 볼드 처리. 예: `**검토 + 만들기** 를 선택합니다`, `**리소스로 이동** 을 선택합니다`
- 볼드 범위는 UI 레이블까지만. 조사 (`를`, `을`) 는 볼드 밖에 둡니다 (§2.4 번역체 회피)
- 클릭·탭 동작의 서술어는 `선택합니다` 로 통일 (`클릭하세요`, `눌러주세요` 금지)
- **순차 조작은 번호 목록** — Portal 에서 여러 화면을 거치는 절차는 `1.` `2.` `3.` 번호 목록으로 작성
- **폼 입력은 2열 표** — 만들기 화면처럼 여러 필드를 채우는 절차는 "설정 | 값" 표로 제시 (ko-kr quickstart 의 "설정 | 작업" 표 차용)

```markdown
1. 위쪽 검색 창에서 **Container Apps** 를 검색합니다.
2. **컨테이너 앱 만들기** 를 선택합니다.
3. **기본 사항** 탭에서 다음을 입력합니다.

    | 설정 | 값 |
    |---|---|
    | 구독 | 본인 Azure 구독 |
    | 리소스 그룹 | `rg-ai200ws-dev` |
    | 컨테이너 앱 이름 | `ca-ai200ws-api-dev` |
```

### 3.10 save-point 진입 / 이탈 패턴

모든 세션 문서의 **사전 준비 조건 블록 직후** 또는 **§1단계 직전** 에 save-point 진입 명령을 둡니다.

#### 세션 시작 — 시작본을 작업 폴더로

````markdown
## 시작본 코드 받기

다음 명령을 그대로 복사해 실행합니다. 작업 폴더 `workshop/` 이 만들어지고, 본 세션의 시작본 코드가 그 안에 풀립니다.

```bash
# Linux · macOS · WSL
mkdir -p workshop && \
  cp -a save-points/session-NN/start/. workshop/

# Windows PowerShell
New-Item -ItemType Directory -Force -Path workshop | Out-Null
Copy-Item -Path save-points/session-NN/start/* -Destination workshop -Recurse -Force
```

이후 본 세션의 모든 명령은 `workshop/` 안에서 실행한다고 가정합니다.
````

#### 막혔을 때 — 완성본으로 덮어쓰기

세션 docs 의 마지막 `## 마무리` 섹션 직전 또는 `## 주의` 섹션 안에 다음 안내를 둡니다.

````markdown
> [!TIP]
> 진행 중 막혔다면 완성본 코드를 그대로 덮어쓰고 어디가 달랐는지 직접 비교할 수 있습니다.
>
> ```bash
> cp -a save-points/session-NN/complete/. workshop/
> ```
````

#### 마무리

세션 docs 의 `## 마무리` 섹션은 **`save-point` 항목** 으로 시작합니다 (`git tag` 사용 안 함).

```markdown
## 마무리

- **save-point** — 본 세션의 모든 변경은 `save-points/session-NN/complete/` 와 일치합니다. 다음 세션으로 넘어가려면 `workshop/` 을 그대로 두고 `cp -a save-points/session-(NN+1)/start/. workshop/` 를 실행합니다 (다음 세션의 시작본이 위에 덮입니다)
- **자원 정리** — …
- **다음 세션 미리보기** — …
```

> [!IMPORTANT]
> `git tag session-NN-start` 또는 `git checkout session-NN-start` 같은 git 기반 save-point 표현은 사용하지 않습니다. 본 워크샵의 save-point 메커니즘은 **단일 main 브랜치 + 폴더 복사** 입니다 ([save-points/README.md](../../save-points/README.md) 참고).

---

## 4. 코드 블록 & 명령어

### 4.1 복붙 가능성 우선

학습자가 워크샵 문서에서 코드를 **그대로 복사·붙여넣기** 해서 동작시키는 것이 목표입니다. 따라서:

- 명령어에 placeholder 가 있으면 `$VAR` 형태 + 그 줄에서 변수를 채우는 명령을 함께 제시
- 한 명령으로 안 되는 경우 `&& \` 또는 `;` 로 연결하지 말고 줄을 나누어 한 줄씩 실행 가능하게
- 주석 (`#`) 으로 각 명령이 무엇을 하는지 짧게 부연

예:

```bash
# 본인 objectId 를 환경변수로 저장
OID=$(az ad signed-in-user show --query id -o tsv)

# 배포 명령 — OID 가 명령어 인자로 전달됩니다
az deployment sub create \
  --location koreacentral \
  --template-file infra/sessions/00-setup/main.bicep \
  --parameters infra/sessions/00-setup/main.bicepparam \
  --parameters userObjectId=$OID
```

**placeholder 표기 보강 (MicrosoftLearning lab 대비 차별점)** — MicrosoftLearning lab 은 `<your-resource-group-name>` 같은 꺾쇠 placeholder 를 쓰지만, 꺾쇠 placeholder 는 그대로 복사하면 명령이 실패하므로 본 워크샵에서는 사용하지 않습니다. 항상 `$VAR` + 변수 채우는 선행 명령 패턴을 사용합니다.

### 4.2 코드 블록 언어 태그

언어 태그를 항상 명시합니다.

| 언어 | 태그 |
|---|---|
| Shell | ` ```bash ` |
| Python | ` ```python ` |
| TypeScript / JavaScript | ` ```ts ` / ` ```tsx ` / ` ```js ` |
| SQL | ` ```sql ` |
| KQL | ` ```kusto ` |
| Bicep | ` ```bicep ` |
| YAML | ` ```yaml ` |
| 출력 예시 (언어 아님) | (태그 없이 ` ``` ` 만) |

### 4.3 코드 블록 도입 문장 (MicrosoftLearning lab 분석 신규)

코드 블록 앞에는 그 명령·코드가 **무엇을 하는지 한 문장** 을 둡니다 (lab 의 "Run the following command in the VS Code terminal to navigate to the client directory." 패턴). 도입 문장 없이 코드 블록만 연달아 나열하지 않습니다.

```markdown
다음 명령으로 배포 결과의 출력 값을 확인합니다.
```

---

## 5. 캡쳐 이미지 규칙 (신규)

학습자가 GUI 결과를 확인하는 지점에 Azure Portal 등의 스크린샷을 삽입합니다. 스크린샷은 사용자가 각 세션을 실제 배포한 뒤 직접 캡쳐하므로, 문서 작성 시점에는 **placeholder** 를 둡니다.

### 5.1 이미지 파일 규칙

- 실제 파일 위치: `docs/sessions/images/` 아래 세션별 하위 폴더 — `docs/sessions/images/session-NN/<단계번호>-<kebab-slug>.png`
  - 예: `docs/sessions/images/session-04/2-service-bus-queue-active-messages.png`
- `<단계번호>` 는 해당 스크린샷이 속한 단계 번호. 한 단계에 여러 캡쳐가 있으면 `2a-`, `2b-` 처럼 영문 소문자를 붙입니다. **파일명은 단계 순서대로 gap 없이 연속** (예: 캡쳐 단계 사이를 빼면 `3a·3b·3d` 가 아니라 `3a·3b·3c` 로 당겨 재정렬)
- `<kebab-slug>` 는 화면 내용을 나타내는 영문 소문자 kebab-case
- 세션 문서 (`docs/sessions/*.md`) 에서의 상대 경로는 **`images/session-NN/<파일명>.png`** — 문서가 `docs/sessions/` 안에 있고 이미지가 `docs/sessions/images/` 에 있으므로 상대경로는 `images/...` 다. `../../images/...` 로 쓰면 저장소 루트를 가리켜 **렌더링이 깨진다**(session-03/04 의 실제 활성 임베드가 정본).

### 5.2 삽입 시점 (moaw·ko-kr quickstart 분석 기반)

- **행동 직후 결과 확인용으로만** 삽입합니다 — Portal 폼 작성을 안내한 직후, 배포 완료 화면, 데이터가 들어간 것을 확인하는 화면 등. moaw 워크샵의 "절차 지시 → 결과 스크린샷" 배치를 따릅니다
- 행동 없이 분위기·장식 목적의 이미지는 넣지 않습니다
- CLI 로 충분히 확인되는 결과 (텍스트 출력) 는 §3.8 의 출력 블록을 우선하고, **GUI 에서만 보이는 것** (Portal 차트, 메트릭, 시각화된 토폴로지) 에 스크린샷을 사용합니다

### 5.3 placeholder 형식

아직 캡쳐가 없는 동안 렌더링을 깨지 않도록 HTML 주석 블록을 사용합니다. 정확한 템플릿:

```markdown
<!-- 📸 capture: <이미지 경로> -->
<!--
![<alt text — "...를 보여 주는 Azure Portal 스크린샷" 패턴>](images/session-NN/<파일명>.png)

<캡션 1~2문장 — 화면에서 무엇을 확인해야 하는지>
-->
```

작성 예:

```markdown
<!-- 📸 capture: images/session-04/2-service-bus-queue-active-messages.png -->
<!--
![Service Bus 큐의 활성 메시지 수 5건을 보여 주는 Azure Portal 스크린샷](images/session-04/2-service-bus-queue-active-messages.png)

큐 개요 화면의 **활성 메시지 수** 가 송신한 메시지 수와 일치하는지 확인합니다. 0 이라면 수신 워커가 이미 소비한 상태입니다.
-->
```

규칙:

- 첫 줄 `<!-- 📸 capture: ... -->` 는 미캡쳐 추적용 마커. 경로는 저장소 루트 기준으로 적습니다
- 두 번째 주석 블록 안에는 **캡쳐 완료 후 그대로 살릴 최종 마크다운** (이미지 + 캡션) 을 미리 완성형으로 작성해 둡니다
- **캡쳐 완료 후 처리**: 사용자가 PNG 를 해당 경로에 넣고, 안쪽 주석 기호 (`<!--` / `-->`) 만 제거합니다. 첫 줄의 `📸 capture:` 마커 주석은 추적용이므로 함께 삭제합니다

### 5.4 alt text 와 캡션 작성

- **alt text** 는 ko-kr Microsoft Learn 의 스크린샷 alt text 관행을 따릅니다 — 화면이 무엇을 보여주는지 서술하고 `...를 보여 주는 Azure Portal 스크린샷` 또는 `...스크린샷: <보이는 내용 서술>.` 패턴으로 작성 (실측 예: `브라우저 페이지의 스크린샷: Hello World 이미지로 실행되는 컨테이너 앱에 대한 메시지와, 컨테이너 앱에 대한 기타 정보가 담겨 있습니다.`)
- alt text 와 캡션 모두 본 가이드의 문장 규칙 (§2.1 종결 — `~합니다`/`~다`/명사구, §2.5 약어 풀어쓰기) 을 따릅니다
- **캡션** 은 이미지 바로 아래 1~2문장. 단순 화면 설명이 아니라 **학습자가 그 화면에서 무엇을 확인해야 하는지** (확인 포인트·기대 값) 를 적습니다. moaw 는 캡션을 거의 쓰지 않지만, 본 워크샵은 자율 학습용이므로 확인 포인트 캡션을 필수로 둡니다
- 화면의 특정 영역을 가리켜야 하면 캡션에서 위치를 말로 설명합니다 (`화면 우측 상단의 **활성 메시지 수**`). 빨간 박스 등 이미지 가공은 사용자가 캡쳐 시 선택적으로 추가

### 5.5 캡쳐 placeholder 점검

placeholder 잔존 여부 (= 아직 안 찍은 캡쳐 목록) 는 다음으로 확인합니다.

```bash
grep -rn "📸 capture:" docs/
```

문서 출고 (워크샵 공개) 전에는 이 grep 이 빈 결과여야 합니다. 작성 단계에서는 남아 있는 것이 정상입니다.

---

## 6. 자주 발생하는 잘못된 패턴 (체크리스트)

새 문서를 작성한 뒤 다음 항목을 grep 으로 점검합니다.

```bash
# 1. ~요 / ~하세요 종결 (종결 어미만 — 명사 "필요" 같은 한자어는 제외)
grep -nE "(요\.|요$|하세요|에요|예요|네요|군요|군요\.|는걸요)" <파일> | grep -vE "필요|중요|개요|줄임표|불요"

# 2. ~하십시오 번역체
grep -nE "십시오" <파일>

# 3. 약어 잔재
grep -rnE "\bAOAI\b|\bRG\b|\bUAMI\b|\bACA\b|\bKV\b|MS Learn" <파일>

# 4. 슬랭
grep -nE "박지|박으|박아|박혀" <파일>

# 5. 레포 (저장소 권장)
grep -n "레포" <파일>

# 6. 기울임체 (단독 *)
awk '{n=gsub(/\*/,"&"); if (n>0 && n%2!=0) print NR": "$0}' <파일>

# 7. 시간 단정 표현
grep -nE "T-[0-9]일|일주일 전|1주일 전|며칠 전|당일 아침|워크샵 당일|시작 직전|시작일 기준" <파일>

# 8. S0X 줄임말
grep -nE '[[:<:]]S0[0-9][[:>:]]' <파일>

# 9. 강사 등장
grep -n "강사" <파일>

# 10. § 섹션 표기
grep -nE '§[0-9]' <파일>

# 11. emoji prefix 블록 (Alert 미사용)
grep -nE '^> [⚠⏱💡🎯💰🔍]' <파일>

# 12. 캡쳐 placeholder 잔존 (작성 중에는 남아 있어도 됨 — 출고 전 0 이어야 함)
grep -rn "📸 capture:" docs/

# 13. 꺾쇠 placeholder (복붙 깨짐 — $VAR 패턴 권장)
grep -nE '<your-|<YOUR_' <파일>
```

12번 (작성 단계) 을 제외하고 모두 빈 결과여야 합니다.

---

## 7. 본 가이드 자체의 갱신

사용자가 새 피드백을 줄 때마다 본 가이드에 규칙을 추가합니다. **같은 피드백을 두 번 받지 않도록** 하는 것이 본 가이드의 목적입니다.

새 규칙을 추가할 때는:

1. 해당 섹션 (§2 문장·어조, §3 구조, §4 코드 블록, §5 캡쳐 이미지 등) 에 추가
2. 기존 문서들에 잔재가 있는지 위 §6 의 체크리스트 grep 패턴으로 확인하고 한 번에 정리
3. 본 가이드 갱신 시점은 코드 작성·자료 갱신과 동일한 작업 흐름의 일부
