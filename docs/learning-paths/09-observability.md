# Phase 9 — Azure에서 앱 관찰 및 문제 해결

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/observe-troubleshoot-apps/ (2 모듈)

## 학습 경로 구성

1. **OpenTelemetry 로 앱 계측** — 분산 추적, 사용자 지정 span, Azure Monitor Application Insights로 내보내기.
2. **로그·메트릭으로 원격 분석 분석** — App Insights 로그에 대한 KQL 쿼리, 오류 패턴/성능 추세, 대시보드·통합 문서, 경고.

## 이 프로젝트에서의 적용

- FastAPI · Next.js(API Routes) · AKS 워커 · Azure Functions 네 곳 모두 OpenTelemetry 계측
- Application Insights 리소스 하나로 집중 → W3C trace context 로 end-to-end 추적
- **RAG 전용 커스텀 span**:
  - `rag.retrieve` (store, topK, score, hit) 속성
  - `rag.generate` (model, prompt_tokens, completion_tokens, latency_ms, cache_hit)
  - `rag.cache.lookup` (redis semantic cache 결과)
- KQL 워크북 2종:
  - **토큰·비용 대시보드**: 시간대별 토큰 사용량, 모델별 비용
  - **RAG 품질 대시보드**: 캐시 히트율, 평균 topK 점수, 에러율

## 커스텀 KQL 샘플

```kusto
// 시간당 RAG 요청 수와 p95 지연, 캐시 히트율
dependencies
| where name == "rag.generate"
| summarize
    requests = count(),
    p95_ms   = percentile(duration, 95),
    cache_hits = countif(customDimensions.cache_hit == "true")
  by bin(timestamp, 1h)
| extend cache_hit_rate = toreal(cache_hits) / requests
```

## 경고 규칙

| 이름 | 조건 | 중요도 |
|---|---|---|
| RAG 오류율 급증 | 5분간 5xx 비율 > 2% | Sev2 |
| 토큰 사용량 이상 | 10분간 총 토큰 > 100k | Sev3 |
| Azure OpenAI 429 | 1분간 429 > 10회 | Sev2 |
| Cosmos RU 초과 | 1분 RU 소비량 > 80% of provisioned | Sev3 |

## 체크리스트

- [ ] Application Insights 리소스 생성 + 연결 문자열을 Key Vault에
- [ ] FastAPI/Next.js/Functions/AKS 워커 OpenTelemetry 계측
- [ ] RAG 커스텀 span 3종 구현
- [ ] KQL 워크북 2개 게시
- [ ] 경고 규칙 4개 등록 + 테스트 트리거
