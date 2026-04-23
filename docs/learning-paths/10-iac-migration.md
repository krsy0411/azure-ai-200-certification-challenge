# Phase 10 — 상위 조립 + GitHub Actions CI

**대응 경로**: (AI-200 범위 밖 · 포트폴리오 완성도 부스터)

Phase 1~9 각자의 `infra/phases/0N-*/main.bicep` 을 **`infra/main.bicep` 에서 한 번에 조립**하고, GitHub Actions 가 PR 에서 `what-if` 를, main 머지에서 실제 배포를 돌리는 CI/CD 로 완성한다.

> Phase 1~9 에서 이미 Bicep IaC 로 배포하기 때문에 "수동 → IaC 전환" 이라는 옛 스토리는 불필요. 대신 **여러 Phase 를 한 번에 파괴·재생성 가능**한 포트폴리오 쇼케이스로 가치가 이동했다.

## 범위

| 서브 페이즈 | 산출물 | 검증 |
|---|---|---|
| **10-A** `infra/main.bicep` | 각 Phase main.bicep 을 `module` 로 import. subscription 스코프. | `az bicep build` 경고 없음. `what-if` 결과가 모두 `Ignore` / `NoChange` (= 동등성) |
| **10-B** `.github/workflows/infra-ci.yml` | PR → `what-if` comment, main push → `az deployment sub create`. OIDC federated credential 사용 (시크릿 저장 없음) | PR 에 자동 댓글로 what-if 요약이 붙고, main 병합 시 Actions Run 이 성공 |
| **10-C** 운영 문서 | 상위 조립 다이어그램, what-if 결과 예시, 롤백 (= 이전 배포 이름으로 다시 돌리기) 전략 | 이 문서의 하단 섹션 |

---

## 10-A — `infra/main.bicep` 상위 조립

```bicep
// infra/main.bicep (개요)
targetScope = 'subscription'

@description('환경 라벨 (dev | prod)')
param environment string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200challenge'

@description('ACR 전역 유니크 접미사')
param acrSuffix string

param location string = 'koreacentral'

// Phase 1 — 컨테이너 호스팅 기초
module phase1 'phases/01-container-hosting/main.bicep' = {
  name: 'phase-01'
  params: {
    location: location
    environment: environment
    projectId: projectId
    acrSuffix: acrSuffix
  }
}

// Phase 2 — ACA  (Phase 2 에서 phase1 의 outputs 를 소비)
module phase2 'phases/02-container-apps/main.bicep' = {
  name: 'phase-02'
  params: {
    location: location
    environment: environment
    projectId: projectId
    resourceGroupName: phase1.outputs.resourceGroupName
    acrLoginServer: phase1.outputs.acrLoginServer
  }
  dependsOn: [ phase1 ]
}

// Phase 3 ~ 9 동일 패턴
```

```bicep
// infra/envs/dev.bicepparam
using '../main.bicep'

param environment = 'dev'
param projectId = 'ai200challenge'
param acrSuffix = '04'
param location = 'koreacentral'
```

배포:

```bash
az bicep build --file infra/main.bicep

az deployment sub what-if \
  --location koreacentral \
  --template-file infra/main.bicep \
  --parameters infra/envs/dev.bicepparam

az deployment sub create \
  --location koreacentral \
  --name top-$(date +%Y%m%d-%H%M%S) \
  --template-file infra/main.bicep \
  --parameters infra/envs/dev.bicepparam
```

---

## 10-B — GitHub Actions CI

### 사전 준비 (1회)

Azure OIDC federated credential 로 **시크릿 없이** 배포. Entra ID 앱 등록 → GitHub 저장소·환경에 federated credential 추가.

```bash
# App registration
APP_NAME="gh-actions-ai200challenge"
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID"

# Role: 구독 Contributor (데모용. 실무는 범위 축소)
az role assignment create \
  --assignee "$APP_ID" \
  --role Contributor \
  --scope "/subscriptions/<구독 ID>"

# Federated credential (main 브랜치)
cat > fic.json <<EOF
{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<owner>/<repo>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
az ad app federated-credential create --id "$APP_ID" --parameters fic.json
```

GitHub 저장소 **Settings → Secrets and variables → Actions → Variables** (Secrets 아님) 에 다음 3개 변수:

- `AZURE_CLIENT_ID` (= `$APP_ID`)
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

### 워크플로

```yaml
# .github/workflows/infra-ci.yml
name: infra-ci
on:
  pull_request:
    paths: [ 'infra/**' ]
  push:
    branches: [ main ]
    paths: [ 'infra/**' ]

permissions:
  id-token: write   # OIDC federated
  contents: read
  pull-requests: write

jobs:
  what-if:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      - name: Bicep build
        run: az bicep build --file infra/main.bicep
      - name: Deployment what-if
        id: whatif
        run: |
          az deployment sub what-if \
            --location koreacentral \
            --template-file infra/main.bicep \
            --parameters infra/envs/dev.bicepparam \
            --result-format FullResourcePayloads > whatif.txt || true
          {
            echo 'WHATIF<<EOF'
            cat whatif.txt
            echo EOF
          } >> "$GITHUB_OUTPUT"
      - name: Comment PR
        uses: marocchino/sticky-pull-request-comment@v2
        with:
          header: infra-whatif
          message: |
            ### `what-if` (dev)
            ```
            ${{ steps.whatif.outputs.WHATIF }}
            ```

  deploy:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      - name: Deploy
        run: |
          az deployment sub create \
            --location koreacentral \
            --name ci-$(date +%Y%m%d-%H%M%S) \
            --template-file infra/main.bicep \
            --parameters infra/envs/dev.bicepparam
```

---

## 10-C — 운영 메모

### 롤백 전략

Bicep 은 "이전 배포 이름" 으로 되돌리는 개념이 없다. 실제 롤백 = **이전 커밋으로 `main.bicep` 을 되돌려 다시 배포**.

```bash
git revert <bad-commit>    # 또는 체리픽으로 안전한 상태 복원
git push origin main
# → GitHub Actions 가 자동으로 이전 상태 재배포
```

### 부분 배포

한 Phase 만 돌리고 싶으면 `infra/main.bicep` 이 아니라 `infra/phases/0N-*/main.bicep` 을 직접 배포한다 (각 Phase 가 독립 `main.bicep` 인 이유). 그러면 Phase 10 CI 는 건너뜀.

### 파괴·재생성 데모

포트폴리오용으로 "전체를 한 번에 지우고 다시 만들 수 있음" 을 시연할 때:

```bash
# 1) 리소스 그룹 통째로 삭제 (비용 0 으로 복귀)
az group delete --name rg-ai200challenge-dev --yes --no-wait

# 2) 다시 배포
az deployment sub create \
  --location koreacentral \
  --name rebuild-$(date +%Y%m%d-%H%M%S) \
  --template-file infra/main.bicep \
  --parameters infra/envs/dev.bicepparam
```

> 단, **이미지는 ACR 과 함께 삭제됨**. 재배포 전 `docker push` 재실행 필요. CI 에 이미지 빌드 잡을 추가하면 완전 자동화 가능 (향후 확장).
