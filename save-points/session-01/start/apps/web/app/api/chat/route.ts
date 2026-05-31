import { NextResponse } from "next/server";

/**
 * 브라우저 → /api/chat → ca-api 의 /api/chat 프록시.
 *
 * 환경변수 `API_BASE_URL` 은 Azure Container Apps 의 envVars 로 자동 주입
 * (Bicep `infra/sessions/01-rag-mvp/main.bicep` 의 ca-web 정의 참고).
 * 클라이언트 컴포넌트에서 직접 ca-api 를 호출하지 않고 본 route 로 우회하는 이유:
 *
 * 1. `API_BASE_URL` 같은 환경변수는 서버에서만 접근 가능 — 브라우저 노출 위험 없음
 * 2. 후속 세션에서 캐싱 · 인증 · 재시도 정책을 한 곳에서 일관 적용 가능
 * 3. CORS 우회 — 같은 origin 안에서 호출되므로 추가 헤더 설정 불필요
 */
export const dynamic = "force-dynamic"; // 매 요청 마다 실행 (캐싱 안 함)

interface ChatRequestBody {
  q?: unknown;
  session_id?: unknown;
}

export async function POST(request: Request) {
  // 1) process.env.API_BASE_URL 읽기. 없으면 NextResponse.json 으로 500 응답 반환하기

  // 2) request.json() 으로 본문 파싱하기. JSON parse 실패 시 400 반환하기

  // 3) body.q 검증 — string 이고 trim 후 길이 > 0 이어야 함. 아니면 400 반환

  // 4) session_id 는 선택 — string 이면 그대로, 아니면 null

  // 5) fetch(`${apiBaseUrl}/api/chat`) 로 ca-api 호출 — POST + JSON 본문, cache: 'no-store'

  // 6) upstream.text() 로 본문을 가져와 같은 상태코드로 NextResponse 반환
  // 힌트: new NextResponse(payload, { status: upstream.status, headers: { 'Content-Type': 'application/json' } })

  // 임시 — 학습자가 채울 때까지 501 로 응답
  return NextResponse.json(
    { error: "API Route 본문을 채워 넣으세요." },
    { status: 501 },
  );
}
