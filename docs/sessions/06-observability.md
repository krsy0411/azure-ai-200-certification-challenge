# session-06 — Observability 심화 (커스텀 span · KQL · Alert)

> 학습 경로 매핑: [Observe and troubleshoot apps](https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/)  
> 사전 조건: session-00~session-05 완료, `git checkout session-06-start`

---

## 0. 이 세션에서 무엇을 경험하나

- **한 문장 골**: 자동 계측만으론 알 수 없는 *"이 RAG 호출의 retrieval 단계가 얼마나 걸렸나"* 같은 질문에 답할 수 있는 커스텀 span 을 심고, KQL Workbook 과 알람으로 워크샵 전체를 한눈에 볼 수 있게 만든다.
- **새로 프로비저닝되는 자원**:
  - Application Insights 커스텀 Workbook (Bicep으로 ARM JSON 포함)
  - Action Group (이메일 수신)
  - Metric Alert (오류율 > 5%)
  - *Log Analytics, App Insights 는 session-00 에서 이미 존재*
- **사용해볼 SDK/CLI**:
  - `opentelemetry.trace` 커스텀 span + attribute
  - `azure-monitor-opentelemetry` 자동 + 수동 결합
  - KQL: `requests`, `dependencies`, `customMetrics`
- **Portal 에서 확인할 지표/데이터**:
  - App Insights → Workbooks → (워크샵 워크북)
  - App Insights → Transaction search → 커스텀 span 노출
  - App Insights → Failures → 의도적 500 의 stack
  - Monitor → Alerts → 발화된 alert 인스턴스

---

## 1단계 · 프로비저닝

### 1.1 Bicep 모듈

- `monitor-workbook.bicep` — 커스텀 워크북 JSON (P95 latency · cache hit rate · token cost)
- `monitor-action-group.bicep` — 본인 이메일 수신자
- `monitor-metric-alert.bicep` — `requests/failed` > 5% 임계

### 1.2 배포

```bash
az deployment group what-if \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/06-observability/main.bicep \
  --parameters infra/sessions/06-observability/main.bicepparam \
  --parameters alertEmail=$(az ad signed-in-user show --query mail -o tsv)

az deployment group create \
  --resource-group rg-ai200ws-dev \
  --template-file infra/sessions/06-observability/main.bicep \
  --parameters infra/sessions/06-observability/main.bicepparam \
  --parameters alertEmail=$(az ad signed-in-user show --query mail -o tsv)
```

> ⏱ Workbook + alert 합쳐 약 **1분**. Action group 이메일 확인 요청을 받게 됩니다 (subscribe 클릭).

---

## 2단계 · 복붙으로 경험해보기

### 2.1 자동 계측 vs 커스텀 span 트레이드오프

**자동 계측 (session-01 부터 켜져 있음)** 이 잡아주는 것:
- HTTP 인입 / outbound HTTP
- DB 드라이버 호출 (Cosmos · PG · Redis)
- 의존성 timing

**자동 계측이 *모르는* 것**:
- "retrieval 결과가 몇 개였나?"
- "AOAI 가 몇 토큰 썼나?"
- "이 호출이 캐시 hit 였나, miss 였나?"
- "사용자가 어떤 문서 셋으로 쿼리했나?"

→ **비즈니스 의미가 담긴 커스텀 span 과 속성 (attribute)** 이 필요.

> 🎯 **AI-200 시험 포인트**: "OpenTelemetry 의 trace · span · attribute 차이는?" — span 은 작업 단위, attribute 는 그 span 의 메타데이터. 자주 묻습니다.

### 2.2 코드 복사·붙여넣기

**파일 1**: `apps/api/src/observability/spans.py`

```python
# (RAG 전용 커스텀 span 데코레이터:
#  - @rag_span("retrieve") → span name = "rag.retrieve", attributes 자동 주입
#  - retrieve 안에서 set_attribute("retrieval.count", len(results))
#  - generate 안에서 set_attribute("tokens.prompt", ...), set_attribute("tokens.completion", ...)
#  - cache.lookup span 에 set_attribute("cache_hit", true/false)
#  실제 코드는 후속 구현.)
```

**파일 2**: `apps/api/src/main.py` 변경

```python
# import 추가
from .observability.spans import rag_span

@app.post("/api/chat")
async def chat(req: ChatReq):
    with rag_span("chat") as root_span:
        root_span.set_attribute("user.session_id", req.session_id)
        # 캐시 lookup
        with rag_span("cache.lookup") as s:
            hit = await semantic_cache.lookup(req.q)
            s.set_attribute("cache_hit", hit is not None)
        if hit:
            return hit
        # retrieve
        with rag_span("rag.retrieve") as s:
            chunks = await store.search(req.q, k=5)
            s.set_attribute("retrieval.count", len(chunks))
        # generate
        with rag_span("rag.generate") as s:
            answer = await aoai.chat(...)
            s.set_attribute("tokens.prompt", answer.usage.prompt_tokens)
            s.set_attribute("tokens.completion", answer.usage.completion_tokens)
        return {"answer": answer.text, "sources": chunks}
```

**파일 3**: `apps/api/src/main.py` 의 chaos 엔드포인트 (의도적 500 — alert 발화 데모용)

```python
@app.post("/api/_chaos")
async def chaos():
    raise HTTPException(status_code=500, detail="intentional chaos")
```

### 2.3 빌드·배포·트래픽 발생

```bash
ACR_NAME=$(az acr list -g rg-ai200ws-dev --query "[0].name" -o tsv)
docker build --platform linux/amd64 -t $ACR_NAME.azurecr.io/api:s06 apps/api
docker push $ACR_NAME.azurecr.io/api:s06
az containerapp update -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --image $ACR_NAME.azurecr.io/api:s06

API_FQDN=$(az containerapp show -n ca-api-ai200ws-dev -g rg-ai200ws-dev \
  --query "properties.configuration.ingress.fqdn" -o tsv)

# 정상 트래픽 20회
for i in {1..20}; do
  curl -sX POST "https://$API_FQDN/api/chat" -H "Content-Type: application/json" \
    -d "{\"q\":\"휴가 정책 $i\"}" > /dev/null
done

# 의도적 chaos 10회 (오류율 33% — alert 임계 5% 초과)
for i in {1..10}; do
  curl -sX POST "https://$API_FQDN/api/_chaos" > /dev/null
done

# 5~10분 후 이메일 도착 확인
```

---

## 3단계 · Azure Portal UI 에서 확인

1. **Application Insights** → **Workbooks** → 좌측에 워크샵 워크북 노출. 클릭하면 P95 latency · cache hit rate · token cost (prompt + completion) 한 화면
2. **App Insights** → **Transaction search** → 최근 `POST /api/chat` 한 건 클릭 → trace 트리에 다음 span 들 노출:
   - `chat`
     - `cache.lookup` (`cache_hit=false`)
     - `rag.retrieve` (`retrieval.count=5`)
     - `rag.generate` (`tokens.prompt=420`, `tokens.completion=85`)
3. **App Insights** → **Failures** → `_chaos` 호출들이 노출, stack trace 확인
4. **Monitor** → **Alerts** → 발화된 인스턴스. 클릭하면 임계·실제 값·트리거 시각
5. **이메일 수신함** — Action Group 이메일 (alert subject: `[Activated] requests/failed > 5%`)
6. **(권장) KQL 직접 작성**:
   ```kusto
   // 분당 토큰 사용량
   customMetrics
   | where name in ("tokens.prompt", "tokens.completion")
   | summarize tokens=sum(value) by name, bin(timestamp, 1m)
   | render timechart
   ```
   ```kusto
   // 캐시 hit rate
   customMetrics
   | where name == "cache_hit"
   | summarize hits=countif(value==1), total=count() by bin(timestamp, 5m)
   | extend hit_rate = round(100.0 * hits / total, 1)
   | render timechart
   ```

---

## 주의 (Heads-up)

- ⚠️ **App Insights AUTH 모드 (`AuthenticationString=Authorization=AAD`)** 사용 시 UAMI 에 `Monitoring Metrics Publisher` 역할 필수. 본 워크샵은 instrumentation key 폴백도 옵션
- ⚠️ **커스텀 메트릭 vs span attribute**: 단순 카운터는 `record_metric`, 트레이스 컨텍스트에 묶이는 메타는 `set_attribute`. 둘을 혼동하면 KQL 쿼리 테이블이 안 맞음
- ⚠️ **샘플링** — 기본 sampling rate 가 100% 가 아닐 수 있음. 워크샵에선 `OTEL_TRACES_SAMPLER=always_on` 으로 명시
- ⚠️ **민감 정보 attribute 금지** — 사용자 질문 본문을 attribute 에 박으면 App Insights 로그에 영구 남음. 본 워크샵은 session_id 까지만

---

## 마무리

- **save-point**: `git tag session-06-complete`
- **다음 세션 미리보기**: session-07 — ACA 하나로 충분한 워크로드도 있지만, AKS 가 필요한 경우는? embedding 재처리 워커를 K8s Job 으로

---

## 참고 자료

- Microsoft Learn — [Observe and troubleshoot apps](https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/)
- OpenTelemetry Python — [opentelemetry.io/docs/languages/python/](https://opentelemetry.io/docs/languages/python/)
- 본 저장소 — `infra/sessions/06-observability/main.bicep`, `apps/api/src/observability/spans.py`

---

👈 [session-05 — App Configuration 피처 플래그](./05-app-config-flags.md) | [session-07 — Azure Kubernetes Service 대안 배포](./07-aks.md) 👉
