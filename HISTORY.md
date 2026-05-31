# HISTORY — 다른 컴퓨터에서 이어받기 위한 임시 인계 문서

> [!IMPORTANT]
> 본 문서는 **임시 인계용** 입니다. 모든 워크샵 자료 작업이 완료되면 사용자 지시에 따라 삭제됩니다.
> 학습자에게 노출되지 않는 maintainer 전용 메타 문서.

본 워크샵 자료를 다른 컴퓨터에 클론한 뒤 (또는 새 Claude 세션에서) 이어받아 작업을 계속할 때, 본 문서를 가장 먼저 읽고 진행하면 5분 안에 컨텍스트 복원이 가능합니다.

---

## 1. 프로젝트 한 줄 요약

**Azure AI-200 자격증 학습용 Workshop in a Day** — 사내 문서 RAG 지식 비서를 처음부터 끝까지 본인 Azure 구독에 배포해보는 한국어 워크샵 자료. krsy0411/maf-workshop-in-a-day-ko 의 save-points 패턴을 적용한 형태.

핵심 컨벤션:
- 모든 작업 원칙 — [`CLAUDE.md`](./CLAUDE.md) (배포 방식, 자원 라이프사이클, 보안, 커밋 규칙 등)
- 문서 작성 스타일 — [`docs/_style.md`](./docs/_style.md) (작성자용 메타 — 같은 피드백이 반복되지 않도록 7개 섹션으로 규칙화)
- save-point 사용법 — [`save-points/README.md`](./save-points/README.md)
- 함정 모음 — [`docs/pitfalls/common.md`](./docs/pitfalls/common.md) — 자원별 함정 회피법

> [!CAUTION]
> **새 작업 시작 전 반드시 `docs/_style.md` 의 §5 체크리스트 10항목을 다시 확인** 하세요. 사용자 피드백을 반영해 추가된 규칙이 많고 일관성이 워크샵 가치의 핵심입니다.

---

## 2. 워크샵 전체 구조 한눈에 보기

```
Workshop in a Day — 7 개 세션 + 사전 설정 (총 8 개)

session-00 → 사전 설정 (Resource Group · Log Analytics · Application Insights · Key Vault · UAMI · Azure OpenAI)
session-01 → RAG MVP on Azure Container Apps + Key Vault + OpenTelemetry
session-02 → PostgreSQL pgvector 비교
session-03 → Managed Redis 시맨틱 캐시
session-04 → 비동기 인제스션 (Service Bus + Event Grid + Azure Functions)
session-05 → App Configuration 피처 플래그
session-06 → Observability 심화 (커스텀 OpenTelemetry span + KQL Workbook + Alert)
session-07 → Azure Kubernetes Service 대안 배포
```

각 세션마다 산출물 3종:
- **세션 docs** (`docs/sessions/0N-*.md`) — 학습자가 읽는 안내 문서
- **Bicep** (`infra/modules/session-NN/*.bicep` + `infra/sessions/0N-*/main.bicep` + `main.bicepparam`) — Azure 자원 정의
- **save-point 스냅샷** (`save-points/session-NN/{start,complete}/`) — 학습자가 `cp -a` 로 작업 폴더에 받는 시작본/완성본

session-01 / 02 / 03 / 04 / 06 / 07 은 추가로 애플리케이션 코드 (apps/api · apps/web · apps/functions · apps/worker) 도 함께.

---

## 3. 현재 진행 상황 (이 문서 작성 시점)

### 완료된 작업

| 영역 | 상태 | 비고 |
|---|---|---|
| 워크샵 컨셉 · 구조 결정 | ✅ | 사내 문서 RAG · 6~7 세션 · 로컬 + 본인 Azure 구독 · Bicep 우선 |
| 8 개 세션 docs 골격 | ✅ | `docs/sessions/0[0-7]-*.md` 모두 작성됨 + 스타일 가이드 적용 완료 |
| `README.md` · `PREREQUISITES.md` · `CLAUDE.md` · `docs/_style.md` · `docs/architecture.md` · `docs/pitfalls/common.md` · `docs/cleanup.md` | ✅ | architecture 는 Mermaid 5 개 다이어그램 |
| save-point 인프라 (폴더 복사 방식) | ✅ | `.gitignore` 에 `workshop/` · `save-points/README.md` · 가이드 §3.7 |
| **session-00 Bicep** | ✅ | 8 개 모듈 + main.bicep + bicepparam (lint 통과). **save-points/session-00/{start,complete}/ 는 비어 있음** |
| **session-01 Bicep** | ✅ | 10 개 모듈 + main.bicep + bicepparam (lint 통과) |
| **session-01 apps/api FastAPI** | ✅ | DefaultAzureCredential + Cosmos vector search + OpenTelemetry 자동 계측 + /api/chat + /healthz |
| **session-01 apps/web Next.js** | ✅ | App Router + API Route 프록시 + 챗 UI |
| **save-points/session-01/{start,complete}/** | ✅ | 27 + 27 = 54 파일 |

### 진행 중 / 다음 단계

| 다음 작업 | 우선순위 | 비고 |
|---|---|---|
| **session-00 save-point 채우기** | 🔥 높음 | 첫 세션 학습자가 `cp -a save-points/session-00/start/. workshop/` 명령이 빈 폴더라 막힘. session-00 은 Bicep 만 다루므로 학습 포인트가 모듈 호출이 됨 |
| session-02 Bicep + apps/api/src/stores/pg_store.py + scripts/seed_both.py + save-points | 다음 | PostgreSQL Flex (Burstable B1ms) · `halfvec(3072)` HNSW |
| session-03 Bicep + apps/api/src/cache/{redis_client,semantic}.py + save-points | | Managed Redis Enterprise + RediSearch |
| session-04 Bicep + apps/functions 본체 + save-points | | Service Bus + Event Grid + Functions (Flex Consumption) |
| session-05 Bicep + apps/api/src/config/loader.py + save-points | | App Configuration + Feature flag |
| session-06 Bicep + apps/api/src/observability/spans.py + save-points | | 커스텀 OTel span · KQL Workbook · Alert |
| session-07 Bicep + apps/worker 본체 + K8s manifests + save-points | | Azure Kubernetes Service |
| **`docs/cleanup.md` 의 스타일 가이드 위반 정리** | 중간 | 가이드 §5 체크리스트 위반 다수 (`> ⚠️`, `~정리하세요`, `~없어요`, 약어 다수, 기울임체, `§7` 표기). 한 번에 일괄 정리 권장 |
| 최종 검증 — 실제 Azure 배포 한 번 끝까지 | 마지막 | session-00 → session-07 전체 실배포로 docs 의 명령어 검증 |

---

## 4. 빠른 컨텍스트 복원 — 새 컴퓨터에서 처음 5분에 할 일

### 4.1 환경 확인

```bash
# Python 3.12+
python --version
# Node 20+
node --version
# Docker
docker info > /dev/null && echo OK
# Azure CLI 2.65+ + Bicep
az --version | head -1
az bicep version
# uv (apps/api 의존성 관리)
uv --version
```

`uv` 가 없으면 `curl -LsSf https://astral.sh/uv/install.sh | sh` 또는 `brew install uv`.

### 4.2 저장소 클론 후

```bash
git clone <repo-url> azure-ai-200-certification-challenge
cd azure-ai-200-certification-challenge

# 마지막 commit 확인 — 본 문서가 마지막인지
git log --oneline -3

# 어떤 세션이 어디까지 진행됐는지 빠르게 확인
ls infra/modules/session-*/
ls infra/sessions/*/main.bicep 2>/dev/null
ls save-points/session-*/{start,complete}/
```

### 4.3 apps/api 의존성 설치 (한 번)

```bash
cd apps/api
uv sync   # .venv/ 생성 + 의존성 설치 + ruff 포함
cd ../..
```

### 4.4 apps/web 의존성 설치 (한 번)

```bash
cd apps/web
npm install
cd ../..
```

### 4.5 lint / 컴파일이 통과하는지 확인

```bash
# Bicep — 작성된 모든 .bicep 파일이 lint 통과해야 함
for f in $(find infra -name "*.bicep"); do
  az bicep build --file "$f" --stdout > /dev/null 2>&1 && echo "OK $f" || echo "FAIL $f"
done

# Python — apps/api
cd apps/api && uv run ruff check src/ && cd ../..

# TypeScript — apps/web
cd apps/web && npm run type-check && cd ../..
```

세 가지 모두 통과하면 환경 OK. **session-00 save-point 채우기부터 이어 진행** 합니다.

---

## 5. 작업 진행 시 반드시 따라야 하는 규칙

### 5.1 커밋 규칙

- 의미 단위로 분리 — 한 커밋에 여러 영역 변경 섞지 않음
- Conventional Commits 한국어 메시지 — `feat(infra)`, `feat(apps/api)`, `docs(session-NN)`, `refactor(infra)`, `chore(reset)` 등
- 한국어 본문 + `Co-Authored-By: Claude Opus 4.7 ...` 끝줄
- HEREDOC 으로 multi-line 메시지 전달 (escape 안전)
- 사용자가 명시적으로 commit 요청할 때만 — 그러나 본 워크샵은 maintainer 가 사용자 본인이므로 작업 단위마다 commit 함

```bash
git commit -m "$(cat <<'EOF'
feat(scope): 한국어 한 줄 제목

상세 설명 본문 (검증 결과, 함정 회피, 후속 작업 등).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### 5.2 작업 단위 커밋 분리 패턴

**Bicep 모듈 + 세션 엔트리 + save-point 한 세트** 를 만들 때 **3 개 커밋으로 분리**:

1. `feat(infra)`: session-NN Bicep 모듈 N 개 추가 (`infra/modules/session-NN/`)
2. `feat(infra)`: session-NN main.bicep + bicepparam — 모듈 조립
3. `feat(save-points/session-NN)`: start/complete 스냅샷

**애플리케이션 코드 + save-point 도 두 커밋**:

1. `feat(apps/api)` 또는 `feat(apps/web)`: main 트리 본체 작성
2. `feat(save-points/session-NN)`: 해당 코드의 start/complete 스냅샷 추가

### 5.3 placeholder 작성 규칙 (save-points/session-NN/start/)

[`docs/_style.md`](./docs/_style.md) §3.7 그대로:

- TODO 키워드 사용 안 함 — 한국어 anchor 주석이 곧 학습 단계의 이름
- 함수 본체는 `raise NotImplementedError("...")` 로 — syntax 통과, runtime 실패로 어디서 멈춰야 하는지 안내
- import 들은 그대로 두기 (학습자가 어떤 SDK 가 필요한지 미리 보도록)
- Bicep — 최소 컴파일 가능한 stub + 한국어 anchor 주석. `// Azure Container Registry 모듈 호출하기` 형태

### 5.4 사용자 식별 정보 보호

- `bicepparam` 기본값에 `userObjectId` · `userPrincipalName` · `devClientIpAddress` 같은 식별 정보 절대 박지 않기
- CLI 인자로만 전달:
  ```bash
  az deployment ... --parameters userObjectId=$(az ad signed-in-user show --query id -o tsv)
  ```

### 5.5 스타일 가이드 자가 점검

새 docs 파일 작성 후 — 다음 grep 패턴이 모두 빈 결과여야 함:

```bash
f=docs/sessions/NN-xxx.md   # 또는 다른 새 파일
grep -nE "(요\.|요$|하세요|에요|예요|네요|군요|는걸요)" $f | grep -vE "필요|중요|개요|줄임표|불요"  # ~요 종결
grep -nE '\bAOAI\b|\bAAD\b|\bRG\b|\bUAMI\b|\bACA\b|\bKV\b|MS Learn' $f                          # 약어 단독
grep -nE "박지|박으|박아|박혀" $f                                                                # 슬랭
grep -n "레포" $f                                                                                # 저장소 권장
grep -nE "T-[0-9]일|일주일 전|1주일 전|며칠 전|당일 아침|워크샵 당일|시작 직전|시작일 기준" $f  # 시간 단정
grep -nE '[[:<:]]S0[0-9][[:>:]]' $f                                                              # S0X 줄임말
grep -n "강사" $f                                                                                # 강사 등장
grep -nE '§[0-9]' $f                                                                             # § 표기
grep -nE '^> [⚠⏱💡🎯💰🔍]' $f                                                                  # emoji prefix 인용 블록
awk '{n=gsub(/\*/,"&"); if (n>0 && n%2!=0) print NR": "$0}' $f                                  # 기울임체
```

---

## 6. 자주 만나는 함정 (이미 정리됨, 참고용)

[`docs/pitfalls/common.md`](./docs/pitfalls/common.md) 에 22 개 함정이 분류되어 있습니다. 새 Bicep · 코드 작성 시 다음을 미리 확인:

- **Cosmos DB data plane RBAC ≠ control plane RBAC** — `Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments` 자원 별도 사용
- **`bicepparam` 사용자 정보 보호** — CLI override 강제
- **글로벌 unique 이름 충돌** — `uniqueString(resourceGroup().id)` 접미사 (ACR · Key Vault · Storage · Cosmos)
- **ARM Mac `--platform linux/amd64`** — Dockerfile · `docker build` 명령에 필수
- **PostgreSQL `vector(3072)` HNSW 한계** — `halfvec(3072)` + `halfvec_cosine_ops` 사용
- **RediSearch `evictionPolicy=NoEviction`** 필수
- **Cosmos change feed lease container** Bicep 으로 사전 생성 필수
- **Azure Functions Flex Consumption 신 스키마** — `functionAppConfig.runtime.name`
- **Storage `allowSharedKeyAccess=false`** + OAC + RBAC 필수
- **AKS DCR + DCRA 명시 선언** — `addonProfiles.omsagent` 단독 동작 안 함
- **Cosmos `query_items` 에 `partition_key` 명시** — cross-partition RU 폭주 회피

---

## 7. 막혔을 때 / 의문이 들 때

1. **스타일 / 어조 결정** — `docs/_style.md` 7 개 섹션 참고
2. **자원 라이프사이클** — `CLAUDE.md` §7 (보존 vs 정리 분류)
3. **세션 docs 와 코드 / Bicep 의 매핑** — `docs/architecture.md` §6 (세션별 자원 추가 매핑)
4. **save-point 사용법** — `save-points/README.md`
5. **함정 회피** — `docs/pitfalls/common.md`

작업 도중 새 사용자 피드백이 나오면:

1. **즉시 가이드 (`docs/_style.md`) 에 규칙 추가** — 같은 피드백 반복 방지
2. 기존 문서들에 동일 위반이 있는지 grep 으로 점검
3. 한 번에 일괄 정리 후 commit

---

## 8. 본 문서 자체의 처리

작업이 모두 완료되면 사용자가 "HISTORY.md 지워" 라고 명시적으로 지시할 때까지 **본 문서는 그대로 둡니다**. 학습자가 보는 README · docs 와 분리된 maintainer 전용 메타 문서로 동작합니다.

삭제 시:

```bash
git rm HISTORY.md
git commit -m "chore: 임시 인계 문서 HISTORY.md 제거 (워크샵 자료 작업 완료)"
```
