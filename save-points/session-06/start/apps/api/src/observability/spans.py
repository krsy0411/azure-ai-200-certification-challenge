"""RAG 커스텀 OpenTelemetry span + 메트릭 (session-06).

자동 계측(FastAPI request span) 위에 비즈니스 의미 span 을 중첩한다. 새 루트 span 은
만들지 않는다 — RAG span 들은 자동 request span 의 자식으로 자동 중첩된다.

- span + attribute → dependencies 테이블, attribute 는 customDimensions
- OTEL 메트릭(Counter) → customMetrics 테이블의 value 컬럼 (KQL 집계 대상)

본 파일은 시작본 stub 이다. anchor 주석을 따라 본체를 채운다.
완성본은 save-points/session-06/complete/ 또는 docs/sessions/06-observability.md 참고.

> [!CAUTION]
> 민감 정보(질문 본문·답변)는 attribute 에 넣지 않는다 — Application Insights 에 영구 기록된다.
"""

from collections.abc import Iterator
from contextlib import contextmanager

from opentelemetry import metrics, trace
from opentelemetry.trace import Span

_tracer = trace.get_tracer("ai200.rag")
_meter = metrics.get_meter("ai200.rag")

# 힌트: meter.create_counter 로 customMetrics 에 발행할 counter 4개를 만든다 —
# "tokens.prompt", "tokens.completion", "cache.hit", "cache.total".
# (KQL 에서 sum(value) / sumif 로 집계하므로 이름이 정확히 일치해야 함)


@contextmanager
def rag_span(name: str) -> Iterator[Span]:
    # 힌트: with _tracer.start_as_current_span(name) as span: yield span
    raise NotImplementedError("rag_span 을 구현하세요.")


def record_tokens(prompt: int, completion: int) -> None:
    # 힌트: tokens.prompt / tokens.completion counter 에 add.
    raise NotImplementedError("record_tokens 를 구현하세요.")


def record_cache(hit: bool) -> None:
    # 힌트: cache.total 에 1 add, hit 면 cache.hit 에도 1 add.
    raise NotImplementedError("record_cache 를 구현하세요.")
