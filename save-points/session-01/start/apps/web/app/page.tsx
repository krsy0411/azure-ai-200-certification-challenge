"use client";

import { useState } from "react";

// FastAPI 백엔드 (ca-api) 의 ChatResponse 와 같은 구조.
interface Source {
  doc_id: string;
  title: string | null;
  score: number;
}

interface ChatResponse {
  answer: string;
  sources: Source[];
}

/**
 * 세션 식별자 — 한 브라우저 탭 동안 유지되는 임의 ID.
 * session-06 의 OpenTelemetry 커스텀 span 의 `user.session_id` attribute 로 사용된다.
 */
function generateSessionId(): string {
  return `web-${Math.random().toString(36).slice(2, 10)}`;
}

export default function ChatPage() {
  const [sessionId] = useState<string>(generateSessionId);
  const [question, setQuestion] = useState<string>("");
  const [response, setResponse] = useState<ChatResponse | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmed = question.trim();
    if (trimmed.length === 0) return;

    setLoading(true);
    setError(null);
    setResponse(null);

    try {
      // 브라우저 → Next.js API Route (/api/chat) → ca-api 의 /api/chat 으로 프록시.
      // 1) fetch 호출하기 — POST /api/chat 에 { q, session_id } JSON 본문 전송
      // 2) 응답 상태가 OK 가 아니면 본문을 읽어 throw
      // 3) 응답 JSON 을 ChatResponse 로 파싱하고 setResponse 호출
      throw new Error("fetch 호출 로직을 채워 넣으세요.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "알 수 없는 오류");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main>
      <h1>사내 문서 RAG 지식 비서</h1>
      <p className="subtitle">
        사내 문서 컬렉션을 근거로 답변하는 AI 어시스턴트. 세션 ID: {sessionId}
      </p>

      <form className="chat-form" onSubmit={handleSubmit}>
        <input
          type="text"
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder="예: 휴가 정책이 어떻게 되나요?"
          disabled={loading}
          aria-label="질문 입력"
        />
        <button type="submit" disabled={loading || question.trim().length === 0}>
          {loading ? "조회 중…" : "질문하기"}
        </button>
      </form>

      {loading && <p className="loading">RAG 파이프라인 호출 중입니다 (임베드 → 검색 → 답변 생성)…</p>}

      {error && <div className="error">⚠ {error}</div>}

      {response && (
        <article className="answer-card">
          <div className="answer-text">{response.answer}</div>

          {response.sources.length > 0 && (
            <div className="sources">
              <h3>근거 출처</h3>
              <ul>
                {response.sources.map((source) => (
                  <li key={`${source.doc_id}-${source.score}`}>
                    <span>{source.title ?? source.doc_id}</span>
                    <span className="score">{source.score.toFixed(3)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </article>
      )}
    </main>
  );
}
