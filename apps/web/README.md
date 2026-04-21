# apps/web — Next.js Frontend

Next.js 14+ (App Router) + TypeScript. Phase 1에서 스캐폴딩 예정.

## 계획된 구조

```
apps/web/
├── package.json
├── Dockerfile                 # 멀티스테이지
├── next.config.mjs
├── app/
│   ├── layout.tsx
│   ├── page.tsx               # 챗 UI
│   ├── documents/page.tsx     # 업로드/목록
│   └── admin/page.tsx         # 모니터링 뷰
├── components/
│   ├── ChatWindow.tsx
│   └── DocumentUploader.tsx
└── lib/
    └── api.ts                 # FastAPI 호출 래퍼
```

## 로컬 실행 (Phase 1 이후)

```bash
pnpm install
pnpm dev
```
