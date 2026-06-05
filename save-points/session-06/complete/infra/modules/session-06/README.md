# `infra/modules/session-06/` — session-06 Bicep 모듈 (후속 작성)

[session-06](../../../docs/sessions/06-observability.md) 의 Observability 심화 자원을 구성할 모듈.

예정 모듈:

- `monitor-workbook.bicep` — 커스텀 ARM JSON Workbook (P95 latency · cache hit rate · token cost)
- `monitor-action-group.bicep` — 이메일 수신 Action Group
- `monitor-metric-alert.bicep` — `requests/failed` > 5% Metric Alert

> [!NOTE]
> Application Insights · Log Analytics Workspace 는 session-00 에서 이미 만들어져 있어 본 세션에서 재생성하지 않습니다.

세션 엔트리 — `infra/sessions/06-observability/main.bicep` (후속 작성)
