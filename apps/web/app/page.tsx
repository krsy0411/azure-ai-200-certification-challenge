'use client';

import { useState } from 'react';

type Message = { role: 'user' | 'bot'; text: string };

export default function Home() {
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = input.trim();
    if (!trimmed || loading) return;

    setInput('');
    setMessages((prev) => [...prev, { role: 'user', text: trimmed }]);
    setLoading(true);

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: trimmed }),
      });
      if (!res.ok) throw new Error(`API ${res.status}`);
      const data: { reply: string; model: string } = await res.json();
      setMessages((prev) => [...prev, { role: 'bot', text: data.reply }]);
    } catch {
      setMessages((prev) => [
        ...prev,
        { role: 'bot', text: '(오류: 백엔드 응답을 받지 못했습니다)' },
      ]);
    } finally {
      setLoading(false);
    }
  }

  return (
    <main
      style={{
        maxWidth: 720,
        margin: '2rem auto',
        padding: '1.5rem',
        background: '#fff',
        borderRadius: 12,
        boxShadow: '0 1px 3px rgba(0,0,0,0.08)',
      }}
    >
      <header style={{ marginBottom: '1rem' }}>
        <h1 style={{ fontSize: '1.4rem', marginBottom: '0.25rem' }}>
          AI-200 Challenge · Phase 1 스캐폴드
        </h1>
        <p style={{ color: '#666', fontSize: '0.9rem' }}>
          FastAPI 에코 응답을 반환합니다. Phase 4 이후 Azure OpenAI + Cosmos DB RAG로 확장됩니다.
        </p>
      </header>

      <section
        style={{
          border: '1px solid #e5e5e7',
          borderRadius: 8,
          padding: '1rem',
          minHeight: 280,
          marginBottom: '1rem',
          background: '#fafafa',
        }}
      >
        {messages.length === 0 && (
          <p style={{ color: '#999', fontSize: '0.9rem' }}>
            질문을 입력해 보세요. 예) &quot;안녕, 오늘의 날씨를 알려줘&quot;
          </p>
        )}
        {messages.map((m, i) => (
          <div
            key={i}
            style={{
              margin: '0.75rem 0',
              textAlign: m.role === 'user' ? 'right' : 'left',
            }}
          >
            <span
              style={{
                display: 'inline-block',
                padding: '0.5rem 0.75rem',
                borderRadius: 8,
                background: m.role === 'user' ? '#4f46e5' : '#e5e7eb',
                color: m.role === 'user' ? '#fff' : '#111',
                maxWidth: '80%',
                wordBreak: 'break-word',
              }}
            >
              {m.text}
            </span>
          </div>
        ))}
        {loading && <p style={{ color: '#666' }}>응답 중...</p>}
      </section>

      <form onSubmit={handleSubmit} style={{ display: 'flex', gap: '0.5rem' }}>
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="메시지 입력..."
          style={{
            flex: 1,
            padding: '0.6rem 0.8rem',
            borderRadius: 6,
            border: '1px solid #d1d5db',
            fontSize: '1rem',
          }}
        />
        <button
          type="submit"
          disabled={loading || !input.trim()}
          style={{
            padding: '0.6rem 1.2rem',
            borderRadius: 6,
            border: 'none',
            background: '#4f46e5',
            color: '#fff',
            fontWeight: 600,
            cursor: loading || !input.trim() ? 'not-allowed' : 'pointer',
            opacity: loading || !input.trim() ? 0.5 : 1,
          }}
        >
          전송
        </button>
      </form>
    </main>
  );
}
