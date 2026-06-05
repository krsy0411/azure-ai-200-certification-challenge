"""RAG 커스텀 OpenTelemetry span + 메트릭 (session-06).

자동 계측(FastAPI request span) 위에 비즈니스 의미 span 을 중첩한다. 새 루트 span 을
만들지 않는다 — FastAPI 자동 계측이 이미 SERVER(requests) span 을 만들고, 아래 span 들은
그 자식으로 자동 중첩된다.

두 경로의 용도 분리 (학습 경로 기준):
- **span + attribute** → dependencies 테이블, attribute 는 customDimensions 컬럼.
  이 호출 한 건의 메타 (retrieval.count, tokens.prompt 등).
- **OTEL 메트릭(Counter)** → customMetrics 테이블의 value 컬럼. 집계 시계열 (분당 토큰,
  캐시 hit rate). set_attribute 만으로는 customMetrics 가 채워지지 않으므로 메트릭을 병행 발행한다.

> [!CAUTION]
> 민감 정보(질문 본문·답변)는 attribute 에 넣지 않는다 — Application Insights 에 영구 기록된다.
"""

from collections.abc import Iterator
from contextlib import contextmanager

from opentelemetry import metrics, trace
from opentelemetry.trace import Span

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
    """RAG 단계 span 을 자동 request span 의 자식으로 연다."""
    with _tracer.start_as_current_span(name) as span:
        yield span


def record_tokens(prompt: int, completion: int) -> None:
    """토큰 사용량을 customMetrics 로 발행 (집계 시계열)."""
    _token_prompt.add(prompt)
    _token_completion.add(completion)


def record_cache(hit: bool) -> None:
    """캐시 조회 결과를 customMetrics 로 발행 (hit rate 계산용)."""
    _cache_total.add(1)
    if hit:
        _cache_hit.add(1)
