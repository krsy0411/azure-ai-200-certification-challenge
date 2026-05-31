import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  title: "AI-200 Workshop — 사내 문서 RAG 지식 비서",
  description:
    "Azure Container Apps + Cosmos DB + Azure OpenAI 로 동작하는 사내 문서 RAG 챗 UI",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
