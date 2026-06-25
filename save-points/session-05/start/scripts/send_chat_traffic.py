#!/usr/bin/env python
"""scripts/send_chat_traffic.py — RAG API 에 검증용 트래픽을 흘린다 (session-05·06).

session-05 의 시맨틱 캐시 피처 플래그(enable_semantic_cache) ON/OFF 효과나
session-06 의 커스텀 span·메트릭·오류율 알림을 Application Insights 에서 또렷하게
보려면 각 상태에서 충분한 요청이 쌓여야 한다. 본 스크립트는 두 가지 모드를 제공한다.

- 기본(chat) 모드: hot 질문(캐시 hit 유발)과 다양한 질문(retrieve+generate = miss
  유발) 을 섞어 /api/chat 에 N 건을 보낸다.
- --chaos N: /api/_chaos 에 N 건을 보내 의도적 500 을 발생시킨다(오류율 알림 검증).
  /api/_chaos 는 즉시 500 을 반환하므로, 간격 없이 몰아치면 일부 요청이 telemetry 에
  누락돼 알림 임계값(5분 내 5건)에 못 미친다 — 반드시 --interval 로 간격을 둔다.

플래그 토글 자체는 이 스크립트가 하지 않는다 — Azure Portal 의 App Configuration
> Feature manager 에서 직접 토글하며 화면을 확인하는 것이 워크샵의 일부다.

인증 불필요 — /api/chat · /api/_chaos 는 Container App 의 외부 ingress 공개 엔드포인트다.

실행 (apps/api 의 의존성 환경을 써서 OS·인증서 차이를 피한다):

    # 정상 트래픽 (span·메트릭)
    uv run --project apps/api python scripts/send_chat_traffic.py \
        --url https://ca-api-ai200ws-dev.<region>.azurecontainerapps.io --count 20
    # 오류율 알림 검증 (간격 필수)
    uv run --project apps/api python scripts/send_chat_traffic.py \
        --url https://ca-api-ai200ws-dev.<region>.azurecontainerapps.io --chaos 10 --interval 3

옵션:
    --url       API 기본 URL 또는 FQDN (필수). https:// 가 없으면 자동으로 붙인다.
    --count     보낼 chat 요청 수 (기본 15). --chaos 가 주어지면 무시된다.
    --chaos     0 보다 크면 /api/_chaos 로 그 수만큼 의도적 500 을 발생시킨다.
    --interval  요청 간 간격 초 (기본 2.0). chaos 는 누락 방지를 위해 3 이상 권장.
"""

from __future__ import annotations

import argparse
import sys
import time

try:
    import httpx
except ModuleNotFoundError:  # pragma: no cover - 안내용
    sys.exit(
        "httpx 를 찾을 수 없습니다. apps/api 의존성 환경으로 실행하세요:\n"
        "  uv run --project apps/api python scripts/send_chat_traffic.py --url <API_URL>"
    )

# hot 질문 1개(반복 호출 → 캐시 hit) + 다양한 질문(매번 다른 retrieve/generate → miss)
HOT = "휴가 규정 알려줘"
VARIED = [
    "복지 포인트는 어떻게 사용하나요",
    "출장 경비 정산 절차 알려줘",
    "재택근무는 어떻게 신청해",
    "사내 보안 정책이 궁금해",
    "경조사 휴가는 며칠이야",
    "급여 지급일은 언제인가요",
    "반차 사용 규정 알려줘",
    "교육비 지원 받을 수 있어?",
    "장비 신청은 어디서 해",
    "주차 등록 방법 알려줘",
]


def _normalize(url: str) -> str:
    url = url.strip().rstrip("/")
    if not url.startswith(("http://", "https://")):
        url = "https://" + url
    return url


def main() -> None:
    parser = argparse.ArgumentParser(description="RAG API 검증용 트래픽 생성기 (session-05)")
    parser.add_argument("--url", required=True, help="API 기본 URL 또는 FQDN")
    parser.add_argument("--count", type=int, default=15, help="보낼 chat 요청 수 (기본 15)")
    parser.add_argument("--chaos", type=int, default=0, help="0보다 크면 /api/_chaos 로 그 수만큼 의도적 500 발생")
    parser.add_argument("--interval", type=float, default=2.0, help="요청 간 간격 초 (기본 2.0)")
    args = parser.parse_args()

    base = _normalize(args.url)
    chaos_mode = args.chaos > 0
    total = args.chaos if chaos_mode else args.count
    endpoint = base + ("/api/_chaos" if chaos_mode else "/api/chat")
    print(f"대상: {endpoint}")
    mode = "chaos(의도적 500)" if chaos_mode else "chat"
    print(f"모드: {mode} · 요청 {total} 건 · 간격 {args.interval}s — Ctrl+C 로 중단 가능\n")

    ok = err = 0
    try:
        with httpx.Client(timeout=60.0) as client:
            for i in range(1, total + 1):
                t0 = time.perf_counter()
                try:
                    if chaos_mode:
                        r = client.post(endpoint)
                        dt = time.perf_counter() - t0
                        # chaos 는 500 이 정상(의도된 오류). 500 을 ok 로 집계한다.
                        if r.status_code == 500:
                            ok += 1
                            print(f"[{i:2d}/{total}] 500 (의도된 오류)  {dt:5.2f}s")
                        else:
                            err += 1
                            print(f"[{i:2d}/{total}] {r.status_code} (예상=500)  {dt:5.2f}s")
                    else:
                        # 짝수번째는 hot(캐시 hit 유발), 홀수번째는 다양한 질문(miss 유발)
                        q = HOT if i % 2 == 0 else VARIED[(i - 1) // 2 % len(VARIED)]
                        r = client.post(endpoint, json={"q": q})
                        dt = time.perf_counter() - t0
                        if r.status_code == 200:
                            ok += 1
                            print(f"[{i:2d}/{total}] 200  {dt:5.2f}s  q={q}")
                        else:
                            err += 1
                            print(f"[{i:2d}/{total}] {r.status_code}  {dt:5.2f}s  q={q}")
                except httpx.HTTPError as e:
                    err += 1
                    print(f"[{i:2d}/{total}] ERR  {type(e).__name__}: {e}")
                if i < total:
                    time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\n중단됨.")

    label = "의도된 500" if chaos_mode else "성공"
    print(f"\n완료 — {label} {ok} · 그 외 {err}")


if __name__ == "__main__":
    main()
