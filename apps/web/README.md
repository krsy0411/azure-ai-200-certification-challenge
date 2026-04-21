# apps/web — Next.js Frontend

Next.js 15 (App Router) · React 19 · TypeScript · npm.

## Phase 1 페이지

- `/` — 챗 UI. `/api/chat` 서버 라우트를 통해 FastAPI `/api/chat` 호출.
- `/api/chat` (Next.js Route Handler) — 서버에서 `API_BASE_URL` 환경변수로 FastAPI를 호출, 클라이언트는 백엔드 URL을 알 필요 없음.

## 로컬 실행

```bash
# 의존성
npm install

# 개발 서버 (백엔드가 localhost:8000에서 돌고 있어야 함)
npm run dev

# 브라우저에서 http://localhost:3000
```

환경변수는 `.env.example`을 `.env.local`로 복사해 조정.

## 컨테이너 빌드

```bash
# 레포 루트에서
docker build -t ai200challenge-web:0.1.0 apps/web
docker run --rm -p 3000:3000 -e API_BASE_URL=http://host.docker.internal:8000 ai200challenge-web:0.1.0
```

## 구조 (현재)

```
apps/web/
├── package.json
├── next.config.mjs        # output: 'standalone'
├── tsconfig.json
├── Dockerfile
├── .dockerignore
├── .env.example
├── app/
│   ├── layout.tsx
│   ├── page.tsx           # 챗 UI (client component)
│   ├── globals.css
│   └── api/
│       └── chat/
│           └── route.ts   # FastAPI 프록시 라우트
└── public/
```
