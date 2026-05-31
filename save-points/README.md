# save-points — 세션별 시작본 · 완성본 스냅샷

본 폴더는 각 세션의 **시작 시점 코드** (`start/`) 와 **완성 시점 코드** (`complete/`) 를 함께 보관합니다. 학습자는 git 브랜치 전환 없이 `cp -a` 한 번으로 원하는 시점의 코드를 작업 폴더 `workshop/` 에 풀고, 그 위에서 채워 넣으며 학습합니다.

## 사용 방법

### 세션 시작 — 시작본을 작업 폴더로

```bash
# Linux · macOS · WSL
mkdir -p workshop && \
  cp -a save-points/session-01/start/. workshop/

# Windows PowerShell
New-Item -ItemType Directory -Force -Path workshop | Out-Null
Copy-Item -Path save-points/session-01/start/* -Destination workshop -Recurse -Force
```

이후 학습자는 `workshop/` 안의 한국어 anchor 주석 (예: `# Azure OpenAI 클라이언트 생성하기`) 을 따라 세션 docs 의 안내대로 코드를 채워 넣습니다.

### 막혔을 때 — 완성본으로 덮어쓰기

```bash
# 작업 폴더를 완성본으로 덮어쓴 뒤 직접 비교
cp -a save-points/session-01/complete/. workshop/
```

### 세션 종료 후 다음 세션으로 넘어갈 때

```bash
# 작업 폴더를 비우고 다음 세션의 시작본으로 다시 시작
rm -rf workshop && \
  mkdir -p workshop && \
  cp -a save-points/session-02/start/. workshop/
```

> [!NOTE]
> `workshop/` 폴더는 `.gitignore` 에 등록되어 있어 학습자가 안에서 무엇을 하든 본 저장소의 git 상태는 깨끗하게 유지됩니다.

## 폴더 구조 규칙

- 각 `save-points/session-NN/{start,complete}/` 는 **해당 세션이 실제로 변경하는 파일만** 담습니다. 이전 세션에서 만든 파일은 포함하지 않습니다
- 학습자가 세션을 순서대로 진행하면 `workshop/` 안에 이전 세션의 결과물이 누적됩니다. 어떤 세션부터 시작하더라도 정합성이 깨지지 않도록, 각 세션은 본인이 의존하는 이전 세션의 결과를 사전 준비 조건 (`> [!IMPORTANT]` 블록) 에서 명시합니다
- `start/` 안의 코드는 컴파일·import 가능한 상태로 두되, 핵심 로직은 한국어 anchor 주석으로 비워둡니다 (예: `# Cosmos DB 벡터 검색 호출하기`)
- `complete/` 는 본 저장소 main 트리 (`apps/`, `infra/`) 의 *해당 세션 시점 상태* 와 동일합니다

## maintainer 작업 흐름

새 세션의 save-point 를 만들 때:

1. main 트리 (`apps/`, `infra/`) 에 해당 세션의 정답 코드를 작성
2. `save-points/session-NN/complete/` 에 본 세션이 변경한 파일만 복사
3. `save-points/session-NN/start/` 는 `complete/` 에서 핵심 로직 부분을 한국어 anchor 주석으로 치환

## 본 저장소의 main 트리와 save-points 의 관계

```
main 트리 (apps/, infra/)        = 모든 세션이 완료된 최종 통합본 (fork 즉시 동작)
save-points/session-NN/complete/  = 세션 NN 시점의 변경 파일 (main 트리의 그 시점 스냅샷)
save-points/session-NN/start/     = complete 의 핵심 로직을 anchor 주석으로 치환한 학습 진입점
workshop/                         = 학습자의 작업 폴더 (.gitignore, cp -a 의 대상)
```
