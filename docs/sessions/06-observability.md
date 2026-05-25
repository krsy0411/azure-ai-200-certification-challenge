# session-06 — Observability 심화 — 커스텀 OpenTelemetry span · KQL Workbook · Metric Alert

> **관련 Microsoft Learn 학습 경로**
>
> - [Observe and troubleshoot apps](https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [session-00](./00-setup.md) ~ [session-05](./05-app-config-flags.md) 완료 — Application Insights · Log Analytics Workspace · Azure Container Apps · 비동기 인제스션 파이프라인 · 시맨틱 캐시 · 피처 플래그 가 본인 구독에 존재
> - `git checkout session-06-start` 명령어 수행

---

## 0. 이 세션에서 경험하는 내용

- **한 문장 골** — 자동 계측만으로는 알 수 없는 "이 RAG 호출의 retrieval 단계가 얼마나 걸렸나" 같은 비즈니스 의미 질문에 답할 수 있는 커스텀 OpenTelemetry span 을 심고, KQL Workbook 과 Metric Alert 로 워크샵 전체를 한눈에 관찰할 수 있게 만들기
- **새로 프로비저닝되는 자원**
  - Application Insights 커스텀 Workbook — P95 latency · cache hit rate · token cost 한 화면 시각화 (Bicep 에 ARM JSON 임베드)
  - Action Group — 알람 수신자 (본인 이메일)
  - Metric Alert — 오류율 > 5% 임계값
  - Application Insights · Log Analytics Workspace 는 [session-00](./00-setup.md) 에서 이미 존재 (재배포 없음)
- **사용해볼 SDK / CLI**
  - `opentelemetry.trace` — 커스텀 span 데코레이터 + attribute 부여
  - `azure-monitor-opentelemetry` — 자동 계측 + 커스텀 계측 결합
  - KQL — `requests`, `dependencies`, `customMetrics`, `customEvents` 테이블 쿼리
- **Portal 에서 확인할 지표 / 데이터**
  - Application Insights → Workbooks → (워크샵 워크북) — P95 latency · cache hit rate · token cost 한 화면
  - Application Insights → Transaction search — 커스텀 span 트리 노출
  - Application Insights → Failures — 의도적 오류의 stack trace
  - Azure Monitor → Alerts — 발화된 alert 인스턴스
  - 본인 이메일 수신함 — Action Group 알람 메일

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈 한눈에 보기

이 세션이 배포하는 Bicep 모듈 (`infra/sessions/06-observability/main.bicep`).

- `monitor-workbook.bicep` — 커스텀 워크북 ARM JSON 임베드 (P95 latency · cache hit rate · token cost)
- `monitor-action-group.bicep` — 본인 이메일을 수신자로 하는 Action Group
- `monitor-metric-alert.bicep` — `requests/failed` 메트릭 5% 초과 시 Action Group 발화

### 1.2 변경사항 미리보기

```bash
ALERT_EMAIL=$(az ad signed-in-user show --query mail -o tsv)

az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/06-observability/main.bicep \
  --parameters infra/sessions/06-observability/main.bicepparam \
  --parameters alertEmail=$ALERT_EMAIL
```

### 1.3 실제 배포

```bash
az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/06-observability/main.bicep \
  --parameters infra/sessions/06-observability/main.bicepparam \
  --parameters alertEmail=$ALERT_EMAIL
```

> [!NOTE]
> Workbook + Action Group + Metric Alert 합쳐 약 **1분** 으로 빠르게 완료됩니다. 배포 직후 본인 이메일 수신함에 Action Group 구독 확인 메일이 도착하므로 메일 안의 `Subscribe` 링크를 클릭해 활성화합니다.

### 1.4 배포 완료 확인

```bash
# Workbook 이 등록되었는지
az monitor app-insights workbook list \
  --resource-group rg-ai200ws-dev \
  --query "[].{name:name, displayName:displayName}" -o table

# Metric Alert 가 활성 상태인지
az monitor metrics alert list \
  --resource-group rg-ai200ws-dev \
  --query "[].{name:name, enabled:enabled, severity:severity}" -o table
```

---

## 2단계 · 복붙으로 경험해보기

### 2.1 자동 계측 vs 커스텀 span

[session-01](./01-rag-mvp.md) 부터 켜둔 `azure-monitor-opentelemetry` 자동 계측은 다음을 자동으로 잡습니다.

- HTTP 인입 (FastAPI 요청)
- 외부 HTTP 호출 (Azure OpenAI 등)
- DB 드라이버 호출 (Cosmos DB · PostgreSQL · Managed Redis)
- 각 의존성의 timing

반면 자동 계측이 **알 수 없는 것** 은 다음과 같습니다.

- "retrieval 결과가 몇 개였나?"
- "Azure OpenAI 호출에 몇 토큰을 썼나?"
- "이 호출이 캐시 hit 였나, miss 였나?"
- "사용자가 어떤 문서 셋을 컨텍스트로 받았나?"

이런 질문에 답하려면 **비즈니스 의미가 담긴 커스텀 span + attribute** 가 필요합니다.

> [!TIP]
> **시험 단골 패턴** — OpenTelemetry 의 `trace` · `span` · `attribute` 차이는 자주 출제됩니다. span 은 작업 단위 (시작 시각 + 종료 시각 + 자식 span 들의 트리 구조), attribute 는 그 span 의 메타데이터 키/값 쌍입니다.

### 2.2 코드 복사·붙여넣기

> [!NOTE]
> 아래 세 파일을 그대로 복사해 해당 경로에 붙여넣습니다. 동작 원리는 코드 다음의 줄별 해설에서 다룹니다.

**파일 1** — `apps/api/src/observability/spans.py`

```python
# (RAG 전용 커스텀 span 데코레이터.
#  핵심 구성:
#  - @rag_span("retrieve") 같은 데코레이터로 span 이름 = "rag.retrieve" 자동 설정
#  - retrieve 안에서 set_attribute("retrieval.count", len(results))
#  - generate 안에서 set_attribute("tokens.prompt", n_prompt), set_attribute("tokens.completion", n_completion)
#  - cache.lookup span 안에서 set_attribute("cache_hit", True 또는 False)
#  - record_metric 으로 customMetrics 테이블에도 별도 메트릭 발행 (cache_hit, tokens.prompt, tokens.completion)
#  - 민감 정보 (질문 본문) 는 attribute 에 기록하지 않음 — session_id 까지만 기록
#  실제 코드 본문은 후속 구현 단계에서 작성합니다.)
```

**파일 2** — `apps/api/src/main.py` 의 변경

```python
# import 추가
from .observability.spans import rag_span

@app.post("/api/chat")
async def chat(req: ChatReq):
    with rag_span("chat") as root_span:
        root_span.set_attribute("user.session_id", req.session_id)

        # 캐시 조회
        with rag_span("cache.lookup") as s:
            hit = await semantic_cache.lookup(req.q)
            s.set_attribute("cache_hit", hit is not None)
        if hit:
            return hit

        # 검색
        with rag_span("rag.retrieve") as s:
            chunks = await store.search(req.q, k=5)
            s.set_attribute("retrieval.count", len(chunks))

        # 생성
        with rag_span("rag.generate") as s:
            answer = await aoai.chat(...)
            s.set_attribute("tokens.prompt", answer.usage.prompt_tokens)
            s.set_attribute("tokens.completion", answer.usage.completion_tokens)

        return {"answer": answer.text, "sources": chunks}
```

**파일 3** — `apps/api/src/main.py` 에 카오스 엔드포인트 추가 (Metric Alert 검증용)

```python
@app.post("/api/_chaos")
async def chaos():
    """의도적으로 500 응답을 반환해 오류율 임계값을 넘기는지 검증."""
    raise HTTPException(status_code=500, detail="intentional chaos")
```

### 2.3 빌드 · 배포 · 트래픽 발생

```bash
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)

# 1) 재빌드 + 푸시
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/api:s06 apps/api
docker push $ACR_NAME.azurecr.io/api:s06

# 2) Azure Container Apps revision 업데이트
az containerapp update \
  --name ca-api-ai200ws-dev \
  --resource-group rg-ai200ws-dev \
  --image $ACR_NAME.azurecr.io/api:s06

# 3) FQDN 가져오기
API_FQDN=$(az containerapp show -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)
```

#### 정상 트래픽 발생

```bash
# 정상 요청 20건 — 다양한 질문으로
for i in {1..20}; do
  curl -sX POST "https://$API_FQDN/api/chat" \
    -H "Content-Type: application/json" \
    -d "{\"q\":\"휴가 정책 질문 $i\",\"session_id\":\"demo-$i\"}" > /dev/null
done
```

#### 의도적 오류 트래픽 발생 (Metric Alert 검증)

```bash
# 카오스 호출 10건 — 오류율 약 33% (10/30) 로 임계값 5% 초과
for i in {1..10}; do
  curl -sX POST "https://$API_FQDN/api/_chaos" > /dev/null
done
```

5~10분 후 본인 이메일 수신함에 Alert 메일 도착 여부를 확인합니다.

---

## 3단계 · Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **Application Insights** → **Workbooks** → 좌측 목록에 워크샵 워크북 노출. 클릭하면 다음 세 그래프가 한 화면에 시각화됩니다.
   - 분당 P95 latency
   - 분당 cache hit rate
   - 분당 token cost (prompt + completion 합산)
2. **Application Insights** → **Transaction search** → 최근 `POST /api/chat` 한 건을 클릭. trace 트리에 다음 span 들이 노출되어야 합니다.
   - `chat` (루트)
     - `cache.lookup` — attribute `cache_hit = false`
     - `rag.retrieve` — attribute `retrieval.count = 5`
     - `rag.generate` — attribute `tokens.prompt = 420`, `tokens.completion = 85` (값은 예시)
3. **Application Insights** → **Failures** → 의도적으로 발생시킨 `/api/_chaos` 호출들이 노출. 클릭하면 stack trace 확인 가능
4. **Azure Monitor** → **Alerts** → 발화된 alert 인스턴스. 클릭하면 임계값 · 실제 측정값 · 발화 시각 표시
5. **본인 이메일 수신함** — Action Group 이 전송한 alert 메일 (제목 예시 `[Activated] requests/failed > 5%`)
6. (권장) **Application Insights** → **Logs** 에서 다음 두 KQL 직접 실행

   #### 분당 토큰 사용량

   ```kusto
   customMetrics
   | where name in ("tokens.prompt", "tokens.completion")
   | summarize tokens=sum(value) by name, bin(timestamp, 1m)
   | render timechart
   ```

   #### 캐시 hit rate 추세

   ```kusto
   customMetrics
   | where name == "cache_hit"
   | summarize hits=countif(value==1), total=count() by bin(timestamp, 5m)
   | extend hit_rate = round(100.0 * hits / total, 1)
   | render timechart
   ```

---

## 주의

> [!WARNING]
> **Application Insights AUTH 모드 (`AuthenticationString=Authorization=AAD`)** — 이 모드를 사용하려면 User Assigned Managed Identity 에 `Monitoring Metrics Publisher` 역할 부여가 필수입니다. 누락 시 텔레메트리가 Application Insights 에 노출되지 않습니다. 본 워크샵은 학습 단순화를 위해 instrumentation key 폴백도 옵션으로 제공합니다.

> [!CAUTION]
> **민감 정보 attribute 금지** — 사용자 질문 본문이나 답변 내용을 span attribute 에 그대로 넣으면 Application Insights · Log Analytics 에 영구히 기록됩니다. 본 워크샵은 `user.session_id` 까지만 attribute 로 기록하고, 실제 질문 본문은 기록하지 않습니다.

> [!NOTE]
> **커스텀 메트릭 vs span attribute 구분** — 단순 카운터 (예: "캐시 hit 가 분당 몇 번?") 는 `record_metric` 으로 `customMetrics` 테이블에 기록합니다. 반면 트레이스 컨텍스트에 묶이는 메타 (예: "이 특정 호출의 retrieval count") 는 `set_attribute` 로 span 에 부여합니다. 두 개념을 혼동하면 KQL 쿼리가 다른 테이블을 보게 되어 결과가 비어 나옵니다.

> [!WARNING]
> **샘플링** — 기본 sampling rate 가 100% 가 아닐 수 있습니다. 워크샵 학습 단계에서는 모든 트레이스를 보기 위해 `OTEL_TRACES_SAMPLER=always_on` 환경변수로 명시하는 것을 권장합니다.

> [!IMPORTANT]
> 더 자세한 함정 모음은 [docs/pitfalls/common.md](../pitfalls/common.md) 의 [인증 · RBAC](../pitfalls/common.md#인증--rbac) 섹션을 참고합니다.

---

## 마무리

- **save-point** — `git tag session-06-complete`
- **자원 정리** — Workbook · Action Group · Metric Alert 는 자체 비용이 거의 없으므로 그대로 두는 것을 권장합니다. Application Insights · Log Analytics Workspace 는 [session-00](./00-setup.md) 부터 사용 중이므로 워크샵 전체 정리 시점에 함께 정리합니다
- **다음 세션 미리보기** — [session-07](./07-aks.md) 에서는 같은 RAG 워커로드를 Azure Container Apps 대신 Azure Kubernetes Service Job 으로 배포해보고, K8s 매니페스트 · `kubectl` · Container Insights 로 두 호스팅 모델의 트레이드오프를 직접 비교합니다

---

## 참고 자료

- Microsoft Learn — [Observe and troubleshoot apps](https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/)
- OpenTelemetry Python — [opentelemetry.io/docs/languages/python/](https://opentelemetry.io/docs/languages/python/)
- 본 저장소 — `infra/sessions/06-observability/main.bicep`, `apps/api/src/observability/spans.py`

---

👈 [session-05 — App Configuration 피처 플래그](./05-app-config-flags.md) | [session-07 — Azure Kubernetes Service 대안 배포](./07-aks.md) 👉
