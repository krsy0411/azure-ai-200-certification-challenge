# session-06 — Observability 심화 — 커스텀 OpenTelemetry span · KQL Workbook · Log Search Alert

> **관련 Microsoft Learn 학습 경로**
>
> - [Observe and troubleshoot apps](https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/)

> [!IMPORTANT]
> **사전 준비 조건**
>
> - [session-00](./00-setup.md) ~ [session-05](./05-app-config-flags.md) 완료 — Application Insights · Log Analytics Workspace · Azure Container Apps · 시맨틱 캐시 · 피처 플래그 가 본인 구독에 존재
> - 시작본 코드를 작업 폴더로 받기 — [시작본 코드 받기](#시작본-코드-받기) 참고

---

## 0. 이 세션에서 경험하는 내용

- **한 문장 골** — "이 RAG 호출의 retrieval 단계가 얼마나 걸렸나 · 몇 토큰을 썼나 · 캐시 hit 였나" 같은 비즈니스 질문에 답하는 커스텀 OpenTelemetry span 을 심고, KQL Workbook 과 Log Search Alert 로 워크샵 전체를 한눈에 관찰
- **새로 프로비저닝되는 자원**
  - Action Group — 알림 수신자 (본인 이메일)
  - Log Search Alert 2개 (오류율 · p95 지연) — scheduledQueryRules
  - Application Insights Workbook — P95 latency · 분당 토큰 · 캐시 hit rate (Bicep 에 ARM JSON 임베드)
  - Application Insights · Log Analytics Workspace 는 [session-00](./00-setup.md) 에서 이미 존재 (재배포 없음)
- **이 세션의 학습 포인트**
  - 자동 계측 위에 커스텀 span 을 중첩 (새 루트 span 을 만들지 않고 자동 request span 의 자식으로)
  - **span attribute** (dependencies.customDimensions) 와 **OTEL 메트릭** (customMetrics.value) 의 용도 분리
  - AI 워크로드에 적합한 Log Search Alert (KQL 기반) 로 p95·오류율 경고
- **사용해볼 SDK / CLI**
  - `opentelemetry.trace` span + `opentelemetry.metrics` counter
  - KQL — `requests`, `dependencies`, `customMetrics` 테이블 쿼리
- **Portal 에서 확인할 지표 / 데이터**
  - Application Insights → Workbooks → 워크샵 워크북
  - Application Insights → Transaction search — 커스텀 span 트리
  - Azure Monitor → Alerts — 발화된 alert + 이메일

---

## 시작본 코드 받기

[session-05](./05-app-config-flags.md) 결과물이 들어 있는 `workshop/` 위에 본 세션 시작본을 덮습니다.

```bash
# Linux · macOS · WSL
cp -a save-points/session-06/start/. workshop/
```

```powershell
# Windows PowerShell
Copy-Item -Path save-points/session-06/start/* -Destination workshop -Recurse -Force
```

이후 본 세션의 모든 명령은 `workshop/` 안에서 실행한다고 가정합니다.

학습자가 채우는 파일은 두 개입니다 — `infra/sessions/06-observability/main.bicep` (모듈 조립), `apps/api/src/observability/spans.py` (커스텀 span + 메트릭). 모듈 3개와 `chain.py`·`main.py` 배선은 완성되어 제공됩니다.

---

## 1단계 · 프로비저닝

`workshop/infra/sessions/06-observability/main.bicep` 을 열고, 주석을 찾아 코드를 채웁니다. `workbookData` 변수(워크북 정의)는 이미 제공됩니다.

### 1.1 호출할 모듈 한눈에 보기

- `monitor-action-group.bicep` — 이메일 수신자 Action Group
- `monitor-scheduled-query-alert.bicep` — Log Search Alert (재사용 — 오류율·p95)
- `monitor-workbook.bicep` — 워크북 ARM JSON 임베드

### 1.2 Action Group + Log Search Alert 2개

`// -------- 1) ...` · `// -------- 2) ...` · `// -------- 3) ...` 주석 아래에 채웁니다.

```bicep
module actionGroup '../../modules/session-06/monitor-action-group.bicep' = {
  name: 'actionGroup'
  params: {
    name: actionGroupName
    shortName: 'ai200alert'
    email: alertEmail
  }
}

module alertErrorRate '../../modules/session-06/monitor-scheduled-query-alert.bicep' = {
  name: 'alert-errorRate'
  params: {
    name: 'alert-error-rate-${projectId}-${env}'
    location: location
    appInsightsId: appInsights.id
    query: 'requests | where success == false | summarize FailedCount = count()'
    metricMeasureColumn: 'FailedCount'
    timeAggregation: 'Total'
    operator: 'GreaterThan'
    threshold: 5
    severity: 2
    actionGroupId: actionGroup.outputs.id
  }
}

module alertP95 '../../modules/session-06/monitor-scheduled-query-alert.bicep' = {
  name: 'alert-p95'
  params: {
    name: 'alert-p95-latency-${projectId}-${env}'
    location: location
    appInsightsId: appInsights.id
    query: 'requests | summarize p95 = percentile(duration, 95)'
    metricMeasureColumn: 'p95'
    timeAggregation: 'Average'
    operator: 'GreaterThan'
    threshold: 3000
    severity: 3
    actionGroupId: actionGroup.outputs.id
  }
}
```

> [!TIP]
> **왜 metric alert 가 아니라 log search alert 인가** — p95 지연·토큰 비용·커스텀 차원 집계 같은 AI 워크로드 조건은 metric alert 로 표현할 수 없습니다. KQL 로 테이블을 집계하는 log search alert (`scheduledQueryRules`) 가 이런 조건에 적합합니다.

### 1.3 Workbook + 출력

`// -------- 4) ...` 와 `// -------- 출력` 주석 아래에 채웁니다.

```bicep
module workbook '../../modules/session-06/monitor-workbook.bicep' = {
  name: 'workbook'
  params: {
    name: guid(resourceGroup().id, 'session-06-workbook')
    location: location
    displayName: 'AI-200 Workshop 관측성'
    appInsightsId: appInsights.id
    serializedData: string(workbookData)
  }
}
```

```bicep
output actionGroupId string = actionGroup.outputs.id
output workbookId string = workbook.outputs.id
```

### 1.4 조립 검증 + 배포

```bash
az bicep build --file infra/sessions/06-observability/main.bicep --outfile /tmp/main.json && echo "BUILD OK"

ALERT_EMAIL=$(az ad signed-in-user show --query mail -o tsv)
az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/06-observability/main.bicep \
  --parameters infra/sessions/06-observability/main.bicepparam \
  --parameters alertEmail=$ALERT_EMAIL
```

> [!NOTE]
> Workbook + Action Group + Alert 합쳐 약 **1분** 으로 빠르게 완료됩니다. 배포 직후 본인 이메일에 Action Group 구독 확인 메일이 오면 안의 `Subscribe` 링크를 클릭해 활성화합니다.

### 1.5 배포 완료 확인

```bash
az monitor scheduled-query list -g rg-ai200ws-dev \
  --query "[].{name:name, enabled:enabled, severity:severity}" -o table

az resource list -g rg-ai200ws-dev --resource-type microsoft.insights/workbooks \
  --query "[].name" -o table
```

기대 — Log Search Alert 2개가 enabled, 워크북 1개 노출.

---

## 2단계 · 복붙으로 경험해보기

### 2.1 자동 계측 vs 커스텀 span

[session-01](./01-rag-mvp.md) 부터 켜둔 `azure-monitor-opentelemetry` 자동 계측은 HTTP 인입·외부 HTTP·DB 드라이버 호출과 timing 을 자동으로 잡습니다. 반면 **알 수 없는 것** 은 "retrieval 결과가 몇 개였나", "몇 토큰을 썼나", "캐시 hit 였나" 같은 비즈니스 의미입니다. 이 답에는 커스텀 span + attribute + 메트릭이 필요합니다.

> [!TIP]
> **시험 단골 패턴** — span 은 작업 단위(시작·종료 + 자식 span 트리), attribute 는 그 span 의 메타데이터 키/값. SpanKind 가 Application Insights 테이블 매핑을 결정합니다 — SERVER/CONSUMER 는 `requests`, CLIENT/INTERNAL/PRODUCER 는 `dependencies`.

### 2.2 커스텀 span + 메트릭 구현

`apps/api/src/observability/spans.py` 가 비어 있습니다. `chain.py`·`main.py` 배선은 이미 제공됩니다. 핵심은 **span attribute 와 OTEL 메트릭의 용도 분리** 입니다.

```python
_tracer = trace.get_tracer("ai200.rag")
_meter = metrics.get_meter("ai200.rag")

# Counter 는 인터벌별 합으로 customMetrics.value 에 내보내져 KQL sum(value) 로 집계된다.
_token_prompt = _meter.create_counter("tokens.prompt", unit="token", description="프롬프트 토큰")
_token_completion = _meter.create_counter(
    "tokens.completion", unit="token", description="컴플리션 토큰"
)
_cache_hit = _meter.create_counter("cache.hit", description="캐시 hit 횟수")
_cache_total = _meter.create_counter("cache.total", description="캐시 조회 총 횟수")


@contextmanager
def rag_span(name: str) -> Iterator[Span]:
    with _tracer.start_as_current_span(name) as span:
        yield span


def record_tokens(prompt: int, completion: int) -> None:
    _token_prompt.add(prompt)
    _token_completion.add(completion)


def record_cache(hit: bool) -> None:
    _cache_total.add(1)
    if hit:
        _cache_hit.add(1)
```

> [!CAUTION]
> **`set_attribute` 만으로는 customMetrics 가 비어 나옵니다** — attribute 는 dependencies.customDimensions 로만 갑니다. 분당 토큰·캐시 hit rate 같은 **집계 시계열** 은 반드시 OTEL 메트릭(Counter) 으로 발행해야 `customMetrics` 테이블에 `value` 가 채워집니다.

> [!NOTE]
> 배선(제공됨) — `chain.py` 가 `rag.retrieve`·`rag.generate` span 을 자동 request span 의 자식으로 열고(새 루트 span 을 만들지 않음), 토큰을 `set_attribute` + `record_tokens` 로, 캐시 결과를 `record_cache` 로 기록합니다. `cache.lookup` span 은 session-03 에서 이미 부여돼 있습니다.

### 2.3 카오스 엔드포인트 (제공됨)

`main.py` 에 알림 검증용 엔드포인트가 이미 추가돼 있습니다.

```python
@app.post("/api/_chaos")
async def chaos() -> None:
    """의도적으로 500 을 반환해 오류율·알림(session-06)을 검증한다."""
    raise HTTPException(status_code=500, detail="intentional chaos")
```

### 2.4 빌드 · 배포 · 트래픽 발생

```bash
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/api:s06 apps/api
docker push $ACR_NAME.azurecr.io/api:s06

az containerapp update --name ca-api-ai200ws-dev --resource-group rg-ai200ws-dev \
  --image $ACR_NAME.azurecr.io/api:s06
API_FQDN=$(az containerapp show -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)
```

정상 트래픽 20건 + 의도적 오류 10건을 발생시켜 span·메트릭·알림을 채웁니다.

```bash
for i in $(seq 1 20); do
  curl -sX POST "https://$API_FQDN/api/chat" -H "Content-Type: application/json" \
    -d "{\"q\":\"휴가 정책 질문 $i\",\"session_id\":\"demo-$i\"}" > /dev/null
done

# 오류율 알림 검증 — 카오스 10건
for i in $(seq 1 10); do
  curl -sX POST "https://$API_FQDN/api/_chaos" > /dev/null
done
```

5~10분 후 본인 이메일에 알림 메일 도착 여부를 확인합니다.

---

## 3단계 · Azure Portal UI 에서 확인

[Azure Portal](https://portal.azure.com) 에서 다음 경로를 직접 클릭합니다.

1. **Application Insights** → **Workbooks** → `AI-200 Workshop 관측성` — P95 latency · 분당 토큰 · 캐시 hit rate 가 한 화면에 시각화
2. **Application Insights** → **Transaction search** → 최근 `POST /api/chat` 한 건 → trace 트리에 `rag.retrieve`(`retrieval.count`) · `rag.generate`(`tokens.prompt`/`tokens.completion`) · `cache.lookup`(`cache_hit`) span 노출
3. **Application Insights** → **Failures** → `/api/_chaos` 호출의 stack trace
4. **Azure Monitor** → **Alerts** → 발화된 오류율 alert + 본인 이메일 메일
5. (권장) **Application Insights** → **Logs** 에서 다음 KQL 직접 실행

   ```kusto
   customMetrics
   | where name in ("tokens.prompt", "tokens.completion")
   | summarize tokens = sum(value) by name, bin(timestamp, 1m)
   | render timechart
   ```

   ```kusto
   customMetrics
   | where name in ("cache.hit", "cache.total")
   | summarize hits = sumif(value, name == "cache.hit"), total = sumif(value, name == "cache.total") by bin(timestamp, 5m)
   | extend hit_rate = round(100.0 * hits / total, 1)
   | render timechart
   ```

---

## Microsoft Learn 경로 커버리지 — 사용 / 생략

[Observe and troubleshoot apps](https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/) 학습 경로 2개 모듈을 본 세션에서 어떻게 다루는지 정리합니다.

| 모듈 | 단원 핵심 | 본 세션 |
|---|---|---|
| **1. OpenTelemetry 로 앱 계측** | SDK/Distro 추가 · span·trace 구성(get_tracer·start_as_current_span·set_attribute·SpanKind) · Azure Monitor 내보내기 · 분산 흐름 디버그 | **사용** — 자동 계측 위 커스텀 span + attribute + OTEL Counter (2.2). Collector 는 직접 내보내기로 대체(생략) |
| **2. 로그·메트릭 분석** | KQL · 오류/성능 탐색(p95) · 통합 문서(Workbook) · 경고(metric vs log search · action group) | **사용** — Workbook(ARM JSON 임베드) + Log Search Alert(오류율·p95) + Action Group(3단계). **생략** — 대시보드(Workbook 으로 대체) · 스마트 감지(자동·무료라 확인만) |

> [!NOTE]
> **본 레포 확장** — Workbook 의 `Microsoft.Insights/workbooks` Bicep 임베드는 학습 경로 범위 밖이지만, 본 워크샵의 Bicep 우선(IaC) 원칙에 따라 ARM JSON 을 Bicep 에 임베드합니다. 인증은 연결 문자열(ikey 포함) 인제스션이라 `Monitoring Metrics Publisher` 역할은 불필요합니다.

---

## 주의

> [!CAUTION]
> **`set_attribute` ≠ customMetrics** — attribute 는 dependencies.customDimensions, 집계 시계열은 OTEL 메트릭(Counter)→customMetrics.value. 토큰·캐시 KQL 이 빈 결과면 메트릭 발행이 빠진 것입니다 ([2.2](#22-커스텀-span--메트릭-구현) 참고).

> [!CAUTION]
> **커스텀 루트 span 을 만들지 않습니다** — FastAPI 자동 계측이 이미 SERVER(requests) span 을 만들므로, 또 다른 루트를 만들면 중복됩니다. RAG span 들은 `start_as_current_span` 으로 열어 자동 request span 의 자식으로 중첩합니다.

> [!CAUTION]
> **민감 정보 attribute 금지** — 질문 본문·답변을 attribute 에 넣으면 Application Insights 에 영구 기록됩니다. `user.session_id` 까지만 기록하고 본문은 넣지 않습니다.

> [!WARNING]
> **샘플링** — 기본 sampling 이 100% 가 아닐 수 있습니다. 모든 트레이스를 보려면 `OTEL_TRACES_SAMPLER=always_on` 을 설정합니다 (메트릭은 샘플링 영향 없음).

> [!IMPORTANT]
> 더 자세한 함정 모음은 [docs/pitfalls/common.md](../pitfalls/common.md) 를 참고합니다.

---

## 마무리

- **save-point** — 본 세션의 모든 변경은 `save-points/session-06/complete/` 와 일치합니다. 다음 세션으로 넘어가려면 `workshop/` 을 그대로 두고 `cp -a save-points/session-07/start/. workshop/` 를 실행합니다
- **자원 정리** — Workbook · Action Group · Log Search Alert 는 비용이 사실상 0 이라 정리하지 않습니다. Application Insights · Log Analytics Workspace 는 [session-00](./00-setup.md) 부터 사용 중이므로 워크샵 전체 정리 시점에 함께 정리합니다
- **다음 세션 미리보기** — [session-07](./07-aks.md) 에서는 같은 RAG 워커로드를 Azure Container Apps 대신 Azure Kubernetes Service 로 배포해보고, K8s 매니페스트 · `kubectl` · Container Insights 로 두 호스팅 모델의 트레이드오프를 직접 비교합니다

---

## 참고 자료

- Microsoft Learn — [Observe and troubleshoot apps](https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/)
- OpenTelemetry Python — [opentelemetry.io/docs/languages/python/](https://opentelemetry.io/docs/languages/python/)
- 본 저장소 — `infra/sessions/06-observability/main.bicep`, `apps/api/src/observability/spans.py`

---

👈 [session-05 — App Configuration 피처 플래그](./05-app-config-flags.md) | [session-07 — Azure Kubernetes Service 대안 배포](./07-aks.md) 👉
