# SNN — &lt;세션 제목&gt;

> 학습 경로 매핑: [&lt;AI-200 공식 학습 경로 이름&gt;](&lt;링크&gt;)  
> 사전 조건: 세션 0..N-1 완료, `git checkout session-NN-start`

---

## 0. 이 세션에서 무엇을 경험하나

- **한 문장 골**: …
- **새로 프로비저닝되는 자원**:
  - `<리소스>` — 한 줄 설명
- **사용해볼 SDK/CLI**:
  - `<sdk>` — 한 줄
- **Portal 에서 확인할 지표/데이터**:
  - `<블레이드 → 탭>` — 무엇이 보여야 하나

---

## 1단계 · 프로비저닝

> ⏱ 자원이 만들어지는 동안 워크샵 docs 를 미리 읽으며 §2단계를 준비합니다. 다 만들어지면 §2단계로 넘어가세요.

### 1.1 Bicep 모듈 한눈에 보기

이 세션에서 새로 배포되는 모듈:

- `infra/modules/<module>.bicep` — 한 줄 설명
- …

### 1.2 배포 명령 (그대로 복사)

```bash
# 1) 변경사항 미리보기
az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/NN-xxx/main.bicep \
  --parameters infra/sessions/NN-xxx/main.bicepparam

# 2) 실제 배포
az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/NN-xxx/main.bicep \
  --parameters infra/sessions/NN-xxx/main.bicepparam
```

> 💡 본 세션 배포는 약 **N분** 소요됩니다. 진행되는 동안 §2.1 을 정독하세요.

### 1.3 배포 완료 확인

```bash
az <resource> show \
  --resource-group rg-ai200ws-dev \
  --name <이름> \
  --query "properties.provisioningState" -o tsv
# 기대 출력: Succeeded
```

---

## 2단계 · 복붙으로 경험해보기

> 🎯 목표: 방금 만든 자원을 **코드 한 번 호출** 해서 동작을 직접 체감.

### 2.1 왜 이 기술 스택을 쓰는가

- **트레이드오프 박스**: 한 두 줄로 핵심 트레이드오프 (예: Cosmos vs PG, `.env` vs KV+MI)
- **AI-200 시험 포인트**: 자주 묻는 패턴 1~2개

### 2.2 코드 복사·붙여넣기

> 아래 코드는 그대로 복사해 해당 파일에 붙여넣으세요. 동작 원리는 코드 다음의 **줄별 해설** 에서 다룹니다.

**파일**: `apps/api/src/<path>/<file>.py`

```python
# (복붙 가능한 완성된 스니펫 — 후속 구현 단계에서 채움)
```

**줄별 해설**:
- `1행`: …
- `5행`: …

### 2.3 실행해보기

```bash
# 로컬 또는 ACA 에 배포한 후
curl -X POST "https://<fqdn>/api/<endpoint>" \
  -H "Content-Type: application/json" \
  -d '{"q": "안녕"}' | jq
```

**기대 출력**:

```json
{ "answer": "...", "sources": [...] }
```

---

## 3단계 · Azure Portal UI 에서 확인

> 🔍 목표: 방금 발생한 트래픽·데이터가 클라우드에 실제로 남았는지 **눈으로** 확인.

학습자는 [Azure Portal](https://portal.azure.com) 의 다음 경로를 직접 클릭해 확인합니다:

1. **&lt;자원 블레이드&gt;** → **&lt;탭&gt;** → 무엇이 보여야 하는가
2. **&lt;다른 자원 블레이드&gt;** → **&lt;탭&gt;** → …
3. **&lt;선택&gt; KQL 쿼리** — 더 깊이 보고 싶을 때
   ```kusto
   <table> | where ...
   ```

---

## 주의 (Heads-up)

> 이 세션에서 실제로 막혔던 지점들. 시간 절약을 위해 사전에 읽어두세요.

- ⚠️ **함정 1**: 한 줄 요약 — 원인 — 회피법
- ⚠️ **함정 2**: …

---

## 마무리

- **save-point**: `git tag session-NN-complete`
- **다음 세션 미리보기**: 한 줄

---

## 참고 자료

- MS Learn: [&lt;학습 경로&gt;](&lt;링크&gt;)
- 본 레포: `infra/sessions/NN-xxx/main.bicep`, `apps/<path>/`
