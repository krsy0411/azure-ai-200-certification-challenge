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
  const apiBaseUrl = process.env.API_BASE_URL;
  if (!apiBaseUrl) {
    return NextResponse.json(
      { error: "API_BASE_URL 환경변수가 설정되지 않았습니다." },
      { status: 500 },
    );
  }

  let body: ChatRequestBody;
  try {
    body = (await request.json()) as ChatRequestBody;
  } catch {
    return NextResponse.json({ error: "잘못된 JSON 본문입니다." }, { status: 400 });
  }

  if (typeof body.q !== "string" || body.q.trim().length === 0) {
    return NextResponse.json(
      { error: "`q` 필드는 비어있지 않은 문자열이어야 합니다." },
      { status: 400 },
    );
  }

  const sessionId = typeof body.session_id === "string" ? body.session_id : null;

  // ca-api 호출
  const upstream = await fetch(`${apiBaseUrl}/api/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ q: body.q, session_id: sessionId }),
    // 운영 환경에서는 timeout / 재시도 정책 추가 필요
    cache: "no-store",
  });

  const payload = await upstream.text();

  return new NextResponse(payload, {
    status: upstream.status,
    headers: { "Content-Type": "application/json" },
  });
}
